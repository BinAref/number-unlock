// Renders the app icon from the game's own painters (golden lock, night
// sky, crystals) into assets/branding/ and web/icons/.
// Run: flutter test test_visual/icon_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/services/theme_service.dart';
import 'package:unlock_numbers/ui/kit/paint_kit.dart';
import 'package:unlock_numbers/ui/kit/world_objects.dart';

Future<void> _render(ThemeTokens t, int size, String path, {bool background = true, bool rounded = false, double inset = 0.1}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final s = size.toDouble();
  final rect = Offset.zero & Size(s, s);
  if (background) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(rounded ? s * 0.22 : 0));
    c.clipRRect(shape);
    c.drawRect(rect, Paint()..shader = gLinear(rect.topCenter, rect.bottomCenter, [t.color('sky.top'), t.color('sky.mid'), t.color('sky.horizon')]));
    for (var i = 0; i < 26; i++) {
      c.drawCircle(Offset(hashUnit(i, 3) * s, hashUnit(i, 7) * s * 0.6), s * (0.004 + 0.006 * hashUnit(i, 9)), Paint()..color = alpha(t.color('sky.star'), 0.5 + 0.5 * hashUnit(i, 5)));
    }
    paintGlow(c, Offset(s / 2, s * 0.56), s * 0.62, t.color('crystal.purple'), 0.8);
  }
  final box = s * (1 - inset * 2);
  c.save();
  c.translate(s * inset + box * 0.06, s * inset - box * 0.02);
  LockPainter(t, pulse: 0.8, open: 0.25).paint(c, Size(box * 0.88, box * 1.0));
  c.restore();
  for (var i = 0; i < 3; i++) {
    final a = -math.pi / 2 + (i - 1) * 0.9;
    paintGem(c, Offset(s / 2 + math.cos(a) * s * 0.4, s * 0.52 + math.sin(a) * s * 0.4), s * 0.035, t, crystal: i == 1 ? 'crystal.blue' : 'crystal.purple');
  }
  final image = await rec.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('render icons', (tester) async {
    final t = ThemeTokens.fromJson(jsonDecode(File('assets/themes/night.json').readAsStringSync()) as Map<String, Object?>, Brightness.dark);
    await tester.runAsync(() async {
      await _render(t, 1024, 'assets/branding/app_icon_1024.png');
      await _render(t, 1024, 'assets/branding/app_icon_foreground.png', background: false, inset: 0.24);
      await _render(t, 192, 'web/icons/Icon-192.png', rounded: true);
      await _render(t, 512, 'web/icons/Icon-512.png', rounded: true);
      await _render(t, 192, 'web/icons/Icon-maskable-192.png', inset: 0.18);
      await _render(t, 512, 'web/icons/Icon-maskable-512.png', inset: 0.18);
      await _render(t, 180, 'web/icons/apple-touch-icon.png');
      await _render(t, 64, 'web/favicon.png', rounded: true, inset: 0.04);
    });
  });
}
