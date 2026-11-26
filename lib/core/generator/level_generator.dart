import 'dart:math' as math;

import '../difficulty/difficulty_analyzer.dart';
import '../difficulty/difficulty_profile.dart';
import '../engine/game_engine.dart';
import '../jobs/compute_job.dart';
import '../model/arrows.dart';
import '../model/puzzle_definition.dart';
import '../model/puzzle_layout.dart';
import '../model/tile_spec.dart';
import '../random/seeded_random.dart';
import '../rules/rule_engine.dart';
import '../rules/match_resolver.dart';
import '../solver/path_counter.dart';
import '../solver/puzzle_solver.dart';
import '../solver/solver_context.dart';
import 'generation_params.dart';
import 'unlock_structure.dart';

/// Resumable hardening (one mutation per [step]); see [LevelGenerator.harden].
///
/// Raises the bar one slot at a time — first two slots must fail, then
/// three … — guided by the exact number of winning orders at that slot
/// count, which local search drives down to zero. Earlier stages are never
/// undone, and the puzzle always stays solvable with the base slots.
class Hardener {
  Hardener(this._gen, Candidate start, this._p, this._rng)
      : _layout = start.layout,
        _witness = start.witness,
        _target = _p.targetCapacity.clamp(2, _gen.baseCapacity).toInt() {
    _k = 1;
    _nextStage();
  }

  final LevelGenerator _gen;
  final GenerationParams _p;
  final SeededRandom _rng;
  final int _target;
  PuzzleLayout _layout;
  List<int> _witness;
  late int _k;
  bool _uniqueStage = false;

  /// Fewest slots proven necessary so far (counts reached zero below it).
  int _floor = 2;
  double? _count;
  late PuzzleLayout _best;
  late List<int> _bestWitness;
  double _bestCount = 0;
  int _steps = 0;

  /// Counts that ran past their budget in a row: a board too wide to count
  /// is not hardened further (keeps forging time bounded on every device).
  int _overflows = 0;
  static const int _maxOverflows = 3;
  bool _done = false;
  Candidate? _result;

  Candidate get result => _result ?? Candidate(_layout, _witness, _floor);

  int get _stageCapacity => _uniqueStage ? _gen.baseCapacity : _k;

  /// Winning orders wanted at the end of the stage: none below the target,
  /// exactly one in the final "unique solution" stage.
  double get _goal => _uniqueStage ? 1 : 0;

