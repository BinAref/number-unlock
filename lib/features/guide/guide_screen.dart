import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/model/tile_spec.dart';
import '../../core/rules/rule_engine.dart';
import '../../services/app_services.dart';
import '../../services/audio_service.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/tile_view.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../common/page_frame.dart';

/// One page of the magic book.
class _Page {
  const _Page(this.titleKey, this.bodyKey, this.demo);

  final String titleKey;
  final String bodyKey;
  final Widget demo;
}

/// The instructions: a magic book whose pages show moving examples. The
/// rule pages come from the active rule engine, so new rules appear here
/// automatically (with their own `rule.<id>` texts and demo tiles).
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  int _page = 0;

  List<_Page> _pages(AppServices s) {
    final rules = RuleEngine.forPuzzle(s.rules.current, mode: 'levels');
    return [
      const _Page('guide.pick.title', 'guide.pick.body', _BoardDemo(mode: 0)),
      const _Page('guide.unlock.title', 'guide.unlock.body', _BoardDemo(mode: 1)),
      const _Page('guide.fixed.title', 'guide.fixed.body', _BoardDemo(mode: 2)),
      for (final r in rules.rules)
        _Page('rule.${r.id}.title', 'rule.${r.id}.body', _TrayDemo(frames: [
          [const TileSpec(6, 2)],
          [const TileSpec(6, 2), r.demo.first],
          [const TileSpec(6, 2), ...r.demo],
          [const TileSpec(6, 2), ...r.demo.map((t) => TileSpec(t.value, -1 - t.color))],
          [const TileSpec(6, 2)],
        ])),
      const _Page('guide.slots.title', 'guide.slots.body', _TrayDemo(frames: [
        [TileSpec(1, 0)],
        [TileSpec(1, 0), TileSpec(4, 5)],
        [TileSpec(1, 0), TileSpec(4, 5), TileSpec(2, 3)],
        [TileSpec(1, 0), TileSpec(4, 5), TileSpec(2, 3), TileSpec(7, 6)],
        [TileSpec(1, 0), TileSpec(4, 5), TileSpec(2, 3), TileSpec(7, 6), TileSpec(3, 1)],
        [TileSpec(1, 0), TileSpec(4, 5), TileSpec(2, 3), TileSpec(7, -7), TileSpec(3, -2)],
        [TileSpec(1, 0), TileSpec(4, 5), TileSpec(2, 3)],
      ])),
      const _Page('guide.chain.title', 'guide.chain.body', _TrayDemo(frames: [
        [TileSpec(3, 4), TileSpec(2, 0), TileSpec(7, 6), TileSpec(8, 2)],
        [TileSpec(3, 4), TileSpec(8, 2), TileSpec(2, 0), TileSpec(7, 6)],
        [TileSpec(3, 4), TileSpec(8, -3), TileSpec(2, -1), TileSpec(7, 6)],
        [TileSpec(3, 4), TileSpec(7, 6)],
        [TileSpec(3, -5), TileSpec(7, -7)],
        [],
      ])),
      const _Page('guide.win.title', 'guide.win.body', _GlyphDemo([Glyph.sparkle, Glyph.check, Glyph.lock])),
      const _Page('guide.boosters.title', 'guide.boosters.body', _GlyphDemo([Glyph.slotPlus, Glyph.hint, Glyph.swap])),
      const _Page('guide.modes.title', 'guide.modes.body', _ModesDemo()),
    ];
  }

  void _go(int delta, int count) {
    final next = (_page + delta).clamp(0, count - 1);
    if (next == _page) return;
    Services.of(context, listen: false).audio.play(Sfx.page);
    setState(() => _page = next);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final i18n = s.i18n;
    final pages = _pages(s);
    final page = pages[_page];
    final rtl = i18n.current.rtl;
    return PageFrame(
      title: i18n.t('guide.title'),
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 200) return;
          _go((v < 0) != rtl ? 1 : -1, pages.length);
        },
        child: StonePanel(
          seed: 13,
          child: Column(children: [
            AnimatedSwitcher(
              duration: s.motion('page'),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(anim), child: child),
              ),
              child: Column(key: ValueKey(_page), children: [
                SizedBox(height: 170, child: Center(child: page.demo)),
                const SizedBox(height: 10),
                Text(i18n.t(page.titleKey), textAlign: TextAlign.center, style: UiText.style(context, size: 21, color: s.theme.tokens.color('text.accent'))),
                const SizedBox(height: 8),
                SizedBox(height: 92, child: Text(i18n.t(page.bodyKey), textAlign: TextAlign.center, style: UiText.style(context, size: 15))),
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Pressable(onTap: _page > 0 ? () => _go(-1, pages.length) : null, enabled: _page > 0, sound: null, semantics: i18n.t('common.previous'), child: GlyphIcon(rtl ? Glyph.arrowRight : Glyph.arrowLeft, size: 30)),
              Text(i18n.t('guide.page', {'n': _page + 1, 'total': pages.length}), style: UiText.numbers(context, size: 14)),
              Pressable(onTap: _page < pages.length - 1 ? () => _go(1, pages.length) : null, enabled: _page < pages.length - 1, sound: null, semantics: i18n.t('common.next'), child: GlyphIcon(rtl ? Glyph.arrowLeft : Glyph.arrowRight, size: 30)),
            ]),
          ]),
        ),
      ),
    );
  }
}

