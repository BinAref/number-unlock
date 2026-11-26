/// A numbered piece of the puzzle: its value (1..9) and its colour slot.
///
/// The colour is only a slot index. The active visual theme decides how each
/// slot looks, so the same puzzle can be painted by any theme.
class TileSpec {
  const TileSpec(this.value, this.color);

  final int value;
  final int color;

  static const int minValue = 1;
  static const int maxValue = 9;

  /// Two characters: the digit and a colour letter (`a` = slot 0).
  String encode() => '$value${String.fromCharCode(97 + color)}';

  static TileSpec decode(String code) {
    if (code.length != 2) throw FormatException('Bad tile code "$code"');
    final value = code.codeUnitAt(0) - 48;
    final color = code.codeUnitAt(1) - 97;
    if (value < minValue || value > maxValue || color < 0 || color > 25) {
      throw FormatException('Bad tile code "$code"');
    }
    return TileSpec(value, color);
  }

  @override
  bool operator ==(Object other) => other is TileSpec && other.value == value && other.color == color;

  @override
  int get hashCode => value * 64 + color;

  @override
  String toString() => 'TileSpec($value, c$color)';
}
