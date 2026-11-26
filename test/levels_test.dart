import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/core/board/board_topology.dart';
import 'package:unlock_numbers/core/engine/game_engine.dart';
import 'package:unlock_numbers/core/levels/level_catalog.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/core/rules/rule_engine.dart';
import 'package:unlock_numbers/core/solver/puzzle_solver.dart';
import 'package:unlock_numbers/core/solver/solver_context.dart';

Future<List<PuzzleDefinition>> loadAll() async {
  final index = LevelIndex.fromJson(jsonDecode(File('assets/levels/index.json').readAsStringSync()) as Map<String, Object?>);
  final catalog = LevelCatalog(index, (f) async => File('assets/levels/$f').readAsStringSync());
  return [for (var l = 1; l <= index.total; l++) await catalog.level(l)];
}

void main() {
  final book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);

  test('there are at least 1000 fixed levels, numbered in order, all different', () async {
    final levels = await loadAll();
    expect(levels.length, greaterThanOrEqualTo(1000));
    expect([for (final l in levels) l.levelNumber], [for (var i = 1; i <= levels.length; i++) i]);
    expect({for (final l in levels) '${l.layout.rows}x${l.layout.cols}:${l.layout.encodeCells()}'}.length, levels.length);
  });

  test('every level is solvable with five slots and no boosters', () async {
    for (final p in await loadAll()) {
      expect(p.layout.tileCount.isEven, isTrue, reason: 'level ${p.levelNumber} tile count');
      expect(BoardTopology.of(p.layout).allTilesReachable(), isTrue, reason: 'level ${p.levelNumber} reachability');
      final g = GameEngine(puzzle: p, rules: RuleEngine.forPuzzle(book.byVersion(p.rulesetVersion), mode: 'levels', level: p.levelNumber));
      for (final c in p.solution!) {
        expect(g.extract(c).accepted, isTrue, reason: 'level ${p.levelNumber}');
      }
      expect(g.status, GameStatus.won, reason: 'level ${p.levelNumber}');
      expect(g.peakRest + 1, p.profile!.minCapacity, reason: 'level ${p.levelNumber} witness uses the stated slots');
    }
  });

  test('stated slot needs re-prove on a sample', () async {
    final levels = await loadAll();
    for (var i = 0; i < levels.length; i += 47) {
      final p = levels[i];
      final ctx = SolverContext(p.layout, RuleEngine.forPuzzle(book.byVersion(p.rulesetVersion), mode: 'levels', level: p.levelNumber));
      final r = PuzzleSolver(ctx).minCapacity(knownPath: p.solution, budgets: const {2: 200000, 3: 1500000, 4: 6000000});
      if (p.profile!.minCapacityProven) expect(r.capacity, p.profile!.minCapacity, reason: 'level ${p.levelNumber}');
    }
  });

  test('difficulty rises across the journey', () async {
    final levels = await loadAll();
    double avg(Iterable<PuzzleDefinition> xs) => xs.map((p) => p.profile!.score).reduce((a, b) => a + b) / xs.length;
    expect(avg(levels.take(100)), lessThan(avg(levels.skip(450).take(100))));
    expect(avg(levels.skip(450).take(100)), lessThan(avg(levels.skip(900))));
    expect(levels.where((p) => p.profile!.minCapacity == 5 && p.profile!.minCapacityProven).length, greaterThan(20));
  });
}