  void _nextStage() {
    if (_uniqueStage) return _finish();
    _k++;
    if (_k >= _target) {
      if (!_p.unique) return _finish();
      _uniqueStage = true;
    }
    _count = _gen._countPaths(_layout, _stageCapacity);
    if (_count == null) return _finish();
    _best = _layout;
    _bestWitness = _witness;
    _bestCount = _count!;
    if (_count! <= _goal) {
      if (!_uniqueStage) _floor = _k + 1;
      _nextStage();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    var layout = _layout;
    if (!_gen.rules.usesColor) {
      final cells = List<TileSpec?>.of(layout.cells);
      _gen._recolor(cells, layout.rows, layout.cols, _p.colorCount, _rng);
      layout = layout.withCells(cells);
    }
    _result = Candidate(layout, List<int>.unmodifiable(_witness), _floor);
  }

  /// Gives up after a few counts in a row overflow, keeping the best layout.
  bool _overflowed() {
    if (++_overflows < _maxOverflows) return false;
    _layout = _best;
    _witness = _bestWitness;
    _finish();
    return true;
  }

  /// One mutation attempt; returns true when hardening is over.
  bool step() {
    if (_done) return true;
    if (_steps >= _p.hardenSteps) {
      _layout = _best;
      _witness = _bestWitness;
      _finish();
      return true;
    }
    _steps++;
    final k = _stageCapacity;
    PuzzleLayout? next;
    if (_rng.chance(0.5)) {
      final cheap = PuzzleSolver(SolverContext(_layout, _gen.rules)).solve(capacity: k, nodeBudget: 20000);
      if (cheap.solved) {
        final pairs = _gen._matchedPairs(_layout, cheap.path!);
        if (pairs.isNotEmpty) next = _gen._breakPair(_layout, _rng.pick(pairs), _rng);
      }
    }
    next ??= _gen._swapRandom(_layout, _rng);
    if (next == null) return false;
    final guard = _uniqueStage ? _target - 1 : k - 1;
    if (guard >= 2) {
      final g = _gen._countPaths(next, guard);
      if (g == null) return _overflowed();
      if (g != 0) return false;
    }
    final c = _gen._countPaths(next, k);
    if (c == null) return _overflowed();
    _overflows = 0;
    if (c < _goal) return false;
    final count = _count!;
    final accept = c < count || (c == count && _rng.chance(0.35)) || _rng.chance(0.02);
    if (!accept) return false;
    final check = PuzzleSolver(SolverContext(next, _gen.rules)).solve(capacity: _gen.baseCapacity, nodeBudget: 120000);
    if (!check.solved) return false;
    _layout = next;
    _witness = check.path!;
    _count = c;
    if (c < _bestCount) {
      _best = next;
      _bestWitness = _witness;
      _bestCount = c;
    }
    if (c <= _goal) {
      if (!_uniqueStage) _floor = k + 1;
      _nextStage();
      return _done;
    }
    return false;
  }
}

/// A whole generation run as a resumable job (challenge puzzles are made on
/// the device, in slices between frames).
class GenerationJob implements ComputeJob<GeneratedPuzzle?> {
  GenerationJob(this.generator, this.params, {required int seed, this.maxAttempts = 12}) : _rng = SeededRandom(seed);

  final LevelGenerator generator;
  final GenerationParams params;
  final int maxAttempts;
  final SeededRandom _rng;
  int _attempt = 0;
  Hardener? _hardener;
  Candidate? _candidate;
  GeneratedPuzzle? _best;
  double _bestPenalty = double.infinity;
  bool _done = false;

  @override
  GeneratedPuzzle? get result => _best;

  @override
  bool step(int units) {
    for (var u = 0; u < units && !_done; u++) {
      _advance();
    }
    return _done;
  }

  void _advance() {
    final hardener = _hardener;
    if (hardener != null) {
      if (hardener.step()) {
        _candidate = hardener.result;
        _hardener = null;
      }
      return;
    }
    final candidate = _candidate;
    if (candidate == null) {
      if (_attempt >= maxAttempts) {
        _done = true;
        return;
      }
      _attempt++;
      final built = generator.buildCandidate(params, _rng);
      if (built == null) return;
      if (params.hardenSteps > 0 && params.targetCapacity > 2) {
        _hardener = Hardener(generator, built, params, _rng);
      } else {
        _candidate = built;
      }
      return;
    }
    _candidate = null;
    final report = generator.analyzer.analyze(
      candidate.layout,
      generator.rules,
      rulesetVersion: generator.rulesetVersion,
      seed: _rng.nextUint32(),
      witness: candidate.witness,
      minCapacityFloor: candidate.provenFloor,
    );
    if (report == null) return;
    final penalty = LevelGenerator.penaltyFor(report.profile, params);
    if (penalty < _bestPenalty) {
      _bestPenalty = penalty;
      _best = GeneratedPuzzle(
        layout: candidate.layout,
        solution: report.solution,
        profile: report.profile,
        attempts: _attempt,
        meetsTarget: penalty == 0,
      );
    }
    if (penalty <= LevelGenerator.closeEnough) _done = true;
  }
}

/// A layout plus the hidden order of picks it was built around.
class Candidate {
  const Candidate(this.layout, this.witness, [this.provenFloor = 2]);

  final PuzzleLayout layout;
  final List<int> witness;

  /// Fewest slots already proven necessary (fewer were shown impossible).
  final int provenFloor;
}

class GeneratedPuzzle {
  const GeneratedPuzzle({
    required this.layout,
    required this.solution,
    required this.profile,
    required this.attempts,
    required this.meetsTarget,
  });

