import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/levels/level_progress.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/widgets.dart';
import '../common/navigation.dart';

/// Where each level sits on the winding, semi-diagonal stone road.
class MapGeometry {
  MapGeometry({required this.width, required this.total, required this.spacing}) : height = (total + 3) * spacing;

  final double width;
  final int total;
  final double spacing;
  final double height;

  double y(int level) => height - spacing * (level + 1.2);

  double x(int level) {
    final amp = width * 0.3;
    final f = math.sin(level * 0.82) * 0.72 + math.sin(level * 0.31 + 1.3) * 0.28;
    return width / 2 + amp * f;
  }

  Offset at(num level) {
    final l = level.floor();
    final frac = level - l;
    final a = Offset(x(l), y(l));
    final b = Offset(x(l + 1), y(l + 1));
    final t = frac * frac * (3 - 2 * frac);
    return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * frac);
  }
}

class LevelsMapScreen extends StatefulWidget {
  const LevelsMapScreen({super.key});

  @override
  State<LevelsMapScreen> createState() => _LevelsMapScreenState();
}

class _LevelsMapScreenState extends State<LevelsMapScreen> {
  ScrollController? _scroll;
  MapGeometry? _geo;

  @override
  void dispose() {
    _scroll?.removeListener(_parallax);
    _scroll?.dispose();
    UnlockNumbersApp.camera.value = 0;
    super.dispose();
  }

  void _parallax() {
    final sc = _scroll;
    if (sc == null || !sc.hasClients) return;
    UnlockNumbersApp.camera.value = sc.position.maxScrollExtent - sc.offset;
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final size = MediaQuery.sizeOf(context);
    final total = s.levels.total;
    final geo = _geo ??= MapGeometry(width: math.min(size.width, 560), total: total, spacing: s.config.mapSpacing);
    final progress = s.player.progress;
    if (_scroll == null) {
      final current = progress.currentLevel(total);
      final target = (geo.y(current) - size.height * 0.62).clamp(0.0, geo.height - size.height);
      _scroll = ScrollController(initialScrollOffset: target)..addListener(_parallax);
      WidgetsBinding.instance.addPostFrameCallback((_) => _parallax());
    }
    final scroll = _scroll!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        Center(
          child: SizedBox(
            width: geo.width,
            child: SingleChildScrollView(
              controller: scroll,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: geo.width,
                height: geo.height,
                child: ListenableBuilder(
                  listenable: scroll,
                  builder: (context, _) {
                    final top = scroll.hasClients ? scroll.offset : (scroll.initialScrollOffset);
                    final bottom = top + size.height;
                    final first = math.max(1, ((geo.height - bottom) / geo.spacing - 2).floor());
                    final last = math.min(total, ((geo.height - top) / geo.spacing + 1).ceil());
                    return Stack(children: [
                      Positioned.fill(child: CustomPaint(painter: _RoadPainter(s.theme.tokens, geo, first, last, progress.highestUnlocked))),
                      for (var l = first; l <= last; l++)
                        Positioned(
                          left: geo.x(l) - 40,
                          top: geo.y(l) - 40,
                          width: 80,
                          height: 92,
                          child: _LevelNode(level: l, state: progress.stateOf(l, openAhead: s.config.openAhead), stars: progress.starsOf(l), fog: _fog(l, progress.highestUnlocked)),
                        ),
                    ]);
                  },
                ),
              ),
            ),
          ),
        ),
        SafeArea(child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 8), child: Plaque(s.i18n.t('map.title'))))),
        SafeArea(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: HomeGate(onTap: () => openHome(context))))),
      ]),
    );
  }

  /// Later levels emerge from the mist.
  static double _fog(int level, int highest) => ((level - highest - 2) / 10).clamp(0.0, 0.85);
}

class _LevelNode extends StatelessWidget {
  const _LevelNode({required this.level, required this.state, required this.stars, required this.fog});

