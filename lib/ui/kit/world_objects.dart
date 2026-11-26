import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import 'paint_kit.dart';
import 'widgets.dart';

/// Repeats [builder] with a 0..1 phase (frozen when effects are reduced).
class Loop extends StatefulWidget {
  const Loop({super.key, required this.period, required this.builder});

  final Duration period;
  final Widget Function(BuildContext context, double phase) builder;

  @override
  State<Loop> createState() => _LoopState();
}

class _LoopState extends State<Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Services.of(context).reducedEffects || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (reduced) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value));
}

double _wave(double phase, [double cycles = 1]) => math.sin(phase * math.pi * 2 * cycles);

/// A round stone pedestal that objects stand on.
void paintPedestal(Canvas c, Rect r, ThemeTokens t) {
  final top = Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.42);
  final side = Path()
    ..moveTo(r.left, top.center.dy)
    ..lineTo(r.left + r.width * 0.06, r.bottom - r.height * 0.18)
    ..quadraticBezierTo(r.center.dx, r.bottom + r.height * 0.1, r.right - r.width * 0.06, r.bottom - r.height * 0.18)
    ..lineTo(r.right, top.center.dy)
    ..close();
  c.drawPath(side.shift(const Offset(0, 5)), Paint()..color = alpha(t.color('text.shadow'), 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  c.drawPath(side, Paint()..shader = gLinear(r.topCenter, r.bottomCenter, [t.color('stone.base'), t.color('stone.deep')]));
  for (var k = 1; k < 5; k++) {
    final x = r.left + r.width * k / 5;
    c.drawLine(Offset(x, top.center.dy + 2), Offset(x + (k - 2.5) * 2, r.bottom - r.height * 0.12), Paint()..color = alpha(t.color('stone.mortar'), 0.6)..strokeWidth = 1.4);
  }
  c.drawOval(top, Paint()..shader = gLinear(top.topCenter, top.bottomCenter, [t.color('stone.light'), t.color('stone.base')]));
  c.drawOval(top, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = t.color('gold.base'));
  c.drawOval(top.deflate(top.height * 0.22), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = alpha(t.color('crystal.blue'), 0.5 * t.number('crystal.intensity', 0.6) + 0.2));
}

/// The great golden padlock (play / continue).
class LockPainter extends CustomPainter {
  LockPainter(this.t, {required this.pulse, required this.open});

  final ThemeTokens t;
  final double pulse;
  final double open;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.12, h * 0.4, w * 0.76, h * 0.56), Radius.circular(w * 0.16));
    paintGlow(canvas, body.center, w * (0.7 + 0.08 * pulse), t.color('gold.glow'), 0.55 + 0.35 * pulse);
    final lift = open * h * 0.14;
    final shackle = Path()
      ..moveTo(w * 0.27, h * 0.46 - lift)
      ..lineTo(w * 0.27, h * 0.3 - lift)
      ..arcToPoint(Offset(w * 0.73, h * 0.3 - lift * (1 - open * 0.4)), radius: Radius.circular(w * 0.23))
      ..lineTo(w * 0.73, h * 0.46 - lift * (1 - open));
    canvas.drawPath(shackle, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.13..strokeCap = StrokeCap.round..color = t.color('gold.deep'));
    canvas.drawPath(
      shackle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.1
        ..strokeCap = StrokeCap.round
        ..shader = gLinear(Offset(w * 0.27, 0), Offset(w * 0.73, 0), [t.color('gold.dark'), t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')], [0, 0.35, 0.6, 1]),
    );
    paintDropShadow(canvas, body, t, dy: 7, blur: 10);
    canvas.drawRRect(body, Paint()..shader = gLinear(body.outerRect.topLeft, body.outerRect.bottomRight, [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')], [0, 0.45, 1]));
    canvas.drawRRect(body.deflate(w * 0.04), Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.025..color = alpha(t.color('gold.deep'), 0.7));
    canvas.drawRRect(body.deflate(w * 0.065), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = alpha(t.color('gold.light'), 0.8));
    final kc = Offset(w * 0.5, body.outerRect.top + body.outerRect.height * 0.36);
    canvas.drawCircle(kc, w * 0.07, Paint()..color = t.color('gold.deep'));
    canvas.drawPath(
      Path()
        ..moveTo(kc.dx - w * 0.03, kc.dy)
        ..lineTo(kc.dx - w * 0.05, kc.dy + w * 0.13)
        ..lineTo(kc.dx + w * 0.05, kc.dy + w * 0.13)
        ..lineTo(kc.dx + w * 0.03, kc.dy)
        ..close(),
      Paint()..color = t.color('gold.deep'),
    );
    paintGlow(canvas, kc, w * 0.12, t.color('crystal.blue'), 0.4 + 0.4 * pulse);
    for (final x in [0.22, 0.78]) {
      paintGem(canvas, Offset(w * x, body.outerRect.top + w * 0.1), w * 0.035, t, crystal: 'crystal.purple');
    }
  }

  @override
  bool shouldRepaint(LockPainter old) => old.pulse != pulse || old.open != open || old.t != t;
}

/// The settings gear, set into a stone niche.
class GearPainter extends CustomPainter {
  GearPainter(this.t, this.angle);

  final ThemeTokens t;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.4;
    final niche = RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: r * 1.18), Radius.circular(r * 0.5));
    paintStoneWall(canvas, niche, t, seed: 21, block: r * 0.5);
    paintGoldEdge(canvas, niche, t, width: 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final teeth = Path();
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5;
      teeth.addPolygon([
        for (final (da, rr) in [(-0.13, r * 0.78), (-0.09, r), (0.09, r), (0.13, r * 0.78)]) Offset(math.cos(a + da) * rr, math.sin(a + da) * rr),
      ], true);
    }
    final gear = Path.combine(PathOperation.union, teeth, Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r * 0.8)));
    canvas.drawPath(gear.shift(const Offset(2, 3)), Paint()..color = alpha(t.color('text.shadow'), 0.4));
    canvas.drawPath(gear, Paint()..shader = gRadial(Offset(-r * 0.3, -r * 0.3), r * 1.4, [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')]));
    canvas.drawCircle(Offset.zero, r * 0.5, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.08..color = t.color('gold.dark'));
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + math.pi / 4;
      canvas.drawCircle(Offset(math.cos(a), math.sin(a)) * r * 0.5, r * 0.08, Paint()..color = t.color('gold.deep'));
    }
    canvas.restore();
    paintGem(canvas, c, r * 0.22, t);
  }

  @override
  bool shouldRepaint(GearPainter old) => old.angle != angle || old.t != t;
}

