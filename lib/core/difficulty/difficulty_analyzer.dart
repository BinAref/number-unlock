import 'dart:math' as math;
import 'dart:typed_data';

import '../model/puzzle_layout.dart';
import '../random/seeded_random.dart';
import '../rules/rule_engine.dart';
import '../solver/playouts.dart';
import '../solver/puzzle_solver.dart';
import '../solver/solver_context.dart';
import '../solver/solver_search.dart';
import '../solver/state_set.dart';
import 'difficulty_profile.dart';

class AnalyzerConfig {
  const AnalyzerConfig({
    this.capacity = 5,
    this.proofBudgets = const <int, int>{2: 60000, 3: 500000, 4: 3000000, 5: 4000000},
    this.branchBudget = 250000,
    this.branchCheckBudget = 8000,
    this.randomRuns = 300,
    this.greedyRuns = 160,
  });

  /// Light settings for on-device generation (challenges).
  static const AnalyzerConfig quick = AnalyzerConfig(
    proofBudgets: <int, int>{2: 6000, 3: 30000, 4: 90000, 5: 150000},
    branchBudget: 15000,
    branchCheckBudget: 1200,
    randomRuns: 100,
    greedyRuns: 50,
  );

  /// Reception slots a player has without boosters.
  final int capacity;

  /// Work allowed per slot-count proof (2, 3, 4 … slots).
  final Map<int, int> proofBudgets;

  /// Work allowed for judging the choices along the solution.
  final int branchBudget;
  final int branchCheckBudget;
  final int randomRuns;
  final int greedyRuns;
}

class AnalysisReport {
  const AnalysisReport({required this.profile, required this.solution, required this.expansions});

  final DifficultyProfile profile;

  /// The easiest known winning order of picks.
  final List<int> solution;
  final int expansions;
}

class _Branches {
  const _Branches({required this.steps, required this.choices, required this.winning, required this.dead, required this.traps, required this.expansions});

  final int steps;
  final int choices;
  final int winning;
  final int dead;
  final int traps;
  final int expansions;

  double get deadEndRatio => (winning + dead) == 0 ? 0 : dead / (winning + dead);
  double get avgChoices => steps == 0 ? 0 : choices / steps;
}

/// Measures how hard a puzzle really is, using the actual game rules.
///
/// Criteria: the fewest reception slots that can solve it (with a proof that
/// fewer cannot), how often slots 3, 4 and 5 are needed, how far apart
/// matching tiles are, how many choices win or lead to dead ends (and which
/// dead ends look tempting), and how forgiving random or greedy play is.
class DifficultyAnalyzer {
  const DifficultyAnalyzer([this.config = const AnalyzerConfig()]);

  final AnalyzerConfig config;

  AnalysisReport? analyze(
    PuzzleLayout layout,
    RuleEngine rules, {
    required int rulesetVersion,
    required int seed,
    List<int>? witness,
  }) {
    final ctx = SolverContext(layout, rules);
    final solver = PuzzleSolver(ctx);
    final cap = config.capacity;
    var expansions = 0;

    final mc = solver.minCapacity(maxCapacity: cap, budgets: config.proofBudgets, knownPath: witness);
    expansions += mc.expansions;
    int minCap;
    bool proven;
    List<int> path;
    if (mc.capacity != null) {
      minCap = mc.capacity!;
      proven = mc.proven;
      path = mc.path!;
    } else {
      if (witness == null) return null;
      final check = solver.replay(witness, capacity: cap, rulesetVersion: rulesetVersion);
      if (!check.valid || !check.won) return null;
      minCap = check.peakRest + 1;
      proven = false;
      path = witness;
    }
    if (witness != null && !proven) {
      final w = solver.replay(witness, capacity: cap, rulesetVersion: rulesetVersion);
      if (w.valid && w.won && w.peakRest + 1 < minCap) {
        minCap = w.peakRest + 1;
        path = witness;
      }
    }

    final replay = solver.replay(path, capacity: cap, rulesetVersion: rulesetVersion);
    if (!replay.won) return null;
    final branches = _branches(ctx, path);
    expansions += branches.expansions;

    final rng = SeededRandom(seed);
    final playouts = Playouts(ctx);
    final randomWin = playouts.winRate(capacity: cap, runs: config.randomRuns, policy: PlayoutPolicy.random, rng: rng);
    final greedyWin = playouts.winRate(capacity: cap, runs: config.greedyRuns, policy: PlayoutPolicy.greedy, rng: rng);
    final gaps = replay.matchGaps;
    final avgGap = gaps.isEmpty ? 0.0 : gaps.fold<int>(0, (a, b) => a + b) / gaps.length;

    final s = score(
      minCapacity: minCap,
      randomWin: randomWin,
      greedyWin: greedyWin,
      deadEnds: branches.deadEndRatio,
      traps: branches.traps,
      tiles: layout.tileCount,
      longestRun: replay.longestPushRun,
    );
    return AnalysisReport(
      profile: DifficultyProfile(
        score: s,
        tier: tierFor(s),
        minCapacity: minCap,
        minCapacityProven: proven,
        slotLandings: replay.landings,
        randomWinRate: randomWin,
        greedyWinRate: greedyWin,
        deadEndRatio: branches.deadEndRatio,
        avgChoices: branches.avgChoices,
        trapMoves: branches.traps,
        avgMatchGap: avgGap,
        longestPushRun: replay.longestPushRun,
        tiles: layout.tileCount,
      ),
      solution: path,
      expansions: expansions,
    );
  }

