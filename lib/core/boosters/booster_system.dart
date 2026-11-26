import 'dart:math' as math;

import '../engine/game_engine.dart';
import '../jobs/compute_job.dart';
import '../solver/solver_context.dart';
import '../solver/solver_search.dart';
import '../util/json_read.dart';

enum BoosterType { extraSlot, hint, swap }

/// Costs and allowances of the three boosters (from `economy.json`).
class BoosterRules {
  const BoosterRules({
    this.extraSlotCoins = 1,
    this.extraSlotByAd = true,
    this.extraSlots = 1,
    this.hintCoins = 1,
    this.hintByAd = true,
    this.freeHints = const {'levels': 3, 'endless': 3},
    this.swapCoins = 1,
    this.swapByAd = true,
    this.swapsPerBoard = 1,
    this.freeSwaps = const {'levels': 0, 'endless': 1},
    this.adCooldown = const Duration(seconds: 10),
  });

  factory BoosterRules.fromJson(Map<String, Object?> json) {
    final slot = readMap(json['extraSlot']);
    final hint = readMap(json['hint']);
    final swap = readMap(json['swap']);
    Map<String, int> perMode(Object? v, Map<String, int> fallback) {
      final m = readMap(v);
      return m.isEmpty ? fallback : {for (final e in m.entries) e.key: readInt(e.value)};
    }

    return BoosterRules(
      extraSlotCoins: readInt(slot['coins'], 1),
      extraSlotByAd: readBool(slot['ad'], true),
      extraSlots: readInt(slot['slots'], 1),
      hintCoins: readInt(hint['coins'], 1),
      hintByAd: readBool(hint['ad'], true),
      freeHints: perMode(hint['free'], const {'levels': 3, 'endless': 3}),
      swapCoins: readInt(swap['coins'], 1),
      swapByAd: readBool(swap['ad'], true),
      swapsPerBoard: readInt(swap['perBoard'], 1),
      freeSwaps: perMode(swap['free'], const {'levels': 0, 'endless': 1}),
      adCooldown: Duration(seconds: readInt(json['adCooldownSeconds'], 10)),
    );
  }

  final int extraSlotCoins;
  final bool extraSlotByAd;

  /// Slots added by the booster (the sixth slot).
  final int extraSlots;
  final int hintCoins;
  final bool hintByAd;

  /// Free hints: per level attempt in `levels`, per whole run in `endless`.
  final Map<String, int> freeHints;
  final int swapCoins;
  final bool swapByAd;

  /// Most swaps on one board (the engine allows one).
  final int swapsPerBoard;

  /// Free swaps: per level attempt in `levels`, per whole run in `endless`.
  final Map<String, int> freeSwaps;

  /// The wait between two ads, wherever they are opened.
  final Duration adCooldown;

  int freeHintsIn(String mode) => freeHints[mode] ?? 0;

  int freeSwapsIn(String mode) => freeSwaps[mode] ?? 0;
}

/// Who pays for what in each mode:
///
/// * Levels — 3 free hints at the start of every level (renewed with every
///   attempt); the swap is locked until a coin or an ad opens one; the sixth
///   slot costs a coin or an ad and lasts for the attempt.
/// * Endless — 3 free hints for the whole run, never renewed by progress;
///   one free swap for the whole run, then a coin or an ad; the sixth slot
///   costs a coin or an ad and lasts for the current board only.
/// * Everywhere — one swap per board; every hint beyond the free ones costs
///   a coin or an ad.
class BoosterPolicy {
  const BoosterPolicy(this.rules);

  final BoosterRules rules;

  /// Free hints still available on this board. In endless the allowance is
  /// shared by the whole run ([runFreeHintsUsed]).
  int freeHintsLeft({required String mode, required BoosterUsage board, int runFreeHintsUsed = 0}) {
    final used = mode == 'endless' ? runFreeHintsUsed : board.freeHints;
    return math.max(0, rules.freeHintsIn(mode) - used);
  }

  /// Whether this board may still have a swap at all.
  bool swapLeft(BoosterUsage board) => !board.swapUsed;

