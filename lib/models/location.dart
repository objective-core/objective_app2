import 'package:objective_app2/models/permissions.dart';
import 'package:geolocator/geolocator.dart';

typedef LocationUpdated = void Function(Position position);
typedef LocationDenied = void Function();

class LocationModel {
  // Module should give current location
  Position? _currentLocation;

  bool get locationAvailable => _currentLocation != null;
  Position get currentLocation => _currentLocation!;

  bool get unableToLocate => (PermissionsModel.locationDenied || PermissionsModel.locationPermanentDenied);
  bool get needToRequestPermissions => PermissionsModel.locationDenied;
  bool get needToOpenSettings => PermissionsModel.locationPermanentDenied;

  LocationUpdated onLocationUpdated;
  LocationDenied onLocationDenied;

  LocationModel({required this.onLocationUpdated, required this.onLocationDenied});

  Future<void> updateLocation() async {
    await PermissionsModel.requestPermissions();

    if (PermissionsModel.locationGranted) {
      _currentLocation = await Geolocator.getCurrentPosition();
      onLocationUpdated(_currentLocation!);
    } else {
      onLocationDenied();
    }
  }
}