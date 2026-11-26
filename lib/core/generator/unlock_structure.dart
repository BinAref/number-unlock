import '../model/arrows.dart';
import '../random/seeded_random.dart';
import 'generation_params.dart';

/// Who opens whom on a board: every cell's arrows and the tiles open from
/// the start.
class UnlockStructure {
  const UnlockStructure({required this.dirs, required this.open, required this.hasArrows, this.parent = const <int>[]});

  final List<int> dirs;
  final List<bool> open;
  final bool hasArrows;

  /// The one tile that opens each locked tile (-1 for open tiles and voids;
  /// empty when the board has no arrows).
  final List<int> parent;
}

/// Lays the arrows of a board shape.
///
/// A growing tree spans every tile from the entrances: each locked tile is
/// opened by exactly one tile — its parent, whose arrow points at it — so
/// it can only be reached through that parent, and the order of picks
/// matters. A tile opens one or two others (one in the single-arrow stage).
/// A tile that opens nobody becomes a star, or carries a decoy arrow aimed
/// where it can never open anything (back at its parent, at a tile that is
/// open from the start, at a void or off the board): decoys add doubt but
/// never a second way in.
///
/// Every choice comes from the seeded generator, in a fixed order, so the
/// same seed lays the same arrows on every platform.
class UnlockStructureBuilder {
  const UnlockStructureBuilder();

  static const int _attempts = 40;

  UnlockStructure? build(List<bool> isTile, int rows, int cols, ArrowParams a, int entrances, SeededRandom rng) {
    final n = rows * cols;
    final tiles = [
      for (var i = 0; i < n; i++)
        if (isTile[i]) i,
    ];
    if (tiles.isEmpty) return null;
    if (!a.enabled) {
      return UnlockStructure(dirs: List<int>.filled(n, Arrows.none), open: List<bool>.of(isTile), hasArrows: false);
    }
    for (var attempt = 0; attempt < _attempts; attempt++) {
      // Fresh entrances each time: some pairs cannot reach every tile with
      // single-arrow chains, another pair usually can.
      final roots = _entrances(isTile, rows, cols, tiles, a, entrances, rng);
      final tree = _grow(isTile, rows, cols, tiles, roots, a, rng, forceComplete: attempt == _attempts - 1);
      if (tree != null) return _finish(tree, isTile, rows, cols, tiles, a, rng);
    }
    return null;
  }

  /// One entrance per connected group of tiles (at its lowest row), then
  /// more along the bottom row up to [wanted]; `scatter` sometimes adds one
  /// higher up the board.
  List<int> _entrances(List<bool> isTile, int rows, int cols, List<int> tiles, ArrowParams a, int wanted, SeededRandom rng) {
    final n = rows * cols;
    final group = List<int>.filled(n, -1);
    var groups = 0;
    for (final t in tiles) {
      if (group[t] >= 0) continue;
      final queue = <int>[t];
      group[t] = groups;
      for (var h = 0; h < queue.length; h++) {
        final c = queue[h];
        for (final d in Arrows.each) {
          final j = Arrows.target(c, d, rows, cols);
          if (j >= 0 && isTile[j] && group[j] < 0) {
            group[j] = groups;
            queue.add(j);
          }
        }
      }
      groups++;
    }
    final isRoot = List<bool>.filled(n, false);
    final roots = <int>[];
    void add(int c) {
      if (isRoot[c]) return;
      isRoot[c] = true;
      roots.add(c);
    }

    for (var g = 0; g < groups; g++) {
      var lowest = -1;
      for (final t in tiles) {
        if (group[t] == g && t ~/ cols > lowest) lowest = t ~/ cols;
      }
      add(rng.pick([
        for (final t in tiles)
          if (group[t] == g && t ~/ cols == lowest) t,
      ]));
    }
    final extra = [
      for (final t in tiles)
        if (t ~/ cols == rows - 1 && !isRoot[t]) t,
    ];
    rng.shuffle(extra);
    for (final t in extra) {
      if (roots.length >= wanted) break;
      add(t);
    }
    if (a.open == 'scatter' && rng.chance(0.6)) {
      final high = [
        for (final t in tiles)
          if (t ~/ cols < rows - 1 && !isRoot[t] && !_touches(t, isRoot, rows, cols)) t,
      ];
      if (high.isNotEmpty) add(rng.pick(high));
    }
    return roots;
  }

  /// Whether [c] has a direction where an arrow could never open anything:
  /// off the board, at a void or at a tile open from the start.
  static bool _harmless(int c, List<bool> open, List<bool> isTile, int rows, int cols) {
    for (final d in Arrows.each) {
      final j = Arrows.target(c, d, rows, cols);
      if (j < 0 || !isTile[j] || open[j]) return true;
    }
    return false;
  }

  static bool _touches(int c, List<bool> marks, int rows, int cols) {
    for (final d in Arrows.each) {
      final j = Arrows.target(c, d, rows, cols);
      if (j >= 0 && marks[j]) return true;
    }
    return false;
  }

