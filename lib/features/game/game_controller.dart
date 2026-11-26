import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/boosters/booster_system.dart';
import '../../core/challenge/challenge_system.dart';
import '../../core/economy/wallet.dart';
import '../../core/engine/game_engine.dart';
import '../../core/hint/hint_system.dart';
import '../../core/levels/level_progress.dart';
import '../../core/model/puzzle_definition.dart';
import '../../core/model/tile_spec.dart';
import '../../core/rules/match_resolver.dart';
import '../../core/rules/rule_engine.dart';
import '../../core/solver/solver_context.dart';
import '../../services/app_services.dart';
import '../../services/audio_service.dart';
import '../../services/monetization.dart';
import '../../services/player_service.dart';

/// A tile waiting in a reception slot, as the player sees it.
class TrayEntry {
  TrayEntry(this.cell);

  final int cell;
  bool matching = false;
  bool vanishing = false;
}

enum Payment { coins, ad }

enum BoosterResult { done, insufficient, adClosed, adFailed, unavailable, noHint, unsure }

/// Drives one attempt: the logic commits first (and is saved), then the
/// visuals replay it — fly, land, glow, vanish, close ranks, chain. An
/// interrupted animation can never change what happened.
class GameController extends ChangeNotifier {
  GameController({required this.services, required PuzzleDefinition puzzle, GameSnapshot? resume, this.run}) {
    final rules = RuleEngine.forPuzzle(
      services.rules.byVersion(puzzle.rulesetVersion),
      mode: puzzle.mode.key,
      level: puzzle.levelNumber ?? puzzle.challengeTier,
    );
    engine = resume != null ? GameEngine.resume(resume, rules: rules) : GameEngine(puzzle: puzzle, rules: rules, baseCapacity: services.baseCapacity);
    _ctx = SolverContext(engine.puzzle.layout, rules);
    tray = [for (final c in engine.trayItems) TrayEntry(c)];
    _attempt = '${puzzle.id}@${DateTime.now().microsecondsSinceEpoch}';
    if (engine.status == GameStatus.lost) {
      ended = GameStatus.lost;
      scheduleMicrotask(_analyseRescue);
    }
    _persist();
  }

  final AppServices services;

  /// The current challenge run (challenge mode only).
  final ChallengeRun? run;
  late final GameEngine engine;
  late final SolverContext _ctx;
  late final String _attempt;
  late List<TrayEntry> tray;

  /// Cell → animation tick of its latest unlock flash.
  final Map<int, int> unlockTick = {};
  int _tick = 0;
  int? hintCell;
  bool swapMode = false;
  int? swapFirst;
  bool thinking = false;
  bool _busy = false;

  /// Set once the animations of a winning or losing move are over.
  GameStatus? ended;
  List<RescueOption>? rescues;
  bool rescueChecking = false;
  WinReward? reward;
  int stars = 0;
  bool _disposed = false;

  /// Reports a localisation key to show as a short message.
  void Function(String key, [Map<String, Object?> args])? onMessage;

  PuzzleDefinition get puzzle => engine.puzzle;
  PuzzleMode get mode => puzzle.mode;
  BoosterRules get boosterRules => services.boosters;
  bool get busy => _busy;
  int get capacity => engine.capacity;
  int get adHintsLeft => (boosterRules.hintAdLimit - engine.boosters.adHints).clamp(0, boosterRules.hintAdLimit);

  TileSpec spec(int cell) => engine.specOf(cell);

  bool onBoard(int cell) => engine.board.hasTile(cell);

  int? slotOf(int cell) {
    for (var i = 0; i < tray.length; i++) {
      if (tray[i].cell == cell) return i;
    }
    return null;
  }

