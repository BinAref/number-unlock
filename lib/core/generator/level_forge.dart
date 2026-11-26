import '../difficulty/difficulty_analyzer.dart';
import '../difficulty/difficulty_profile.dart';
import '../jobs/compute_job.dart';
import '../model/puzzle_definition.dart';
import '../model/puzzle_layout.dart';
import '../random/seeded_random.dart';
import '../rules/rule_book.dart';
import '../rules/rule_engine.dart';
import 'difficulty_curve.dart';
import 'generation_params.dart';
import 'level_generator.dart';

/// Forges level N of the endless journey.
///
/// A pure function of (curve, rules, N): integer-seeded randomness and
/// platform-identical maths mean every phone, every browser and the build
/// tool produce exactly the same puzzle — level 500 is the same for
/// everyone in the world.
class LevelForge {
  LevelForge({required this.curve, required this.book, this.analyzer = const DifficultyAnalyzer(AnalyzerConfig.levels)});

  final DifficultyCurve curve;
  final RuleBook book;
  final DifficultyAnalyzer analyzer;

  ComputeJob<PuzzleDefinition> job(int level) => _ForgeJob(this, level);

  PuzzleDefinition forge(int level) => runToCompletion(job(level), slice: 1);
}

class _ForgeJob implements ComputeJob<PuzzleDefinition> {
  _ForgeJob(this.f, this.level)
      : _rules = RuleEngine.forPuzzle(f.book.current, mode: PuzzleMode.levels.key, level: level),
        _seed = combineSeeds(f.curve.seedFor(level), 0) {
    _rng = SeededRandom(_seed);
  }

  final LevelForge f;
  final int level;
  final RuleEngine _rules;
  final int _seed;
  late final SeededRandom _rng;
  GenerationJob? _job;
  GenerationParams? _params;
  int _draw = 0;
  GeneratedPuzzle? _best;
  double _bestPenalty = double.infinity;
  PuzzleDefinition? _result;

  @override
  PuzzleDefinition get result => _result!;

  @override
  bool step(int units) {
    if (_result != null) return true;
    final hand = f.curve.handcraftedFor(level);
    if (hand != null) {
      final r = f.analyzer.analyze(hand.layout, _rules, rulesetVersion: f.book.currentVersion, seed: f.curve.seedFor(level))!;
      _result = _definition(hand.layout, r.profile, r.solution, 0);
      return true;
    }
    for (var u = 0; u < units; u++) {
      final job = _job;
      if (job == null) {
        if (_draw >= 3 && _best != null) return _finish();
        if (_draw >= 9) throw StateError('Level $level could not be forged.');
        _params = f.curve.paramsFor(level, _rng);
        _job = GenerationJob(
          LevelGenerator(_rules, analyzer: f.analyzer, rulesetVersion: f.book.currentVersion),
          _params!,
          seed: _rng.nextUint32(),
          maxAttempts: f.curve.attemptsFor(level),
        );
        _draw++;
        continue;
      }
      if (!job.step(1)) continue;
      _job = null;
      final r = job.result;
      if (r == null) continue;
      final penalty = LevelGenerator.penaltyFor(r.profile, _params!);
      if (penalty < _bestPenalty) {
        _bestPenalty = penalty;
        _best = r;
      }
      if (penalty <= LevelGenerator.closeEnough) return _finish();
    }
    return false;
  }

  bool _finish() {
    final b = _best!;
    _result = _definition(b.layout, b.profile, b.solution, _seed);
    return true;
  }

  PuzzleDefinition _definition(PuzzleLayout layout, DifficultyProfile profile, List<int> solution, int seed) => PuzzleDefinition(
        id: 'level-$level',
        mode: PuzzleMode.levels,
        layout: layout,
        rulesetVersion: f.book.currentVersion,
        levelNumber: level,
        seed: seed,
        profile: profile,
        solution: solution,
      );
}
