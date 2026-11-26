import 'dart:async';
import 'dart:math' as math;

import '../core/endless/endless_director.dart';
import '../core/endless/endless_run.dart';
import '../core/endless/endless_stats.dart';
import '../core/model/puzzle_definition.dart';
import 'compute_scheduler.dart';
import 'player_service.dart';
import 'save_system.dart';

/// The endless mode's runs: the run in progress, its boards — prepared in the
/// background [ahead] boards ahead of the player, one after another — and the
/// end of a run. Nothing infinite is ever generated in advance.
class EndlessService {
  EndlessService({required this.director, required this.compute, required this.save, this.ahead = 10, int Function()? entropy})
      : _entropy = entropy ?? _secureEntropy;

  static final math.Random _secure = math.Random.secure();
  static int _secureEntropy() => _secure.nextInt(0x100000000);

  final EndlessDirector director;
  final ComputeScheduler compute;
  final SaveSystem save;
  final int ahead;
  final int Function() _entropy;

  EndlessRun? _run;
  bool _loaded = false;
  final Map<int, Future<PuzzleDefinition?>> _boards = {};
  Future<void> _queue = Future<void>.value();

  /// The run in progress (null when none).
  EndlessRun? get run => _run;

  /// Loads the saved run, if any, and starts preparing its boards.
  Future<EndlessRun?> load() async {
    if (!_loaded) {
      _run = await save.loadEndlessRun();
      _loaded = true;
    }
    final r = _run;
    if (r != null) _prefetch(r.board);
    return r;
  }

  /// A new run: a fresh seed (never one of the recent ones), board 1 and no
  /// points. The previous run, if any, is simply replaced.
  Future<EndlessRun> startRun() async {
    final recent = await save.loadEndlessSeeds();
    final seed = EndlessDirector.freshSeed(_entropy, recent);
    final run = EndlessRun(seed: seed);
    _run = run;
    _loaded = true;
    _boards.clear();
    await save.clearAttempt(PuzzleMode.endless.key);
    await save.saveEndlessRun(run);
    await save.saveEndlessSeeds([...recent, seed]);
    _prefetch(1);
    return run;
  }

  /// Board [index] of the current run — at once when prepared ahead; null
  /// only if no verified board could be made.
  Future<PuzzleDefinition?> board(int index) {
    _prefetch(index);
    return _boards[index] ?? Future<PuzzleDefinition?>.value();
  }

  void _prefetch(int from) {
    final run = _run;
    if (run == null) return;
    _boards.removeWhere((i, _) => i < from);
    for (var i = from; i < from + ahead; i++) {
      _boards.putIfAbsent(i, () {
        final job = director.boardJob(run, i);
        final next = _queue.then((_) => compute.run(job, units: 1));
        _queue = next.then((_) {}, onError: (Object _) {});
        return next;
      });
    }
  }

  /// Banks a cleared board: its points join the run total (never reset
  /// within the run), a coin every few boards, then the next board.
  /// Returns the coins paid.
  Future<int> clearBoard(PuzzleDefinition board, int points, PlayerService player) async {
    final run = _run!;
    final number = board.boardNumber ?? run.board;
    run.clearBoard(points, board.layout.fingerprint());
    final coins = player.creditEndlessBoard(runSeed: run.seed, board: number);
    await save.clearAttempt(PuzzleMode.endless.key);
    await save.saveEndlessRun(run);
    _prefetch(run.board);
    return coins;
  }

  /// Saves run counters changed during a board (free hints, the free swap).
  Future<void> saveRun() async {
    final r = _run;
    if (r != null) await save.saveEndlessRun(r);
  }

  /// Ends the run after a lost board: the total is recorded against the
  /// player's record and the run is cleared.
  Future<RunSummary> finishRun(PlayerService player) async {
    final run = _run!;
    final summary = player.recordEndlessRun(score: run.score, boards: run.boardsCleared);
    _run = null;
    _boards.clear();
    await save.clearEndlessRun();
    await save.clearAttempt(PuzzleMode.endless.key);
    return summary;
  }
}
