import '../util/json_read.dart';

/// How a finished run compares with the player's record.
class RunSummary {
  const RunSummary({required this.score, required this.boards, required this.previousBest, required this.newRecord});

  /// The run's final total.
  final int score;

  /// Boards cleared in the run.
  final int boards;

  /// The record before this run.
  final int previousBest;

  /// True when this run beat an earlier record (never on the very first run).
  final bool newRecord;
}

/// The player's endless records — kept apart from level stars, always.
///
/// The record is the highest total of a single run, never a sum of runs.
class EndlessStats {
  EndlessStats({this.best = 0, this.bestBoards = 0, this.last = 0, this.lastBoards = 0, this.runs = 0});

  factory EndlessStats.fromJson(Map<String, Object?> json) => EndlessStats(
        best: readInt(json['best']),
        bestBoards: readInt(json['bestBoards']),
        last: readInt(json['last']),
        lastBoards: readInt(json['lastBoards']),
        runs: readInt(json['runs']),
      );

  /// Highest total of a single run.
  int best;

  /// Most boards cleared in a single run.
  int bestBoards;

  /// Total and boards of the last finished run.
  int last;
  int lastBoards;

  /// Finished runs.
  int runs;

  /// Records a finished run. A tie is not a record, and the very first run
  /// sets the record quietly (there is nothing to beat yet).
  RunSummary record({required int score, required int boards}) {
    final previous = best;
    final newRecord = runs > 0 && score > previous;
    if (score > best) best = score;
    if (boards > bestBoards) bestBoards = boards;
    last = score;
    lastBoards = boards;
    runs++;
    return RunSummary(score: score, boards: boards, previousBest: previous, newRecord: newRecord);
  }

  Map<String, Object?> toJson() => {'best': best, 'bestBoards': bestBoards, 'last': last, 'lastBoards': lastBoards, 'runs': runs};
}
