import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

class ConnectionProvider extends ChangeNotifier {
  String _serverIp = '192.168.123.5:8001';
  String get serverIp => _serverIp;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String _statusMessage = 'Not connected';
  String get statusMessage => _statusMessage;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  List<String> logs = [];

  ConnectionProvider() {
    _loadIp();
  }

  void addLog(String msg) {
    logs.insert(0, '${DateTime.now().toLocal()} - $msg');
    if (logs.length > 50) logs.removeLast();
    notifyListeners();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = prefs.getString('server_ip') ?? '192.168.123.5:8001';
    notifyListeners();
  }

  Future<void> setIp(String ip) async {
    _serverIp = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    addLog('IP set to $ip');
    notifyListeners();
  }

  Future<void> testHttpConnection() async {
    _statusMessage = 'Testing HTTP...';
    notifyListeners();
    try {
      final response = await http.get(Uri.parse('http://$_serverIp/'));
      if (response.statusCode == 200) {
        _statusMessage = 'HTTP OK: ${response.body}';
        addLog('HTTP ping successful');
      } else {
        _statusMessage = 'HTTP Error: ${response.statusCode}';
        addLog('HTTP status: ${response.statusCode}');
      }
    } catch (e) {
      _statusMessage = 'HTTP Failed';
      addLog('HTTP error: $e');
    }
    notifyListeners();
  }

  void connectWebSocket() {
    _statusMessage = 'Connecting WS...';
    notifyListeners();
    _channel?.sink.close();
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$_serverIp/ws'));
      _isConnected = true;
      _statusMessage = 'WS Connected';
      addLog('WS connected to ws://$_serverIp/ws');
      
      _subscription = _channel?.stream.listen((message) {
        addLog('WS received: $message');
      }, onDone: () {
        _isConnected = false;
        _statusMessage = 'WS Disconnected';
        addLog('WS disconnected');
        notifyListeners();
      }, onError: (error) {
        _isConnected = false;
        _statusMessage = 'WS Error: $error';
        addLog('WS error: $error');
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _statusMessage = 'WS Connect Fail: $e';
      addLog('WS connect error: $e');
      notifyListeners();
    }
  }

  void pongWS() {
    if (_isConnected) {
      _channel?.sink.add('ping');
      addLog('WS sent: ping');
    } else {
      addLog('WS not connected, cannot ping');
    }
  }

  void disconnectWebSocket() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _statusMessage = 'WS User disconnected';
    addLog('WS user disconnected');
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
