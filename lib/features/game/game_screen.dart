import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/engine/game_engine.dart';
import '../../core/model/puzzle_definition.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/paint_kit.dart';
import '../../ui/kit/tile_view.dart';
import '../../ui/kit/widgets.dart';
import '../../ui/kit/world_objects.dart';
import '../common/navigation.dart';
import 'game_controller.dart';
import 'game_dialogs.dart';

/// Board, tray and header geometry, computed from the screen and grid size.
class GameLayout {
  GameLayout._(this.frame, this.tile, this.gap, this.frameBorder, this.trayRect, this.slot, this.slotGap, this.slotsLeft, this.rtl);

  factory GameLayout.compute({required Size size, required EdgeInsets safe, required int rows, required int cols, required int capacity, required DesignTokens d, required bool rtl}) {
    final side = d.value('board.sideMargin', 14);
    final border = d.value('board.framePad', 16);
    final gapRatio = d.value('board.gapRatio', 0.11);
    final headerH = safe.top + d.value('header.height', 64) + d.value('header.boosterHeight', 78) + 10;
    final slotMax = d.value('tray.maxSlot', 64);
    final trayPad = d.value('tray.pad', 10);
    final slotGapRatio = d.value('tray.gapRatio', 0.16);
    final width = math.min(size.width, 560.0);
    final left0 = (size.width - width) / 2;
    final slot = math.min(slotMax, (width - 2 * side - 2 * trayPad) / (capacity + (capacity - 1) * slotGapRatio));
    final trayH = slot + 2 * trayPad;
    final bottom = size.height - safe.bottom - d.value('board.bottomMargin', 12);
    final availH = bottom - headerH - trayH - d.value('tray.gapToBoard', 14) - 2 * border - 24;
    final availW = width - 2 * side - 2 * border;
    final fromW = availW / (cols + (cols - 1) * gapRatio);
    final fromH = availH / (rows + (rows - 1) * gapRatio);
    final tile = math.min(fromW, fromH).clamp(d.value('board.minTile', 34), d.value('board.maxTile', 84)).toDouble();
    final gap = tile * gapRatio;
    final boardW = cols * tile + (cols - 1) * gap + 2 * border;
    final boardH = rows * tile + (rows - 1) * gap + 2 * border;
    final frame = Rect.fromLTWH(left0 + (width - boardW) / 2, bottom - boardH, boardW, boardH);
    final slotGap = slot * slotGapRatio;
    final trayW = capacity * slot + (capacity - 1) * slotGap + 2 * trayPad;
    final tray = Rect.fromLTWH(left0 + (width - trayW) / 2, frame.top - d.value('tray.gapToBoard', 14) - trayH, trayW, trayH);
    return GameLayout._(frame, tile, gap, border, tray, slot, slotGap, tray.left + trayPad, rtl);
  }

  final Rect frame;
  final double tile;
  final double gap;
  final double frameBorder;
  final Rect trayRect;
  final double slot;
  final double slotGap;
  final double slotsLeft;
  final bool rtl;

  Rect cell(int row, int col) =>
      Rect.fromLTWH(frame.left + frameBorder + col * (tile + gap), frame.top + frameBorder + row * (tile + gap), tile, tile);