Widget _tile(BuildContext context, TileSpec spec, double size, {TileLook look = const TileLook()}) {
  final t = Services.of(context).theme.tokens;
  final matching = spec.color < 0;
  final colorSlot = matching ? -1 - spec.color : spec.color;
  return CustomPaint(
    size: Size.square(size),
    painter: TilePainter(t, value: spec.value, colorSlot: colorSlot, look: matching ? const TileLook(match: 1) : look),
  );
}

/// Picking, unlocking and fixed positions on a tiny 3 × 2 board.
class _BoardDemo extends StatelessWidget {
  const _BoardDemo({required this.mode});

  final int mode;

  @override
  Widget build(BuildContext context) {
    const top = [TileSpec(5, 1), TileSpec(8, 4), TileSpec(2, 6)];
    const bottom = [TileSpec(3, 0), TileSpec(9, 3), TileSpec(6, 5)];
    return Loop(
      period: const Duration(milliseconds: 3200),
      builder: (context, ph) {
        final taken = ph > 0.35;
        final unlock = taken ? ((ph - 0.35) / 0.25).clamp(0.0, 1.0) : 0.0;
        const size = 56.0;
        Widget cell(int row, int col) {
          if (row == 1 && col == 1 && taken) {
            return SizedBox.square(
              dimension: size,
              child: mode == 2
                  ? DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Services.of(context).theme.tokens.color('text.muted'), width: 2)))
                  : null,
            );
          }
          final spec = row == 0 ? top[col] : bottom[col];
          final locked = row == 0 && !(taken && col == 1 && mode != 2);
          final pulse = row == 1 && !taken && col == 1 ? 0.5 + 0.5 * math.sin(ph * math.pi * 10) : 0.0;
          return _tile(context, spec, size, look: TileLook(locked: locked, unlock: row == 0 && col == 1 && taken && mode != 2 ? unlock : 0, hint: mode == 0 ? pulse : 0));
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < 2; r++)
            Row(mainAxisSize: MainAxisSize.min, children: [for (var c = 0; c < 3; c++) Padding(padding: const EdgeInsets.all(3), child: cell(r, c))]),
        ]);
      },
    );
  }
}

/// Stop-motion frames of the reception slots.
class _TrayDemo extends StatelessWidget {
  const _TrayDemo({required this.frames});

  final List<List<TileSpec>> frames;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Loop(
      period: Duration(milliseconds: 800 * frames.length),
      builder: (context, ph) {
        final frame = frames[(ph * frames.length).floor().clamp(0, frames.length - 1)];
        const slot = 48.0;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: slot + 8,
              height: slot + 8,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: t.color('slot.socket'), borderRadius: BorderRadius.circular(12), border: Border.all(color: t.color('slot.rim'), width: 2)),
              child: Center(child: i < frame.length ? _tile(context, frame[i], slot) : null),
            ),
        ]);
      },
    );
  }
}

class _GlyphDemo extends StatelessWidget {
  const _GlyphDemo(this.glyphs);

  final List<Glyph> glyphs;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Loop(
      period: const Duration(seconds: 3),
      builder: (context, ph) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < glyphs.length; i++)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Transform.scale(
              scale: 1 + 0.12 * math.sin(ph * math.pi * 2 + i * 2),
              child: CustomPaint(
                size: const Size(72, 72),
                painter: _GemCirclePainter(t),
                child: SizedBox(width: 72, height: 72, child: Center(child: GlyphIcon(glyphs[i], size: 34, color: t.color('gold.light')))),
              ),
            ),
          ),
      ]),
    );
  }
}

class _GemCirclePainter extends CustomPainter {
  _GemCirclePainter(this.t);

  final dynamic t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    paintGlow(canvas, c, size.width * 0.7, t.color('crystal.purple'), 0.5);
    canvas.drawCircle(c, size.width / 2, Paint()..color = t.color('ui.panelDeep'));
    canvas.drawCircle(c, size.width / 2 - 2, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = t.color('gold.base'));
  }

  @override
  bool shouldRepaint(_GemCirclePainter old) => old.t != t;
}

class _ModesDemo extends StatelessWidget {
  const _ModesDemo();

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Loop(
      period: const Duration(seconds: 4),
      builder: (context, ph) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 130, height: 130, child: CustomPaint(painter: MapPainter(t, math.sin(ph * math.pi * 2) * 0.6))),
        const SizedBox(width: 12),
        SizedBox(width: 130, height: 140, child: CustomPaint(painter: CrystalPainter(t, ph))),
      ]),
    );
  }
}
