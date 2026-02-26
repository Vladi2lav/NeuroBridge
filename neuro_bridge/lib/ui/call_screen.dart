import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/services/webrtc_signaling.dart';

class CallScreen extends StatefulWidget {
  final String roomId;
  final bool isCreator;

  const CallScreen({super.key, required this.roomId, required this.isCreator});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  String? _mainUserId; // Null means 'Self' is main
  
  final WebRTCSignaling _signaling = WebRTCSignaling();
  
  bool _isLoading = true;
  bool _isAudioOn = true;
  bool _isVideoOn = true;
  
  List<MediaDeviceInfo> _mics = [];
  String? _selectedMic;
  
  // --- ДЛЯ НЕЙРОСЕТИ И ТРЕКИНГА ---
  WebSocketChannel? _trackingChannel;
  List<dynamic> _backendHands = [];
  
  // Данные трекинга от других участников
  Map<String, List<dynamic>> _peerHands = {};

  // Общий чат для субтитров и жестов
  List<Map<String, String>> _chatMessages = [];
  String _myActiveSpeech = "";
  Map<String, String> _peerActiveSpeech = {};
  
  String _myLastHandGesture = "";

  // Ключ для "фотографирования" нашего видео
  final GlobalKey _localVideoKey = GlobalKey();
  Timer? _frameCaptureTimer;
  bool _isProcessingFrame = false;
  bool _isAwaitingServer = false; // ОЖИДАНИЕ ОТВЕТА СЕРВЕРА (Защита от очередей)
  
  // Распознавание речи для субтитров
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isSpeechInitialized = false;

  void _addMessage(String sender, String text) {
    if (text.isEmpty) return;
    
    final msg = {"sender": sender, "text": text};
    
    setState(() {
      _chatMessages.add(msg);
      if (_chatMessages.length > 30) {
        _chatMessages.removeAt(0); // Ограничиваем историю
      }
    });
    
    // На мобильных экранах удаляем сообщение через 2.5 сек, чтобы не засорять 
    final isMobile = MediaQuery.of(context).size.width <= 600;
    if (isMobile) {
       Timer(const Duration(milliseconds: 2500), () {
          if (mounted && _chatMessages.contains(msg)) {
             setState(() {
                _chatMessages.remove(msg);
             });
          }
       });
    }
  }

  @override
  void initState() {
    super.initState();
    _initWebRtcInfo();
  }

  Future<void> _initWebRtcInfo() async {
    print('📱 [UI] Initializing Renderers...');
    await _localRenderer.initialize();
    
    _signaling.onLocalStreamAdded = (stream) {
      setState(() {
         _localRenderer.srcObject = stream;
      });
    };
    
    _signaling.onRemoteStreamAdded = (peerId, stream) async {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      setState(() {
        _remoteRenderers[peerId] = renderer;
        if (_mainUserId == null) {
          _mainUserId = peerId;
        }
      });
    };

    _signaling.onPeerLeft = (peerId) {
      if (!mounted) return;
      setState(() {
        _remoteRenderers[peerId]?.dispose();
        _remoteRenderers.remove(peerId);
        _peerHands.remove(peerId);
        _peerActiveSpeech.remove(peerId);
        if (_mainUserId == peerId) {
          _mainUserId = _remoteRenderers.isNotEmpty ? _remoteRenderers.keys.first : null;
        }
      });
    };

    _signaling.onPeerHandsData = (peerId, remoteHands, remoteSubtitle) {
      if (!mounted) return;
      setState(() {
        _peerHands[peerId] = remoteHands;
        if (remoteSubtitle.startsWith("SPEECH:")) {
           _peerActiveSpeech[peerId] = remoteSubtitle.substring(7);
        } else if (remoteSubtitle.startsWith("FINAL_SPEECH:")) {
           _peerActiveSpeech.remove(peerId);
           _addMessage("Участник", remoteSubtitle.substring(13));
        } else if (remoteSubtitle.startsWith("GESTURE:")) {
           _addMessage("Участник (Жест)", remoteSubtitle.substring(8));
        }
      });
    };

    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('backend_ip') ?? '192.168.123.5';

    await _signaling.initWebRTC();
    _signaling.connect(ip, widget.roomId);
    
    final mics = await _signaling.getAudioInputs();

    setState(() {
      _mics = mics;
      if (mics.isNotEmpty) {
        _selectedMic = mics.first.deviceId;
      }
      _isLoading = false;
    });
    
    // Инициализируем STT для живой речи
    try {
       _isSpeechInitialized = await _speech.initialize(
         onStatus: (status) {
            // Если STT остановилось (пауза в речи), но микрофон включен - запускаем снова
            if (status == 'notListening' && _isAudioOn && mounted) {
               Future.delayed(const Duration(seconds: 1), () {
                 if (_isAudioOn && mounted && !_speech.isListening) {
                   _startListeningSpeech();
                 }
               });
            }
         },
         onError: (e) => print("STT ошибка: $e")
       );
       if (_isSpeechInitialized && _isAudioOn) {
          _startListeningSpeech();
       }
    } catch (e) {
       print("Ошибка инита STT: $e");
    }

    _connectTrackingWS(ip);
  }

