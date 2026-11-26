// Measures generation speed and difficulty for a grid of settings.
// Run: dart run tool/probe_generator.dart [rows cols depth climb peel count]
import 'dart:convert';
import 'dart:io';

import 'package:unlock_numbers/core/difficulty/difficulty_analyzer.dart';
import 'package:unlock_numbers/core/generator/generation_params.dart';
import 'package:unlock_numbers/core/generator/level_generator.dart';
import 'package:unlock_numbers/core/random/seeded_random.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';
import 'package:unlock_numbers/core/rules/rule_engine.dart';

void main(List<String> args) {
  final book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);
  final rules = RuleEngine.forPuzzle(book.current, mode: 'levels');
  final configs = <GenerationParams>[];
  if (args.length >= 5) {
    configs.add(GenerationParams(
      rows: int.parse(args[0]),
      cols: int.parse(args[1]),
      targetDepth: int.parse(args[2]),
      climb: double.parse(args[3]),
      peel: PeelStyle.values.byName(args[4]),
      hardenSteps: args.length >= 7 ? int.parse(args[6]) : 0,
      bottomGaps: args.length >= 8 ? int.parse(args[7]) : 0,
      spread: args.length >= 9 && args[8] == 'spread',
    ));
  } else {
    for (final g in const [(3, 3), (4, 4), (5, 5), (6, 6)]) {
      for (final d in const [2, 3, 4]) {
        configs.add(GenerationParams(
          rows: g.$1,
          cols: g.$2,
          targetDepth: d,
          climb: 0.8,
          peel: PeelStyle.deep,
          hardenSteps: 160,
        ));
      }
    }
  }
  final count = args.length >= 6 ? int.parse(args[5]) : 6;
  final analyzer = const DifficultyAnalyzer();
  final generator = LevelGenerator(rules, analyzer: analyzer);
  stdout.writeln('grid  d  climb peel     | minCap(proven)          | score avg [min..max] | rnd   grd   dead | ms/puzzle');
  for (final p in configs) {
    final rng = SeededRandom(1234 + p.rows * 100 + p.targetDepth);
    final caps = <String>[];
    final scores = <int>[];
    var rnd = 0.0, grd = 0.0, dead = 0.0;
    final sw = Stopwatch()..start();
    var made = 0;
    for (var i = 0; i < count; i++) {
      var cand = generator.buildCandidate(p, rng);
      if (cand == null) continue;
      if (p.hardenSteps > 0) cand = generator.harden(cand, p, rng);
      final report = analyzer.analyze(cand.layout, rules, rulesetVersion: 1, seed: rng.nextUint32(), witness: cand.witness);
      if (report == null) continue;
      made++;
      final prof = report.profile;
      caps.add('${prof.minCapacity}${prof.minCapacityProven ? '' : '?'}');
      scores.add(prof.score);
      rnd += prof.randomWinRate;
      grd += prof.greedyWinRate;
      dead += prof.deadEndRatio;
    }
    sw.stop();
    if (made == 0) {
      stdout.writeln('${p.rows}x${p.cols} ${p.targetDepth}  none');
      continue;
    }
    scores.sort();
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    stdout.writeln('${p.rows}x${p.cols}   ${p.targetDepth}  ${p.climb.toStringAsFixed(1)}   ${p.peel.name.padRight(8)} | '
        '${caps.join(' ').padRight(23)} | ${avg.toStringAsFixed(1).padLeft(5)} [${scores.first}..${scores.last}]'.padRight(20) +
        ' | ${(rnd / made).toStringAsFixed(2)}  ${(grd / made).toStringAsFixed(2)}  ${(dead / made).toStringAsFixed(2)} | '
            '${(sw.elapsedMilliseconds / made).toStringAsFixed(0)}');
  }
}
