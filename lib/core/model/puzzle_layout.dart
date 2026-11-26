import '../random/seeded_random.dart';
import 'tile_spec.dart';

/// The fixed starting arrangement of a puzzle: a rows × cols grid whose cells
/// hold a tile or are empty from the start ("voids").
///
/// Cells are indexed row-major; row 0 is the top row and `rows - 1` is the
/// bottom row, whose tiles start open.
class PuzzleLayout {
  PuzzleLayout({required this.rows, required this.cols, required List<TileSpec?> cells})
      : cells = List<TileSpec?>.unmodifiable(cells),
        tileCount = _countTiles(cells) {
    if (rows < 1 || cols < 1 || cells.length != rows * cols) {
      throw ArgumentError('A ${rows}x$cols layout needs ${rows * cols} cells, got ${cells.length}.');
    }
  }

  static int _countTiles(List<TileSpec?> cells) {
    var n = 0;
    for (final c in cells) {
      if (c != null) n++;
    }
    return n;
  }

  final int rows;
  final int cols;
  final List<TileSpec?> cells;
  final int tileCount;

  static const String voidCode = '..';

  int get cellCount => rows * cols;
  int get voidCount => cellCount - tileCount;

  int indexOf(int row, int col) => row * cols + col;
  int rowOf(int index) => index ~/ cols;
  int colOf(int index) => index % cols;
  bool isTile(int index) => cells[index] != null;
  TileSpec specOf(int index) => cells[index]!;
  bool isBottomRow(int index) => rowOf(index) == rows - 1;

  Iterable<int> get tileIndices sync* {
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] != null) yield i;
    }
  }

  String encodeCells() {
    final b = StringBuffer();
    for (final c in cells) {
      b.write(c == null ? voidCode : c.encode());
    }
    return b.toString();
  }

  static PuzzleLayout decode(int rows, int cols, String code) {
    if (code.length != rows * cols * 2) {
      throw FormatException('Layout code has ${code.length} chars, expected ${rows * cols * 2}.');
    }
    final cells = <TileSpec?>[];
    for (var i = 0; i < code.length; i += 2) {
      final part = code.substring(i, i + 2);
      cells.add(part == voidCode ? null : TileSpec.decode(part));
    }
    return PuzzleLayout(rows: rows, cols: cols, cells: cells);
  }

  /// A stable 32-bit fingerprint (identical on every platform).
  int fingerprint() {
    var h = 0x811C9DC5;
    h = mul32(h ^ rows, 0x01000193);
    h = mul32(h ^ cols, 0x01000193);
    for (final unit in encodeCells().codeUnits) {
      h = mul32(h ^ unit, 0x01000193);
    }
    return h & 0xFFFFFFFF;
  }

  @override
  bool operator ==(Object other) =>
      other is PuzzleLayout && other.rows == rows && other.cols == cols && other.encodeCells() == encodeCells();

  @override
  int get hashCode => fingerprint();
}