  final PuzzleLayout layout;
  final List<int> solution;
  final DifficultyProfile profile;
  final int attempts;

  /// False when the closest candidate missed the requested band.
  final bool meetsTarget;
}

/// Builds puzzles that are solvable by construction, then measures them.
///
/// 1. Shape: the grid, plus an empty cell when needed so the tile count is
///    even (every match removes two tiles).
/// 2. The arrows ([UnlockStructureBuilder]), then a hidden winning order of
///    picks that respects them.
/// 3. A tray "height walk" for that order: when a pick must wait and when it
///    must match the tile before it, never exceeding the target depth.
/// 4. Values (and colours) chosen through the rule engine to honour the walk.
/// 5. Verification with the real game engine, then difficulty analysis.
///
/// Nothing reaches a player unverified.
class LevelGenerator {
  LevelGenerator(
    this.rules, {
    this.analyzer = const DifficultyAnalyzer(),
    this.rulesetVersion = 1,
    this.baseCapacity = 5,
    this.hardenBudgets = const <int, int>{2: 120000, 3: 250000, 4: 500000},
  });

  final RuleEngine rules;
  final DifficultyAnalyzer analyzer;
  final int rulesetVersion;

  /// Slots every puzzle must be solvable with, without boosters.
  final int baseCapacity;

  /// Work allowed per slot-count proof while hardening.
  final Map<int, int> hardenBudgets;

  /// Tries up to [maxAttempts] candidates and returns the first inside the
  /// requested band, or the closest one found.
  GeneratedPuzzle? generate(GenerationParams params, {required int seed, int maxAttempts = 30}) =>
      runToCompletion(GenerationJob(this, params, seed: seed, maxAttempts: maxAttempts), slice: 64);

  /// A candidate this close to its band is kept: hunting for the exact band
  /// on boards that naturally land a point or two outside it only burns time.
  static const double closeEnough = 3;

  /// 0 when [profile] satisfies [params]; grows with the distance otherwise.
  static double penaltyFor(DifficultyProfile profile, GenerationParams params) {
    var penalty = 0.0;
    if (profile.score < params.minScore) penalty += params.minScore - profile.score;
    if (profile.score > params.maxScore) penalty += profile.score - params.maxScore;
    if (params.exactCapacity && profile.minCapacity != params.targetCapacity) {
      penalty += 40.0 * (profile.minCapacity - params.targetCapacity).abs();
    }
    if (params.requireProof && !profile.minCapacityProven) penalty += 25;
    return penalty;
  }

  Candidate? buildCandidate(GenerationParams p, SeededRandom rng) {
    final rows = p.rows;
    final cols = p.cols;
    final n = rows * cols;
    final gaps = math.max(0, math.min(p.bottomGaps, cols - 2));
    var voids = p.voids >= 0 ? p.voids : (p.holes > 0 ? ((n - gaps) * p.holes).round() : ((n - gaps).isOdd ? 1 : 0));
    if ((n - gaps - voids).isOdd) voids += 1;
    if (n - gaps - voids < 2) return null;

    final isTile = List<bool>.filled(n, true);
    if (p.shape == 'corridors') {
      if (!_carve(isTile, rows, cols, p, rng)) return null;
    } else {
      if (!_placeBottomGaps(isTile, rows, cols, gaps, rng)) return null;
      if (!_placeVoids(isTile, rows, cols, voids, rng, scatter: p.holes > 0)) return null;
    }
    final structure = const UnlockStructureBuilder().build(isTile, rows, cols, p.arrows, p.entrances, rng);
    if (structure == null) return null;
    if (p.spread) return _buildSpread(p, rng, isTile, rows, cols, structure);
    final order = _peel(rows, cols, isTile, structure, p.peel, rng);
    if (order.length != isTile.where((t) => t).length) return null;
    final depth = math.max(1, math.min(p.targetDepth, order.length ~/ 2));
    final walk = _walk(order.length, depth, p.minPeakVisits, p.climb, rng, floor: math.min(p.floorDepth, depth - 1));
    if (walk == null) return null;
    final specs = _assignSpecs(walk, p, rng);
    if (specs == null) return null;

    final cells = List<TileSpec?>.filled(n, null);
    for (var i = 0; i < order.length; i++) {
      cells[order[i]] = specs[i];
    }
    if (!rules.usesColor) _recolor(cells, rows, cols, p.colorCount, rng);
    final layout = PuzzleLayout(rows: rows, cols: cols, cells: cells, dirs: structure.dirs, open: structure.open, hasArrows: structure.hasArrows);

    final engine = GameEngine(
      puzzle: PuzzleDefinition(id: 'candidate', mode: PuzzleMode.levels, layout: layout, rulesetVersion: rulesetVersion),
      rules: rules,
      baseCapacity: depth + 1,
    );
    for (final c in order) {
      if (!engine.extract(c).accepted) return null;
    }
    if (engine.status != GameStatus.won) return null;
    return Candidate(layout, List<int>.unmodifiable(order));
  }

