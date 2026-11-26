import '../model/tile_spec.dart';
import '../util/json_read.dart';

/// What a rule demands of the values in a matching group.
enum ValueCondition { any, allEqual, sum }

/// What a rule demands of the colours in a matching group.
enum ColorCondition { any, allEqual, allDistinct }

/// Whether the group's values must follow an order (left to right).
enum OrderCondition { any, ascending, descending }

/// How the group's tiles must sit inside the tray.
enum AdjacencyCondition { contiguous }

/// One matching rule, described entirely as data
/// (see `assets/config/rules.json`).
///
/// New rules are added by adding entries there, without touching the game
/// logic: the group size, value/sum/colour/order conditions, priority, the
/// on/off switch and the modes or levels where a rule applies are all fields.
class RuleDefinition {
  const RuleDefinition({
    required this.id,
    this.enabled = true,
    this.priority = 0,
    this.size = 2,
    this.adjacency = AdjacencyCondition.contiguous,
    this.value = ValueCondition.any,
    this.sumTarget = 10,
    this.color = ColorCondition.any,
    this.order = OrderCondition.any,
    this.modes = const <String>{'levels', 'endless'},
    this.minLevel = 1,
    this.maxLevel,
    this.demo = const <TileSpec>[],
  });

  factory RuleDefinition.fromJson(Map<String, Object?> json) {
    return RuleDefinition(
      id: readString(json['id']),
      enabled: readBool(json['enabled'], true),
      priority: readInt(json['priority']),
      size: readInt(json['size'], 2),
      adjacency: _byName(AdjacencyCondition.values, json['adjacency'], AdjacencyCondition.contiguous),
      value: _byName(ValueCondition.values, json['value'], ValueCondition.any),
      sumTarget: readInt(json['sum'], 10),
      color: _byName(ColorCondition.values, json['color'], ColorCondition.any),
      order: _byName(OrderCondition.values, json['order'], OrderCondition.any),
      modes: readStringList(json['modes']).isEmpty
          ? const <String>{'levels', 'endless'}
          : readStringList(json['modes']).toSet(),
      minLevel: readInt(json['minLevel'], 1),
      maxLevel: readIntOrNull(json['maxLevel']),
      demo: [for (final code in readStringList(json['demo'])) TileSpec.decode(code)],
    );
  }

  /// Stable identifier; also the localisation key stem (`rule.<id>.title`).
  final String id;
  final bool enabled;

  /// Higher priority rules are checked first.
  final int priority;

  /// How many tiles the group holds.
  final int size;
  final AdjacencyCondition adjacency;
  final ValueCondition value;
  final int sumTarget;
  final ColorCondition color;
  final OrderCondition order;

  /// Play modes where the rule is active (`levels`, `endless`).
  final Set<String> modes;
  final int minLevel;
  final int? maxLevel;

  /// Example tiles shown by the instructions page.
  final List<TileSpec> demo;

  bool get usesColor => color != ColorCondition.any;

  bool availableIn(String mode, {int? level}) {
    if (!enabled || !modes.contains(mode)) return false;
    if (level == null) return true;
    if (level < minLevel) return false;
    final max = maxLevel;
    return max == null || level <= max;
  }

  /// Whether [group] (tiles in tray order) satisfies this rule.
  bool test(List<TileSpec> group) {
    if (group.length != size || size < 2) return false;
    switch (value) {
      case ValueCondition.any:
        break;
      case ValueCondition.allEqual:
        final v = group.first.value;
        for (final t in group) {
          if (t.value != v) return false;
        }
      case ValueCondition.sum:
        var s = 0;
        for (final t in group) {
          s += t.value;
        }
        if (s != sumTarget) return false;
    }
    switch (color) {
      case ColorCondition.any:
        break;
      case ColorCondition.allEqual:
        final c = group.first.color;
        for (final t in group) {
          if (t.color != c) return false;
        }
      case ColorCondition.allDistinct:
        final seen = <int>{};
        for (final t in group) {
          if (!seen.add(t.color)) return false;
        }
    }
    switch (order) {
      case OrderCondition.any:
        break;
      case OrderCondition.ascending:
        for (var i = 1; i < group.length; i++) {
          if (group[i].value <= group[i - 1].value) return false;
        }
      case OrderCondition.descending:
        for (var i = 1; i < group.length; i++) {
          if (group[i].value >= group[i - 1].value) return false;
        }
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'enabled': enabled,
        'priority': priority,
        'size': size,
        'adjacency': adjacency.name,
        'value': value.name,
        'sum': sumTarget,
        'color': color.name,
        'order': order.name,
        'modes': modes.toList(),
        'minLevel': minLevel,
        if (maxLevel != null) 'maxLevel': maxLevel,
        'demo': [for (final t in demo) t.encode()],
      };
}

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
