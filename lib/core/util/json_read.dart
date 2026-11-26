/// Small, forgiving readers for decoded JSON maps (pure Dart).
library;

int readInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? readIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

double readDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

bool readBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true' || value == '1';
  return fallback;
}

String readString(Object? value, [String fallback = '']) => value is String ? value : fallback;

String? readStringOrNull(Object? value) => value is String ? value : null;

Map<String, Object?> readMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return const <String, Object?>{};
}

List<Object?> readList(Object? value) => value is List ? value.cast<Object?>() : const <Object?>[];

List<int> readIntList(Object? value) => [for (final v in readList(value)) readInt(v)];

List<String> readStringList(Object? value) => [for (final v in readList(value)) if (v is String) v];

List<double> readDoubleList(Object? value) => [for (final v in readList(value)) readDouble(v)];