  /// Combines the criteria into 0..100.
  static int score({
    required int minCapacity,
    required double randomWin,
    required double greedyWin,
    required double deadEnds,
    required int traps,
    required int tiles,
    required int longestRun,
  }) {
    final capPart = switch (minCapacity) {
      <= 2 => 0.0,
      3 => 16.0,
      4 => 34.0,
      _ => 52.0,
    };
    final r = randomWin.clamp(0.0005, 1.0);
    final randomPart = 18.0 * ((-math.log(r) / math.ln10) / 3.3).clamp(0.0, 1.0);
    final greedyPart = 9.0 * (1 - greedyWin.clamp(0.0, 1.0));
    final deadPart = 9.0 * deadEnds.clamp(0.0, 1.0);
    final trapPart = math.min(3.0, traps * 0.25);
    final sizePart = 5.0 * (tiles / 48).clamp(0.0, 1.0);
    final planPart = math.min(4.0, longestRun * 0.5);
    final total = capPart + randomPart + greedyPart + deadPart + trapPart + sizePart + planPart;
    return total.round().clamp(0, 100);
  }

  static DifficultyTier tierFor(int score) {
    if (score < 25) return DifficultyTier.easy;
    if (score < 48) return DifficultyTier.medium;
    if (score < 70) return DifficultyTier.hard;
    return DifficultyTier.expert;
  }

  _Branches _branches(SolverContext ctx, List<int> path) {
    final cap = config.capacity;
    final keyLength = ctx.keyLengthFor(cap);
    final failures = StateSet(keyLength);
    final successes = StateSet(keyLength);
    final key = Uint32List(keyLength);
    final removed = Uint32List(ctx.wordCount);
    final removedCells = <int>[];
    final tray = <int>[];
    var remaining = ctx.layout.tileCount;
    _markPath(ctx, successes, const <int>[], const <int>[], path);

    var budget = config.branchBudget;
    var used = 0;
    var steps = 0;
    var choices = 0;
    var winning = 0;
    var dead = 0;
    var traps = 0;
    for (final move in path) {
      if (budget <= 0) break;
      steps++;
      for (final c in ctx.tiles) {
        if (SolverContext.isSet(removed, c) || !ctx.topology.isOpenInMask(c, removed)) continue;
        final child = List<int>.of(tray)..add(c);
        final matched = ctx.resolver.resolveQuietly(child) > 0;
        choices++;
        bool? wins;
        if (child.length >= cap) {
          wins = false;
        } else if (remaining - 1 == 0) {
          wins = child.isEmpty;
        } else {
          SolverContext.setBit(removed, c);
          ctx.encodeKey(key, removed, child);
          if (successes.contains(key)) {
            wins = true;
          } else if (failures.contains(key)) {
            wins = false;
          } else if (budget > 0) {
            final start = [...removedCells, c];
            final search = SolverSearch(
              ctx,
              removed: start,
              tray: child,
              capacity: cap,
              failures: failures,
              nodeBudget: math.max(1, math.min(config.branchCheckBudget, budget)),
            );
            while (search.advance(4096) == SearchStatus.running) {}
            budget -= search.expansions;
            used += search.expansions;
            if (search.status == SearchStatus.solved) {
              wins = true;
              _markPath(ctx, successes, start, child, search.solution!);
            } else if (search.status == SearchStatus.exhausted) {
              wins = false;
            }
          }
          SolverContext.clearBit(removed, c);
        }
        if (wins == true) {
          winning++;
        } else if (wins == false) {
          dead++;
          if (matched) traps++;
        }
      }
      SolverContext.setBit(removed, move);
      removedCells.add(move);
      remaining--;
      tray.add(move);
      ctx.resolver.resolveQuietly(tray);
    }
    return _Branches(steps: steps, choices: choices, winning: winning, dead: dead, traps: traps, expansions: used);
  }

  /// Records every state along a winning path as winnable.
  void _markPath(SolverContext ctx, StateSet successes, List<int> removedCells, List<int> tray, List<int> path) {
    final key = Uint32List(successes.keyLength);
    final removed = ctx.maskOf(removedCells);
    final t = List<int>.of(tray);
    var remaining = ctx.layout.tileCount - removedCells.length;
    ctx.encodeKey(key, removed, t);
    successes.add(key);
    for (final move in path) {
      SolverContext.setBit(removed, move);
      remaining--;
      t.add(move);
      ctx.resolver.resolveQuietly(t);
      if (remaining == 0 || t.length >= config.capacity) break;
      ctx.encodeKey(key, removed, t);
      successes.add(key);
    }
  }
}
