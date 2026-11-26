import 'dart:math' as math;
import 'dart:typed_data';

import '../engine/game_engine.dart';
import '../model/puzzle_definition.dart';
import 'solver_context.dart';
import 'solver_search.dart';
import 'state_set.dart';

class SolveResult {
  const SolveResult(this.status, this.path, this.expansions);

  final SearchStatus status;
  final List<int>? path;
  final int expansions;

  bool get solved => status == SearchStatus.solved;

  /// Proven impossible (the whole search space was explored).
  bool get impossible => status == SearchStatus.exhausted;
}

/// The smallest number of reception slots that solves a puzzle.
class MinCapacityResult {
  const MinCapacityResult({required this.capacity, required this.proven, required this.path, required this.expansions});

  /// Fewest slots that worked, or null when nothing was found.
  final int? capacity;

  /// True when every smaller slot count was proven impossible.
  final bool proven;
  final List<int>? path;
  final int expansions;
}

/// Facts about one sequence of picks, measured by the real game engine.
class ReplayResult {
  const ReplayResult({
    required this.valid,
    required this.won,
    required this.peakRest,
    required this.landings,
    required this.matchGaps,
    required this.longestPushRun,
    this.avgRest = 0,
  });

  /// Average tiles waiting in the tray after each pick.
  final double avgRest;

  /// Every pick was legal.
  final bool valid;
  final bool won;

  /// Most tiles that waited in the tray at once.
  final int peakRest;

  /// landings[k] = picks that landed in slot k + 1.
  final List<int> landings;

  /// Picks between a tile entering the tray and leaving it in a match.
  final List<int> matchGaps;

  /// Longest run of consecutive picks that produced no match.
  final int longestPushRun;
}

/// Convenience front-end over [SolverSearch].
class PuzzleSolver {
  PuzzleSolver(this.ctx);

  final SolverContext ctx;

  SolveResult solve({
    Iterable<int> removed = const <int>[],
    List<int> tray = const <int>[],
    required int capacity,
    int? restLimit,
    int nodeBudget = 1 << 30,
    StateSet? failures,
  }) {
    final search = SolverSearch(
      ctx,
      removed: removed,
      tray: tray,
      capacity: capacity,
      restLimit: restLimit,
      failures: failures,
      nodeBudget: nodeBudget,
    );
    while (search.advance(1 << 15) == SearchStatus.running) {}
    return SolveResult(search.status, search.solution, search.expansions);
  }

  /// The fewest slots that solve the puzzle.
  ///
  /// Solvability only grows with more slots, so the search walks downward
  /// from a known solution and a single failed proof (at one slot fewer)
  /// settles the answer. [budgets] caps the work per slot count.
  MinCapacityResult minCapacity({
    int maxCapacity = 5,
    int minCapacity = 2,
    Map<int, int> budgets = const <int, int>{},
    List<int>? knownPath,
  }) {
    var total = 0;
    List<int>? path;
    int? cap;
    if (knownPath != null) {
      final peak = peakOf(knownPath);
      if (peak != null && peak + 1 <= maxCapacity) {
        path = knownPath;
        cap = math.max(minCapacity, peak + 1);
      }
    }
    if (cap == null) {
      final r = solve(capacity: maxCapacity, nodeBudget: budgets[maxCapacity] ?? (1 << 30));
      total += r.expansions;
      if (!r.solved) return MinCapacityResult(capacity: null, proven: false, path: null, expansions: total);
      path = r.path!;
      cap = math.max(minCapacity, (peakOf(path) ?? maxCapacity - 1) + 1);
    }
    var proven = cap == minCapacity;
    while (cap! > minCapacity) {
      final r = solve(capacity: cap - 1, nodeBudget: budgets[cap - 1] ?? (1 << 30));
      total += r.expansions;
      if (r.solved) {
        path = r.path!;
        final peak = peakOf(path) ?? cap - 2;
        cap = math.max(minCapacity, math.min(cap - 1, peak + 1));
        proven = cap == minCapacity;
        continue;
      }
      proven = r.impossible;
      break;
    }
    return MinCapacityResult(capacity: cap, proven: proven, path: path, expansions: total);
  }

  /// Most tiles waiting at once along [path], or null if it is not a win.
  int? peakOf(List<int> path) {
    final removed = Uint32List(ctx.wordCount);
    final tray = <int>[];
    var peak = 0;
    for (final c in path) {
      if (c < 0 || c >= ctx.layout.cellCount || !ctx.layout.isTile(c)) return null;
      if (SolverContext.isSet(removed, c) || !ctx.topology.isOpenInMask(c, removed)) return null;
      SolverContext.setBit(removed, c);
      tray.add(c);
      ctx.resolver.resolveQuietly(tray);
      if (tray.length > peak) peak = tray.length;
    }
    if (path.length != ctx.layout.tileCount || tray.isNotEmpty) return null;
    return peak;
  }

  /// Plays [path] with the real game engine and measures it.
  ReplayResult replay(List<int> path, {required int capacity, required int rulesetVersion}) {
    final engine = GameEngine(
      puzzle: PuzzleDefinition(id: 'replay', mode: PuzzleMode.levels, layout: ctx.layout, rulesetVersion: rulesetVersion),
      rules: ctx.rules,
      baseCapacity: capacity,
    );
    final landings = List<int>.filled(capacity, 0);
    final entered = <int, int>{};
    final gaps = <int>[];
    var run = 0;
    var longest = 0;
    var valid = true;
    var restSum = 0;
    for (var step = 0; step < path.length; step++) {
      final result = engine.extract(path[step]);
      if (!result.accepted) {
        valid = false;
        break;
      }
      restSum += engine.tray.length;
      landings[result.slot]++;
      entered[result.cell] = step;
      if (result.matches.isEmpty) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
        for (final m in result.matches) {
          for (final c in m.cells) {
            gaps.add(step - (entered[c] ?? step));
          }
        }
      }
      if (result.status == GameStatus.lost) {
        valid = false;
        break;
      }
    }
    return ReplayResult(
      valid: valid,
      won: engine.status == GameStatus.won,
      peakRest: engine.peakRest,
      landings: landings,
      matchGaps: gaps,
      longestPushRun: longest,
      avgRest: path.isEmpty ? 0 : restSum / path.length,
    );
  }
}
