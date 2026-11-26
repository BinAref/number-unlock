import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/util/json_read.dart';
import 'monetization.dart';
import 'storage.dart';

/// Every ad passes here, wherever it is opened (hint, swap, sixth slot …):
/// a new ad may start only [cooldown] after the previous one closed.
///
/// While the wait runs, ad buttons show the seconds left (listeners are
/// told every second), and tapping one shows them instead of opening
/// anything. The moment the last ad closed is saved (`un.ads`), so closing
/// and reopening the app does not skip the wait.
class AdGate extends ChangeNotifier {
  AdGate({required this.ads, required this.store, this.cooldown = const Duration(seconds: 10), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const String key = 'un.ads';

  final RewardedAdsService ads;
  final KeyValueStore store;
  final Duration cooldown;
  final DateTime Function() _clock;
  DateTime? _lastEnd;
  bool _showing = false;
  Timer? _ticker;
  int _shownSeconds = -1;

  Future<void> load() async {
    final raw = await store.read(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final ms = readInt(readMap(jsonDecode(raw))['lastEnd']);
        if (ms > 0) _lastEnd = DateTime.fromMillisecondsSinceEpoch(ms);
      } on FormatException {
        _lastEnd = null;
      }
    }
    _startTicker();
  }

  /// Time left before the next ad may start (zero when one may start now).
  Duration get remaining {
    final last = _lastEnd;
    if (last == null) return Duration.zero;
    var left = cooldown - _clock().difference(last);
    if (left > cooldown) left = cooldown;
    return left.isNegative ? Duration.zero : left;
  }

  /// Whole seconds left, rounded up (what the buttons show).
  int get secondsLeft => (remaining.inMilliseconds / 1000).ceil();

  /// Whether an ad may start now.
  bool get ready => !_showing && remaining == Duration.zero;

  /// Plays an ad when allowed; returns null — and shows nothing — while the
  /// wait is still running or another ad is on screen.
  Future<AdOutcome?> show(String placement) async {
    if (!ready) return null;
    _showing = true;
    try {
      return await ads.show(placement);
    } finally {
      _showing = false;
      final end = _clock();
      _lastEnd = end;
      await store.write(key, jsonEncode({'lastEnd': end.millisecondsSinceEpoch}));
      _startTicker();
      notifyListeners();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    if (remaining == Duration.zero) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final s = secondsLeft;
      if (s != _shownSeconds) {
        _shownSeconds = s;
        notifyListeners();
      }
      if (s == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
