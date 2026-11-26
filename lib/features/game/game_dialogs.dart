import 'package:flutter/material.dart';

import '../../core/boosters/booster_system.dart';
import '../../core/endless/endless_stats.dart';
import '../../core/engine/game_engine.dart';
import '../../core/model/puzzle_definition.dart';
import '../../services/app_services.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/widgets.dart';
import '../common/navigation.dart';
import 'game_controller.dart';

/// Asks how to pay for a booster: coins, or an ad when allowed.
Future<Payment?> _choosePayment(BuildContext context, {required String title, required String body, required int coins, required bool adAllowed, String? note}) {
  final s = Services.of(context, listen: false);
  return showStoneDialog<Payment>(
    context,
    title: title,
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text(body, textAlign: TextAlign.center, style: UiText.style(context, size: 16)),
      if (note != null) ...[const SizedBox(height: 8), Text(note, textAlign: TextAlign.center, style: UiText.style(context, size: 13, color: s.theme.tokens.color('text.accent')))],
      const SizedBox(height: 18),
      StoneButton(
        label: s.i18n.t('game.payCoins', {'n': s.i18n.plural('coins.count', coins)}),
        primary: true,
        onTap: () => Navigator.pop(context, Payment.coins),
      ),
      if (adAllowed) ...[
        const SizedBox(height: 10),
        StoneButton(label: s.i18n.t('game.payAd'), glyph: Glyph.film, onTap: () => Navigator.pop(context, Payment.ad)),
      ],
      const SizedBox(height: 10),
      StoneButton(label: s.i18n.t('common.cancel'), dense: true, onTap: () => Navigator.pop(context)),
    ]),
  );
}

void _report(BuildContext context, BoosterResult result, {required bool viaAd}) {
  final i18n = Services.of(context, listen: false).i18n;
  switch (result) {
    case BoosterResult.done:
      if (viaAd) showToast(context, i18n.t('ads.watched'), glyph: Glyph.check);
    case BoosterResult.insufficient:
      _offerShop(context);
    case BoosterResult.adClosed:
      showToast(context, i18n.t('ads.closedEarly'));
    case BoosterResult.adFailed:
      showToast(context, i18n.t('ads.failed'));
    case BoosterResult.noHint:
      showToast(context, i18n.t('game.hintNone'));
    case BoosterResult.unsure:
      showToast(context, i18n.t('game.hintUnsure'));
    case BoosterResult.unavailable:
      break;
  }
}

void _offerShop(BuildContext context) {
  final i18n = Services.of(context, listen: false).i18n;
  showStoneDialog<void>(
    context,
    title: i18n.t('game.noCoins'),
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text(i18n.t('shop.useFor'), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
      const SizedBox(height: 16),
      StoneButton(label: i18n.t('game.getCoins'), primary: true, onTap: () {
        Navigator.pop(context);
        openShop(context);
      }),
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('common.close'), dense: true, onTap: () => Navigator.pop(context)),
    ]),
  );
}

Future<void> boosterSlot(BuildContext context, GameController game) async {
  final s = Services.of(context, listen: false);
  if (game.engine.boosters.extraSlot) return showToast(context, s.i18n.t('booster.alreadyOpen'));
  final pay = await _choosePayment(context,
      title: s.i18n.t('booster.slot.title'), body: s.i18n.t('booster.slot.body'), coins: game.boosterRules.extraSlotCoins, adAllowed: game.boosterRules.extraSlotByAd);
  if (pay == null || !context.mounted) return;
  final r = await game.addSlot(pay);
  if (context.mounted) _report(context, r, viaAd: pay == Payment.ad);
}

Future<void> boosterHint(BuildContext context, GameController game) async {
  final s = Services.of(context, listen: false);
  final pay = await _choosePayment(context,
      title: s.i18n.t('booster.hint.title'),
      body: s.i18n.t('booster.hint.body'),
      coins: game.boosterRules.hintCoins,
      adAllowed: game.adHintsLeft > 0,
      note: s.i18n.t('booster.adLimit', {'n': game.engine.boosters.adHints, 'max': game.boosterRules.hintAdLimit}));
  if (pay == null || !context.mounted) return;
  final r = await game.useHint(pay);
  if (!context.mounted) return;
  _report(context, r, viaAd: pay == Payment.ad);
  if (r == BoosterResult.noHint && (game.rescues?.isNotEmpty ?? false)) showToast(context, s.i18n.t('game.hintRescue'));
}

Future<void> boosterSwap(BuildContext context, GameController game) async {
  final s = Services.of(context, listen: false);
  if (game.engine.tray.length < 2) return showToast(context, s.i18n.t('game.swapNeedTwo'));
  final pay = await _choosePayment(context, title: s.i18n.t('booster.swap.title'), body: s.i18n.t('booster.swap.body'), coins: game.boosterRules.swapCoins, adAllowed: false);
  if (pay == null || !context.mounted) return;
  _report(context, game.startSwap(), viaAd: false);
}

