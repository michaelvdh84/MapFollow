import 'package:flutter/material.dart';
import 'application/run_controller.dart';
import 'data/repository.dart';
import 'data/voice_service.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await SqliteRunRepository.open();
    final controller = RunController(
      repository: repository,
      voice: DeviceVoiceService(),
    );
    runApp(MapFollowApp(controller: controller));
    await controller.perform(controller.initialize);
  } catch (_) {
    // Do not expose database errors (which may contain location payloads).
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Impossible d’ouvrir les données locales. Vérifiez l’espace de stockage, puis relancez MapFollow. Vos données existantes sont conservées.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