  final int level;
  final LevelNodeState state;
  final int stars;
  final double fog;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final locked = state == LevelNodeState.locked;
    Widget node = Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 80,
        height: 70,
        child: CustomPaint(
          painter: _PlatformPainter(t, state),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: locked
                  ? GlyphIcon(Glyph.lock, size: 22, color: t.color('text.muted'))
                  : Text('$level', style: UiText.numbers(context, size: 22, color: state == LevelNodeState.current ? t.color('text.onGold') : t.color('text.onStone'), shadow: state != LevelNodeState.current)),
            ),
          ),
        ),
      ),
      if (state == LevelNodeState.completed) StarRow(stars: stars, size: 15),
    ]);
    if (state == LevelNodeState.current) {
      node = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.9, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.elasticOut,
        builder: (context, v, child) => Transform.scale(scale: v, child: child),
        child: node,
      );
    }
    return Opacity(
      opacity: 1 - fog,
      child: Pressable(
        onTap: () {
          if (locked) {
            showToast(context, s.i18n.t('map.lockedToast', {'n': s.player.progress.highestUnlocked}), glyph: Glyph.lock);
          } else {
            playLevel(context, level);
          }
        },
        semantics: s.i18n.t('common.level', {'n': level}),
        child: node,
      ),
    );
  }
}

class _PlatformPainter extends CustomPainter {
  _PlatformPainter(this.t, this.state);

  final ThemeTokens t;
  final LevelNodeState state;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, size.height * 0.2, size.width - 8, size.height * 0.72);
    final top = Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.62);
    final current = state == LevelNodeState.current;
    final done = state == LevelNodeState.completed;
    if (current) paintGlow(canvas, top.center, size.width * 0.75, t.color('gold.glow'), 0.9);
    if (done) paintGlow(canvas, top.center, size.width * 0.55, t.color('crystal.blue'), 0.35 * t.number('crystal.intensity', 0.6) + 0.15);
    final side = RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 4, top.center.dy, r.width - 8, r.height * 0.42), Radius.circular(r.height * 0.3));
    canvas.drawRRect(side.shift(const Offset(0, 4)), Paint()..color = alpha(t.color('text.shadow'), 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(side, Paint()..shader = gLinear(side.outerRect.topCenter, side.outerRect.bottomCenter, [t.color('stone.base'), t.color('stone.deep')]));
    final face = current
        ? [t.color('gold.light'), t.color('gold.base')]
        : state == LevelNodeState.locked
            ? [t.color('stone.dark'), t.color('stone.deep')]
            : [t.color('stone.light'), t.color(done ? 'stone.blue' : 'stone.base')];
    canvas.drawOval(top, Paint()..shader = gLinear(top.topCenter, top.bottomCenter, face));
    canvas.drawOval(top, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = state == LevelNodeState.locked ? t.color('stone.mortar') : t.color('gold.base'));
    if (state == LevelNodeState.open) canvas.drawOval(top.deflate(4), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = t.color('ui.focus'));
  }

  @override
  bool shouldRepaint(_PlatformPainter old) => old.state != state || old.t != t;
}

/// The road, built from repeatable parts drawn only where visible: slab
/// segments that curve between platforms, supporting pillars into the
/// clouds, a bridge with rails every ten levels, lamps and greenery.
class _RoadPainter extends CustomPainter {
  _RoadPainter(this.t, this.g, this.first, this.last, this.highest);

  final ThemeTokens t;
  final MapGeometry g;
  final int first;
  final int last;
  final int highest;

  @override
  void paint(Canvas canvas, Size size) {
    final from = math.max(0, first - 1);
    final to = math.min(g.total + 1, last + 1);
    for (var l = from; l < to; l++) {
      final bridge = (l + 1) % 10 == 0;
      _segment(canvas, l, bridge);
    }
    for (var l = math.max(1, from); l <= to; l++) {
      if (l % 2 == 0) _pillar(canvas, g.at(l + 0.5), l);
      if (l % 5 == 0) _lamp(canvas, g.at(l + 0.35) + Offset((l % 10 == 0 ? -1 : 1) * 34, -6));
      if (l % 3 == 1) _plants(canvas, g.at(l + 0.6), l);
    }
    for (var l = math.max(highest + 3, from); l <= to; l++) {
      final p = g.at(l);
      final a = ((l - highest - 2) / 12).clamp(0.0, 0.8);
      canvas.drawOval(Rect.fromCenter(center: p, width: g.width * 0.9, height: g.spacing * 1.1), Paint()..shader = gRadial(p, g.width * 0.45, [alpha(t.color('water.mist'), a * 0.8), alpha(t.color('water.mist'), 0)]));
    }
  }

