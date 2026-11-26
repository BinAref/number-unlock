// Visual review of the arrow rule's marks on the real game screen: every
// single and double arrow, stars, open and locked tiles, in both themes and
// both directions, into test_visual/shots/.
// Run: flutter test test_visual/arrows_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/app.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/model/puzzle_layout.dart';
import 'package:unlock_numbers/features/game/game_screen.dart';
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
  testWidgets('arrow marks on the board', (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Row by row: ★ → ↓ ← / ↑ ↑→ →↓ ↓← / ↑← ↑↓ →← ★ / ↑ ↑ ↑→ ↑←.
    final puzzle = PuzzleDefinition(
      id: 'arrows',
      mode: PuzzleMode.levels,
      rulesetVersion: 1,
      levelNumber: 42,
      layout: PuzzleLayout.decode(4, 4, '1a9b2c8d3e7f4a6b5c5d1e9f2a8b3c7d', dirs: '0248136c95a01139', open: '0000000000000110'),
    );
    for (final (lang, theme) in const [('en', 'day'), ('ar', 'night')]) {
      final store = MemoryStore()..data['un.settings'] = '{"language":"$lang","theme":"$theme"}';
      final s = (await tester.runAsync(() => AppServices.bootstrap(store: store, audio: false)))!;
      await tester.pumpWidget(UnlockNumbersApp(services: s, home: GameScreen(puzzle: puzzle)));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/arrows_${theme}_$lang.png'));
      await tester.pumpWidget(const SizedBox());
    }
  });
}
