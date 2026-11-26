import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/boosters/booster_system.dart';
import '../core/challenge/challenge_system.dart';
import '../core/economy/economy_rules.dart';
import '../core/generator/difficulty_curve.dart';
import '../core/levels/level_catalog.dart';
import '../core/rules/rule_book.dart';
import '../core/util/json_read.dart';
import 'audio_service.dart';
import 'compute_scheduler.dart';
import 'localization_service.dart';
import 'monetization.dart';
import 'player_service.dart';
import 'save_system.dart';
import 'storage.dart';
import 'theme_service.dart';

/// Values from `assets/config/app_config.json`.
class AppConfig {
  const AppConfig(this._json);

  final Map<String, Object?> _json;

  String get version => readString(_json['appVersion'], '1.0.0');
  String get supportUrl => readString(_json['supportUrl']);
  String get privacyUrl => readString(_json['privacyUrl']);
  int get adSeconds => readInt(readMap(_json['ads'])['mockSeconds'], 3);
  int get purchaseDelayMs => readInt(readMap(_json['purchases'])['mockDelayMs'], 900);
  int get openAhead => readInt(readMap(_json['progression'])['openAhead']);
  double get mapSpacing => readDouble(readMap(_json['progression'])['mapSpacing'], 118);
}

/// Every service the game uses, created once at start-up from the asset
/// files. Widgets reach it through [Services.of].
class AppServices {
  AppServices._({
    required this.config,
    required this.rules,
    required this.economy,
    required this.boosters,
    required this.baseCapacity,
    required this.hintBudget,
    required this.rescueBudget,
    required this.i18n,
    required this.theme,
    required this.design,
    required this.save,
    required this.player,
    required this.audio,
    required this.haptics,
    required this.ads,
    required this.purchases,
    required this.levels,
    required this.challenges,
    required this.compute,
  });

  static Future<AppServices> bootstrap({
    AssetBundle? bundle,
    KeyValueStore? store,
    Locale? deviceLocale,
    Brightness? platform,
    bool audio = true,
  }) async {
    final b = bundle ?? rootBundle;
    Future<Map<String, Object?>> json(String path) async => readMap(jsonDecode(await b.loadString(path)));

    final config = AppConfig(await json('assets/config/app_config.json'));
    final economyJson = await json('assets/config/economy.json');
    final economy = EconomyRules.fromJson(economyJson);
    final solver = readMap(economyJson['solver']);
    final rules = RuleBook.fromJson(await json('assets/config/rules.json'));
    final save = SaveSystem(store ?? await PrefsStore.open());
    final player = await PlayerService.load(save, economy);
    final settings = player.settings;
    final i18n = await LocalizationService.load(bundle: b, preferred: settings.language, device: deviceLocale);
    final theme = await ThemeService.load(bundle: b, selection: settings.theme, platform: platform);
    final design = await DesignTokens.load(b);
    final audioService = AudioService(music: settings.music, sfx: settings.sfx, enabled: audio);
    await audioService.init();
    final levelIndex = LevelIndex.fromJson(await json('assets/levels/index.json'));
    final challengeCurve = DifficultyCurve.fromJson(await json('assets/config/challenge_curve.json'), bandsKey: 'tiers');
    return AppServices._(
      config: config,
      rules: rules,
      economy: economy,
      boosters: BoosterRules.fromJson(readMap(economyJson['boosters'])),
      baseCapacity: readInt(economyJson['baseCapacity'], 5),
      hintBudget: readInt(solver['hintBudget'], 300000),
      rescueBudget: readInt(solver['rescueBudget'], 220000),
      i18n: i18n,
      theme: theme,
      design: design,
      save: save,
      player: player,
      audio: audioService,
      haptics: HapticsService(enabled: settings.vibration),
      ads: MockRewardedAds(seconds: config.adSeconds),
      purchases: MockPurchases.fromJson(await json('assets/config/store.json'), delay: Duration(milliseconds: config.purchaseDelayMs)),
      levels: LevelCatalog(levelIndex, (file) => b.loadString('assets/levels/$file')),
      challenges: ChallengeDirector(curve: challengeCurve, rules: rules.current),
      compute: ComputeScheduler(slice: Duration(milliseconds: readInt(solver['sliceMs'], 7))),
    );
  }

  final AppConfig config;
  final RuleBook rules;
  final EconomyRules economy;
  final BoosterRules boosters;
  final int baseCapacity;
  final int hintBudget;
  final int rescueBudget;
  final LocalizationService i18n;
  final ThemeService theme;
  final DesignTokens design;
  final SaveSystem save;
  final PlayerService player;
  final AudioService audio;
  final HapticsService haptics;
  final RewardedAdsService ads;
  final PurchaseService purchases;
  final LevelCatalog levels;
  final ChallengeDirector challenges;
  final ComputeScheduler compute;

  bool get reducedEffects => player.settings.reducedEffects;

  Duration motion(String key) => design.motion(key, reduced: reducedEffects);
}

/// Gives widgets the services; widgets that read it rebuild when the theme
/// or the language changes.
class Services extends InheritedNotifier<Listenable> {
  Services({super.key, required this.services, required super.child})
      : super(notifier: Listenable.merge([services.theme, services.i18n]));

  final AppServices services;

  static AppServices of(BuildContext context, {bool listen = true}) {
    final w = listen
        ? context.dependOnInheritedWidgetOfExactType<Services>()
        : context.getInheritedWidgetOfExactType<Services>();
    return w!.services;
  }
}
