// Visual review: renders every page on a phone-sized screen with the real
// fonts, in both themes and both directions, into test_visual/shots/.
// Run: flutter test test_visual --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/app.dart';
import 'package:unlock_numbers/features/challenge/challenge_screen.dart';
import 'package:unlock_numbers/features/game/game_screen.dart';
import 'package:unlock_numbers/features/guide/guide_screen.dart';
import 'package:unlock_numbers/features/levels/levels_map_screen.dart';
import 'package:unlock_numbers/features/settings/settings_screen.dart';
import 'package:unlock_numbers/features/shop/shop_screen.dart';
import 'package:unlock_numbers/services/app_services.dart';
import 'package:unlock_numbers/services/storage.dart';

Future<void> _fonts() async {
  const families = {
    'Cairo': ['Cairo-500', 'Cairo-600', 'Cairo-700'],
    'NunitoSans': ['NunitoSans-600', 'NunitoSans-700'],
    'CinzelDecorative': ['CinzelDecorative-Bold', 'CinzelDecorative-Black'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(Future.value(ByteData.view(File('assets/fonts/$f.ttf').readAsBytesSync().buffer)));
    }
    await loader.load();
  }
}

void main() {
  testWidgets('render pages', (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> shot(String name, {required String lang, required String theme, Widget? home, int highest = 37}) async {
      final store = MemoryStore()
        ..data['un.settings'] = '{"language":"$lang","theme":"$theme"}'
        ..data['un.progress'] = '{"stars":{${List.generate(highest - 1, (i) => '"${i + 1}":${1 + i % 3}').join(',')}},"highest":$highest}'
        ..data['un.player'] = '{"xp":640}'
        ..data['un.profile'] = '{"name":"Aref","avatar":2}';
      final s = (await tester.runAsync(() => AppServices.bootstrap(store: store, audio: false)))!;
      await tester.pumpWidget(UnlockNumbersApp(services: s, home: home));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
      await tester.pumpWidget(const SizedBox());
    }

    final probe = (await tester.runAsync(() => AppServices.bootstrap(store: MemoryStore(), audio: false)))!;
    final mid = (await tester.runAsync(() => probe.levels.level(120)))!;
    final late = (await tester.runAsync(() => probe.levels.level(990)))!;

    await shot('home_day_en', lang: 'en', theme: 'day');
    await shot('home_night_ar', lang: 'ar', theme: 'night');
    await shot('game_day_en', lang: 'en', theme: 'day', home: GameScreen(puzzle: mid));
    await shot('game_night_ar', lang: 'ar', theme: 'night', home: GameScreen(puzzle: late));
    await shot('map_day_en', lang: 'en', theme: 'day', home: const LevelsMapScreen());
    await shot('settings_night_tr', lang: 'tr', theme: 'night', home: const SettingsScreen());
    await shot('shop_day_ar', lang: 'ar', theme: 'day', home: const ShopScreen());
    await shot('guide_night_en', lang: 'en', theme: 'night', home: const GuideScreen());
    await shot('challenge_day_ar', lang: 'ar', theme: 'day', home: const ChallengeScreen());
  });
}
