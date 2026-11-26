import '../util/json_read.dart';
import 'rule_definition.dart';

/// One versioned set of matching rules.
///
/// Every fixed level remembers the ruleset version it was built for, so a
/// future ruleset never changes how an existing level plays.
class RuleSet {
  const RuleSet({required this.version, required this.rules});

  factory RuleSet.fromJson(Map<String, Object?> json) => RuleSet(
        version: readInt(json['version'], 1),
        rules: [for (final r in readList(json['rules'])) RuleDefinition.fromJson(readMap(r))],
      );

  final int version;
  final List<RuleDefinition> rules;

  /// Enabled rules for a mode (and optionally a level number).
  List<RuleDefinition> activeFor(String mode, {int? level}) => [
        for (final r in rules)
          if (r.availableIn(mode, level: level)) r,
      ];

  Map<String, Object?> toJson() => {
        'version': version,
        'rules': [for (final r in rules) r.toJson()],
      };
}

/// All known rulesets (from `assets/config/rules.json`).
class RuleBook {
  RuleBook({required this.currentVersion, required Iterable<RuleSet> sets})
      : _sets = {for (final s in sets) s.version: s} {
    if (!_sets.containsKey(currentVersion)) {
      throw ArgumentError('Ruleset $currentVersion is missing.');
    }
  }

  factory RuleBook.fromJson(Map<String, Object?> json) => RuleBook(
        currentVersion: readInt(json['currentVersion'], 1),
        sets: [for (final s in readList(json['rulesets'])) RuleSet.fromJson(readMap(s))],
      );

  final int currentVersion;
  final Map<int, RuleSet> _sets;

  RuleSet get current => _sets[currentVersion]!;

  /// The ruleset a puzzle was built with (falls back to the current one).
  RuleSet byVersion(int version) => _sets[version] ?? current;

  Iterable<RuleSet> get all => _sets.values;
}
