import 'dart:async';

import '../core/util/json_read.dart';

// ---------------------------------------------------------------------------
// Rewarded ads
// ---------------------------------------------------------------------------

enum AdOutcome {
  /// Watched to the end: the reward may be granted.
  rewarded,

  /// Closed before the reward: nothing is granted or counted.
  closedEarly,

  /// No ad could be loaded or shown.
  failed,
}

/// The game asks for a rewarded ad and grants the reward only on
/// [AdOutcome.rewarded]. Swap [MockRewardedAds] for an AdMob-backed class
/// when the store build is ready; nothing else changes.
abstract interface class RewardedAdsService {
  Future<AdOutcome> show(String placement);
}

/// Shows the simulated ad (the UI registers how it is drawn).
typedef MockAdPresenter = Future<AdOutcome> Function(int seconds);

class MockRewardedAds implements RewardedAdsService {
  MockRewardedAds({this.seconds = 3});

  final int seconds;
  MockAdPresenter? presenter;
  bool _showing = false;

  @override
  Future<AdOutcome> show(String placement) async {
    final present = presenter;
    if (present == null || _showing) return AdOutcome.failed;
    _showing = true;
    try {
      return await present(seconds);
    } finally {
      _showing = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

/// A coin pack from `assets/config/store.json`.
class CoinProduct {
  const CoinProduct({
    required this.id,
    required this.coins,
    required this.price,
    required this.chest,
    required this.nameKey,
    this.badge,
    this.bonusPercent = 0,
  });

  factory CoinProduct.fromJson(Map<String, Object?> json) => CoinProduct(
        id: readString(json['id']),
        coins: readInt(json['coins']),
        price: readString(json['price']),
        chest: readString(json['chest'], 'pouch'),
        nameKey: readString(json['nameKey']),
        badge: readStringOrNull(json['badge']),
        bonusPercent: readInt(json['bonusPercent']),
      );

  /// Store product id (Google Play / App Store).
  final String id;
  final int coins;

  /// Display price; the real store price replaces it once connected.
  final String price;

  /// Which chest artwork to draw: pouch, small, large, vault.
  final String chest;
  final String nameKey;
  final String? badge;
  final int bonusPercent;
}

enum PurchaseOutcome { success, cancelled, failed }

/// Coin purchases. Swap [MockPurchases] for a Google Play Billing /
/// StoreKit implementation once the products exist in the consoles.
abstract interface class PurchaseService {
  List<CoinProduct> get products;

  Future<PurchaseOutcome> buy(CoinProduct product);
}

class MockPurchases implements PurchaseService {
  MockPurchases(this.products, {this.delay = const Duration(milliseconds: 900)});

  factory MockPurchases.fromJson(Map<String, Object?> store, {Duration delay = const Duration(milliseconds: 900)}) =>
      MockPurchases([for (final p in readList(store['products'])) CoinProduct.fromJson(readMap(p))], delay: delay);

  @override
  final List<CoinProduct> products;
  final Duration delay;
  bool _busy = false;

  @override
  Future<PurchaseOutcome> buy(CoinProduct product) async {
    if (_busy) return PurchaseOutcome.failed;
    _busy = true;
    try {
      await Future<void>.delayed(delay);
      return PurchaseOutcome.success;
    } finally {
      _busy = false;
    }
  }
}