  /// Whether the next swap on this board costs nothing more: it was paid
  /// for already, or the mode's free swap covers it.
  bool swapReady({required String mode, required BoosterUsage board, bool runFreeSwapUsed = false}) {
    if (board.swapUnlocked) return true;
    if (rules.freeSwapsIn(mode) <= 0) return false;
    return mode == 'endless' ? !runFreeSwapUsed : true;
  }
}

enum RescueKind { extraSlot, swap }

/// A booster proven to turn the current position into a winnable one.
class RescueOption {
  const RescueOption(this.kind, {this.swapA, this.swapB});

  final RescueKind kind;

  /// Tray slots a rescuing swap would exchange.
  final int? swapA;
  final int? swapB;
}

/// Checks which available boosters can genuinely save the current position.
///
/// Every option it returns comes with a found winning continuation; anything
/// it cannot prove is simply not offered as a rescue.
class RescueSearch implements ComputeJob<List<RescueOption>> {
  RescueSearch(
    this.ctx, {
    required List<int> removed,
    required List<int> tray,
    required this.capacity,
    required bool canAddSlot,
    required bool canSwap,
    this.extraSlots = 1,
    this.budget = 200000,
  })  : _removed = List<int>.unmodifiable(removed),
        _tray = List<int>.unmodifiable(tray) {
    if (canAddSlot) _queue.add((RescueKind.extraSlot, -1, -1));
    if (canSwap) {
      for (var a = 0; a < _tray.length; a++) {
        for (var b = a + 1; b < _tray.length; b++) {
          _queue.add((RescueKind.swap, a, b));
        }
      }
    }
  }

  final SolverContext ctx;
  final int capacity;
  final int extraSlots;
  final int budget;
  final List<int> _removed;
  final List<int> _tray;
  final List<(RescueKind, int, int)> _queue = [];
  final List<RescueOption> _found = [];
  bool _swapFound = false;
  int _index = 0;
  int _spent = 0;
  SolverSearch? _search;
  (RescueKind, int, int)? _current;
  bool _done = false;

  @override
  List<RescueOption> get result => List<RescueOption>.unmodifiable(_found);

  @override
  bool step(int units) {
    if (_done) return true;
    var left = units;
    while (left > 0) {
      if (_search == null && !_startNext()) {
        _done = true;
        return true;
      }
      final search = _search!;
      final before = search.expansions;
      final status = search.advance(left);
      final used = search.expansions - before;
      left -= used < 1 ? 1 : (used > left ? left : used);
      if (status == SearchStatus.running) continue;
      _spent += search.expansions;
      if (status == SearchStatus.solved) _record(_current!);
      _search = null;
      if (_spent >= budget) {
        _done = true;
        return true;
      }
    }
    return false;
  }

  void _record((RescueKind, int, int) option) {
    final (kind, a, b) = option;
    if (kind == RescueKind.swap) {
      if (_swapFound) return;
      _swapFound = true;
      _found.add(RescueOption(kind, swapA: a, swapB: b));
    } else {
      _found.add(const RescueOption(RescueKind.extraSlot));
    }
  }

  bool _startNext() {
    while (_index < _queue.length) {
      final option = _queue[_index++];
      final (kind, a, b) = option;
      if (kind == RescueKind.swap && _swapFound) continue;
      final tray = List<int>.of(_tray);
      var cap = capacity;
      if (kind == RescueKind.extraSlot) {
        cap += extraSlots;
      } else {
        final t = tray[a];
        tray[a] = tray[b];
        tray[b] = t;
        ctx.resolver.resolveQuietly(tray);
        if (_removed.length >= ctx.layout.tileCount) {
          if (tray.isEmpty) _record(option);
          continue;
        }
      }
      _current = option;
      _search = SolverSearch(
        ctx,
        removed: _removed,
        tray: tray,
        capacity: cap,
        nodeBudget: budget - _spent < 1 ? 1 : budget - _spent,
      );
      return true;
    }
    return false;
  }
}
