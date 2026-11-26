import '../difficulty/difficulty_analyzer.dart';
import '../generator/difficulty_curve.dart';
import '../generator/level_generator.dart';
import '../model/puzzle_definition.dart';
import '../random/seeded_random.dart';
import '../rules/rule_book.dart';
import '../rules/rule_engine.dart';
import '../util/json_read.dart';

/// One challenge attempt ("run"): tiers climb as puzzles are solved and the
/// run ends when a puzzle is lost.
class ChallengeRun {
  ChallengeRun({required this.tier, required this.solved, required this.seed, List<int>? recent, this.score = 0})
      : recent = recent ?? <int>[];

  /// Points earned in this run so far.
  int score;

  factory ChallengeRun.fresh(int seed) => ChallengeRun(tier: 1, solved: 0, seed: seed);

  factory ChallengeRun.fromJson(Map<String, Object?> json) => ChallengeRun(
        tier: readInt(json['tier'], 1),
        solved: readInt(json['solved']),
        seed: readInt(json['seed']),
        recent: readIntList(json['recent']),
        score: readInt(json['score']),
      );

  /// Current difficulty step (1 = gentlest).
  int tier;

  /// Puzzles solved in this run.
  int solved;

  /// Seed of the current tier's puzzle.
  int seed;

  /// Fingerprints of recent puzzles, so none repeats.
  final List<int> recent;

  static const int memory = 40;

  void advance(int nextSeed, int finishedFingerprint) {
    solved++;
    tier++;
    seed = nextSeed;
    remember(finishedFingerprint);
  }

  void remember(int fingerprint) {
    recent.remove(fingerprint);
    recent.add(fingerprint);
    while (recent.length > memory) {
      recent.removeAt(0);
    }
  }

  Map<String, Object?> toJson() => {'tier': tier, 'solved': solved, 'seed': seed, 'recent': recent, 'score': score};
}

/// Builds challenge puzzles on demand: a fresh seed every time, the same
/// verification and difficulty measurement as the fixed levels, and a
/// difficulty that follows the tier (not a fixed puzzle per tier).
class ChallengeDirector {
  ChallengeDirector({required this.curve, required this.rules, this.analyzer = const DifficultyAnalyzer(AnalyzerConfig.quick)});

  final DifficultyCurve curve;
  final RuleSet rules;
  final DifficultyAnalyzer analyzer;

  RuleEngine engineFor(int tier) => RuleEngine.forPuzzle(rules, mode: PuzzleMode.challenge.key, level: tier);

  /// A resumable job producing the puzzle for [tier] from [seed].
  GenerationJob jobFor(int tier, int seed) {
    final rng = SeededRandom(seed);
    final params = curve.paramsFor(tier, rng);
    final generator = LevelGenerator(engineFor(tier), analyzer: analyzer, rulesetVersion: rules.version);
    return GenerationJob(generator, params, seed: rng.nextUint32(), maxAttempts: curve.attemptsFor(tier));
  }

  PuzzleDefinition toPuzzle(GeneratedPuzzle generated, {required int tier, required int seed}) => PuzzleDefinition(
        id: 'challenge-$tier-$seed',
        mode: PuzzleMode.challenge,
        layout: generated.layout,
        rulesetVersion: rules.version,
        challengeTier: tier,
        seed: seed,
        profile: generated.profile,
        solution: generated.solution,
      );

  /// A new seed that is not tied to anything the player saw before.
  static int freshSeed(int entropy, int salt) => combineSeeds(entropy, salt);
}