/// The magic book of instructions on its lectern.
class BookPainter extends CustomPainter {
  BookPainter(this.t, {required this.open, required this.flutter});

  final ThemeTokens t;
  final double open;
  final double flutter;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    paintPedestal(canvas, Rect.fromLTWH(w * 0.16, h * 0.62, w * 0.68, h * 0.36), t);
    final spine = Offset(w * 0.5, h * 0.56);
    final bw = w * 0.42 * (0.55 + 0.45 * open);
    final bh = h * 0.42;
    paintGlow(canvas, spine - Offset(0, bh * 0.4), w * 0.55, t.color('crystal.purple'), 0.35 + 0.3 * open);
    for (final dir in [-1.0, 1.0]) {
      final cover = Path()
        ..moveTo(spine.dx, spine.dy)
        ..lineTo(spine.dx + dir * bw, spine.dy - bh * 0.12)
        ..lineTo(spine.dx + dir * bw, spine.dy - bh)
        ..lineTo(spine.dx, spine.dy - bh * 0.88)
        ..close();
      canvas.drawPath(cover, Paint()..shader = gLinear(Offset(spine.dx, spine.dy - bh), spine, [t.color('stone.purple'), t.color('ui.panelDeep')]));
      canvas.drawPath(cover, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = t.color('gold.base'));
      final page = Path()
        ..moveTo(spine.dx, spine.dy - bh * 0.06)
        ..lineTo(spine.dx + dir * bw * 0.9, spine.dy - bh * 0.16)
        ..lineTo(spine.dx + dir * bw * 0.9, spine.dy - bh * 0.92)
        ..lineTo(spine.dx, spine.dy - bh * 0.82)
        ..close();
      canvas.drawPath(page, Paint()..color = mix(t.color('gold.light'), const Color(0xFFFFFFFF), 0.5));
      for (var k = 1; k < 5; k++) {
        final y = spine.dy - bh * (0.2 + 0.14 * k);
        canvas.drawLine(Offset(spine.dx + dir * bw * 0.15, y), Offset(spine.dx + dir * bw * 0.75, y - bh * 0.03), Paint()..color = alpha(t.color('stone.dark'), 0.35)..strokeWidth = 1.2);
      }
    }
    final lift = (flutter * 0.5 + 0.5) * open;
    final flying = Path()
      ..moveTo(spine.dx, spine.dy - bh * 0.06)
      ..quadraticBezierTo(spine.dx + bw * 0.4, spine.dy - bh * (0.4 + 0.5 * lift), spine.dx + bw * 0.86 * (1 - lift), spine.dy - bh * (0.2 + 0.7 * lift))
      ..lineTo(spine.dx + bw * 0.86 * (1 - lift), spine.dy - bh * (0.9 + 0.1 * lift))
      ..quadraticBezierTo(spine.dx + bw * 0.4, spine.dy - bh * (1.0 + 0.3 * lift), spine.dx, spine.dy - bh * 0.82)
      ..close();
    canvas.drawPath(flying, Paint()..color = alpha(const Color(0xFFFFFFFF), 0.9));
    paintGem(canvas, Offset(spine.dx, spine.dy - bh * 0.95), w * 0.035, t, crystal: 'crystal.purple');
  }

  @override
  bool shouldRepaint(BookPainter old) => old.open != open || old.flutter != flutter || old.t != t;
}