  void _startListeningSpeech() {
     if (!_isSpeechInitialized || !_isAudioOn) return;
     _speech.listen(
       localeId: 'ru_RU',
       cancelOnError: false,
       partialResults: true,
       listenMode: stt.ListenMode.dictation,
       pauseFor: const Duration(hours: 1), // Не выключать микро как можно дольше
       onResult: (result) {
          if (result.recognizedWords.isNotEmpty && mounted) {
             setState(() {
                _myActiveSpeech = result.recognizedWords;
             });
             
             if (result.finalResult) {
                 _addMessage("Вы", result.recognizedWords);
                 _myActiveSpeech = "";
                 _signaling.broadcastHandsData(_backendHands, "FINAL_SPEECH:${result.recognizedWords}");
             } else {
                 _signaling.broadcastHandsData(_backendHands, "SPEECH:${result.recognizedWords}");
             }
          }
       }
     );
  }

  void _stopListeningSpeech() {
     if (_isSpeechInitialized) {
        _speech.stop();
     }
  }

  void _connectTrackingWS(String ip) {
    try {
      _trackingChannel = WebSocketChannel.connect(Uri.parse('ws://$ip:8001/ws/hand_tracking'));
      
      // СРАЗУ ПОСЛЕ ПОДКЛЮЧЕНИЯ ЗАПУСКАЕМ СБОР КАДРОВ
      _startCaptureLoop();
      
      _trackingChannel!.stream.listen((message) {
        if (mounted) setState(() => _isAwaitingServer = false); // СЕРВЕР ОТВЕТИЛ! Разрешаем слать новый кадр
        
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'hands_data') {
            setState(() {
              _backendHands = data['hands'] ?? [];
              
              String incomingSubtitle = data['subtitle']?.toString() ?? "";
              
              if (incomingSubtitle.isNotEmpty && incomingSubtitle != _myLastHandGesture) {
                  _addMessage("Вы (Жест)", incomingSubtitle);
                  _signaling.broadcastHandsData(_backendHands, "GESTURE:$incomingSubtitle");
              }
              _myLastHandGesture = incomingSubtitle;
              
              // Для трансляции только самих рук
              if (incomingSubtitle.isEmpty) {
                 _signaling.broadcastHandsData(_backendHands, "");
              }
            });
          }
        } catch (e) {
          print("🚨 Ошибка парсинга JSON трекинга: $e");
        }
      }, onError: (err) {
        print("❌ Ошибка WebSocket трекинга: $err");
      });
    } catch (e) {
      print("📵 Не удалось подключиться к серверу трекинга");
    }
  }

  // --- ЛОГИКА ОТПРАВКИ КАДРОВ ---
  void _startCaptureLoop() {
    print("🚀 [ТРЕКИНГ] Запуск оптимизированного потока кадров...");
    
    DateTime _lastFrameTime = DateTime.now();

    _frameCaptureTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
       if (_isProcessingFrame || _isAwaitingServer || _trackingChannel == null) return;
       
       // Ждем минимум 250 мс между кадрами (Максимум 4 FPS),
       // чтобы не блокировать UI-поток (из-за чего отставало видео камеры).
       // Если нужно быстрее, можно снизить до 200, но это золотая середина.
       if (DateTime.now().difference(_lastFrameTime).inMilliseconds < 250) return;

       _isProcessingFrame = true;

       try {
         RenderRepaintBoundary? boundary = _localVideoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
         if (boundary != null) {
           _lastFrameTime = DateTime.now();
           // pixelRatio снижен до 0.15 для резкого ускорения toImage()
           ui.Image image = await boundary.toImage(pixelRatio: 0.15); 
           ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
           
           if (byteData != null) {
             final bytes = byteData.buffer.asUint8List();
             
             int formatCode = 2; // RGBA8888 
             var header = ByteData(16);
             header.setUint8(0, formatCode);
             header.setUint32(1, image.width, Endian.little);
             header.setUint32(5, image.height, Endian.little);
             header.setInt32(9, 0, Endian.little);
             
             var builder = BytesBuilder();
             builder.add(header.buffer.asUint8List());
             builder.add(bytes);
             
             _trackingChannel!.sink.add(builder.toBytes());
             setState(() => _isAwaitingServer = true);
             
             Timer(const Duration(milliseconds: 3000), () {
                 if (mounted && _isAwaitingServer) {
                     setState(() => _isAwaitingServer = false);
                 }
             });
           }
         }
       } catch (e) {
         print("🚨 [ТРЕКИНГ] Ошибка при снятии скриншота: $e");
       }
       _isProcessingFrame = false;
    });
  }
  // ----------------------------------------------------

  void _toggleAudio() {
    setState(() {
      _isAudioOn = !_isAudioOn;
      _signaling.toggleAudio(_isAudioOn);
      
      if (_isAudioOn) {
         _startListeningSpeech();
      } else {
         _stopListeningSpeech();
      }
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOn = !_isVideoOn;
      _signaling.toggleVideo(_isVideoOn);
    });
  }
  
  void _shareLink() {
    // В вебе мы можем легко получить домен
    String url = Uri.base.origin;
    // Либо если запускаем не в вебе
    if (url.isEmpty || url.startsWith('file:') || url == 'null') {
      url = "https://neurobridge.test"; // Заглушка, если это сборка Windows/Android
    }
    final fullLink = '$url/#/room/${widget.roomId}';
    
    Clipboard.setData(ClipboardData(text: fullLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка на комнату скопирована в буфер обмена!'))
    );
  }

  void _changeMic(String? deviceId) {
    if (deviceId != null) {
      setState(() => _selectedMic = deviceId);
      _signaling.changeAudioInput(deviceId);
    }
  }

  @override
  void dispose() {
    _signaling.dispose();
    _localRenderer.dispose();
    for (var r in _remoteRenderers.values) {
      r.dispose();
    }
    
    _stopListeningSpeech();
    _frameCaptureTimer?.cancel();
    _trackingChannel?.sink.close();
    super.dispose();
  }

  Widget _buildChatPanel({bool isMobile = false}) {
    List<Widget> messages = [];
    for (var msg in _chatMessages) {
       messages.add(Container(
         margin: const EdgeInsets.only(bottom: 6),
         padding: const EdgeInsets.all(8),
         decoration: BoxDecoration(
            color: msg['sender']!.startsWith('Вы') ? Colors.blueAccent.withOpacity(isMobile ? 0.6 : 0.3) : Colors.grey.withOpacity(isMobile ? 0.6 : 0.3),
            borderRadius: BorderRadius.circular(8)
         ),
         child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(msg['sender']!, style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
               const SizedBox(height: 2),
               Text(msg['text']!, style: const TextStyle(color: Colors.white, fontSize: 15)),
            ]
         )
       ));
    }
    
    if (_myActiveSpeech.isNotEmpty) {
       messages.add(Container(
           margin: const EdgeInsets.only(bottom: 6),
           padding: const EdgeInsets.all(8),
           decoration: BoxDecoration(color: Colors.blue.withOpacity(isMobile ? 0.4 : 0.1), borderRadius: BorderRadius.circular(8)),
           child: Text("Вы: $_myActiveSpeech...", style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
       ));
    }
    for (var peer in _peerActiveSpeech.entries) {
       messages.add(Container(
           margin: const EdgeInsets.only(bottom: 6),
           padding: const EdgeInsets.all(8),
           decoration: BoxDecoration(color: Colors.grey.withOpacity(isMobile ? 0.4 : 0.1), borderRadius: BorderRadius.circular(8)),
           child: Text("Участник: ${peer.value}...", style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
       ));
    }

    return Container(
       color: isMobile ? Colors.transparent : Colors.black54,
       child: Column(
          children: [
             if (!isMobile)
                const Padding(
                   padding: EdgeInsets.all(8),
                   child: Text("Субтитры", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                ),
             Expanded(
                child: ListView(
                   padding: isMobile ? const EdgeInsets.all(0) : const EdgeInsets.all(8),
                   children: messages,
                )
             )
          ]
       )
    );
  }

  Widget _buildControlsPanel({required bool isDesktop}) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      width: isDesktop ? 300 : double.infinity,
      child: Column(
        mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          if (isDesktop) ...[
            const Text('NeuroBridge', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  Text('Комната: ${widget.roomId}', style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _shareLink, 
                    icon: const Icon(Icons.share), 
                    label: const Text('Поделиться ссылкой')
                  )
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
               Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   FloatingActionButton(
                     heroTag: 'audio',
                     backgroundColor: _isAudioOn ? Colors.white24 : Colors.red,
                     onPressed: _toggleAudio,
                     child: Icon(_isAudioOn ? Icons.mic : Icons.mic_off, color: Colors.white),
                   ),
                   if (isDesktop && _mics.isNotEmpty)
                     Container(
                       margin: const EdgeInsets.only(top: 8),
                       width: 100,
                       child: DropdownButton<String>(
                         isExpanded: true,
                         dropdownColor: Colors.black,
                         style: const TextStyle(color: Colors.white, fontSize: 12),
                         value: _selectedMic,
                         items: _mics.map((m) => DropdownMenuItem(value: m.deviceId, child: Text(m.label, overflow: TextOverflow.ellipsis,))).toList(),
                         onChanged: _changeMic,
                       )
                     )
                 ],
               ),
               
               FloatingActionButton(
                 heroTag: 'video',
                 backgroundColor: _isVideoOn ? Colors.white24 : Colors.red,
                 onPressed: _toggleVideo,
                 child: Icon(_isVideoOn ? Icons.videocam : Icons.videocam_off, color: Colors.white),
               ),
               FloatingActionButton(
                 heroTag: 'end',
                 backgroundColor: Colors.redAccent,
                 onPressed: () => Navigator.of(context).pop(),
                 child: const Icon(Icons.call_end, color: Colors.white),
               ),
            ],
          )
        ],
      )
    );
  }

  void _showMobileMenu() {
    showModalBottomSheet(
      context: context, 
      backgroundColor: Colors.black87,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Комната: ${widget.roomId}', style: const TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () { 
                Navigator.pop(context);
                _shareLink();
              }, 
              icon: const Icon(Icons.copy), 
              label: const Text('Скопировать ссылку')
            ),
            const SizedBox(height: 20),
            if (_mics.isNotEmpty)
              DropdownButton<String>(
                isExpanded: true,
                dropdownColor: Colors.black,
                style: const TextStyle(color: Colors.white),
                value: _selectedMic,
                items: _mics.map((m) => DropdownMenuItem(value: m.deviceId, child: Text(m.label))).toList(),
                onChanged: (val) {
                  _changeMic(val);
                  Navigator.pop(context);
                },
              )
          ],
        ),
      )
    );
  }

  Widget _buildSmallVideo(String label, RTCVideoRenderer renderer, bool mirror, VoidCallback onTap) {
     return GestureDetector(
        onTap: onTap,
        child: Container(
           margin: const EdgeInsets.only(bottom: 8, right: 8),
           width: 160,
           height: 120,
           decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
           child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                   RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                   Positioned(
                     bottom: 4, left: 4, 
                     child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        color: Colors.black54,
                        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))
                     )
                   )
                ]
              )
           )
        )
     );
  }

  Widget _buildVideoContent(bool isDesktop) {
     final isMeMain = _mainUserId == null;
     final mainRenderer = isMeMain ? _localRenderer : _remoteRenderers[_mainUserId!];
     
     List<Widget> gridItems = [];
     
     if (!isMeMain) {
       // Оборачиваем маленькое окошко в RepaintBoundary, чтобы снимать кадры отсюда
       gridItems.add(RepaintBoundary(
         key: _localVideoKey,
         child: _buildSmallVideo('Вы', _localRenderer, true, () {
           setState(() => _mainUserId = null);
         })
       ));
     }
     
     int userCounter = 1;
     for (var entry in _remoteRenderers.entries) {
        if (entry.key != _mainUserId) {
           gridItems.add(_buildSmallVideo('Участник $userCounter', entry.value, false, () {
              setState(() => _mainUserId = entry.key);
           }));
        }
        userCounter++;
     }
     
     Widget mainVideoWidget = Container();
     if (mainRenderer != null) {
       Widget videoView = RTCVideoView(mainRenderer, mirror: isMeMain, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
       
       // Оборачиваем большое окошко, если локальное видео на весь экран
       if (isMeMain) {
         videoView = RepaintBoundary(
           key: _localVideoKey,
           child: videoView,
         );
       }
       
       
       // СМОТРИМ, ЧЬИ РУКИ ОТОБРАЖАТЬ ПО СЕРЕДИНЕ:
       List<dynamic> targetHands = isMeMain ? _backendHands : (_peerHands[_mainUserId] ?? []);
       
       mainVideoWidget = Stack(
         fit: StackFit.expand,
         children: [
           videoView,
           // ОВЕРЛЕЙ НЕОНОВОГО ТРЕКИНГА (рисует кости поверх видео)
           if (targetHands.isNotEmpty)
             CustomPaint(
               painter: NeonTrackingPainter(hands: targetHands),
             ),
         ],
       );
     }
     
     if (isDesktop) {
        return Row(
           children: [
              Expanded(flex: 6, child: mainVideoWidget),
              Container(
                width: 280,
                decoration: const BoxDecoration(
                   border: Border(left: BorderSide(color: Colors.white24))
                ),
                child: Column(
                   children: [
                      if (gridItems.isNotEmpty)
                         SizedBox(
                            height: 150.0 * (gridItems.length > 2 ? 2 : gridItems.length),
                            child: ListView(padding: const EdgeInsets.all(8), children: gridItems)
                         ),
                      Expanded(child: _buildChatPanel())
                   ]
                )
              )
           ]
        );
     } else {
        return Stack(
          children: [
             Positioned.fill(child: mainVideoWidget),
             
             // Чат-субтитры поверх мобильного видео (снизу-слева)
             Positioned(
                 left: 10, right: 10, top: 20, bottom: 150,
                 child: Align(
                    alignment: Alignment.bottomLeft,
                    child: SizedBox(
                       width: 320,
                       height: 250,
                       child: _buildChatPanel(isMobile: true)
                    )
                 )
             ),
             
             if (gridItems.isNotEmpty)
               Positioned(
                 bottom: 20, left: 10, right: 10,
                 height: 120,
                 child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: gridItems,
                 )
               ),
              if (!isDesktop)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white, size: 30),
                      onPressed: _showMobileMenu,
                    )
                  ),
          ]
        );
     }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
       return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 600;
            
            final videoContent = _buildVideoContent(isDesktop);
            
            if (isDesktop) {
              return Row(
                children: [
                  _buildControlsPanel(isDesktop: true),
                  Expanded(child: videoContent)
                ],
              );
            } else {
              return Column(
                children: [
                  Expanded(child: videoContent),
                  _buildControlsPanel(isDesktop: false),
                ],
              );
            }
          },
        ),
      ),
    );
  }
}

