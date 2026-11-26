import '../levels/star_rules.dart';
import '../util/json_read.dart';

/// Rewards and the star rules (from `assets/config/economy.json`).
class EconomyRules {
  const EconomyRules({
    this.startingCoins = 5,
    this.levelFirstClear = 1,
    this.threeStarBonus = 1,
    this.endlessEvery = 3,
    this.stars = const StarRules(),
  });

  factory EconomyRules.fromJson(Map<String, Object?> json) {
    final rewards = readMap(json['rewards']);
    return EconomyRules(
      startingCoins: readInt(json['startingCoins'], 5),
      levelFirstClear: readInt(rewards['levelFirstClear'], 1),
      threeStarBonus: readInt(rewards['threeStarBonus'], 1),
      endlessEvery: readInt(rewards['endlessEvery'], 3),
      stars: StarRules.fromJson(readMap(json['stars'])),
    );
  }

  final int startingCoins;
  final int levelFirstClear;
  final int threeStarBonus;

  /// One coin for every this many boards cleared in an endless run.
  final int endlessEvery;

  /// How a won level turns into stars.
  final StarRules stars;

  /// Coins for a level win (only the first clear pays, plus a one-time bonus
  /// the first time three stars are reached).
  int levelCoins({required bool firstClear, required int stars, required int previousStars}) =>
      (firstClear ? levelFirstClear : 0) + (stars == 3 && previousStars < 3 ? threeStarBonus : 0);

  /// Coins for clearing endless board [board].
  int endlessCoins(int board) => endlessEvery > 0 && board > 0 && board % endlessEvery == 0 ? 1 : 0;
}
