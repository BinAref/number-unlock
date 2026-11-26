import 'dart:typed_data';

import '../random/seeded_random.dart' show mul32;

/// An exact hash set of fixed-length keys made of unsigned 32-bit words.
///
/// Open addressing over typed arrays: compact, allocation-free lookups and
/// identical behaviour on the Dart VM and on the web.
class StateSet {
  StateSet(this.keyLength, {int initialCapacity = 1024}) {
    if (keyLength < 1) throw ArgumentError.value(keyLength, 'keyLength');
    var cap = 16;
    while (cap < initialCapacity) {
      cap <<= 1;
    }
    _alloc(cap);
  }

  final int keyLength;
  late Uint32List _keys;
  late Uint8List _used;
  late int _mask;
  int _size = 0;

  int get length => _size;

  void _alloc(int capacity) {
    _keys = Uint32List(capacity * keyLength);
    _used = Uint8List(capacity);
    _mask = capacity - 1;
  }

  int _hash(Uint32List key) {
    var h = 0x811C9DC5;
    for (var i = 0; i < keyLength; i++) {
      h = mul32(h ^ key[i], 0x01000193);
    }
    h ^= h >>> 15;
    h = mul32(h, 0x2C1B3C6D);
    h ^= h >>> 12;
    return h & 0xFFFFFFFF;
  }

  bool _equalsAt(int slot, Uint32List key) {
    final base = slot * keyLength;
    for (var i = 0; i < keyLength; i++) {
      if (_keys[base + i] != key[i]) return false;
    }
    return true;
  }

  bool contains(Uint32List key) {
    var slot = _hash(key) & _mask;
    while (_used[slot] != 0) {
      if (_equalsAt(slot, key)) return true;
      slot = (slot + 1) & _mask;
    }
    return false;
  }

  /// Adds [key]; returns false when it was already present.
  bool add(Uint32List key) {
    if ((_size + 1) * 10 > (_mask + 1) * 7) _grow();
    var slot = _hash(key) & _mask;
    while (_used[slot] != 0) {
      if (_equalsAt(slot, key)) return false;
      slot = (slot + 1) & _mask;
    }
    _used[slot] = 1;
    final base = slot * keyLength;
    for (var i = 0; i < keyLength; i++) {
      _keys[base + i] = key[i];
    }
    _size++;
    return true;
  }

  void _grow() {
    final oldKeys = _keys;
    final oldUsed = _used;
    final oldCapacity = _mask + 1;
    _alloc(oldCapacity * 2);
    _size = 0;
    final tmp = Uint32List(keyLength);
    for (var s = 0; s < oldCapacity; s++) {
      if (oldUsed[s] == 0) continue;
      final base = s * keyLength;
      for (var i = 0; i < keyLength; i++) {
        tmp[i] = oldKeys[base + i];
      }
      add(tmp);
    }
  }

  void clear() {
    _alloc(16);
    _size = 0;
  }
}
