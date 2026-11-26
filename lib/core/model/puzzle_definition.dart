import '../difficulty/difficulty_profile.dart';
import '../util/json_read.dart';
import 'puzzle_layout.dart';

enum PuzzleMode {
  /// Fixed levels: the same puzzle for everyone, rated with stars.
  levels,

  /// Endless runs: random boards, cumulative points, until a loss.
  endless;

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
    this.boardNumber,
    this.seed,
    this.profile,
    this.solution,
  });

  /// Reads a puzzle saved with its arrows (`dirs`, `open`, `arrows`).
  /// Puzzles saved before the arrow rule have no `open` field and are
  /// rejected, so an old saved attempt is dropped instead of replayed under
  /// the retired "open all four neighbours" rule.
  factory PuzzleDefinition.fromJson(Map<String, Object?> json) {
    final rows = readInt(json['rows']);
    final cols = readInt(json['cols']);
    final difficulty = json['difficulty'];
    final solution = json['solution'];
    final open = readStringOrNull(json['open']);
    if (open == null) throw const FormatException('Puzzle data predates the arrow rule.');
    return PuzzleDefinition(
      id: readString(json['id']),
      mode: PuzzleMode.values.firstWhere((m) => m.name == json['mode'], orElse: () => PuzzleMode.levels),
      layout: PuzzleLayout.decode(
        rows,
        cols,
        readString(json['cells']),
        dirs: readStringOrNull(json['dirs']),
        open: open,
        arrows: readBool(json['arrows'], true),
      ),
      rulesetVersion: readInt(json['rules'], 1),
      levelNumber: readIntOrNull(json['level']),
      boardNumber: readIntOrNull(json['board']),
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

  /// The board's place in its endless run (1 = first).
  final int? boardNumber;
  final int? seed;
  final DifficultyProfile? profile;

  /// A verified winning order of picks (cell indices), when known.
  final List<int>? solution;

  Map<String, Object?> toJson({bool includeSolution = true}) => {
        'id': id,
        'mode': mode.name,
        if (levelNumber != null) 'level': levelNumber,
        if (boardNumber != null) 'board': boardNumber,
        if (seed != null) 'seed': seed,
        'rows': layout.rows,
        'cols': layout.cols,
        'cells': layout.encodeCells(),
        'dirs': layout.encodeDirs(),
        'open': layout.encodeOpen(),
        'arrows': layout.hasArrows,
        'rules': rulesetVersion,
        if (profile != null) 'difficulty': profile!.toJson(),
        if (includeSolution && solution != null) 'solution': solution,
      };
}
