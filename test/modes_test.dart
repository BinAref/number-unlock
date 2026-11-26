import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/core/economy/economy_rules.dart';
import 'package:unlock_numbers/core/endless/endless_director.dart';
import 'package:unlock_numbers/core/endless/endless_run.dart';
import 'package:unlock_numbers/core/endless/endless_stats.dart';
import 'package:unlock_numbers/core/engine/game_engine.dart';
import 'package:unlock_numbers/core/generator/difficulty_curve.dart';
import 'package:unlock_numbers/core/jobs/compute_job.dart';
import 'package:unlock_numbers/core/levels/level_progress.dart';
import 'package:unlock_numbers/core/levels/star_rules.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/random/seeded_random.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/services/compute_scheduler.dart';
import 'package:unlock_numbers/services/endless_service.dart';
import 'package:unlock_numbers/services/player_service.dart';
import 'package:unlock_numbers/services/save_system.dart';
import 'package:unlock_numbers/services/storage.dart';

final RuleBook book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);
final DifficultyCurve endlessCurve = DifficultyCurve.fromJson(
  jsonDecode(File('assets/config/endless_curve.json').readAsStringSync()) as Map<String, Object?>,
  bandsKey: 'boards',
);

void main() {
  group('level stars', () {
    const rules = StarRules();

    test('stars come from the help a win took: none 3, one 2, more 1, loss 0', () {
      expect(rules.starsFor(won: true, helps: 0), 3);
      expect(rules.starsFor(won: true, helps: 1), 2);
      expect(rules.starsFor(won: true, helps: 2), 1);
      expect(rules.starsFor(won: true, helps: 7), 1);
      expect(rules.starsFor(won: false, helps: 0), 0);
    });

    test('every hint, the sixth slot and a swap each count as one help', () {
      expect(BoosterUsage(extraSlot: true, swapUsed: true, adHints: 1, coinHints: 2).helps, 5);
      expect(BoosterUsage().helps, 0);
    });

    test('the best stars of a level are kept; a worse replay never lowers them', () {
      final p = LevelProgress();
      p.recordWin(4, 2, total: 100);
      p.recordWin(4, 1, total: 100);
      expect(p.starsOf(4), 2);
      p.recordWin(4, 3, total: 100);
      expect(p.starsOf(4), 3);
      expect(p.highestUnlocked, 5);
    });

    test('profile stats: completed, three-star levels and mastery', () {
      final p = LevelProgress(stars: {1: 3, 2: 2, 3: 1}, highestUnlocked: 4);
      expect(p.completedCount, 3);
      expect(p.totalStars, 6);
      expect(p.threeStarCount, 1);
      expect(p.mastery, closeTo(6 / 9, 1e-9));
      expect(LevelProgress().mastery, 0);
    });
  });

  group('endless records', () {
    test('the record is the best single run; the first run sets it quietly; a tie is no record', () {
      final s = EndlessStats();
      expect(s.record(score: 500, boards: 3).newRecord, isFalse);
      expect(s.best, 500);
      expect(s.record(score: 300, boards: 5).newRecord, isFalse);
      expect(s.best, 500);
      expect(s.bestBoards, 5);
      expect(s.last, 300);
      expect(s.record(score: 500, boards: 2).newRecord, isFalse);
      final better = s.record(score: 900, boards: 6);
      expect(better.newRecord, isTrue);
      expect(better.previousBest, 500);
      expect(s.best, 900);
      expect(s.runs, 4);
    });

    test('a run lost on its first board still counts', () {
      final s = EndlessStats();
      s.record(score: 0, boards: 0);
      expect(s.runs, 1);
      expect(s.record(score: 120, boards: 1).newRecord, isTrue);
    });

    test('points add up across boards and are never reset within a run', () {
      final run = EndlessRun(seed: 1);
      run.clearBoard(120, 1);
      run.clearBoard(140, 2);
      expect(run.score, 260);
      expect(run.board, 3);
      expect(run.boardsCleared, 2);
    });

    test('a run survives saving', () {
      final run = EndlessRun(seed: 0x9f2c41d0, board: 7, score: 2310, hintsUsed: 1, recent: [11, 22]);
      final back = EndlessRun.fromJson(jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>);
      expect(back.seed, 0x9f2c41d0);
      expect(back.board, 7);
      expect(back.score, 2310);
      expect(back.hintsUsed, 1);
      expect(back.recent, [11, 22]);
    });
  });

  group('endless boards', () {
    final director = EndlessDirector(curve: endlessCurve, rules: book.current);

    test("a run's boards follow from its seed; another run gets other boards", () {
      final run = EndlessRun(seed: 1234);
      final a = runToCompletion(director.boardJob(run, 1), slice: 8)!;
      final b = runToCompletion(director.boardJob(run, 1), slice: 8)!;
      final other = runToCompletion(director.boardJob(EndlessRun(seed: 98765), 1), slice: 8)!;
      expect(a.layout, b.layout);
      expect(a.layout == other.layout, isFalse);
      expect(a.mode, PuzzleMode.endless);
      expect(a.boardNumber, 1);
    });

    test('every board is verified solvable along its solution', () {
      final run = EndlessRun(seed: 777);
      for (final board in [1, 3, 6, 10]) {
        final p = runToCompletion(director.boardJob(run, board), slice: 8)!;
        final g = GameEngine(puzzle: p, rules: director.engineFor(board));
        for (final c in p.solution!) {
          expect(g.extract(c).accepted, isTrue, reason: 'board $board');
        }
        expect(g.status, GameStatus.won, reason: 'board $board');
      }
    });

    test('difficulty climbs with the board, without vault jumps, and the last band holds', () {
      final rng = SeededRandom(5);
      int cells(int board) {
        final p = endlessCurve.paramsFor(board, rng);
        return p.rows * p.cols;
      }

      expect(cells(1), lessThanOrEqualTo(12));
      expect(cells(30), greaterThan(cells(5)));
      expect(endlessCurve.paramsFor(1, rng).arrows.maxArrows, 1);
      expect(endlessCurve.paramsFor(500, rng).rows, 8);
      expect(endlessCurve.isVault(10), isFalse);
    });

    test('a fresh run never reuses a recent seed', () {
      var n = 0;
      const draws = [5, 5, 6, 7];
      expect(EndlessDirector.freshSeed(() => draws[n++], [5]), 6);
    });

    test('later boards are worth more', () {
      expect(EndlessDirector.basePoints(1), 100);
      expect(EndlessDirector.basePoints(6), greaterThan(EndlessDirector.basePoints(5)));
    });
  });

  group('endless service', () {
    EndlessService serviceFor(SaveSystem save, List<int> draws) {
      var n = 0;
      return EndlessService(
        director: EndlessDirector(curve: endlessCurve, rules: book.current),
        compute: ComputeScheduler(slice: const Duration(milliseconds: 8)),
        save: save,
        ahead: 3,
        entropy: () => draws[math.min(n++, draws.length - 1)],
      );
    }

    test('a run: prepared boards, banked points, a coin every 3 boards, then the record', () async {
      final save = SaveSystem(MemoryStore());
      final player = await PlayerService.load(save, const EconomyRules());
      final service = serviceFor(save, [4242]);
      final run = await service.startRun();
      expect(run.board, 1);
      final first = (await service.board(1))!;
      expect(first.boardNumber, 1);
      await service.clearBoard(first, 120, player);
      expect(service.run!.score, 120);
      expect(service.run!.board, 2);
      final second = (await service.board(2))!;
      expect(second.layout == first.layout, isFalse);
      await service.clearBoard(second, 150, player);
      await service.clearBoard((await service.board(3))!, 170, player);
      expect(player.coins, const EconomyRules().startingCoins + 1);

      // A new service over the same save resumes the run where it was.
      final resumed = await serviceFor(save, [1]).load();
      expect(resumed!.board, 4);
      expect(resumed.score, 440);

      final summary = await service.finishRun(player);
      expect(summary.score, 440);
      expect(summary.boards, 3);
      expect(player.endless.best, 440);
      expect(service.run, isNull);
      expect(await save.loadEndlessRun(), isNull);
    });

    test('a new run never reuses the last seed', () async {
      final save = SaveSystem(MemoryStore());
      final first = await serviceFor(save, [4242]).startRun();
      final second = await serviceFor(save, [4242, 777]).startRun();
      expect(first.seed, 4242);
      expect(second.seed, 777);
    });
  });

  group('saving (schema v3)', () {
    test('an older save keeps coins, profile and settings; retired data goes', () async {
      final store = MemoryStore()
        ..data['un.wallet'] = '{"coins":12}'
        ..data['un.profile'] = '{"name":"Aref","avatar":2}'
        ..data['un.settings'] = '{"theme":"night"}'
        ..data['un.progress'] = '{"highest":40,"stars":{"1":3}}'
        ..data['un.player'] = '{"xp":640}'
        ..data['un.challenge.run'] = '{"tier":4}'
        ..data['un.attempt.challenge'] = '{}'
        ..data['un.level.v2.12'] = '{}'
        ..data['un.level.v3.12'] = '{}';
      final save = SaveSystem(store);
      await save.migrate(levelCacheVersion: 3);
      expect(store.data.keys, containsAll(<String>['un.wallet', 'un.profile', 'un.settings', 'un.level.v3.12', 'un.schema']));
      for (final gone in ['un.progress', 'un.player', 'un.challenge.run', 'un.attempt.challenge', 'un.level.v2.12']) {
        expect(store.data.containsKey(gone), isFalse, reason: gone);
      }
      expect((await save.loadProgress()).highestUnlocked, 1);
    });

    test('migrating again changes nothing', () async {
      final save = SaveSystem(MemoryStore());
      await save.migrate(levelCacheVersion: 3);
      await save.saveProgress(LevelProgress(stars: {1: 2}, highestUnlocked: 2));
      await save.migrate(levelCacheVersion: 3);
      expect((await save.loadProgress()).starsOf(1), 2);
    });

    test('endless runs, records and recent seeds are stored apart', () async {
      final save = SaveSystem(MemoryStore());
      await save.saveEndlessRun(EndlessRun(seed: 42, board: 3, score: 250));
      await save.saveEndlessStats(EndlessStats(best: 900, runs: 4));
      await save.saveEndlessSeeds([for (var i = 0; i < 60; i++) i]);
      expect((await save.loadEndlessRun())!.board, 3);
      expect((await save.loadEndlessStats()).best, 900);
      final seeds = await save.loadEndlessSeeds();
      expect(seeds.length, SaveSystem.seedMemory);
      expect(seeds.last, 59);
    });
  });
}
