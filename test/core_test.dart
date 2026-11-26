import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/core/boosters/booster_system.dart';
import 'package:unlock_numbers/core/challenge/challenge_system.dart';
import 'package:unlock_numbers/core/economy/wallet.dart';
import 'package:unlock_numbers/core/engine/game_engine.dart';
import 'package:unlock_numbers/core/generator/difficulty_curve.dart';
import 'package:unlock_numbers/core/hint/hint_system.dart';
import 'package:unlock_numbers/core/jobs/compute_job.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/model/puzzle_layout.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/core/rules/rule_engine.dart';
import 'package:unlock_numbers/core/solver/puzzle_solver.dart';
import 'package:unlock_numbers/core/solver/solver_context.dart';

final RuleBook book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);
RuleEngine rules() => RuleEngine.forPuzzle(book.current, mode: 'levels');

PuzzleDefinition puzzle(int rows, int cols, String cells) =>
    PuzzleDefinition(id: 't', mode: PuzzleMode.levels, layout: PuzzleLayout.decode(rows, cols, cells), rulesetVersion: 1);

GameEngine game(int rows, int cols, String cells, {int capacity = 5}) => GameEngine(puzzle: puzzle(rows, cols, cells), rules: rules(), baseCapacity: capacity);

void main() {
  group('board and unlocking', () {
    // Rows: top 1 2 3 / middle 4 5 6 / bottom 7 8 9 (cells 0..8).
    const grid = '1a2a3a4a5a6a7a8a9a';

    test('the bottom row starts open, everything else locked', () {
      final g = game(3, 3, grid);
      expect(g.openTiles(), [6, 7, 8]);
    });

    test('locked tiles cannot be picked', () {
      final g = game(3, 3, grid);
      expect(g.extract(4).rejection, MoveRejection.locked);
      expect(g.trayItems, isEmpty);
    });

    test('extracting opens the four direct neighbours only, never diagonals', () {
      final g = game(3, 3, grid);
      expect(g.extract(7).unlocked, [4]);
      expect(g.isOpen(3), isFalse);
      expect(g.isOpen(5), isFalse);
      expect(g.extract(4).unlocked..sort(), [1, 3, 5]);
      expect(g.isOpen(0), isFalse);
    });

    test('an open tile does not open its neighbours until extracted', () {
      final g = game(3, 3, grid);
      expect(g.isOpen(3), isFalse);
      expect(g.isOpen(4), isFalse);
    });

    test('taken cells stay empty and nothing moves', () {
      final g = game(3, 3, grid);
      g.extract(7);
      expect(g.board.hasTile(7), isFalse);
      expect([for (final c in [0, 1, 2, 3, 4, 5, 6, 8]) g.board.hasTile(c)], everyElement(isTrue));
      expect(g.puzzle.layout.specOf(4).value, 5);
    });
  });

  group('matching', () {
    test('two equal numbers vanish, whatever their colours', () {
      final g = game(1, 4, '4c4d9a1b');
      g.extract(0);
      expect(g.extract(1).matches.single.rule.id, 'pair_equal');
      expect(g.trayItems, isEmpty);
    });

    test('two numbers adding up to ten vanish', () {
      final g = game(1, 4, '2a8b4c4d');
      g.extract(0);
      expect(g.extract(1).matches.single.rule.id, 'pair_sum10');
    });

    test('only neighbours match: 2 and 8 apart do not vanish', () {
      final g = game(1, 4, '2a4b8c1d');
      g.extract(0);
      g.extract(1);
      expect(g.extract(2).matches, isEmpty);
      expect(g.trayItems, [0, 1, 2]);
    });

    test('a swap can trigger chained matches; survivors keep their order', () {
      final g = game(1, 4, '3a2b7c8d');
      for (final c in [0, 1, 2, 3]) {
        g.extract(c);
      }
      expect(g.trayItems, [0, 1, 2, 3]);
      final r = g.swap(2, 3);
      expect(r.matches.length, 2);
      expect(r.matches.first.trayAfter, [0, 2]);
      expect(g.status, GameStatus.won);
      expect(g.canSwap, isFalse);
    });

    test('the three-number rule exists but is off in the first ruleset', () {
      expect(book.current.rules.any((r) => r.id == 'triple_sum10_distinct' && !r.enabled), isTrue);
      expect(rules().rules.map((r) => r.id), isNot(contains('triple_sum10_distinct')));
    });
  });

  group('winning and losing', () {
    test('win only when board and slots are both empty', () {
      final g = game(2, 2, '7c7f3a3e');
      for (final c in [2, 3, 0, 1]) {
        g.extract(c);
      }
      expect(g.status, GameStatus.won);
    });

    test('five full slots without a match lose', () {
      final g = game(1, 6, '1a2b3c4d1e5f');
      for (final c in [0, 1, 2, 3, 4]) {
        g.extract(c);
      }
      expect(g.status, GameStatus.lost);
      expect(g.lossReason, LossReason.trayFull);
      expect(g.extract(5).rejection, MoveRejection.finished);
    });

    test('an empty board with unmatched leftovers loses', () {
      final g = game(1, 2, '1a2b');
      g.extract(0);
      g.extract(1);
      expect(g.lossReason, LossReason.leftovers);
    });

    test('the sixth slot lasts for the attempt and a snapshot restores it', () {
      final g = game(1, 6, '1a2b3c4d1e5f');
      expect(g.addSlot(), isTrue);
      expect(g.addSlot(), isFalse);
      expect(g.capacity, 6);
      final again = GameEngine.resume(g.snapshot(), rules: rules());
      expect(again.capacity, 6);
      expect(again.boosters.extraSlot, isTrue);
    });
  });

  group('solver, hints and rescue', () {
    test('minimum slots are measured and proven', () {
      final ctx = SolverContext(PuzzleLayout.decode(2, 2, '7c7f3a3e'), rules());
      final r = PuzzleSolver(ctx).minCapacity();
      expect(r.capacity, 2);
      expect(r.proven, isTrue);
    });

    test('a hint is the first step of a real winning path', () {
      final layout = PuzzleLayout.decode(3, 3, '..5a5e6c1d9f3e7b4a');
      final h = runToCompletion(HintSearch(SolverContext(layout, rules()), removed: const [], tray: const [], capacity: 5));
      expect(h.status, HintStatus.found);
      final g = GameEngine(puzzle: puzzle(3, 3, '..5a5e6c1d9f3e7b4a'), rules: rules());
      for (final c in h.path) {
        expect(g.extract(c).accepted, isTrue);
      }
      expect(g.status, GameStatus.won);
    });

    test('rescue offers only boosters that truly save the position', () {
      final g = game(1, 10, '1a2b3c4d5e5f6a7b8c9d');
      for (final c in [0, 1, 2, 3, 4]) {
        g.extract(c);
      }
      expect(g.status, GameStatus.lost);
      final options = runToCompletion(RescueSearch(SolverContext(g.puzzle.layout, rules()),
          removed: g.board.removedCells, tray: g.trayItems, capacity: g.capacity, canAddSlot: true, canSwap: true));
      expect(options.map((o) => o.kind), [RescueKind.extraSlot]);
    });
  });

  group('coins', () {
    test('each operation charges or pays at most once', () {
      final w = Wallet(coins: 2);
      expect(w.spend(1, opId: 'hint:a'), SpendResult.spent);
      expect(w.spend(1, opId: 'hint:a'), SpendResult.duplicate);
      expect(w.spend(5, opId: 'slot:a'), SpendResult.insufficient);
      expect(w.credit(10, opId: 'buy:1'), isTrue);
      expect(w.credit(10, opId: 'buy:1'), isFalse);
      expect(w.coins, 11);
    });
  });

  group('challenge', () {
    final director = ChallengeDirector(
      curve: DifficultyCurve.fromJson(jsonDecode(File('assets/config/challenge_curve.json').readAsStringSync()) as Map<String, Object?>, bandsKey: 'tiers'),
      rules: book.current,
    );

    test('a seed always forges the same verified puzzle; new seeds differ', () {
      final a = runToCompletion(director.jobFor(1, 1234), slice: 4)!;
      final b = runToCompletion(director.jobFor(1, 1234), slice: 4)!;
      final c = runToCompletion(director.jobFor(1, 98765), slice: 4)!;
      expect(a.layout, b.layout);
      expect(a.layout == c.layout, isFalse);
      final g = GameEngine(puzzle: director.toPuzzle(a, tier: 1, seed: 1234), rules: director.engineFor(1));
      for (final cell in a.solution) {
        g.extract(cell);
      }
      expect(g.status, GameStatus.won);
    });
  });
}