  /// Counterexample-guided hardening.
  ///
  /// Repeatedly finds the cheapest remaining solution (one slot below the
  /// target), breaks one of its matches by moving a tile, and keeps the
  /// change only if the puzzle is still solvable with the base slots. It
  /// stops once fewer slots are proven to fail — so "needs five slots" is a
  /// fact, not a hope.
  Candidate harden(Candidate start, GenerationParams p, SeededRandom rng) {
    final hardener = Hardener(this, start, p, rng);
    while (!hardener.step()) {}
    return hardener.result;
  }

  /// Values grouped into families that match each other under the active
  /// pair rules (with the first release: {1,9} {2,8} {3,7} {4,6} {5}).
  List<List<int>> _families() {
    final family = List<int>.filled(10, -1);
    final out = <List<int>>[];
    for (var v = TileSpec.minValue; v <= TileSpec.maxValue; v++) {
      if (family[v] >= 0) continue;
      final group = <int>[v];
      family[v] = out.length;
      for (var w = v + 1; w <= TileSpec.maxValue; w++) {
        if (family[w] < 0 && rules.pairMatches(TileSpec(v, 0), TileSpec(w, 0))) {
          family[w] = out.length;
          group.add(w);
        }
      }
      if (rules.pairMatches(TileSpec(v, 0), TileSpec(v, 0)) || group.length > 1) out.add(group);
    }
    return out;
  }

  Candidate? _buildSpread(GenerationParams p, SeededRandom rng, List<bool> isTile, int rows, int cols, UnlockStructure structure) {
    final n = rows * cols;
    final cells = [
      for (var i = 0; i < n; i++)
        if (isTile[i]) i,
    ];
    final families = _families();
    if (families.isEmpty || cells.length.isOdd) return null;
    final weights = [for (final f in families) f.length == 1 ? 0.6 : 1.0];
    final pairsOf = List<int>.filled(families.length, 0);
    for (var k = 0; k < cells.length ~/ 2; k++) {
      pairsOf[rng.pickWeighted([for (var f = 0; f < families.length; f++) weights[f] / (1 + pairsOf[f])])]++;
    }
    final labels = <int>[
      for (var f = 0; f < families.length; f++)
        for (var k = 0; k < pairsOf[f] * 2; k++) f,
    ];
    rng.shuffle(labels);
    final label = List<int>.filled(n, -1);
    for (var i = 0; i < cells.length; i++) {
      label[cells[i]] = labels[i];
    }
    _anneal(label, cells, rows, cols, rng);

    final high = p.complementRatio.clamp(0.0, 1.0) * 0.5;
    final specs = List<TileSpec?>.filled(n, null);
    for (final c in cells) {
      final fam = families[label[c]];
      final v = fam.length == 1 ? fam.first : (rng.chance(high) ? fam.last : fam.first);
      specs[c] = TileSpec(v, 0);
    }
    if (!rules.usesColor) _recolor(specs, rows, cols, p.colorCount, rng);
    final layout = PuzzleLayout(rows: rows, cols: cols, cells: specs, dirs: structure.dirs, open: structure.open, hasArrows: structure.hasArrows);
    final solved = PuzzleSolver(SolverContext(layout, rules)).solve(capacity: baseCapacity, nodeBudget: 150000);
    if (!solved.solved) return null;
    return Candidate(layout, List<int>.unmodifiable(solved.path!));
  }

