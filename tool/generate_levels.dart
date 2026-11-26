// Generates the fixed level packs (assets/levels/) from level_curve.json.
//
// Every level is built from its own deterministic seed, verified by the
// solver and measured by the difficulty analyzer. The output is committed,
// so the levels never change on a game update unless this tool is re-run
// on purpose.
//
// Run: dart run tool/generate_levels.dart [--count 1000] [--workers 15]
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:unlock_numbers/core/difficulty/difficulty_analyzer.dart';
import 'package:unlock_numbers/core/generator/difficulty_curve.dart';
import 'package:unlock_numbers/core/generator/level_generator.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/model/puzzle_layout.dart';
import 'package:unlock_numbers/core/random/seeded_random.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/core/rules/rule_engine.dart';

Future<void> main(List<String> args) async {
  int option(String name, int fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : fallback;
  }

  final rulesJson = File('assets/config/rules.json').readAsStringSync();
  final curveJson = File('assets/config/level_curve.json').readAsStringSync();
  final curveMap = jsonDecode(curveJson) as Map<String, Object?>;
  final count = option('count', (curveMap['levelCount'] as int?) ?? 1000);
  final packSize = option('pack', (curveMap['packSize'] as int?) ?? 100);
  final workers = option('workers', (Platform.numberOfProcessors - 1).clamp(1, 32));
  final sw = Stopwatch()..start();
  stdout.writeln('Generating $count levels on $workers workers…');

  final jobs = <Future<List<Map<String, Object?>>>>[];
  for (var w = 0; w < workers; w++) {
    final levels = [for (var l = 1 + w; l <= count; l += workers) l];
    jobs.add(Isolate.run(() => _generateMany(levels, rulesJson, curveJson, 0)));
  }
  final byLevel = <int, Map<String, Object?>>{};
  for (final batch in await Future.wait(jobs)) {
    for (final level in batch) {
      byLevel[level['level'] as int] = level;
    }
  }

  // No two levels may share a layout.
  var salt = 1;
  while (true) {
    final seen = <String, int>{};
    final duplicates = <int>[];
    for (var l = 1; l <= count; l++) {
      final key = '${byLevel[l]!['rows']}x${byLevel[l]!['cols']}:${byLevel[l]!['cells']}';
      if (seen.containsKey(key)) {
        duplicates.add(l);
      } else {
        seen[key] = l;
      }
    }
    if (duplicates.isEmpty) break;
    stdout.writeln('Regenerating duplicates: $duplicates');
    for (final level in _generateMany(duplicates, rulesJson, curveJson, salt++)) {
      byLevel[level['level'] as int] = level;
    }
  }

  final outDir = Directory('assets/levels')..createSync(recursive: true);
  for (final old in outDir.listSync().whereType<File>()) {
    if (old.path.endsWith('.json')) old.deleteSync();
  }
  final book = RuleBook.fromJson(jsonDecode(rulesJson) as Map<String, Object?>);
  final packs = <Map<String, Object?>>[];
  for (var from = 1, pack = 1; from <= count; from += packSize, pack++) {
    final to = (from + packSize - 1).clamp(from, count);
    final name = 'pack_${pack.toString().padLeft(3, '0')}.json';
    final body = StringBuffer()
      ..write('{"pack":$pack,"from":$from,"to":$to,"rules":${book.currentVersion},"levels":[\n');
    for (var l = from; l <= to; l++) {
      body.write(jsonEncode(byLevel[l]));
      body.write(l == to ? '\n' : ',\n');
    }
    body.write(']}\n');
    File('${outDir.path}/$name').writeAsStringSync(body.toString());
    packs.add({'file': name, 'from': from, 'to': to});
  }
  File('${outDir.path}/index.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'generator': 1,
    'rules': book.currentVersion,
    'total': count,
    'packSize': packSize,
    'packs': packs,
  }));

  stdout.writeln('Done in ${sw.elapsed.inSeconds}s. Summary per 50 levels:');
  stdout.writeln('levels     | score avg | slots needed 2/3/4/5 | proven | grids');
  for (var from = 1; from <= count; from += 50) {
    final to = (from + 49).clamp(from, count);
    var sum = 0;
    final caps = <int, int>{};
    var proven = 0;
    final grids = <String, int>{};
    for (var l = from; l <= to; l++) {
      final d = byLevel[l]!['difficulty'] as Map<String, Object?>;
      sum += d['score'] as int;
      caps.update(d['minCap'] as int, (v) => v + 1, ifAbsent: () => 1);
      if (d['proven'] == true) proven++;
      grids.update('${byLevel[l]!['rows']}', (v) => v + 1, ifAbsent: () => 1);
    }
    final n = to - from + 1;
    stdout.writeln('${'$from-$to'.padRight(10)} | ${(sum / n).toStringAsFixed(1).padLeft(9)} | '
        '${[2, 3, 4, 5].map((c) => caps[c] ?? 0).join('/').padRight(20)} | ${'$proven'.padLeft(6)} | '
        '${grids.entries.map((e) => '${e.key}:${e.value}').join(' ')}');
  }
}