  Rect slotRect(int index, int capacity) {
    final k = rtl ? capacity - 1 - index : index;
    return Rect.fromLTWH(slotsLeft + k * (slot + slotGap), trayRect.top + (trayRect.height - slot) / 2, slot, slot);
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.puzzle, this.resume});

  final PuzzleDefinition puzzle;
  final GameSnapshot? resume;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController game;
  GameStatus? _shown;

  @override
  void initState() {
    super.initState();
    game = GameController(services: Services.of(context, listen: false), puzzle: widget.puzzle, resume: widget.resume)
      ..onMessage = (key, [args = const {}]) {
        if (mounted) showToast(context, Services.of(context, listen: false).i18n.t(key, args));
      }
      ..addListener(_onChange);
  }

  @override
  void dispose() {
    game.removeListener(_onChange);
    game.dispose();
    super.dispose();
  }

  void _onChange() {
    final ended = game.ended;
    if (ended == _shown) return;
    _shown = ended;
    if (ended == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // The controller announces the end only once every animation has
      // settled, so a breath for the last frame is all that is needed.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || game.ended != ended) return;
      if (ended == GameStatus.won) {
        await showWinDialog(context, game);
      } else {
        await showLoseDialog(context, game);
      }
      if (mounted && game.ended == null) _shown = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final layout = puzzleLayout(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showPauseDialog(context, game);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: game,
          builder: (context, _) {
            final l = layout(game.capacity);
            final cells = <Widget>[];
            final p = game.puzzle.layout;
            for (var i = 0; i < p.cellCount; i++) {
              if (!p.isTile(i)) continue;
              final entry = game.entryOf(i);
              if (entry == null && !game.onBoard(i)) continue;
              final slot = game.slotOf(i);
              final rect = slot != null ? l.slotRect(slot, game.capacity).deflate(l.slot * 0.04) : l.cell(p.rowOf(i), p.colOf(i));
              cells.add(_TileHost(key: ValueKey(i), cell: i, rect: rect, game: game, entry: entry, slot: slot));
            }
            return Stack(children: [
              Positioned.fromRect(rect: l.frame, child: IgnorePointer(child: CustomPaint(painter: StoneFramePainter(t, border: l.frameBorder, radius: 22, seed: 9)))),
              Positioned.fromRect(rect: l.trayRect.inflate(8), child: IgnorePointer(child: _TrayPainterHost(capacity: game.capacity, layout: l, base: s.baseCapacity))),
              ...cells,
              Positioned(top: 0, left: 0, right: 0, child: _Header(game: game)),
              if (game.swapMode) Positioned(left: 16, right: 16, top: l.trayRect.top - 54, child: _SwapBanner(game: game)),
              if (game.thinking) Positioned(left: 0, right: 0, top: l.trayRect.top - 50, child: Center(child: _ThinkingChip())),
            ]);
          },
        ),
      ),
    );
  }

  GameLayout Function(int capacity) puzzleLayout(BuildContext context) {
    final s = Services.of(context);
    final mq = MediaQuery.of(context);
    final p = widget.puzzle.layout;
    return (cap) => GameLayout.compute(size: mq.size, safe: mq.padding, rows: p.rows, cols: p.cols, capacity: cap, d: s.design, rtl: s.i18n.current.rtl);
  }
}

class _TileHost extends StatelessWidget {
  const _TileHost({super.key, required this.cell, required this.rect, required this.game, required this.entry, required this.slot});

  final int cell;
  final Rect rect;
  final GameController game;
  final TrayEntry? entry;
  final int? slot;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final t = s.theme.tokens;
    final spec = game.spec(cell);
    final inTray = entry != null;
    final locked = !inTray && game.engine.board.isLocked(cell);
    return AnimatedPositioned(
      duration: s.motion(inTray && (entry!.matching || game.swapMode) ? 'compact' : 'tileFly'),
      curve: Curves.easeInOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          s.audio.userGesture();
          if (inTray) {
            game.tapSlot(slot!);
          } else {
            game.tapTile(cell);
          }
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (entry?.matching ?? false) ? 1 : 0),
          duration: s.motion('matchGlow'),
          builder: (context, match, _) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (entry?.vanishing ?? false) ? 1 : 0),
            duration: s.motion('matchVanish'),
            curve: Curves.easeInBack,
            builder: (context, vanish, _) => TweenAnimationBuilder<double>(
              key: ValueKey(game.unlockTick[cell] ?? 0),
              tween: Tween(begin: game.unlockTick.containsKey(cell) ? 0 : 1, end: 1),
              duration: s.motion('unlock'),
              builder: (context, unlock, _) {
                Widget paint(double hint) => CustomPaint(
                      painter: TilePainter(
                        t,
                        value: spec.value,
                        colorSlot: spec.color,
                        look: TileLook(
                          locked: locked,
                          unlock: unlock >= 1 ? 0 : unlock,
                          hint: hint,
                          swapMark: game.swapMode && game.swapFirst == slot && inTray,
                          match: match,
                          vanish: vanish,
                          dimmed: game.swapMode && !inTray,
                          arrows: inTray ? 0 : game.engine.puzzle.layout.dirs[cell],
                          star: !inTray && game.engine.puzzle.layout.isStar(cell),
                        ),
                      ),
                    );
                if (game.hintCell == cell) {
                  return Loop(period: s.motion('hintPulse'), builder: (context, ph) => paint(0.5 + 0.5 * math.sin(ph * math.pi * 2)));
                }
                return paint(0);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayPainterHost extends StatelessWidget {
  const _TrayPainterHost({required this.capacity, required this.layout, required this.base});

  final int capacity;
  final GameLayout layout;
  final int base;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: capacity > base ? 0 : 1, end: 1),
      duration: s.motion('slotOpen'),
      curve: Curves.easeOutBack,
      builder: (context, grow, _) => CustomPaint(painter: _TrayPainter(s.theme.tokens, layout, capacity, base, grow)),
    );
  }
}

