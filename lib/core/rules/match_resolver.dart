import 'rule_definition.dart';
import 'rule_engine.dart';

/// One match that happened inside the tray.
class MatchStep {
  const MatchStep({required this.rule, required this.start, required this.cells, required this.trayAfter});

  final RuleDefinition rule;

  /// Slot index where the matched group started.
  final int start;

  /// The matched tiles (cell indices), in tray order.
  final List<int> cells;

  /// The tray after the survivors closed ranks.
  final List<int> trayAfter;
}

/// Resolves matches in the tray until none is left.
///
/// After every match the matched tiles vanish, their slots free up, the
/// survivors close ranks in their original order and the tray is checked
/// again, so chained matches resolve one after another. A match only removes
/// tiles — it never creates a new number.
class MatchResolver {
  const MatchResolver(this.rules);

  final BoundRules rules;

  /// Resolves [tray] in place and reports each step (for animations).
  List<MatchStep> resolve(List<int> tray) {
    final steps = <MatchStep>[];
    _run(tray, (hit, cells) {
      steps.add(MatchStep(rule: hit.rule, start: hit.start, cells: cells, trayAfter: List<int>.unmodifiable(tray)));
    });
    return steps;
  }

  /// The same resolution without bookkeeping (solver hot path).
  /// Returns how many tiles were removed.
  int resolveQuietly(List<int> tray) => _run(tray, null);

  int _run(List<int> tray, void Function(MatchHit hit, List<int> cells)? onStep) {
    var removed = 0;
    while (true) {
      final hit = rules.findFirst(tray);
      if (hit == null) return removed;
      final end = hit.start + hit.size;
      if (onStep == null) {
        tray.removeRange(hit.start, end);
      } else {
        final cells = tray.sublist(hit.start, end);
        tray.removeRange(hit.start, end);
        onStep(hit, cells);
      }
      removed += hit.size;
    }
  }
}
