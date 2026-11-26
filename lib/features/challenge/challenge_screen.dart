import 'package:flutter/material.dart';

import '../../core/challenge/challenge_system.dart';
import '../../core/model/puzzle_definition.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../common/navigation.dart';
import '../common/page_frame.dart';

/// The challenge hall: a crystal spire instead of a map — challenges are
/// forged anew, so there is no fixed road of puzzles.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  ChallengeRun? _run;
  bool _hasAttempt = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = Services.of(context, listen: false);
    final run = await s.save.loadChallengeRun();
    final attempt = await s.save.loadAttempt(PuzzleMode.challenge.key);
    if (mounted) {
      setState(() {
        _run = run;
        _hasAttempt = attempt != null;
      });
    }
  }

  Future<void> _start({required bool resume}) async {
    final s = Services.of(context, listen: false);
    if (!resume && _run != null) {
      final ok = await showStoneDialog<bool>(
        context,
        title: s.i18n.t('challenge.start'),
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.i18n.t('challenge.confirmRestart'), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
          const SizedBox(height: 16),
          StoneButton(label: s.i18n.t('common.continue'), primary: true, onTap: () => Navigator.pop(context, true)),
          const SizedBox(height: 8),
          StoneButton(label: s.i18n.t('common.cancel'), dense: true, onTap: () => Navigator.pop(context, false)),
        ]),
      );
      if (ok != true) return;
      await s.save.clearChallengeRun();
    }
    if (!mounted) return;
    await launchChallenge(context, resume: resume);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final i18n = s.i18n;
    final run = _run;
    final tier = run?.tier ?? 1;
    return PageFrame(
      title: i18n.t('challenge.title'),
      child: Column(children: [
        SizedBox(width: 200, height: 200, child: Loop(period: const Duration(seconds: 5), builder: (context, ph) => CustomPaint(painter: CrystalPainter(t, ph)))),
        StonePanel(
          child: Column(children: [
            Text(i18n.t('challenge.tier', {'n': tier}), style: UiText.style(context, size: 22, color: t.color('text.accent'))),
            const SizedBox(height: 8),
            Text(i18n.t('challenge.solved', {'n': run?.solved ?? 0}), style: UiText.style(context, size: 16)),
            const SizedBox(height: 12),
            Text(i18n.t('challenge.progress'), style: UiText.style(context, size: 13, color: t.color('text.muted'))),
            const SizedBox(height: 6),
            CustomPaint(size: const Size(260, 34), painter: _RunesPainter(t, tier)),
            const SizedBox(height: 12),
            Text(i18n.t('challenge.about'), textAlign: TextAlign.center, style: UiText.style(context, size: 14, color: t.color('text.muted'))),
          ]),
        ),
        const SizedBox(height: 18),
        if (run != null)
          StoneButton(label: i18n.t('challenge.continue'), glyph: Glyph.play, primary: true, onTap: () => _start(resume: true)),
        if (run != null) const SizedBox(height: 10),
        StoneButton(label: i18n.t('challenge.start'), glyph: Glyph.sparkle, primary: run == null, onTap: () => _start(resume: false)),
        if (run == null && _hasAttempt) const SizedBox.shrink(),
        const SizedBox(height: 8),
        Text(i18n.t('challenge.newRunHint'), textAlign: TextAlign.center, style: UiText.style(context, size: 12, color: t.color('text.muted'))),
      ]),
    );
  }
}

/// Rune stones of the run: lit up to the current tier.
class _RunesPainter extends CustomPainter {
  _RunesPainter(this.t, this.tier);

  final ThemeTokens t;
  final int tier;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 8;
    final start = ((tier - 1) ~/ count) * count;
    final step = size.width / count;
    for (var i = 0; i < count; i++) {
      final n = start + i + 1;
      final c = Offset(step * (i + 0.5), size.height / 2);
      final lit = n < tier;
      final current = n == tier;
      if (current) paintGlow(canvas, c, 22, t.color('crystal.purple'), 0.9);
      canvas.drawCircle(c, current ? 13 : 10, Paint()..color = lit ? t.color('crystal.purple') : (current ? t.color('gold.base') : t.color('stone.dark')));
      canvas.drawCircle(c, current ? 13 : 10, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('gold.base'));
      if (i < count - 1) canvas.drawLine(c + const Offset(12, 0), c + Offset(step - 12, 0), Paint()..color = alpha(t.color('gold.base'), lit ? 0.9 : 0.35)..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_RunesPainter old) => old.tier != tier || old.t != t;
}
