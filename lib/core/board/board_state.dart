import 'dart:typed_data';

import '../model/puzzle_layout.dart';
import 'board_topology.dart';
import 'unlock_system.dart';

/// The live board of one attempt.
///
/// The grid never moves: extracting a tile only leaves its cell empty until
/// the end of the puzzle. Nothing falls, slides, refills or reshuffles.
class BoardState {
  BoardState(this.layout, {Iterable<int> removed = const <int>[]})
      : topology = BoardTopology.of(layout),
        _removed = List<bool>.filled(layout.cellCount, false) {
    _remaining = layout.tileCount;
    for (final c in removed) {
      if (c >= 0 && c < layout.cellCount && layout.isTile(c) && !_removed[c]) {
        _removed[c] = true;
        _remaining--;
      }
    }
  }

  BoardState._copy(this.layout, this.topology, this._removed, this._remaining);

  static const UnlockSystem _unlock = UnlockSystem();

  final PuzzleLayout layout;
  final BoardTopology topology;
  final List<bool> _removed;
  late int _remaining;

  bool hasTile(int cell) => layout.isTile(cell) && !_removed[cell];

  bool isRemoved(int cell) => _removed[cell];

  /// Open tiles can be selected; locked ones cannot.
  bool isOpen(int cell) => hasTile(cell) && topology.isOpenWith(cell, isRemoved);

  bool isLocked(int cell) => hasTile(cell) && !isOpen(cell);

  List<int> openTiles() => [
        for (var i = 0; i < layout.cellCount; i++)
          if (isOpen(i)) i,
      ];

  int get remaining => _remaining;

  bool get isCleared => _remaining == 0;

  List<int> get removedCells => [
        for (var i = 0; i < layout.cellCount; i++)
          if (_removed[i]) i,
      ];

  Uint32List removedMask() {
    final mask = Uint32List(topology.wordCount);
    for (var i = 0; i < layout.cellCount; i++) {
      if (_removed[i]) mask[i >> 5] = mask[i >> 5] | (1 << (i & 31));
    }
    return mask;
  }

  /// Takes an open tile off the board and returns the tiles this unlocked.
  List<int> extract(int cell) {
    if (!isOpen(cell)) throw StateError('Cell $cell is not an open tile.');
    final unlocked = _unlock.unlockedBy(this, cell);
    _removed[cell] = true;
    _remaining--;
    return unlocked;
  }

  BoardState copy() => BoardState._copy(layout, topology, List<bool>.of(_removed), _remaining);
}
