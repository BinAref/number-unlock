// Synthesises every sound of the game (assets/audio/): soft, warm effects
// and two seamless ambient loops (day and night). Music is encoded to MP3
// with ffmpeg when available.
//
// Run: dart run tool/generate_audio.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int rate = 22050;
final math.Random _rng = math.Random(7);

class Buf {
  Buf(double seconds) : data = Float64List((seconds * rate).round());
  final Float64List data;
  int get length => data.length;
}

double _env(double t, double attack, double decay) => t < attack ? t / attack : math.exp(-(t - attack) / decay);

/// A plucked / bell tone made of a few partials with an exponential tail.
void tone(Buf b, double start, double freq, double amp, {double attack = 0.005, double decay = 0.4, List<double> partials = const [1, 0.32, 0.12], double length = 0, double vibrato = 0, double detune = 0}) {
  final s0 = (start * rate).round();
  final n = ((length > 0 ? length : decay * 6) * rate).round();
  for (var i = 0; i < n; i++) {
    final idx = s0 + i;
    if (idx < 0) continue;
    if (idx >= b.length) break;
    final t = i / rate;
    final e = _env(t, attack, decay);
    if (e < 1e-4 && t > attack) break;
    var v = 0.0;
    for (var k = 0; k < partials.length; k++) {
      final f = freq * (k + 1) * (1 + detune * k) * (1 + vibrato * math.sin(2 * math.pi * 5.5 * t));
      v += partials[k] * math.sin(2 * math.pi * f * t + k);
    }
    b.data[idx] += amp * e * v;
  }
}

/// Soft filtered noise (whooshes, thuds, paper).
void noise(Buf b, double start, double dur, double amp, {double smooth = 0.9, double attack = 0.02}) {
  final s0 = (start * rate).round();
  final n = (dur * rate).round();
  var y = 0.0;
  for (var i = 0; i < n; i++) {
    final idx = s0 + i;
    if (idx >= b.length) break;
    final t = i / n;
    final e = (t < attack ? t / attack : 1.0) * math.pow(1 - t, 1.6);
    y = smooth * y + (1 - smooth) * (_rng.nextDouble() * 2 - 1);
    b.data[idx] += amp * e * y * 4;
  }
}

/// A slow pad chord (soft attack and release, gently detuned).
void pad(Buf b, double start, double dur, List<double> freqs, double amp) {
  final s0 = (start * rate).round();
  final n = (dur * rate).round();
  for (var i = 0; i < n; i++) {
    final idx = (s0 + i) % b.length;
    final t = i / rate;
    final x = i / n;
    final e = math.min(1.0, x / 0.25) * math.min(1.0, (1 - x) / 0.3);
    var v = 0.0;
    for (final f in freqs) {
      v += math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.003 * t + 1) + 0.18 * math.sin(2 * math.pi * f * 2 * t);
    }
    b.data[idx] += amp * e * v / freqs.length;
  }
}

/// Schroeder reverb; [wrap] folds the tail onto the start for seamless loops.
void reverb(Buf b, {double wet = 0.25, double feedback = 0.78, bool wrap = false}) {
  final dry = Float64List.fromList(b.data);
  final n = b.length;
  final out = Float64List(n);
  final passes = wrap ? 2 : 1;
  for (final d in const [779, 809, 746, 711]) {
    final line = Float64List(d);
    var p = 0;
    for (var pass = 0; pass < passes; pass++) {
      for (var i = 0; i < n; i++) {
        final y = line[p];
        line[p] = dry[i] + y * feedback;
        p = (p + 1) % d;
        if (pass == passes - 1) out[i] += y * 0.25;
      }
    }
  }
  for (final d in const [113, 278]) {
    final line = Float64List(d);
    var p = 0;
    for (var i = 0; i < n; i++) {
      final buf = line[p];
      final y = -out[i] + buf;
      line[p] = out[i] + buf * 0.5;
      out[i] = y;
      p = (p + 1) % d;
    }
  }
  for (var i = 0; i < n; i++) {
    b.data[i] = dry[i] * (1 - wet) + out[i] * wet;
  }
}

