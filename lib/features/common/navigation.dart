import 'package:flutter/material.dart';

import '../../core/model/puzzle_definition.dart';
import '../../services/app_services.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../endless/endless_screen.dart';
import '../game/game_screen.dart';
import '../guide/guide_screen.dart';
import '../levels/levels_map_screen.dart';
import '../settings/settings_screen.dart';
import '../shop/shop_screen.dart';

/// Pages glide in through a soft fade and rise (the world stays behind).
PageRoute<T> portalRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, _, __) => page,
      transitionsBuilder: (context, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        );
      },
    );

Widget gameScreenFor(PuzzleDefinition puzzle) => GameScreen(puzzle: puzzle);

void openHome(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

void openLevels(BuildContext context) => Navigator.push(context, portalRoute(const LevelsMapScreen()));

void openEndless(BuildContext context) => Navigator.push(context, portalRoute(const EndlessScreen()));

void openSettings(BuildContext context) => Navigator.push(context, portalRoute(const SettingsScreen()));

void openGuide(BuildContext context) => Navigator.push(context, portalRoute(const GuideScreen()));

void openShop(BuildContext context) => Navigator.push(context, portalRoute(const ShopScreen()));

/// Opens a fixed level: resumes its saved attempt (or restarts on request).
Future<void> playLevel(BuildContext context, int level, {bool replace = false, bool askResume = true}) async {
  final s = Services.of(context, listen: false);
  final puzzle = await _withForging(context, level);
  if (puzzle == null) return;
  final saved = await s.save.loadAttempt(PuzzleMode.levels.key);
  var resume = saved != null && saved.puzzle.levelNumber == level && saved.puzzle.layout == puzzle.layout ? saved : null;
  if (!context.mounted) return;
  if (resume != null && askResume) {
    final keep = await showStoneDialog<bool>(
      context,
      title: s.i18n.t('common.level', {'n': level}),
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        StoneButton(label: s.i18n.t('home.continue'), glyph: Glyph.play, primary: true, onTap: () => Navigator.pop(context, true)),
        const SizedBox(height: 10),
        StoneButton(label: s.i18n.t('game.restart'), glyph: Glyph.restart, onTap: () => Navigator.pop(context, false)),
      ]),
    );
    if (keep == null || !context.mounted) return;
    if (!keep) {
      await s.save.clearAttempt(PuzzleMode.levels.key);
      resume = null;
    }
  }
  if (!context.mounted) return;
  final route = portalRoute<void>(GameScreen(puzzle: puzzle, resume: resume));
  if (replace) {
    await Navigator.pushReplacement(context, route);
  } else {
    await Navigator.push(context, route);
  }
}

/// Loads a level, showing the forge while a new one is being made.
Future<PuzzleDefinition?> _withForging(BuildContext context, int level) async {
  final s = Services.of(context, listen: false);
  if (await s.levels.isReady(level)) return s.levels.level(level);
  if (!context.mounted) return null;
  final nav = Navigator.of(context);
  final dialog = showStoneDialog<void>(
    context,
    dismissible: false,
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 110, height: 110, child: Loop(period: const Duration(seconds: 3), builder: (context, ph) => CustomPaint(painter: CrystalPainter(s.theme.tokens, ph)))),
      const SizedBox(height: 10),
      Text(s.i18n.t('levels.forging', {'n': level}), textAlign: TextAlign.center, style: UiText.style(context, size: 16)),
    ]),
  );
  final puzzle = await s.levels.level(level);
  if (nav.mounted) nav.pop();
  await dialog;
  return puzzle;
}

/// Continues the endless run — its saved board, or the run's next board — or
/// starts a fresh run. Boards are prepared ahead in the background, so they
/// usually open at once; a short "preparing" note shows only when a board is
/// still being made.
Future<void> launchEndless(BuildContext context, {required bool fresh, bool replace = false}) async {
  final s = Services.of(context, listen: false);
  final run = fresh ? await s.endless.startRun() : (await s.endless.load() ?? await s.endless.startRun());
  if (!fresh) {
    final saved = await s.save.loadAttempt(PuzzleMode.endless.key);
    if (saved != null && saved.puzzle.boardNumber == run.board && context.mounted) {
      final route = portalRoute<void>(GameScreen(puzzle: saved.puzzle, resume: saved));
      replace ? await Navigator.pushReplacement(context, route) : await Navigator.push(context, route);
      return;
    }
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  final pending = s.endless.board(run.board);
  final ready = await Future.any([
    pending.then((_) => true),
    Future<bool>.delayed(const Duration(milliseconds: 150), () => false),
  ]);
  Future<void>? note;
  if (!ready && context.mounted) {
    note = showStoneDialog<void>(
      context,
      dismissible: false,
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 120, height: 120, child: Loop(period: const Duration(seconds: 3), builder: (context, ph) => CustomPaint(painter: CrystalPainter(s.theme.tokens, ph)))),
        const SizedBox(height: 10),
        Text(s.i18n.t('endless.generating'), textAlign: TextAlign.center, style: UiText.style(context, size: 16)),
      ]),
    );
  }
  final puzzle = await pending;
  if (note != null && nav.mounted) {
    nav.pop();
    await note;
  }
  if (puzzle == null || !nav.mounted) return;
  final route = portalRoute<void>(GameScreen(puzzle: puzzle));
  replace ? await nav.pushReplacement(route) : await nav.push(route);
}
