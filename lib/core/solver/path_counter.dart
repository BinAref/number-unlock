import 'dart:typed_data';

import '../random/seeded_random.dart' show mul32;
import 'solver_context.dart';

/// Counts winning orders of picks exactly (memoised over game states).
///
/// The count shrinks as a puzzle tightens; zero is a proof that no order
/// works with that many slots. Used to steer level hardening and as a
/// difficulty signal ("how many correct paths exist").
class PathCounter {
  PathCounter(this.ctx, {required this.capacity, this.stateBudget = 150000})
      : _keyLength = ctx.keyLengthFor(capacity) {
    _alloc(1024);
  }

  final SolverContext ctx;
  final int capacity;
  final int stateBudget;
  final int _keyLength;

  late Uint32List _keys;
  late Float64List _values;
  late Uint8List _used;
  late int _mask;
  int _size = 0;
  bool _overflow = false;

  /// States visited by the last count.
  int get statesVisited => _size;

  /// Winning orders from the start, or null when the budget ran out.
  double? countFromStart() {
    _overflow = false;
    final removed = Uint32List(ctx.wordCount);
    final result = _count(removed, <int>[], ctx.layout.tileCount, Uint32List(_keyLength));
    return _overflow ? null : result;
  }

  double? _count(Uint32List removed, List<int> tray, int remaining, Uint32List key) {
    if (remaining == 0) return tray.isEmpty ? 1.0 : 0.0;
    ctx.encodeKey(key, removed, tray);
    final cached = _get(key);
    if (cached != null) return cached;
    if (_size >= stateBudget) {
      _overflow = true;
      return null;
    }
    final limit = capacity - 1;
    var total = 0.0;
    final childKey = Uint32List(_keyLength);
    for (final c in ctx.tiles) {
      if (SolverContext.isSet(removed, c) || !ctx.topology.isOpenInMask(c, removed)) continue;
      final child = List<int>.of(tray)..add(c);
      ctx.resolver.resolveQuietly(child);
      if (child.length > limit) continue;
      SolverContext.setBit(removed, c);
      final sub = _count(removed, child, remaining - 1, childKey);
      SolverContext.clearBit(removed, c);
      if (sub == null) return null;
      total += sub;
    }
    ctx.encodeKey(key, removed, tray);
    _put(key, total);
    return total;
  }

  void _alloc(int capacity) {
    _keys = Uint32List(capacity * _keyLength);
    _values = Float64List(capacity);
    _used = Uint8List(capacity);
    _mask = capacity - 1;
  }

  int _hash(Uint32List key) {
    var h = 0x811C9DC5;
    for (var i = 0; i < _keyLength; i++) {
      h = mul32(h ^ key[i], 0x01000193);
    }
    h ^= h >>> 15;
    return h & 0xFFFFFFFF;
  }

  bool _eq(int slot, Uint32List key) {
    final base = slot * _keyLength;
    for (var i = 0; i < _keyLength; i++) {
      if (_keys[base + i] != key[i]) return false;
    }
    return true;
  }

  double? _get(Uint32List key) {
    var slot = _hash(key) & _mask;
    while (_used[slot] != 0) {
      if (_eq(slot, key)) return _values[slot];
      slot = (slot + 1) & _mask;
    }
    return null;
  }

  void _put(Uint32List key, double value) {
    if ((_size + 1) * 10 > (_mask + 1) * 7) _grow();
    var slot = _hash(key) & _mask;
    while (_used[slot] != 0) {
      if (_eq(slot, key)) {
        _values[slot] = value;
        return;
      }
      slot = (slot + 1) & _mask;
    }
    _used[slot] = 1;
    _values[slot] = value;
    final base = slot * _keyLength;
    for (var i = 0; i < _keyLength; i++) {
      _keys[base + i] = key[i];
    }
    _size++;
  }

  void _grow() {
    final oldKeys = _keys;
    final oldValues = _values;
    final oldUsed = _used;
    final oldCapacity = _mask + 1;
    _alloc(oldCapacity * 2);
    _size = 0;
    final tmp = Uint32List(_keyLength);
    for (var s = 0; s < oldCapacity; s++) {
      if (oldUsed[s] == 0) continue;
      final base = s * _keyLength;
      for (var i = 0; i < _keyLength; i++) {
        tmp[i] = oldKeys[base + i];
      }
      _put(tmp, oldValues[s]);
    }
  }
}