  /// Simulated annealing that pushes same-family tiles apart (and out of
  /// the same row), so open frontiers rarely offer an easy pair.
  void _anneal(List<int> label, List<int> cells, int rows, int cols, SeededRandom rng) {
    double pairCost(int a, int b) {
      final ra = a ~/ cols;
      final rb = b ~/ cols;
      final d = (ra - rb).abs() + (a % cols - b % cols).abs();
      var cost = d == 1 ? 8.0 : (d == 2 ? 3.0 : (d == 3 ? 1.0 : 0.0));
      if (ra == rb) {
        cost += 2.5;
        if (ra == rows - 1) cost += 6;
      }
      return cost;
    }

    double cellCost(int c) {
      var s = 0.0;
      for (final o in cells) {
        if (o != c && label[o] == label[c]) s += pairCost(c, o);
      }
      return s;
    }

    var temp = 2.5;
    final iterations = cells.length * 70;
    for (var it = 0; it < iterations; it++) {
      final a = rng.pick(cells);
      final b = rng.pick(cells);
      if (a == b || label[a] == label[b]) continue;
      final before = cellCost(a) + cellCost(b);
      final la = label[a];
      label[a] = label[b];
      label[b] = la;
      final delta = cellCost(a) + cellCost(b) - before;
      if (delta > 0 && !rng.chance(detExpNeg(delta / temp))) {
        label[b] = label[a];
        label[a] = la;
      }
      temp = math.max(0.05, temp * 0.997);
    }
  }

  double? _countPaths(PuzzleLayout layout, int capacity) =>
      PathCounter(SolverContext(layout, rules), capacity: capacity, stateBudget: hardenBudgets[capacity] ?? 200000)
          .countFromStart();

  PuzzleLayout? _swapRandom(PuzzleLayout layout, SeededRandom rng) {
    final tiles = layout.tileIndices.toList();
    for (var attempt = 0; attempt < 12; attempt++) {
      final a = rng.pick(tiles);
      final b = rng.pick(tiles);
      if (a == b) continue;
      final sa = layout.specOf(a);
      final sb = layout.specOf(b);
      if (rules.pairMatches(sa, sb)) continue;
      final cells = List<TileSpec?>.of(layout.cells);
      cells[a] = sb;
      cells[b] = sa;
      return layout.withCells(cells);
    }
    return null;
  }

  /// The matches made along [path]: (tile that waited, tile that matched it).
  List<(int, int)> _matchedPairs(PuzzleLayout layout, List<int> path) {
    final resolver = MatchResolver(rules.bind(layout));
    final tray = <int>[];
    final out = <(int, int)>[];
    for (final c in path) {
      tray.add(c);
      for (final step in resolver.resolve(tray)) {
        if (step.cells.length == 2) out.add((step.cells[0], step.cells[1]));
      }
    }
    return out;
  }

  /// Swaps the matching tile of [pair] with a tile it does not match.
  PuzzleLayout? _breakPair(PuzzleLayout layout, (int, int) pair, SeededRandom rng) {
    final (waiting, matching) = pair;
    final sw = layout.specOf(waiting);
    final sm = layout.specOf(matching);
    final options = [
      for (final t in layout.tileIndices)
        if (t != waiting &&
            t != matching &&
            !rules.pairMatches(sw, layout.specOf(t)) &&
            !rules.pairMatches(sm, layout.specOf(t)))
          t,
    ];
    if (options.isEmpty) return null;
    final other = rng.pick(options);
    final cells = List<TileSpec?>.of(layout.cells);
    cells[matching] = layout.specOf(other);
    cells[other] = sm;
    return layout.withCells(cells);
  }

