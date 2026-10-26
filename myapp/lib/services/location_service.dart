import 'package:geolocator/geolocator.dart';

class DeliveryLocation {
  const DeliveryLocation({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

class DeviceLocationService {
  Future<DeliveryLocation> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'Turn on location services or enter your address manually.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Location permission was denied. Enter your address manually or enable permission in Settings.',
      );
    }
    final position = await Geolocator.getCurrentPosition();
    return DeliveryLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}

class LocationFailure implements Exception {
  const LocationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