class _TrayPainter extends CustomPainter {
  _TrayPainter(this.t, this.l, this.capacity, this.base, this.grow);

  final ThemeTokens t;
  final GameLayout l;
  final int capacity;
  final int base;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = l.trayRect.inflate(8).topLeft;
    final bar = RRect.fromRectAndRadius((l.trayRect.shift(-origin)).inflate(4), Radius.circular(l.slot * 0.4));
    paintDropShadow(canvas, bar, t);
    paintStoneWall(canvas, bar, t, seed: 17, block: l.slot * 0.5);
    paintGoldEdge(canvas, bar, t, width: 2.6);
    for (var i = 0; i < capacity; i++) {
      final r = l.slotRect(i, capacity).shift(-origin);
      final extra = i >= base;
      final sc = extra ? grow.clamp(0.0, 1.2) : 1.0;
      final rect = Rect.fromCenter(center: r.center, width: r.width * sc, height: r.height * sc);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.24));
      paintRecess(canvas, rr, t, top: t.color('slot.socket'), bottom: t.color('slot.socketLight'));
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = extra ? t.color('slot.fresh') : t.color('slot.rim'));
      if (extra && grow < 1) paintGlow(canvas, rect.center, rect.width, t.color('slot.fresh'), 1 - grow);
    }
  }

  @override
  bool shouldRepaint(_TrayPainter old) => old.capacity != capacity || old.grow != grow || old.t != t || old.l.slot != l.slot;
}

class _Header extends StatelessWidget {
  const _Header({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final i18n = s.i18n;
    final p = game.puzzle;
    final endless = p.mode == PuzzleMode.endless;
    final label = endless ? i18n.t('endless.label', {'n': p.boardNumber}) : i18n.t('game.level', {'n': p.levelNumber});
    final runScore = endless ? s.endless.run?.score : null;
    final tier = p.profile?.tier.name;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Column(children: [
          SizedBox(
            height: s.design.value('header.height', 64),
            child: CustomPaint(
              painter: _LintelPainter(s.theme.tokens),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  _Medallion(glyph: Glyph.pause, label: i18n.t('game.pause'), onTap: () => showPauseDialog(context, game)),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(label, style: UiText.style(context, size: 19), overflow: TextOverflow.ellipsis),
                      if (runScore != null)
                        Text(i18n.t('endless.score', {'n': runScore}), style: UiText.numbers(context, size: 12, color: s.theme.tokens.color('text.accent')))
                      else if (tier != null)
                        Text(i18n.t('difficulty.$tier'), style: UiText.style(context, size: 12, color: s.theme.tokens.color('text.accent'))),
                    ]),
                  ),
                  CoinCounter(onAdd: () => openShop(context)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _BoosterBar(game: game),
        ]),
      ),
    );
  }
}

class _LintelPainter extends CustomPainter {
  _LintelPainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height * 0.34));
    paintDropShadow(canvas, rr, t);
    paintStoneWall(canvas, rr, t, seed: 31, block: 24);
    paintGoldEdge(canvas, rr.deflate(1.5), t, width: 2.4);
    paintGem(canvas, Offset(size.width / 2, size.height - 3), 4, t, crystal: 'crystal.purple');
  }

  @override
  bool shouldRepaint(_LintelPainter old) => old.t != t;
}

class _Medallion extends StatelessWidget {
  const _Medallion({required this.glyph, required this.label, required this.onTap});

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Pressable(
      onTap: onTap,
      semantics: label,
      child: CustomPaint(
        painter: _MedallionPainter(t),
        child: SizedBox(width: 46, height: 46, child: Center(child: GlyphIcon(glyph, size: 22, color: t.color('gold.light')))),
      ),
    );
  }
}

class _MedallionPainter extends CustomPainter {
  _MedallionPainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c + const Offset(0, 3), r, Paint()..color = alpha(t.color('text.shadow'), 0.4));
    canvas.drawCircle(c, r, Paint()..shader = gRadial(c - Offset(r * 0.3, r * 0.3), r * 1.4, [t.color('stone.purple'), t.color('ui.panelDeep')]));
    canvas.drawCircle(c, r - 1.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = t.color('gold.base'));
  }

  @override
  bool shouldRepaint(_MedallionPainter old) => old.t != t;
}

