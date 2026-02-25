import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '../config/env.dart';
import 'dart:async';

class VoiceCommandContext {
  final String screenName;
  final Function() onCreateRoom;
  final Function(String code) onJoinRoom;
  final Function() onJoinCall;

  VoiceCommandContext({
    required this.screenName,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onJoinCall,
  });
}

class GeminiResponse {
  final String text;
  final Uint8List? audioBytes;
  GeminiResponse(this.text, this.audioBytes);
}

class VoiceAssistant {
  static final VoiceAssistant _instance = VoiceAssistant._internal();
  factory VoiceAssistant() => _instance;
  VoiceAssistant._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  final List<Map<String, dynamic>> _chatHistory = [];

  bool _isInit = false;
  bool isBlindModeActive = false; 

  final ValueNotifier<String> currentSpeechContent = ValueNotifier<String>('');
  VoiceCommandContext? currentContext;

  Uint8List? _welcomeAudioBytes;

  Future<void> init() async {
    if (_isInit) return;
    try {
       await _speech.initialize(
         onStatus: (status) {
           if (status == 'notListening' && isBlindModeActive) {
             _listenForWakeWord();
           }
         },
         onError: (error) => debugPrint('STT Error: $error'),
       );
       _chatHistory.clear();
       _isInit = true;
    } catch (e) {
      debugPrint("Voice init error: $e");
    }
  }