  /// Grows the tree. Returns null when tiles were stranded (the caller
  /// retries), except on the last attempt: then a stranded tile is opened
  /// from the start instead, so the board always stays whole.
  _Tree? _grow(List<bool> isTile, int rows, int cols, List<int> tiles, List<int> roots, ArrowParams a, SeededRandom rng,
      {required bool forceComplete}) {
    final n = rows * cols;
    final dirs = List<int>.filled(n, Arrows.none);
    final parent = List<int>.filled(n, -1);
    final kids = List<int>.filled(n, 0);
    final cap = List<int>.filled(n, 1);
    final inTree = List<bool>.filled(n, false);
    final open = List<bool>.filled(n, false);
    final isActive = List<bool>.filled(n, false);
    final active = <int>[];
    var covered = 0;

    void join(int c) {
      inTree[c] = true;
      covered++;
      cap[c] = a.maxArrows >= 2 && rng.chance(a.twoRatio) ? 2 : 1;
      active.add(c);
      isActive[c] = true;
    }

    void retire(int c) {
      active.remove(c);
      isActive[c] = false;
    }

    // Whether a free region beside [from] has no other growing tile that
    // could still open it — it would be stranded once [from] stops growing.
    bool strandsWithout(int from) {
      for (final d in Arrows.each) {
        final j = Arrows.target(from, d, rows, cols);
        if (j < 0 || !isTile[j] || inTree[j]) continue;
        final seen = <int>{j};
        final queue = <int>[j];
        var reachable = false;
        for (var h = 0; h < queue.length && !reachable; h++) {
          for (final e in Arrows.each) {
            final x = Arrows.target(queue[h], e, rows, cols);
            if (x < 0 || !isTile[x]) continue;
            if (inTree[x]) {
              if (x != from && isActive[x]) reachable = true;
            } else if (seen.add(x)) {
              queue.add(x);
            }
          }
        }
        if (!reachable) return true;
      }
      return false;
    }

    int freeAround(int c) {
      var k = 0;
      for (final d in Arrows.each) {
        final j = Arrows.target(c, d, rows, cols);
        if (j >= 0 && isTile[j] && !inTree[j]) k++;
      }
      return k;
    }

    for (final r in roots) {
      open[r] = true;
      join(r);
    }
    while (covered < tiles.length) {
      if (active.isEmpty) {
        if (!forceComplete) return null;
        // Prefer a stranded tile next to the tree that can still show a
        // harmless arrow (at the edge or beside an open tile).
        var stranded = -1;
        var best = -1;
        for (final t in tiles) {
          if (inTree[t]) continue;
          final score = (_touches(t, inTree, rows, cols) ? 2 : 0) + (_harmless(t, open, isTile, rows, cols) ? 1 : 0);
          if (score > best) {
            best = score;
            stranded = t;
          }
        }
        open[stranded] = true;
        join(stranded);
        continue;
      }
      // Newest tile (long chains) or any growing tile (bushy branches).
      final k = rng.chance(a.branchiness) ? rng.nextInt(active.length) : active.length - 1;
      final from = active[k];
      final options = <int>[];
      final weights = <double>[];
      // Prefer tiles with few free neighbours, so none gets stranded —
      // sharply for single-arrow chains, which cannot branch around a gap.
      final sharp = cap[from] == 1;
      for (final d in Arrows.each) {
        final j = Arrows.target(from, d, rows, cols);
        if (j < 0 || !isTile[j] || inTree[j]) continue;
        final w = 1 / (1 + freeAround(j));
        options.add(j);
        weights.add(sharp ? w * w * w + 0.02 : w * w + 0.08);
      }
      if (options.isEmpty) {
        retire(from);
        continue;
      }
      final next = options[rng.pickWeighted(weights)];
      dirs[from] |= Arrows.between(from, next, cols);
      kids[from]++;
      parent[next] = from;
      join(next);
      if (kids[from] >= cap[from]) {
        // A forced fork: rather than strand a pocket that only this tile
        // can still reach, let it open that pocket too (when two arrows are
        // allowed). Branches then appear where the shape needs them.
        if (a.maxArrows >= 2 && kids[from] < 2 && strandsWithout(from)) {
          cap[from] = 2;
        } else {
          retire(from);
        }
      }
    }
    return _Tree(dirs, parent, kids, open);
  }

  /// Childless tiles become stars or get a decoy arrow; some single-child
  /// tiles get a decoy second arrow.
  UnlockStructure _finish(_Tree t, List<bool> isTile, int rows, int cols, List<int> tiles, ArrowParams a, SeededRandom rng) {
    final dirs = t.dirs;
    int decoy(int c) {
      final options = <int>[];
      for (final d in Arrows.each) {
        if (Arrows.has(dirs[c], d)) continue;
        final j = Arrows.target(c, d, rows, cols);
        if (j < 0 || !isTile[j] || t.open[j] || j == t.parent[c]) options.add(d);
      }
      return options.isEmpty ? Arrows.none : options[rng.nextInt(options.length)];
    }

    for (final c in tiles) {
      if (t.kids[c] == 0) {
        if (a.starRatio > 0 && rng.chance(a.starRatio)) continue;
        var d = decoy(c);
        if (d == Arrows.none && a.starRatio <= 0) {
          // Stars are not taught yet, so every tile shows an arrow. Only a
          // tile opened from the start in the rescue above can land here;
          // its arrow may add a second way into its target, never block one.
          final any = [
            for (final x in Arrows.each)
              if (Arrows.target(c, x, rows, cols) >= 0) x,
          ];
          if (any.isNotEmpty) d = any[rng.nextInt(any.length)];
        }
        dirs[c] |= d;
      } else if (t.kids[c] == 1 && a.maxArrows >= 2 && rng.chance(a.decoyRatio)) {
        dirs[c] |= decoy(c);
      }
    }
    return UnlockStructure(dirs: dirs, open: t.open, hasArrows: true, parent: t.parent);
  }
}

class _Tree {
  const _Tree(this.dirs, this.parent, this.kids, this.open);

  final List<int> dirs;
  final List<int> parent;
  final List<int> kids;
  final List<bool> open;
}
