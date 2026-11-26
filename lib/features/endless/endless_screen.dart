import 'package:flutter/material.dart';

import '../../core/endless/endless_run.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../common/navigation.dart';
import '../common/page_frame.dart';

/// The endless hall: the run in progress (if any), the endless records, and
/// the way into a run. Boards are made fresh for every run, so there is no
/// map — and nothing here mixes with the stars of the fixed levels.
class EndlessScreen extends StatefulWidget {
  const EndlessScreen({super.key});

  @override
  State<EndlessScreen> createState() => _EndlessScreenState();
}

class _EndlessScreenState extends State<EndlessScreen> {
  EndlessRun? _run;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final run = await Services.of(context, listen: false).endless.load();
    if (mounted) setState(() => _run = run);
  }

  Future<void> _play({required bool fresh}) async {
    final s = Services.of(context, listen: false);
    if (fresh && _run != null) {
      final ok = await showStoneDialog<bool>(
        context,
        title: s.i18n.t('endless.start'),
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.i18n.t('endless.confirmRestart'), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
          const SizedBox(height: 16),
          StoneButton(label: s.i18n.t('common.continue'), primary: true, onTap: () => Navigator.pop(context, true)),
          const SizedBox(height: 8),
          StoneButton(label: s.i18n.t('common.cancel'), dense: true, onTap: () => Navigator.pop(context, false)),
        ]),
      );
      if (ok != true) return;
      // The run being replaced still counts: its total is recorded.
      await s.endless.finishRun(s.player);
    }
    if (!mounted) return;
    await launchEndless(context, fresh: fresh);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final i18n = s.i18n;
    final run = _run;
    final stats = s.player.endless;
    Widget stat(String key, int value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(i18n.t(key), style: UiText.style(context, size: 14))),
            Text('$value', style: UiText.numbers(context, size: 15, color: t.color('text.accent'))),
          ]),
        );
    return PageFrame(
      title: i18n.t('endless.title'),
      child: Column(children: [
        SizedBox(width: 180, height: 180, child: Loop(period: const Duration(seconds: 5), builder: (context, ph) => CustomPaint(painter: CrystalPainter(t, ph)))),
        StonePanel(
          child: Column(children: [
            if (run != null) ...[
              Text(i18n.t('endless.progress'), style: UiText.style(context, size: 13, color: t.color('text.muted'))),
              Text(i18n.t('endless.board', {'n': run.board}), style: UiText.style(context, size: 22, color: t.color('text.accent'))),
              Text(i18n.t('endless.runTotal', {'n': run.score}), style: UiText.numbers(context, size: 16, color: t.color('text.accent'))),
              Text(i18n.t('endless.cleared', {'n': run.boardsCleared}), style: UiText.style(context, size: 14)),
              const SizedBox(height: 8),
              CustomPaint(size: const Size(260, 34), painter: _RunesPainter(t, run.board)),
              const SizedBox(height: 12),
            ],
            stat('profile.best', stats.best),
            stat('profile.last', stats.last),
            stat('profile.mostBoards', stats.bestBoards),
            stat('profile.runs', stats.runs),
            const SizedBox(height: 10),
            Text(i18n.t('endless.scoring'), textAlign: TextAlign.center, style: UiText.style(context, size: 13, color: t.color('text.muted'))),
            const SizedBox(height: 8),
            Text(i18n.t('endless.about'), textAlign: TextAlign.center, style: UiText.style(context, size: 14, color: t.color('text.muted'))),
          ]),
        ),
        const SizedBox(height: 18),
        if (run != null) ...[
          StoneButton(label: i18n.t('endless.continue', {'n': run.board}), glyph: Glyph.play, primary: true, onTap: () => _play(fresh: false)),
          const SizedBox(height: 10),
        ],
        StoneButton(label: i18n.t('endless.start'), glyph: Glyph.sparkle, primary: run == null, onTap: () => _play(fresh: true)),
        const SizedBox(height: 8),
        Text(i18n.t('endless.newRunHint'), textAlign: TextAlign.center, style: UiText.style(context, size: 12, color: t.color('text.muted'))),
      ]),
    );
  }
}

/// Rune stones of the run: lit up to the current board.
class _RunesPainter extends CustomPainter {
  _RunesPainter(this.t, this.board);

  final ThemeTokens t;
  final int board;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 8;
    final start = ((board - 1) ~/ count) * count;
    final step = size.width / count;
    for (var i = 0; i < count; i++) {
      final n = start + i + 1;
      final c = Offset(step * (i + 0.5), size.height / 2);
      final lit = n < board;
      final current = n == board;
      if (current) paintGlow(canvas, c, 22, t.color('crystal.purple'), 0.9);
      canvas.drawCircle(c, current ? 13 : 10, Paint()..color = lit ? t.color('crystal.purple') : (current ? t.color('gold.base') : t.color('stone.dark')));
      canvas.drawCircle(c, current ? 13 : 10, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = t.color('gold.base'));
      if (i < count - 1) canvas.drawLine(c + const Offset(12, 0), c + Offset(step - 12, 0), Paint()..color = alpha(t.color('gold.base'), lit ? 0.9 : 0.35)..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_RunesPainter old) => old.board != board || old.t != t;
}
