import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/boosters/booster_system.dart';
import '../../core/economy/wallet.dart';
import '../../core/endless/endless_director.dart';
import '../../core/endless/endless_run.dart';
import '../../core/endless/endless_stats.dart';
import '../../core/engine/game_engine.dart';
import '../../core/hint/hint_system.dart';
import '../../core/model/puzzle_definition.dart';
import '../../core/scoring/move_scorer.dart';
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

/// How a help is paid for: from the free allowance, with coins, or an ad.
enum Payment { free, coins, ad }

enum BoosterResult { done, insufficient, adClosed, adFailed, adWait, unavailable, noHint, unsure }

/// Drives one attempt: the logic commits first (and is saved), then the
/// visuals replay it — fly, land, glow, vanish, close ranks, chain. An
/// interrupted animation can never change what happened.
class GameController extends ChangeNotifier {
  GameController({required this.services, required PuzzleDefinition puzzle, GameSnapshot? resume}) {
    final rules = RuleEngine.forPuzzle(
      services.rules.byVersion(puzzle.rulesetVersion),
      mode: puzzle.mode.key,
      level: puzzle.levelNumber ?? puzzle.boardNumber,
    );
    engine = resume != null ? GameEngine.resume(resume, rules: rules) : GameEngine(puzzle: puzzle, rules: rules, baseCapacity: services.baseCapacity);
    _ctx = SolverContext(engine.puzzle.layout, rules);
    tray = [for (final c in engine.trayItems) TrayEntry(c)];
    _attempt = '${puzzle.id}@${DateTime.now().microsecondsSinceEpoch}';
    if (puzzle.mode == PuzzleMode.endless) {
      sheet = ScoreSheet();
      _scorer = MoveScorer(_ctx);
    }
    if (engine.status == GameStatus.lost) {
      ended = GameStatus.lost;
      scheduleMicrotask(_analyseRescue);
    }
    _persist();
  }

  final AppServices services;
  late final GameEngine engine;
  late final SolverContext _ctx;
  late final String _attempt;
  late List<TrayEntry> tray;

  /// Cell → animation tick of its latest unlock flash.
  final Map<int, int> unlockTick = {};
  int _tick = 0;
  int? hintCell;
  bool swapMode = false;
  bool thinking = false;

  /// A booster at work (an ad, a hint being worked out): other boosters
  /// wait for it; taps on the board never do.
  bool _boosterBusy = false;

  /// Visual sequences still playing. Taps never wait for them: the game
  /// logic moves at once and each move's animation runs alongside the rest.
  int _visuals = 0;

  /// Bumps with every move, so a result computed for an older position (a
  /// hint) is never shown on a newer one.
  int _version = 0;
  int? _swapFirstCell;

  /// Set once the animations of a winning or losing move are over.
  GameStatus? ended;
  List<RescueOption>? rescues;
  bool rescueChecking = false;
  WinReward? reward;
  int stars = 0;
  bool _disposed = false;

  /// Endless scoring: every pick graded against the perfect path.
  ScoreSheet? sheet;
  MoveScorer? _scorer;
  Future<void> _grading = Future<void>.value();
  bool scoring = false;

  /// Points the cleared endless board banked, and the coins it paid.
  int? puzzlePoints;
  int boardCoins = 0;

  /// The finished endless run, once the player ends it after a loss.
  RunSummary? runSummary;

  /// Reports a localisation key to show as a short message.
  void Function(String key, [Map<String, Object?> args])? onMessage;

  PuzzleDefinition get puzzle => engine.puzzle;
  PuzzleMode get mode => puzzle.mode;
  BoosterRules get boosterRules => services.boosters;
  bool get busy => _boosterBusy;

  /// Whether any move's animation is still playing.
  bool get animating => _visuals > 0;

  /// The tray slot chosen first for a swap (it follows its tile while the
  /// tray closes ranks).
  int? get swapFirst => _swapFirstCell == null ? null : slotOf(_swapFirstCell!);
  int get capacity => engine.capacity;
  BoosterPolicy get policy => BoosterPolicy(boosterRules);

