import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../services/theme_service.dart';

/// Deterministic 0..1 noise from integers (same art on every run).
double hashUnit(int a, [int b = 0, int c = 0]) {
  var h = (a * 374761393 + b * 668265263 + c * 2147483647) & 0x7FFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF;
  h = h ^ (h >> 16);
  return (h & 0xFFFF) / 65535.0;
}

Color alpha(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));

Color mix(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0.0, 1.0))!;

/// A soft radial light.
void paintGlow(Canvas canvas, Offset center, double radius, Color color, [double strength = 1]) {
  if (radius <= 0 || strength <= 0) return;
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = gRadial(center, radius, [alpha(color, 0.6 * strength), alpha(color, 0.18 * strength), alpha(color, 0)], [0, 0.45, 1]),
  );
}

/// Stone masonry filling [rrect]: staggered blocks with mortar, per-block
/// shading and the blue / purple stones of the world.
void paintStoneWall(Canvas canvas, RRect rrect, ThemeTokens t, {int seed = 1, double block = 26, double accent = 0.22}) {
  canvas.save();
  canvas.clipRRect(rrect);
  final r = rrect.outerRect;
  canvas.drawRect(r, Paint()..color = t.color('stone.mortar'));
  final h = block * 0.62;
  final w = block * 1.3;
  final light = t.color('stone.light');
  final base = t.color('stone.base');
  final dark = t.color('stone.dark');
  final blue = t.color('stone.blue');
  final purple = t.color('stone.purple');
  final gap = math.max(1.0, block * 0.05);
  var row = 0;
  for (var y = r.top - h * 0.3; y < r.bottom; y += h, row++) {
    final shift = row.isOdd ? w * 0.5 : 0.0;
    var col = 0;
    for (var x = r.left - shift; x < r.right; x += w, col++) {
      final u = hashUnit(seed * 131 + row, col);
      var c = mix(base, u < 0.5 ? light : dark, (u - 0.5).abs() * 0.8);
      final tint = hashUnit(seed * 7 + col, row * 3, seed);
      if (tint < accent) c = mix(c, tint < accent / 2 ? blue : purple, 0.38);
      final rect = Rect.fromLTWH(x + gap, y + gap, w - gap * 2, h - gap * 2);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.24));
      canvas.drawRRect(
        rr,
        Paint()..shader = gLinear(rect.topCenter, rect.bottomCenter, [mix(c, light, 0.38), c, mix(c, dark, 0.42)], [0, 0.45, 1]),
      );
      canvas.drawLine(
        rect.topLeft + Offset(h * 0.3, 1),
        rect.topRight + Offset(-h * 0.3, 1),
        Paint()
          ..color = alpha(light, 0.5)
          ..strokeWidth = 1,
      );
    }
  }
  canvas.drawRect(
    r,
    Paint()
      ..shader = gLinear(r.topCenter, r.bottomCenter, [alpha(light, 0.12), alpha(dark, 0), alpha(t.color('stone.deep'), 0.38)], [0, 0.5, 1]),
  );
  canvas.restore();
}

