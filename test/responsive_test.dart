import 'package:flutter_test/flutter_test.dart';
import 'package:unlock_numbers/core/engine/game_engine.dart';
import 'package:unlock_numbers/core/model/puzzle_definition.dart';
import 'package:unlock_numbers/core/model/puzzle_layout.dart';
import 'package:unlock_numbers/features/game/game_controller.dart';
import 'package:unlock_numbers/services/app_services.dart';
import 'package:unlock_numbers/services/storage.dart';

/// Instant response: the game logic moves the moment the player taps; the
/// animations follow, side by side, and never hold the next tap back.
void main() {
  testWidgets('back-to-back taps are all taken at once, while earlier moves still animate', (tester) async {
    final s = (await tester.runAsync(() => AppServices.bootstrap(store: MemoryStore(), audio: false)))!;
    // One row, every tile open: 1 9 2 8 3 7 — three pairs that add up to ten.
    final puzzle = PuzzleDefinition(
      id: 'quick',
      mode: PuzzleMode.levels,
      layout: PuzzleLayout.decode(1, 6, '1a9b2c8d3e7f'),
      rulesetVersion: 1,
      levelNumber: 1,
    );
    final game = GameController(services: s, puzzle: puzzle);

    for (final c in [0, 1, 2, 3, 4]) {
      game.tapTile(c); // no awaiting and no frames in between
    }
    expect(game.engine.board.remaining, 1, reason: 'every tap was taken at once');
    expect(game.animating, isTrue);

    game.tapTile(5);
    expect(game.engine.status, GameStatus.won, reason: 'the logic is already done');
    expect(game.ended, isNull, reason: 'the end screen waits for the animations to settle');

    await tester.pump(const Duration(seconds: 3));
    expect(game.animating, isFalse);
    expect(game.tray, isEmpty);
    expect(game.ended, GameStatus.won);
    game.dispose();
  });

  testWidgets('a locked tile is refused without blocking the next tap', (tester) async {
    final s = (await tester.runAsync(() => AppServices.bootstrap(store: MemoryStore(), audio: false)))!;
    // Two rows: the bottom row is open, the top row opens through its arrows.
    final puzzle = PuzzleDefinition(
      id: 'locked',
      mode: PuzzleMode.levels,
      layout: PuzzleLayout.decode(2, 2, '7c7f3a3e', dirs: '0011', open: '0011'),
      rulesetVersion: 1,
      levelNumber: 1,
    );
    final game = GameController(services: s, puzzle: puzzle);
    game.tapTile(0);
    expect(game.engine.board.remaining, 4, reason: 'locked: refused');
    game.tapTile(2);
    game.tapTile(0);
    expect(game.engine.board.remaining, 2, reason: 'the arrow opened it, and the tap went through at once');
    await tester.pump(const Duration(seconds: 3));
    game.dispose();
  });
}
