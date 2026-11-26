import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/audio_service.dart';
import '../../services/theme_service.dart';
import 'glyphs.dart';
import 'paint_kit.dart';

/// Text styles: the current language's font, theme colours, soft shadow.
class UiText {
  const UiText._();

  static TextStyle style(BuildContext context, {double size = 16, FontWeight weight = FontWeight.w700, Color? color, bool shadow = true, String? family}) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    return TextStyle(
      fontFamily: family ?? s.i18n.current.font,
      fontFamilyFallback: const ['Cairo', 'NunitoSans'],
      fontSize: size,
      fontWeight: weight,
      color: color ?? t.color('text.onStone'),
      height: 1.2,
      shadows: shadow ? [Shadow(color: alpha(t.color('text.shadow'), 0.85), blurRadius: 3, offset: const Offset(0, 1.5))] : null,
    );
  }

  /// Digits (tiles, counters) always use the same clear face.
  static TextStyle numbers(BuildContext context, {double size = 16, Color? color, bool shadow = true}) =>
      style(context, size: size, color: color, shadow: shadow, family: 'NunitoSans');

  static TextStyle display(BuildContext context, {double size = 30, Color? color}) =>
      style(context, size: size, color: color, family: 'CinzelDecorative', weight: FontWeight.w900);
}

/// Shrinks a little while pressed; plays the tap sound.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.enabled = true, this.sound = Sfx.tap, this.semantics});

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final Sfx? sound;
  final String? semantics;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return Semantics(
      button: true,
      enabled: active,
      label: widget.semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: active
            ? (_) {
                setState(() => _down = false);
                final s = Services.of(context, listen: false);
                s.audio.userGesture();
                if (widget.sound != null) s.audio.play(widget.sound!);
                s.haptics.selection();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(opacity: widget.enabled ? 1 : 0.5, duration: const Duration(milliseconds: 200), child: widget.child),
        ),
      ),
    );
  }
}

/// A carved stone panel with a gold-rimmed recess.
class StonePanel extends StatelessWidget {
  const StonePanel({super.key, required this.child, this.padding = const EdgeInsets.all(22), this.border = 14, this.radius = 24, this.seed = 3});

  final Widget child;
  final EdgeInsets padding;
  final double border;
  final double radius;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return CustomPaint(
      painter: StoneFramePainter(t, border: border, radius: radius, seed: seed),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A gold-edged title plate.
class Plaque extends StatelessWidget {
  const Plaque(this.text, {super.key, this.size = 20});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return CustomPaint(
      painter: _PlaquePainter(t),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 1.6, vertical: size * 0.45),
        child: Text(text, textAlign: TextAlign.center, style: UiText.style(context, size: size)),
      ),
    );
  }
}

class _PlaquePainter extends CustomPainter {
  _PlaquePainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final body = Path()
      ..moveTo(h * 0.45, 0)
      ..lineTo(size.width - h * 0.45, 0)
      ..lineTo(size.width, h / 2)
      ..lineTo(size.width - h * 0.45, h)
      ..lineTo(h * 0.45, h)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawPath(body.shift(const Offset(0, 4)), Paint()..color = alpha(t.color('text.shadow'), 0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawPath(body, Paint()..shader = gLinear(Offset.zero, Offset(0, h), [t.color('stone.purple'), t.color('ui.panelDeep')]));
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = gLinear(Offset.zero, Offset(size.width, h), [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')]),
    );
    paintGem(canvas, Offset(h * 0.32, h / 2), h * 0.12, t, crystal: 'crystal.purple');
    paintGem(canvas, Offset(size.width - h * 0.32, h / 2), h * 0.12, t, crystal: 'crystal.purple');
  }

  @override
  bool shouldRepaint(_PlaquePainter old) => old.t != t;
}

/// A stone (or golden, when [primary]) slab button.
class StoneButton extends StatelessWidget {
  const StoneButton({super.key, required this.label, this.onTap, this.glyph, this.primary = false, this.enabled = true, this.dense = false, this.trailing});

  final String label;
  final VoidCallback? onTap;
  final Glyph? glyph;
  final bool primary;
  final bool enabled;
  final bool dense;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    final textColor = primary ? t.color('text.onGold') : t.color('text.onStone');
    return Pressable(
      onTap: onTap,
      enabled: enabled,
      semantics: label,
      child: CustomPaint(
        painter: _SlabPainter(t, primary),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 16 : 24, vertical: dense ? 9 : 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (glyph != null) ...[GlyphIcon(glyph!, size: dense ? 18 : 22, color: textColor, shadow: !primary), const SizedBox(width: 8)],
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: UiText.style(context, size: dense ? 15 : 18, color: textColor, shadow: !primary)),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _SlabPainter extends CustomPainter {
  _SlabPainter(this.t, this.primary);

  final ThemeTokens t;
  final bool primary;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height * 0.38));
    paintDropShadow(canvas, rr, t, dy: 4, blur: 6);
    if (primary) {
      canvas.drawRRect(rr, Paint()..shader = gLinear(Offset.zero, Offset(0, size.height), [t.color('gold.light'), t.color('gold.base'), t.color('gold.dark')], [0, 0.5, 1]));
      canvas.drawRRect(rr.deflate(3), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = alpha(t.color('gold.light'), 0.8));
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('gold.deep'));
    } else {
      paintStoneWall(canvas, rr, t, seed: size.width.round(), block: size.height * 0.62);
      paintGoldEdge(canvas, rr.deflate(1.5), t, width: 2.2);
    }
  }

