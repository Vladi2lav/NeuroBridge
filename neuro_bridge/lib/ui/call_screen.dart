import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
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
  Map<String, dynamic> _virtualElements = {}; // Виртуальные кнопки и блоки от сервера
  String _currentSubtitle = "";
  Timer? _subtitleTimer;
  
  // --- CAMERA MODULE (LOCAL LIKE FUNCTIONAL-BETA) ---
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  int _lastFrameTime = 0;
  bool _isWaitingForServerResponse = false;
  Size? _imageSize; // Размер кадра с камеры
  bool _isProcessingFrame = false; // <-- ВЕРНУЛ ПЕРЕМЕННУЮ

  // Данные трекинга от других участников (ВЕРНУЛ ПЕРЕМЕННЫЕ)
  Map<String, List<dynamic>> _peerHands = {};
  Map<String, String> _peerSubtitles = {};
  Map<String, Timer?> _peerSubtitleTimers = {};

  // Локальный ML Kit трекинг (как в бете) ТОЛЬКО для отрисовки поверх себя
  HandLandmarkerPlugin? _handLandmarker;
  List<Hand> _localHands = [];

  @override
  void initState() {
    super.initState();
    _initHandLandmarker();
    _initCamera();
    _initWebRtcInfo();
  }

  Future<void> _initHandLandmarker() async {
     _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 2,
        delegate: HandLandmarkerDelegate.gpu,
     );
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: !kIsWeb && Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888, 
    );

    await _cameraController!.initialize();
    setState(() => _cameraInitialized = true);
    
    if (!kIsWeb) {
       _startCameraStream();
    } else {
       print("⚠️ [ТРЕКИНГ] Web-версия (Браузер) не поддерживает startImageStream для камеры! Обработки рук не будет. Запустите на Windows или Android.");
    }
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
        _peerSubtitles.remove(peerId);
        if (_mainUserId == peerId) {
          _mainUserId = _remoteRenderers.isNotEmpty ? _remoteRenderers.keys.first : null;
        }
      });
    };

    _signaling.onPeerHandsData = (peerId, remoteHands, remoteSubtitle) {
      if (!mounted) return;
      setState(() {
        _peerHands[peerId] = remoteHands;
        if (remoteSubtitle.isNotEmpty) {
           _peerSubtitles[peerId] = remoteSubtitle;
           _peerSubtitleTimers[peerId]?.cancel();
           _peerSubtitleTimers[peerId] = Timer(const Duration(seconds: 3), () {
             if (mounted) setState(() => _peerSubtitles[peerId] = "");
           });
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

    _connectTrackingWS(ip);
  }

  void _connectTrackingWS(String ip) {
    try {
      _trackingChannel = WebSocketChannel.connect(Uri.parse('ws://$ip:8001/ws/hand_tracking'));
      
      // СРАЗУ ПОСЛЕ ПОДКЛЮЧЕНИЯ ЗАПУСКАЕМ СБОР КАДРОВ
      // Сбор кадров теперь запускается в _initCamera через _startCameraStream(). 
      // _startCaptureLoop() удален, так как мы не используем RepaintBoundary.
      
      _trackingChannel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'hands_data') {
            setState(() {
              _backendHands = data['hands'] ?? [];
              
              if (data['virtual_elements'] != null) {
                _virtualElements = data['virtual_elements'];
              }
              
              if (data['subtitle'] != null && data['subtitle'].toString().isNotEmpty) {
                _currentSubtitle = data['subtitle'];
                
                // Таймер для скрытия субтитров через 3 секунды
                _subtitleTimer?.cancel();
                _subtitleTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) setState(() => _currentSubtitle = "");
                });
              }
              
              // Транслируем свои руки остальным участникам
              _signaling.broadcastHandsData(_backendHands, _currentSubtitle);
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

  // --- ЛОГИКА ОТПРАВКИ КАДРОВ ИЗ CAMERA (КАК В FUNCTIONAL-BETA) ---
  void _startCameraStream() {
    if (_cameraController == null) return;
    
    _cameraController!.startImageStream((image) async {
       if (_isProcessingFrame) return;
       _isProcessingFrame = true;

       if (_imageSize == null) {
          setState(() {
             _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          });
       }

       Uint8List finalBytes;
       if (!kIsWeb && Platform.isAndroid && image.format.group == ImageFormatGroup.yuv420) {
           var builder = BytesBuilder();
           builder.add(image.planes[0].bytes);
           builder.add(image.planes[2].bytes);
           builder.add([0]);
           finalBytes = builder.toBytes();
       } else {
           final WriteBuffer allBytes = WriteBuffer();
           for (final Plane plane in image.planes) {
             allBytes.putUint8List(plane.bytes);
           }
           finalBytes = allBytes.done().buffer.asUint8List();
       }

       final int currentTime = DateTime.now().millisecondsSinceEpoch;

       // 1. ОТПРАВКА НА СЕРВЕР WS
       if (_trackingChannel != null && !_isWaitingForServerResponse) {
          if (currentTime - _lastFrameTime >= 50) {
             _lastFrameTime = currentTime;
             _isWaitingForServerResponse = true;
             
             try {
                int formatCode = (!kIsWeb && Platform.isAndroid) ? 0 : 1; // 0=NV21, 1=BGRA
                var header = ByteData(16);
                header.setUint8(0, formatCode);
                header.setUint32(1, image.width, Endian.little);
                header.setUint32(5, image.height, Endian.little);
                header.setInt32(9, _cameraController!.description.sensorOrientation, Endian.little);

                var builder = BytesBuilder();
                builder.add(header.buffer.asUint8List());
                builder.add(finalBytes);
                
                _trackingChannel!.sink.add(builder.toBytes());
                
                Future.delayed(const Duration(milliseconds: 150), () {
                   if (mounted) _isWaitingForServerResponse = false;
                });
             } catch (e) {
                print("🚨 Ошибка отправки кадра на сервер: $e");
                _isWaitingForServerResponse = false;
             }
          }
       }
       
       // 2. ЛОКАЛЬНАЯ ОТРИСОВКА ML KIT ДЛЯ СЕБЯ (КАК В БЕТЕ)
       if (_handLandmarker != null) {
          try {
             final hands = _handLandmarker!.detect(image, _cameraController!.description.sensorOrientation);
             if (mounted) {
               setState(() {
                 _localHands = hands;
               });
             }
          } catch(e) { }
       }
       
       _isProcessingFrame = false;
    });
  }
  // ----------------------------------------------------

  void _toggleAudio() {
    setState(() {
      _isAudioOn = !_isAudioOn;
      _signaling.toggleAudio(_isAudioOn);
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
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _handLandmarker?.dispose();
    _signaling.dispose();
    _localRenderer.dispose();
    for (var r in _remoteRenderers.values) {
      r.dispose();
    }
    
    _trackingChannel?.sink.close();
    _subtitleTimer?.cancel();
    super.dispose();
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
                fit: StackFit.expand,
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

  Widget _buildSmallCamera(String label, VoidCallback onTap) {
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
                fit: StackFit.expand,
                children: [
                   if (_cameraInitialized && _cameraController != null)
                     CameraPreview(_cameraController!),
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
       // Локальное видео рендерим ЧЕРЕЗ CAMERA PLUGIN как просил юзер: "мой блок видео, скопировать"
       gridItems.add(_buildSmallCamera('Вы', () {
           setState(() => _mainUserId = null);
       }));
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
     if (isMeMain && _cameraInitialized) {
       // Если мы - главные, показываем CameraPreview как в functional-beta
       mainVideoWidget = Stack(
         fit: StackFit.expand,
         children: [
           CameraPreview(_cameraController!),
           // Локальная отрисовка ML Kit И виртуальных элементов (без костей от сервера)
           CustomPaint(
             painter: TrackingPainter(
                useBackend: false, // для костей юзаем _localHands снизу
                backendHands: [], // свои кости из бека не рисуем
                localHands: _localHands,
                imageSize: _imageSize,
                virtualElements: _virtualElements,
             ),
           ),
         ],
       );
     } else if (mainRenderer != null) {
       // Показываем ЧУЖОЕ WebRTC видео (+ чужие кости из бэка)
       mainVideoWidget = Stack(
         fit: StackFit.expand,
         children: [
           RTCVideoView(mainRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
           // ОВЕРЛЕЙ НЕОНОВОГО ТРЕКИНГА
           if ((_peerHands[_mainUserId] ?? []).isNotEmpty || _virtualElements.isNotEmpty)
             CustomPaint(
               painter: TrackingPainter(
                 useBackend: true,
                 backendHands: _peerHands[_mainUserId] ?? [],
                 localHands: [],
                 virtualElements: _virtualElements,
               ),
             ),
         ],
       );
     }
     
     // ДИНАМИЧЕСКИЙ СУБТИТР (Либо свой, либо того, кого мы смотрим крупно)
     String displaySubtitle = isMeMain ? _currentSubtitle : (_peerSubtitles[_mainUserId] ?? "");
     
     if (isDesktop) {
        return Row(
           children: [
              Expanded(flex: 6, child: mainVideoWidget),
              if (gridItems.isNotEmpty || !isMeMain)
                Container(
                  width: 250,
                  decoration: const BoxDecoration(
                     border: Border(left: BorderSide(color: Colors.white24))
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: gridItems,
                  )
                )
           ]
        );
     } else {
        return Stack(
          children: [
             Positioned.fill(child: mainVideoWidget),
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
              // СУБТИТРЫ (ПОКАЗЫВАЮТСЯ ВНИЗУ)
              if (displaySubtitle.isNotEmpty)
                Positioned(
                  bottom: 150, left: 0, right: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: displaySubtitle.isNotEmpty ? 1.0 : 0.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1),
                          boxShadow: [
                            BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 10, spreadRadius: 2)
                          ]
                        ),
                        child: Text(
                          displaySubtitle,
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                )
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

// КРАСИВЫЙ НЕОНОВЫЙ ХУДОЖНИК ИЗ БЕТЫ (Универсальный: либо локальный ML Kit, либо WebRTC чужой)
class TrackingPainter extends CustomPainter {
  final bool useBackend;
  final List<dynamic> backendHands;
  final List<Hand> localHands;
  final Size? imageSize;
  final Map<String, dynamic> virtualElements;

  TrackingPainter({required this.useBackend, required this.backendHands, required this.localHands, this.imageSize, this.virtualElements = const {}});

  @override
  void paint(Canvas canvas, Size size) {
    if (useBackend) {
        // --- ОТРИСОВКА ЧУЖИХ РУК (ИЗ БЭКЕНДА) ---
        if (backendHands.isEmpty && virtualElements.isEmpty) return;
        
        // 1. ОТРИСОВКА ВИРТУАЛЬНЫХ ЭЛЕМЕНТОВ
        _drawVirtualElements(canvas, size);

        // 2. ОТРИСОВКА НЕОНОВЫХ ЛИНИЙ
        final linePaint = Paint()..color = Colors.cyanAccent.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 4.0..strokeCap = StrokeCap.round;
        final shadowPaint = Paint()..color = Colors.cyanAccent.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 10.0..strokeCap = StrokeCap.round;
        final dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
        final innerDotPaint = Paint()..color = Colors.blueAccent..style = PaintingStyle.fill;

        for (var hand in backendHands) {
           for (var conn in _connections) {
             if (conn[0] < hand.length && conn[1] < hand.length) {
               final double x1 = (1.0 - hand[conn[0]]['x']) * size.width;
               final double y1 = hand[conn[0]]['y'] * size.height;
               final double x2 = (1.0 - hand[conn[1]]['x']) * size.width;
               final double y2 = hand[conn[1]]['y'] * size.height;

               canvas.drawLine(Offset(x1, y1), Offset(x2, y2), shadowPaint);
               canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
             }
           }
           for (var lm in hand) {
              canvas.drawCircle(Offset((1.0 - lm['x']) * size.width, lm['y'] * size.height), 6, dotPaint);
              canvas.drawCircle(Offset((1.0 - lm['x']) * size.width, lm['y'] * size.height), 4, innerDotPaint);
           }
        }
    } else {
        // --- ОТРИСОВКА СВОИХ РУК (ЛОКАЛЬНЫЙ ML KIT) ---
        _drawVirtualElements(canvas, size);
        
        if (localHands.isEmpty) return;

        final linePaint = Paint()..color = Colors.greenAccent.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 4.0..strokeCap = StrokeCap.round;
        final shadowPaint = Paint()..color = Colors.greenAccent.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 10.0..strokeCap = StrokeCap.round;
        final dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
        final innerDotPaint = Paint()..color = Colors.green..style = PaintingStyle.fill;

        for (var hand in localHands) {
           for (var conn in _connections) {
             if (conn[0] < hand.landmarks.length && conn[1] < hand.landmarks.length) {
               final double x1 = (1.0 - hand.landmarks[conn[0]].x) * size.width;
               final double y1 = hand.landmarks[conn[0]].y * size.height;
               final double x2 = (1.0 - hand.landmarks[conn[1]].x) * size.width;
               final double y2 = hand.landmarks[conn[1]].y * size.height;

               canvas.drawLine(Offset(x1, y1), Offset(x2, y2), shadowPaint);
               canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
             }
           }
           for (var lm in hand.landmarks) {
              canvas.drawCircle(Offset((1.0 - lm.x) * size.width, lm.y * size.height), 6, dotPaint);
              canvas.drawCircle(Offset((1.0 - lm.x) * size.width, lm.y * size.height), 4, innerDotPaint);
           }
        }
    }
  }

  void _drawVirtualElements(Canvas canvas, Size size) {
    if (virtualElements.isEmpty) return;
    
    final button = virtualElements['button'];
    if (button != null && button['visible'] == true && button['pos'] != null) {
       final double bx = (1.0 - button['pos']['x']) * size.width;
       final double by = button['pos']['y'] * size.height;
       final btnPaint = Paint()..color = Colors.orangeAccent..style = PaintingStyle.fill;
       canvas.drawCircle(Offset(bx, by), 30, btnPaint);
       final tp = TextPainter(text: const TextSpan(style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), text: 'PRESS'), textAlign: TextAlign.center, textDirection: TextDirection.ltr)..layout();
       tp.paint(canvas, Offset(bx - tp.width / 2, by - tp.height / 2));
    }
    
    final block = virtualElements['block'];
    if (block != null && block['visible'] == true && block['pos'] != null) {
       final double bx = (1.0 - block['pos']['x']) * size.width;
       final double by = block['pos']['y'] * size.height;
       final blockPaint = Paint()..color = block['grabbed'] == true ? Colors.redAccent : Colors.tealAccent..style = PaintingStyle.fill;
       canvas.drawRect(Rect.fromLTWH(bx - 30.0, by - 30.0, 60.0, 60.0), blockPaint);
    }
  }

  static const _connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // Index
    [5, 9], [9, 10], [10, 11], [11, 12], // Middle
    [9, 13], [13, 14], [14, 15], [15, 16], // Ring
    [13, 17], [17, 18], [18, 19], [19, 20], // Pinky
    [0, 17] // Palm base
  ];

  @override
  bool shouldRepaint(covariant TrackingPainter oldDelegate) => true;
}
