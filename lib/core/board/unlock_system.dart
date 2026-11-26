import 'board_state.dart';

/// Decides which locked tiles open when a tile is extracted.
///
/// Rule: extracting a tile opens only the locked tiles its arrows point at —
/// the cell right next to it in each arrow's direction. A star (no arrows)
/// opens nothing. An arrow aimed at a tile that is already open or taken, at
/// a void or off the board opens nothing, and nothing is opened in its
/// place. Merely being open does not open anything: a tile has to be
/// extracted first, and no match is required for it to open its targets.
class UnlockSystem {
  const UnlockSystem();

  /// The tiles that [cell]'s extraction from [board] would unlock.
  List<int> unlockedBy(BoardState board, int cell) {
    final out = <int>[];
    for (final n in board.topology.targets[cell]) {
      if (board.hasTile(n) && !board.isOpen(n)) out.add(n);
    }
    return out;
  }
}