  Future<GeminiResponse> _sendToGemini(String prompt, {bool requestAudio = true, bool addToHistory = true}) async {
      if (Env.geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE') return GeminiResponse("Ключ API не настроен в env.dart", null);

      final modelName = requestAudio ? 'gemini-2.5-flash-native-audio-preview-12-2025' : 'gemini-2.5-flash-lite';
      final apiVersion = 'v1beta';
      final url = Uri.parse('https://generativelanguage.googleapis.com/$apiVersion/models/$modelName:generateContent?key=${Env.geminiApiKey}');
      
      final userMessage = {"role": "user", "parts": [{"text": prompt}]};
      if (addToHistory) {
         _chatHistory.add(userMessage);
         if (_chatHistory.length > 20) _chatHistory.removeRange(0, _chatHistory.length - 20);
      }

      final systemPrompt = '''
Ты голосовой помощник для слепых, тебя зовут "Данил" (или "Даня"). Работай в приложении видеозвонков. Твой голос и интонация должны быть дружелюбными и помогающими.
Текущий экран: ${currentContext?.screenName ?? 'Неизвестно'}.

Если экран "MainScreen":
- Можно "создать комнату". Ответь ТОЛЬКО: "[ACTION:CREATE_ROOM]"
- Можно "присоединиться" к комнате (нужен код цифрами). Ответь ТОЛЬКО: "[ACTION:JOIN_ROOM|кодизцифр]".

Если экран "RoomScreen":
- Можно "войти в звонок" (он же видеозвонок, встреча). Ответь ТОЛЬКО: "[ACTION:JOIN_CALL]"

Если команда непонятна, или это просто вопрос - отвечай вежливо и коротко как помощник Данил.
Если ты распознал команду (создать, вступить) - ВЕРНИ ИСКЛЮЧИТЕЛЬНО ТЕГ [ACTION:...], и больше никаких слов, я сам всё озвучу через UI.
''';

      Map<String, dynamic> requestBody = {
         "systemInstruction": {
            "parts": [{"text": systemPrompt}]
         },
         "contents": addToHistory ? _chatHistory : [userMessage],
      };

      // Добавляем generationConfig только если нужно аудио. Текстовая модель не поддерживает этот параметр в таком виде.
      if (requestAudio) {
          requestBody["generationConfig"] = {
             "responseModalities": ["AUDIO"]
          };
      }

      try {
         final response = await http.post(
             url,
             headers: {'Content-Type': 'application/json'},
             body: jsonEncode(requestBody)
         );

         if (response.statusCode == 200) {
             final json = jsonDecode(response.body);
             final candidates = json['candidates'] as List?;
             if (candidates == null || candidates.isEmpty) return GeminiResponse("Пустой ответ", null);

             final parts = candidates[0]['content']['parts'] as List;
             
             String rawText = "";
             String base64Audio = "";

             for (var part in parts) {
                if (part.containsKey('text')) {
                    rawText += part['text'];
                } else if (part.containsKey('inlineData') && part['inlineData']['mimeType'].toString().startsWith('audio/')) {
                    base64Audio = part['inlineData']['data'];
                }
             }

             if (addToHistory) {
                 _chatHistory.add({
                    "role": "model",
                    "parts": [{"text": rawText}]
                 });
             }

             Uint8List? audioBytes;
             if (base64Audio.isNotEmpty) {
                 audioBytes = base64Decode(base64Audio);
             }

             return GeminiResponse(rawText, audioBytes);
         } else {
             final b = response.body;
             return GeminiResponse("Ошибка API: ${response.statusCode}. $b", null);
         }
      } catch (e) {
          return GeminiResponse("Ошибка: $e", null);
      }
  }

  Future<void> _waitForAudioCompletion() async {
     if (_audioPlayer.state != PlayerState.playing) return;
     final completer = Completer<void>();
     final sub = _audioPlayer.onPlayerComplete.listen((_) {
         if (!completer.isCompleted) completer.complete();
     });
     
     // safeguard timeout just in case it bugs out
     Future.delayed(const Duration(seconds: 15), () {
        if (!completer.isCompleted) completer.complete();
     });
     
     await completer.future;
     sub.cancel();
  }

  // Plays audio bytes and WAITS for completion
  Future<void> _playAudioAndWait(Uint8List bytes) async {
     Uint8List audioToPlay = bytes;
     
     // Нативный PCM от Gemini не содержит WAV-заголовка, поэтому добавим его налету
     if (bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') {
         final channels = 1;
         final sampleRate = 24000;
         final byteRate = sampleRate * 2;
         
         final buffer = ByteData(44 + bytes.length);
         buffer.setUint8(0, 0x52); buffer.setUint8(1, 0x49); buffer.setUint8(2, 0x46); buffer.setUint8(3, 0x46); // RIFF
         buffer.setUint32(4, 36 + bytes.length, Endian.little);
         buffer.setUint8(8, 0x57); buffer.setUint8(9, 0x41); buffer.setUint8(10, 0x56); buffer.setUint8(11, 0x45); // WAVE
         buffer.setUint8(12, 0x66); buffer.setUint8(13, 0x6D); buffer.setUint8(14, 0x74); buffer.setUint8(15, 0x20); // fmt 
         buffer.setUint32(16, 16, Endian.little);
         buffer.setUint16(20, 1, Endian.little);      // Format: PCM
         buffer.setUint16(22, channels, Endian.little);
         buffer.setUint32(24, sampleRate, Endian.little);
         buffer.setUint32(28, byteRate, Endian.little);
         buffer.setUint16(32, 2, Endian.little);      // Block align
         buffer.setUint16(34, 16, Endian.little);     // Bits per sample
         buffer.setUint8(36, 0x64); buffer.setUint8(37, 0x61); buffer.setUint8(38, 0x74); buffer.setUint8(39, 0x61); // data
         buffer.setUint32(40, bytes.length, Endian.little);
         
         final outList = buffer.buffer.asUint8List();
         outList.setAll(44, bytes);
         audioToPlay = outList;
     }

     await _audioPlayer.play(BytesSource(audioToPlay));
     await _waitForAudioCompletion();
  }

  Future<void> speak(String text) async {
      final res = await _sendToGemini("Просто быстро произнеси это вслух, без лишних слов: $text", requestAudio: true, addToHistory: false);
      if (res.audioBytes != null) {
          await _playAudioAndWait(res.audioBytes!);
      }
  }

  Future<void> determineBlindness(String answer, Function(bool) onResult) async {
      final prompt = '''
Пользователю задали вопрос: "Можете ли вы видеть?". Он ответил: "$answer". Выведи только слово "BLIND" если он нуждается в помощи или у него проблемы со зрением, иначе выведи "NOT_BLIND". Никаких других символов.
''';      
      final res = await _sendToGemini(prompt, requestAudio: false, addToHistory: false);
      bool blind = res.text.contains("BLIND") && !res.text.contains("NOT_BLIND");
      onResult(blind);
  }

  Future<String> generateWelcomeSpeech() async {
     final response = await _sendToGemini(
        "Представься. Ты - голосовой помощник Данил. Поздоровайся и коротко спроси пользователя, видит ли он экран, чтобы ты адаптировал интерфейс.", 
        requestAudio: false, 
        addToHistory: true
     );
     final textResp = response.text.replaceAll(RegExp(r'\*\*|\*|#|-|_'), '').trim();
     
     if (textResp.isNotEmpty) {
        final audioRes = await _sendToGemini(
           "Просто быстро произнеси это вслух, без лишних слов: $textResp", 
           requestAudio: true, 
           addToHistory: false
        );
        if (audioRes.audioBytes != null) {
           _welcomeAudioBytes = audioRes.audioBytes;
        }
     }
     return textResp;
  }

  // Should be called by UI when it's ready to emit audio
  Future<void> speakWelcomeAudio() async {
      if (_welcomeAudioBytes != null) {
          await _playAudioAndWait(_welcomeAudioBytes!);
      }
  }

  Future<void> activateBlindMode() async {
    isBlindModeActive = true;
    final res = await _sendToGemini("Объясни пользователю, что ты помощник Даня, и теперь активирован режим для незрячих. Скажи ему: чтобы задать вопрос, пусть позовет тебя по имени Данил или Даня.", requestAudio: false, addToHistory: true);
    if (res.text.isNotEmpty) {
       await speak(res.text);
    }
    _listenForWakeWord();
  }

  void disableBlindMode() {
     isBlindModeActive = false;
     _speech.stop();
  }

  void stop() {
    _speech.stop();
    _audioPlayer.stop();
    currentSpeechContent.value = '';
  }

  Future<String> listenOnce() async {
    Completer<String> completer = Completer();
    if (_speech.isListening) _speech.stop();
    await Future.delayed(const Duration(milliseconds: 200));

    await _speech.listen(
      localeId: 'ru_RU',
      cancelOnError: true,
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
         currentSpeechContent.value = result.recognizedWords;
         if (result.finalResult && !completer.isCompleted) {
            completer.complete(result.recognizedWords);
            Future.delayed(const Duration(milliseconds: 1000), () => currentSpeechContent.value = '');
         }
      }
    );
    
    Future.delayed(const Duration(seconds: 7), () {
      if (!completer.isCompleted) completer.complete("");
    });
    
    return completer.future;
  }

