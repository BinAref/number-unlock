import 'package:flutter/foundation.dart';

import '../core/economy/economy_rules.dart';
import '../core/economy/wallet.dart';
import '../core/endless/endless_stats.dart';
import '../core/levels/level_progress.dart';
import 'save_system.dart';

/// What a level win paid out (for the celebration screen).
class WinReward {
  const WinReward({required this.coins, required this.stars, required this.previousStars});

  final int coins;
  final int stars;

  /// The level's best stars before this win (the best is never lowered).
  final int previousStars;
}

/// The player's state — profile, settings, coins, level progress and endless
/// records — as one observable object. Every change is saved immediately.
///
/// Level stars and endless points are two separate systems: they are stored,
/// shown and rewarded apart, and never added together.
class PlayerService extends ChangeNotifier {
  PlayerService._(this._save, this.economy, this.profile, this.settings, this.progress, this._wallet, this.endless);

  static Future<PlayerService> load(SaveSystem save, EconomyRules economy) async {
    final wallet = await save.loadWallet() ?? Wallet(coins: economy.startingCoins);
    return PlayerService._(
      save,
      economy,
      await save.loadProfile(),
      await save.loadSettings(),
      await save.loadProgress(),
      wallet,
      await save.loadEndlessStats(),
    );
  }

  final SaveSystem _save;
  final EconomyRules economy;
  final PlayerProfile profile;
  final GameSettings settings;

  /// Fixed levels: the best stars of each level and how far the player came.
  final LevelProgress progress;

  /// Endless records (the run in progress lives in the endless service).
  final EndlessStats endless;
  final Wallet _wallet;

  int get coins => _wallet.coins;

  bool canAfford(int amount) => _wallet.canAfford(amount);

  /// Charges once per [opId]; a repeated id never charges again.
  SpendResult spend(int amount, String opId) {
    final r = _wallet.spend(amount, opId: opId);
    if (r == SpendResult.spent) _commitWallet();
    return r;
  }

  bool credit(int amount, String opId) {
    final ok = _wallet.credit(amount, opId: opId);
    if (ok) _commitWallet();
    return ok;
  }

  void _commitWallet() {
    _save.saveWallet(_wallet);
    notifyListeners();
  }

  /// Records a level win: keeps the best stars, unlocks the next level and
  /// pays the coins a first clear or a first three-star win earns.
  WinReward recordLevelWin({required int level, required int stars, required int totalLevels}) {
    final completion = progress.recordWin(level, stars, total: totalLevels);
    final coins = economy.levelCoins(firstClear: completion.firstClear, stars: stars, previousStars: completion.previousStars);
    if (coins > 0) _wallet.credit(coins, opId: 'win:level-$level:${completion.previousStars}->$stars');
    _save.saveProgress(progress);
    _save.saveWallet(_wallet);
    notifyListeners();
    return WinReward(coins: coins, stars: stars, previousStars: completion.previousStars);
  }

  /// Pays the coin endless board [board] may earn; returns the coins paid.
  int creditEndlessBoard({required int runSeed, required int board}) {
    final coins = economy.endlessCoins(board);
    if (coins > 0 && _wallet.credit(coins, opId: 'endless:${runSeed.toRadixString(16)}:$board')) {
      _commitWallet();
      return coins;
    }
    return 0;
  }

  /// Records a finished endless run against the records.
  RunSummary recordEndlessRun({required int score, required int boards}) {
    final summary = endless.record(score: score, boards: boards);
    _save.saveEndlessStats(endless);
    notifyListeners();
    return summary;
  }

  void updateProfile({String? name, int? avatar}) {
    if (name != null) profile.name = name.trim().isEmpty ? null : name.trim();
    if (avatar != null) profile.avatar = avatar;
    _save.saveProfile(profile);
    notifyListeners();
  }

  void updateSettings(void Function(GameSettings s) change) {
    change(settings);
    _save.saveSettings(settings);
    notifyListeners();
  }
}
