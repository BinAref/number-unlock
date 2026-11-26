import 'dart:math' as math;

import '../util/json_read.dart';

/// Rewards and progression numbers (from `assets/config/economy.json`).
class EconomyRules {
  const EconomyRules({
    this.startingCoins = 5,
    this.levelFirstClear = 1,
    this.threeStarBonus = 1,
    this.challengeBase = 1,
    this.challengeEvery = 3,
    this.levelXp = 20,
    this.starXp = 10,
    this.challengeXp = 25,
    this.challengeTierXp = 5,
    this.xpBase = 100,
    this.xpGrowth = 1.12,
  });

  factory EconomyRules.fromJson(Map<String, Object?> json) {
    final rewards = readMap(json['rewards']);
    final xp = readMap(json['xp']);
    return EconomyRules(
      startingCoins: readInt(json['startingCoins'], 5),
      levelFirstClear: readInt(rewards['levelFirstClear'], 1),
      threeStarBonus: readInt(rewards['threeStarBonus'], 1),
      challengeBase: readInt(rewards['challengeBase'], 1),
      challengeEvery: readInt(rewards['challengeEvery'], 3),
      levelXp: readInt(xp['level'], 20),
      starXp: readInt(xp['star'], 10),
      challengeXp: readInt(xp['challenge'], 25),
      challengeTierXp: readInt(xp['challengeTier'], 5),
      xpBase: readInt(xp['base'], 100),
      xpGrowth: readDouble(xp['growth'], 1.12),
    );
  }

  final int startingCoins;
  final int levelFirstClear;
  final int threeStarBonus;
  final int challengeBase;
  final int challengeEvery;
  final int levelXp;
  final int starXp;
  final int challengeXp;
  final int challengeTierXp;
  final int xpBase;
  final double xpGrowth;

  /// Coins for a level win (only the first clear pays, plus a one-time bonus
  /// the first time three stars are reached).
  int levelCoins({required bool firstClear, required int stars, required int previousStars}) =>
      (firstClear ? levelFirstClear : 0) + (stars == 3 && previousStars < 3 ? threeStarBonus : 0);

  int challengeCoins(int tier) => challengeBase + (challengeEvery <= 0 ? 0 : tier ~/ challengeEvery);

  int levelXpFor(int stars) => levelXp + starXp * stars;

  int challengeXpFor(int tier) => challengeXp + challengeTierXp * tier;

  /// XP needed to go from player level [level] to the next.
  int xpToNext(int level) => (xpBase * math.pow(xpGrowth, level - 1)).round();

  PlayerLevel playerLevel(int xp) {
    var level = 1;
    var left = xp;
    while (left >= xpToNext(level)) {
      left -= xpToNext(level);
      level++;
    }
    return PlayerLevel(level: level, xpInLevel: left, xpForNext: xpToNext(level));
  }
}

class PlayerLevel {
  const PlayerLevel({required this.level, required this.xpInLevel, required this.xpForNext});

  final int level;
  final int xpInLevel;
  final int xpForNext;

  double get progress => xpForNext <= 0 ? 0 : (xpInLevel / xpForNext).clamp(0.0, 1.0);
}
