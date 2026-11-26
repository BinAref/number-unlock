import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/model/puzzle_definition.dart';
import '../../services/app_services.dart';
import '../../services/audio_service.dart';
import '../../services/theme_service.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../common/navigation.dart';

/// Emblems a player can pick as their portrait.
const List<Glyph> kEmblems = [Glyph.sparkle, Glyph.lock, Glyph.hint, Glyph.gear, Glyph.music, Glyph.globe, Glyph.shield, Glyph.theme];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _unlock = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  bool _hasLevelSave = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _unlock.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = Services.of(context, listen: false);
    final saved = await s.save.loadAttempt(PuzzleMode.levels.key);
    final current = s.player.progress.currentLevel(s.levels.total);
    if (mounted) setState(() => _hasLevelSave = saved?.puzzle.levelNumber == current);
  }

  Future<void> _play() async {
    final s = Services.of(context, listen: false);
    s.audio.play(Sfx.unlock);
    await _unlock.forward(from: 0);
    if (!mounted) return;
    await playLevel(context, s.player.progress.currentLevel(s.levels.total), askResume: false);
    _unlock.reset();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final size = MediaQuery.sizeOf(context);
    final w = math.min(size.width, 560.0);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(children: [
        _TopArch(width: size.width),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final logo = math.min(w * 0.86, c.maxHeight * 1.3);
            return Stack(alignment: Alignment.center, children: [
              SizedBox(width: logo * 0.86, height: logo * 0.86, child: Loop(period: const Duration(seconds: 20), builder: (context, ph) => CustomPaint(painter: PortalPainter(s.theme.tokens, ph)))),
              GameLogo(width: logo),
            ]);
          }),
        ),
        SizedBox(
          width: w,
          height: math.min(330, size.height * 0.42),
          child: ListenableBuilder(listenable: s.player, builder: (context, _) => _Terrace(onPlay: _play, unlock: _unlock, hasSave: _hasLevelSave, onReturn: _refresh)),
        ),
        SizedBox(height: MediaQuery.paddingOf(context).bottom + 6),
      ]),
    );
  }
}

