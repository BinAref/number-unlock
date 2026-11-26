import '../jobs/compute_job.dart';
import '../solver/solver_context.dart';
import '../solver/solver_search.dart';
import '../util/json_read.dart';

enum BoosterType { extraSlot, hint, swap }

/// Costs and limits of the three boosters (from `economy.json`).
class BoosterRules {
  const BoosterRules({
    this.extraSlotCoins = 1,
    this.extraSlotByAd = true,
    this.extraSlots = 1,
    this.hintCoins = 1,
    this.hintAdLimit = 3,
    this.swapCoins = 1,
    this.swapsPerAttempt = 1,
    this.swapByAd = false,
  });

  factory BoosterRules.fromJson(Map<String, Object?> json) {
    final slot = readMap(json['extraSlot']);
    final hint = readMap(json['hint']);
    final swap = readMap(json['swap']);
    return BoosterRules(
      extraSlotCoins: readInt(slot['coins'], 1),
      extraSlotByAd: readBool(slot['ad'], true),
      extraSlots: readInt(slot['slots'], 1),
      hintCoins: readInt(hint['coins'], 1),
      hintAdLimit: readInt(hint['adLimit'], 3),
      swapCoins: readInt(swap['coins'], 1),
      swapsPerAttempt: readInt(swap['perAttempt'], 1),
      swapByAd: readBool(swap['ad']),
    );
  }

  final int extraSlotCoins;
  final bool extraSlotByAd;

  /// Slots added by the booster (the sixth slot).
  final int extraSlots;
  final int hintCoins;

  /// Hints that can be earned with ads in one attempt (coins: unlimited).
  final int hintAdLimit;
  final int swapCoins;
  final int swapsPerAttempt;
  final bool swapByAd;
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
