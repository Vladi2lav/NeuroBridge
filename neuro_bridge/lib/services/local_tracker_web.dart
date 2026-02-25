import 'package:camera/camera.dart';
import 'local_tracker_api.dart';
export 'local_tracker_api.dart';

class LocalTrackerWeb implements LocalHandTracker {
  @override
  void init() {}

  @override
  List<dynamic> detect(CameraImage image, int sensorOrientation) {
    return []; // Not supported on web locally
  }

  @override
  void dispose() {}
}

LocalHandTracker getLocalTracker() => LocalTrackerWeb();
