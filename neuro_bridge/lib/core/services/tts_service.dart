import 'dart:async';

abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
}

class MockTtsService implements TtsService {
  @override
  Future<void> initialize() async {
    // Simulate initialization
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> speak(String text) async {
    print("Mock TTS Speaking: $text");
    // Simulate speaking duration based on length
    await Future.delayed(Duration(milliseconds: 100 * text.length));
    print("Mock TTS Finished Speaking: $text");
  }

  @override
  Future<void> stop() async {
    print("Mock TTS Stopped");
  }
}
