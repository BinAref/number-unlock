/// The receiving slots above the board.
///
/// Holds extracted tiles (by cell index) in the order they were picked. A new
/// tile always lands in the first free slot; after a match the survivors close
/// ranks while keeping their relative order. Compaction happens here only —
/// never on the board.
class ReceptionTray {
  ReceptionTray({required int capacity, Iterable<int> items = const <int>[]})
      : _capacity = capacity,
        _items = List<int>.of(items) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  int _capacity;
  final List<int> _items;

  int get capacity => _capacity;

  List<int> get items => List<int>.unmodifiable(_items);

  /// Mutable view for the match resolver.
  List<int> get raw => _items;

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool get hasFreeSlot => _items.length < _capacity;

  /// Puts a tile in the first free slot and returns that slot's index.
  int place(int cell) {
    if (!hasFreeSlot) throw StateError('No free reception slot.');
    _items.add(cell);
    return _items.length - 1;
  }

  void swap(int a, int b) {
    final t = _items[a];
    _items[a] = _items[b];
    _items[b] = t;
  }

  void growTo(int capacity) {
    if (capacity > _capacity) _capacity = capacity;
  }
}
