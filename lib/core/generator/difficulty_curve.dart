import 'dart:math' as math;

import '../model/puzzle_layout.dart';
import '../random/seeded_random.dart';
import '../util/json_read.dart';
import 'generation_params.dart';

/// One board shape a band may use: size plus empty bottom-row cells.
class GridChoice {
  const GridChoice(this.rows, this.cols, [this.gaps = 0, this.depth]);

  /// `[rows, cols]`, `[rows, cols, gaps]` or `[rows, cols, gaps, depth]`.
  factory GridChoice.fromJson(Object? json) {
    final v = readIntList(json);
    if (v.length < 2) return const GridChoice(4, 4);
    return GridChoice(v[0], v[1], v.length > 2 ? v[2] : 0, v.length > 3 ? v[3] : null);
  }

  final int rows;
  final int cols;
  final int gaps;

  /// Target depth for this shape (overrides the band's range).
  final int? depth;
}

/// `[start, end]` from JSON: a single number (or `[n]`) means a flat range.
List<double> _range(Object? v, double a, double b) {
  if (v is num) return [v.toDouble(), v.toDouble()];
  final list = readDoubleList(v);
  if (list.isEmpty) return [a, b];
  if (list.length == 1) return [list.first, list.first];
  return [list[0], list[1]];
}

double _lerpRange(List<double> range, double t) => range[0] + (range[1] - range[0]) * t;

/// A band's arrow settings: the teaching stage (`open`, `max`) plus ranges
/// interpolated across the band like every other setting.
///
/// Stages: `open: all` (every tile open, no arrows) → `max: 1` (single
/// arrows) → `max: 2` (two-arrow tiles) → `star > 0` (stars) → all mixed.
class ArrowBand {
  const ArrowBand({
    this.open = 'bottom',
    this.maxArrows = 2,
    this.two = const [0.35, 0.35],
    this.star = const [0.25, 0.25],
    this.decoy = const [0.3, 0.3],
    this.branch = const [0.45, 0.45],
  });

  factory ArrowBand.fromJson(Map<String, Object?> json) => ArrowBand(
        open: readString(json['open'], 'bottom'),
        maxArrows: readInt(json['max'], 2),
        two: _range(json['two'], 0.35, 0.35),
        star: _range(json['star'], 0.25, 0.25),
        decoy: _range(json['decoy'], 0.3, 0.3),
        branch: _range(json['branch'], 0.45, 0.45),
      );

  final String open;
  final int maxArrows;
  final List<double> two;
  final List<double> star;
  final List<double> decoy;
  final List<double> branch;

  ArrowParams at(double t) => ArrowParams(
        open: open,
        maxArrows: maxArrows.clamp(1, 2),
        twoRatio: _lerpRange(two, t).clamp(0.0, 1.0),
        starRatio: _lerpRange(star, t).clamp(0.0, 1.0),
        decoyRatio: _lerpRange(decoy, t).clamp(0.0, 1.0),
        branchiness: _lerpRange(branch, t).clamp(0.0, 1.0),
      );
}

/// A stretch of the difficulty curve (levels or challenge tiers).
///
/// Numeric settings are `[start, end]` ranges interpolated across the band,
/// so difficulty rises smoothly inside it. Every few steps a "vault" step
/// can switch to tighter boards and a higher slot target.
class CurveBand {
  const CurveBand({
    required this.from,
    required this.to,
    required this.grids,
    required this.depth,
    required this.peaks,
    required this.complement,
    required this.colors,
    required this.peels,
    required this.climb,
    required this.score,
    required this.width,
    required this.exact,
    required this.proof,
    required this.spread,
    required this.harden,
    required this.attempts,
    required this.vaultGrids,
    required this.vaultDepth,
    required this.vaultHarden,
    this.shape = 'grid',
    this.fill = const [0.55, 0.55],
    this.holes = const [0, 0],
    this.entrances = const [2, 2],
    this.floor = const [0, 0],
    this.unique = false,
    this.arrows = const ArrowBand(),
  });