class _TopArch extends StatelessWidget {
  const _TopArch({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: top + 128,
      child: Loop(
        period: const Duration(seconds: 6),
        builder: (context, ph) => CustomPaint(
          painter: ArchPainter(t, math.sin(ph * math.pi * 2)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top + 10, 16, 34),
            child: ListenableBuilder(
              listenable: s.player,
              builder: (context, _) {
                final p = s.player;
                final lvl = p.level;
                return Row(children: [
                  Pressable(onTap: () => openSettings(context), child: _Portrait(emblem: kEmblems[p.profile.avatar % kEmblems.length])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(p.profile.name ?? s.i18n.t('profile.defaultName'), style: UiText.style(context, size: 17), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text(s.i18n.t('home.playerLevel', {'n': lvl.level}), style: UiText.style(context, size: 13, color: t.color('text.accent'))),
                        const SizedBox(width: 8),
                        Expanded(child: _ProgressGroove(value: lvl.progress)),
                        const SizedBox(width: 6),
                        Text(s.i18n.t('home.progress', {'p': (lvl.progress * 100).round()}), style: UiText.numbers(context, size: 12)),
                      ]),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  CoinCounter(onAdd: () => openShop(context)),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.emblem});

  final Glyph emblem;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return SizedBox(
      width: 56,
      height: 56,
      child: CustomPaint(painter: _PortraitPainter(t), child: Center(child: GlyphIcon(emblem, size: 26, color: t.color('gold.light')))),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    paintGlow(canvas, c, r * 1.5, t.color('crystal.purple'), 0.4);
    canvas.drawCircle(c, r, Paint()..shader = gRadial(c, r, [t.color('stone.purple'), t.color('ui.panelDeep')]));
    canvas.drawCircle(c, r - 2, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..shader = gLinear(Offset.zero, Offset(size.width, size.height), [t.color('gold.light'), t.color('gold.dark')]));
  }

  @override
  bool shouldRepaint(_PortraitPainter old) => old.t != t;
}

/// The progress bar, carved into the stone.
class _ProgressGroove extends StatelessWidget {
  const _ProgressGroove({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => CustomPaint(size: const Size(double.infinity, 12), painter: _GroovePainter(t, v)),
    );
  }
}

class _GroovePainter extends CustomPainter {
  _GroovePainter(this.t, this.v);

  final ThemeTokens t;
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    paintRecess(canvas, rr, t);
    if (v > 0) {
      final fill = RRect.fromRectAndRadius(Rect.fromLTWH(1.5, 1.5, (size.width - 3) * v, size.height - 3), Radius.circular(size.height / 2));
      canvas.drawRRect(fill, Paint()..shader = gLinear(Offset.zero, Offset(size.width, 0), [t.color('ui.progress'), t.color('ui.progressGlow')]));
      paintGlow(canvas, Offset(fill.right, size.height / 2), size.height * 1.6, t.color('ui.progressGlow'), 0.7);
    }
    canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = t.color('gold.base'));
  }

  @override
  bool shouldRepaint(_GroovePainter old) => old.v != v || old.t != t;
}

/// The stone terrace: the golden lock (play) at the centre, the challenge
/// crystal above it, map and book to one side, chest and gear to the other.
class _Terrace extends StatelessWidget {
  const _Terrace({required this.onPlay, required this.unlock, required this.hasSave, required this.onReturn});

  final VoidCallback onPlay;
  final Animation<double> unlock;
  final bool hasSave;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final i18n = s.i18n;
    final level = s.player.progress.currentLevel(s.levels.total);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final item = math.min(w * 0.25, h * 0.36);
      Widget object(Widget art, String label, VoidCallback onTap, {double scale = 1}) => Pressable(
            onTap: () async {
              onTap();
            },
            semantics: label,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: item * scale, height: item * scale, child: art),
              Text(label, textAlign: TextAlign.center, style: UiText.style(context, size: 13)),
            ]),
          );
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(left: w * 0.03, top: h * 0.02, child: object(Loop(period: const Duration(seconds: 5), builder: (context, ph) => CustomPaint(painter: MapPainter(t, math.sin(ph * math.pi * 2) * 0.6))), i18n.t('home.levels'), () => openLevels(context))),
        Positioned(left: w * 0.04, bottom: h * 0.02, child: object(Loop(period: const Duration(seconds: 4), builder: (context, ph) => CustomPaint(painter: BookPainter(t, open: 0.8 + 0.2 * math.sin(ph * math.pi * 2), flutter: math.sin(ph * math.pi * 4)))), i18n.t('home.guide'), () => openGuide(context))),
        Positioned(right: w * 0.03, top: h * 0.02, child: object(Loop(period: const Duration(seconds: 4), builder: (context, ph) => CustomPaint(painter: ChestPainter(t, lid: 0.18 + 0.12 * math.sin(ph * math.pi * 2), sparkle: ph))), i18n.t('home.shop'), () => openShop(context))),
        Positioned(right: w * 0.05, bottom: h * 0.02, child: object(Loop(period: s.design.motion('gear'), builder: (context, ph) => CustomPaint(painter: GearPainter(t, ph * math.pi * 2))), i18n.t('home.settings'), () => openSettings(context), scale: 0.85)),
        Positioned(
          left: (w - item) / 2,
          top: 0,
          child: object(Loop(period: const Duration(seconds: 4), builder: (context, ph) => CustomPaint(painter: CrystalPainter(t, ph))), i18n.t('home.challenge'), () => openChallenge(context), scale: 0.9),
        ),
        Positioned(
          left: (w - item * 1.5) / 2,
          bottom: 0,
          child: Pressable(
            onTap: onPlay,
            sound: null,
            semantics: i18n.t('home.play'),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: item * 1.5,
                height: item * 1.3,
                child: AnimatedBuilder(
                  animation: unlock,
                  builder: (context, _) => Loop(
                    period: const Duration(milliseconds: 2400),
                    builder: (context, ph) => CustomPaint(painter: LockPainter(t, pulse: 0.5 + 0.5 * math.sin(ph * math.pi * 2), open: Curves.easeOutBack.transform(unlock.value))),
                  ),
                ),
              ),
              Plaque(hasSave ? i18n.t('home.continue') : i18n.t('home.play'), size: 18),
              const SizedBox(height: 2),
              Text(i18n.t('home.levelLabel', {'n': level}), style: UiText.style(context, size: 13, color: t.color('text.accent'))),
            ]),
          ),
        ),
      ]);
    });
  }
}