/// A polished gold rim around [rrect].
void paintGoldEdge(Canvas canvas, RRect rrect, ThemeTokens t, {double width = 4}) {
  final r = rrect.outerRect;
  canvas.drawRRect(
    rrect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 2
      ..color = t.color('gold.deep'),
  );
  canvas.drawRRect(
    rrect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = gLinear(r.topLeft, r.bottomRight,
          [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark'), t.color('gold.base'), t.color('gold.light')], [0, 0.3, 0.55, 0.8, 1]),
  );
  canvas.drawRRect(
    rrect.deflate(width * 0.3),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = alpha(t.color('gold.light'), 0.55),
  );
}

/// A carved, recessed surface (inside frames, sockets and panels).
void paintRecess(Canvas canvas, RRect rrect, ThemeTokens t, {Color? top, Color? bottom}) {
  final r = rrect.outerRect;
  canvas.drawRRect(
    rrect,
    Paint()..shader = gLinear(r.topCenter, r.bottomCenter, [top ?? t.color('ui.panelDeep'), bottom ?? t.color('ui.panel')]),
  );
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRRect(
    rrect.shift(const Offset(0, 3)).inflate(3),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = alpha(t.color('text.shadow'), 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  canvas.restore();
}

void paintDropShadow(Canvas canvas, RRect rrect, ThemeTokens t, {double dy = 6, double blur = 10}) {
  canvas.drawRRect(
    rrect.shift(Offset(0, dy)),
    Paint()
      ..color = alpha(t.color('text.shadow'), t.number('world.shadowStrength', 0.3))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );
}

/// A gold stud with a crystal heart (frame corners, ornaments).
void paintGem(Canvas canvas, Offset c, double r, ThemeTokens t, {String crystal = 'crystal.blue', double glow = 0.6}) {
  paintGlow(canvas, c, r * 2.6, t.color(crystal), glow * t.number('crystal.intensity', 0.6));
  canvas.drawCircle(
    c,
    r,
    Paint()..shader = gRadial(c - Offset(r * 0.3, r * 0.3), r * 1.4, [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')], [0, 0.5, 1]),
  );
  canvas.drawCircle(
    c,
    r * 0.55,
    Paint()..shader = gRadial(c - Offset(r * 0.18, r * 0.2), r * 0.7, [t.color('crystal.glow'), t.color(crystal)], [0, 1]),
  );
}

/// The carved stone frame of panels, the board and dialogs.
///
/// Built from repeated blocks with independent corners and edges, so it
/// stretches to any size without distortion (a code nine-slice).
class StoneFramePainter extends CustomPainter {
  StoneFramePainter(this.t, {this.border = 14, this.radius = 22, this.seed = 3, this.recess = true, this.gems = true});

  final ThemeTokens t;
  final double border;
  final double radius;
  final int seed;
  final bool recess;
  final bool gems;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    paintDropShadow(canvas, outer, t);
    paintStoneWall(canvas, outer, t, seed: seed, block: border * 1.7);
    final inner = outer.deflate(border);
    if (recess) paintRecess(canvas, inner, t);
    paintGoldEdge(canvas, inner, t, width: 2.6);
    paintGoldEdge(canvas, outer.deflate(1.2), t, width: 1.6);
    if (gems && size.shortestSide > border * 4) {
      final d = border * 0.5;
      final r = border * 0.34;
      for (final c in [Offset(d, d), Offset(size.width - d, d), Offset(d, size.height - d), Offset(size.width - d, size.height - d)]) {
        paintGem(canvas, c, r, t);
      }
    }
  }

  @override
  bool shouldRepaint(StoneFramePainter old) => old.t != t || old.border != border || old.radius != radius || old.recess != recess;
}

/// A minted gold coin.
void paintCoin(Canvas canvas, Offset c, double r, ThemeTokens t, {double shine = 0}) {
  canvas.drawCircle(c + Offset(0, r * 0.12), r, Paint()..color = t.color('gold.deep'));
  canvas.drawCircle(
    c,
    r,
    Paint()..shader = gRadial(c - Offset(r * 0.35, r * 0.4), r * 1.5, [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')], [0, 0.55, 1]),
  );
  canvas.drawCircle(
    c,
    r * 0.72,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..color = alpha(t.color('gold.dark'), 0.7),
  );
  final p = Path()
    ..moveTo(c.dx, c.dy - r * 0.42)
    ..lineTo(c.dx + r * 0.3, c.dy)
    ..lineTo(c.dx, c.dy + r * 0.42)
    ..lineTo(c.dx - r * 0.3, c.dy)
    ..close();
  canvas.drawPath(p, Paint()..color = alpha(t.color('gold.light'), 0.9));
  if (shine > 0) {
    final s = r * (0.35 + 0.25 * shine);
    final o = c + Offset(-r * 0.35, -r * 0.4);
    final star = Path()
      ..moveTo(o.dx, o.dy - s)
      ..lineTo(o.dx + s * 0.18, o.dy - s * 0.18)
      ..lineTo(o.dx + s, o.dy)
      ..lineTo(o.dx + s * 0.18, o.dy + s * 0.18)
      ..lineTo(o.dx, o.dy + s)
      ..lineTo(o.dx - s * 0.18, o.dy + s * 0.18)
      ..lineTo(o.dx - s, o.dy)
      ..lineTo(o.dx - s * 0.18, o.dy - s * 0.18)
      ..close();
    canvas.drawPath(star, Paint()..color = alpha(const Color(0xFFFFFFFF), 0.85 * shine));
  }
}

Path starPath(Offset c, double r, {double inner = 0.45, int points = 5}) {
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final rad = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

void paintStar(Canvas canvas, Offset c, double r, ThemeTokens t, {required bool filled}) {
  final path = starPath(c, r);
  canvas.drawPath(path.shift(Offset(0, r * 0.12)), Paint()..color = alpha(t.color('text.shadow'), 0.55));
  if (filled) {
    paintGlow(canvas, c, r * 1.8, t.color('gold.glow'), 0.5);
    canvas.drawPath(path, Paint()..shader = gLinear(c - Offset(0, r), c + Offset(0, r), [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')]));
  } else {
    canvas.drawPath(path, Paint()..color = t.color('stone.dark'));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.12..color = t.color('stone.base'));
  }
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = alpha(filled ? t.color('gold.deep') : t.color('stone.deep'), 0.9),
  );
}

List<double>? _evenStops(int n) => n <= 2 ? null : [for (var i = 0; i < n; i++) i / (n - 1)];

/// Gradients that space their colours evenly unless stops are given.
ui.Gradient gLinear(Offset from, Offset to, List<Color> colors, [List<double>? stops]) =>
    ui.Gradient.linear(from, to, colors, stops ?? _evenStops(colors.length));

ui.Gradient gRadial(Offset center, double radius, List<Color> colors, [List<double>? stops]) =>
    ui.Gradient.radial(center, radius, colors, stops ?? _evenStops(colors.length));

ui.Gradient gSweep(Offset center, List<Color> colors, [List<double>? stops]) =>
    ui.Gradient.sweep(center, colors, stops ?? _evenStops(colors.length));