  final String shape;
  final List<double> fill;

  /// Share of a grid board's cells left empty.
  final List<double> holes;
  final List<double> entrances;
  final List<double> floor;
  final bool unique;

  /// The arrow rule's stage and settings.
  final ArrowBand arrows;

  factory CurveBand.fromJson(Map<String, Object?> json) {
    List<double> pair(Object? v, double a, double b) => _range(v, a, b);

    return CurveBand(
      from: readInt(json['from'], 1),
      to: readInt(json['to'], 1),
      grids: [for (final g in readList(json['grids'])) GridChoice.fromJson(g)],
      depth: pair(json['depth'], 2, 2),
      peaks: pair(json['peaks'], 1, 1),
      complement: pair(json['complement'], 0.4, 0.4),
      colors: pair(json['colors'], 5, 5),
      peels: [
        for (final name in readStringList(json['peel']))
          PeelStyle.values.firstWhere((s) => s.name == name, orElse: () => PeelStyle.mixed),
      ],
      climb: pair(json['climb'], 0.5, 0.5),
      score: pair(json['score'], 10, 10),
      width: readDouble(json['width'], 10),
      exact: readBool(json['exact']),
      proof: readBool(json['proof']),
      spread: pair(json['spread'], 0, 0),
      harden: pair(json['harden'], 0, 0),
      attempts: readInt(json['attempts'], 12),
      vaultGrids: [for (final g in readList(json['vaultGrids'])) GridChoice.fromJson(g)],
      vaultDepth: readInt(json['vaultDepth']),
      vaultHarden: readInt(json['vaultHarden']),
      shape: readString(json['shape'], 'grid'),
      fill: pair(json['fill'], 0.55, 0.55),
      holes: pair(json['holes'], 0, 0),
      entrances: pair(json['entrances'], 2, 2),
      floor: pair(json['floor'], 0, 0),
      unique: readBool(json['unique']),
      arrows: ArrowBand.fromJson(readMap(json['arrows'])),
    );
  }

  final int from;
  final int to;
  final List<GridChoice> grids;
  final List<double> depth;
  final List<double> peaks;
  final List<double> complement;
  final List<double> colors;
  final List<PeelStyle> peels;
  final List<double> climb;
  final List<double> score;
  final double width;
  final bool exact;
  final bool proof;

  /// Chance of a "spread" layout (tight frontiers).
  final List<double> spread;
  final List<double> harden;

  /// Candidates tried per level before keeping the closest.
  final int attempts;

  /// Vault steps: tighter boards, +[vaultDepth] slots, more hardening.
  final List<GridChoice> vaultGrids;
  final int vaultDepth;
  final int vaultHarden;

  bool contains(int index) => index >= from && index <= to;

  double _t(int index) => to <= from ? 1 : ((index - from) / (to - from)).clamp(0.0, 1.0);

  static double _lerp(List<double> range, double t) => range[0] + (range[1] - range[0]) * t;

  /// Generation settings for [index] inside this band.
  GenerationParams paramsFor(int index, SeededRandom rng, {double scoreShift = 0, bool vault = false}) {
    final t = _t(index);
    final useVault = vault && vaultGrids.isNotEmpty;
    final options = useVault ? vaultGrids : grids;
    final grid = options.isEmpty ? const GridChoice(4, 4) : options[rng.nextInt(options.length)];
    final depthF = _lerp(depth, t);
    var d = grid.depth ?? (depthF.floor() + (rng.chance(depthF - depthF.floor()) ? 1 : 0) + (useVault ? vaultDepth : 0));
    d = d.clamp(1, 4);
    final center = _lerp(score, t) + scoreShift;
    final hardenSteps = useVault && vaultHarden > 0 ? vaultHarden : _lerp(harden, t).round();
    return GenerationParams(
      rows: grid.rows,
      cols: grid.cols,
      bottomGaps: grid.gaps,
      targetDepth: d,
      minPeakVisits: _lerp(peaks, t).round().clamp(1, 12),
      complementRatio: _lerp(complement, t).clamp(0.0, 1.0),
      colorCount: _lerp(colors, t).round().clamp(2, 8),
      peel: peels.isEmpty ? PeelStyle.mixed : peels[rng.nextInt(peels.length)],
      climb: _lerp(climb, t).clamp(0.0, 1.0),
      minScore: math.max(0, (center - width / 2).round()),
      maxScore: math.min(100, (center + width / 2).round()),
      exactCapacity: exact || useVault,
      requireProof: proof || useVault,
      spread: useVault || rng.chance(_lerp(spread, t)),
      hardenSteps: hardenSteps,
      shape: shape,
      fill: _lerp(fill, t),
      holes: _lerp(holes, t),
      entrances: _lerp(entrances, t).round(),
      floorDepth: _lerp(floor, t).round(),
      unique: unique,
      arrows: arrows.at(t),
    );
  }
}

