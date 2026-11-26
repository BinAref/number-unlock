// Forges the bundled first levels (assets/levels/) with the very LevelForge
// every device uses for the endless journey (so bundled and forged levels
// come from one algorithm). Run: dart run tool/generate_levels.dart [--count 10] [--probe 700]
import 'dart:convert';
import 'dart:io';

import 'package:unlock_numbers/core/generator/difficulty_curve.dart';
import 'package:unlock_numbers/core/generator/level_forge.dart';
import 'package:unlock_numbers/core/rules/rule_book.dart';

void main(List<String> args) {
  int? option(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : null;
  }

  final curveMap = jsonDecode(File('assets/config/level_curve.json').readAsStringSync()) as Map<String, Object?>;
  final book = RuleBook.fromJson(jsonDecode(File('assets/config/rules.json').readAsStringSync()) as Map<String, Object?>);
  final forge = LevelForge(curve: DifficultyCurve.fromJson(curveMap), book: book);

  final probe = option('probe');
  if (probe != null) {
    final sw = Stopwatch()..start();
    final p = forge.forge(probe);
    final d = p.profile!;
    stdout.writeln('level $probe: ${p.layout.rows}x${p.layout.cols} tiles ${d.tiles} slots ${d.minCapacity}${d.minCapacityProven ? '' : '?'} '
        'score ${d.score} paths ${d.paths} avgRest ${d.avgRest.toStringAsFixed(2)} in ${sw.elapsed.inSeconds}s');
    return;
  }

  final count = option('count') ?? (curveMap['bundled'] as int? ?? 10);
  final dir = Directory('assets/levels')..createSync(recursive: true);
  for (final f in dir.listSync().whereType<File>()) {
    if (f.path.endsWith('.json')) f.deleteSync();
  }
  final body = StringBuffer('{"pack":1,"from":1,"to":$count,"rules":${book.currentVersion},"levels":[\n');
  for (var l = 1; l <= count; l++) {
    final p = forge.forge(l);
    stdout.writeln('level $l: ${p.layout.rows}x${p.layout.cols} slots ${p.profile!.minCapacity} score ${p.profile!.score}');
    body
      ..write(jsonEncode(p.toJson()))
      ..write(l == count ? '\n' : ',\n');
  }
  body.write(']}\n');
  File('${dir.path}/pack_001.json').writeAsStringSync(body.toString());
  File('${dir.path}/index.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'version': 2,
    'rules': book.currentVersion,
    'total': count,
    'packs': [
      {'file': 'pack_001.json', 'from': 1, 'to': count},
    ],
  }));
}
