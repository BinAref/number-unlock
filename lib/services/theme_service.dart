import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/util/json_read.dart';

Color _parseColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFFFF00FF);
}

/// The look of one theme, read by key (`sky.top`, `gold.base` …).
///
/// Painters never hold a colour of their own: everything comes from the
/// theme files, so a new theme is just a new JSON file.
class ThemeTokens {
  ThemeTokens._(this.id, this.brightness, this._colors, this._numbers, this._palettes);

  factory ThemeTokens.fromJson(Map<String, Object?> json, Brightness brightness) => ThemeTokens._(
        readString(json['id']),
        brightness,
        {for (final e in readMap(json['colors']).entries) e.key: _parseColor('${e.value}')},
        {for (final e in readMap(json['numbers']).entries) e.key: readDouble(e.value)},
        {
          for (final e in readMap(json['palettes']).entries)
            e.key: [for (final c in readStringList(e.value)) _parseColor(c)],
        },
      );

  final String id;
  final Brightness brightness;
  final Map<String, Color> _colors;
  final Map<String, double> _numbers;
  final Map<String, List<Color>> _palettes;

  static const Color _missing = Color(0xFFFF00FF);

  Color color(String key) {
    final c = _colors[key];
    assert(c != null || _warn(key));
    return c ?? _missing;
  }

  double number(String key, [double fallback = 0]) => _numbers[key] ?? fallback;

  List<Color> palette(String key) => _palettes[key] ?? const [_missing];

  /// The colour of tile colour slot [slot].
  Color tile(int slot) {
    final p = palette('tiles');
    return p[slot % p.length];
  }

  static bool _warn(String key) {
    debugPrint('Missing theme token: $key');
    return true;
  }
}

/// Shared, theme-independent design numbers (`assets/design/tokens.json`).
class DesignTokens {
  DesignTokens(this._values);

  static Future<DesignTokens> load(AssetBundle bundle) async =>
      DesignTokens(readMap(jsonDecode(await bundle.loadString('assets/design/tokens.json'))));

  final Map<String, Object?> _values;

  double value(String path, [double fallback = 0]) {
    final parts = path.split('.');
    Object? node = _values;
    for (final p in parts) {
      if (node is Map) {
        node = node[p];
      } else {
        return fallback;
      }
    }
    return readDouble(node, fallback);
  }

  /// A motion duration (`motion.tileFly` …), shortened when effects are reduced.
  Duration motion(String key, {bool reduced = false}) {
    final ms = value('motion.$key', 300);
    final scale = reduced ? value('motion.reducedScale', 0.5) : 1.0;
    return Duration(milliseconds: (ms * scale).round());
  }
}

class ThemeInfo {
  const ThemeInfo({required this.id, required this.nameKey, required this.tokens});

  final String id;
  final String nameKey;
  final ThemeTokens tokens;
}

/// The available themes and which one is showing (`system` follows the
/// device's light or dark mode).
class ThemeService extends ChangeNotifier {
  ThemeService._(this.themes, this._systemLight, this._systemDark, this._selection, this._platform);

  static const String system = 'system';

  static Future<ThemeService> load({required AssetBundle bundle, String? selection, Brightness? platform}) async {
    final registry = readMap(jsonDecode(await bundle.loadString('assets/themes/themes.json')));
    final themes = <ThemeInfo>[];
    for (final entry in readList(registry['themes'])) {
      final e = readMap(entry);
      final brightness = readString(e['brightness']) == 'dark' ? Brightness.dark : Brightness.light;
      final json = readMap(jsonDecode(await bundle.loadString('assets/themes/${readString(e['file'])}')));
      themes.add(ThemeInfo(id: readString(e['id']), nameKey: readString(e['nameKey']), tokens: ThemeTokens.fromJson(json, brightness)));
    }
    return ThemeService._(
      themes,
      readString(registry['systemLight'], themes.first.id),
      readString(registry['systemDark'], themes.last.id),
      selection ?? readString(registry['default'], system),
      platform ?? Brightness.light,
    );
  }

  final List<ThemeInfo> themes;
  final String _systemLight;
  final String _systemDark;
  String _selection;
  Brightness _platform;

  String get selection => _selection;

  String get activeId => _selection == system ? (_platform == Brightness.dark ? _systemDark : _systemLight) : _selection;

  ThemeTokens get tokens => (themes.firstWhere((t) => t.id == activeId, orElse: () => themes.first)).tokens;

  void select(String id) {
    if (id == _selection) return;
    _selection = id;
    notifyListeners();
  }

  void platformChanged(Brightness b) {
    if (b == _platform) return;
    _platform = b;
    if (_selection == system) notifyListeners();
  }
}