/// A fixed, hand-made level (used for the first, teaching levels). Without
/// `dirs` and `open` it is a matching-only board: every tile open, no arrows.
class HandcraftedLevel {
  const HandcraftedLevel({required this.level, required this.layout});

  factory HandcraftedLevel.fromJson(Map<String, Object?> json) => HandcraftedLevel(
        level: readInt(json['level']),
        layout: PuzzleLayout.decode(
          readInt(json['rows']),
          readInt(json['cols']),
          readString(json['cells']),
          dirs: readStringOrNull(json['dirs']),
          open: readStringOrNull(json['open']),
        ),
      );

  final int level;
  final PuzzleLayout layout;
}

/// The whole curve: bands, optional hand-made entries and a rhythm that
/// makes every tenth step a tougher "vault" followed by a gentler breather.
class DifficultyCurve {
  const DifficultyCurve({
    required this.baseSeed,
    required this.bands,
    this.handcrafted = const <HandcraftedLevel>[],
    this.rhythmEvery = 0,
    this.vaultScore = 0,
    this.breatherScore = 0,
  });

  factory DifficultyCurve.fromJson(Map<String, Object?> json, {String bandsKey = 'bands'}) {
    final rhythm = readMap(json['rhythm']);
    return DifficultyCurve(
      baseSeed: readInt(json['baseSeed'], 1),
      bands: [for (final b in readList(json[bandsKey])) CurveBand.fromJson(readMap(b))],
      handcrafted: [for (final h in readList(json['handcrafted'])) HandcraftedLevel.fromJson(readMap(h))],
      rhythmEvery: readInt(rhythm['every']),
      vaultScore: readDouble(rhythm['vaultScore']),
      breatherScore: readDouble(rhythm['breatherScore']),
    );
  }

  final int baseSeed;
  final List<CurveBand> bands;
  final List<HandcraftedLevel> handcrafted;
  final int rhythmEvery;
  final double vaultScore;
  final double breatherScore;

  HandcraftedLevel? handcraftedFor(int index) {
    for (final h in handcrafted) {
      if (h.level == index) return h;
    }
    return null;
  }

  CurveBand bandFor(int index) {
    for (final b in bands) {
      if (b.contains(index)) return b;
    }
    return bands.last;
  }

  /// The deterministic seed of level (or tier) [index].
  int seedFor(int index) => combineSeeds(baseSeed, index);

  bool isVault(int index) => rhythmEvery > 0 && index % rhythmEvery == 0;

  bool isBreather(int index) => rhythmEvery > 0 && index % rhythmEvery == 1 && index > 1;

  GenerationParams paramsFor(int index, SeededRandom rng) {
    final band = bandFor(index);
    final vault = isVault(index);
    final breather = isBreather(index);
    return band.paramsFor(
      index,
      rng,
      scoreShift: vault ? vaultScore : (breather ? breatherScore : 0),
      vault: vault,
    );
  }

  int attemptsFor(int index) => bandFor(index).attempts;
}
