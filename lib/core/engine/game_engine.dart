import 'dart:math' as math;

import '../board/board_state.dart';
import '../model/puzzle_definition.dart';
import '../model/tile_spec.dart';
import '../reception/reception_tray.dart';
import '../rules/match_resolver.dart';
import '../rules/rule_engine.dart';
import '../util/json_read.dart';

enum GameStatus { playing, won, lost }

enum LossReason {
  /// Every available slot is taken and nothing matches.
  trayFull,

  /// The board is empty but unmatched tiles remain in the tray.
  leftovers,
}

enum MoveRejection { finished, notATile, alreadyTaken, locked, noFreeSlot }

/// Booster use within one attempt. Saved with the attempt, so resuming never
/// resets the limits.
class BoosterUsage {
  BoosterUsage({this.extraSlot = false, this.swapUsed = false, this.adHints = 0, this.coinHints = 0});

  factory BoosterUsage.fromJson(Map<String, Object?> json) => BoosterUsage(
        extraSlot: readBool(json['extraSlot']),
        swapUsed: readBool(json['swap']),
        adHints: readInt(json['adHints']),
        coinHints: readInt(json['coinHints']),
      );

  bool extraSlot;
  bool swapUsed;
  int adHints;
  int coinHints;

  bool get anyUsed => extraSlot || swapUsed || adHints > 0 || coinHints > 0;

  int get hints => adHints + coinHints;

  BoosterUsage copy() =>
      BoosterUsage(extraSlot: extraSlot, swapUsed: swapUsed, adHints: adHints, coinHints: coinHints);

  Map<String, Object?> toJson() => {'extraSlot': extraSlot, 'swap': swapUsed, 'adHints': adHints, 'coinHints': coinHints};
}

class ExtractResult {
  const ExtractResult({
    required this.cell,
    required this.slot,
    required this.unlocked,
    required this.matches,
    required this.status,
    required this.lossReason,
  }) : rejection = null;

  const ExtractResult.rejected(MoveRejection this.rejection)
      : cell = -1,
        slot = -1,
        unlocked = const <int>[],
        matches = const <MatchStep>[],
        status = GameStatus.playing,
        lossReason = null;

  final MoveRejection? rejection;
  final int cell;

  /// The slot the tile landed in before any match.
  final int slot;

  /// Tiles this extraction unlocked on the board.
  final List<int> unlocked;
  final List<MatchStep> matches;
  final GameStatus status;
  final LossReason? lossReason;

  bool get accepted => rejection == null;
}

class SwapResult {
  const SwapResult({required this.a, required this.b, required this.matches, required this.status, required this.lossReason})
      : accepted = true;

  const SwapResult.rejected()
      : a = -1,
        b = -1,
        matches = const <MatchStep>[],
        status = GameStatus.playing,
        lossReason = null,
        accepted = false;

  final bool accepted;
  final int a;
  final int b;
  final List<MatchStep> matches;
  final GameStatus status;
  final LossReason? lossReason;
}

/// Everything needed to continue an attempt exactly where it was left.
class GameSnapshot {
  const GameSnapshot({
    required this.puzzle,
    required this.removed,
    required this.tray,
    required this.capacity,
    required this.baseCapacity,
    required this.boosters,
    required this.moves,
    required this.peakRest,
  });

  factory GameSnapshot.fromJson(Map<String, Object?> json) => GameSnapshot(
        puzzle: PuzzleDefinition.fromJson(readMap(json['puzzle'])),
        removed: readIntList(json['removed']),
        tray: readIntList(json['tray']),
        capacity: readInt(json['capacity'], 5),
        baseCapacity: readInt(json['baseCapacity'], 5),
        boosters: BoosterUsage.fromJson(readMap(json['boosters'])),
        moves: readInt(json['moves']),
        peakRest: readInt(json['peakRest']),
      );

  final PuzzleDefinition puzzle;
  final List<int> removed;
  final List<int> tray;
  final int capacity;
  final int baseCapacity;
  final BoosterUsage boosters;
  final int moves;
  final int peakRest;

  Map<String, Object?> toJson() => {
        'puzzle': puzzle.toJson(includeSolution: false),
        'removed': removed,
        'tray': tray,
        'capacity': capacity,
        'baseCapacity': baseCapacity,
        'boosters': boosters.toJson(),
        'moves': moves,
        'peakRest': peakRest,
      };
}

/// The game logic of one attempt. It knows nothing about widgets, sounds or
/// animations: the UI asks it for moves and then animates the results.
class GameEngine {
  GameEngine({required this.puzzle, required this.rules, this.baseCapacity = 5}) : bound = rules.bind(puzzle.layout) {
    resolver = MatchResolver(bound);
    board = BoardState(puzzle.layout);
    tray = ReceptionTray(capacity: baseCapacity);
    boosters = BoosterUsage();
    _evaluate();
  }

