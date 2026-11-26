import 'package:flutter/material.dart';

import '../../core/challenge/challenge_system.dart';
import '../../core/model/puzzle_definition.dart';
import '../../services/app_services.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../challenge/challenge_screen.dart';
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

Widget gameScreenFor(PuzzleDefinition puzzle, {ChallengeRun? run}) => GameScreen(puzzle: puzzle, run: run);

void openHome(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

void openLevels(BuildContext context) => Navigator.push(context, portalRoute(const LevelsMapScreen()));

void openChallenge(BuildContext context) => Navigator.push(context, portalRoute(const ChallengeScreen()));

void openSettings(BuildContext context) => Navigator.push(context, portalRoute(const SettingsScreen()));

void openGuide(BuildContext context) => Navigator.push(context, portalRoute(const GuideScreen()));

void openShop(BuildContext context) => Navigator.push(context, portalRoute(const ShopScreen()));

/// Opens a fixed level: resumes its saved attempt (or restarts on request).
Future<void> playLevel(BuildContext context, int level, {bool replace = false, bool askResume = true}) async {
  final s = Services.of(context, listen: false);
  final puzzle = await s.levels.level(level);
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

/// Continues the saved challenge, or forges the puzzle of the run's tier.
Future<void> launchChallenge(BuildContext context, {required bool resume, bool replace = false}) async {
  final s = Services.of(context, listen: false);
  final now = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
  var run = await s.save.loadChallengeRun();
  if (!resume || run == null) {
    if (!replace || run == null) {
      run = ChallengeRun.fresh(ChallengeDirector.freshSeed(now, 1));
      await s.save.clearAttempt(PuzzleMode.challenge.key);
    }
  }
  if (resume) {
    final saved = await s.save.loadAttempt(PuzzleMode.challenge.key);
    if (saved != null && context.mounted) {
      final route = portalRoute<void>(GameScreen(puzzle: saved.puzzle, resume: saved, run: run));
      replace ? await Navigator.pushReplacement(context, route) : await Navigator.push(context, route);
      return;
    }
  }
  await s.save.saveChallengeRun(run);
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  final forging = showStoneDialog<void>(
    context,
    dismissible: false,
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 120, height: 120, child: Loop(period: const Duration(seconds: 3), builder: (context, ph) => CustomPaint(painter: CrystalPainter(s.theme.tokens, ph)))),
      const SizedBox(height: 10),
      Text(s.i18n.t('challenge.generating'), textAlign: TextAlign.center, style: UiText.style(context, size: 16)),
    ]),
  );
  PuzzleDefinition? puzzle;
  var seed = run.seed;
  for (var attempt = 0; attempt < 4 && puzzle == null; attempt++) {
    final generated = await s.compute.run(s.challenges.jobFor(run.tier, seed), units: 1);
    if (generated != null && !run.recent.contains(generated.layout.fingerprint())) {
      puzzle = s.challenges.toPuzzle(generated, tier: run.tier, seed: seed);
    } else {
      seed = ChallengeDirector.freshSeed(seed, attempt + 7);
    }
  }
  run.seed = seed;
  if (puzzle != null) run.remember(puzzle.layout.fingerprint());
  await s.save.saveChallengeRun(run);
  if (!nav.mounted) return;
  nav.pop();
  await forging;
  if (puzzle == null || !nav.mounted) return;
  final route = portalRoute<void>(GameScreen(puzzle: puzzle, run: run));
  replace ? await nav.pushReplacement(route) : await nav.push(route);
}
