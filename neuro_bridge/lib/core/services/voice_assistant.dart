import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  final List<Map<String, dynamic>> _chatHistory = [];

  bool _isInit = false;
  bool isBlindModeActive = false; 
  bool _isSpeaking = false;

  final ValueNotifier<String> currentSpeechContent = ValueNotifier<String>('');
  VoiceCommandContext? currentContext;

  String? _welcomeTextCache;

  Future<void> init() async {
    if (_isInit) return;
    try {
       await _tts.setLanguage("ru-RU");
       await _tts.awaitSpeakCompletion(true);
       
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

      final modelName = requestAudio ? 'gemini-2.5-flash-native-audio-preview-12-2025' : 'gemini-2.5-flash';
      final apiVersion = 'v1beta';
      final url = Uri.parse('https://generativelanguage.googleapis.com/$apiVersion/models/$modelName:generateContent?key=${Env.geminiApiKey}');
      
      final userMessage = {"role": "user", "parts": [{"text": prompt}]};
      if (addToHistory) {
         _chatHistory.add(userMessage);
         if (_chatHistory.length > 20) _chatHistory.removeRange(0, _chatHistory.length - 20);
      }

      final systemPrompt = '''
Ты голосовой помощник по имени "Данил" (или "Даня"). Работай в приложении видеозвонков. Твой голос и интонация должны быть дружелюбными и помогающими.
Текущий экран: ${currentContext?.screenName ?? 'Неизвестно'}.

Если пользователь просит помощи ("что ты умеешь?", "помоги", "какие функции здесь есть?"), ОБЯЗАТЕЛЬНО четко и понятно перечисли функции, доступные на текущем экране.

Если экран "MainScreen":
Доступные функции: 1) Создание комнаты; 2) Присоединение к уроку (комнате) по коду.
- Если пользователь хочет "создать комнату". Ответь ТОЛЬКО тегом: "[ACTION:CREATE_ROOM]"
- Если пользователь хочет "вступить в комнату" или "присоединиться" (он должен назвать код комнаты цифрами, например 1234). Ответь ТОЛЬКО тегом: "[ACTION:JOIN_ROOM|кодизцифр]".

Если экран "RoomScreen":
Доступные функции: Подключение к видеозвонку (встрече).
- Если пользователь хочет "войти в звонок". Ответь ТОЛЬКО тегом: "[ACTION:JOIN_CALL]"

Если команда непонятна, или это просто вопрос - отвечай вежливо и коротко как помощник.
Если ты распознал команду интерфейса (создать, вступить) - ВЕРНИ ИСКЛЮЧИТЕЛЬНО ТЕГ [ACTION:...], и больше никаких слов.
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

  Future<void> speak(String text) async {
      if (text.isEmpty) return;
      print(">>> [TTS SPEAK] Озвучиваем локально: '$text'");
      _isSpeaking = true;
      try {
        await _tts.speak(text);
      } catch (e) {
        print(">>> [TTS SPEAK ERROR] $e");
      } finally {
        _isSpeaking = false;
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
     final textResp = "Здравствуйте! Я — ваш голосовой помощник Данил. Можете ли вы видеть экран?";
     _chatHistory.add({"role": "user", "parts": [{"text": "Представься и спроси, вижу ли я экран."}]});
     _chatHistory.add({"role": "model", "parts": [{"text": textResp}]});
     _welcomeTextCache = textResp;
     return textResp;
  }

  // Should be called by UI when it's ready to emit audio
  Future<void> speakWelcomeAudio() async {
      if (_welcomeTextCache != null) {
          await speak(_welcomeTextCache!);
          _welcomeTextCache = null;
      }
  }

  Future<void> activateBlindMode() async {
    isBlindModeActive = true;
    final textResp = "Успешно! Активирован режим для незрячих. Чтобы задать вопрос или выполнить действие, просто позовите меня по имени, Данил или Даня.";
    _chatHistory.add({"role": "user", "parts": [{"text": "Активирован режим незрячих, проинформируй меня об этом."}]});
    _chatHistory.add({"role": "model", "parts": [{"text": textResp}]});
    await speak(textResp);
    _listenForWakeWord();
  }

  void disableBlindMode() {
     isBlindModeActive = false;
     _speech.stop();
  }

  void stop() {
    _speech.stop();
    _tts.stop();
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
    if (!isBlindModeActive || !_isInit || _speech.isListening || _isSpeaking) return;

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
