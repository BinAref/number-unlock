import '../random/seeded_random.dart';
import 'arrows.dart';
import 'tile_spec.dart';

/// The fixed starting arrangement of a puzzle: a rows × cols grid whose cells
/// hold a tile or are empty from the start ("voids"), each tile's arrows, and
/// which tiles are open from the start.
///
/// Cells are indexed row-major; row 0 is the top row and `rows - 1` the
/// bottom row.
///
/// Arrow boards ([hasArrows]) follow the arrow rule: extracting a tile opens
/// only the locked tiles its arrows point at, and a tile with no arrows (a
/// star) opens nothing. Boards without arrows are the first, matching-only
/// boards: every tile is open from the start and nothing is drawn on them.
class PuzzleLayout {
  PuzzleLayout({
    required this.rows,
    required this.cols,
    required List<TileSpec?> cells,
    required List<int> dirs,
    required List<bool> open,
    required this.hasArrows,
  })  : cells = List<TileSpec?>.unmodifiable(cells),
        dirs = List<int>.unmodifiable(_dirsFor(cells, dirs)),
        openAtStart = List<bool>.unmodifiable(_openFor(cells, open)),
        tileCount = _countTiles(cells) {
    if (rows < 1 || cols < 1 || cells.length != rows * cols) {
      throw ArgumentError('A ${rows}x$cols layout needs ${rows * cols} cells, got ${cells.length}.');
    }
  }

  /// A board without the arrow rule: every tile is open from the start.
  factory PuzzleLayout.allOpen({required int rows, required int cols, required List<TileSpec?> cells}) => PuzzleLayout(
        rows: rows,
        cols: cols,
        cells: cells,
        dirs: List<int>.filled(cells.length, Arrows.none),
        open: List<bool>.filled(cells.length, true),
        hasArrows: false,
      );

  static List<int> _dirsFor(List<TileSpec?> cells, List<int> dirs) {
    if (dirs.length != cells.length) throw ArgumentError('Expected ${cells.length} arrow masks, got ${dirs.length}.');
    return [for (var i = 0; i < cells.length; i++) cells[i] == null ? Arrows.none : dirs[i] & Arrows.all];
  }

  static List<bool> _openFor(List<TileSpec?> cells, List<bool> open) {
    if (open.length != cells.length) throw ArgumentError('Expected ${cells.length} open flags, got ${open.length}.');
    return [for (var i = 0; i < cells.length; i++) cells[i] != null && open[i]];
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

  /// Each cell's arrow mask ([Arrows]); always [Arrows.none] for voids.
  final List<int> dirs;

  /// Tiles open from the very start (false for voids).
  final List<bool> openAtStart;

  /// Whether the arrow rule is shown and applies (false: all tiles open).
  final bool hasArrows;
  final int tileCount;

  static const String voidCode = '..';
  static const String voidMark = '.';

  int get cellCount => rows * cols;
  int get voidCount => cellCount - tileCount;

  int indexOf(int row, int col) => row * cols + col;
  int rowOf(int index) => index ~/ cols;
  int colOf(int index) => index % cols;
  bool isTile(int index) => cells[index] != null;
  TileSpec specOf(int index) => cells[index]!;
  bool isBottomRow(int index) => rowOf(index) == rows - 1;

  /// A tile with no arrows on an arrow board: it opens nothing.
  bool isStar(int index) => hasArrows && isTile(index) && dirs[index] == Arrows.none;

  Iterable<int> get tileIndices sync* {
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] != null) yield i;
    }
  }

  /// The same board with other numbers in its cells (arrows and openings
  /// stay with the cells, so the unlocking structure is untouched).
  PuzzleLayout withCells(List<TileSpec?> next) =>
      PuzzleLayout(rows: rows, cols: cols, cells: next, dirs: dirs, open: openAtStart, hasArrows: hasArrows);

  String encodeCells() {
    final b = StringBuffer();
    for (final c in cells) {
      b.write(c == null ? voidCode : c.encode());
    }
    return b.toString();
  }

  /// One hex digit per cell (the arrow mask), `.` for voids.
  String encodeDirs() {
    final b = StringBuffer();
    for (var i = 0; i < cells.length; i++) {
      b.write(cells[i] == null ? voidMark : dirs[i].toRadixString(16));
    }
    return b.toString();
  }

  /// `1` for a tile open from the start, `0` for a locked one, `.` for voids.
  String encodeOpen() {
    final b = StringBuffer();
    for (var i = 0; i < cells.length; i++) {
      b.write(cells[i] == null ? voidMark : (openAtStart[i] ? '1' : '0'));
    }
    return b.toString();
  }

  /// Decodes [code] (two characters per cell). With neither [dirs] nor
  /// [open], the board has no arrows and every tile is open; [open] alone
  /// defaults to the bottom row when only [dirs] is given.
  static PuzzleLayout decode(int rows, int cols, String code, {String? dirs, String? open, bool? arrows}) {
    final n = rows * cols;
    if (code.length != n * 2) {
      throw FormatException('Layout code has ${code.length} chars, expected ${n * 2}.');
    }
    final cells = <TileSpec?>[];
    for (var i = 0; i < code.length; i += 2) {
      final part = code.substring(i, i + 2);
      cells.add(part == voidCode ? null : TileSpec.decode(part));
    }
    if (dirs == null && open == null) return PuzzleLayout.allOpen(rows: rows, cols: cols, cells: cells);
    final masks = List<int>.filled(n, Arrows.none);
    if (dirs != null) {
      if (dirs.length != n) throw FormatException('Arrow code has ${dirs.length} chars, expected $n.');
      for (var i = 0; i < n; i++) {
        final ch = dirs[i];
        if (ch == voidMark) continue;
        final v = int.tryParse(ch, radix: 16);
        if (v == null) throw FormatException('Bad arrow mask "$ch" at cell $i.');
        masks[i] = v;
      }
    }
    final flags = List<bool>.generate(n, (i) => i ~/ cols == rows - 1);
    if (open != null) {
      if (open.length != n) throw FormatException('Open code has ${open.length} chars, expected $n.');
      for (var i = 0; i < n; i++) {
        flags[i] = open[i] == '1';
      }
    }
    return PuzzleLayout(rows: rows, cols: cols, cells: cells, dirs: masks, open: flags, hasArrows: arrows ?? dirs != null);
  }

  /// A stable 32-bit fingerprint (identical on every platform) covering the
  /// numbers, the arrows and the opening tiles.
  int fingerprint() {
    var h = 0x811C9DC5;
    h = mul32(h ^ rows, 0x01000193);
    h = mul32(h ^ cols, 0x01000193);
    h = mul32(h ^ (hasArrows ? 1 : 0), 0x01000193);
    for (final unit in '${encodeCells()}|${encodeDirs()}|${encodeOpen()}'.codeUnits) {
      h = mul32(h ^ unit, 0x01000193);
    }
    return h & 0xFFFFFFFF;
  }

  @override
  bool operator ==(Object other) =>
      other is PuzzleLayout &&
      other.rows == rows &&
      other.cols == cols &&
      other.hasArrows == hasArrows &&
      other.encodeCells() == encodeCells() &&
      other.encodeDirs() == encodeDirs() &&
      other.encodeOpen() == encodeOpen();

  @override
  int get hashCode => fingerprint();
}
