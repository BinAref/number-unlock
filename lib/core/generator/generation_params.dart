import '../util/json_read.dart';

/// How the generator chooses its hidden winning order of picks.
enum PeelStyle {
  /// Any open tile.
  random,

  /// Lower rows first: the board clears layer by layer.
  layered,

  /// Higher rows first: digging up columns, partners end up far apart.
  deep,

  /// A blend of the three, chosen pick by pick.
  mixed,
}

/// Knobs for building one puzzle.
class GenerationParams {
  const GenerationParams({
    required this.rows,
    required this.cols,
    this.voids = -1,
    required this.targetDepth,
    this.minPeakVisits = 1,
    this.complementRatio = 0.5,
    this.colorCount = 6,
    this.peel = PeelStyle.mixed,
    this.climb = 0.5,
    this.minScore = 0,
    this.maxScore = 100,
    this.exactCapacity = false,
    this.requireProof = false,
    this.hardenSteps = 0,
    this.bottomGaps = 0,
    this.spread = false,
    this.shape = 'grid',
    this.fill = 0.55,
    this.entrances = 2,
    this.floorDepth = 0,
    this.unique = false,
  });

  factory GenerationParams.fromJson(Map<String, Object?> json) => GenerationParams(
        rows: readInt(json['rows'], 4),
        cols: readInt(json['cols'], 4),
        voids: readInt(json['voids'], -1),
        targetDepth: readInt(json['depth'], 2),
        minPeakVisits: readInt(json['peaks'], 1),
        complementRatio: readDouble(json['complement'], 0.5),
        colorCount: readInt(json['colors'], 6),
        peel: PeelStyle.values.firstWhere((s) => s.name == json['peel'], orElse: () => PeelStyle.mixed),
        climb: readDouble(json['climb'], 0.5),
        minScore: readInt(json['minScore']),
        maxScore: readInt(json['maxScore'], 100),
        exactCapacity: readBool(json['exact']),
        requireProof: readBool(json['proof']),
        hardenSteps: readInt(json['harden']),
        bottomGaps: readInt(json['gaps']),
        spread: readBool(json['spread']),
        shape: readString(json['shape'], 'grid'),
        fill: readDouble(json['fill'], 0.55),
        entrances: readInt(json['entrances'], 2),
        floorDepth: readInt(json['floor']),
        unique: readBool(json['unique']),
      );

  final int rows;
  final int cols;

  /// Cells empty from the start (-1: automatic, one when rows × cols is odd).
  final int voids;

  /// Most tiles the hidden solution keeps waiting at once (1..capacity-1);
  /// the puzzle is built to need `targetDepth + 1` slots.
  final int targetDepth;

  /// How many times the hidden solution must reach [targetDepth].
  final int minPeakVisits;

  /// Share of pairs that sum to ten instead of being identical.
  final double complementRatio;
  final int colorCount;
  final PeelStyle peel;

  /// 0..1: how eagerly the hidden solution keeps tiles waiting.
  final double climb;
  final int minScore;
  final int maxScore;

  /// Reject puzzles that turn out to need fewer slots than intended.
  final bool exactCapacity;

  /// Require a proof that fewer slots cannot solve the puzzle.
  final bool requireProof;

  /// Local-search steps that rearrange tiles until fewer slots provably fail.
  final int hardenSteps;

  /// Empty cells in the bottom row: they narrow the open frontier, which is
  /// what makes wide boards demand more slots.
  final int bottomGaps;

  /// Place matching families far apart (annealed) instead of along a hidden
  /// order; the solver then supplies the verified solution. Produces tight
  /// frontiers — the source of genuinely hard puzzles.
  final bool spread;

  /// `grid` (full board) or `corridors`: a tree of one-tile-wide passages
  /// inside the frame, so even a 10 × 10 board keeps a narrow, tense front.
  final String shape;

  /// Share of the cells that become tiles in a corridor board.
  final double fill;

  /// Corridor entrances in the bottom row.
  final int entrances;

  /// Once reached, the hidden solution never keeps fewer tiles waiting until
  /// the final unwinding — the slots stay busy for the whole level.
  final int floorDepth;

  /// Drive the number of winning orders down to exactly one.
  final bool unique;

  int get targetCapacity => targetDepth + 1;

  GenerationParams copyWith({int? rows, int? cols, int? targetDepth, int? hardenSteps, int? minScore, int? maxScore}) =>
      GenerationParams(
        rows: rows ?? this.rows,
        cols: cols ?? this.cols,
        voids: voids,
        targetDepth: targetDepth ?? this.targetDepth,
        minPeakVisits: minPeakVisits,
        complementRatio: complementRatio,
        colorCount: colorCount,
        peel: peel,
        climb: climb,
        minScore: minScore ?? this.minScore,
        maxScore: maxScore ?? this.maxScore,
        exactCapacity: exactCapacity,
        requireProof: requireProof,
        hardenSteps: hardenSteps ?? this.hardenSteps,
        bottomGaps: bottomGaps,
        spread: spread,
        shape: shape,
        fill: fill,
        entrances: entrances,
        floorDepth: floorDepth,
        unique: unique,
      );

  Map<String, Object?> toJson() => {
        'rows': rows,
        'cols': cols,
        'voids': voids,
        'depth': targetDepth,
        'peaks': minPeakVisits,
        'complement': complementRatio,
        'colors': colorCount,
        'peel': peel.name,
        'climb': climb,
        'minScore': minScore,
        'maxScore': maxScore,
        'exact': exactCapacity,
        'proof': requireProof,
        'harden': hardenSteps,
        'gaps': bottomGaps,
        'spread': spread,
      };
}
