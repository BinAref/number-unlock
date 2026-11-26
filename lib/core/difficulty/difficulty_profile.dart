import '../util/json_read.dart';

enum DifficultyTier { easy, medium, hard, expert }

/// Measured difficulty of one puzzle (see `DifficultyAnalyzer`).
class DifficultyProfile {
  const DifficultyProfile({
    required this.score,
    required this.tier,
    required this.minCapacity,
    required this.minCapacityProven,
    this.slotLandings = const <int>[],
    this.randomWinRate = 0,
    this.greedyWinRate = 0,
    this.deadEndRatio = 0,
    this.avgChoices = 0,
    this.trapMoves = 0,
    this.avgMatchGap = 0,
    this.longestPushRun = 0,
    this.tiles = 0,
  });

  factory DifficultyProfile.fromJson(Map<String, Object?> json) => DifficultyProfile(
        score: readInt(json['score']),
        tier: DifficultyTier.values.firstWhere((t) => t.name == json['tier'], orElse: () => DifficultyTier.easy),
        minCapacity: readInt(json['minCap'], 5),
        minCapacityProven: readBool(json['proven']),
        slotLandings: readIntList(json['landings']),
        randomWinRate: readDouble(json['randomWin']),
        greedyWinRate: readDouble(json['greedyWin']),
        deadEndRatio: readDouble(json['deadEnds']),
        avgChoices: readDouble(json['choices']),
        trapMoves: readInt(json['traps']),
        avgMatchGap: readDouble(json['matchGap']),
        longestPushRun: readInt(json['planRun']),
        tiles: readInt(json['tiles']),
      );

  /// 0 (trivial) .. 100 (fiendish).
  final int score;
  final DifficultyTier tier;

  /// Fewest reception slots that can solve the puzzle.
  final int minCapacity;

  /// True when every smaller slot count was proven unsolvable.
  final bool minCapacityProven;

  /// How many times the easiest known solution lands a tile in slot k
  /// (index 0 = slot 1).
  final List<int> slotLandings;

  /// Share of random play-throughs that win with five slots.
  final double randomWinRate;

  /// Share of "always take a match" play-throughs that win.
  final double greedyWinRate;

  /// Share of choices along the solution that lead to a dead end.
  final double deadEndRatio;

  /// Average number of open tiles to choose from along the solution.
  final double avgChoices;

  /// Dead-end choices that looked tempting (they made an immediate match).
  final int trapMoves;

  /// Average number of picks between a tile entering the tray and its match.
  final double avgMatchGap;

  /// Longest stretch of picks without any match (planning ahead).
  final int longestPushRun;
  final int tiles;

  /// Tiles that must wait in the tray at once for the easiest solution.
  int get minRestDepth => minCapacity - 1;

  Map<String, Object?> toJson() => {
        'score': score,
        'tier': tier.name,
        'minCap': minCapacity,
        'proven': minCapacityProven,
        'landings': slotLandings,
        'randomWin': _round(randomWinRate),
        'greedyWin': _round(greedyWinRate),
        'deadEnds': _round(deadEndRatio),
        'choices': _round(avgChoices),
        'traps': trapMoves,
        'matchGap': _round(avgMatchGap),
        'planRun': longestPushRun,
        'tiles': tiles,
      };

  static double _round(double v) => (v * 1000).round() / 1000;
}