Future<void> showPauseDialog(BuildContext context, GameController game) {
  final s = Services.of(context, listen: false);
  final i18n = s.i18n;
  return showStoneDialog<void>(
    context,
    title: i18n.t('game.paused'),
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      StoneButton(label: i18n.t('game.resume'), glyph: Glyph.play, primary: true, onTap: () => Navigator.pop(context)),
      // An endless board cannot be restarted: one try per board.
      if (game.mode == PuzzleMode.levels) ...[
        const SizedBox(height: 10),
        StoneButton(label: i18n.t('game.restart'), glyph: Glyph.restart, onTap: () {
          Navigator.pop(context);
          s.save.clearAttempt(game.mode.key);
          Navigator.pushReplacement(context, portalRoute(gameScreenFor(game.puzzle)));
        }),
      ],
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('game.quit'), glyph: Glyph.home, onTap: () {
        Navigator.pop(context);
        openHome(context);
      }),
      const SizedBox(height: 14),
      ListenableBuilder(
        listenable: s.player,
        builder: (context, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _QuickToggle(glyph: Glyph.music, value: s.player.settings.music, onChanged: (v) {
            s.player.updateSettings((x) => x.music = v);
            s.audio.setMusic(v);
          }),
          _QuickToggle(glyph: Glyph.sound, value: s.player.settings.sfx, onChanged: (v) {
            s.player.updateSettings((x) => x.sfx = v);
            s.audio.setSfx(v);
          }),
        ]),
      ),
    ]),
  );
}

class _QuickToggle extends StatelessWidget {
  const _QuickToggle({required this.glyph, required this.value, required this.onChanged});

  final Glyph glyph;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [GlyphIcon(glyph, size: 22), const SizedBox(width: 8), StoneToggle(value: value, onChanged: onChanged)]);
}

Future<void> showWinDialog(BuildContext context, GameController game) {
  if (game.mode == PuzzleMode.endless) return _showBoardCleared(context, game);
  final s = Services.of(context, listen: false);
  final i18n = s.i18n;
  final t = s.theme.tokens;
  final reward = game.reward;
  final level = game.puzzle.levelNumber ?? 1;
  return showStoneDialog<void>(
    context,
    title: i18n.t('win.title'),
    dismissible: false,
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.elasticOut,
        builder: (context, v, child) => Transform.scale(scale: 0.4 + 0.6 * v, child: child),
        child: StarRow(stars: game.stars, size: 46),
      ),
      if (game.stars == 3) Text(i18n.t('win.perfect'), style: UiText.style(context, size: 16, color: t.color('text.accent'))),
      const SizedBox(height: 12),
      if (reward != null && reward.coins > 0)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: reward.coins),
            duration: s.motion('coinFly'),
            builder: (context, v, _) => Text(i18n.t('win.reward', {'n': v}), style: UiText.numbers(context, size: 24, color: t.color('text.accent'))),
          ),
          const SizedBox(width: 4),
          const GlyphIcon(Glyph.sparkle, size: 18),
        ]),
      const SizedBox(height: 18),
      if (level < s.levels.total)
        StoneButton(label: i18n.t('win.next'), primary: true, glyph: Glyph.arrowRight, onTap: () {
          Navigator.pop(context);
          playLevel(context, level + 1, replace: true, askResume: false);
        })
      else
        Text(i18n.t('win.allDone'), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('win.replay'), glyph: Glyph.restart, onTap: () {
        Navigator.pop(context);
        Navigator.pushReplacement(context, portalRoute(gameScreenFor(game.puzzle)));
      }),
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('common.home'), glyph: Glyph.home, dense: true, onTap: () {
        Navigator.pop(context);
        openHome(context);
      }),
    ]),
  );
}

/// An endless board is cleared: its points are counted, added to the run
/// total, and the next board follows on its own after a short moment — the
/// run feels like one continuous journey, never a return to a menu.
Future<void> _showBoardCleared(BuildContext context, GameController game) {
  final s = Services.of(context, listen: false);
  return showStoneDialog<void>(
    context,
    title: s.i18n.t('endless.board', {'n': game.puzzle.boardNumber ?? 1}),
    dismissible: false,
    builder: (dialogContext) => _BoardCleared(
      game: game,
      onDone: () {
        Navigator.pop(dialogContext);
        launchEndless(context, fresh: false, replace: true);
      },
    ),
  );
}

class _BoardCleared extends StatefulWidget {
  const _BoardCleared({required this.game, required this.onDone});

  final GameController game;
  final VoidCallback onDone;

  @override
  State<_BoardCleared> createState() => _BoardClearedState();
}

