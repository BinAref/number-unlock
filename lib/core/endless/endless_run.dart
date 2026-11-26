import '../random/seeded_random.dart';
import '../util/json_read.dart';

/// One endless run: boards keep coming, each harder than the last, until a
/// board is lost. Points from cleared boards add up and are never reset
/// within the run.
///
/// The run seed is random — never shared between players or between runs —
/// and every board of the run follows from it, so a resumed run continues
/// with exactly the boards it would have had.
class EndlessRun {
  EndlessRun({required this.seed, this.board = 1, this.score = 0, this.hintsUsed = 0, this.freeSwapUsed = false, List<int>? recent})
      : recent = recent ?? <int>[];

  factory EndlessRun.fromJson(Map<String, Object?> json) => EndlessRun(
        seed: int.tryParse(readString(json['seed']), radix: 16) ?? 0,
        board: readInt(json['board'], 1),
        score: readInt(json['score']),
        hintsUsed: readInt(json['hints']),
        freeSwapUsed: readBool(json['freeSwap']),
        recent: readIntList(json['recent']),
      );

  /// The run's 32-bit seed (saved as hex).
  final int seed;

  /// The board being played (1 = the gentlest).
  int board;

  /// Points banked from cleared boards.
  int score;

  /// Free hints the run has used so far (the run's allowance is fixed).
  int hintsUsed;

  /// Whether the run's free swap is spent.
  bool freeSwapUsed;

  /// Fingerprints of this run's boards, so none repeats.
  final List<int> recent;

  static const int memory = 60;

  int get boardsCleared => board - 1;

  /// The seed of board [index] of this run.
  int seedFor(int index) => combineSeeds(seed, index);

  /// Banks a cleared board's points and moves on to the next board.
  void clearBoard(int points, int fingerprint) {
    score += points;
    board++;
    remember(fingerprint);
  }

  void remember(int fingerprint) {
    recent.remove(fingerprint);
    recent.add(fingerprint);
    while (recent.length > memory) {
      recent.removeAt(0);
    }
  }

  static String seedText(int seed) => (seed & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  Map<String, Object?> toJson() => {
        'seed': seedText(seed),
        'board': board,
        'score': score,
        'hints': hintsUsed,
        'freeSwap': freeSwapUsed,
        'recent': recent,
      };
}
