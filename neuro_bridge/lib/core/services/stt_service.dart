import 'dart:async';

abstract class SttService {
  Future<void> initialize();
  Future<void> startListening({required Function(String text) onResult});
  Future<void> stopListening();
  bool get isListening;
}

class MockSttService implements SttService {
  bool _isListening = false;
  Timer? _timer;
  
  @override
  bool get isListening => _isListening;

  @override
  Future<void> initialize() async {
    // Simulate initialization delay
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> startListening({required Function(String text) onResult}) async {
    _isListening = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isListening) {
        onResult("Mocked transcribed text segment at ${DateTime.now().toIso8601String()}");
      }
    });
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
    _timer?.cancel();
    _timer = null;
  }
}
