import '../domain/models.dart';

/// Serializes a recorded run as a GPX 1.1 track.
class GpxExporter {
  String export(RunSession session, {String name = 'Course MapFollow'}) {
    final points = session.segments.expand((s) => s).toList();
    final distinct = <String>{
      for (final f in points) '${f.point.latitude},${f.point.longitude}',
    };
    if (distinct.length < 2) {
      throw const GpxExportException(
        'La sortie ne contient pas assez de points GPS pour créer un GPX.',
      );
    }
    final safeName =
        session.simulated && !name.toUpperCase().contains('SIMULATION')
        ? '$name SIMULATION'
        : name;
    final out = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n')
      ..writeln(
        '<gpx version="1.1" creator="MapFollow" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln(
        '  <metadata><name>${_escape(safeName)}</name><time>${session.startedAt.toUtc().toIso8601String()}</time></metadata>',
      )
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
        out.write(
          '<time>${fix.timestamp.toUtc().toIso8601String()}</time></trkpt>\n',
        );
      }
      out.writeln('    </trkseg>');
    }
    out.writeln('  </trk>\n</gpx>');
    return out.toString();
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String _number(double value) => value.toString();
}

class GpxExportException implements Exception {
  const GpxExportException(this.message);
  final String message;
  @override
  String toString() => message;
}
