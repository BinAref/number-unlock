import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/core/board/board_topology.dart';
import 'package:unlock_numbers/core/engine/game_engine.dart';
import 'package:unlock_numbers/core/generator/generation_params.dart';
import 'package:unlock_numbers/core/generator/level_generator.dart';
import 'package:unlock_numbers/core/generator/unlock_structure.dart';
import 'package:unlock_numbers/core/model/arrows.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/model/puzzle_layout.dart';
import 'package:unlock_numbers/core/model/tile_spec.dart';
import 'package:unlock_numbers/core/random/seeded_random.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/core/rules/rule_engine.dart';

final RuleBook book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);
RuleEngine rules() => RuleEngine.forPuzzle(book.current, mode: 'levels');

/// The teaching stages, in the order players meet them.
const Map<String, ArrowParams> stages = {
  'single': ArrowParams(maxArrows: 1, twoRatio: 0, starRatio: 0, decoyRatio: 0, branchiness: 0.3),
  'double': ArrowParams(maxArrows: 2, twoRatio: 0.5, starRatio: 0, decoyRatio: 0.3, branchiness: 0.5),
  'stars': ArrowParams(maxArrows: 2, twoRatio: 0.4, starRatio: 0.6, decoyRatio: 0.3, branchiness: 0.5),
  'mixed': ArrowParams(),
  'scatter': ArrowParams(open: 'scatter'),
};

PuzzleLayout layoutOf(UnlockStructure s, int rows, int cols) => PuzzleLayout(
      rows: rows,
      cols: cols,
      cells: List<TileSpec?>.generate(rows * cols, (_) => const TileSpec(1, 0)),
      dirs: s.dirs,
      open: s.open,
      hasArrows: s.hasArrows,
    );