  GameEngine.resume(GameSnapshot snapshot, {required this.rules})
      : puzzle = snapshot.puzzle,
        baseCapacity = snapshot.baseCapacity,
        bound = rules.bind(snapshot.puzzle.layout) {
    resolver = MatchResolver(bound);
    board = BoardState(puzzle.layout, removed: snapshot.removed);
    tray = ReceptionTray(
      capacity: math.max(snapshot.capacity, snapshot.tray.length),
      items: [
        for (final c in snapshot.tray)
          if (puzzle.layout.isTile(c) && board.isRemoved(c)) c,
      ],
    );
    resolver.resolve(tray.raw);
    boosters = snapshot.boosters.copy();
    moves = snapshot.moves;
    peakRest = snapshot.peakRest;
    _evaluate();
  }

  final PuzzleDefinition puzzle;
  final RuleEngine rules;
  final BoundRules bound;
  final int baseCapacity;
  late final MatchResolver resolver;
  late final BoardState board;
  late final ReceptionTray tray;
  late final BoosterUsage boosters;

  GameStatus status = GameStatus.playing;
  LossReason? lossReason;
  int moves = 0;

  /// Most tiles that waited in the tray at once (after matches resolved).
  int peakRest = 0;

  TileSpec specOf(int cell) => puzzle.layout.specOf(cell);

  List<int> get trayItems => tray.items;

  int get capacity => tray.capacity;

  bool isOpen(int cell) => board.isOpen(cell);

  List<int> openTiles() => board.openTiles();

  ExtractResult extract(int cell) {
    if (status != GameStatus.playing) return const ExtractResult.rejected(MoveRejection.finished);
    if (cell < 0 || cell >= puzzle.layout.cellCount || !puzzle.layout.isTile(cell)) {
      return const ExtractResult.rejected(MoveRejection.notATile);
    }
    if (board.isRemoved(cell)) return const ExtractResult.rejected(MoveRejection.alreadyTaken);
    if (!board.isOpen(cell)) return const ExtractResult.rejected(MoveRejection.locked);
    if (!tray.hasFreeSlot) return const ExtractResult.rejected(MoveRejection.noFreeSlot);

    final unlocked = board.extract(cell);
    final slot = tray.place(cell);
    final steps = resolver.resolve(tray.raw);
    moves++;
    peakRest = math.max(peakRest, tray.length);
    _evaluate();
    return ExtractResult(
      cell: cell,
      slot: slot,
      unlocked: unlocked,
      matches: steps,
      status: status,
      lossReason: lossReason,
    );
  }

  /// The sixth slot: available once per attempt, until the attempt ends.
  bool get canAddSlot => !boosters.extraSlot && status != GameStatus.won;

  bool addSlot() {
    if (!canAddSlot) return false;
    tray.growTo(tray.capacity + 1);
    boosters.extraSlot = true;
    _evaluate();
    return true;
  }

  /// Swapping two tray tiles: once per attempt, tray tiles only.
  bool get canSwap => !boosters.swapUsed && tray.length >= 2 && status != GameStatus.won;

  SwapResult swap(int a, int b) {
    if (!canSwap || a == b || a < 0 || b < 0 || a >= tray.length || b >= tray.length) {
      return const SwapResult.rejected();
    }
    tray.swap(a, b);
    boosters.swapUsed = true;
    final steps = resolver.resolve(tray.raw);
    _evaluate();
    return SwapResult(a: a, b: b, matches: steps, status: status, lossReason: lossReason);
  }

  void recordHint({required bool viaAd}) {
    if (viaAd) {
      boosters.adHints++;
    } else {
      boosters.coinHints++;
    }
  }

  void _evaluate() {
    if (board.isCleared && tray.isEmpty) {
      status = GameStatus.won;
      lossReason = null;
    } else if (!tray.hasFreeSlot) {
      status = GameStatus.lost;
      lossReason = LossReason.trayFull;
    } else if (board.isCleared) {
      status = GameStatus.lost;
      lossReason = LossReason.leftovers;
    } else {
      status = GameStatus.playing;
      lossReason = null;
    }
  }

  GameSnapshot snapshot() => GameSnapshot(
        puzzle: puzzle,
        removed: board.removedCells,
        tray: tray.items,
        capacity: tray.capacity,
        baseCapacity: baseCapacity,
        boosters: boosters.copy(),
        moves: moves,
        peakRest: peakRest,
      );
}
