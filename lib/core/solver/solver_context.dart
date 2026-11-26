import 'dart:typed_data';

import '../board/board_topology.dart';
import '../model/puzzle_layout.dart';
import '../rules/match_resolver.dart';
import '../rules/rule_engine.dart';

/// Everything the solver needs about one puzzle, prepared once.
///
/// It reuses the very same topology (unlocking) and rule engine (matching)
/// as gameplay, so every solution it finds can really be played.
class SolverContext {
  SolverContext(this.layout, this.rules)
      : topology = BoardTopology.of(layout),
        bound = rules.bind(layout) {
    resolver = MatchResolver(bound);
    tiles = List<int>.unmodifiable(layout.tileIndices);
  }

  final PuzzleLayout layout;
  final RuleEngine rules;
  final BoardTopology topology;
  final BoundRules bound;
  late final MatchResolver resolver;

  /// Cells holding a tile at the start.
  late final List<int> tiles;

  int get wordCount => topology.wordCount;

  /// Words needed to pack a resting tray (6 bits per tile class, 5 per word).
  static int trayWordsFor(int capacity) {
    final rest = capacity - 1;
    final words = (rest + 4) ~/ 5;
    return words < 1 ? 1 : words;
  }

  int keyLengthFor(int capacity) => wordCount + trayWordsFor(capacity);

  /// Writes the state key: extracted cells, then the tray's tile classes.
  void encodeKey(Uint32List out, Uint32List removed, List<int> tray) {
    for (var w = 0; w < wordCount; w++) {
      out[w] = removed[w];
    }
    for (var k = wordCount; k < out.length; k++) {
      out[k] = 0;
    }
    final classes = bound.equivalence;
    for (var i = 0; i < tray.length; i++) {
      final w = wordCount + i ~/ 5;
      if (w >= out.length) throw StateError('Tray longer than the key allows.');
      out[w] = out[w] | ((classes[tray[i]] + 1) << (6 * (i % 5)));
    }
  }

  Uint32List maskOf(Iterable<int> cells) {
    final mask = Uint32List(wordCount);
    for (final c in cells) {
      setBit(mask, c);
    }
    return mask;
  }

  static bool isSet(Uint32List mask, int cell) => (mask[cell >> 5] & (1 << (cell & 31))) != 0;

  static void setBit(Uint32List mask, int cell) {
    final w = cell >> 5;
    mask[w] = mask[w] | (1 << (cell & 31));
  }

  static void clearBit(Uint32List mask, int cell) {
    final w = cell >> 5;
    mask[w] = (mask[w] & ~(1 << (cell & 31))) & 0xFFFFFFFF;
  }
}
