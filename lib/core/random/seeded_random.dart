/// Deterministic pseudo-random numbers for puzzle generation.
///
/// Uses mulberry32 with all 32-bit arithmetic done by hand, so the Dart VM
/// (Android, iOS, tools) and JavaScript (web) produce exactly the same
/// sequence for the same seed. A seed therefore always rebuilds the same
/// puzzle on every platform.
library;

/// Multiplies two unsigned 32-bit integers modulo 2^32 without losing
/// precision on the web, where integers are IEEE doubles.
int mul32(int a, int b) {
  final aLo = a & 0xFFFF;
  final aHi = (a >>> 16) & 0xFFFF;
  final bLo = b & 0xFFFF;
  final bHi = (b >>> 16) & 0xFFFF;
  final lo = aLo * bLo;
  final mid = ((aHi * bLo) + (aLo * bHi)) & 0xFFFF;
  return (lo + (mid << 16)) & 0xFFFFFFFF;
}

/// A fast 32-bit integer hash (used to derive child seeds).
int hash32(int input) {
  var x = input & 0xFFFFFFFF;
  x ^= x >>> 16;
  x = mul32(x, 0x7FEB352D);
  x ^= x >>> 15;
  x = mul32(x, 0x846CA68B);
  x ^= x >>> 16;
  return x & 0xFFFFFFFF;
}

/// e^(-x) for x >= 0 using only + − × ÷, so every platform computes the
/// very same bits (library exp/log may differ in the last digit between the
/// Dart VM and JavaScript, which would make generated levels diverge).
double detExpNeg(double x) {
  if (x <= 0) return 1;
  if (x > 40) return 0;
  var y = x;
  var halvings = 0;
  while (y > 0.5) {
    y /= 2;
    halvings++;
  }
  var term = 1.0;
  var sum = 1.0;
  for (var n = 1; n <= 12; n++) {
    term *= -y / n;
    sum += term;
  }
  for (var i = 0; i < halvings; i++) {
    sum *= sum;
  }
  return sum;
}

/// log10(x) for x > 0 with the same guarantee as [detExpNeg].
double detLog10(double x) {
  if (x <= 0) return -400;
  var m = x;
  var e = 0;
  while (m >= 2) {
    m /= 2;
    e++;
  }
  while (m < 1) {
    m *= 2;
    e--;
  }
  final z = (m - 1) / (m + 1);
  final z2 = z * z;
  var term = z;
  var sum = 0.0;
  for (var n = 1; n <= 25; n += 2) {
    sum += term / n;
    term *= z2;
  }
  return (2 * sum + e * 0.6931471805599453) / 2.302585092994046;
}

/// Combines two values into one 32-bit seed.
int combineSeeds(int a, int b) => hash32((a & 0xFFFFFFFF) ^ mul32(b & 0xFFFFFFFF, 0x9E3779B1));

class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int get state => _state;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = mul32(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + mul32(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  /// A value in `[0, max)`.
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return nextUint32() % max;
  }

  /// A value in `[min, max]` (both inclusive).
  int nextRange(int min, int max) => min + nextInt(max - min + 1);

  double nextDouble() => nextUint32() / 4294967296.0;

  /// A value in `[min, max)`.
  double nextDoubleRange(double min, double max) => min + (max - min) * nextDouble();

  bool chance(double probability) => nextDouble() < probability;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }

  /// Picks an index with probability proportional to its weight.
  int pickWeighted(List<double> weights) {
    var total = 0.0;
    for (final w in weights) {
      if (w > 0) total += w;
    }
    if (total <= 0) return nextInt(weights.length);
    var roll = nextDouble() * total;
    for (var i = 0; i < weights.length; i++) {
      final w = weights[i];
      if (w <= 0) continue;
      roll -= w;
      if (roll < 0) return i;
    }
    return weights.length - 1;
  }

  /// A new independent seed derived from the current state and a salt.
  int deriveSeed(int salt) => combineSeeds(nextUint32(), salt);
}