List<Map<String, Object?>> _generateMany(List<int> levels, String rulesJson, String curveJson, int salt) {
  final book = RuleBook.fromJson(jsonDecode(rulesJson) as Map<String, Object?>);
  final curve = DifficultyCurve.fromJson(jsonDecode(curveJson) as Map<String, Object?>);
  return [for (final level in levels) _makeLevel(level, book, curve, salt)];
}

Map<String, Object?> _makeLevel(int level, RuleBook book, DifficultyCurve curve, int salt) {
  final rules = RuleEngine.forPuzzle(book.current, mode: PuzzleMode.levels.key, level: level);
  final version = book.currentVersion;
  final hand = curve.handcraftedFor(level);
  if (hand != null && salt == 0) {
    final report = const DifficultyAnalyzer().analyze(hand.layout, rules, rulesetVersion: version, seed: curve.seedFor(level));
    if (report == null) throw StateError('Handcrafted level $level is not solvable.');
    return _definition(level, hand.layout, version, 0, report.profile.toJson(), report.solution);
  }
  final seed = combineSeeds(curve.seedFor(level), salt);
  final rng = SeededRandom(seed);
  final generator = LevelGenerator(rules, rulesetVersion: version);
  GeneratedPuzzle? best;
  var bestPenalty = double.infinity;
  for (var draw = 0; draw < 3; draw++) {
    final params = curve.paramsFor(level, rng);
    final result = generator.generate(params, seed: rng.nextUint32(), maxAttempts: curve.attemptsFor(level));
    if (result == null) continue;
    final penalty = LevelGenerator.penaltyFor(result.profile, params);
    if (penalty < bestPenalty) {
      best = result;
      bestPenalty = penalty;
    }
    if (penalty == 0) break;
  }
  if (best == null) throw StateError('Level $level could not be generated.');
  if (level % 50 == 0) {
    stdout.writeln('  level $level: ${best.layout.rows}x${best.layout.cols} '
        'slots ${best.profile.minCapacity}${best.profile.minCapacityProven ? '' : '?'} score ${best.profile.score}');
  }
  return _definition(level, best.layout, version, seed, best.profile.toJson(), best.solution);
}

Map<String, Object?> _definition(
  int level,
  PuzzleLayout layout,
  int version,
  int seed,
  Map<String, Object?> difficulty,
  List<int> solution,
) {
  final json = PuzzleDefinition(
    id: 'level-$level',
    mode: PuzzleMode.levels,
    layout: layout,
    rulesetVersion: version,
    levelNumber: level,
    seed: seed,
    solution: solution,
  ).toJson();
  json['difficulty'] = difficulty;
  return json;
}
