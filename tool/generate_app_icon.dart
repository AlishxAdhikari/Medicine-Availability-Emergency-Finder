// Renders the launcher icon source images from the app's own logo painter.
//
// The icon is not a hand-drawn asset that can drift away from the mark on the
// splash and login screens: it is that same MedAlertMark, rendered to PNG. Run
// it after changing lib/widgets/medalert_mark.dart, then regenerate the
// platform icons:
//
//   flutter test tool/generate_app_icon.dart
//   dart run flutter_launcher_icons
//
// It lives in tool/ rather than test/ so `flutter test` does not rewrite
// binary assets on every run.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/theme.dart';
import 'package:medalert/widgets/medalert_mark.dart';

/// The full square icon, and the foreground layer Android's adaptive icon
/// masks. The foreground gets a much smaller mark because the launcher crops
/// aggressively toward the centre.
const double _canvas = 1024;

Future<void> _render(
  WidgetTester tester, {
  required String path,
  required Widget child,
}) async {
  // The RepaintBoundary is clipped to the test surface, so the surface has to
  // be at least icon-sized or the PNG comes out cropped to 800x600.
  await tester.binding.setSurfaceSize(const Size(_canvas, _canvas));

  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: _canvas, height: _canvas, child: child),
        ),
      ),
    ),
  );
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Encoding is real async work on the raster thread; under the test
  // binding's fake clock the futures below never complete, and the run hangs
  // instead of failing. runAsync gives them the real one.
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });

  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

/// The mark on the brand navy, inset so the magnifying glass -- which the
/// painter deliberately draws past the 120-unit box -- is not clipped.
Widget _icon({required Color background, required double inset}) {
  return ColoredBox(
    color: background,
    child: Center(
      child: MedAlertMark(
        size: _canvas * inset,
        color: Colors.white,
        holeColor: background,
      ),
    ),
  );
}

void main() {
  testWidgets('writes assets/icon/medalert_icon.png', (tester) async {
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await _render(
      tester,
      path: 'assets/icon/medalert_icon.png',
      child: _icon(background: MedAlertTheme.primaryLight, inset: 0.62),
    );

    await _render(
      tester,
      path: 'assets/icon/medalert_icon_foreground.png',
      child: _icon(background: MedAlertTheme.primaryLight, inset: 0.42),
    );

    expect(File('assets/icon/medalert_icon.png').existsSync(), isTrue);
    expect(
      File('assets/icon/medalert_icon_foreground.png').existsSync(),
      isTrue,
    );
  });
}
