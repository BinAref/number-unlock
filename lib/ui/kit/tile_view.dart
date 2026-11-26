import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/model/arrows.dart';
import '../../services/theme_service.dart';
import 'glyphs.dart';
import 'paint_kit.dart';

/// Everything that changes how one tile looks right now.
class TileLook {
  const TileLook({
    this.locked = false,
    this.unlock = 0,
    this.hint = 0,
    this.swapMark = false,
    this.match = 0,
    this.vanish = 0,
    this.lifted = 0,
    this.dimmed = false,
    this.arrows = 0,
    this.star = false,
  });

  /// The arrow rule: which edges this tile opens through (an [Arrows] mask).
  final int arrows;

  /// A tile that opens nothing (no arrows on an arrow board).
  final bool star;

  /// Locked: dimmed with a lock badge — number and colour stay readable.
  final bool locked;

  /// 0..1 flash while the tile opens.
  final double unlock;

  /// 0..1 pulse of the hint aura (0 = no hint).
  final double hint;

  /// Chosen as one side of a swap.
  final bool swapMark;

  /// 0..1 glow while matching.
  final double match;

  /// 0..1 shrink-and-fade while vanishing.
  final double vanish;

  /// 0..1 lift (press / flight).
  final double lifted;

  /// Faded because something else is in focus (swap mode on the board).
  final bool dimmed;
}

/// Paints a number tile in layers: shadow, body, colour, bevel, rim,
/// reflection, locked veil and badge, number, and the state effects.
class TilePainter extends CustomPainter {
  TilePainter(this.t, {required this.value, required this.colorSlot, required this.look});

  final ThemeTokens t;
  final int value;
  final int colorSlot;
  final TileLook look;

  static final Map<String, TextPainter> _numbers = {};

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final vanish = look.vanish.clamp(0.0, 1.0);
    if (vanish >= 1) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final scale = (1 - vanish * 0.7) * (1 + look.lifted * 0.06) * (1 + look.match * 0.06);
    canvas.scale(scale);
    canvas.translate(-c.dx, -c.dy);
    final fade = 1 - vanish;