  /// The endless run, when this board belongs to one.
  EndlessRun? get _run => mode == PuzzleMode.endless ? services.endless.run : null;

  /// Free hints still available on this board (in endless, the run's).
  int get freeHintsLeft => policy.freeHintsLeft(mode: mode.key, board: engine.boosters, runFreeHintsUsed: _run?.hintsUsed ?? 0);

  /// Whether the next swap costs nothing more (paid already, or free).
  bool get swapReady => policy.swapReady(mode: mode.key, board: engine.boosters, runFreeSwapUsed: _run?.freeSwapUsed ?? false);

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

  Future<void> _wait(String motion) {
    final d = services.motion(motion);
    // Several moves in flight: the older animations hurry to keep up.
    return Future<void>.delayed(_visuals > 1 ? d * 0.35 : d);
  }

  /// Runs one move's animation alongside any others. When the last one
  /// ends, a finished game is announced (so the end screen never cuts an
  /// animation short, and never waits on a fixed delay).
  void _play(Future<void> Function() sequence) {
    _visuals++;
    sequence().whenComplete(() {
      _visuals--;
      if (_visuals == 0) _settle();
    });
  }

  void _settle() {
    if (_disposed || ended != null) return;
    final status = engine.status;
    if (status == GameStatus.won || status == GameStatus.lost) {
      _end(status);
      _notify();
    }
  }

  void _persist() {
    final key = mode.key;
    if (engine.status == GameStatus.won) {
      services.save.clearAttempt(key);
    } else {
      services.save.saveAttempt(key, engine.snapshot());
    }
  }

  /// Takes a tile — at once, whatever is still animating. The logic commits
  /// first (and is saved); the flight, the landing and any matches then
  /// play alongside earlier moves.
  void tapTile(int cell) {
    if (ended != null || swapMode) return;
    if (!engine.isOpen(cell)) {
      if (engine.board.hasTile(cell)) {
        onMessage?.call('game.lockedTile');
        services.audio.play(Sfx.error, volume: 0.5);
        services.haptics.light();
      }
      return;
    }
    final value = engine.specOf(cell).value;
    final before = (engine.board.removedCells, engine.trayItems, engine.capacity, hintCell == cell);
    final result = engine.extract(cell);
    if (!result.accepted) return;
    _version++;
    _grade(before.$1, before.$2, before.$3, cell, hinted: before.$4);
    hintCell = null;
    services.audio.pick(value);
    services.haptics.light();
    for (final u in result.unlocked) {
      unlockTick[u] = ++_tick;
    }
    tray.add(TrayEntry(cell));
    _persist();
    if (result.status == GameStatus.playing && engine.tray.length == engine.capacity - 1 && engine.capacity > 2) {
      onMessage?.call('game.lastSlot');
    }
    _notify();
    _play(() async {
      await _wait('tileFly');
      services.audio.play(Sfx.land, volume: 0.45);
      if (result.unlocked.isNotEmpty) services.audio.play(Sfx.unlock, volume: 0.4);
      await _playMatches(result.matches);
    });
  }

