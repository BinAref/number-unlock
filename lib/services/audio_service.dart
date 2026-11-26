import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Every sound the game makes (files in `assets/audio/`).
enum Sfx {
  tap('sfx_tap.wav'),
  land('sfx_land.wav'),
  unlock('sfx_unlock.wav'),
  match('sfx_match.wav'),
  chain('sfx_chain.wav'),
  swap('sfx_swap.wav'),
  hint('sfx_hint.wav'),
  slotOpen('sfx_slot.wav'),
  coin('sfx_coin.wav'),
  win('sfx_win.wav'),
  lose('sfx_lose.wav'),
  page('sfx_page.wav'),
  chest('sfx_chest.wav'),
  toggle('sfx_toggle.wav'),
  error('sfx_error.wav');

  const Sfx(this.file);

  final String file;
}

/// Calm, layered audio: short sound effects from a small player pool and a
/// looping ambient track per theme. Picking a tile plays a soft note tuned
/// to its number, so every solution hums a little melody.
class AudioService {
  AudioService({required bool music, required bool sfx, this.enabled = true}) : _musicOn = music, _sfxOn = sfx;

  /// False in tests and tools: no audio players are ever created.
  final bool enabled;

  static const int _poolSize = 6;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  AudioPlayer? _music;
  String? _track;
  bool _musicOn;
  bool _sfxOn;
  bool _unlocked = !kIsWeb;

  Future<void> init() async {
    if (!enabled) return;
    try {
      await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } on Object {
      // Not supported on every platform; defaults are fine.
    }
    for (var i = 0; i < _poolSize; i++) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
    }
  }

  /// Browsers only allow sound after a user gesture.
  void userGesture() {
    if (_unlocked) return;
    _unlocked = true;
    if (_musicOn && _track != null) _startTrack(_track!);
  }

  void _play(String file, {double volume = 0.8}) {
    if (!_sfxOn || !_unlocked || _pool.isEmpty) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    p.stop().then((_) => p.play(AssetSource('audio/$file'), volume: volume)).catchError((Object _) {});
  }

  void play(Sfx sfx, {double volume = 0.8}) => _play(sfx.file, volume: volume);

  /// The soft note of a picked tile (1..9).
  void pick(int value) => _play('sfx_pick_${value.clamp(1, 9)}.wav', volume: 0.7);

  /// Starts (or switches to) the ambient loop for [themeId].
  void music(String themeId) {
    _track = 'music_$themeId.mp3';
    if (_musicOn && _unlocked) _startTrack(_track!);
  }

  Future<void> _startTrack(String file) async {
    if (!enabled) return;
    final player = _music ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
    try {
      await player.stop();
      await player.play(AssetSource('audio/$file'), volume: 0.42);
    } on Object {
      // Missing track or no audio device: stay silent.
    }
  }

  void setMusic(bool on) {
    _musicOn = on;
    if (!on) {
      _music?.stop();
    } else if (_track != null && _unlocked) {
      _startTrack(_track!);
    }
  }

  void setSfx(bool on) => _sfxOn = on;

  void pause() => _music?.pause();

  void resume() {
    if (_musicOn && _unlocked) _music?.resume();
  }
}

/// Vibration feedback, honouring the player's setting.
class HapticsService {
  HapticsService({required this.enabled});

  bool enabled;

  void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }
}