/// The levels map: a parchment with a dotted path and a compass.
class MapPainter extends CustomPainter {
  MapPainter(this.t, this.needle);

  final ThemeTokens t;
  final double needle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sheet = Path()
      ..moveTo(w * 0.08, h * 0.3)
      ..lineTo(w * 0.36, h * 0.22)
      ..lineTo(w * 0.64, h * 0.3)
      ..lineTo(w * 0.92, h * 0.22)
      ..lineTo(w * 0.92, h * 0.78)
      ..lineTo(w * 0.64, h * 0.86)
      ..lineTo(w * 0.36, h * 0.78)
      ..lineTo(w * 0.08, h * 0.86)
      ..close();
    canvas.drawPath(sheet.shift(const Offset(0, 5)), Paint()..color = alpha(t.color('text.shadow'), 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawPath(sheet, Paint()..shader = gLinear(Offset.zero, Offset(w, h), [mix(t.color('gold.light'), const Color(0xFFFFFFFF), 0.3), t.color('gold.light'), mix(t.color('gold.base'), t.color('gold.light'), 0.5)]));
    for (final x in [0.36, 0.64]) {
      canvas.drawLine(Offset(w * x, h * (x == 0.36 ? 0.22 : 0.3)), Offset(w * x, h * (x == 0.36 ? 0.78 : 0.86)), Paint()..color = alpha(t.color('gold.dark'), 0.35)..strokeWidth = 1.2);
    }
    final trail = Path()
      ..moveTo(w * 0.18, h * 0.72)
      ..cubicTo(w * 0.4, h * 0.7, w * 0.3, h * 0.42, w * 0.55, h * 0.48)
      ..cubicTo(w * 0.72, h * 0.52, w * 0.66, h * 0.34, w * 0.8, h * 0.36);
    for (final m in trail.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        final pos = m.getTangentForOffset(d)!.position;
        canvas.drawCircle(pos, 1.6, Paint()..color = t.color('ui.danger'));
      }
    }
    final x = Offset(w * 0.8, h * 0.36);
    canvas.drawLine(x - const Offset(5, 5), x + const Offset(5, 5), Paint()..color = t.color('ui.danger')..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    canvas.drawLine(x + const Offset(-5, 5), x + const Offset(5, -5), Paint()..color = t.color('ui.danger')..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    final cc = Offset(w * 0.24, h * 0.36);
    final cr = w * 0.13;
    canvas.drawCircle(cc + const Offset(0, 3), cr, Paint()..color = alpha(t.color('text.shadow'), 0.4));
    canvas.drawCircle(cc, cr, Paint()..shader = gRadial(cc, cr, [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')]));
    canvas.drawCircle(cc, cr * 0.78, Paint()..color = mix(t.color('crystal.glow'), t.color('gold.light'), 0.4));
    canvas.save();
    canvas.translate(cc.dx, cc.dy);
    canvas.rotate(needle);
    canvas.drawPath(Path()..moveTo(0, -cr * 0.7)..lineTo(cr * 0.16, 0)..lineTo(-cr * 0.16, 0)..close(), Paint()..color = t.color('ui.danger'));
    canvas.drawPath(Path()..moveTo(0, cr * 0.7)..lineTo(cr * 0.16, 0)..lineTo(-cr * 0.16, 0)..close(), Paint()..color = t.color('stone.dark'));
    canvas.restore();
    canvas.drawCircle(cc, cr * 0.1, Paint()..color = t.color('gold.deep'));
  }

  @override
  bool shouldRepaint(MapPainter old) => old.needle != needle || old.t != t;
}

/// A treasure chest whose lid lifts on a glow of coins.
class ChestPainter extends CustomPainter {
  ChestPainter(this.t, {required this.lid, required this.sparkle, this.scale = 1});

  final ThemeTokens t;
  final double lid;
  final double sparkle;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.12, h * 0.48, w * 0.76, h * 0.42), Radius.circular(w * 0.06));
    paintDropShadow(canvas, body, t, dy: 6, blur: 8);
    paintGlow(canvas, Offset(w * 0.5, h * 0.46), w * (0.45 + 0.1 * lid), t.color('gold.glow'), 0.3 + 0.6 * lid);
    final wood = mix(t.color('island.earth'), t.color('stone.purple'), 0.25);
    if (lid > 0.05) {
      for (var i = 0; i < 7; i++) {
        final cx = w * (0.26 + 0.08 * i);
        final cy = h * (0.47 - 0.03 * math.sin(i * 1.3)) - lid * h * 0.03;
        paintCoin(canvas, Offset(cx, cy), w * 0.06, t, shine: i == ((sparkle * 7).floor() % 7) ? 1 : 0);
      }
    }
    canvas.drawRRect(body, Paint()..shader = gLinear(body.outerRect.topCenter, body.outerRect.bottomCenter, [mix(wood, const Color(0xFFFFFFFF), 0.15), mix(wood, const Color(0xFF000000), 0.35)]));
    for (final x in [0.22, 0.5, 0.78]) {
      canvas.drawRect(Rect.fromLTWH(w * x - w * 0.035, h * 0.48, w * 0.07, h * 0.42), Paint()..shader = gLinear(Offset(w * x - w * 0.035, 0), Offset(w * x + w * 0.035, 0), [t.color('gold.dark'), t.color('gold.light'), t.color('gold.dark')]));
    }
    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.rotate(-lid * 0.55);
    canvas.translate(-w * 0.5, -h * 0.5);
    final lidRect = Rect.fromLTWH(w * 0.1, h * 0.28, w * 0.8, h * 0.24);
    final lidShape = RRect.fromRectAndCorners(lidRect, topLeft: Radius.circular(w * 0.3), topRight: Radius.circular(w * 0.3), bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4));
    canvas.drawRRect(lidShape, Paint()..shader = gLinear(lidRect.topCenter, lidRect.bottomCenter, [mix(wood, const Color(0xFFFFFFFF), 0.25), wood]));
    canvas.drawRRect(lidShape, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = t.color('gold.base'));
    canvas.restore();
    final lock = Rect.fromCenter(center: Offset(w * 0.5, h * 0.56), width: w * 0.14, height: h * 0.14);
    canvas.drawRRect(RRect.fromRectAndRadius(lock, Radius.circular(w * 0.03)), Paint()..shader = gLinear(lock.topCenter, lock.bottomCenter, [t.color('gold.light'), t.color('gold.dark')]));
    canvas.drawCircle(lock.center, w * 0.018, Paint()..color = t.color('gold.deep'));
  }

  @override
  bool shouldRepaint(ChestPainter old) => old.lid != lid || old.sparkle != sparkle || old.t != t;
}

/// The challenge: a floating crystal ringed by turning golden runes.
class CrystalPainter extends CustomPainter {
  CrystalPainter(this.t, this.phase);

