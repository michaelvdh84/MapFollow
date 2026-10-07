import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/geo.dart';
import '../domain/map_guidance.dart';
import '../domain/models.dart';

abstract class MapGuidanceSource {
  Future<Route> prepare(Route route);
}

class MapGuidanceException implements Exception {
  const MapGuidanceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A single explicit, bounded corridor query. Coordinates are sent only when
/// prepare is invoked by the user. No automatic retries or tile downloading.
class OverpassMapGuidanceSource implements MapGuidanceSource {
  OverpassMapGuidanceSource({
    Uri? endpoint,
    Directory? cacheDirectory,
    Future<String> Function(Uri endpoint, String query)? download,
    DateTime Function()? clock,
  }) : endpoint =
           endpoint ??
           Uri.parse(
             const String.fromEnvironment(
               'MAPFOLLOW_OVERPASS_ENDPOINT',
               defaultValue: 'https://overpass-api.de/api/interpreter',
             ),
           ),
       _cacheDirectory = cacheDirectory,
       _downloadOverride = download,
       _clock = clock ?? DateTime.now;

  final Uri endpoint;
  final Directory? _cacheDirectory;
  final Future<String> Function(Uri, String)? _downloadOverride;
  final DateTime Function() _clock;
  static const maximumBytes = 6 * 1024 * 1024;
  static const cacheLifetime = Duration(days: 7);
  static const requestTimeout = Duration(seconds: 35);

  @override
  Future<Route> prepare(Route route) async {
    try {
      if (endpoint.scheme != 'https' ||
          endpoint.host.isEmpty ||
          endpoint.userInfo.isNotEmpty) {
        throw const MapGuidanceException(
          'Le service cartographique doit utiliser HTTPS.',
        );
      }
      final query = _query(route);
      Directory? directory;
      try {
        directory =
            _cacheDirectory ??
            Directory(
              path.join(
                (await getApplicationSupportDirectory()).path,
                'osm-guidance-cache',
              ),
            );
      } catch (_) {
        // Cache availability must not be a prerequisite for explicit preparation.
      }
      final key = _hash('${endpoint.toString()}\n$query');
      final file = directory == null
          ? null
          : File(path.join(directory.path, '$key.json'));
      final cached = await _readCache(file);
      if (cached != null) {
        try {
          return await _prepare(route, cached);
        } catch (_) {
          /* Fetch once below. */
        }
      }
      final response =
          await (_downloadOverride?.call(endpoint, query) ?? _download(query))
              .timeout(requestTimeout);
      if (utf8.encode(response).length > maximumBytes) {
        throw const MapGuidanceException(
          'Zone cartographique trop volumineuse.',
        );
      }
      final prepared = await _prepare(route, response);
      await _writeCache(file, response);
      return prepared;
    } on MapGuidanceException {
      rethrow;
    } on TimeoutException {
      throw const MapGuidanceException(
        'Le service cartographique ne répond pas. Réessayez manuellement.',
      );
    } on SocketException {
      throw const MapGuidanceException(
        'Service cartographique inaccessible. Vérifiez la connexion puis réessayez.',
      );
    } on FormatException {
      throw const MapGuidanceException(
        'Données cartographiques invalides ou zone trop étendue. Suivez le tracé.',
      );
    } catch (_) {
      // Never surface request URLs, coordinates, response bodies or raw OS errors.
      throw const MapGuidanceException(
        'Préparation indisponible. Suivez le tracé et réessayez manuellement.',
      );
    }
  }

  Future<Route> _prepare(Route route, String response) => compute(_prepareMap, (
    route,
    response,
    _clock(),
  ), debugLabel: 'osm-guidance');

  String _query(Route route) {
    if (route.segments.length > 100 || routeDistance(route) > 100000) {
      throw const MapGuidanceException(
        'La préparation est limitée aux parcours de 100 km et 100 segments.',
      );
    }
    final lines = <String>[];
    var count = 0;
    for (final segment in route.segments) {
      if (segment.points.length < 2) continue;
      final retained = <RoutePoint>[segment.points.first];
      for (final point in segment.points) {
        if (!point.latitude.isFinite ||
            !point.longitude.isFinite ||
            point.latitude.abs() > 85 ||
            point.longitude.abs() > 180) {
          throw const FormatException('Coordonnées invalides.');
        }
        if (distanceBetween(retained.last, point) >= 50) retained.add(point);
      }
      if (!identical(retained.last, segment.points.last)) {
        retained.add(segment.points.last);
      }
      count += retained.length;
      if (count > 2500) {
        throw const MapGuidanceException(
          'Parcours trop complexe pour cette préparation.',
        );
      }
      final coordinates = retained
          .map(
            (p) =>
                '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}',
          )
          .join(',');
      lines.add(
        'way[highway][highway!~"^(motorway|trunk|construction|proposed)"](around:80,$coordinates);',
      );
    }
    if (lines.isEmpty) {
      throw const MapGuidanceException(
        'Le parcours ne contient pas de chemin exploitable.',
      );
    }
    return '[out:json][timeout:25][maxsize:33554432];(${lines.join()} );(._;>;);out body;';
  }

  Future<String> _download(String query) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await _readResponse(client, query).timeout(requestTimeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readResponse(HttpClient client, String query) async {
    final request = await client.postUrl(endpoint);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'MapFollow/0.4 (personal route guidance)',
    );
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write('data=${Uri.encodeQueryComponent(query)}');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const MapGuidanceException(
        'Le service cartographique est indisponible ou occupé. Réessayez manuellement.',
      );
    }
    if (response.contentLength > maximumBytes) {
      throw const MapGuidanceException('Zone cartographique trop volumineuse.');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maximumBytes) {
        throw const MapGuidanceException(
          'Zone cartographique trop volumineuse.',
        );
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<String?> _readCache(File? file) async {
    if (file == null) return null;
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > maximumBytes ||
          _clock().difference(stat.modified) > cacheLifetime) {
        return null;
      }
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(File? file, String data) async {
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(data, flush: true);
      await temporary.rename(file.path);
      // Bound the app-owned cache to 24 MiB, oldest entries first.
      final entries = <(File, FileStat)>[];
      await for (final entry in file.parent.list()) {
        if (entry is File &&
            RegExp(
              r'^[0-9a-f]{16}\.json$',
            ).hasMatch(path.basename(entry.path))) {
          entries.add((entry, await entry.stat()));
        }
      }
      entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      var size = entries.fold(0, (sum, entry) => sum + entry.$2.size);
      for (final entry in entries) {
        if (size <= 24 * 1024 * 1024) break;
        if (entry.$1.path == file.path) continue;
        await entry.$1.delete();
        size -= entry.$2.size;
      }
    } catch (_) {
      /* Preparation succeeded; caching is best effort. */
    }
  }

  String _hash(String value) {
    var hash = 0x811c9dc5;
    var second = 0x9e3779b9;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
      second = ((second ^ byte) * 0x85ebca6b) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0') +
        second.toRadixString(16).padLeft(8, '0');
  }
}

Route _prepareMap((Route, String, DateTime) input) {
  final data = jsonDecode(input.$2);
  if (data is! Map<String, dynamic> || data['remark'] != null) {
    throw const FormatException('Réponse cartographique incomplète.');
  }
  return const OsmGuidanceBuilder().prepare(input.$1, data, now: input.$3);
}
