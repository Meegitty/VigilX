import 'package:geolocator/geolocator.dart';

class LocationSnapshot {
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });
}

class LocationService {
  /// Ensure GPS service is on and permissions are granted.
  static Future<void> _ensureServiceAndPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied. Enable it in Settings.');
    }
  }

  /// Get a single current location snapshot.
  static Future<LocationSnapshot> getCurrent() async {
    await _ensureServiceAndPermission();

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    return LocationSnapshot(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
    );
  }

  /// Subscribe to continuous location updates for real-time tracking.
  static Future<Stream<LocationSnapshot>> subscribeToLocationChanges({
    LocationSettings? settings,
  }) async {
    await _ensureServiceAndPermission();

    settings ??= const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // meters between updates
    );

    final stream = Geolocator.getPositionStream(locationSettings: settings);
    return stream.map(
      (pos) => LocationSnapshot(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      ),
    );
  }
}