  final ThemeTokens t;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    paintPedestal(canvas, Rect.fromLTWH(w * 0.2, h * 0.7, w * 0.6, h * 0.28), t);
    final c = Offset(w * 0.5, h * (0.42 + 0.03 * _wave(phase)));
    final purple = t.color('crystal.purple');
    paintGlow(canvas, c, w * 0.6, purple, 0.55 + 0.25 * _wave(phase, 2) * 0.5 + 0.25 * t.number('crystal.intensity', 0.6));
    final ring = Rect.fromCenter(center: c, width: w * 0.86, height: h * 0.22);
    canvas.drawOval(ring, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = alpha(t.color('gold.base'), 0.8));
    final s = w * 0.2;
    final gem = Path()
      ..moveTo(c.dx, c.dy - s * 1.5)
      ..lineTo(c.dx + s * 0.75, c.dy - s * 0.2)
      ..lineTo(c.dx, c.dy + s * 1.1)
      ..lineTo(c.dx - s * 0.75, c.dy - s * 0.2)
      ..close();
    canvas.drawPath(gem, Paint()..shader = gLinear(c - Offset(s, s), c + Offset(s, s), [t.color('crystal.glow'), purple, mix(purple, const Color(0xFF000000), 0.35)]));
    canvas.drawPath(Path()..moveTo(c.dx, c.dy - s * 1.5)..lineTo(c.dx, c.dy + s * 1.1), Paint()..color = alpha(const Color(0xFFFFFFFF), 0.4)..strokeWidth = 1.2);
    canvas.drawPath(Path()..moveTo(c.dx - s * 0.75, c.dy - s * 0.2)..lineTo(c.dx + s * 0.75, c.dy - s * 0.2), Paint()..color = alpha(const Color(0xFFFFFFFF), 0.35)..strokeWidth = 1.2);
    for (var i = 0; i < 6; i++) {
      final a = phase * math.pi * 2 + i * math.pi / 3;
      final p = Offset(c.dx + math.cos(a) * ring.width / 2, c.dy + math.sin(a) * ring.height / 2);
      final front = math.sin(a) > 0;
      paintGem(canvas, p, w * (front ? 0.04 : 0.028), t, crystal: 'crystal.purple', glow: front ? 0.8 : 0.3);
    }
  }