  static List<int> _neighbors(int i, int rows, int cols) {
    final r = i ~/ cols;
    final c = i % cols;
    return [
      if (r > 0) i - cols,
      if (r < rows - 1) i + cols,
      if (c > 0) i - 1,
      if (c < cols - 1) i + 1,
    ];
  }

  static bool _reachable(List<bool> isTile, int rows, int cols) {
    final n = rows * cols;
    final seen = List<bool>.filled(n, false);
    final queue = <int>[];
    for (var c = 0; c < cols; c++) {
      final i = (rows - 1) * cols + c;
      if (isTile[i]) {
        seen[i] = true;
        queue.add(i);
      }
    }
    var head = 0;
    while (head < queue.length) {
      final i = queue[head++];
      for (final j in _neighbors(i, rows, cols)) {
        if (isTile[j] && !seen[j]) {
          seen[j] = true;
          queue.add(j);
        }
      }
    }
    for (var i = 0; i < n; i++) {
      if (isTile[i] && !seen[i]) return false;
    }
    return queue.isNotEmpty;
  }

  bool _placeBottomGaps(List<bool> isTile, int rows, int cols, int count, SeededRandom rng) {
    if (count == 0) return true;
    final bottom = (rows - 1) * cols;
    final columns = List<int>.generate(cols, (c) => c);
    for (var attempt = 0; attempt < 40; attempt++) {
      rng.shuffle(columns);
      final chosen = columns.take(count).toList();
      // Keep gaps apart so the bottom row stays readable.
      var spaced = true;
      for (final a in chosen) {
        for (final b in chosen) {
          if (a != b && (a - b).abs() < 2) spaced = false;
        }
      }
      if (!spaced && attempt < 30) continue;
      for (final c in chosen) {
        isTile[bottom + c] = false;
      }
      if (_reachable(isTile, rows, cols)) return true;
      for (final c in chosen) {
        isTile[bottom + c] = true;
      }
    }
    return false;
  }

  /// Empties [count] cells above the bottom row, keeping every tile linked to
  /// the bottom row. A lone parity void sits high on the board; [scatter]
  /// spreads many holes evenly instead.
  bool _placeVoids(List<bool> isTile, int rows, int cols, int count, SeededRandom rng, {bool scatter = false}) {
    if (count == 0) return true;
    if (rows < 2) return false;
    final rowWeights = [for (var r = 0; r < rows - 1; r++) scatter ? 1.0 : (rows - 1 - r).toDouble()];
    final tries = scatter ? 120 : 48;
    for (var v = 0; v < count; v++) {
      var placed = false;
      for (var attempt = 0; attempt < tries && !placed; attempt++) {
        final r = rng.pickWeighted(rowWeights);
        final i = r * cols + rng.nextInt(cols);
        if (!isTile[i]) continue;
        isTile[i] = false;
        if (_reachable(isTile, rows, cols)) {
          placed = true;
        } else {
          isTile[i] = true;
        }
      }
      if (!placed) return false;
    }
    return true;
  }