  void _grade(List<int> removed, List<int> tray, int capacity, int cell, {required bool hinted}) {
    final sheet = this.sheet;
    final scorer = _scorer;
    if (sheet == null || scorer == null) return;
    if (hinted) {
      sheet.grades.add(MoveGrade.hinted);
      return;
    }
    _grading = _grading.then((_) async {
      sheet.grades.add(await services.compute.run(scorer.grade(removed: removed, tray: tray, move: cell, capacity: capacity), units: 400));
    });
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
      stars = services.economy.stars.starsFor(won: true, helps: engine.boosters.helps);
      reward = services.player.recordLevelWin(level: puzzle.levelNumber ?? 1, stars: stars, totalLevels: services.levels.total);
      services.levels.ensureAhead(services.player.progress.highestUnlocked);
    } else {
      // The board's points wait for the last grades, then join the run total.
      final board = puzzle.boardNumber ?? 1;
      scoring = true;
      _grading.then((_) async {
        final points = sheet?.pointsFor(EndlessDirector.basePoints(board)) ?? 0;
        puzzlePoints = points;
        boardCoins = await services.endless.clearBoard(puzzle, points, services.player);
        scoring = false;
        _notify();
      });
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

  /// Abandons a lost level attempt.
  void abandon() => services.save.clearAttempt(mode.key);

  /// Ends the endless run after a lost board: the total is recorded against
  /// the record and the run is closed.
  Future<RunSummary> finishRun() async {
    final summary = runSummary ?? await services.endless.finishRun(services.player);
    runSummary = summary;
    _notify();
    return summary;
  }

  BoosterResult _mapAd(AdOutcome o) => switch (o) {
        AdOutcome.rewarded => BoosterResult.done,
        AdOutcome.closedEarly => BoosterResult.adClosed,
        AdOutcome.failed => BoosterResult.adFailed,
      };

  /// The sixth slot (coins or an ad; never charged when already open).
  Future<BoosterResult> addSlot(Payment pay) async {
    if (_boosterBusy || !engine.canAddSlot || pay == Payment.free) return BoosterResult.unavailable;
    _boosterBusy = true;
    try {
      if (pay == Payment.coins) {
        final r = services.player.spend(boosterRules.extraSlotCoins, 'slot:$_attempt');
        if (r != SpendResult.spent) return r == SpendResult.insufficient ? BoosterResult.insufficient : BoosterResult.unavailable;
      } else {
        if (!boosterRules.extraSlotByAd) return BoosterResult.unavailable;
        final o = await services.adGate.show('extra_slot');
        if (o == null) return BoosterResult.adWait;
        if (o != AdOutcome.rewarded) return _mapAd(o);
      }
      engine.addSlot();
      sheet?.usedSlot = true;
      services.audio.play(Sfx.slotOpen);
      _persist();
      if (ended == GameStatus.lost && engine.status == GameStatus.playing) {
        ended = null;
        rescues = null;
      }
      return BoosterResult.done;
    } finally {
      _boosterBusy = false;
      _notify();
    }
  }

  /// The smart hint: computed first (in the background — the board stays
  /// playable), paid only when a real hint exists. A hint worked out for a
  /// position the player has since changed is dropped and worked out again.
  Future<BoosterResult> useHint(Payment pay) async {
    if (_boosterBusy || ended != null) return BoosterResult.unavailable;
    if (pay == Payment.free && freeHintsLeft <= 0) return BoosterResult.unavailable;
    if (pay == Payment.ad && !boosterRules.hintByAd) return BoosterResult.unavailable;
    if (pay == Payment.ad && !services.adGate.ready) return BoosterResult.adWait;
    if (pay == Payment.coins && !services.player.canAfford(boosterRules.hintCoins)) return BoosterResult.insufficient;
    _boosterBusy = true;
    thinking = true;
    _notify();
    try {
      HintResult? result;
      for (var tries = 0; tries < 2 && result == null; tries++) {
        final at = _version;
        final r = await services.compute.run(
          HintSearch(_ctx, removed: engine.board.removedCells, tray: engine.trayItems, capacity: engine.capacity, budget: services.hintBudget),
          units: 400,
        );
        if (at == _version) result = r;
      }
      thinking = false;
      _notify();
      if (result == null || ended != null) return BoosterResult.unsure;
      if (result.status == HintStatus.noPath) {
        _boosterBusy = false;
        await _analyseRescue();
        return BoosterResult.noHint;
      }
      if (result.status == HintStatus.undetermined || result.cell == null) return BoosterResult.unsure;
      switch (pay) {
        case Payment.free:
          engine.recordHint(viaAd: false, free: true);
          final run = _run;
          if (run != null) {
            run.hintsUsed++;
            services.endless.saveRun();
          }
        case Payment.coins:
          final r = services.player.spend(boosterRules.hintCoins, 'hint:$_attempt:${engine.boosters.hints}');
          if (r != SpendResult.spent) return BoosterResult.insufficient;
          engine.recordHint(viaAd: false);
        case Payment.ad:
          final o = await services.adGate.show('hint');
          if (o == null) return BoosterResult.adWait;
          if (o != AdOutcome.rewarded) return _mapAd(o);
          engine.recordHint(viaAd: true);
      }
      hintCell = result.cell;
      services.audio.play(Sfx.hint);
      _persist();
      return BoosterResult.done;
    } finally {
      thinking = false;
      _boosterBusy = false;
      _notify();
    }
  }

  /// Pays for this board's swap with a coin or an ad. Once paid, the swap
  /// can be made — or cancelled and made later on the same board — without
  /// paying again.
  Future<BoosterResult> unlockSwap(Payment pay) async {
    if (_boosterBusy || !policy.swapLeft(engine.boosters)) return BoosterResult.unavailable;
    if (swapReady) return BoosterResult.done;
    if (pay == Payment.coins) {
      final r = services.player.spend(boosterRules.swapCoins, 'swap:$_attempt');
      if (r != SpendResult.spent) return r == SpendResult.insufficient ? BoosterResult.insufficient : BoosterResult.unavailable;
    } else if (pay == Payment.ad && boosterRules.swapByAd) {
      _boosterBusy = true;
      try {
        final o = await services.adGate.show('swap');
        if (o == null) return BoosterResult.adWait;
        if (o != AdOutcome.rewarded) return _mapAd(o);
      } finally {
        _boosterBusy = false;
      }
    } else {
      return BoosterResult.unavailable;
    }
    engine.boosters.swapUnlocked = true;
    _persist();
    _notify();
    return BoosterResult.done;
  }

  /// Enters swap mode once the swap is free or paid for (one per board).
  BoosterResult startSwap() {
    if (_boosterBusy || !policy.swapLeft(engine.boosters)) return BoosterResult.unavailable;
    if (engine.tray.length < 2) return BoosterResult.unavailable;
    if (!swapReady) return BoosterResult.insufficient;
    swapMode = true;
    _swapFirstCell = null;
    _notify();
    return BoosterResult.done;
  }

  void cancelSwap() {
    swapMode = false;
    _swapFirstCell = null;
    _notify();
  }

  /// Chooses the tiles of a swap. Choices follow tiles, not positions: the
  /// tray may still be closing ranks from an earlier match while the player
  /// picks, and a tile already vanishing cannot be chosen.
  void tapSlot(int slot) {
    if (!swapMode || slot >= tray.length) return;
    final entry = tray[slot];
    if (entry.matching || entry.vanishing) return;
    services.haptics.selection();
    final firstCell = _swapFirstCell;
    if (firstCell == null || firstCell == entry.cell) {
      _swapFirstCell = firstCell == entry.cell ? null : entry.cell;
      _notify();
      return;
    }
    final a = engine.trayItems.indexOf(firstCell);
    final b = engine.trayItems.indexOf(entry.cell);
    if (!swapReady || a < 0 || b < 0) {
      cancelSwap();
      return;
    }
    final freeSwap = !engine.boosters.swapUnlocked;
    swapMode = false;
    _swapFirstCell = null;
    final result = engine.swap(a, b);
    _version++;
    final run = _run;
    if (freeSwap && run != null) {
      // The run's one free swap is spent.
      run.freeSwapUsed = true;
      services.endless.saveRun();
    }
    sheet?.usedSwap = true;
    final va = slotOf(firstCell)!;
    final vb = slotOf(entry.cell)!;
    final moved = tray[va];
    tray[va] = tray[vb];
    tray[vb] = moved;
    services.audio.play(Sfx.swap);
    _persist();
    if (ended == GameStatus.lost && engine.status == GameStatus.playing) {
      ended = null;
      rescues = null;
    }
    _notify();
    _play(() async {
      await _wait('swap');
      await _playMatches(result.matches);
    });
  }
}