  @override
  bool shouldRepaint(CrystalPainter old) => old.phase != phase || old.t != t;
}

/// The magic portal behind the logo: a stone ring of runes and a slow swirl.
class PortalPainter extends CustomPainter {
  PortalPainter(this.t, this.phase);

  final ThemeTokens t;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.46;
    paintGlow(canvas, c, r * 1.5, t.color('crystal.blue'), 0.35 + 0.25 * t.number('crystal.intensity', 0.6));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.16..color = t.color('stone.dark'));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.12..shader = gSweep(c, [t.color('stone.light'), t.color('stone.base'), t.color('stone.light')]));
    canvas.drawCircle(c, r * 0.93, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('gold.base'));
    canvas.drawCircle(c, r * 1.07, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('gold.base'));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.92)));
    canvas.drawCircle(c, r, Paint()..shader = gRadial(c, r, [alpha(t.color('crystal.glow'), 0.55), alpha(t.color('crystal.purple'), 0.35), alpha(t.color('ui.panelDeep'), 0.25)], [0, 0.6, 1]));
    for (var k = 0; k < 4; k++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * (0.25 + 0.17 * k)),
        phase * math.pi * 2 * (k.isEven ? 1 : -1) + k,
        math.pi * 1.2,
        false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..color = alpha(t.color('crystal.glow'), 0.5 - k * 0.08),
      );
    }
    canvas.restore();
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 + phase * 0.6;
      paintGem(canvas, c + Offset(math.cos(a), math.sin(a)) * r, r * 0.045, t, glow: 0.4);
    }
  }

  @override
  bool shouldRepaint(PortalPainter old) => old.phase != phase || old.t != t;
}

