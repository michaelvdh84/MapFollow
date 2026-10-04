import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../domain/models.dart' as domain;

class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.route,
    required this.fix,
    required this.recorded,
    required this.active,
  });
  final domain.Route route;
  final domain.LocationFix? fix;
  final List<List<domain.LocationFix>> recorded;
  final bool active;
  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final MapController _map = MapController();
  bool _ready = false, _follow = true, _tileError = false;
  int _tileRevision = 0;
  late final List<LatLng> _routePoints;
  static LatLng _latLng(domain.RoutePoint p) => LatLng(p.latitude, p.longitude);
  @override
  void initState() {
    super.initState();
    _routePoints = widget.route.segments
        .expand((s) => s.points)
        .map(_latLng)
        .toList();
  }

  @override
  void didUpdateWidget(covariant RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready &&
        _follow &&
        widget.active &&
        widget.fix != null &&
        widget.fix != oldWidget.fix) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ready) {
          _map.move(_latLng(widget.fix!.point), _map.camera.zoom);
        }
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _routePoints.first,
          initialZoom: 15,
          initialCameraFit: _routePoints.length < 2
              ? null
              : CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(_routePoints),
                  padding: const EdgeInsets.all(35),
                  maxZoom: 17,
                ),
          maxZoom: 19,
          minZoom: 3,
          onMapReady: () => _ready = true,
          onPositionChanged: (_, gesture) {
            if (gesture && _follow) setState(() => _follow = false);
          },
        ),
        children: [
          TileLayer(
            key: ValueKey(_tileRevision),
            urlTemplate: const String.fromEnvironment(
              'MAP_TILE_URL',
              defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            userAgentPackageName: 'be.mapfollow.mapfollow',
            // No prefetch or offline packs: cache only what the runner views.
            panBuffer: 0,
            maxNativeZoom: 19,
            errorTileCallback: (_, _, _) {
              if (_tileError) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _tileError = true);
              });
            },
          ),
          PolylineLayer(
            polylines: [
              for (final segment in widget.route.segments)
                Polyline(
                  points: segment.points.map(_latLng).toList(),
                  strokeWidth: 5,
                  color: const Color(0xff315d47),
                ),
              for (final segment in widget.recorded.where((s) => s.length > 1))
                Polyline(
                  points: segment.map((p) => _latLng(p.point)).toList(),
                  strokeWidth: 4,
                  color: Colors.deepOrange,
                ),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _routePoints.first,
                width: 32,
                height: 32,
                child: const Icon(Icons.flag, color: Colors.green, size: 30),
              ),
              Marker(
                point: _routePoints.last,
                width: 32,
                height: 32,
                child: const Icon(Icons.flag, color: Colors.red, size: 30),
              ),
              if (widget.fix != null)
                Marker(
                  point: _latLng(widget.fix!.point),
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.white.withValues(alpha: .9),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const Text(
            '© OpenStreetMap contributors · ODbL',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: IconButton.filledTonal(
          tooltip: 'Recentrer et suivre la position',
          icon: Icon(_follow ? Icons.my_location : Icons.location_searching),
          onPressed: () {
            setState(() => _follow = true);
            if (_ready) {
              _map.move(
                widget.fix == null
                    ? _routePoints.first
                    : _latLng(widget.fix!.point),
                16,
              );
            }
          },
        ),
      ),
      if (_tileError)
        Positioned(
          top: 8,
          left: 8,
          right: 62,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Fond de carte indisponible. Le suivi GPS continue.',
                    style: TextStyle(fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _tileError = false;
                      _tileRevision++;
                    }),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
