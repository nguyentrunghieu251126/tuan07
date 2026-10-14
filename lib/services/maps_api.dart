import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class MapsApi {
  final String key;
  MapsApi({this.key = kGoogleApiKey});

  Future<LatLng?> geocode(String address) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address,
      'key': key,
      'language': 'vi',
      'region': 'vn',
    });
    final data = await _getJson(uri);
    _checkStatus(data, 'Geocoding API');
    final results = data['results'] as List;
    if (results.isEmpty) return null;
    final loc = results[0]['geometry']['location'];
    return LatLng(
      (loc['lat'] as num).toDouble(),
      (loc['lng'] as num).toDouble(),
    );
  }

  Future<String?> reverseGeocode(LatLng p) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${p.latitude},${p.longitude}',
        'key': key,
        'language': 'vi',
      });
      final data = await _getJson(uri);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      return results[0]['formatted_address'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<List<RouteInfo>> computeRoutes(
    LatLng origin,
    LatLng dest,
    TransportMode mode,
  ) async {
    try {
      return await _routesApi(origin, dest, mode);
    } on ApiException catch (e) {
      try {
        return await _directionsApi(origin, dest, mode);
      } catch (_) {
        throw e;
      }
    }
  }

  Future<List<RouteInfo>> _routesApi(
    LatLng o,
    LatLng d,
    TransportMode mode,
  ) async {
    final body = {
      'origin': _waypoint(o),
      'destination': _waypoint(d),
      'travelMode': mode.routesApi,
      'computeAlternativeRoutes': true,
      'languageCode': 'vi',
      'regionCode': 'VN',
      'units': 'METRIC',
      if (mode != TransportMode.walk) 'routingPreference': 'TRAFFIC_AWARE',
    };
    final res = await http.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: _headers(
        'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.description',
      ),
      body: jsonEncode(body),
    );
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(
        'Routes API: ${data['error']?['message'] ?? 'HTTP ${res.statusCode}'}',
      );
    }
    final routes = (data['routes'] as List?) ?? [];
    return routes.map((r) {
      final enc = r['polyline']['encodedPolyline'] as String;
      return RouteInfo(
        points: decodePolyline(enc),
        encodedPolyline: enc,
        distanceMeters: (r['distanceMeters'] as num?)?.toInt() ?? 0,
        durationSeconds:
            int.tryParse(
              (r['duration'] as String? ?? '0s').replaceAll('s', ''),
            ) ??
            0,
        summary: r['description'] as String?,
      );
    }).toList();
  }

  Future<List<RouteInfo>> _directionsApi(
    LatLng o,
    LatLng d,
    TransportMode mode,
  ) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${o.latitude},${o.longitude}',
      'destination': '${d.latitude},${d.longitude}',
      'mode': mode.directionsApi,
      'alternatives': 'true',
      'language': 'vi',
      'key': key,
    });
    final data = await _getJson(uri);
    _checkStatus(data, 'Directions API');
    final routes = (data['routes'] as List?) ?? [];
    return routes.map((r) {
      final leg = r['legs'][0];
      final enc = r['overview_polyline']['points'] as String;
      return RouteInfo(
        points: decodePolyline(enc),
        encodedPolyline: enc,
        distanceMeters: (leg['distance']['value'] as num).toInt(),
        durationSeconds: (leg['duration']['value'] as num).toInt(),
        summary: r['summary'] as String?,
      );
    }).toList();
  }

  Future<List<PlaceResult>> searchPlaces(String query, LatLng center) async {
    final res = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:searchText'),
      headers: _headers(
        'places.id,places.displayName,places.formattedAddress,places.location,places.rating',
      ),
      body: jsonEncode({
        'textQuery': query,
        'languageCode': 'vi',
        'regionCode': 'VN',
        'locationBias': {
          'circle': {
            'center': {
              'latitude': center.latitude,
              'longitude': center.longitude,
            },
            'radius': 3000.0,
          },
        },
      }),
    );
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(
        'Places API: ${data['error']?['message'] ?? 'HTTP ${res.statusCode}'}',
      );
    }
    final places = (data['places'] as List?) ?? [];
    return places.map((p) {
      final loc = p['location'];
      return PlaceResult(
        id: p['id'] as String,
        name: p['displayName']?['text'] as String? ?? 'Không tên',
        address: p['formattedAddress'] as String? ?? '',
        location: LatLng(
          (loc['latitude'] as num).toDouble(),
          (loc['longitude'] as num).toDouble(),
        ),
        rating: (p['rating'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Map<String, String> _headers(String fieldMask) => {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': key,
    'X-Goog-FieldMask': fieldMask,
  };

  Map<String, dynamic> _waypoint(LatLng p) => {
    'location': {
      'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
    },
  };

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw ApiException('Lỗi khi gọi API: ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  void _checkStatus(Map<String, dynamic> data, String api) {
    final status = data['status'] as String?;
    if (status == 'OK' || status == 'ZERO_RESULTS') return;
    throw ApiException('$api: $status ${data['error_message'] ?? ''}'.trim());
  }
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  final len = encoded.length;
  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
}