/// The great stone arch across the top of the home page: masonry, gold
/// trim, a crystal keystone and two hanging lamps.
class ArchPainter extends CustomPainter {
  ArchPainter(this.t, this.swing);

  final ThemeTokens t;
  final double swing;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arch = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..quadraticBezierTo(w * 0.94, h * 0.7, w * 0.82, h * 0.74)
      ..quadraticBezierTo(w * 0.5, h * 0.9, w * 0.18, h * 0.74)
      ..quadraticBezierTo(w * 0.06, h * 0.7, 0, h)
      ..close();
    canvas.drawPath(arch.shift(const Offset(0, 6)), Paint()..color = alpha(t.color('text.shadow'), 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.save();
    canvas.clipPath(arch);
    paintStoneWall(canvas, RRect.fromRectAndRadius(Offset.zero & size, Radius.zero), t, seed: 5, block: 30);
    canvas.restore();
    final rim = Path()
      ..moveTo(w, h)
      ..quadraticBezierTo(w * 0.94, h * 0.7, w * 0.82, h * 0.74)
      ..quadraticBezierTo(w * 0.5, h * 0.9, w * 0.18, h * 0.74)
      ..quadraticBezierTo(w * 0.06, h * 0.7, 0, h);
    canvas.drawPath(rim, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = t.color('gold.deep'));
    canvas.drawPath(rim, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..shader = gLinear(Offset.zero, Offset(w, 0), [t.color('gold.dark'), t.color('gold.light'), t.color('gold.dark')]));
    final key = Offset(w * 0.5, h * 0.86);
    final ks = h * 0.12;
    canvas.drawPath(Path()..moveTo(key.dx - ks, key.dy - ks)..lineTo(key.dx + ks, key.dy - ks)..lineTo(key.dx + ks * 0.7, key.dy + ks * 0.6)..lineTo(key.dx - ks * 0.7, key.dy + ks * 0.6)..close(),
        Paint()..shader = gLinear(key - Offset(0, ks), key + Offset(0, ks), [t.color('gold.light'), t.color('gold.dark')]));
    paintGem(canvas, key - Offset(0, ks * 0.2), ks * 0.4, t, crystal: 'crystal.purple', glow: 0.9);
    for (final x in [0.08, 0.92]) {
      _lamp(canvas, Offset(w * x, h * 0.72), h * 0.2, swing * (x < 0.5 ? 1 : -1));
    }
    for (var k = 0; k < 2; k++) {
      final vx = w * (k == 0 ? 0.24 : 0.74);
      final vy = h * 0.78 + (k == 0 ? 0 : h * 0.02);
      final vine = Path()..moveTo(vx, vy);
      for (var i = 1; i <= 4; i++) {
        vine.quadraticBezierTo(vx + (i.isOdd ? 8 : -8), vy + i * 9 - 4, vx, vy + i * 9);
      }
      canvas.drawPath(vine, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('plant.vine'));
      for (var i = 1; i <= 4; i++) {
        canvas.drawOval(Rect.fromCenter(center: Offset(vx + (i.isOdd ? 5 : -5), vy + i * 9), width: 9, height: 5), Paint()..color = t.color(i.isOdd ? 'plant.leaf' : 'plant.leafLight'));
      }
    }
  }

  void _lamp(Canvas canvas, Offset top, double len, double sway) {
    canvas.save();
    canvas.translate(top.dx, top.dy);
    canvas.rotate(sway * 0.12);
    canvas.drawLine(Offset.zero, Offset(0, len), Paint()..color = t.color('gold.dark')..strokeWidth = 1.6);
    final lc = Offset(0, len + 9);
    paintGlow(canvas, lc, 30, t.color('lamp.glow'), 0.4 + 0.6 * t.number('lamp.intensity', 0.4));
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: lc, width: 13, height: 17), const Radius.circular(4));
    canvas.drawRRect(body, Paint()..color = t.color('lamp.light'));
    canvas.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = t.color('gold.dark'));
    canvas.drawLine(lc - const Offset(7, 9), lc + const Offset(7, -9), Paint()..color = t.color('gold.base')..strokeWidth = 2.4);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArchPainter old) => old.swing != swing || old.t != t;
}

