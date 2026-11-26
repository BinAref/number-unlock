import 'dart:convert';

import '../model/puzzle_definition.dart';
import '../util/json_read.dart';

class LevelPackRef {
  const LevelPackRef({required this.file, required this.from, required this.to});

  final String file;
  final int from;
  final int to;

  bool contains(int level) => level >= from && level <= to;
}

/// `assets/levels/index.json`: which pack holds which levels.
class LevelIndex {
  const LevelIndex({required this.version, required this.rulesVersion, required this.total, required this.packs});

  factory LevelIndex.fromJson(Map<String, Object?> json) => LevelIndex(
        version: readInt(json['version'], 1),
        rulesVersion: readInt(json['rules'], 1),
        total: readInt(json['total']),
        packs: [
          for (final p in readList(json['packs']))
            LevelPackRef(
              file: readString(readMap(p)['file']),
              from: readInt(readMap(p)['from']),
              to: readInt(readMap(p)['to']),
            ),
        ],
      );

  final int version;
  final int rulesVersion;
  final int total;
  final List<LevelPackRef> packs;

  LevelPackRef? packFor(int level) {
    for (final p in packs) {
      if (p.contains(level)) return p;
    }
    return null;
  }
}

/// Where pack files come from (app bundle, files, tests).
typedef PackReader = Future<String> Function(String fileName);

/// The fixed levels, loaded pack by pack only when needed.
class LevelCatalog {
  LevelCatalog(this.index, this._read);

  final LevelIndex index;
  final PackReader _read;
  final Map<String, Future<List<PuzzleDefinition>>> _packs = {};

  int get total => index.total;

  Future<List<PuzzleDefinition>> _pack(LevelPackRef ref) => _packs.putIfAbsent(ref.file, () async {
        final json = jsonDecode(await _read(ref.file)) as Map<String, Object?>;
        return [for (final l in readList(json['levels'])) PuzzleDefinition.fromJson(readMap(l))];
      });

  /// The fixed puzzle of [level] (always the same layout).
  Future<PuzzleDefinition> level(int level) async {
    final ref = index.packFor(level);
    if (ref == null) throw RangeError.range(level, 1, total, 'level');
    final pack = await _pack(ref);
    return pack[level - ref.from];
  }
}
