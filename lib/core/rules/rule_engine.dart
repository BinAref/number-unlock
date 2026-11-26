import 'dart:typed_data';

import '../model/puzzle_layout.dart';
import '../model/tile_spec.dart';
import 'rule_book.dart';
import 'rule_definition.dart';

/// The single, central rule engine.
///
/// Gameplay, the solver, the level generator, the hints and the boosters all
/// evaluate matches through this class, so they can never disagree about
/// what counts as a match.
class RuleEngine {
  RuleEngine(Iterable<RuleDefinition> rules) : rules = List<RuleDefinition>.unmodifiable(_sorted(rules));

  /// The rules active for [mode] (and optionally a level number).
  factory RuleEngine.forPuzzle(RuleSet set, {required String mode, int? level}) =>
      RuleEngine(set.activeFor(mode, level: level));

  static List<RuleDefinition> _sorted(Iterable<RuleDefinition> rules) {
    final indexed = <(int, RuleDefinition)>[];
    var i = 0;
    for (final r in rules) {
      if (r.enabled) indexed.add((i++, r));
    }
    indexed.sort((a, b) {
      final d = b.$2.priority.compareTo(a.$2.priority);
      return d != 0 ? d : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Active rules, highest priority first.
  final List<RuleDefinition> rules;

  bool get isEmpty => rules.isEmpty;

  bool get pairOnly => rules.isNotEmpty && rules.every((r) => r.size == 2);

  bool get usesColor => rules.any((r) => r.usesColor);

  /// The first rule (by priority) that accepts exactly this group.
  RuleDefinition? ruleFor(List<TileSpec> group) {
    for (final r in rules) {
      if (r.size == group.length && r.test(group)) return r;
    }
    return null;
  }

  /// Whether tile [b] placed right after tile [a] would match.
  bool pairMatches(TileSpec a, TileSpec b) {
    for (final r in rules) {
      if (r.size == 2 && r.test([a, b])) return true;
    }
    return false;
  }

  BoundRules bind(PuzzleLayout layout) => BoundRules._(this, layout);
}

/// A match found in the tray: [rule] accepts the tiles from [start].
class MatchHit {
  const MatchHit(this.rule, this.start);

  final RuleDefinition rule;
  final int start;

  int get size => rule.size;
}

/// The rule engine bound to one layout, with pair results cached per cell.
class BoundRules {
  BoundRules._(this.engine, this.layout) : _n = layout.cellCount {
    _pairTables = [for (final r in engine.rules) r.size == 2 ? _pairTable(r) : null];
    _anyPair = Uint8List(_n * _n);
    for (final t in _pairTables) {
      if (t == null) continue;
      for (var i = 0; i < t.length; i++) {
        if (t[i] != 0) _anyPair[i] = 1;
      }
    }
    final (ids, count) = _equivalence();
    equivalence = ids;
    classCount = count;
  }

  final RuleEngine engine;
  final PuzzleLayout layout;
  final int _n;
  late final List<Uint8List?> _pairTables;
  late final Uint8List _anyPair;

  /// Canonical class per cell: tiles in the same class behave identically
  /// under the active rules, so the solver may treat them as one.
  late final List<int> equivalence;
  late final int classCount;

  bool get pairOnly => engine.pairOnly;

  Uint8List _pairTable(RuleDefinition rule) {
    final table = Uint8List(_n * _n);
    for (final a in layout.tileIndices) {
      final sa = layout.specOf(a);
      for (final b in layout.tileIndices) {
        if (rule.test([sa, layout.specOf(b)])) table[a * _n + b] = 1;
      }
    }
    return table;
  }

  /// Whether tile [b] right after tile [a] matches under any pair rule.
  bool pairMatch(int a, int b) => _anyPair[a * _n + b] == 1;

  /// The first match in [tray]: rules by priority, then left to right.
  MatchHit? findFirst(List<int> tray) {
    final rules = engine.rules;
    for (var r = 0; r < rules.length; r++) {
      final rule = rules[r];
      final size = rule.size;
      if (tray.length < size) continue;
      final table = _pairTables[r];
      for (var s = 0; s + size <= tray.length; s++) {
        final bool ok;
        if (table != null) {
          ok = table[tray[s] * _n + tray[s + 1]] == 1;
        } else {
          ok = rule.test([for (var k = 0; k < size; k++) layout.specOf(tray[s + k])]);
        }
        if (ok) return MatchHit(rule, s);
      }
    }
    return null;
  }

  (List<int>, int) _equivalence() {
    final ids = List<int>.filled(_n, -1);
    final keys = <String, int>{};
    final tiles = layout.tileIndices.toList();
    for (final cell in tiles) {
      final String key;
      if (engine.pairOnly) {
        // With pair rules only, a resolved tray never holds a match, and a new
        // tile can only pair with the tile before it. Which rule claims that
        // single window cannot change the result, so tiles whose combined
        // pair relations agree are interchangeable.
        final b = StringBuffer();
        for (final other in tiles) {
          b.write(_anyPair[cell * _n + other]);
          b.write(_anyPair[other * _n + cell]);
        }
        key = b.toString();
      } else {
        final s = layout.specOf(cell);
        key = engine.usesColor ? '${s.value}:${s.color}' : '${s.value}';
      }
      ids[cell] = keys.putIfAbsent(key, () => keys.length);
    }
    return (ids, keys.length);
  }
}