void save(Buf b, String path, {double peak = 0.8}) {
  var max = 1e-9;
  for (final v in b.data) {
    max = math.max(max, v.abs());
  }
  final pcm = Int16List(b.length);
  for (var i = 0; i < b.length; i++) {
    final v = math.tan(1) * 0 + _soft(b.data[i] / max * peak);
    pcm[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  final bytes = BytesBuilder();
  void u32(int v) => bytes.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => bytes.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  bytes.add('RIFF'.codeUnits);
  u32(36 + pcm.length * 2);
  bytes.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(rate);
  u32(rate * 2);
  u16(2);
  u16(16);
  bytes.add('data'.codeUnits);
  u32(pcm.length * 2);
  bytes.add(pcm.buffer.asUint8List());
  File(path).writeAsBytesSync(bytes.toBytes());
}

double _soft(double x) => x.abs() < 0.6 ? x : x.sign * (0.6 + 0.4 * (1 - math.exp(-(x.abs() - 0.6) / 0.4)));

double note(int semitonesFromA4) => 440 * math.pow(2, semitonesFromA4 / 12).toDouble();

void main() {
  final dir = Directory('assets/audio')..createSync(recursive: true);
  String p(String name) => '${dir.path}/$name';

  // Tile notes: a C-major pentatonic ladder, so every solution hums a tune.
  const ladder = [3, 5, 7, 10, 12, 15, 17, 19, 22];
  for (var v = 1; v <= 9; v++) {
    final b = Buf(0.9);
    tone(b, 0, note(ladder[v - 1]), 0.6, decay: 0.22, partials: const [1, 0.28, 0.1, 0.05]);
    tone(b, 0, note(ladder[v - 1] + 12), 0.12, decay: 0.12);
    reverb(b, wet: 0.22);
    save(b, p('sfx_pick_$v.wav'), peak: 0.7);
  }

  var b = Buf(0.12);
  tone(b, 0, 1320, 0.5, attack: 0.001, decay: 0.018, partials: const [1, 0.2]);
  noise(b, 0, 0.03, 0.15, smooth: 0.6);
  save(b, p('sfx_tap.wav'), peak: 0.5);

  b = Buf(0.06);
  tone(b, 0, 2000, 0.4, attack: 0.001, decay: 0.01);
  save(b, p('sfx_toggle.wav'), peak: 0.45);

  b = Buf(0.3);
  tone(b, 0, 150, 0.7, attack: 0.002, decay: 0.05, partials: const [1, 0.3]);
  noise(b, 0, 0.12, 0.3, smooth: 0.93);
  save(b, p('sfx_land.wav'), peak: 0.55);

  b = Buf(0.9);
  for (var k = 0; k < 3; k++) {
    tone(b, k * 0.06, note(31 + [0, 3, 8][k]), 0.35, decay: 0.18, partials: const [1, 0.4, 0.2]);
  }
  reverb(b, wet: 0.35);
  save(b, p('sfx_unlock.wav'), peak: 0.6);

  b = Buf(1.1);
  tone(b, 0, note(15), 0.5, decay: 0.32, partials: const [1, 0.5, 0.25, 0.1]);
  tone(b, 0.05, note(22), 0.4, decay: 0.36, partials: const [1, 0.4, 0.2]);
  reverb(b, wet: 0.3);
  save(b, p('sfx_match.wav'), peak: 0.75);

  b = Buf(1.2);
  for (var k = 0; k < 4; k++) {
    tone(b, k * 0.08, note(15 + [0, 4, 7, 12][k]), 0.4, decay: 0.28, partials: const [1, 0.45, 0.2]);
  }
  reverb(b, wet: 0.32);
  save(b, p('sfx_chain.wav'), peak: 0.8);

  b = Buf(0.45);
  noise(b, 0, 0.4, 0.55, smooth: 0.82, attack: 0.4);
  save(b, p('sfx_swap.wav'), peak: 0.5);

  b = Buf(1.3);
  for (var k = 0; k < 6; k++) {
    tone(b, k * 0.07, note(27 + [0, 7, 12, 16, 19, 24][k]), 0.22, decay: 0.3, vibrato: 0.004, partials: const [1, 0.3]);
  }
  reverb(b, wet: 0.45);
  save(b, p('sfx_hint.wav'), peak: 0.6);

  b = Buf(1.0);
  noise(b, 0, 0.25, 0.4, smooth: 0.95);
  tone(b, 0.18, note(10), 0.45, decay: 0.35, partials: const [1, 0.5, 0.3]);
  reverb(b, wet: 0.3);
  save(b, p('sfx_slot.wav'), peak: 0.7);

  b = Buf(0.6);
  tone(b, 0, 2093, 0.4, attack: 0.001, decay: 0.07, partials: const [1, 0.6, 0.3], detune: 0.21);
  tone(b, 0.07, 2637, 0.35, attack: 0.001, decay: 0.09, partials: const [1, 0.5, 0.3], detune: 0.19);
  reverb(b, wet: 0.25);
  save(b, p('sfx_coin.wav'), peak: 0.6);

  b = Buf(2.6);
  const harp = [3, 7, 10, 15, 19, 22, 27];
  for (var k = 0; k < harp.length; k++) {
    tone(b, k * 0.09, note(harp[k]), 0.35, decay: 0.5, partials: const [1, 0.3, 0.12]);
  }
  for (final s in const [3, 7, 10, 15]) {
    tone(b, 0.75, note(s), 0.22, attack: 0.03, decay: 0.7, partials: const [1, 0.4, 0.15]);
  }
  reverb(b, wet: 0.35);
  save(b, p('sfx_win.wav'), peak: 0.85);

  b = Buf(1.8);
  for (var k = 0; k < 3; k++) {
    tone(b, k * 0.28, note([0, -4, -7][k]), 0.35, attack: 0.04, decay: 0.45, partials: const [1, 0.25]);
  }
  reverb(b, wet: 0.4);
  save(b, p('sfx_lose.wav'), peak: 0.6);

  b = Buf(0.35);
  noise(b, 0, 0.3, 0.5, smooth: 0.7, attack: 0.15);
  save(b, p('sfx_page.wav'), peak: 0.45);

  b = Buf(1.2);
  for (var i = 0; i < (0.35 * rate).round(); i++) {
    final t = i / rate;
    b.data[i] += 0.25 * math.sin(2 * math.pi * (90 + 120 * t) * t) * (1 - t / 0.35);
  }
  for (var k = 0; k < 4; k++) {
    tone(b, 0.3 + k * 0.07, note(34 + [0, 4, 7, 12][k]), 0.2, decay: 0.2, partials: const [1, 0.5]);
  }
  reverb(b, wet: 0.35);
  save(b, p('sfx_chest.wav'), peak: 0.65);

  b = Buf(0.3);
  tone(b, 0, 147, 0.6, attack: 0.002, decay: 0.06, partials: const [1, 0.5, 0.2]);
  save(b, p('sfx_error.wav'), peak: 0.45);

  _music(p('music_day'), bpm: 72, chords: const [
    [-9, -5, -2, 2], // C maj7
    [-12, -9, -5, -2], // A m7
    [-16, -12, -9, -5], // F maj7
    [-14, -10, -7, -2], // G6
  ], scale: const [3, 5, 7, 10, 12, 15, 17, 19], density: 0.55, seed: 11);
  _music(p('music_night'), bpm: 60, chords: const [
    [-12, -9, -5, -1], // A m9-ish
    [-16, -12, -9, -5], // F maj7
    [-9, -5, -2, 2], // C maj7
    [-17, -14, -10, -7], // E m7
  ], scale: const [0, 3, 5, 7, 10, 12, 15, 19], density: 0.38, seed: 23);
}

void _music(String base, {required double bpm, required List<List<int>> chords, required List<int> scale, required double density, required int seed}) {
  final beat = 60 / bpm;
  const barsPerChord = 2;
  final bars = chords.length * barsPerChord * 2;
  final seconds = bars * 4 * beat;
  final b = Buf(seconds);
  final r = math.Random(seed);
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[(bar ~/ barsPerChord) % chords.length];
    final start = bar * 4 * beat;
    if (bar % barsPerChord == 0) pad(b, start, 4 * beat * barsPerChord + beat, [for (final c in chord) note(c)], 0.16);
    tone(b, start, note(chord.first - 12), 0.16, attack: 0.05, decay: 1.4, partials: const [1, 0.3]);
    for (var step = 0; step < 8; step++) {
      if (r.nextDouble() > density) continue;
      final n = scale[r.nextInt(scale.length)];
      tone(b, start + step * beat / 2, note(n), 0.11 + 0.05 * r.nextDouble(), decay: 0.55, partials: const [1, 0.25, 0.08]);
    }
  }
  reverb(b, wet: 0.38, feedback: 0.82, wrap: true);
  final wav = '$base.wav';
  save(b, wav, peak: 0.55);
  try {
    final res = Process.runSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-b:a', '80k', '$base.mp3']);
    if (res.exitCode == 0) {
      File(wav).deleteSync();
    } else {
      stderr.writeln(res.stderr);
    }
  } on ProcessException {
    stderr.writeln('ffmpeg not found: keeping $wav (rename the asset or install ffmpeg).');
  }
}