  @override
  bool shouldRepaint(_SlabPainter old) => old.t != t || old.primary != primary;
}

/// The home button: a small stone gate carrying the house sign. It sits
/// fixed at the bottom centre of every inner page.
class HomeGate extends StatelessWidget {
  const HomeGate({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    return Pressable(
      onTap: onTap,
      semantics: s.i18n.t('common.home'),
      child: SizedBox(
        width: 92,
        height: 78,
        child: CustomPaint(
          painter: _GatePainter(t),
          child: Padding(padding: const EdgeInsets.only(top: 22), child: Center(child: GlyphIcon(Glyph.home, size: 30, color: t.color('gold.light')))),
        ),
      ),
    );
  }
}

class _GatePainter extends CustomPainter {
  _GatePainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arch = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.45)
      ..quadraticBezierTo(0, 0, w / 2, 0)
      ..quadraticBezierTo(w, 0, w, h * 0.45)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(arch.shift(const Offset(0, 4)), Paint()..color = alpha(t.color('text.shadow'), 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.save();
    canvas.clipPath(arch);
    paintStoneWall(canvas, RRect.fromRectAndRadius(Offset.zero & size, Radius.zero), t, seed: 11, block: 18);
    canvas.restore();
    final inner = Path()
      ..moveTo(w * 0.2, h)
      ..lineTo(w * 0.2, h * 0.52)
      ..quadraticBezierTo(w * 0.2, h * 0.2, w / 2, h * 0.2)
      ..quadraticBezierTo(w * 0.8, h * 0.2, w * 0.8, h * 0.52)
      ..lineTo(w * 0.8, h)
      ..close();
    canvas.drawPath(inner, Paint()..shader = gLinear(Offset(0, h * 0.2), Offset(0, h), [t.color('ui.panelDeep'), t.color('stone.purple')]));
    canvas.drawPath(inner, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = t.color('gold.base'));
    paintGem(canvas, Offset(w / 2, h * 0.09), 5, t, crystal: 'crystal.purple');
  }

  @override
  bool shouldRepaint(_GatePainter old) => old.t != t;
}

/// The gold coin counter, set into the stone; optional "+" opens the shop.
class CoinCounter extends StatelessWidget {
  const CoinCounter({super.key, this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    return ListenableBuilder(
      listenable: s.player,
      builder: (context, _) => CustomPaint(
        painter: _CapsulePainter(t),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 6, 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(size: const Size(26, 26), painter: _CoinPainter(t)),
            const SizedBox(width: 6),
            Text('${s.player.coins}', style: UiText.numbers(context, size: 18, color: t.color('text.accent'))),
            if (onAdd != null) ...[
              const SizedBox(width: 6),
              Pressable(
                onTap: onAdd,
                semantics: s.i18n.t('home.addCoins'),
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: _GemButtonPainter(t),
                  child: SizedBox(width: 24, height: 24, child: Center(child: GlyphIcon(Glyph.plus, size: 14, color: t.color('text.onStone')))),
                ),
              ),
            ] else
              const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }
}

class _CapsulePainter extends CustomPainter {
  _CapsulePainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    paintRecess(canvas, rr, t);
    paintGoldEdge(canvas, rr, t, width: 2.4);
  }

  @override
  bool shouldRepaint(_CapsulePainter old) => old.t != t;
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) => paintCoin(canvas, size.center(Offset.zero), size.width * 0.42, t, shine: 0.6);

