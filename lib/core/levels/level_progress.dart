import '../util/json_read.dart';

/// How a level appears on the map.
enum LevelNodeState { completed, open, current, locked }

class LevelCompletion {
  const LevelCompletion({required this.level, required this.stars, required this.previousStars, required this.firstClear});

  final int level;
  final int stars;
  final int previousStars;
  final bool firstClear;

  bool get improved => stars > previousStars;
}

/// Completed levels, their best stars and how far the player has unlocked.
class LevelProgress {
  LevelProgress({Map<int, int>? stars, this.highestUnlocked = 1}) : stars = stars ?? <int, int>{};

  factory LevelProgress.fromJson(Map<String, Object?> json) {
    final raw = readMap(json['stars']);
    return LevelProgress(
      stars: {for (final e in raw.entries) int.parse(e.key): readInt(e.value)},
      highestUnlocked: readInt(json['highest'], 1),
    );
  }

  final Map<int, int> stars;

  /// The newest level that can be played.
  int highestUnlocked;

  bool isCompleted(int level) => stars.containsKey(level);

  int starsOf(int level) => stars[level] ?? 0;

  int get completedCount => stars.length;

  int get totalStars => stars.values.fold(0, (a, b) => a + b);

  /// Levels finished with all three stars.
  int get threeStarCount => stars.values.where((s) => s >= 3).length;

  /// Progress through the levels as mastery, 0..1: the stars earned out of
  /// all the stars the completed levels can give (the journey never ends,
  /// so a share of levels completed would mean nothing).
  double get mastery => completedCount == 0 ? 0 : totalStars / (3 * completedCount);

  /// The level the play button continues with.
  int currentLevel(int total) => highestUnlocked.clamp(1, total);

  bool canPlay(int level, {int openAhead = 0}) => level >= 1 && level <= highestUnlocked + openAhead;

  LevelNodeState stateOf(int level, {int openAhead = 0}) {
    if (isCompleted(level)) return LevelNodeState.completed;
    if (level == highestUnlocked) return LevelNodeState.current;
    if (canPlay(level, openAhead: openAhead)) return LevelNodeState.open;
    return LevelNodeState.locked;
  }

  /// Records a win, keeping the best stars, and unlocks the next level.
  LevelCompletion recordWin(int level, int earnedStars, {required int total}) {
    final previous = starsOf(level);
    final firstClear = !isCompleted(level);
    stars[level] = earnedStars > previous ? earnedStars : previous;
    if (level >= highestUnlocked && level < total) highestUnlocked = level + 1;
    return LevelCompletion(level: level, stars: earnedStars, previousStars: previous, firstClear: firstClear);
  }

  Map<String, Object?> toJson() => {
        'stars': {for (final e in stars.entries) '${e.key}': e.value},
        'highest': highestUnlocked,
      };
}
