import 'package:flutter/foundation.dart';

import '../core/economy/economy_rules.dart';
import '../core/economy/wallet.dart';
import '../core/levels/level_progress.dart';
import '../core/util/json_read.dart';
import 'save_system.dart';

/// What a win paid out (for the celebration screen).
class WinReward {
  const WinReward({required this.coins, required this.xp, required this.stars, required this.levelUp});

  final int coins;
  final int xp;
  final int stars;
  final bool levelUp;
}

/// The player's state — profile, settings, coins, XP and level progress —
/// as one observable object. Every change is saved immediately.
class PlayerService extends ChangeNotifier {
  PlayerService._(this._save, this.economy, this.profile, this.settings, this.progress, this._wallet, Map<String, Object?> stats)
      : _xp = readInt(stats['xp']),
        bestScore = readInt(stats['best']),
        bestTier = readInt(stats['bestTier']),
        challengesSolved = readInt(stats['solved']);

  static Future<PlayerService> load(SaveSystem save, EconomyRules economy) async {
    final wallet = await save.loadWallet() ?? Wallet(coins: economy.startingCoins);
    return PlayerService._(
      save,
      economy,
      await save.loadProfile(),
      await save.loadSettings(),
      await save.loadProgress(),
      wallet,
      await save.loadPlayer(),
    );
  }

  final SaveSystem _save;
  final EconomyRules economy;
  final PlayerProfile profile;
  final GameSettings settings;
  final LevelProgress progress;
  final Wallet _wallet;
  int _xp;

  /// Highest challenge run score ever reached.
  int bestScore;

  /// Highest challenge difficulty ever reached.
  int bestTier;
  int challengesSolved;

  int get coins => _wallet.coins;
  int get xp => _xp;
  PlayerLevel get level => economy.playerLevel(_xp);

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

  WinReward recordLevelWin({required int level, required int stars, required int totalLevels}) {
    final before = this.level.level;
    final completion = progress.recordWin(level, stars, total: totalLevels);
    final coins = economy.levelCoins(firstClear: completion.firstClear, stars: stars, previousStars: completion.previousStars);
    final xpGain = completion.improved || completion.firstClear ? economy.levelXpFor(stars) : economy.levelXp ~/ 4;
    _xp += xpGain;
    if (coins > 0) _wallet.credit(coins, opId: 'win:level-$level:${completion.previousStars}->$stars');
    _save.saveProgress(progress);
    _save.saveWallet(_wallet);
    _savePlayer();
    notifyListeners();
    return WinReward(coins: coins, xp: xpGain, stars: stars, levelUp: this.level.level > before);
  }

  WinReward recordChallengeWin({required int tier, required int seed}) {
    final before = level.level;
    challengesSolved++;
    final coins = economy.challengeCoins(tier);
    final xpGain = economy.challengeXpFor(tier);
    _xp += xpGain;
    _wallet.credit(coins, opId: 'win:challenge-$tier-$seed');
    _save.saveWallet(_wallet);
    _savePlayer();
    notifyListeners();
    return WinReward(coins: coins, xp: xpGain, stars: 0, levelUp: level.level > before);
  }

  void _savePlayer() => _save.savePlayer({'xp': _xp, 'best': bestScore, 'bestTier': bestTier, 'solved': challengesSolved});

  /// Records a challenge run total; true when it is a new personal best.
  bool recordRunScore(int score, int tier) {
    final isNew = score > bestScore;
    if (isNew) bestScore = score;
    if (tier > bestTier) bestTier = tier;
    _savePlayer();
    notifyListeners();
    return isNew;
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
