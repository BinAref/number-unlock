import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/util/json_read.dart';

/// One entry of `assets/i18n/languages.json`.
class LanguageInfo {
  const LanguageInfo({required this.code, required this.name, required this.rtl, required this.file, required this.font, required this.plural});

  factory LanguageInfo.fromJson(Map<String, Object?> json) => LanguageInfo(
        code: readString(json['code']),
        name: readString(json['name']),
        rtl: readString(json['dir']) == 'rtl',
        file: readString(json['file']),
        font: readString(json['font']),
        plural: readString(json['plural'], 'oneOther'),
      );

  final String code;

  /// The language's own name (shown in the language picker).
  final String name;
  final bool rtl;
  final String file;
  final String font;

  /// Plural rule id: `arabic`, `oneOther` or `other`.
  final String plural;
}

/// All visible text comes from the language files through keys.
///
/// Adding a language = a new JSON file + one entry in `languages.json`.
class LocalizationService extends ChangeNotifier {
  LocalizationService._(this._bundle, this.languages, this._fallbackCode);

  static const String _dir = 'assets/i18n/';

  static Future<LocalizationService> load({required AssetBundle bundle, String? preferred, Locale? device}) async {
    final registry = readMap(jsonDecode(await bundle.loadString('${_dir}languages.json')));
    final languages = [for (final l in readList(registry['languages'])) LanguageInfo.fromJson(readMap(l))];
    final service = LocalizationService._(bundle, languages, readString(registry['fallback'], 'en'));
    await service._loadFallback();
    final deviceCode = device?.languageCode;
    final code = preferred ?? (languages.any((l) => l.code == deviceCode) ? deviceCode! : service._fallbackCode);
    await service.setLanguage(code, notify: false);
    return service;
  }

  final AssetBundle _bundle;
  final List<LanguageInfo> languages;
  final String _fallbackCode;
  Map<String, String> _strings = const {};
  Map<String, String> _fallback = const {};
  late LanguageInfo current;

  TextDirection get direction => current.rtl ? TextDirection.rtl : TextDirection.ltr;

  Locale get locale => Locale(current.code);

  List<Locale> get supportedLocales => [for (final l in languages) Locale(l.code)];

  Future<Map<String, String>> _readFile(String file) async {
    final map = readMap(jsonDecode(await _bundle.loadString('$_dir$file')));
    return {for (final e in map.entries) e.key: '${e.value}'};
  }

  Future<void> _loadFallback() async {
    final info = languages.firstWhere((l) => l.code == _fallbackCode, orElse: () => languages.first);
    _fallback = await _readFile(info.file);
  }

  Future<void> setLanguage(String code, {bool notify = true}) async {
    final info = languages.firstWhere((l) => l.code == code, orElse: () => languages.firstWhere((l) => l.code == _fallbackCode));
    _strings = info.code == _fallbackCode ? _fallback : await _readFile(info.file);
    current = info;
    if (notify) notifyListeners();
  }

  /// The text for [key], with `{name}` placeholders filled from [args].
  String t(String key, [Map<String, Object?> args = const {}]) {
    var text = _strings[key] ?? _fallback[key];
    if (text == null) {
      assert(() {
        debugPrint('Missing translation: $key');
        return true;
      }());
      text = key;
    }
    if (args.isEmpty) return text;
    for (final e in args.entries) {
      text = text!.replaceAll('{${e.key}}', '${e.value}');
    }
    return text!;
  }

  bool has(String key) => _strings.containsKey(key) || _fallback.containsKey(key);

  /// Picks the plural form of [key] for [count] (`key.one`, `key.other`, …).
  String plural(String key, int count, [Map<String, Object?> args = const {}]) {
    final form = _pluralForm(count);
    final full = {'n': count, ...args};
    if (_strings.containsKey('$key.$form')) return t('$key.$form', full);
    if (_strings.containsKey('$key.other')) return t('$key.other', full);
    return t('$key.$form', full);
  }

  String _pluralForm(int n) {
    switch (current.plural) {
      case 'arabic':
        if (n == 0) return 'zero';
        if (n == 1) return 'one';
        if (n == 2) return 'two';
        final r = n % 100;
        if (r >= 3 && r <= 10) return 'few';
        if (r >= 11 && r <= 99) return 'many';
        return 'other';
      case 'oneOther':
        return n == 1 ? 'one' : 'other';
      default:
        return 'other';
    }
  }
}
