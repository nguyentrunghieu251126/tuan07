import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum TransportMode {
  drive('Ô tô', Icons.directions_car, 'DRIVE', 'driving'),
  twoWheeler('Xe máy', Icons.two_wheeler, 'TWO_WHEELER', 'driving'),
  walk('Đi bộ', Icons.directions_walk, 'WALK', 'walking');

  const TransportMode(
    this.label,
    this.icon,
    this.routesApi,
    this.directionsApi,
  );

  final String label;
  final IconData icon;
  final String routesApi;
  final String directionsApi;

  static TransportMode fromName(String name) => TransportMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => TransportMode.drive,
  );
}

class RouteInfo {
  final List<LatLng> points;
  final String encodedPolyline;
  final int distanceMeters;
  final int durationSeconds;
  final String? summary;

  RouteInfo({
    required this.points,
    required this.encodedPolyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.summary,
  });

  String get distanceText => formatDistance(distanceMeters);
  String get durationText => formatDuration(durationSeconds);
}

String formatDistance(int m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '$m m';

String formatDuration(int s) {
  final h = s ~/ 3600;
  final m = ((s % 3600) / 60).round();
  if (h > 0) return '$h giờ $m phút';
  return '${m < 1 ? 1 : m} phút';
}

class PlaceResult {
  final String id;
  final String name;
  final String address;
  final LatLng location;
  final double? rating;

  PlaceResult({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.rating,
  });
}

class FavoriteRoute {
  final int? id;
  final String name;
  final String startLabel;
  final String endLabel;
  final LatLng start;
  final LatLng end;
  final TransportMode mode;
  final int distanceMeters;
  final int durationSeconds;
  final String polyline;
  final DateTime createdAt;

  FavoriteRoute({
    this.id,
    required this.name,
    required this.startLabel,
    required this.endLabel,
    required this.start,
    required this.end,
    required this.mode,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'start_label': startLabel,
    'end_label': endLabel,
    'start_lat': start.latitude,
    'start_lng': start.longitude,
    'end_lat': end.latitude,
    'end_lng': end.longitude,
    'mode': mode.name,
    'distance_m': distanceMeters,
    'duration_s': durationSeconds,
    'polyline': polyline,
    'created_at': createdAt.toIso8601String(),
  };

  factory FavoriteRoute.fromMap(Map<String, Object?> m) => FavoriteRoute(
    id: m['id'] as int?,
    name: m['name'] as String,
    startLabel: m['start_label'] as String,
    endLabel: m['end_label'] as String,
    start: LatLng(
      (m['start_lat'] as num).toDouble(),
      (m['start_lng'] as num).toDouble(),
    ),
    end: LatLng(
      (m['end_lat'] as num).toDouble(),
      (m['end_lng'] as num).toDouble(),
    ),
    mode: TransportMode.fromName(m['mode'] as String),
    distanceMeters: m['distance_m'] as int,
    durationSeconds: m['duration_s'] as int,
    polyline: m['polyline'] as String,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}
