import 'dart:async';
import 'dart:convert';
import '../models/accessibility_profile.dart';

abstract class LlmService {
  Future<AccessibilityProfile> generateProfileFromText(String text);
  Future<String> formatLessonText(String dictationText);
}

class MockLlmService implements LlmService {
  @override
  Future<AccessibilityProfile> generateProfileFromText(String text) async {
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2));
    
    // Parse text simply for mock purposes
    final lower = text.toLowerCase();
    return AccessibilityProfile(
      hasVisionLimitation: lower.contains("vision") || lower.contains("see") || lower.contains("зрение") || lower.contains("не вижу"),
      hasHearingLimitation: lower.contains("hearing") || lower.contains("hear") || lower.contains("слух") || lower.contains("не слышу"),
      hasSpeechLimitation: lower.contains("speech") || lower.contains("speak") || lower.contains("речь") || lower.contains("не говорю"),
      hasAdhdLimitation: lower.contains("adhd") || lower.contains("focus") || lower.contains("сдвг") || lower.contains("внимание"),
      fontScale: lower.contains("vision") || lower.contains("зрение") ? 1.5 : 1.0,
      useTts: lower.contains("vision") || lower.contains("зрение"),
      useStt: lower.contains("hearing") || lower.contains("слух"),
    );
  }

  @override
  Future<String> formatLessonText(String dictationText) async {
    await Future.delayed(const Duration(seconds: 1));
    return "💡 **Formatted text:**\n\n$dictationText";
  }
}
