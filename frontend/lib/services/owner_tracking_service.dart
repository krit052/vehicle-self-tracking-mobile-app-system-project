import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class OwnerLocationException implements Exception {
  final String message;

  const OwnerLocationException(this.message);

  @override
  String toString() => message;
}

class OwnerTrackingSnapshot {
  final LatLng? ownerPosition;
  final LatLng? parkingPosition;
  final double? accuracy;
  final bool accuracyAccepted;
  final String status;
  final double? distanceFromParkingM;
  final DateTime? updatedAt;
  final DateTime? parkedAt;

  const OwnerTrackingSnapshot({
    required this.ownerPosition,
    required this.parkingPosition,
    required this.accuracy,
    required this.accuracyAccepted,
    required this.status,
    required this.distanceFromParkingM,
    required this.updatedAt,
    required this.parkedAt,
  });

  bool get hasParkingPosition => parkingPosition != null;
  bool get isNear => status == 'NEAR';
  bool get isAway => status == 'AWAY';

  factory OwnerTrackingSnapshot.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const OwnerTrackingSnapshot(
        ownerPosition: null,
        parkingPosition: null,
        accuracy: null,
        accuracyAccepted: false,
        status: 'UNKNOWN',
        distanceFromParkingM: null,
        updatedAt: null,
        parkedAt: null,
      );
    }

    final ownerLat = (json['latitude'] as num?)?.toDouble();
    final ownerLon = (json['longitude'] as num?)?.toDouble();
    final parkingLat = (json['parking_latitude'] as num?)?.toDouble();
    final parkingLon = (json['parking_longitude'] as num?)?.toDouble();

    return OwnerTrackingSnapshot(
      ownerPosition: ownerLat != null && ownerLon != null
          ? LatLng(ownerLat, ownerLon)
          : null,
      parkingPosition: parkingLat != null && parkingLon != null
          ? LatLng(parkingLat, parkingLon)
          : null,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      accuracyAccepted: (json['accuracy_accepted'] as bool?) ?? false,
      status: json['status']?.toString() ?? 'UNKNOWN',
      distanceFromParkingM:
          (json['distance_from_parking_m'] as num?)?.toDouble() ??
          (json['distance_from_vehicle'] as num?)?.toDouble(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      parkedAt: DateTime.tryParse(json['parked_at']?.toString() ?? ''),
    );
  }
}

class OwnerTrackingService {
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 1,
    timeLimit: Duration(seconds: 15),
  );

  static const LocationSettings _streamSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 1,
  );

  Future<Position> currentPosition() async {
    await _ensurePermission();
    return Geolocator.getCurrentPosition(locationSettings: _locationSettings);
  }

  Stream<Position> positionStream() async* {
    await _ensurePermission();
    yield* Geolocator.getPositionStream(locationSettings: _streamSettings);
  }

  static double distanceMeters(LatLng from, LatLng to) {
    return const Distance().as(LengthUnit.Meter, from, to);
  }

  Future<void> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const OwnerLocationException('Location service is disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const OwnerLocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const OwnerLocationException(
        'Location permission is permanently denied.',
      );
    }
  }
}
