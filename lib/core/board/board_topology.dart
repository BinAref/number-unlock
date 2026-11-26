import 'dart:typed_data';

import '../model/arrows.dart';
import '../model/puzzle_layout.dart';

/// Static geometry of a puzzle: which cells hold tiles, who neighbours whom,
/// which tiles start open and — the arrow rule — which tiles each tile opens.
///
/// Extracting a tile opens only the locked tiles its arrows point at: the
/// cell right next to it in each arrow's direction. An arrow aimed at an
/// open or empty cell, a void or the edge of the board opens nothing, and no
/// other tile is opened in its place. Opening never chains: a tile that has
/// just opened opens nothing until it is extracted itself.
///
/// Shared by gameplay, the solver, the generator and the hints, so every
/// system agrees on how tiles unlock.
class BoardTopology {
  BoardTopology._({
    required this.rows,
    required this.cols,
    required this.isTile,
    required this.neighbors,
    required this.targets,
    required this.sources,
    required this.startsOpen,
    required this.incomingMasks,
    required this.wordCount,
  });

  factory BoardTopology.of(PuzzleLayout layout) {
    final rows = layout.rows;
    final cols = layout.cols;
    final n = layout.cellCount;
    final wordCount = (n + 31) >> 5;
    final isTile = List<bool>.generate(n, layout.isTile, growable: false);
    final neighbors = List<List<int>>.generate(n, (i) {
      if (!isTile[i]) return const <int>[];
      final out = <int>[];
      for (final d in Arrows.each) {
        final j = Arrows.target(i, d, rows, cols);
        if (j >= 0 && isTile[j]) out.add(j);
      }
      return List<int>.unmodifiable(out);
    }, growable: false);
    final targets = List<List<int>>.generate(n, (i) {
      if (!isTile[i]) return const <int>[];
      final out = <int>[];
      for (final d in Arrows.each) {
        if (!Arrows.has(layout.dirs[i], d)) continue;
        final j = Arrows.target(i, d, rows, cols);
        if (j >= 0 && isTile[j]) out.add(j);
      }
      return List<int>.unmodifiable(out);
    }, growable: false);
    final sources = List<List<int>>.generate(n, (_) => <int>[], growable: false);
    for (var i = 0; i < n; i++) {
      for (final j in targets[i]) {
        sources[j].add(i);
      }
    }
    final masks = List<Uint32List>.generate(n, (i) {
      final m = Uint32List(wordCount);
      for (final j in sources[i]) {
        m[j >> 5] = m[j >> 5] | (1 << (j & 31));
      }
      return m;
    }, growable: false);
    return BoardTopology._(
      rows: rows,
      cols: cols,
      isTile: isTile,
      neighbors: neighbors,
      targets: targets,
      sources: [for (final s in sources) List<int>.unmodifiable(s)],
      startsOpen: List<bool>.generate(n, (i) => isTile[i] && layout.openAtStart[i], growable: false),
      incomingMasks: masks,
      wordCount: wordCount,
    );
  }

  final int rows;
  final int cols;
  final List<bool> isTile;

  /// The tile cells touching each cell (up, down, left, right; voids are
  /// never neighbours). Geometry only — tiles open through [targets].
  final List<List<int>> neighbors;

  /// The tiles each tile's arrows point at: extracting the tile opens those
  /// that are still locked.
  final List<List<int>> targets;

  /// The tiles whose extraction opens each tile.
  final List<List<int>> sources;

  /// Tiles open from the very start.
  final List<bool> startsOpen;

  /// [sources] as bit masks (used by the solver's hot loop).
  final List<Uint32List> incomingMasks;
  final int wordCount;

  int get cellCount => rows * cols;

  /// Whether a tile (not yet extracted) is open, given a test for extracted
  /// cells: it started open, or a tile pointing at it has been extracted.
  bool isOpenWith(int cell, bool Function(int cell) isRemoved) {
    if (startsOpen[cell]) return true;
    for (final s in sources[cell]) {
      if (isRemoved(s)) return true;
    }
    return false;
  }

  /// Same rule, against an extracted-cells bit mask.
  bool isOpenInMask(int cell, Uint32List removed) {
    if (startsOpen[cell]) return true;
    final m = incomingMasks[cell];
    for (var w = 0; w < wordCount; w++) {
      if ((m[w] & removed[w]) != 0) return true;
    }
    return false;
  }

  /// True when every tile can eventually be opened: following arrows from
  /// the tiles that start open reaches all of them. A puzzle failing this
  /// can never be cleared.
  bool allTilesReachable() {
    final seen = List<bool>.filled(cellCount, false);
    final queue = <int>[];
    for (var i = 0; i < cellCount; i++) {
      if (startsOpen[i]) {
        seen[i] = true;
        queue.add(i);
      }
    }
    var head = 0;
    while (head < queue.length) {
      final c = queue[head++];
      for (final t in targets[c]) {
        if (!seen[t]) {
          seen[t] = true;
          queue.add(t);
        }
      }
    }
    for (var i = 0; i < cellCount; i++) {
      if (isTile[i] && !seen[i]) return false;
    }
    return true;
  }
}
