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
    this.plannedRoute = false,
  });

  /// Absent au départ d'un Run libre : la carte attend alors sa première position.
  final domain.Route? route;
  final domain.LocationFix? fix;
  final List<List<domain.LocationFix>> recorded;
  final bool active;

  /// En guidage, le tracé source reste la référence verte, indépendamment de son historique.
  final bool plannedRoute;
  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final MapController _map = MapController();
  bool _ready = false, _follow = true, _tileError = false;
  bool _showOutbound = true, _showReturn = true;
  int _tileRevision = 0;
  late final List<LatLng> _routePoints;
  static LatLng _latLng(domain.RoutePoint p) => LatLng(p.latitude, p.longitude);
  @override
  void initState() {
    super.initState();
    _routePoints =
        widget.route?.segments.expand((s) => s.points).map(_latLng).toList() ??
        [];
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
          _map.move(
            _latLng(widget.fix!.point),
            oldWidget.fix == null && widget.route == null
                ? 16
                : _map.camera.zoom,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  List<LatLng> get _visiblePoints => _routePoints.isNotEmpty
      ? _routePoints
      : widget.recorded
            .expand((segment) => segment)
            .map((fix) => _latLng(fix.point))
            .toList();

  List<LatLng> get _initialPoints => _visiblePoints;

  bool get _classifiedRoute =>
      widget.route?.segments.any(
        (s) => s.points.any((p) => p.traversal != null),
      ) ??
      false;
  bool get _hasTraversal =>
      (_classifiedRoute && !widget.plannedRoute) ||
      widget.recorded.any((s) => s.any((p) => p.point.traversal != null));

  /// Chaque arête prend le sens de son arrivée ; la transition reste donc visible.
  /// Les segments source ne sont jamais joints, même lorsque leur sens est identique.
  List<Polyline> _classifiedLines(
    Iterable<List<domain.RoutePoint>> segments,
    domain.TraversalDirection? direction,
  ) {
    final lines = <Polyline>[];
    for (final points in segments) {
      var chain = <LatLng>[];
      void emit() {
        if (chain.length > 1) {
          lines.add(
            Polyline(
              points: chain,
              strokeWidth: direction == domain.TraversalDirection.outbound
                  ? 6
                  : direction == domain.TraversalDirection.returning
                  ? 3
                  : 4,
              color: direction == domain.TraversalDirection.outbound
                  ? Colors.blue
                  : direction == domain.TraversalDirection.returning
                  ? Colors.orange
                  : Colors.deepOrange,
              pattern: direction == domain.TraversalDirection.returning
                  ? StrokePattern.dashed(segments: const [8, 6])
                  : const StrokePattern.solid(),
            ),
          );
        }
        chain = [];
      }

      for (var i = 1; i < points.length; i++) {
        if (points[i].traversal == direction) {
          if (chain.isEmpty) chain.add(_latLng(points[i - 1]));
          chain.add(_latLng(points[i]));
        } else {
          emit();
        }
      }
      emit();
    }
    return lines;
  }

  List<Polyline> get _polylines {
    final classified = [
      if (_classifiedRoute && !widget.plannedRoute)
        ...widget.route!.segments.map((s) => s.points),
      ...widget.recorded.map((s) => s.map((p) => p.point).toList()),
    ];
    return [
      if (!_classifiedRoute || widget.plannedRoute)
        for (final segment in widget.route?.segments ?? <domain.RouteSegment>[])
          Polyline(
            points: segment.points.map(_latLng).toList(),
            strokeWidth: 5,
            color: const Color(0xff315d47),
          ),
      ..._classifiedLines(classified, null),
      if (_showOutbound)
        ..._classifiedLines(classified, domain.TraversalDirection.outbound),
      // Le retour passe au-dessus de tous les allers, y compris un troisième passage.
      if (_showReturn)
        ..._classifiedLines(classified, domain.TraversalDirection.returning),
    ];
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: widget.fix != null
              ? _latLng(widget.fix!.point)
              : _visiblePoints.isNotEmpty
              ? _visiblePoints.first
              : const LatLng(0, 0),
          initialZoom: _visiblePoints.isEmpty && widget.fix == null ? 3 : 15,
          initialCameraFit: _initialPoints.length < 2
              ? null
              : CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(_initialPoints),
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
          PolylineLayer(polylines: _polylines),
          MarkerLayer(
            markers: [
              if (_visiblePoints.isNotEmpty)
                Marker(
                  point: _visiblePoints.first,
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.flag, color: Colors.green, size: 30),
                ),
              if (_visiblePoints.isNotEmpty &&
                  (!widget.active || widget.route != null))
                Marker(
                  point: _visiblePoints.last,
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
      if (_hasTraversal)
        Positioned(
          bottom: 26,
          left: 8,
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.horizontal_rule, color: Colors.blue),
                label: const Text('Aller'),
                selected: _showOutbound,
                onSelected: (value) => setState(() => _showOutbound = value),
              ),
              FilterChip(
                avatar: const Icon(Icons.more_horiz, color: Colors.orange),
                label: const Text('Retour'),
                selected: _showReturn,
                onSelected: (value) => setState(() => _showReturn = value),
              ),
            ],
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
                widget.fix != null
                    ? _latLng(widget.fix!.point)
                    : _visiblePoints.isNotEmpty
                    ? _visiblePoints.first
                    : const LatLng(0, 0),
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
