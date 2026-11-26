import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/core/board/board_topology.dart';
import 'package:unlock_numbers/core/engine/game_engine.dart';
import 'package:unlock_numbers/core/generator/difficulty_curve.dart';
import 'package:unlock_numbers/core/generator/level_forge.dart';
import 'package:unlock_numbers/core/levels/level_catalog.dart';
import 'package:unlock_numbers/core/model/arrows.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/random/seeded_random.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/core/rules/rule_engine.dart';

void main() {
  final book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);
  final curve = DifficultyCurve.fromJson(jsonDecode(File('assets/config/level_curve.json').readAsStringSync()) as Map<String, Object?>);

  void expectSolvable(PuzzleDefinition p) {
    expect(p.layout.tileCount.isEven, isTrue);
    expect(BoardTopology.of(p.layout).allTilesReachable(), isTrue);
    final g = GameEngine(puzzle: p, rules: RuleEngine.forPuzzle(book.byVersion(p.rulesetVersion), mode: 'levels', level: p.levelNumber));
    for (final c in p.solution!) {
      expect(g.extract(c).accepted, isTrue, reason: 'level ${p.levelNumber}');
    }
    expect(g.status, GameStatus.won, reason: 'level ${p.levelNumber} must be solvable with five slots and no boosters');
  }

  test('the bundled first levels are solvable without boosters', () async {
    final index = LevelIndex.fromJson(jsonDecode(File('assets/levels/index.json').readAsStringSync()) as Map<String, Object?>);
    final catalog = LevelCatalog(index, (f) async => File('assets/levels/$f').readAsStringSync());
    for (var l = 1; l <= index.total; l++) {
      expectSolvable(await catalog.level(l));
    }
  });

  test('a level is the same puzzle every time (and everywhere) it is forged', () {
    final forge = LevelForge(curve: curve, book: book);
    final a = forge.forge(14);
    final b = forge.forge(14);
    expect(a.layout, b.layout);
    expect(a.solution, b.solution);
    expect(forge.forge(15).layout == a.layout, isFalse);
    expectSolvable(a);
  });

  test('platform-identical maths', () {
    expect((detExpNeg(1) - 0.36787944117144233).abs(), lessThan(1e-12));
    expect((detLog10(1000) - 3).abs(), lessThan(1e-12));
  });

  test('the endless curve climbs to 10 × 10 arrow boards that need every slot', () {
    final p = curve.paramsFor(5000, SeededRandom(1));
    expect(p.rows, 10);
    expect(p.cols, 10);
    expect(p.targetCapacity, 5);
    expect(p.floorDepth, 3);
    expect(p.arrows.enabled, isTrue);
    expect(p.arrows.starRatio, greaterThan(0));
  });

  test('arrows are taught in stages: matching only, single, two-arrow, stars', () {
    final forge = LevelForge(curve: curve, book: book);
    for (final l in [1, 2, 3]) {
      final layout = forge.forge(l).layout;
      expect(layout.hasArrows, isFalse, reason: 'level $l is matching only');
      expect(layout.openAtStart.where((o) => o).length, layout.tileCount);
    }
    final single = forge.forge(6).layout;
    expect([for (final t in single.tileIndices) Arrows.count(single.dirs[t])], everyElement(1));
    final twoArrow = forge.forge(15).layout;
    expect(twoArrow.tileIndices.any(twoArrow.isStar), isFalse);
    expect(twoArrow.tileIndices.any((t) => Arrows.count(twoArrow.dirs[t]) == 2), isTrue);
    expect(curve.paramsFor(25, SeededRandom(1)).arrows.starRatio, greaterThan(0));
  });
}
