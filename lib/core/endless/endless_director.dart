import 'dart:math' as math;

import '../difficulty/difficulty_analyzer.dart';
import '../generator/difficulty_curve.dart';
import '../generator/level_generator.dart';
import '../jobs/compute_job.dart';
import '../model/puzzle_definition.dart';
import '../random/seeded_random.dart';
import '../rules/rule_book.dart';
import '../rules/rule_engine.dart';
import 'endless_run.dart';

/// Makes the boards of endless runs.
///
/// Board i of a run comes from (run seed, i), with the difficulty of board i
/// on `endless_curve.json`: gentle at first, harder with every board and no
/// jumps (bands interpolate smoothly, no vault rhythm). Every board is built
/// solvable and verified before it is shown — a player can lose by their own
/// choices, never to an impossible board.
class EndlessDirector {
  EndlessDirector({required this.curve, required this.rules, this.analyzer = const DifficultyAnalyzer(AnalyzerConfig.quick)});

  final DifficultyCurve curve;
  final RuleSet rules;
  final DifficultyAnalyzer analyzer;

  RuleEngine engineFor(int board) => RuleEngine.forPuzzle(rules, mode: PuzzleMode.endless.key, level: board);

  /// Points a cleared board is worth before its quality: rises with the
  /// board number, so later boards matter more.
  static int basePoints(int board) => 100 + 20 * (math.max(1, board) - 1);

  /// A fresh 32-bit run seed from [entropy] that none of [recentSeeds] used.
  static int freshSeed(int Function() entropy, Iterable<int> recentSeeds) {
    final used = recentSeeds.toSet();
    var seed = entropy() & 0xFFFFFFFF;
    for (var guard = 0; used.contains(seed) && guard < 64; guard++) {
      seed = entropy() & 0xFFFFFFFF;
    }
    return seed;
  }

  /// The resumable job building a board at difficulty [difficulty] from [seed].
  GenerationJob jobFor(int difficulty, int seed) {
    final rng = SeededRandom(seed);
    final params = curve.paramsFor(difficulty, rng);
    final generator = LevelGenerator(engineFor(difficulty), analyzer: analyzer, rulesetVersion: rules.version);
    return GenerationJob(generator, params, seed: rng.nextUint32(), maxAttempts: curve.attemptsFor(difficulty));
  }

  /// Builds board [board] of [run], skipping layouts the run already had.
  /// When a seed yields nothing usable, other seeds are tried, then a touch
  /// gentler settings (the fallback) — never an unverified board.
  ComputeJob<PuzzleDefinition?> boardJob(EndlessRun run, int board) => _BoardJob(this, run.seedFor(board), board, List<int>.of(run.recent));

  PuzzleDefinition toPuzzle(GeneratedPuzzle generated, {required int board, required int seed}) => PuzzleDefinition(
        id: 'endless-$board-${EndlessRun.seedText(seed)}',
        mode: PuzzleMode.endless,
        layout: generated.layout,
        rulesetVersion: rules.version,
        boardNumber: board,
        seed: seed,
        profile: generated.profile,
        solution: generated.solution,
      );
}

class _BoardJob implements ComputeJob<PuzzleDefinition?> {
  _BoardJob(this.d, this.seed, this.board, this.recent) : _difficulty = board;

  final EndlessDirector d;
  final int seed;
  final int board;
  final List<int> recent;
  int _difficulty;
  int _try = 0;
  GenerationJob? _job;
  PuzzleDefinition? _result;
  bool _done = false;

  static const int _triesPerDifficulty = 3;
  static const int _maxTries = 9;

  int get _seed => _try == 0 ? seed : combineSeeds(seed, 0x5EED0000 + _try);

  @override
  PuzzleDefinition? get result => _result;

  @override
  bool step(int units) {
    if (_done) return true;
    final job = _job ??= d.jobFor(_difficulty, _seed);
    if (!job.step(units)) return false;
    _job = null;
    final g = job.result;
    if (g != null && !recent.contains(g.layout.fingerprint())) {
      _result = d.toPuzzle(g, board: board, seed: _seed);
      return _done = true;
    }
    _try++;
    if (_try >= _maxTries) return _done = true;
    if (_try % _triesPerDifficulty == 0) _difficulty = math.max(1, _difficulty - 1);
    return false;
  }
}