class _BoardClearedState extends State<_BoardCleared> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    widget.game.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_scheduled || widget.game.scoring) return;
    _scheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context, listen: false);
    final i18n = s.i18n;
    final t = s.theme.tokens;
    final game = widget.game;
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (game.scoring)
          Text(i18n.t('endless.counting'), style: UiText.style(context, size: 15, color: t.color('text.muted')))
        else ...[
          Text(i18n.t('endless.points', {'n': game.puzzlePoints ?? 0}), style: UiText.numbers(context, size: 26, color: t.color('text.accent'))),
          Text(i18n.t('endless.accuracy', {'p': ((game.sheet?.quality ?? 0) * 100).round()}), style: UiText.style(context, size: 14)),
          Text(i18n.t('endless.runTotal', {'n': s.endless.run?.score ?? 0}), style: UiText.numbers(context, size: 16)),
          if (game.boardCoins > 0) Text(i18n.t('win.reward', {'n': game.boardCoins}), style: UiText.numbers(context, size: 16, color: t.color('text.accent'))),
        ],
      ]),
    );
  }
}

/// The end of an endless run: the total, the boards cleared and how it
/// compares with the record — then a new run or home.
Future<void> showRunSummary(BuildContext context, RunSummary summary) {
  final s = Services.of(context, listen: false);
  final i18n = s.i18n;
  final t = s.theme.tokens;
  return showStoneDialog<void>(
    context,
    title: i18n.t('endless.runOver'),
    dismissible: false,
    builder: (dialogContext) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text(i18n.t('endless.runTotal', {'n': summary.score}), style: UiText.numbers(context, size: 26, color: t.color('text.accent'))),
      const SizedBox(height: 4),
      Text(i18n.t('endless.runSummary', {'n': summary.boards}), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
      const SizedBox(height: 8),
      if (summary.newRecord)
        Text(i18n.t('endless.newBest'), style: UiText.style(context, size: 18, color: t.color('ui.success')))
      else
        Text(i18n.t('endless.best', {'n': s.player.endless.best}), style: UiText.numbers(context, size: 14)),
      const SizedBox(height: 16),
      StoneButton(label: i18n.t('endless.start'), primary: true, glyph: Glyph.restart, onTap: () {
        Navigator.pop(dialogContext);
        launchEndless(context, fresh: true, replace: true);
      }),
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('common.home'), glyph: Glyph.home, dense: true, onTap: () {
        Navigator.pop(dialogContext);
        openHome(context);
      }),
    ]),
  );
}

Future<void> showLoseDialog(BuildContext context, GameController game) {
  final s = Services.of(context, listen: false);
  final i18n = s.i18n;
  final endless = game.mode == PuzzleMode.endless;

  Future<void> endRun() async {
    final summary = await game.finishRun();
    if (context.mounted) await showRunSummary(context, summary);
  }
  return showStoneDialog<void>(
    context,
    title: i18n.t('lose.title'),
    dismissible: false,
    builder: (context) => ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final rescues = game.rescues ?? const <RescueOption>[];
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(i18n.t(game.engine.lossReason == LossReason.leftovers ? 'lose.leftovers' : 'lose.trayFull'),
              textAlign: TextAlign.center, style: UiText.style(context, size: 16)),
          if (endless) Text(i18n.t('endless.runTotal', {'n': s.endless.run?.score ?? 0}), style: UiText.numbers(context, size: 16)),
          if (endless) Text(i18n.t('endless.best', {'n': s.player.endless.best}), style: UiText.numbers(context, size: 14)),
          const SizedBox(height: 14),
          if (game.rescueChecking)
            Text(i18n.t('lose.checking'), style: UiText.style(context, size: 14, color: s.theme.tokens.color('text.muted')))
          else if (rescues.isNotEmpty) ...[
            Text(i18n.t('lose.rescueTitle'), style: UiText.style(context, size: 15, color: s.theme.tokens.color('text.accent'))),
            const SizedBox(height: 10),
            for (final r in rescues) ...[
              StoneButton(
                label: i18n.t(r.kind == RescueKind.extraSlot ? 'booster.slot.title' : 'booster.swap.title'),
                glyph: r.kind == RescueKind.extraSlot ? Glyph.slotPlus : Glyph.swap,
                primary: true,
                onTap: () {
                  Navigator.pop(context);
                  if (r.kind == RescueKind.extraSlot) {
                    boosterSlot(context, game);
                  } else {
                    boosterSwap(context, game);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ] else
            Text(i18n.t('lose.noRescue'), textAlign: TextAlign.center, style: UiText.style(context, size: 14, color: s.theme.tokens.color('text.muted'))),
          const SizedBox(height: 12),
          if (!endless)
            StoneButton(label: i18n.t('lose.retry'), glyph: Glyph.restart, onTap: () {
              Navigator.pop(context);
              game.abandon();
              Navigator.pushReplacement(context, portalRoute(gameScreenFor(game.puzzle)));
            }),
          if (endless)
            StoneButton(label: i18n.t('lose.endRun'), glyph: Glyph.close, onTap: () {
              Navigator.pop(context);
              endRun();
            }),
          const SizedBox(height: 8),
          StoneButton(label: i18n.t('common.home'), glyph: Glyph.home, dense: true, onTap: () async {
            Navigator.pop(context);
            // Leaving a lost endless board ends the run and records it.
            if (endless) {
              await game.finishRun();
            } else {
              game.abandon();
            }
            if (context.mounted) openHome(context);
          }),
        ]);
      },
    ),
  );
}
