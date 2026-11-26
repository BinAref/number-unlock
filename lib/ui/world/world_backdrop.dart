import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../kit/paint_kit.dart';

/// Vertical camera offset (the levels map scrolls it for parallax).
class WorldCamera extends ValueNotifier<double> {
  WorldCamera() : super(0);
}

/// The living world behind every page, as separate layers that move at
/// their own speeds: sky, sun or moon, stars, far islands, clouds, floating
/// islands with waterfalls, mist and drifting motes (fireflies at night).
class WorldBackdrop extends StatefulWidget {
  const WorldBackdrop({super.key, required this.camera});

  final ValueListenable<double> camera;

  @override
  State<WorldBackdrop> createState() => _WorldBackdropState();
}

class _WorldBackdropState extends State<WorldBackdrop> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final _WorldCache _cache = _WorldCache();
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      if (t - _last >= 1 / 30) {
        _last = t;
        _time.value = t;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final reduced = s.reducedEffects || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (reduced && _ticker.isActive) _ticker.stop();
    if (!reduced && !_ticker.isActive) _ticker.start();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WorldPainter(s.theme.tokens, _time, widget.camera, _cache),
        size: Size.infinite,
      ),
    );
  }
}

class _Fall {
  const _Fall(this.x, this.top, this.length, this.width);

  final double x;
  final double top;
  final double length;
  final double width;
}

class _WorldCache {
  String? key;
  ui.Picture? far;
  ui.Picture? mid;
  ui.Picture? clouds;
  List<_Fall> falls = const [];

  void ensure(Size size, ThemeTokens t) {
    final k = '${t.id}:${size.width.round()}x${size.height.round()}';
    if (k == key) return;
    key = k;
    far = _record(size, (c) => _farIslands(c, size, t));
    final falls = <_Fall>[];
    mid = _record(size, (c) => _midIslands(c, size, t, falls));
    this.falls = falls;
    clouds = _record(Size(size.width * 2, size.height), (c) => _cloudBand(c, Size(size.width * 2, size.height), t));
  }

  static ui.Picture _record(Size size, void Function(Canvas) draw) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec, Offset.zero & size));
    return rec.endRecording();
  }

  static void _farIslands(Canvas c, Size size, ThemeTokens t) {
    final color = alpha(t.color('island.far'), t.number('island.farOpacity', 0.7));
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.1 + 0.27 * i + 0.08 * hashUnit(i, 3));
      final y = size.height * (0.28 + 0.38 * hashUnit(i, 9));
      final w = size.width * (0.16 + 0.08 * hashUnit(i, 5));
      final p = Path()
        ..moveTo(x - w / 2, y)
        ..quadraticBezierTo(x, y - w * 0.18, x + w / 2, y)
        ..quadraticBezierTo(x + w * 0.2, y + w * 0.32, x + w * 0.05, y + w * 0.6)
        ..quadraticBezierTo(x - w * 0.2, y + w * 0.3, x - w / 2, y)
        ..close();
      c.drawPath(p, Paint()..color = color);
    }
  }

  static void _midIslands(Canvas c, Size size, ThemeTokens t, List<_Fall> falls) {
    final specs = [
      (0.14, 0.42, 0.34, 1),
      (0.86, 0.6, 0.38, 2),
      (0.5, 0.86, 0.3, 3),
    ];
    for (final (fx, fy, fw, seed) in specs) {
      paintIsland(c, Offset(size.width * fx, size.height * fy), size.width * fw, t, seed, falls);
    }
  }

  static void _cloudBand(Canvas c, Size size, ThemeTokens t) {
    for (var i = 0; i < 7; i++) {
      final x = size.width * (i / 7 + 0.05 * hashUnit(i, 1));
      final y = size.height * (0.1 + 0.75 * hashUnit(i, 2));
      final r = size.width * (0.03 + 0.03 * hashUnit(i, 4));
      _cloud(c, Offset(x, y), r, t, i);
    }
  }

  static void _cloud(Canvas c, Offset o, double r, ThemeTokens t, int seed) {
    final opacity = t.number('cloud.opacity', 0.9);
    final puffs = [
      for (var k = 0; k < 6; k++)
        (Offset((k - 2.5) * r * 0.8, -math.sin(k / 5 * math.pi) * r * 0.7 * (0.7 + 0.5 * hashUnit(seed, k))), r * (0.7 + 0.5 * hashUnit(seed, k, 7))),
    ];
    for (final (d, pr) in puffs) {
      c.drawCircle(o + d + Offset(0, r * 0.25), pr, Paint()..color = alpha(t.color('cloud.shade'), opacity));
    }
    for (final (d, pr) in puffs) {
      c.drawCircle(o + d, pr * 0.92, Paint()..color = alpha(t.color('cloud.light'), opacity));
    }
  }
}