  TrayEntry? entryOf(int cell) {
    final i = slotOf(cell);
    return i == null ? null : tray[i];
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _wait(String motion) => Future<void>.delayed(services.motion(motion));

  void _persist() {
    final key = mode.key;
    if (engine.status == GameStatus.won) {
      services.save.clearAttempt(key);
    } else {
      services.save.saveAttempt(key, engine.snapshot());
    }
  }

  Future<void> tapTile(int cell) async {
    if (_busy || ended != null || swapMode) return;
    if (!engine.isOpen(cell)) {
      if (engine.board.hasTile(cell)) {
        onMessage?.call('game.lockedTile');
        services.audio.play(Sfx.error, volume: 0.5);
        services.haptics.light();
      }
      return;
    }
    final value = engine.specOf(cell).value;
    final result = engine.extract(cell);
    if (!result.accepted) return;
    _busy = true;
    hintCell = null;
    services.audio.pick(value);
    services.haptics.light();
    for (final u in result.unlocked) {
      unlockTick[u] = ++_tick;
    }
    tray.add(TrayEntry(cell));
    _persist();
    _notify();
    await _wait('tileFly');
    services.audio.play(Sfx.land, volume: 0.45);
    if (result.unlocked.isNotEmpty) services.audio.play(Sfx.unlock, volume: 0.4);
    await _playMatches(result.matches);
    _busy = false;
    if (result.status == GameStatus.playing && engine.tray.length == engine.capacity - 1 && engine.capacity > 2) {
      onMessage?.call('game.lastSlot');
    }
    _end(result.status);
    _notify();
  }

  Future<void> _playMatches(List<MatchStep> steps) async {
    for (var i = 0; i < steps.length; i++) {
      final cells = steps[i].cells.toSet();
      final entries = [for (final e in tray) if (cells.contains(e.cell)) e];
      for (final e in entries) {
        e.matching = true;
      }
      services.audio.play(i == 0 ? Sfx.match : Sfx.chain);
      services.haptics.medium();
      _notify();
      await _wait('matchGlow');
      for (final e in entries) {
        e.vanishing = true;
      }
      _notify();
      await _wait('matchVanish');
      tray.removeWhere((e) => cells.contains(e.cell));
      _notify();
      await _wait('compact');
    }
  }

  void _end(GameStatus status) {
    if (status == GameStatus.won) {
      ended = GameStatus.won;
      _onWin();
    } else if (status == GameStatus.lost) {
      ended = GameStatus.lost;
      services.audio.play(Sfx.lose, volume: 0.6);
      services.haptics.heavy();
      _analyseRescue();
    }
  }

  void _onWin() {
    services.save.clearAttempt(mode.key);
    services.audio.play(Sfx.win);
    if (mode == PuzzleMode.levels) {
      stars = starsFor(
        usedBoosters: engine.boosters.anyUsed,
        peakRest: engine.peakRest,
        minRest: puzzle.profile?.minRestDepth ?? engine.peakRest,
      );
      reward = services.player.recordLevelWin(level: puzzle.levelNumber ?? 1, stars: stars, totalLevels: services.levels.total);
    } else {
      final r = run;
      reward = services.player.recordChallengeWin(tier: puzzle.challengeTier ?? 1, seed: puzzle.seed ?? 0);
      if (r != null) {
        r.advance(ChallengeDirector.freshSeed(DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF, r.solved + 1), puzzle.layout.fingerprint());
        services.save.saveChallengeRun(r);
      }
    }
  }

  Future<void> _analyseRescue() async {
    rescueChecking = true;
    rescues = null;
    _notify();
    final job = RescueSearch(
      _ctx,
      removed: engine.board.removedCells,
      tray: engine.trayItems,
      capacity: engine.capacity,
      canAddSlot: engine.canAddSlot,
      canSwap: engine.canSwap,
      extraSlots: boosterRules.extraSlots,
      budget: services.rescueBudget,
    );
    rescues = await services.compute.run(job, units: 300);
    rescueChecking = false;
    _notify();
  }

  /// Ends a lost challenge run (or abandons a lost level attempt).
  void abandon() {
    services.save.clearAttempt(mode.key);
    if (mode == PuzzleMode.challenge) services.save.clearChallengeRun();
  }

  BoosterResult _mapAd(AdOutcome o) => switch (o) {
        AdOutcome.rewarded => BoosterResult.done,
        AdOutcome.closedEarly => BoosterResult.adClosed,
        AdOutcome.failed => BoosterResult.adFailed,
      };

  /// The sixth slot (coins or an ad; never charged when already open).
  Future<BoosterResult> addSlot(Payment pay) async {
    if (_busy || !engine.canAddSlot) return BoosterResult.unavailable;
    _busy = true;
    try {
      if (pay == Payment.coins) {
        final r = services.player.spend(boosterRules.extraSlotCoins, 'slot:$_attempt');
        if (r != SpendResult.spent) return r == SpendResult.insufficient ? BoosterResult.insufficient : BoosterResult.unavailable;
      } else {
        if (!boosterRules.extraSlotByAd) return BoosterResult.unavailable;
        final o = await services.ads.show('extra_slot');
        if (o != AdOutcome.rewarded) return _mapAd(o);
      }
      engine.addSlot();
      services.audio.play(Sfx.slotOpen);
      _persist();
      if (ended == GameStatus.lost && engine.status == GameStatus.playing) {
        ended = null;
        rescues = null;
      }
      return BoosterResult.done;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// The smart hint: computed first, paid only when a real hint exists.
  Future<BoosterResult> useHint(Payment pay) async {
    if (_busy || ended != null) return BoosterResult.unavailable;
    if (pay == Payment.ad && adHintsLeft <= 0) return BoosterResult.unavailable;
    if (pay == Payment.coins && !services.player.canAfford(boosterRules.hintCoins)) return BoosterResult.insufficient;
    _busy = true;
    thinking = true;
    _notify();
    try {
      final result = await services.compute.run(
        HintSearch(_ctx, removed: engine.board.removedCells, tray: engine.trayItems, capacity: engine.capacity, budget: services.hintBudget),
        units: 400,
      );
      thinking = false;
      _notify();
      if (result.status == HintStatus.noPath) {
        _busy = false;
        await _analyseRescue();
        return BoosterResult.noHint;
      }
      if (result.status == HintStatus.undetermined || result.cell == null) return BoosterResult.unsure;
      if (pay == Payment.coins) {
        final r = services.player.spend(boosterRules.hintCoins, 'hint:$_attempt:${engine.boosters.hints}');
        if (r != SpendResult.spent) return BoosterResult.insufficient;
        engine.recordHint(viaAd: false);
      } else {
        final o = await services.ads.show('hint');
        if (o != AdOutcome.rewarded) return _mapAd(o);
        engine.recordHint(viaAd: true);
      }
      hintCell = result.cell;
      services.audio.play(Sfx.hint);
      _persist();
      return BoosterResult.done;
    } finally {
      thinking = false;
      _busy = false;
      _notify();
    }
  }

  /// Enters swap mode (charged only when the swap really happens).
  BoosterResult startSwap() {
    if (_busy || engine.boosters.swapUsed) return BoosterResult.unavailable;
    if (engine.tray.length < 2) return BoosterResult.unavailable;
    if (!services.player.canAfford(boosterRules.swapCoins)) return BoosterResult.insufficient;
    swapMode = true;
    swapFirst = null;
    _notify();
    return BoosterResult.done;
  }

  void cancelSwap() {
    swapMode = false;
    swapFirst = null;
    _notify();
  }

  Future<void> tapSlot(int slot) async {
    if (!swapMode || _busy || slot >= tray.length) return;
    services.haptics.selection();
    final first = swapFirst;
    if (first == null || first == slot) {
      swapFirst = first == slot ? null : slot;
      _notify();
      return;
    }
    if (services.player.spend(boosterRules.swapCoins, 'swap:$_attempt') != SpendResult.spent) {
      cancelSwap();
      onMessage?.call('game.noCoins');
      return;
    }
    _busy = true;
    swapMode = false;
    swapFirst = null;
    final result = engine.swap(first, slot);
    final a = tray[first];
    tray[first] = tray[slot];
    tray[slot] = a;
    services.audio.play(Sfx.swap);
    _notify();
    await _wait('swap');
    await _playMatches(result.matches);
    _persist();
    _busy = false;
    if (ended == GameStatus.lost) {
      ended = null;
      rescues = null;
    }
    _end(result.status);
    _notify();
  }
}