/// The game's logo with glowing numbers orbiting it.
class GameLogo extends StatelessWidget {
  const GameLogo({super.key, this.width = 320});

  final double width;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    Widget word(String text, double size) => ShaderMask(
          shaderCallback: (r) => gLinear(r.topCenter, r.bottomCenter, [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')], [0, 0.55, 1]),
          child: Text(
            text,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: UiText.display(context, size: size, color: const Color(0xFFFFFFFF)).copyWith(
              letterSpacing: size * 0.06,
              shadows: [Shadow(color: alpha(t.color('gold.deep'), 1), offset: const Offset(0, 3), blurRadius: 0), Shadow(color: alpha(t.color('gold.glow'), 0.7), blurRadius: 16)],
            ),
          ),
        );
    return Loop(
      period: s.design.motion('orbit'),
      builder: (context, phase) => SizedBox(
        width: width,
        height: width * 0.62,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: CustomPaint(painter: _OrbitPainter(t, phase, back: true))),
          Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(child: word(s.i18n.t('app.logoTop'), width * 0.17)),
            FittedBox(child: word(s.i18n.t('app.logoBottom'), width * 0.11)),
          ]),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _OrbitPainter(t, phase, back: false)))),
        ]),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t, this.phase, {required this.back});

  final ThemeTokens t;
  final double phase;
  final bool back;

  static final Map<String, TextPainter> _digits = {};

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rx = size.width * 0.5;
    final ry = size.height * 0.36;
    for (var i = 0; i < 9; i++) {
      final a = phase * math.pi * 2 + i * math.pi * 2 / 9;
      final depth = math.sin(a);
      if ((depth < 0) != back) continue;
      final p = c + Offset(math.cos(a) * rx * 0.92, depth * ry);
      final scale = 0.75 + 0.35 * (depth + 1) / 2;
      final color = t.tile(i);
      paintGlow(canvas, p, 22 * scale, color, back ? 0.35 : 0.75);
      canvas.drawCircle(p, 12 * scale, Paint()..color = alpha(color, back ? 0.55 : 0.95));
      canvas.drawCircle(p, 12 * scale, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = alpha(t.color('gold.light'), back ? 0.5 : 0.9));
      final key = '${i + 1}:${(scale * 10).round()}:${t.id}';
      final tp = _digits.putIfAbsent(
        key,
        () => TextPainter(
          text: TextSpan(text: '${i + 1}', style: TextStyle(fontFamily: 'NunitoSans', fontWeight: FontWeight.w700, fontSize: 15 * scale, color: t.color('tile.number'))),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.phase != phase || old.t != t;
}
