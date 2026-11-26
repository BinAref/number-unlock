import 'dart:convert';

import '../core/economy/wallet.dart';
import '../core/endless/endless_run.dart';
import '../core/endless/endless_stats.dart';
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

/// Everything persisted, one JSON document per key (save schema v3).
class SaveSystem {
  SaveSystem(this.store);

  final KeyValueStore store;

  /// The save layout this build writes.
  static const int schema = 3;

  static const String schemaKey = 'un.schema';
  static const String profileKey = 'un.profile';
  static const String settingsKey = 'un.settings';
  static const String walletKey = 'un.wallet';

  /// Level progress: `{"highest":27,"stars":{"1":3,"2":2}}`.
  static const String levelsKey = 'un.levels';

  /// The endless run in progress: `{"seed":"9f2c41d0","board":7,"score":2310,…}`.
  static const String endlessRunKey = 'un.endless.run';

  /// Endless records: `{"best":4820,"bestBoards":17,"last":1290,"lastBoards":6,"runs":23}`.
  static const String endlessStatsKey = 'un.endless.stats';

  /// Recent run seeds, so a new run never repeats one: `{"seeds":["9f2c41d0",…]}`.
  static const String endlessSeedsKey = 'un.endless.seeds';
  static const int seedMemory = 50;

  /// The unfinished board of a mode (`levels` or `endless`).
  static String attemptKey(String mode) => 'un.attempt.$mode';

  /// Brings an older save up to [schema]. Run once at start, before loading.
  ///
  /// v2 → v3: the arrow rule changed every level, so level progress starts
  /// over; challenge data is retired (the endless mode replaces it); coins,
  /// profile and settings are kept.
  Future<void> migrate({required int levelCacheVersion}) async {
    final from = readInt(await store.read(schemaKey));
    if (from >= schema) return;
    for (final key in const ['un.progress', 'un.player', 'un.challenge.run', 'un.attempt.levels', 'un.attempt.challenge']) {
      await store.remove(key);
    }
    final current = 'un.level.v$levelCacheVersion.';
    for (final key in await store.keys()) {
      if (key.startsWith('un.level.v') && !key.startsWith(current)) await store.remove(key);
    }
    await store.write(schemaKey, '$schema');
  }

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

  Future<LevelProgress> loadProgress() async => LevelProgress.fromJson(await _read(levelsKey) ?? const {});
  Future<void> saveProgress(LevelProgress p) => _write(levelsKey, p.toJson());

  Future<Wallet?> loadWallet() async {
    final json = await _read(walletKey);
    return json == null ? null : Wallet.fromJson(json);
  }

  Future<void> saveWallet(Wallet w) => _write(walletKey, w.toJson());

  /// The unfinished board of a mode (`levels` or `endless`).
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

  Future<EndlessRun?> loadEndlessRun() async {
    final json = await _read(endlessRunKey);
    return json == null ? null : EndlessRun.fromJson(json);
  }

  Future<void> saveEndlessRun(EndlessRun run) => _write(endlessRunKey, run.toJson());
  Future<void> clearEndlessRun() => store.remove(endlessRunKey);

  Future<EndlessStats> loadEndlessStats() async => EndlessStats.fromJson(await _read(endlessStatsKey) ?? const {});
  Future<void> saveEndlessStats(EndlessStats stats) => _write(endlessStatsKey, stats.toJson());

  Future<List<int>> loadEndlessSeeds() async => [
        for (final s in readStringList((await _read(endlessSeedsKey))?['seeds']))
          if (int.tryParse(s, radix: 16) case final v?) v,
      ];

  /// Keeps the last [seedMemory] run seeds.
  Future<void> saveEndlessSeeds(List<int> seeds) {
    final keep = seeds.length > seedMemory ? seeds.sublist(seeds.length - seedMemory) : seeds;
    return _write(endlessSeedsKey, {
      'seeds': [for (final s in keep) EndlessRun.seedText(s)],
    });
  }
}
