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

/// Stars: three for a booster-free win that never kept more tiles waiting
/// than the puzzle strictly needs, two for any booster-free win, one when
/// boosters helped.
int starsFor({required bool usedBoosters, required int peakRest, required int minRest}) {
  if (usedBoosters) return 1;
  return peakRest <= minRest ? 3 : 2;
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
