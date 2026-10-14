import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/models.dart';
import '../services/favorite_db.dart';
import '../services/maps_api.dart';
import 'favorites_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _api = MapsApi();

  static const _hcm = LatLng(10.7769, 106.7009);
  static const _initialPosition = CameraPosition(target: _hcm, zoom: 14);

  LatLng? _start;
  LatLng? _end;
  TransportMode _mode = TransportMode.drive;
  List<RouteInfo> _routes = [];
  int _selected = 0;
  List<PlaceResult> _places = [];
  LatLng _cameraCenter = _hcm;
  bool _loading = false;

  static const _placeCategories = [
    ('Khách sạn', Icons.hotel),
    ('Quán ăn', Icons.restaurant),
    ('Bệnh viện', Icons.local_hospital),
    ('Trường học', Icons.school),
    ('Cây xăng', Icons.local_gas_station),
    ('ATM', Icons.atm),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _useCurrentLocation(true),
    );
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<LatLng?> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _toast('Vui lòng bật dịch vụ vị trí (GPS)!');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _toast('Ứng dụng chưa được cấp quyền vị trí.');
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  Future<void> _useCurrentLocation(bool isStart) async {
    setState(() => _loading = true);
    try {
      final p = await _getCurrentLocation();
      if (p == null) return;
      await _setPoint(isStart, p, label: 'Vị trí của tôi');
      _moveCamera(p, zoom: 15);
    } catch (e) {
      _toast('Không lấy được vị trí: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setPoint(bool isStart, LatLng p, {String? label}) async {
    final text = label ?? await _api.reverseGeocode(p) ?? _fmt(p);
    if (!mounted) return;
    setState(() {
      if (isStart) {
        _start = p;
        _startCtrl.text = text;
      } else {
        _end = p;
        _endCtrl.text = text;
      }
      _routes = [];
    });
  }

  String _fmt(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';

  Future<void> _onMapTap(LatLng p) async {
    FocusScope.of(context).unfocus();
    final isStart = await _askStartOrEnd(_fmt(p));
    if (isStart == null) return;
    await _setPoint(isStart, p);
  }

  Future<bool?> _askStartOrEnd(String title, {String? subtitle}) {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: subtitle == null ? null : Text(subtitle),
            ),
            ListTile(
              leading: const Icon(Icons.trip_origin, color: Colors.green),
              title: const Text('Đặt làm điểm xuất phát'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.place, color: Colors.red),
              title: const Text('Đặt làm điểm đích'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveCamera(LatLng p, {double? zoom}) async {
    final c = await _mapController.future;
    c.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(p)
          : CameraUpdate.newLatLngZoom(p, zoom),
    );
  }

  Future<void> _fitBounds(List<LatLng> pts) async {
    if (pts.isEmpty) return;
    if (pts.length == 1) return _moveCamera(pts.first, zoom: 15);
    double minLat = pts.first.latitude, maxLat = minLat;
    double minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final c = await _mapController.future;
    c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  Future<LatLng?> _resolve(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$')
        .firstMatch(t);
    if (m != null) {
      return LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!));
    }
    return _api.geocode(t);
  }

  Future<bool> _ensurePoints() async {
    if (_startCtrl.text.trim().isEmpty || _endCtrl.text.trim().isEmpty) {
      _toast('Vui lòng nhập cả hai điểm!');
      return false;
    }
    _start ??= await _resolve(_startCtrl.text);
    if (_start == null) {
      _toast('Không tìm thấy điểm xuất phát: "${_startCtrl.text}"');
      return false;
    }
    _end ??= await _resolve(_endCtrl.text);
    if (_end == null) {
      _toast('Không tìm thấy điểm đích: "${_endCtrl.text}"');
      return false;
    }
    return true;
  }

  Future<void> _findRoute() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      if (!await _ensurePoints()) return;
      final routes = await _api.computeRoutes(_start!, _end!, _mode);
      if (routes.isEmpty) {
        _toast('Không tìm thấy tuyến đường nào cho "${_mode.label}"!');
        setState(() => _routes = []);
        return;
      }
      routes.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
      setState(() {
        _routes = routes;
        _selected = 0;
        _places = [];
      });
      _fitBounds([...routes.first.points, _start!, _end!]);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compareModes() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final results = <TransportMode, RouteInfo?>{};
    try {
      if (!await _ensurePoints()) return;
      await Future.wait(
        TransportMode.values.map((m) async {
          try {
            final rs = await _api.computeRoutes(_start!, _end!, m);
            rs.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
            results[m] = rs.isEmpty ? null : rs.first;
          } catch (_) {
            results[m] = null;
          }
        }),
      );
    } catch (e) {
      _toast('$e');
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted || results.isEmpty) return;

    final valid = results.entries.where((e) => e.value != null).toList();
    final fastest = valid.isEmpty
        ? null
        : valid
              .reduce(
                (a, b) => a.value!.durationSeconds <= b.value!.durationSeconds
                    ? a
                    : b,
              )
              .key;

    final picked = await showDialog<TransportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('So sánh phương tiện'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TransportMode.values.map((m) {
            final r = results[m];
            return ListTile(
              leading: Icon(m.icon),
              title: Text(m.label + (m == fastest ? '  (nhanh nhất)' : '')),
              subtitle: Text(
                r == null
                    ? 'Không có tuyến'
                    : '${r.distanceText} · ${r.durationText}',
              ),
              selected: m == fastest,
              enabled: r != null,
              onTap: () => Navigator.pop(ctx, m),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
    if (picked != null) {
      setState(() => _mode = picked);
      _findRoute();
    }
  }

  Future<void> _searchPlaces(String query) async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final places = await _api.searchPlaces(query, _cameraCenter);
      if (places.isEmpty) _toast('Không tìm thấy "$query" quanh đây.');
      setState(() => _places = places);
      _fitBounds(places.map((p) => p.location).toList());
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _customPlaceSearch() async {
    final ctrl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tìm địa điểm'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'VD: cà phê, nhà thuốc...',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Tìm'),
          ),
        ],
      ),
    );
    if (q != null && q.trim().isNotEmpty) _searchPlaces(q.trim());
  }

  Future<void> _onPlaceTap(PlaceResult p) async {
    final isStart = await _askStartOrEnd(p.name, subtitle: p.address);
    if (isStart == null) return;
    await _setPoint(isStart, p.location, label: p.name);
  }

  Future<void> _saveFavorite() async {
    if (_routes.isEmpty || _start == null || _end == null) return;
    final r = _routes[_selected];
    final nameCtrl = TextEditingController(
      text: '${_short(_startCtrl.text)} → ${_short(_endCtrl.text)}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lưu tuyến yêu thích'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Tên tuyến'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await FavoriteDb.instance.insert(
      FavoriteRoute(
        name: name.trim(),
        startLabel: _startCtrl.text,
        endLabel: _endCtrl.text,
        start: _start!,
        end: _end!,
        mode: _mode,
        distanceMeters: r.distanceMeters,
        durationSeconds: r.durationSeconds,
        polyline: r.encodedPolyline,
        createdAt: DateTime.now(),
      ),
    );
    _toast('Đã lưu "$name" vào yêu thích');
  }

  String _short(String s) => s.split(',').first.trim();

  Future<void> _openFavorites() async {
    final fav = await Navigator.push<FavoriteRoute>(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );
    if (fav == null) return;
    final route = RouteInfo(
      points: decodePolyline(fav.polyline),
      encodedPolyline: fav.polyline,
      distanceMeters: fav.distanceMeters,
      durationSeconds: fav.durationSeconds,
      summary: fav.name,
    );
    setState(() {
      _start = fav.start;
      _end = fav.end;
      _startCtrl.text = fav.startLabel;
      _endCtrl.text = fav.endLabel;
      _mode = fav.mode;
      _routes = [route];
      _selected = 0;
      _places = [];
    });
    _fitBounds([...route.points, fav.start, fav.end]);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Set<Marker> get _markers {
    final s = <Marker>{};
    if (_start != null) {
      s.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _start!,
          infoWindow: InfoWindow(title: 'Xuất phát', snippet: _startCtrl.text),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }
    if (_end != null) {
      s.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _end!,
          infoWindow: InfoWindow(title: 'Đích đến', snippet: _endCtrl.text),
        ),
      );
    }
    for (final p in _places) {
      s.add(
        Marker(
          markerId: MarkerId('place_${p.id}'),
          position: p.location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: p.name,
            snippet: '${p.rating != null ? '★ ${p.rating}  ' : ''}Chạm để chọn',
            onTap: () => _onPlaceTap(p),
          ),
        ),
      );
    }
    return s;
  }

  Set<Polyline> get _polylines {
    final s = <Polyline>{};
    for (var i = 0; i < _routes.length; i++) {
      final sel = i == _selected;
      s.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: _routes[i].points,
          color: sel ? Colors.blue : Colors.grey,
          width: sel ? 6 : 4,
          zIndex: sel ? 2 : 1,
          consumeTapEvents: true,
          onTap: () => setState(() => _selected = i),
        ),
      );
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Navigator'),
        actions: [
          IconButton(
            tooltip: 'Tuyến yêu thích',
            icon: const Icon(Icons.favorite),
            onPressed: _openFavorites,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInputPanel(),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  padding: EdgeInsets.only(
                    top: 52,
                    bottom: _routes.isEmpty ? 0 : 120,
                  ),
                  onMapCreated: (c) {
                    if (!_mapController.isCompleted) _mapController.complete(c);
                  },
                  onCameraMove: (pos) => _cameraCenter = pos.target,
                  onTap: _onMapTap,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildPlaceChips(),
                ),
                if (_routes.isNotEmpty)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _buildRouteCard(),
                  ),
                if (_loading)
                  const Positioned(
                    top: 56,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputPanel() {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            TextField(
              controller: _startCtrl,
              onChanged: (_) => _start = null,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.trip_origin, color: Colors.green),
                labelText: 'Điểm xuất phát (địa chỉ hoặc lat, lng)',
                suffixIcon: IconButton(
                  tooltip: 'Dùng vị trí hiện tại',
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _useCurrentLocation(true),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _endCtrl,
              onChanged: (_) => _end = null,
              onSubmitted: (_) => _findRoute(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.place, color: Colors.red),
                labelText: 'Điểm đích (VD: 227 Nguyễn Văn Cừ, TP.HCM)',
                suffixIcon: IconButton(
                  tooltip: 'Vị trí hiện tại làm điểm đích',
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _useCurrentLocation(false),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TransportMode>(
                showSelectedIcon: false,
                segments: TransportMode.values
                    .map(
                      (m) => ButtonSegment(
                        value: m,
                        icon: Icon(m.icon),
                        label: Text(m.label),
                      ),
                    )
                    .toList(),
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() => _mode = s.first);
                  if (_routes.isNotEmpty) _findRoute();
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _findRoute,
                    icon: const Icon(Icons.directions),
                    label: const Text('Tìm đường đi'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _compareModes,
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('So sánh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceChips() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final (label, icon) in _placeCategories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                onPressed: () => _searchPlaces(label),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: const Icon(Icons.search, size: 18),
              label: const Text('Tìm khác...'),
              onPressed: _customPlaceSearch,
            ),
          ),
          if (_places.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.clear, size: 18),
              label: const Text('Xóa'),
              onPressed: () => setState(() => _places = []),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    final r = _routes[_selected];
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(_mode.icon, size: 32, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${r.durationText}  ·  ${r.distanceText}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    [
                      if (_selected == 0) 'Tuyến tối ưu',
                      if (r.summary != null && r.summary!.isNotEmpty)
                        r.summary!,
                      if (_routes.length > 1)
                        '${_routes.length} tuyến (chạm đường xám để đổi)',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Lưu yêu thích',
              icon: const Icon(Icons.star_border),
              onPressed: _saveFavorite,
            ),
          ],
        ),
      ),
    );
  }
}