  @override
  bool shouldRepaint(_CoinPainter old) => old.t != t;
}

class _GemButtonPainter extends CustomPainter {
  _GemButtonPainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..shader = gRadial(c - Offset(r * 0.3, r * 0.3), r * 1.3, [mix(t.color('ui.gem'), const Color(0xFFFFFFFF), 0.4), t.color('ui.gem'), mix(t.color('ui.gem'), const Color(0xFF000000), 0.35)]));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = t.color('gold.base'));
  }

  @override
  bool shouldRepaint(_GemButtonPainter old) => old.t != t;
}

/// An animated stone lever: a gem that lights up when on.
class StoneToggle extends StatelessWidget {
  const StoneToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Pressable(
      onTap: () => onChanged(!value),
      sound: Sfx.toggle,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: value ? 1 : 0, end: value ? 1 : 0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, v, _) => CustomPaint(size: const Size(62, 32), painter: _TogglePainter(t, v)),
      ),
    );
  }
}

class _TogglePainter extends CustomPainter {
  _TogglePainter(this.t, this.v);

  final ThemeTokens t;
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    paintRecess(canvas, rr, t, top: t.color('ui.panelDeep'), bottom: mix(t.color('ui.panelDeep'), t.color('ui.toggleOn'), v * 0.45));
    paintGoldEdge(canvas, rr, t, width: 2);
    final r = size.height / 2 - 4;
    final x = (r + 4) + (size.width - 2 * (r + 4)) * v.clamp(0.0, 1.0);
    final c = Offset(x, size.height / 2);
    final gem = mix(t.color('ui.toggleOff'), t.color('ui.toggleOn'), v);
    if (v > 0.5) paintGlow(canvas, c, r * 2.4, gem, (v - 0.5) * 1.6);
    canvas.drawCircle(c + const Offset(0, 2), r, Paint()..color = alpha(t.color('text.shadow'), 0.5));
    canvas.drawCircle(c, r, Paint()..shader = gRadial(c - Offset(r * 0.3, r * 0.35), r * 1.4, [mix(gem, const Color(0xFFFFFFFF), 0.5), gem, mix(gem, const Color(0xFF000000), 0.3)]));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = t.color('gold.base'));
  }

  @override
  bool shouldRepaint(_TogglePainter old) => old.v != v || old.t != t;
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 22, this.total = 3});

  final int stars;
  final double size;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return CustomPaint(size: Size(size * total * 1.15, size * 1.1), painter: _StarsPainter(t, stars, total, size));
  }
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.t, this.stars, this.total, this.starSize);

  final ThemeTokens t;
  final int stars;
  final int total;
  final double starSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < total; i++) {
      final lift = (i == 1 && total == 3) ? -starSize * 0.12 : 0.0;
      paintStar(canvas, Offset(starSize * (0.58 + i * 1.15), size.height / 2 + lift), starSize * 0.5, t, filled: i < stars);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.stars != stars || old.t != t;
}

/// A stone tablet dialog that rises with a soft scale and fade.
Future<T?> showStoneDialog<T>(BuildContext context, {String? title, required WidgetBuilder builder, bool dismissible = true}) {
  final s = Services.of(context, listen: false);
  final t = s.theme.tokens;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: s.i18n.t('common.close'),
    barrierColor: alpha(t.color('ui.overlay'), t.number('ui.overlayOpacity', 0.5)),
    transitionDuration: s.motion('dialog'),
    pageBuilder: (context, _, __) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              type: MaterialType.transparency,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                Padding(
                  padding: EdgeInsets.only(top: title == null ? 0 : 22),
                  child: StonePanel(
                    padding: EdgeInsets.fromLTRB(22, title == null ? 22 : 40, 22, 22),
                    child: Builder(builder: builder),
                  ),
                ),
                if (title != null) Plaque(title),
              ]),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.86, end: 1.0).animate(curved), child: child));
    },
  );
}

OverlayEntry? _toastEntry;
Timer? _toastTimer;

/// A short message banner that glides in from the top.
void showToast(BuildContext context, String text, {Glyph glyph = Glyph.sparkle}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final s = Services.of(context, listen: false);
  _toastTimer?.cancel();
  _toastEntry?.remove();
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - v) * -30), child: child)),
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: CustomPaint(
                painter: _CapsulePainter(s.theme.tokens),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    GlyphIcon(glyph, size: 18, color: s.theme.tokens.color('text.accent')),
                    const SizedBox(width: 8),
                    Flexible(child: Text(text, textAlign: TextAlign.center, style: UiText.style(context, size: 15))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
  _toastTimer = Timer(s.design.motion('toast'), () {
    if (_toastEntry == entry) {
      entry.remove();
      _toastEntry = null;
    }
  });
}
