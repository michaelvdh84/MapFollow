import '../domain/models.dart';

/// Sérialise une course en trace GPX 1.1 avec les extensions MapFollow.
class GpxExporter {
  // Namespace versionné : les logiciels tiers peuvent ignorer ces extensions
  // et utiliser quand même les coordonnées, altitudes, dates et segments GPX.
  static const _mapFollowNamespace =
      'https://github.com/michaelvdh84/MapFollow/xmlns/1';

  String export(RunSession session, {String? name}) {
    final points = session.segments.expand((s) => s).toList();
    final distinct = <String>{
      for (final f in points) '${f.point.latitude},${f.point.longitude}',
    };
    if (distinct.length < 2) {
      throw const GpxExportException(
        'La sortie ne contient pas assez de points GPS pour créer un GPX.',
      );
    }
    final chosenName =
        name ?? (session.name.isEmpty ? 'Course MapFollow' : session.name);
    final safeName =
        session.simulated && !chosenName.toUpperCase().contains('SIMULATION')
        ? '$chosenName SIMULATION'
        : chosenName;
    final out = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n')
      ..writeln(
        '<gpx version="1.1" creator="MapFollow" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:mf="$_mapFollowNamespace" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(safeName)}</name>')
      ..writeln(
        '    <time>${session.startedAt.toUtc().toIso8601String()}</time>',
      )
      ..writeln(
        '    <extensions><mf:run mode="${session.mode.name}" activeSeconds="${session.activeSeconds}" distanceMeters="${_number(session.distance)}" simulated="${session.simulated}" locationProfile="${session.locationProfile.name}" traversalControl="${session.traversalControl.name}"${session.endedAt == null ? '' : ' endedAt="${session.endedAt!.toUtc().toIso8601String()}"'}/></extensions>',
      )
      ..writeln('  </metadata>')
      ..writeln('  <trk><name>${_escape(safeName)}</name>');
    for (final segment in session.segments) {
      if (segment.isEmpty) continue;
      out.writeln('    <trkseg>');
      for (final fix in segment) {
        final p = fix.point;
        out.write(
          '      <trkpt lat="${_number(p.latitude)}" lon="${_number(p.longitude)}">',
        );
        if (p.elevation != null && p.elevation!.isFinite) {
          out.write('<ele>${_number(p.elevation!)}</ele>');
        }
        out.write('<time>${fix.timestamp.toUtc().toIso8601String()}</time>');
        final fields = <String>[];
        if (fix.accuracy.isFinite && fix.accuracy >= 0) {
          fields.add(
            '<mf:accuracyMeters>${_number(fix.accuracy)}</mf:accuracyMeters>',
          );
        }
        final speed = fix.speed;
        if (speed != null && speed.isFinite && speed >= 0) {
          fields.add(
            '<mf:speedMetersPerSecond>${_number(speed)}</mf:speedMetersPerSecond>',
          );
        }
        if (p.traversal != null) {
          fields.add(
            '<mf:traversalDirection>${p.traversal!.name}</mf:traversalDirection>',
          );
        }
        final heading = fix.heading;
        if (heading != null &&
            heading.isFinite &&
            heading >= 0 &&
            heading < 360) {
          fields.add(
            '<mf:headingDegrees>${_number(heading)}</mf:headingDegrees>',
          );
        }
        if (fields.isNotEmpty) {
          out.write('<extensions>${fields.join()}</extensions>');
        }
        out.writeln('</trkpt>');
      }
      out.writeln('    </trkseg>');
    }
    out.writeln('  </trk>\n</gpx>');
    return out.toString();
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  String _number(double value) => value.toString();
}

class GpxExportException implements Exception {
  const GpxExportException(this.message);
  final String message;
  @override
  String toString() => message;
}
