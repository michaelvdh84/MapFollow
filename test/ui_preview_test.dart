import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/presentation/app.dart';
import 'fakes.dart';

void main() {
  testWidgets('phone-sized French screens have no layout exceptions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final sdk = Platform.environment['FLUTTER_ROOT'] ?? '.tools/flutter';
      for (final font in [
        ('Roboto', 'roboto-regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final file = File('$sdk/bin/cache/artifacts/material_fonts/${font.$2}');
        if (await file.exists()) {
          final loader = FontLoader(font.$1)
            ..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())),
            );
          await loader.load();
        }
      }
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryRepository();
    final controller = RunController(
      repository: repository,
      voice: FakeVoice(),
    );
    await controller.initialize();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MapFollowApp(controller: controller),
      ),
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/previews');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('library');
    await tester.tap(find.text('Réglages'));
    await capture('settings');
    await tester.tap(find.text('Historique'));
    await capture('history');
    await tester.pumpWidget(const SizedBox());
    await controller.shutdown();
    controller.dispose();
  });
}
