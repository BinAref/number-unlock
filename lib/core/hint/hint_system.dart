import 'dart:math' as math;

import '../jobs/compute_job.dart';
import '../solver/solver_context.dart';
import '../solver/solver_search.dart';
import '../solver/state_set.dart';

enum HintStatus {
  /// A pick that leads to a real win was found.
  found,

  /// Proven: no winning path exists from here with the current slots.
  noPath,

  /// The search ran out of budget before deciding (no hint, no charge).
  undetermined,
}

class HintResult {
  const HintResult(this.status, {this.cell, this.path = const <int>[]});

  final HintStatus status;

  /// The suggested pick (when found).
  final int? cell;

  /// The full winning continuation behind the suggestion.
  final List<int> path;
}

/// The smart hint: searches for an actual winning continuation from the
/// current state and suggests its first pick.
///
/// It prefers the safest route — the one that keeps the fewest tiles waiting
/// in the tray — by trying tighter tray limits first. A pick that matches
/// nothing right now may be suggested when it is needed to unlock what comes
/// next. When no route exists it says so instead of guessing.
class HintSearch implements ComputeJob<HintResult> {
  HintSearch(
    this.ctx, {
    required List<int> removed,
    required List<int> tray,
    required this.capacity,
    this.budget = 300000,
  })  : _removed = List<int>.unmodifiable(removed),
        _tray = List<int>.unmodifiable(tray) {
    if (_tray.length >= capacity || _removed.length >= ctx.layout.tileCount) {
      _result = const HintResult(HintStatus.noPath);
      return;
    }
    _limit = math.max(1, _tray.length);
    _startLevel();
  }

  final SolverContext ctx;
  final int capacity;
  final int budget;
  final List<int> _removed;
  final List<int> _tray;
  late int _limit;
  SolverSearch? _search;
  int _spent = 0;
  bool _undecided = false;
  HintResult? _result;

  @override
  HintResult get result => _result ?? const HintResult(HintStatus.undetermined);

  void _startLevel() {
    final last = _limit >= capacity - 1;
    final left = budget - _spent;
    final share = last ? left : math.min(left, budget ~/ 4);
    _search = SolverSearch(
      ctx,
      removed: _removed,
      tray: _tray,
      capacity: capacity,
      restLimit: _limit,
      failures: StateSet(ctx.keyLengthFor(capacity)),
      nodeBudget: math.max(1, share),
    );
  }

  @override
  bool step(int units) {
    if (_result != null) return true;
    final search = _search!;
    final status = search.advance(units);
    if (status == SearchStatus.running) return false;
    _spent += search.expansions;
    if (status == SearchStatus.solved) {
      final path = search.solution!;
      _result = path.isEmpty
          ? const HintResult(HintStatus.noPath)
          : HintResult(HintStatus.found, cell: path.first, path: path);
      return true;
    }
    if (status == SearchStatus.budgetExceeded) _undecided = true;
    if (_limit >= capacity - 1 || _spent >= budget) {
      _result = HintResult(_undecided ? HintStatus.undetermined : HintStatus.noPath);
      return true;
    }
    _limit++;
    _startLevel();
    return false;
  }
}