  void _segment(Canvas canvas, int l, bool bridge) {
    final path = Path();
    for (var k = 0; k <= 10; k++) {
      final p = g.at(l + k / 10);
      if (k == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final width = bridge ? 26.0 : 34.0;
    canvas.drawPath(path.shift(const Offset(0, 7)), Paint()..style = PaintingStyle.stroke..strokeWidth = width..strokeCap = StrokeCap.round..color = alpha(t.color('text.shadow'), 0.35));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = width + 6..strokeCap = StrokeCap.round..color = t.color(bridge ? 'gold.dark' : 'stone.deep'));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = width..strokeCap = StrokeCap.round..color = t.color(bridge ? 'island.earth' : 'stone.base'));
    for (final m in path.computeMetrics()) {
      for (var d = 6.0; d < m.length; d += 14) {
        final tan = m.getTangentForOffset(d)!;
        final n = Offset(-tan.vector.dy, tan.vector.dx);
        canvas.drawLine(tan.position - n * (width * 0.42), tan.position + n * (width * 0.42), Paint()..color = alpha(t.color(bridge ? 'gold.deep' : 'stone.mortar'), 0.7)..strokeWidth = 1.6);
      }
      if (bridge) {
        for (final side in [-1.0, 1.0]) {
          final rail = Path();
          for (var d = 0.0; d <= m.length; d += 6) {
            final tan = m.getTangentForOffset(d)!;
            final n = Offset(-tan.vector.dy, tan.vector.dx);
            final p = tan.position + n * (width * 0.6 * side) - Offset(0, 6);
            d == 0 ? rail.moveTo(p.dx, p.dy) : rail.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(rail, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('gold.base'));
        }
      }
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = alpha(t.color('stone.light'), 0.6));
  }

  void _pillar(Canvas canvas, Offset top, int l) {
    final h = g.spacing * (0.7 + 0.3 * hashUnit(l, 2));
    final rect = Rect.fromLTWH(top.dx - 9, top.dy + 8, 18, h);
    canvas.drawRect(rect, Paint()..shader = gLinear(rect.topCenter, rect.bottomCenter, [t.color('stone.base'), alpha(t.color('stone.deep'), 0)]));
    canvas.drawRect(Rect.fromLTWH(rect.left - 3, rect.top, rect.width + 6, 6), Paint()..color = t.color('gold.dark'));
  }

  void _lamp(Canvas canvas, Offset p) {
    canvas.drawLine(p, p + const Offset(0, 26), Paint()..color = t.color('stone.dark')..strokeWidth = 3);
    paintGlow(canvas, p - const Offset(0, 6), 24, t.color('lamp.glow'), 0.4 + 0.6 * t.number('lamp.intensity', 0.4));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p - const Offset(0, 6), width: 10, height: 13), const Radius.circular(3)), Paint()..color = t.color('lamp.light'));
  }

  void _plants(Canvas canvas, Offset p, int l) {
    final dir = hashUnit(l, 9) < 0.5 ? -1.0 : 1.0;
    final base = p + Offset(dir * 26, 4);
    for (var k = 0; k < 3; k++) {
      final a = -math.pi / 2 + (k - 1) * 0.5 * dir;
      final tip = base + Offset(math.cos(a), math.sin(a)) * (12 + 4.0 * k);
      canvas.drawLine(base, tip, Paint()..color = t.color(k == 1 ? 'plant.leafLight' : 'plant.leaf')..strokeWidth = 4..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.first != first || old.last != last || old.t != t || old.highest != highest;
}
