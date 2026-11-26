import '../jobs/compute_job.dart';
import '../solver/solver_context.dart';
import '../solver/solver_search.dart';
import '../solver/state_set.dart';

/// How good one pick was, judged against the best possible play.
enum MoveGrade {
  /// As good as following the hint: the best outcome is still reachable.
  perfect,

  /// Still winnable, but the tray will need more room than necessary.
  good,

  /// The pick a hint suggested (help costs half).
  hinted,

  /// No winning path is left after this pick.
  fatal,
}

/// The score of one challenge puzzle: perfect picks earn full points, every
/// departure from the best path costs some, boosters trim the total, and a
/// lost puzzle earns nothing.
class ScoreSheet {
  final List<MoveGrade> grades = [];
  bool usedSlot = false;
  bool usedSwap = false;

  static int basePoints(int tier) => 100 + 20 * (tier - 1);

  double get quality {
    if (grades.isEmpty) return 0;
    var sum = 0.0;
    for (final g in grades) {
      sum += switch (g) {
        MoveGrade.perfect => 1.0,
        MoveGrade.good => 0.5,
        MoveGrade.hinted => 0.5,
        MoveGrade.fatal => 0.0,
      };
    }
    var q = sum / grades.length;
    if (usedSlot) q *= 0.8;
    if (usedSwap) q *= 0.85;
    return q;
  }

  int pointsFor(int tier) => (basePoints(tier) * quality).round();
}

/// Grades picks with the real solver, reusing what it learned across the
/// picks of one puzzle.
class ChallengeScorer {
  ChallengeScorer(this.ctx);

  final SolverContext ctx;
  final Map<int, StateSet> _failures = {};

  StateSet _set(int capacity, int limit) => _failures.putIfAbsent(capacity * 16 + limit, () => StateSet(ctx.keyLengthFor(capacity)));

  ComputeJob<MoveGrade> grade({required List<int> removed, required List<int> tray, required int move, required int capacity, int budget = 60000}) =>
      _GradeJob(this, removed, tray, move, capacity, budget);
}

class _GradeJob implements ComputeJob<MoveGrade> {
  _GradeJob(this.s, this.removed, this.tray, this.move, this.capacity, this.budget) {
    _afterRemoved = [...removed, move];
    _afterTray = [...tray, move];
    s.ctx.resolver.resolveQuietly(_afterTray);
    _limit = tray.isEmpty ? 1 : tray.length;
    _search = _start(removed, tray, _limit);
  }

  final ChallengeScorer s;
  final List<int> removed;
  final List<int> tray;
  final int move;
  final int capacity;
  final int budget;
  late final List<int> _afterRemoved;
  late final List<int> _afterTray;
  late int _limit;
  late SolverSearch _search;
  int _phase = 0;
  bool _unknown = false;
  MoveGrade? _result;

  @override
  MoveGrade get result => _result ?? MoveGrade.good;

  SolverSearch _start(List<int> r, List<int> t, int limit) =>
      SolverSearch(s.ctx, removed: r, tray: t, capacity: capacity, restLimit: limit, failures: s._set(capacity, limit), nodeBudget: budget);

  @override
  bool step(int units) {
    if (_result != null) return true;
    final status = _search.advance(units);
    if (status == SearchStatus.running) return false;
    switch (_phase) {
      case 0:
        // The best achievable tray limit before the pick.
        if (status == SearchStatus.solved) {
          if (_afterTray.length >= capacity) return _done(MoveGrade.fatal);
          if (_afterRemoved.length >= s.ctx.layout.tileCount) return _done(_afterTray.isEmpty ? MoveGrade.perfect : MoveGrade.fatal);
          _phase = 1;
          _search = _start(_afterRemoved, _afterTray, _limit);
        } else {
          if (status == SearchStatus.budgetExceeded) _unknown = true;
          if (_limit >= capacity - 1) return _done(_unknown ? MoveGrade.good : MoveGrade.fatal);
          _limit++;
          _search = _start(removed, tray, _limit);
        }
      case 1:
        if (status == SearchStatus.solved) return _done(MoveGrade.perfect);
        if (status == SearchStatus.budgetExceeded) return _done(MoveGrade.good);
        _phase = 2;
        _search = _start(_afterRemoved, _afterTray, capacity - 1);
      default:
        return _done(status == SearchStatus.exhausted ? MoveGrade.fatal : MoveGrade.good);
    }
    return false;
  }

  bool _done(MoveGrade g) {
    _result = g;
    return true;
  }
}
