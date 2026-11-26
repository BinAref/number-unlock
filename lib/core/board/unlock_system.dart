import 'board_state.dart';

/// Decides which locked tiles open when a tile is extracted.
///
/// Rule: extracting a tile opens every locked tile directly above, below,
/// left or right of the emptied cell. Diagonals never open. Merely being
/// open does not open neighbours — a tile has to be extracted first, and no
/// match is required for it to open them.
class UnlockSystem {
  const UnlockSystem();

  /// The tiles that [cell]'s extraction from [board] would unlock.
  List<int> unlockedBy(BoardState board, int cell) {
    final out = <int>[];
    for (final n in board.topology.neighbors[cell]) {
      if (board.hasTile(n) && !board.isOpen(n)) out.add(n);
    }
    return out;
  }
}
