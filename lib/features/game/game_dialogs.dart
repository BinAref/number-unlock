import 'package:flutter/material.dart';

import '../../core/boosters/booster_system.dart';
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
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('game.restart'), glyph: Glyph.restart, onTap: () {
        Navigator.pop(context);
        s.save.clearAttempt(game.mode.key);
        Navigator.pushReplacement(context, portalRoute(gameScreenFor(game.puzzle, run: game.run)));
      }),
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
  final s = Services.of(context, listen: false);
  final i18n = s.i18n;
  final t = s.theme.tokens;
  final reward = game.reward;
  final levels = game.mode == PuzzleMode.levels;
  final level = game.puzzle.levelNumber ?? 1;
  return showStoneDialog<void>(
    context,
    title: i18n.t('win.title'),
    dismissible: false,
    builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      if (levels) ...[
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: 0.4 + 0.6 * v, child: child),
          child: StarRow(stars: game.stars, size: 46),
        ),
        if (game.stars == 3) Text(i18n.t('win.perfect'), style: UiText.style(context, size: 16, color: t.color('text.accent'))),
      ] else
        ListenableBuilder(
          listenable: game,
          builder: (context, _) => Column(children: [
            if (game.scoring)
              Text(i18n.t('challenge.counting'), style: UiText.style(context, size: 15, color: t.color('text.muted')))
            else ...[
              Text(i18n.t('challenge.points', {'n': game.puzzlePoints ?? 0}), style: UiText.numbers(context, size: 26, color: t.color('text.accent'))),
              Text(i18n.t('challenge.accuracy', {'p': ((game.sheet?.quality ?? 0) * 100).round()}), style: UiText.style(context, size: 14)),
              Text(i18n.t('challenge.runTotal', {'n': game.run?.score ?? 0}), style: UiText.numbers(context, size: 16)),
              if (game.newBest) Text(i18n.t('challenge.newBest'), style: UiText.style(context, size: 16, color: t.color('ui.success'))),
            ],
          ]),
        ),
      const SizedBox(height: 12),
      if (reward != null)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (reward.coins > 0) ...[
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: reward.coins),
              duration: s.motion('coinFly'),
              builder: (context, v, _) => Text(i18n.t('win.reward', {'n': v}), style: UiText.numbers(context, size: 24, color: t.color('text.accent'))),
            ),
            const SizedBox(width: 4),
            const GlyphIcon(Glyph.sparkle, size: 18),
            const SizedBox(width: 16),
          ],
          Text(i18n.t('win.xp', {'n': reward.xp}), style: UiText.numbers(context, size: 18, color: t.color('ui.focus'))),
        ]),
      const SizedBox(height: 18),
      if (levels) ...[
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
      ] else
        StoneButton(label: i18n.t('win.challengeNext'), primary: true, glyph: Glyph.arrowRight, onTap: () {
          Navigator.pop(context);
          launchChallenge(context, resume: false, replace: true);
        }),
      const SizedBox(height: 10),
      StoneButton(label: i18n.t('common.home'), glyph: Glyph.home, dense: true, onTap: () {
        Navigator.pop(context);
        openHome(context);
      }),
    ]),
  );
}

Future<void> showLoseDialog(BuildContext context, GameController game) {
  final s = Services.of(context, listen: false);
  final i18n = s.i18n;
  final challenge = game.mode == PuzzleMode.challenge;
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
          if (challenge) Text(i18n.t('challenge.runTotal', {'n': game.run?.score ?? 0}), style: UiText.numbers(context, size: 16)),
          if (challenge) Text(i18n.t('challenge.best', {'n': s.player.bestScore}), style: UiText.numbers(context, size: 14)),
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
          if (!challenge)
            StoneButton(label: i18n.t('lose.retry'), glyph: Glyph.restart, onTap: () {
              Navigator.pop(context);
              game.abandon();
              Navigator.pushReplacement(context, portalRoute(gameScreenFor(game.puzzle)));
            }),
          if (challenge)
            StoneButton(label: i18n.t('lose.endRun'), glyph: Glyph.close, onTap: () {
              Navigator.pop(context);
              game.abandon();
              openHome(context);
            }),
          const SizedBox(height: 8),
          StoneButton(label: i18n.t('common.home'), glyph: Glyph.home, dense: true, onTap: () {
            Navigator.pop(context);
            if (!challenge) game.abandon();
            openHome(context);
          }),
        ]);
      },
    ),
  );
}
