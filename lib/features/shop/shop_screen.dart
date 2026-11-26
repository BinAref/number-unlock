import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/audio_service.dart';
import '../../services/monetization.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../common/page_frame.dart';

/// The treasury: coin packs as chests of growing size on stone plinths.
/// Prices and amounts come from `store.json` (later: the store itself).
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String? _buying;
  String? _opened;

  Future<void> _buy(CoinProduct p) async {
    if (_buying != null) return;
    final s = Services.of(context, listen: false);
    final i18n = s.i18n;
    final coins = i18n.plural('coins.count', p.coins);
    final ok = await showStoneDialog<bool>(
      context,
      title: i18n.t('shop.confirmTitle'),
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(i18n.t('shop.confirmBody', {'coins': coins, 'price': p.price}), textAlign: TextAlign.center, style: UiText.style(context, size: 17)),
        const SizedBox(height: 6),
        Text(i18n.t('shop.testMode'), textAlign: TextAlign.center, style: UiText.style(context, size: 12, color: s.theme.tokens.color('text.muted'))),
        const SizedBox(height: 16),
        StoneButton(label: i18n.t('shop.buy'), primary: true, onTap: () => Navigator.pop(context, true)),
        const SizedBox(height: 8),
        StoneButton(label: i18n.t('common.cancel'), dense: true, onTap: () => Navigator.pop(context, false)),
      ]),
    );
    if (ok != true || !mounted) {
      if (mounted && ok == false) showToast(context, i18n.t('shop.cancelled'));
      return;
    }
    setState(() => _buying = p.id);
    final outcome = await s.purchases.buy(p);
    if (!mounted) return;
    setState(() => _buying = null);
    switch (outcome) {
      case PurchaseOutcome.success:
        s.player.credit(p.coins, 'purchase:${p.id}:${DateTime.now().microsecondsSinceEpoch}');
        s.audio.play(Sfx.chest);
        s.audio.play(Sfx.coin);
        setState(() => _opened = p.id);
        showToast(context, i18n.t('shop.success'), glyph: Glyph.check);
      case PurchaseOutcome.cancelled:
        showToast(context, i18n.t('shop.cancelled'));
      case PurchaseOutcome.failed:
        showToast(context, i18n.t('shop.failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final i18n = s.i18n;
    final t = s.theme.tokens;
    return PageFrame(
      title: i18n.t('shop.title'),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(i18n.t('shop.balance'), style: UiText.style(context, size: 16)),
          const SizedBox(width: 10),
          const CoinCounter(),
        ]),
        const SizedBox(height: 6),
        Text(i18n.t('shop.useFor'), textAlign: TextAlign.center, style: UiText.style(context, size: 13, color: t.color('text.muted'))),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 420 ? 2 : 2;
          final w = (c.maxWidth - 14 * (cols - 1)) / cols;
          final products = s.purchases.products;
          return Wrap(spacing: 14, runSpacing: 14, children: [
            for (var i = 0; i < products.length; i++)
              SizedBox(width: w, child: _ChestCard(product: products[i], index: i, busy: _buying == products[i].id, opened: _opened == products[i].id, onBuy: () => _buy(products[i]))),
          ]);
        }),
        const SizedBox(height: 10),
        Text(i18n.t('shop.testMode'), textAlign: TextAlign.center, style: UiText.style(context, size: 12, color: t.color('text.muted'))),
      ]),
    );
  }
}

class _ChestCard extends StatelessWidget {
  const _ChestCard({required this.product, required this.index, required this.busy, required this.opened, required this.onBuy});

  final CoinProduct product;
  final int index;
  final bool busy;
  final bool opened;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final i18n = s.i18n;
    final t = s.theme.tokens;
    final scale = 0.7 + 0.1 * index;
    return StonePanel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      border: 10,
      seed: 40 + index,
      child: Column(children: [
        if (product.badge != null)
          Text(i18n.t('shop.${product.badge}'), style: UiText.style(context, size: 12, color: t.color('text.accent')))
        else
          const SizedBox(height: 15),
        SizedBox(
          height: 96,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: opened ? 1 : 0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (context, lid, _) => Loop(
              period: const Duration(seconds: 3),
              builder: (context, ph) => CustomPaint(
                size: Size(110 * scale, 96 * scale),
                painter: ChestPainter(t, lid: math.max(lid, 0.08 + 0.05 * math.sin(ph * math.pi * 2)), sparkle: ph),
              ),
            ),
          ),
        ),
        Text(i18n.t(product.nameKey), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
        Text(i18n.plural('coins.count', product.coins), style: UiText.numbers(context, size: 18, color: t.color('text.accent'))),
        if (product.bonusPercent > 0) Text(i18n.t('shop.bonus', {'n': product.bonusPercent}), style: UiText.numbers(context, size: 12, color: t.color('ui.success'))),
        const SizedBox(height: 8),
        StoneButton(label: busy ? i18n.t('common.loading') : product.price, primary: true, dense: true, enabled: !busy, onTap: onBuy),
      ]),
    );
  }
}
