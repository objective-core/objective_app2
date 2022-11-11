import 'package:permission_handler/permission_handler.dart';


class PermissionsModel {
  static Map<Permission, PermissionStatus> statuses = {};

  static Future<void> requestPermissions() async {
    statuses = await [
      Permission.location,
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  static bool hasPermission(Permission permission) {
    return statuses[permission]== PermissionStatus.granted;
  }

  // Location needed to position map initially.
  static bool get locationGranted =>
      statuses[Permission.location] == PermissionStatus.granted;

  static bool get locationDenied =>
      statuses[Permission.location] == PermissionStatus.denied;

  static bool get locationPermanentDenied =>
      statuses[Permission.location] == PermissionStatus.permanentlyDenied;

  static bool get needToRequestPermissions =>
      statuses.values.any((status) => status == PermissionStatus.denied);

  static bool get needToOpenSettings =>
      statuses.values.any((status) => status == PermissionStatus.permanentlyDenied);

  // To shot a video we need to know location.
  static bool get allGranted =>
      statuses.values.every((status) => status == PermissionStatus.granted);
}