  /// A hidden winning order of picks that respects the arrows: a tile can be
  /// picked once it is open, and picking it opens what its arrows point at.
  List<int> _peel(int rows, int cols, List<bool> isTile, UnlockStructure structure, PeelStyle style, SeededRandom rng) {
    final n = rows * cols;
    final removed = List<bool>.filled(n, false);
    final opened = List<bool>.generate(n, (i) => isTile[i] && structure.open[i]);
    final order = <int>[];
    final span = math.max(1, rows - 1);
    bool isOpen(int i) => isTile[i] && !removed[i] && opened[i];

    while (true) {
      final open = [
        for (var i = 0; i < n; i++)
          if (isOpen(i)) i,
      ];
      if (open.isEmpty) break;
      var mode = style;
      if (style == PeelStyle.mixed) {
        mode = const [PeelStyle.random, PeelStyle.layered, PeelStyle.deep][rng.pickWeighted(const [0.4, 0.3, 0.3])];
      }
      final int pick;
      switch (mode) {
        case PeelStyle.layered:
          pick = open[rng.pickWeighted([
            for (final i in open) 1 + 4 * ((i ~/ cols) / span) * ((i ~/ cols) / span),
          ])];
        case PeelStyle.deep:
          pick = open[rng.pickWeighted([
            for (final i in open) 1 + 4 * ((rows - 1 - i ~/ cols) / span) * ((rows - 1 - i ~/ cols) / span),
          ])];
        case PeelStyle.random:
        case PeelStyle.mixed:
          pick = rng.pick(open);
      }
      removed[pick] = true;
      order.add(pick);
      for (final d in Arrows.each) {
        if (!Arrows.has(structure.dirs[pick], d)) continue;
        final j = Arrows.target(pick, d, rows, cols);
        if (j >= 0 && isTile[j]) opened[j] = true;
      }
    }
    return order;
  }

  /// A sequence of push (true) / match (false) steps whose height never
  /// exceeds [depth] and ends at zero.
  List<bool>? _walk(int n, int depth, int minPeaks, double climb, SeededRandom rng, {int floor = 0}) {
    if (n.isOdd || n < 2) return null;
    for (var attempt = 0; attempt < 80; attempt++) {
      final out = <bool>[];
      var h = 0;
      var peaks = 0;
      var top = 0;
      var reached = floor <= 0;
      var ok = true;
      for (var i = 0; i < n; i++) {
        final left = n - i;
        final canPush = h < depth && h + 1 <= left - 1;
        // Once the floor is reached, stay at or above it until the end.
        final canPop = h > 0 && (!reached || h > floor || left <= h);
        bool push;
        if (canPush && canPop) {
          push = rng.chance(0.5 + 0.4 * climb * (1 - h / depth));
        } else if (canPush || canPop) {
          push = canPush;
        } else {
          ok = false;
          break;
        }
        h += push ? 1 : -1;
        out.add(push);
        if (h > top) top = h;
        if (h >= floor) reached = true;
        if (push && h == depth) peaks++;
      }
      if (ok && h == 0 && top == depth && peaks >= minPeaks) return out;
    }
    return null;
  }

  /// Carves a tree of one-tile-wide corridors from bottom-row entrances
  /// (no loops, no 2 × 2 blocks), so the open front stays narrow even on
  /// a 10 × 10 frame: branches, dead ends and long detours make the order
  /// of picks matter.
  bool _carve(List<bool> isTile, int rows, int cols, GenerationParams p, SeededRandom rng) {
    final n = rows * cols;
    isTile.fillRange(0, n, false);
    var target = (n * p.fill).round();
    if (target.isOdd) target--;
    final bottom = (rows - 1) * cols;
    final columns = List<int>.generate(cols, (c) => c);
    rng.shuffle(columns);
    final active = <int>[];
    for (final c in columns) {
      if (active.length >= math.max(1, p.entrances)) break;
      if ((c > 0 && isTile[bottom + c - 1]) || (c < cols - 1 && isTile[bottom + c + 1])) continue;
      isTile[bottom + c] = true;
      active.add(bottom + c);
    }
    var count = active.length;
    final entrance = List<bool>.filled(n, false);
    for (final e in active) {
      entrance[e] = true;
    }
    // Each tile must be able to open what grows from it: no more children
    // than one tile's arrows allow.
    final maxKids = p.arrows.enabled ? p.arrows.maxArrows : 3;
    bool free(int i) {
      if (isTile[i] || i >= bottom) return false;
      var touching = 0;
      var via = -1;
      for (final j in _neighbors(i, rows, cols)) {
        if (isTile[j]) {
          touching++;
          via = j;
        }
      }
      if (touching != 1) return false;
      var degree = 0;
      for (final k in _neighbors(via, rows, cols)) {
        if (isTile[k]) degree++;
      }
      if ((entrance[via] ? degree : degree - 1) >= maxKids) return false;
      final r = i ~/ cols;
      final c = i % cols;
      for (var r0 = r - 1; r0 <= r; r0++) {
        for (var c0 = c - 1; c0 <= c; c0++) {
          if (r0 < 0 || c0 < 0 || r0 + 1 >= rows || c0 + 1 >= cols) continue;
          var filled = 0;
          for (final idx in [r0 * cols + c0, r0 * cols + c0 + 1, (r0 + 1) * cols + c0, (r0 + 1) * cols + c0 + 1]) {
            if (idx == i || isTile[idx]) filled++;
          }
          if (filled == 4) return false;
        }
      }
      return true;
    }

    var guard = 0;
    while (count < target && active.isNotEmpty && guard++ < n * 50) {
      final from = rng.chance(0.65) ? active.last : active[rng.nextInt(active.length)];
      final options = <int>[];
      final weights = <double>[];
      for (final j in _neighbors(from, rows, cols)) {
        if (!free(j)) continue;
        options.add(j);
        weights.add(j ~/ cols < from ~/ cols ? 3.0 : 1.7);
      }
      if (options.isEmpty) {
        active.remove(from);
        continue;
      }
      final next = options[rng.pickWeighted(weights)];
      isTile[next] = true;
      active.add(next);
      count++;
    }
    return count.isEven && count >= target * 0.8 && _reachable(isTile, rows, cols);
  }