// КРАСИВЫЙ НЕОНОВЫЙ ХУДОЖНИК ИЗ БЕТЫ (Трекинг рук)
class NeonTrackingPainter extends CustomPainter {
  final List<dynamic> hands;

  NeonTrackingPainter({required this.hands});

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;

    // 2. ОТРИСОВКА НЕОНОВЫХ ЛИНИЙ (КОСТИ И СУСТАВЫ)
    final linePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
      
    final shadowPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
      
    final innerDotPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;

    final connections = [
      [0, 1], [1, 2], [2, 3], [3, 4], // Большой
      [0, 5], [5, 6], [6, 7], [7, 8], // Указательный
      [5, 9], [9, 10], [10, 11], [11, 12], // Средний
      [9, 13], [13, 14], [14, 15], [15, 16], // Безымянный
      [13, 17], [17, 18], [18, 19], [19, 20], // Мизинец
      [0, 17] // Ладонь
    ];

    for (var hand in hands) {
       // Отрисовка всех соединений
       for (var conn in connections) {
         if (conn[0] < hand.length && conn[1] < hand.length) {
           final p1 = hand[conn[0]];
           final p2 = hand[conn[1]];
           
           // X больше не зеркалируем здесь, так как бэкенд уже присылает правильные координаты
           final double x1 = p1['x'] * size.width;
           final double y1 = p1['y'] * size.height;
           final double x2 = p2['x'] * size.width;
           final double y2 = p2['y'] * size.height;

           canvas.drawLine(Offset(x1, y1), Offset(x2, y2), shadowPaint);
           canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
         }
       }

       // Отрисовка суставов (точки)
       for (var lm in hand) {
          double cx = lm['x'] * size.width;
          double cy = lm['y'] * size.height;
          canvas.drawCircle(Offset(cx, cy), 6, dotPaint);
          canvas.drawCircle(Offset(cx, cy), 4, innerDotPaint);
       }
    }
  }

  @override
  bool shouldRepaint(covariant NeonTrackingPainter oldDelegate) => true;
}
