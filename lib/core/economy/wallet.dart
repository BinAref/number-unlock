import '../util/json_read.dart';

enum SpendResult { spent, insufficient, duplicate }

/// The single currency: gold coins.
///
/// Every change carries an operation id and is applied at most once, so a
/// double tap, a retried callback or a replayed reward can never charge or
/// pay twice.
class Wallet {
  Wallet({int coins = 0, Iterable<String> recentOps = const <String>[]})
      : _coins = coins < 0 ? 0 : coins,
        _ops = List<String>.of(recentOps);

  factory Wallet.fromJson(Map<String, Object?> json) =>
      Wallet(coins: readInt(json['coins']), recentOps: readStringList(json['ops']));

  int _coins;
  final List<String> _ops;

  static const int memory = 200;

  int get coins => _coins;

  bool canAfford(int amount) => amount <= _coins;

  bool hasApplied(String opId) => _ops.contains(opId);

  SpendResult spend(int amount, {required String opId}) {
    if (hasApplied(opId)) return SpendResult.duplicate;
    if (amount < 0 || amount > _coins) return SpendResult.insufficient;
    _coins -= amount;
    _remember(opId);
    return SpendResult.spent;
  }

  /// Returns false when this operation was already credited.
  bool credit(int amount, {required String opId}) {
    if (amount <= 0 || hasApplied(opId)) return false;
    _coins += amount;
    _remember(opId);
    return true;
  }

  void _remember(String opId) {
    _ops.add(opId);
    while (_ops.length > memory) {
      _ops.removeAt(0);
    }
  }

  Map<String, Object?> toJson() => {'coins': _coins, 'ops': _ops};
}