  List<TileSpec>? _assignSpecs(List<bool> walk, GenerationParams p, SeededRandom rng) {
    final colorSlots = rules.usesColor ? math.max(1, p.colorCount) : 1;
    final stack = <TileSpec>[];
    final out = <TileSpec>[];
    final used = List<int>.filled(10, 0);
    double weightOf(TileSpec s) => (s.value == 5 ? 0.55 : 1.0) / (1 + used[s.value]);
    for (final push in walk) {
      final top = stack.isEmpty ? null : stack.last;
      var candidates = <TileSpec>[];
      if (push) {
        for (var v = TileSpec.minValue; v <= TileSpec.maxValue; v++) {
          for (var c = 0; c < colorSlots; c++) {
            final s = TileSpec(v, c);
            if (top == null || !rules.pairMatches(top, s)) candidates.add(s);
          }
        }
      } else {
        if (top == null) return null;
        final same = <TileSpec>[];
        final other = <TileSpec>[];
        for (var v = TileSpec.minValue; v <= TileSpec.maxValue; v++) {
          for (var c = 0; c < colorSlots; c++) {
            final s = TileSpec(v, c);
            if (rules.pairMatches(top, s)) (s.value == top.value ? same : other).add(s);
          }
        }
        final useOther = other.isNotEmpty && (same.isEmpty || rng.chance(p.complementRatio));
        candidates = useOther ? other : same;
      }
      if (candidates.isEmpty) return null;
      final s = candidates[rng.pickWeighted([for (final x in candidates) weightOf(x)])];
      used[s.value]++;
      if (push) {
        stack.add(s);
      } else {
        stack.removeLast();
      }
      out.add(s);
    }
    return out;
  }

  void _recolor(List<TileSpec?> cells, int rows, int cols, int colorCount, SeededRandom rng) {
    final k = colorCount.clamp(2, 8);
    final colors = List<int>.filled(cells.length, -1);
    final order = [
      for (var i = 0; i < cells.length; i++)
        if (cells[i] != null) i,
    ];
    rng.shuffle(order);
    final use = List<int>.filled(k, 0);
    for (final i in order) {
      final weights = List<double>.filled(k, 1.0);
      for (final j in _neighbors(i, rows, cols)) {
        final cj = colors[j];
        if (cj >= 0) weights[cj] *= 0.15;
      }
      for (var c = 0; c < k; c++) {
        weights[c] /= 1 + use[c] * 0.35;
      }
      final c = rng.pickWeighted(weights);
      colors[i] = c;
      use[c]++;
      cells[i] = TileSpec(cells[i]!.value, c);
    }
  }
}
