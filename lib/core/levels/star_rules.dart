import '../util/json_read.dart';

/// Stars for a level, from how much help the win took — a rule the player
/// understands and controls: no help at all → 3, one help → 2, more → 1,
/// a loss → 0. Every hint (free or paid), the sixth slot and a swap each
/// count as one help. Thresholds come from `economy.json` (`stars`).
class StarRules {
  const StarRules({this.helpsFor3 = 0, this.helpsFor2 = 1});

  factory StarRules.fromJson(Map<String, Object?> json) => StarRules(
        helpsFor3: readInt(json['helpsFor3'], 0),
        helpsFor2: readInt(json['helpsFor2'], 1),
      );

  /// Most helps that still earn three stars.
  final int helpsFor3;

  /// Most helps that still earn two stars.
  final int helpsFor2;

  int starsFor({required bool won, required int helps}) {
    if (!won) return 0;
    if (helps <= helpsFor3) return 3;
    if (helps <= helpsFor2) return 2;
    return 1;
  }
}