/// A floating island: grassy cap, layered blue-purple rock, crystals,
/// bushes, and a waterfall pouring off one edge.
void paintIsland(Canvas c, Offset o, double w, ThemeTokens t, int seed, List<_Fall>? falls) {
  final top = o.dy;
  final rock = Path()
    ..moveTo(o.dx - w / 2, top)
    ..cubicTo(o.dx - w * 0.42, top + w * 0.3, o.dx - w * 0.18, top + w * 0.42, o.dx + w * 0.02, top + w * 0.72)
    ..cubicTo(o.dx + w * 0.2, top + w * 0.4, o.dx + w * 0.44, top + w * 0.28, o.dx + w / 2, top)
    ..close();
  c.drawPath(
    rock,
    Paint()..shader = gLinear(Offset(o.dx, top), Offset(o.dx, top + w * 0.72), [t.color('island.rock'), t.color('island.rockShade'), t.color('island.rockDeep')], [0, 0.45, 1]),
  );
  for (var k = 1; k <= 3; k++) {
    final y = top + w * 0.1 * k;
    c.drawLine(Offset(o.dx - w * (0.42 - k * 0.07), y), Offset(o.dx + w * (0.4 - k * 0.07), y + w * 0.02), Paint()..color = alpha(t.color('island.rockDeep'), 0.5)..strokeWidth = 1.5);
  }
  for (var k = 0; k < 2; k++) {
    final cx = o.dx + w * (k == 0 ? -0.16 : 0.14);
    final cy = top + w * (0.2 + 0.1 * k);
    final s = w * 0.07;
    final shard = Path()
      ..moveTo(cx, cy - s * 1.4)
      ..lineTo(cx + s * 0.55, cy)
      ..lineTo(cx, cy + s * 0.5)
      ..lineTo(cx - s * 0.55, cy)
      ..close();
    final cc = t.color(k == 0 ? 'crystal.blue' : 'crystal.purple');
    paintGlow(c, Offset(cx, cy), s * 2.2, cc, t.number('crystal.intensity', 0.5));
    c.drawPath(shard, Paint()..shader = gLinear(Offset(cx - s, cy - s), Offset(cx + s, cy + s), [t.color('crystal.glow'), cc]));
  }
  final earth = Path()
    ..moveTo(o.dx - w / 2, top)
    ..quadraticBezierTo(o.dx, top + w * 0.08, o.dx + w / 2, top)
    ..lineTo(o.dx + w / 2, top - w * 0.03)
    ..quadraticBezierTo(o.dx, top + w * 0.03, o.dx - w / 2, top - w * 0.03)
    ..close();
  c.drawPath(earth, Paint()..color = t.color('island.earth'));
  final grass = Path()..moveTo(o.dx - w / 2 - w * 0.02, top - w * 0.02);
  for (var k = 0; k <= 8; k++) {
    final x = o.dx - w / 2 + w * k / 8;
    grass.quadraticBezierTo(x - w / 16, top - w * (0.1 + 0.03 * hashUnit(seed, k)), x, top - w * 0.06);
  }
  grass
    ..lineTo(o.dx + w / 2 + w * 0.02, top - w * 0.02)
    ..quadraticBezierTo(o.dx, top + w * 0.04, o.dx - w / 2 - w * 0.02, top - w * 0.02)
    ..close();
  c.drawPath(grass, Paint()..shader = gLinear(Offset(o.dx, top - w * 0.12), Offset(o.dx, top), [t.color('island.grassLight'), t.color('island.grass')]));
  for (var k = 0; k < 3; k++) {
    final bx = o.dx + w * (-0.28 + 0.24 * k + 0.06 * hashUnit(seed, k, 4));
    final br = w * (0.06 + 0.03 * hashUnit(seed, k, 8));
    final by = top - w * 0.07 - br * 0.6;
    c.drawCircle(Offset(bx, by + br * 0.2), br, Paint()..color = t.color('plant.vine'));
    c.drawCircle(Offset(bx - br * 0.2, by), br * 0.82, Paint()..color = t.color('plant.leaf'));
    c.drawCircle(Offset(bx - br * 0.35, by - br * 0.25), br * 0.38, Paint()..color = alpha(t.color('plant.leafLight'), 0.9));
  }
  if (falls != null) {
    final fx = o.dx + w * (hashUnit(seed, 77) < 0.5 ? -0.36 : 0.34);
    falls.add(_Fall(fx, top - w * 0.03, w * 0.95, w * 0.07));
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter(this.t, this.time, this.camera, this.cache) : super(repaint: Listenable.merge([time, camera]));

  final ThemeTokens t;
  final ValueListenable<double> time;
  final ValueListenable<double> camera;
  final _WorldCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    cache.ensure(size, t);
    final now = time.value;
    final cam = camera.value;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()..shader = gLinear(rect.topCenter, rect.bottomCenter, [t.color('sky.top'), t.color('sky.mid'), t.color('sky.horizon')], [0, 0.55, 1]),
    );
    paintGlow(canvas, Offset(size.width * 0.5, size.height * 0.95), size.width * 0.9, t.color('sky.glow'), 0.5);
    _stars(canvas, size, now);
    _celestial(canvas, size, now);

    _tiled(canvas, size, cache.far!, cam * 0.12, 0);
    final drift = (now * size.width / 160) % (size.width * 2);
    _tiled(canvas, size, cache.clouds!, cam * 0.22, -drift, width: size.width * 2);
    final bob = math.sin(now * 0.6) * 5;
    final midShift = cam * 0.38;
    _tiled(canvas, size, cache.mid!, midShift, 0, dy: bob);
    _falls(canvas, size, now, midShift, bob);
    _mist(canvas, size, now);
    _particles(canvas, size, now, cam);
  }

  void _tiled(Canvas canvas, Size size, ui.Picture pic, double shift, double dx, {double width = 0, double dy = 0}) {
    final h = size.height;
    final y = shift % h;
    for (final oy in [y - h, y]) {
      canvas.save();
      canvas.translate(dx, oy + dy);
      canvas.drawPicture(pic);
      if (width > 0) {
        canvas.translate(width, 0);
        canvas.drawPicture(pic);
      }
      canvas.restore();
    }
  }

  void _celestial(Canvas canvas, Size size, double now) {
    final c = Offset(size.width * t.number('sky.celestialX', 0.8), size.height * t.number('sky.celestialY', 0.12));
    final r = size.width * t.number('sky.celestialSize', 0.08);
    final rays = t.number('sky.rays');
    if (rays > 0) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(now * 0.03);
      for (var i = 0; i < 12; i++) {
        canvas.rotate(math.pi / 6);
        final ray = Path()
          ..moveTo(0, 0)
          ..lineTo(size.width * 0.9, -r * 0.5)
          ..lineTo(size.width * 0.9, r * 0.5)
          ..close();
        canvas.drawPath(ray, Paint()..shader = gLinear(Offset.zero, Offset(size.width * 0.9, 0), [alpha(t.color('sky.celestialGlow'), 0.18 * rays), alpha(t.color('sky.celestialGlow'), 0)]));
      }
      canvas.restore();
    }
    paintGlow(canvas, c, r * 3.4, t.color('sky.celestialGlow'), 0.9);
    final disc = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final crescent = t.number('sky.celestialCrescent');
    final shape = crescent > 0
        ? Path.combine(PathOperation.difference, disc, Path()..addOval(Rect.fromCircle(center: c + Offset(r * crescent, -r * crescent * 0.35), radius: r * 0.92)))
        : disc;
    canvas.drawPath(shape, Paint()..shader = gRadial(c - Offset(r * 0.3, r * 0.3), r * 1.4, [const Color(0xFFFFFFFF), t.color('sky.celestial')]));
  }

  void _stars(Canvas canvas, Size size, double now) {
    final amount = t.number('sky.stars');
    if (amount <= 0) return;
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final x = hashUnit(i, 11) * size.width;
      final y = hashUnit(i, 23) * size.height * 0.75;
      final tw = 0.55 + 0.45 * math.sin(now * (0.8 + hashUnit(i, 5) * 1.6) + i);
      paint.color = alpha(t.color('sky.star'), amount * tw * (0.35 + 0.65 * hashUnit(i, 7)));
      canvas.drawCircle(Offset(x, y), 0.6 + 1.3 * hashUnit(i, 13), paint);
    }
  }

  void _falls(Canvas canvas, Size size, double now, double shift, double bob) {
    final h = size.height;
    final glow = t.number('water.glowStrength', 0.3);
    for (final f in cache.falls) {
      for (final oy in [(shift % h) - h, shift % h]) {
        final top = f.top + oy + bob;
        final rect = Rect.fromLTWH(f.x - f.width / 2, top, f.width, f.length);
        if (rect.bottom < 0 || rect.top > h) continue;
        if (glow > 0.4) paintGlow(canvas, rect.center, f.length * 0.5, t.color('water.glow'), glow * 0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(f.width / 2)),
          Paint()..shader = gLinear(rect.topCenter, rect.bottomCenter, [alpha(t.color('water.fall'), 0.95), alpha(t.color('water.fallShade'), 0.7), alpha(t.color('water.fallShade'), 0)], [0, 0.6, 1]),
        );
        final stripe = Paint()
          ..color = alpha(const Color(0xFFFFFFFF), 0.55)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        for (var k = 0; k < 5; k++) {
          final y = top + ((now * 70 + k * f.length / 5) % (f.length * 0.85));
          final x = f.x + (k.isEven ? -1 : 1) * f.width * 0.18;
          canvas.drawLine(Offset(x, y), Offset(x, y + f.length * 0.08), stripe);
        }
        final mistC = Offset(f.x, top + f.length * 0.82);
        final mo = t.number('water.mistOpacity', 0.4);
        for (var k = 0; k < 3; k++) {
          final pr = f.width * (1.1 + 0.35 * math.sin(now * 1.4 + k * 2));
          canvas.drawCircle(mistC + Offset((k - 1) * f.width * 0.9, 0), pr, Paint()..color = alpha(t.color('water.mist'), mo * 0.5));
        }
      }
    }
  }

  void _mist(Canvas canvas, Size size, double now) {
    final mo = t.number('water.mistOpacity', 0.4);
    for (var k = 0; k < 2; k++) {
      final y = size.height * (0.62 + 0.22 * k);
      final dx = math.sin(now * 0.05 + k * 2) * size.width * 0.15;
      final band = Rect.fromLTWH(-size.width * 0.3 + dx, y - size.height * 0.06, size.width * 1.6, size.height * 0.12);
      canvas.drawOval(band, Paint()..shader = gRadial(band.center, band.width / 2, [alpha(t.color('water.mist'), mo * 0.45), alpha(t.color('water.mist'), 0)]));
    }
  }

  void _particles(Canvas canvas, Size size, double now, double cam) {
    final n = t.number('particle.count', 20).round();
    final fireflies = t.number('particle.fireflies') > 0.5;
    final color = t.color('particle.color');
    for (var i = 0; i < n; i++) {
      final speed = 8 + 14 * hashUnit(i, 3);
      final y = (hashUnit(i, 1) * size.height - now * speed + cam * 0.5) % size.height;
      final x = hashUnit(i, 2) * size.width + math.sin(now * 0.7 + i) * 14;
      final pulse = 0.5 + 0.5 * math.sin(now * (1.2 + hashUnit(i, 4)) + i * 1.7);
      if (fireflies) {
        paintGlow(canvas, Offset(x, y), 9, color, pulse);
        canvas.drawCircle(Offset(x, y), 1.6, Paint()..color = alpha(color, 0.9 * pulse));
      } else {
        canvas.drawCircle(Offset(x, y), 1.2 + hashUnit(i, 6), Paint()..color = alpha(color, 0.35 + 0.35 * pulse));
      }
    }
  }

  @override
  bool shouldRepaint(_WorldPainter old) => old.t != t;
}