    final rect = Rect.fromCenter(center: c, width: s * 0.94, height: s * 0.94);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.22));
    final base = t.tile(colorSlot);
    final glowStrength = t.number('tile.glowStrength', 0.7);

    if (look.hint > 0) {
      paintGlow(canvas, c, s * (0.85 + 0.15 * look.hint), t.color('tile.hint'), 0.6 + 0.4 * look.hint);
    }
    if (!look.locked && look.match == 0) paintGlow(canvas, c, s * 0.66, base, 0.25 * glowStrength * fade);

    canvas.drawRRect(
      rr.shift(Offset(0, s * (0.05 + 0.04 * look.lifted))),
      Paint()
        ..color = alpha(t.color('tile.shadow'), 0.45 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * (0.04 + 0.05 * look.lifted)),
    );
    final light = mix(base, const Color(0xFFFFFFFF), 0.42);
    final dark = mix(base, const Color(0xFF000000), 0.34);
    canvas.drawRRect(rr, Paint()..shader = gLinear(rect.topLeft, rect.bottomRight, [alpha(light, fade), alpha(base, fade), alpha(dark, fade)], [0, 0.5, 1]));
    canvas.drawRRect(
      rr.deflate(s * 0.05),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..shader = gLinear(rect.topCenter, rect.bottomCenter, [alpha(light, 0.9 * fade), alpha(dark, 0.6 * fade)]),
    );
    canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.028..color = alpha(t.color('tile.rim'), 0.75 * fade));
    final gloss = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(rect.left + s * 0.1, rect.top + s * 0.07, rect.width - s * 0.2, rect.height * 0.32),
        topLeft: Radius.circular(s * 0.16),
        topRight: Radius.circular(s * 0.16),
        bottomLeft: Radius.circular(s * 0.3),
        bottomRight: Radius.circular(s * 0.3),
      ));
    canvas.drawPath(gloss, Paint()..shader = gLinear(rect.topCenter, Offset(c.dx, rect.top + rect.height * 0.4), [alpha(const Color(0xFFFFFFFF), 0.38 * fade), alpha(const Color(0xFFFFFFFF), 0)]));

    if (look.locked) {
      canvas.drawRRect(rr, Paint()..color = alpha(t.color('tile.locked'), t.number('tile.lockedOpacity', 0.5) * 0.75 * fade));
      canvas.drawRRect(rr, Paint()..color = alpha(const Color(0xFF8C8C9C), 0.22 * t.number('tile.lockedDesaturate', 0.7) * fade));
    }

    _number(canvas, c, s, fade * (look.locked ? 0.82 : 1));
    if (look.arrows != Arrows.none || look.star) _marks(canvas, rect, s, fade);

    if (look.locked) {
      final badge = Offset(rect.right - s * 0.2, rect.bottom - s * 0.2);
      canvas.drawCircle(badge, s * 0.14, Paint()..color = alpha(t.color('tile.locked'), 0.9 * fade));
      canvas.drawCircle(badge, s * 0.14, Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.02..color = alpha(t.color('gold.base'), fade));
      canvas.save();
      canvas.translate(badge.dx - s * 0.08, badge.dy - s * 0.08);
      GlyphPainter(Glyph.lock, alpha(t.color('gold.light'), fade)).paint(canvas, Size.square(s * 0.16));
      canvas.restore();
    }
    if (look.unlock > 0) {
      final u = look.unlock.clamp(0.0, 1.0);
      canvas.drawRRect(rr, Paint()..color = alpha(t.color('tile.glow'), (1 - u) * 0.65));
      canvas.drawRRect(rr.inflate(s * 0.1 * u), Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.05 * (1 - u)..color = alpha(t.color('tile.glow'), 1 - u));
    }
    if (look.hint > 0) {
      canvas.drawRRect(rr.inflate(s * (0.04 + 0.03 * look.hint)), Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.05..color = alpha(t.color('tile.hint'), 0.7 + 0.3 * look.hint));
    }
    if (look.swapMark) {
      final ring = rr.inflate(s * 0.06);
      final path = Path()..addRRect(ring);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += s * 0.18) {
          canvas.drawPath(m.extractPath(d, d + s * 0.1), Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.05..strokeCap = StrokeCap.round..color = t.color('tile.swap'));
        }
      }
    }
    if (look.match > 0) {
      canvas.drawRRect(rr, Paint()..color = alpha(t.color('tile.match'), 0.55 * look.match * fade));
      paintGlow(canvas, c, s * 0.9, t.color('tile.match'), look.match * fade);
    }
    if (look.dimmed) canvas.drawRRect(rr, Paint()..color = alpha(t.color('tile.locked'), 0.35));
    canvas.restore();
  }

  /// The arrow rule's marks: a chevron at each edge the tile opens through,
  /// or a small star in the corner when it opens nothing. Both stay clear
  /// of the number and of the lock badge.
  void _marks(Canvas canvas, Rect rect, double s, double fade) {
    final fill = Paint()..color = alpha(t.color('tile.arrow'), fade);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, s * 0.025)
      ..strokeJoin = StrokeJoin.round
      ..color = alpha(t.color('tile.numberStroke'), 0.9 * fade);
    final c = rect.center;
    final reach = rect.width / 2 - s * 0.075;
    final depth = s * 0.09;
    final half = s * 0.1;
    void chevron(Offset dir) {
      final tip = c + dir * reach;
      final base = c + dir * (reach - depth);
      final side = Offset(-dir.dy, dir.dx) * half;
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + side.dx, base.dy + side.dy)
        ..lineTo(base.dx - side.dx, base.dy - side.dy)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }

    if (Arrows.has(look.arrows, Arrows.up)) chevron(const Offset(0, -1));
    if (Arrows.has(look.arrows, Arrows.right)) chevron(const Offset(1, 0));
    if (Arrows.has(look.arrows, Arrows.down)) chevron(const Offset(0, 1));
    if (Arrows.has(look.arrows, Arrows.left)) chevron(const Offset(-1, 0));
    if (look.star) {
      final star = starPath(Offset(rect.left + s * 0.2, rect.top + s * 0.2), s * 0.1, inner: 0.5, points: 8);
      canvas.drawPath(star, Paint()..color = alpha(t.color('tile.star'), fade));
      canvas.drawPath(star, edge);
    }
  }

  void _number(Canvas canvas, Offset c, double s, double opacity) {
    final size = (s * 0.56).roundToDouble();
    final key = '$value:$size:${t.id}';
    final stroke = _numbers.putIfAbsent(
      '$key:s',
      () => TextPainter(
        text: TextSpan(
          text: '$value',
          style: TextStyle(
            fontFamily: 'NunitoSans',
            fontWeight: FontWeight.w700,
            fontSize: size,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2, size * 0.14)
              ..strokeJoin = StrokeJoin.round
              ..color = t.color('tile.numberStroke'),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    final fill = _numbers.putIfAbsent(
      '$key:f',
      () => TextPainter(
        text: TextSpan(text: '$value', style: TextStyle(fontFamily: 'NunitoSans', fontWeight: FontWeight.w700, fontSize: size, color: t.color('tile.number'))),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    final o = c - Offset(fill.width / 2, fill.height / 2 + s * 0.01);
    canvas.saveLayer(null, Paint()..color = alpha(const Color(0xFFFFFFFF), opacity));
    stroke.paint(canvas, o);
    fill.paint(canvas, o);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TilePainter old) =>
      old.value != value ||
      old.colorSlot != colorSlot ||
      old.t != t ||
      old.look.locked != look.locked ||
      old.look.unlock != look.unlock ||
      old.look.hint != look.hint ||
      old.look.swapMark != look.swapMark ||
      old.look.match != look.match ||
      old.look.vanish != look.vanish ||
      old.look.lifted != look.lifted ||
      old.look.dimmed != look.dimmed ||
      old.look.arrows != look.arrows ||
      old.look.star != look.star;
}
