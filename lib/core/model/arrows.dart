/// The directions a tile can open, stored as a 4-bit mask per cell.
///
/// Extracting a tile opens only the locked tile right next to it in each
/// direction its arrows point (see `BoardTopology`). A tile without arrows
/// on an arrow board is a star: it opens nothing.
///
/// Directions are screen-absolute — up is always up and right always right —
/// so the board is never mirrored, whatever the reading direction.
abstract final class Arrows {
  static const int none = 0;
  static const int up = 1;
  static const int right = 2;
  static const int down = 4;
  static const int left = 8;
  static const int all = 15;

  /// Every single direction, in a fixed order (keeps generation deterministic).
  static const List<int> each = [up, right, down, left];

  static bool has(int mask, int dir) => (mask & dir) != 0;

  static int count(int mask) {
    var n = 0;
    for (final d in each) {
      if (has(mask, d)) n++;
    }
    return n;
  }

  /// The cell that [dir] points at from [cell] on a rows × cols board, or -1
  /// when the arrow points off the board.
  static int target(int cell, int dir, int rows, int cols) {
    final r = cell ~/ cols;
    final c = cell % cols;
    switch (dir) {
      case up:
        return r > 0 ? cell - cols : -1;
      case down:
        return r < rows - 1 ? cell + cols : -1;
      case left:
        return c > 0 ? cell - 1 : -1;
      case right:
        return c < cols - 1 ? cell + 1 : -1;
    }
    return -1;
  }

  /// The direction from [from] to the adjacent cell [to], or [none] when the
  /// two cells do not touch.
  static int between(int from, int to, int cols) {
    if (to == from - cols) return up;
    if (to == from + cols) return down;
    if (to == from - 1 && from % cols != 0) return left;
    if (to == from + 1 && to % cols != 0) return right;
    return none;
  }
}
