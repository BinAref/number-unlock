import 'dart:typed_data';

import '../model/puzzle_layout.dart';

/// Static geometry of a puzzle: which cells hold tiles, who neighbours whom
/// (up, down, left and right — never diagonally) and which tiles start open.
///
/// Shared by gameplay, the solver, the generator and the hints, so every
/// system agrees on how tiles unlock.
class BoardTopology {
  BoardTopology._({
    required this.rows,
    required this.cols,
    required this.isTile,
    required this.neighbors,
    required this.startsOpen,
    required this.neighborMasks,
    required this.wordCount,
  });

  factory BoardTopology.of(PuzzleLayout layout) {
    final n = layout.cellCount;
    final wordCount = (n + 31) >> 5;
    final isTile = List<bool>.generate(n, layout.isTile, growable: false);
    final neighbors = List<List<int>>.generate(n, (i) {
      if (!isTile[i]) return const <int>[];
      final r = layout.rowOf(i);
      final c = layout.colOf(i);
      final out = <int>[];
      void consider(int rr, int cc) {
        if (rr < 0 || cc < 0 || rr >= layout.rows || cc >= layout.cols) return;
        final j = layout.indexOf(rr, cc);
        if (isTile[j]) out.add(j);
      }

      consider(r - 1, c);
      consider(r + 1, c);
      consider(r, c - 1);
      consider(r, c + 1);
      return List<int>.unmodifiable(out);
    }, growable: false);
    final startsOpen = List<bool>.generate(n, (i) => isTile[i] && layout.isBottomRow(i), growable: false);
    final masks = List<Uint32List>.generate(n, (i) {
      final m = Uint32List(wordCount);
      for (final j in neighbors[i]) {
        m[j >> 5] = m[j >> 5] | (1 << (j & 31));
      }
      return m;
    }, growable: false);
    return BoardTopology._(
      rows: layout.rows,
      cols: layout.cols,
      isTile: isTile,
      neighbors: neighbors,
      startsOpen: startsOpen,
      neighborMasks: masks,
      wordCount: wordCount,
    );
  }

  final int rows;
  final int cols;
  final List<bool> isTile;

  /// The tile cells next to each cell (voids are never neighbours).
  final List<List<int>> neighbors;

  /// Bottom-row tiles: selectable from the very start.
  final List<bool> startsOpen;

  /// Neighbour sets as bit masks (used by the solver's hot loop).
  final List<Uint32List> neighborMasks;
  final int wordCount;

  int get cellCount => rows * cols;

  /// Whether a tile (not yet extracted) is open, given a test for extracted
  /// cells. A tile is open when it starts open or a neighbour was extracted.
  bool isOpenWith(int cell, bool Function(int cell) isRemoved) {
    if (startsOpen[cell]) return true;
    for (final n in neighbors[cell]) {
      if (isRemoved(n)) return true;
    }
    return false;
  }

  /// Same rule, against an extracted-cells bit mask.
  bool isOpenInMask(int cell, Uint32List removed) {
    if (startsOpen[cell]) return true;
    final m = neighborMasks[cell];
    for (var w = 0; w < wordCount; w++) {
      if ((m[w] & removed[w]) != 0) return true;
    }
    return false;
  }

  /// True when every tile can eventually be reached from the bottom row
  /// through neighbouring tiles. A puzzle failing this can never be cleared.
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
      for (final n in neighbors[c]) {
        if (!seen[n]) {
          seen[n] = true;
          queue.add(n);
        }
      }
    }
    for (var i = 0; i < cellCount; i++) {
      if (isTile[i] && !seen[i]) return false;
    }
    return true;
  }
}
