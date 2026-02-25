import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'local_tracker_api.dart';
export 'local_tracker_api.dart';

class LocalTrackerNative implements LocalHandTracker {
  HandLandmarkerPlugin? _handLandmarker;

  @override
  void init() {
    _handLandmarker = HandLandmarkerPlugin.create(
       numHands: 2,
       delegate: HandLandmarkerDelegate.gpu,
    );
  }

  @override
  List<dynamic> detect(CameraImage image, int sensorOrientation) {
    if (_handLandmarker == null) return [];
    try {
      final hands = _handLandmarker!.detect(image, sensorOrientation);
      return hands.map((h) {
         return h.landmarks.map((lm) => {'x': lm.x, 'y': lm.y, 'z': lm.z}).toList();
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  void dispose() {
    _handLandmarker?.dispose();
  }
}

LocalHandTracker getLocalTracker() => LocalTrackerNative();
