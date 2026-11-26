import 'dart:convert';

import 'package:flutter/foundation.dart' as foundation;

import '../core/generator/difficulty_curve.dart';
import '../core/generator/level_forge.dart';
import '../core/levels/level_catalog.dart';
import '../core/model/puzzle_definition.dart';
import '../core/rules/rule_book.dart';
import '../core/util/json_read.dart';
import 'compute_scheduler.dart';
import 'storage.dart';

/// The endless levels.
///
/// The first levels ship with the game; every later level is forged on the
/// device the first time it is needed and then kept. Because forging is
/// deterministic, the same level number is the same puzzle for everyone.
/// After each win the next [lookahead] levels are prepared in the
/// background, so the player never waits.
class LevelService {
  LevelService({
    required this.bundled,
    required this.forge,
    required this.store,
    required this.scheduler,
    required this.version,
    required this.lookahead,
    required String rulesJson,
    required String curveJson,
  })  : _rulesJson = rulesJson,
        _curveJson = curveJson;

  final LevelCatalog bundled;
  final LevelForge forge;
  final KeyValueStore store;
  final ComputeScheduler scheduler;
  final int version;
  final int lookahead;
  final String _rulesJson;
  final String _curveJson;
  final Map<int, PuzzleDefinition> _memory = {};
  final Map<int, Future<PuzzleDefinition>> _pending = {};
  bool _warming = false;

  /// The journey never ends.
  int get total => 1 << 30;

  int get bundledCount => bundled.total;

  String _key(int n) => 'un.level.v$version.$n';

  Future<PuzzleDefinition> level(int n) {
    final known = _memory[n];
    if (known != null) return Future.value(known);
    return _pending.putIfAbsent(n, () async {
      try {
        final p = await _load(n);
        _memory[n] = p;
        return p;
      } finally {
        _pending.remove(n);
      }
    });
  }

  Future<bool> isReady(int n) async => n <= bundledCount || _memory.containsKey(n) || (await store.read(_key(n))) != null;

  Future<PuzzleDefinition> _load(int n) async {
    if (n <= bundledCount) return bundled.level(n);
    final raw = await store.read(_key(n));
    if (raw != null) {
      try {
        return PuzzleDefinition.fromJson(readMap(jsonDecode(raw)));
      } on Object {
        // Corrupt cache: forge again (the result is identical anyway).
      }
    }
    final PuzzleDefinition p;
    if (foundation.kIsWeb) {
      p = await scheduler.run(forge.job(n), units: 1);
    } else {
      final json = await foundation.compute(forgeLevelInIsolate, <Object>[n, _rulesJson, _curveJson]);
      p = PuzzleDefinition.fromJson(readMap(jsonDecode(json)));
    }
    await store.write(_key(n), jsonEncode(p.toJson()));
    return p;
  }

  /// Prepares the levels up to [highest] + [lookahead], one at a time.
  Future<void> ensureAhead(int highest) async {
    if (_warming) return;
    _warming = true;
    try {
      for (var n = bundledCount + 1; n <= highest + lookahead; n++) {
        if (!await isReady(n)) await level(n);
      }
    } on Object {
      // Try again after the next win.
    } finally {
      _warming = false;
    }
  }
}

/// Isolate entry point (mobile): forges one level from the raw config.
String forgeLevelInIsolate(List<Object> args) {
  final book = RuleBook.fromJson(readMap(jsonDecode(args[1] as String)));
  final curve = DifficultyCurve.fromJson(readMap(jsonDecode(args[2] as String)));
  return jsonEncode(LevelForge(curve: curve, book: book).forge(args[0] as int).toJson());
}
