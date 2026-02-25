import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      setState(() {
        _remoteRenderers[peerId]?.dispose();
        _remoteRenderers.remove(peerId);
        if (_mainUserId == peerId) {
          _mainUserId = _remoteRenderers.isNotEmpty ? _remoteRenderers.keys.first : null;
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
  }

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
    _signaling.dispose();
    _localRenderer.dispose();
    for (var r in _remoteRenderers.values) {
      r.dispose();
    }
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
       gridItems.add(_buildSmallVideo('Вы', _localRenderer, true, () {
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
     if (mainRenderer != null) {
       mainVideoWidget = RTCVideoView(mainRenderer, mirror: isMeMain, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
     }
     
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
