import '../difficulty/difficulty_profile.dart';
import '../util/json_read.dart';
import 'puzzle_layout.dart';

enum PuzzleMode {
  levels,
  challenge;

  /// Key used by rule availability (`modes` in `rules.json`).
  String get key => name;
}

/// A complete puzzle: its fixed layout plus identity and metadata.
class PuzzleDefinition {
  const PuzzleDefinition({
    required this.id,
    required this.mode,
    required this.layout,
    required this.rulesetVersion,
    this.levelNumber,
    this.challengeTier,
    this.seed,
    this.profile,
    this.solution,
  });

  factory PuzzleDefinition.fromJson(Map<String, Object?> json) {
    final rows = readInt(json['rows']);
    final cols = readInt(json['cols']);
    final difficulty = json['difficulty'];
    final solution = json['solution'];
    return PuzzleDefinition(
      id: readString(json['id']),
      mode: PuzzleMode.values.firstWhere((m) => m.name == json['mode'], orElse: () => PuzzleMode.levels),
      layout: PuzzleLayout.decode(rows, cols, readString(json['cells'])),
      rulesetVersion: readInt(json['rules'], 1),
      levelNumber: readIntOrNull(json['level']),
      challengeTier: readIntOrNull(json['tier']),
      seed: readIntOrNull(json['seed']),
      profile: difficulty == null ? null : DifficultyProfile.fromJson(readMap(difficulty)),
      solution: solution == null ? null : readIntList(solution),
    );
  }

  final String id;
  final PuzzleMode mode;
  final PuzzleLayout layout;
  final int rulesetVersion;
  final int? levelNumber;
  final int? challengeTier;
  final int? seed;
  final DifficultyProfile? profile;

  /// A verified winning order of picks (cell indices), when known.
  final List<int>? solution;

  Map<String, Object?> toJson({bool includeSolution = true}) => {
        'id': id,
        'mode': mode.name,
        if (levelNumber != null) 'level': levelNumber,
        if (challengeTier != null) 'tier': challengeTier,
        if (seed != null) 'seed': seed,
        'rows': layout.rows,
        'cols': layout.cols,
        'cells': layout.encodeCells(),
        'rules': rulesetVersion,
        if (profile != null) 'difficulty': profile!.toJson(),
        if (includeSolution && solution != null) 'solution': solution,
      };
}
