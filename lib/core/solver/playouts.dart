import '../random/seeded_random.dart';
import 'solver_context.dart';

enum PlayoutPolicy {
  /// Any open tile, uniformly.
  random,

  /// Takes a matching tile whenever one is open, otherwise any tile.
  greedy,
}

/// Fast simulated play-throughs, used to estimate how forgiving a puzzle is.
class Playouts {
  Playouts(this.ctx);

  final SolverContext ctx;

  /// Plays [runs] games with [policy] and returns the share that won.
  double winRate({required int capacity, required int runs, required PlayoutPolicy policy, required SeededRandom rng}) {
    if (runs <= 0) return 0;
    final n = ctx.layout.cellCount;
    final removed = List<bool>.filled(n, false);
    final tray = <int>[];
    final open = <int>[];
    final matching = <int>[];
    final probe = <int>[];
    var wins = 0;
    for (var r = 0; r < runs; r++) {
      removed.fillRange(0, n, false);
      tray.clear();
      var remaining = ctx.layout.tileCount;
      var lost = false;
      while (remaining > 0) {
        open.clear();
        for (final c in ctx.tiles) {
          if (!removed[c] && ctx.topology.isOpenWith(c, (x) => removed[x])) open.add(c);
        }
        if (open.isEmpty) {
          lost = true;
          break;
        }
        int pick;
        if (policy == PlayoutPolicy.greedy) {
          matching.clear();
          for (final c in open) {
            probe
              ..clear()
              ..addAll(tray)
              ..add(c);
            if (ctx.resolver.resolveQuietly(probe) > 0) matching.add(c);
          }
          pick = matching.isNotEmpty ? rng.pick(matching) : rng.pick(open);
        } else {
          pick = rng.pick(open);
        }
        removed[pick] = true;
        remaining--;
        tray.add(pick);
        ctx.resolver.resolveQuietly(tray);
        if (tray.length >= capacity) {
          lost = true;
          break;
        }
      }
      if (!lost && tray.isEmpty) wins++;
    }
    return wins / runs;
  }
}