class _BoosterBar extends StatelessWidget {
  const _BoosterBar({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final i18n = s.i18n;
    final r = game.boosterRules;
    final b = game.engine.boosters;
    final playing = game.ended == null;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _BoosterButton(
        glyph: Glyph.slotPlus,
        label: i18n.t('game.slot6'),
        cost: b.extraSlot ? null : r.extraSlotCoins,
        status: b.extraSlot ? i18n.t('game.active') : null,
        ad: !b.extraSlot && r.extraSlotByAd,
        enabled: playing && !b.extraSlot && !game.busy,
        onTap: () => boosterSlot(context, game),
      ),
      _BoosterButton(
        glyph: Glyph.hint,
        label: i18n.t('game.hint'),
        cost: game.freeHintsLeft > 0 ? null : r.hintCoins,
        status: game.freeHintsLeft > 0 ? i18n.t('booster.free', {'n': game.freeHintsLeft}) : null,
        ad: game.freeHintsLeft == 0 && r.hintByAd,
        enabled: playing && !game.busy,
        onTap: () => boosterHint(context, game),
      ),
      _BoosterButton(
        glyph: Glyph.swap,
        label: i18n.t('game.swap'),
        cost: b.swapUsed || game.swapReady ? null : r.swapCoins,
        status: b.swapUsed ? i18n.t('game.used') : (game.swapReady ? i18n.t('booster.ready') : null),
        ad: !b.swapUsed && !game.swapReady && r.swapByAd,
        enabled: !b.swapUsed && !game.busy && game.engine.tray.length >= 2 && game.ended != GameStatus.won,
        onTap: () => boosterSwap(context, game),
      ),
    ]);
  }
}

class _BoosterButton extends StatelessWidget {
  const _BoosterButton({required this.glyph, required this.label, required this.cost, required this.status, required this.ad, required this.enabled, required this.onTap});

  final Glyph glyph;
  final String label;
  final int? cost;
  final String? status;
  final bool ad;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Pressable(
      onTap: onTap,
      enabled: enabled,
      semantics: label,
      child: SizedBox(
        width: 98,
        height: 72,
        child: CustomPaint(
          painter: _SocketPainter(t),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            GlyphIcon(glyph, size: 26, color: t.color('gold.light')),
            const SizedBox(height: 2),
            Text(label, style: UiText.style(context, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (cost != null) ...[
                CustomPaint(size: const Size(12, 12), painter: _MiniCoin(t)),
                const SizedBox(width: 2),
                Text('$cost', style: UiText.numbers(context, size: 11, color: t.color('text.accent'))),
              ],
              if (ad) ...[const SizedBox(width: 6), GlyphIcon(Glyph.film, size: 12, color: t.color('ui.focus'))],
              if (status != null) ...[const SizedBox(width: 4), Flexible(child: Text(status!, style: UiText.style(context, size: 10, color: t.color('text.muted')), maxLines: 1))],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SocketPainter extends CustomPainter {
  _SocketPainter(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    paintDropShadow(canvas, rr, t, dy: 4, blur: 6);
    paintStoneWall(canvas, rr, t, seed: size.width.round() + 3, block: 20);
    final inner = rr.deflate(5);
    paintRecess(canvas, inner, t);
    paintGoldEdge(canvas, inner, t, width: 1.8);
  }

  @override
  bool shouldRepaint(_SocketPainter old) => old.t != t;
}

class _MiniCoin extends CustomPainter {
  _MiniCoin(this.t);

  final ThemeTokens t;

  @override
  void paint(Canvas canvas, Size size) => paintCoin(canvas, size.center(Offset.zero), size.width / 2, t);

  @override
  bool shouldRepaint(_MiniCoin old) => old.t != t;
}

class _SwapBanner extends StatelessWidget {
  const _SwapBanner({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final i18n = Services.of(context).i18n;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible(child: Plaque(i18n.t(game.swapFirst == null ? 'game.swapFirst' : 'game.swapSecond'), size: 14)),
      const SizedBox(width: 8),
      StoneButton(label: i18n.t('game.swapCancel'), dense: true, onTap: game.cancelSwap),
    ]);
  }
}

class _ThinkingChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return Loop(
      period: const Duration(milliseconds: 1400),
      builder: (context, ph) => Row(mainAxisSize: MainAxisSize.min, children: [
        Transform.rotate(angle: ph * math.pi * 2, child: GlyphIcon(Glyph.sparkle, size: 20, color: s.theme.tokens.color('text.accent'))),
        const SizedBox(width: 8),
        Text(s.i18n.t('game.thinking'), style: UiText.style(context, size: 14)),
      ]),
    );
  }
}