  void _listenForWakeWord() async {
    if (!isBlindModeActive || !_isInit || _speech.isListening || _audioPlayer.state == PlayerState.playing) return;

    await _speech.listen(
      localeId: 'ru_RU',
      cancelOnError: false,
      partialResults: true,
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        currentSpeechContent.value = result.recognizedWords;
        if (words.contains('данил') || words.contains('даня') || words.contains('нейро')) {
           _speech.stop();
           currentSpeechContent.value = '';
           _handleCommandSession();
        } else if (result.finalResult) {
           Future.delayed(const Duration(milliseconds: 1000), () => currentSpeechContent.value = '');
        }
      },
    );
  }

  Future<void> _handleCommandSession() async {
     await speak("Слушаю вас.");
     
     if (!_speech.isAvailable) return;

     await _speech.listen(
       localeId: 'ru_RU',
       cancelOnError: true,
       pauseFor: const Duration(seconds: 4),
       onResult: (result) async {
          currentSpeechContent.value = result.recognizedWords;
          if (result.finalResult) {
            final cmd = result.recognizedWords;
            Future.delayed(const Duration(milliseconds: 500), () => currentSpeechContent.value = '');
            await _processCommand(cmd);
          }
       }
     );
  }

  Future<void> _processCommand(String text) async {
     if (currentContext == null) {
        await speak("Тут я вам не могу помочь.");
        _listenForWakeWord();
        return;
     }

     final res = await _sendToGemini(text, requestAudio: false, addToHistory: true);
     final resText = res.text;

     if (resText.contains("[ACTION:CREATE_ROOM]")) {
         if (currentContext!.screenName == "MainScreen") {
            await speak("Уже создаю.");
            currentContext!.onCreateRoom();
         } else {
            await speak("Вы уже в комнате.");
         }
     } else if (resText.contains("[ACTION:JOIN_ROOM|")) {
         if (currentContext!.screenName == "MainScreen") {
            final regex = RegExp(r"\[ACTION:JOIN_ROOM\|(\d+)\]");
            final match = regex.firstMatch(resText);
            if (match != null && match.groupCount > 0) {
               final code = match.group(1)!;
               await speak("Вступаю в комнату $code.");
               currentContext!.onJoinRoom(code);
            } else {
               await speak("Я не расслышал, продиктуйте код комнаты по одной цифре.");
            }
         } else {
             await speak("Вы уже в комнате.");
         }
     } else if (resText.contains("[ACTION:JOIN_CALL]")) {
         if (currentContext!.screenName == "RoomScreen") {
             await speak("Захожу в звонок.");
             currentContext!.onJoinCall();
         } else {
             await speak("Сначала нужно вступить в комнату.");
         }
     } else {
         if (resText.isNotEmpty) {
             await speak(resText);
         }
     }

     Future.delayed(const Duration(seconds: 1), () => _listenForWakeWord());
  }

  // --- МЕТОДЫ ДЛЯ ТЕСТИРОВАНИЯ (Настройки) ---
  bool get isGeminiConnected => true;

  Future<void> testTTS(String text) async {
     await speak(text);
  }

  void startRawListening(Function(String) onResult, Function(bool) onStatus) {
    if (!_isInit) return;
    _speech.listen(
      localeId: 'ru_RU',
      cancelOnError: false,
      partialResults: true,
      onResult: (result) {
         if (result.finalResult) {
            onResult(result.recognizedWords);
         } else {
            currentSpeechContent.value = result.recognizedWords;
         }
      },
      listenFor: const Duration(seconds: 30),
    );
    onStatus(true);
  }

  void stopRawListening(Function(bool) onStatus) {
    _speech.stop();
    onStatus(false);
  }

  Future<String> testGemini(String input) async {
     final res = await _sendToGemini(input, requestAudio: false, addToHistory: false);
     if (res.text.isNotEmpty) {
        await speak(res.text);
     }
     return res.text;
  }
}
