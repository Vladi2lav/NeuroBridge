import 'package:camera/camera.dart';

abstract class LocalHandTracker {
  void init();
  List<dynamic> detect(CameraImage image, int sensorOrientation);
  void dispose();
}