void main() {
  group('arrow geometry', () {
    test('targets and directions on a 3 × 4 board', () {
      expect(Arrows.target(5, Arrows.up, 3, 4), 1);
      expect(Arrows.target(5, Arrows.down, 3, 4), 9);
      expect(Arrows.target(4, Arrows.left, 3, 4), -1);
      expect(Arrows.target(7, Arrows.right, 3, 4), -1);
      expect(Arrows.target(1, Arrows.up, 3, 4), -1);
      expect(Arrows.between(5, 6, 4), Arrows.right);
      expect(Arrows.between(4, 3, 4), Arrows.none, reason: 'cell 3 ends the row above');
      expect(Arrows.count(Arrows.up | Arrows.left), 2);
    });

    test('an arrow never jumps over a void', () {
      // One column: a 3 at the top, a void, a 7 at the bottom pointing up.
      final layout = PuzzleLayout.decode(3, 1, '3a..7a', dirs: '0.1', open: '0.1');
      final topology = BoardTopology.of(layout);
      expect(topology.targets[2], isEmpty);
      expect(topology.allTilesReachable(), isFalse);
    });

    test('a tile targeted by two others opens with the first of them', () {
      // Row: 4 → 9 ← 6, the outer two open from the start.
      final g = GameEngine(
        puzzle: PuzzleDefinition(
          id: 't',
          mode: PuzzleMode.levels,
          layout: PuzzleLayout.decode(1, 3, '4a9b6c', dirs: '208', open: '101'),
          rulesetVersion: 1,
        ),
        rules: rules(),
      );
      expect(g.isOpen(1), isFalse);
      expect(g.extract(2).unlocked, [1]);
      expect(g.extract(0).unlocked, isEmpty);
    });
  });

  group('saving', () {
    test('arrows and opening tiles survive JSON', () {
      final layout = PuzzleLayout.decode(2, 2, '7c7f3a3e', dirs: '0021', open: '0011');
      final def = PuzzleDefinition(id: 'x', mode: PuzzleMode.levels, layout: layout, rulesetVersion: 1);
      final back = PuzzleDefinition.fromJson(jsonDecode(jsonEncode(def.toJson())) as Map<String, Object?>);
      expect(back.layout, layout);
      expect(back.layout.dirs, [0, 0, 2, 1]);
      expect(back.layout.openAtStart, [false, false, true, true]);
      expect(back.layout.hasArrows, isTrue);
    });

    test('matching-only boards stay fully open after saving', () {
      final layout = PuzzleLayout.decode(2, 2, '7c7f3a3e');
      final def = PuzzleDefinition(id: 'x', mode: PuzzleMode.levels, layout: layout, rulesetVersion: 1);
      final back = PuzzleDefinition.fromJson(jsonDecode(jsonEncode(def.toJson())) as Map<String, Object?>);
      expect(back.layout.hasArrows, isFalse);
      expect(back.layout.openAtStart, everyElement(isTrue));
    });

    test('puzzles saved before the arrow rule are rejected, not replayed', () {
      expect(
        () => PuzzleDefinition.fromJson(const {'id': 'old', 'mode': 'levels', 'rows': 2, 'cols': 2, 'cells': '7c7f3a3e', 'rules': 1}),
        throwsFormatException,
      );
    });
  });

  group('generated arrows', () {
    const builder = UnlockStructureBuilder();

    UnlockStructure build(ArrowParams a, int seed, {int rows = 5, int cols = 5, int entrances = 2}) =>
        builder.build(List<bool>.filled(rows * cols, true), rows, cols, a, entrances, SeededRandom(seed))!;

    test('every tile can be reached through arrows, in every stage', () {
      for (final entry in stages.entries) {
        for (var seed = 1; seed <= 40; seed++) {
          final s = build(entry.value, seed);
          expect(BoardTopology.of(layoutOf(s, 5, 5)).allTilesReachable(), isTrue, reason: '${entry.key} seed $seed');
        }
      }
    });

    test('single-arrow stage: every tile shows exactly one arrow, no stars', () {
      for (var seed = 1; seed <= 40; seed++) {
        final s = build(stages['single']!, seed);
        expect([for (final d in s.dirs) Arrows.count(d)], everyElement(1), reason: 'seed $seed');
      }
    });

    test('two-arrow stage: one or two arrows per tile, some with two, no stars', () {
      var doubles = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final s = build(stages['double']!, seed);
        for (final d in s.dirs) {
          expect(Arrows.count(d), inInclusiveRange(1, 2), reason: 'seed $seed');
          if (Arrows.count(d) == 2) doubles++;
        }
      }
      expect(doubles, greaterThan(40));
    });

    test('star stage: stars appear, and no tile ever has more than two arrows', () {
      var stars = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final s = build(stages['stars']!, seed);
        for (final d in s.dirs) {
          expect(Arrows.count(d), lessThanOrEqualTo(2));
          if (d == Arrows.none) stars++;
        }
      }
      expect(stars, greaterThan(40));
    });

    test('decoys never open a second way in', () {
      // Every arrow points at a tile it really opens (a child), or where it
      // can never open anything: its own opener, a tile open from the
      // start, a void or off the board. Open tiles boxed in by locked ones
      // (a scatter entrance up the board) are checked by the solver tests.
      var rescued = 0;
      for (final entry in stages.entries) {
        for (var seed = 1; seed <= 40; seed++) {
          final s = build(entry.value, seed, rows: 6, cols: 5);
          for (var c = 0; c < 30; c++) {
            final noHarmlessWay = s.open[c] &&
                Arrows.each.every((d) {
                  final j = Arrows.target(c, d, 6, 5);
                  return j >= 0 && !s.open[j];
                });
            if (noHarmlessWay) {
              if (entry.key != 'scatter') rescued++;
              continue;
            }
            for (final d in Arrows.each) {
              if (!Arrows.has(s.dirs[c], d)) continue;
              final j = Arrows.target(c, d, 6, 5);
              final child = j >= 0 && s.parent[j] == c;
              final harmless = j < 0 || s.open[j] || j == s.parent[c];
              expect(child || harmless, isTrue, reason: '${entry.key} seed $seed cell $c');
            }
          }
          for (var c = 0; c < 30; c++) {
            expect(s.open[c] || s.parent[c] >= 0, isTrue, reason: 'every locked tile has its opener');
          }
        }
      }
      expect(rescued, 0, reason: 'forced forks reach every tile: nothing is rescued');
    });

    test('forced forks keep every tile reachable from the entrances alone', () {
      for (final entry in stages.entries) {
        if (entry.key == 'scatter') continue;
        for (var seed = 1; seed <= 40; seed++) {
          final s = build(entry.value, seed, rows: 6, cols: 5);
          expect(s.open.where((o) => o).length, 2, reason: '${entry.key} seed $seed opens only its two entrances');
        }
      }
    });

    test('the same seed lays the same arrows; another seed differs', () {
      final a = build(const ArrowParams(), 7);
      final b = build(const ArrowParams(), 7);
      final c = build(const ArrowParams(), 8);
      expect(a.dirs, b.dirs);
      expect(a.open, b.open);
      expect(a.dirs == c.dirs && a.open == c.open, isFalse);
    });

    test('matching-only boards: every tile open, no arrows', () {
      final s = build(ArrowParams.none, 3);
      expect(s.hasArrows, isFalse);
      expect(s.open, everyElement(isTrue));
      expect(s.dirs, everyElement(Arrows.none));
    });
  });

  group('generator', () {
    test('boards are solvable along their witness in every stage', () {
      final gen = LevelGenerator(rules());
      var built = 0;
      for (final entry in stages.entries) {
        for (var seed = 1; seed <= 6; seed++) {
          final p = GenerationParams(rows: 4, cols: 4, targetDepth: 2, arrows: entry.value);
          final c = gen.buildCandidate(p, SeededRandom(seed));
          if (c == null) continue;
          built++;
          expect(c.layout.hasArrows, isTrue);
          expect(BoardTopology.of(c.layout).allTilesReachable(), isTrue);
          final g = GameEngine(puzzle: PuzzleDefinition(id: 't', mode: PuzzleMode.levels, layout: c.layout, rulesetVersion: 1), rules: rules());
          for (final cell in c.witness) {
            expect(g.extract(cell).accepted, isTrue, reason: '${entry.key} seed $seed');
          }
          expect(g.status, GameStatus.won, reason: '${entry.key} seed $seed');
        }
      }
      expect(built, greaterThan(20));
    });

    test('corridor and holed boards keep every tile within two arrows and reachable', () {
      final gen = LevelGenerator(rules());
      var built = 0;
      for (var seed = 1; seed <= 8; seed++) {
        for (final p in const [
          GenerationParams(rows: 6, cols: 6, targetDepth: 3, shape: 'corridors', fill: 0.6),
          GenerationParams(rows: 6, cols: 6, targetDepth: 3, holes: 0.3, entrances: 3),
        ]) {
          final c = gen.buildCandidate(p, SeededRandom(seed));
          if (c == null) continue;
          built++;
          for (final t in c.layout.tileIndices) {
            expect(Arrows.count(c.layout.dirs[t]), lessThanOrEqualTo(2));
          }
          expect(BoardTopology.of(c.layout).allTilesReachable(), isTrue);
        }
      }
      expect(built, greaterThan(6));
    });

    test('hardening moves numbers, never arrows', () {
      final gen = LevelGenerator(rules());
      const p = GenerationParams(rows: 4, cols: 4, targetDepth: 3, hardenSteps: 60);
      Candidate? start;
      for (var seed = 11; start == null && seed < 60; seed++) {
        start = gen.buildCandidate(p, SeededRandom(seed));
      }
      expect(start, isNotNull);
      final hard = gen.harden(start!, p, SeededRandom(12));
      expect(hard.layout.encodeDirs(), start.layout.encodeDirs());
      expect(hard.layout.encodeOpen(), start.layout.encodeOpen());
    });
  });
}
