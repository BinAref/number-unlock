import 'dart:convert';

import '../core/challenge/challenge_system.dart';
import '../core/economy/wallet.dart';
import '../core/engine/game_engine.dart';
import '../core/levels/level_progress.dart';
import '../core/util/json_read.dart';
import 'storage.dart';

class PlayerProfile {
  PlayerProfile({this.name, this.avatar = 0});

  factory PlayerProfile.fromJson(Map<String, Object?> json) =>
      PlayerProfile(name: readStringOrNull(json['name']), avatar: readInt(json['avatar']));

  /// Null until the player picks a name (the UI shows a localised default).
  String? name;
  int avatar;

  Map<String, Object?> toJson() => {if (name != null) 'name': name, 'avatar': avatar};
}

class GameSettings {
  GameSettings({
    this.music = true,
    this.sfx = true,
    this.vibration = true,
    this.reducedEffects = false,
    this.language,
    this.theme = 'system',
  });

  factory GameSettings.fromJson(Map<String, Object?> json) => GameSettings(
        music: readBool(json['music'], true),
        sfx: readBool(json['sfx'], true),
        vibration: readBool(json['vibration'], true),
        reducedEffects: readBool(json['reduced']),
        language: readStringOrNull(json['language']),
        theme: readString(json['theme'], 'system'),
      );

  bool music;
  bool sfx;
  bool vibration;
  bool reducedEffects;

  /// Null: follow the device language.
  String? language;

  /// A theme id, or `system` to follow the device.
  String theme;

  Map<String, Object?> toJson() => {
        'music': music,
        'sfx': sfx,
        'vibration': vibration,
        'reduced': reducedEffects,
        if (language != null) 'language': language,
        'theme': theme,
      };
}

/// Everything persisted, one JSON document per key.
class SaveSystem {
  SaveSystem(this.store);

  final KeyValueStore store;

  static const String profileKey = 'un.profile';
  static const String settingsKey = 'un.settings';
  static const String progressKey = 'un.progress';
  static const String walletKey = 'un.wallet';
  static const String playerKey = 'un.player';
  static const String challengeRunKey = 'un.challenge.run';

  static String attemptKey(String mode) => 'un.attempt.$mode';

  Future<Map<String, Object?>?> _read(String key) async {
    final raw = await store.read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return readMap(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, Object?> json) => store.write(key, jsonEncode(json));

  Future<PlayerProfile> loadProfile() async => PlayerProfile.fromJson(await _read(profileKey) ?? const {});
  Future<void> saveProfile(PlayerProfile p) => _write(profileKey, p.toJson());

  Future<GameSettings> loadSettings() async => GameSettings.fromJson(await _read(settingsKey) ?? const {});
  Future<void> saveSettings(GameSettings s) => _write(settingsKey, s.toJson());

  Future<LevelProgress> loadProgress() async => LevelProgress.fromJson(await _read(progressKey) ?? const {});
  Future<void> saveProgress(LevelProgress p) => _write(progressKey, p.toJson());

  Future<Wallet?> loadWallet() async {
    final json = await _read(walletKey);
    return json == null ? null : Wallet.fromJson(json);
  }

  Future<void> saveWallet(Wallet w) => _write(walletKey, w.toJson());

  /// XP and records: `{"xp":640,"best":1280,"bestTier":7,"solved":23}`.
  Future<Map<String, Object?>> loadPlayer() async => await _read(playerKey) ?? const <String, Object?>{};
  Future<void> savePlayer(Map<String, Object?> json) => _write(playerKey, json);

  /// The unfinished attempt of a mode (`levels` or `challenge`).
  Future<GameSnapshot?> loadAttempt(String mode) async {
    final json = await _read(attemptKey(mode));
    if (json == null) return null;
    try {
      return GameSnapshot.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> saveAttempt(String mode, GameSnapshot snapshot) => _write(attemptKey(mode), snapshot.toJson());
  Future<void> clearAttempt(String mode) => store.remove(attemptKey(mode));

  Future<ChallengeRun?> loadChallengeRun() async {
    final json = await _read(challengeRunKey);
    return json == null ? null : ChallengeRun.fromJson(json);
  }

  Future<void> saveChallengeRun(ChallengeRun run) => _write(challengeRunKey, run.toJson());
  Future<void> clearChallengeRun() => store.remove(challengeRunKey);
}
