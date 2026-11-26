import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/monetization.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';

/// Connects the mock rewarded ad to a full-screen test advert.
void installMockAds(AppServices services, GlobalKey<NavigatorState> navigator) {
  final ads = services.ads;
  if (ads is! MockRewardedAds) return;
  ads.presenter = (seconds) async {
    final context = navigator.currentContext;
    if (context == null) return AdOutcome.failed;
    final outcome = await showGeneralDialog<AdOutcome>(
      context: context,
      barrierDismissible: false,
      barrierColor: alpha(services.theme.tokens.color('ui.overlay'), 0.92),
      pageBuilder: (context, _, __) => _MockAd(seconds: seconds),
    );
    return outcome ?? AdOutcome.closedEarly;
  };
}

class _MockAd extends StatefulWidget {
  const _MockAd({required this.seconds});

  final int seconds;

  @override
  State<_MockAd> createState() => _MockAdState();
}

class _MockAdState extends State<_MockAd> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        timer.cancel();
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, AdOutcome.rewarded);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Plaque(s.i18n.t('ads.title')),
              const SizedBox(height: 20),
              SizedBox(width: 160, height: 160, child: Loop(period: const Duration(seconds: 3), builder: (context, ph) => CustomPaint(painter: CrystalPainter(t, ph)))),
              const SizedBox(height: 16),
              Text(s.i18n.t('ads.testMode'), textAlign: TextAlign.center, style: UiText.style(context, size: 14, color: t.color('text.muted'))),
              const SizedBox(height: 10),
              Text(_left > 0 ? s.i18n.t('ads.countdown', {'n': _left}) : s.i18n.t('ads.watched'), style: UiText.style(context, size: 20, color: t.color('text.accent'))),
            ]),
          ),
          PositionedDirectional(
            top: 12,
            end: 12,
            child: Pressable(
              onTap: () => Navigator.pop(context, _left <= 0 ? AdOutcome.rewarded : AdOutcome.closedEarly),
              semantics: s.i18n.t('ads.close'),
              child: Padding(padding: const EdgeInsets.all(8), child: GlyphIcon(Glyph.close, size: 26, color: t.color('text.muted'))),
            ),
          ),
        ]),
      ),
    );
  }
}
