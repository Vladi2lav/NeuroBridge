import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebRTCSignaling {
  WebSocketChannel? _channel;
  MediaStream? localStream;

  Map<String, RTCPeerConnection> peerConnections = {};
  String? myId;

  Function(MediaStream stream)? onLocalStreamAdded;
  Function(String peerId, MediaStream stream)? onRemoteStreamAdded;
  Function(String peerId)? onPeerLeft;
  // Добавлено: передача чужих рук и субтитров
  Function(String peerId, List<dynamic> hands, String subtitle)? onPeerHandsData;

  Future<void> initWebRTC() async {
    print('[WebRTC] Получаю доступ к камере и микрофону...');
    try {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
        },
      });
      print('[WebRTC] Доступ получен. Добавляем локальный стрим.');
      onLocalStreamAdded?.call(localStream!);
    } catch (e) {
      print('[WebRTC] !!! ОШИБКА ДОСТУПА К КАМЕРЕ: $e');
    }
  }

  void connect(String serverIp, String roomId) {
    print('[WebRTC] Попытка подключения к сокету: ws://$serverIp:8001/ws/signal/$roomId');
    final wsUrl = Uri.parse('ws://$serverIp:8001/ws/signal/$roomId');
    _channel = WebSocketChannel.connect(wsUrl);

    _channel?.stream.listen((message) {
      _handleMessage(json.decode(message));
    }, onError: (err) {
      print('[WebRTC] !!! ОШИБКА СОКЕТА: $err');
    }, onDone: () {
      print('[WebRTC] !!! СОКЕТ ЗАКРЫЛСЯ !!!');
    });
  }

  Future<RTCPeerConnection> _createPeerConnection(String peerId) async {
    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    final pc = await createPeerConnection(configuration);

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _sendToSignaling({
        'type': 'candidate',
        'to': peerId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onRemoteStreamAdded?.call(peerId, event.streams[0]);
      }
    };

    if (localStream != null) {
      localStream!.getTracks().forEach((track) {
        pc.addTrack(track, localStream!);
      });
    }

    peerConnections[peerId] = pc;
    return pc;
  }

  void _handleMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    final fromId = data['from'];

    try {
      switch (type) {
        case 'room_state':
          myId = data['my_id'];
          List<dynamic> peers = data['peers'];
          print('[WebRTC] Мой ID: $myId, уже есть участники: $peers');

          for (var p in peers) {
            final String peerId = p.toString();
            final pc = await _createPeerConnection(peerId);
            final offer = await pc.createOffer();
            await pc.setLocalDescription(offer);
            _sendToSignaling({
              'type': 'offer',
              'to': peerId,
              'sdp': offer.sdp,
            });
          }
          break;
        case 'peer_joined':
          final String peerId = data['peer_id'];
          print('[WebRTC] Новый участник присоединился: $peerId');
          // Prepare pc, wait for their offer
          await _createPeerConnection(peerId);
          break;
        case 'peer_left':
          final String peerId = data['peer_id'];
          print('[WebRTC] Участник покинул нас: $peerId');
          peerConnections[peerId]?.dispose();
          peerConnections.remove(peerId);
          onPeerLeft?.call(peerId);
          break;
        case 'offer':
          var pc = peerConnections[fromId];
          if (pc == null) pc = await _createPeerConnection(fromId);

          await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          _sendToSignaling({
            'type': 'answer',
            'to': fromId,
            'sdp': answer.sdp,
          });
          break;
        case 'answer':
          final pc = peerConnections[fromId];
          if (pc != null) {
            await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
          }
          break;
        case 'candidate': // Renamed from 'ice_candidate' in the provided edit to match original 'candidate'
          final pc = peerConnections[fromId];
          if (pc != null) {
            final candidateMap = data['candidate'];
            final candidate = RTCIceCandidate(
              candidateMap['candidate'],
              candidateMap['sdpMid'],
              candidateMap['sdpMLineIndex'],
            );
            await pc.addCandidate(candidate);
          }
          break;
        case 'peer_hands_data':
          // Получили руки от собеседника!
          onPeerHandsData?.call(fromId, data['hands'] ?? [], data['subtitle'] ?? '');
          break;
      }
    } catch (e) {
      print("Signaling error: $e");
    }
  }

  void _sendToSignaling(Map<String, dynamic> data) {
    _channel?.sink.add(json.encode(data));
  }

  void broadcastHandsData(List<dynamic> hands, String subtitle) {
    _sendToSignaling({
      'type': 'peer_hands_data',
      'hands': hands,
      'subtitle': subtitle,
    });
  }

  void toggleAudio(bool enabled) {
    if (localStream != null) {
      for (var track in localStream!.getAudioTracks()) {
        track.enabled = enabled;
      }
    }
  }

  void toggleVideo(bool enabled) {
    if (localStream != null) {
      for (var track in localStream!.getVideoTracks()) {
        track.enabled = enabled;
      }
    }
  }

  Future<List<MediaDeviceInfo>> getAudioInputs() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.where((device) => device.kind == 'audioinput').toList();
  }

  Future<void> changeAudioInput(String deviceId) async {
    if (localStream != null) {
      final newStream = await navigator.mediaDevices.getUserMedia({
        'audio': {'deviceId': deviceId},
        'video': false, 
      });
      final newAudioTrack = newStream.getAudioTracks().first;
      final oldAudioTrack = localStream!.getAudioTracks().first;
      
      await localStream!.removeTrack(oldAudioTrack);
      oldAudioTrack.stop();
      
      await localStream!.addTrack(newAudioTrack);
      
      // Update in all peer connections
      for (var pc in peerConnections.values) {
        final senders = await pc.getSenders();
        final audioSender = senders.firstWhere((sender) => sender.track?.kind == 'audio');
        await audioSender.replaceTrack(newAudioTrack);
      }
    }
  }

  void dispose() {
    print('[WebRTC] Очистка PeerConnection и Socket...');
    localStream?.dispose();
    for (var pc in peerConnections.values) {
      pc.dispose();
    }
    _channel?.sink.close();
  }
}

