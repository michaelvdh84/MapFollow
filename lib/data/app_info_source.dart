import 'dart:io';

import 'package:flutter/services.dart';

/// Read the installed package metadata; never maintain a second version label.
class AndroidAppInfoSource {
  static const _channel = MethodChannel('mapfollow/appInfo');

  Future<String?> readVersion() async {
    try {
      if (!Platform.isAndroid) return null;
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'getVersion',
      );
      final version = info?['versionName'], build = info?['buildNumber'];
      if (version is! String ||
          version.isEmpty ||
          build is! String ||
          build.isEmpty) {
        return null;
      }
      return '$version+$build';
    } catch (_) {
      // Unsupported platforms and tests show an unavailable version rather
      // than an invented number. This read must not prevent starting the app.
      return null;
    }
  }
}
