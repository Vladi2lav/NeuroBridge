import 'package:freezed_annotation/freezed_annotation.dart';

part 'accessibility_profile.freezed.dart';
part 'accessibility_profile.g.dart';

@freezed
class AccessibilityProfile with _$AccessibilityProfile {
  const factory AccessibilityProfile({
    @Default(false) bool hasVisionLimitation,
    @Default(false) bool hasHearingLimitation,
    @Default(false) bool hasSpeechLimitation,
    @Default(false) bool hasAdhdLimitation,
    // Add additional fields as needed for specific scaling factors, etc.
    @Default(1.0) double fontScale,
    @Default(true) bool useTts,
    @Default(true) bool useStt,
  }) = _AccessibilityProfile;

  factory AccessibilityProfile.fromJson(Map<String, dynamic> json) =>
      _$AccessibilityProfileFromJson(json);
}
