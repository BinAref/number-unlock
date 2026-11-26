import 'dart:math' as math;
import 'dart:typed_data';

import 'solver_context.dart';
import 'state_set.dart';

enum SearchStatus { running, solved, exhausted, budgetExceeded }

class _Frame {
  _Frame(this.tray, this.moves, this.childTrays, this.via);

  final List<int> tray;
  final List<int> moves;
  final List<List<int>> childTrays;

  /// The pick that led here (-1 for the starting state).
  final int via;
  int next = 0;
}

/// A depth-first search for a winning order of picks, resumable in slices so
/// it can run on the UI thread (web) without freezing a frame.
///
/// * Exact: it simulates real picks, unlocks and chained matches.
/// * Memoised: states proven hopeless are remembered and never re-explored.
/// * Bounded: [restLimit] caps how many tiles may wait in the tray at once
///   (capacity − 1 by default; a full tray is a loss), and [nodeBudget] caps
///   the work.
class SolverSearch {
  SolverSearch(
    this.ctx, {
    required Iterable<int> removed,
    required List<int> tray,
    required this.capacity,
    int? restLimit,
    StateSet? failures,
    this.nodeBudget = 1 << 30,
  })  : limit = math.min(restLimit ?? capacity - 1, capacity - 1),
        failures = failures ?? StateSet(ctx.keyLengthFor(capacity)) {
    if (this.failures.keyLength != ctx.keyLengthFor(capacity)) {
      throw ArgumentError('The failure set was built for another capacity.');
    }
    _removed = Uint32List(ctx.wordCount);
    _key = Uint32List(this.failures.keyLength);
    var removedCount = 0;
    for (final c in removed) {
      if (ctx.layout.isTile(c) && !SolverContext.isSet(_removed, c)) {
        SolverContext.setBit(_removed, c);
        removedCount++;
      }
    }
    _remaining = ctx.layout.tileCount - removedCount;
    final start = List<int>.of(tray);
    if (_remaining == 0) {
      if (start.isEmpty) {
        _status = SearchStatus.solved;
        _solution = const <int>[];
      } else {
        _status = SearchStatus.exhausted;
      }
      return;
    }
    if (start.length > limit) {
      _status = SearchStatus.exhausted;
      return;
    }
    ctx.encodeKey(_key, _removed, start);
    if (this.failures.contains(_key)) {
      _status = SearchStatus.exhausted;
      return;
    }
    final root = _expand(start, -1);
    if (root == null) {
      this.failures.add(_key);
      _status = SearchStatus.exhausted;
      return;
    }
    _frames.add(root);
  }

  final SolverContext ctx;
  final int capacity;
  final int limit;
  final StateSet failures;
  final int nodeBudget;

  late final Uint32List _removed;
  late final Uint32List _key;
  late int _remaining;
  final List<_Frame> _frames = <_Frame>[];
  SearchStatus _status = SearchStatus.running;
  List<int>? _solution;
  int _expansions = 0;

  SearchStatus get status => _status;

  /// The winning picks from the starting state (when solved).
  List<int>? get solution => _solution;

  int get expansions => _expansions;

  bool get isDone => _status != SearchStatus.running;

  /// Runs up to [maxExpansions] state expansions; returns the status.
  SearchStatus advance(int maxExpansions) {
    if (_status != SearchStatus.running) return _status;
    var left = maxExpansions;
    while (left > 0) {
      if (_frames.isEmpty) {
        _status = SearchStatus.exhausted;
        break;
      }
      final f = _frames.last;
      if (f.next >= f.moves.length) {
        ctx.encodeKey(_key, _removed, f.tray);
        failures.add(_key);
        _frames.removeLast();
        if (f.via >= 0) {
          SolverContext.clearBit(_removed, f.via);
          _remaining++;
        }
        continue;
      }
      final i = f.next++;
      final move = f.moves[i];
      final child = f.childTrays[i];
      SolverContext.setBit(_removed, move);
      _remaining--;
      if (_remaining == 0) {
        if (child.isEmpty) {
          _solution = [
            for (final fr in _frames)
              if (fr.via >= 0) fr.via,
            move,
          ];
          _status = SearchStatus.solved;
          break;
        }
        SolverContext.clearBit(_removed, move);
        _remaining++;
        continue;
      }
      ctx.encodeKey(_key, _removed, child);
      if (failures.contains(_key)) {
        SolverContext.clearBit(_removed, move);
        _remaining++;
        continue;
      }
      final next = _expand(child, move);
      _expansions++;
      left--;
      if (next == null) {
        failures.add(_key);
        SolverContext.clearBit(_removed, move);
        _remaining++;
      } else {
        _frames.add(next);
      }
      if (_expansions >= nodeBudget) {
        _status = SearchStatus.budgetExceeded;
        break;
      }
    }
    return _status;
  }

  bool _isOpen(int cell) => ctx.topology.isOpenInMask(cell, _removed);

  /// Legal picks from the current state, best first.
  _Frame? _expand(List<int> tray, int via) {
    final open = <int>[];
    for (final c in ctx.tiles) {
      if (!SolverContext.isSet(_removed, c) && _isOpen(c)) open.add(c);
    }
    final moves = <int>[];
    final trays = <List<int>>[];
    final scores = <int>[];
    final pairOnly = ctx.bound.pairOnly;
    for (final c in open) {
      final child = List<int>.of(tray)..add(c);
      final removedCount = ctx.resolver.resolveQuietly(child);
      if (child.length > limit) continue;
      var score = removedCount > 0 ? 1000 + 10 * removedCount : 0;
      score -= 40 * child.length;
      var gain = 0;
      for (final n in ctx.topology.neighbors[c]) {
        if (!SolverContext.isSet(_removed, n) && !_isOpen(n)) gain++;
      }
      score += 6 * gain;
      if (removedCount == 0 && pairOnly) {
        for (final o in open) {
          if (o != c && ctx.bound.pairMatch(c, o)) {
            score += 15;
            break;
          }
        }
      }
      moves.add(c);
      trays.add(child);
      scores.add(score);
    }
    if (moves.isEmpty) return null;
    final order = List<int>.generate(moves.length, (i) => i)
      ..sort((a, b) {
        final d = scores[b] - scores[a];
        return d != 0 ? d : moves[a] - moves[b];
      });
    return _Frame(
      tray,
      [for (final i in order) moves[i]],
      [for (final i in order) trays[i]],
      via,
    );
  }
}
