// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class GameAudioController {
  GameAudioController();

  html.AudioElement? _bgm;
  bool _bgmStarted = false;

  Future<void> startBgm() async {
    if (_bgmStarted) return;
    _bgmStarted = true;
    final bgm =
        _bgm ??
        (html.AudioElement('assets/assets/bgm/moonlight.ogg')
          ..loop = true
          ..volume = 0.45);
    bgm.currentTime = 0;
    _bgm = bgm;
    try {
      await bgm.play();
    } catch (_) {
      _bgmStarted = false;
    }
  }

  Future<void> pauseBgm() async {
    _bgm?.pause();
  }

  Future<void> resumeBgm() async {
    final bgm = _bgm;
    if (bgm == null || !_bgmStarted) {
      await startBgm();
      return;
    }
    try {
      await bgm.play();
    } catch (_) {}
  }

  Future<void> restartBgm() async {
    final bgm = _bgm;
    if (bgm != null) {
      bgm.pause();
      bgm.currentTime = 0;
    }
    _bgmStarted = false;
    await startBgm();
  }

  Future<void> stopBgm() async {
    final bgm = _bgm;
    if (bgm != null) {
      bgm.pause();
      bgm.currentTime = 0;
    }
    _bgmStarted = false;
  }

  void playClick() => _playOneShot('assets/assets/audio/click.ogg', 0.55);

  void playLand() =>
      _playOneShot('assets/assets/audio/footstep_snow.ogg', 0.65);

  void playFreeze() =>
      _playOneShot('assets/assets/audio/ice-freezing.mp3', 0.75);

  Future<void> dispose() async {
    _bgm?.pause();
    _bgm = null;
  }

  void _playOneShot(String source, double volume) {
    final audio = html.AudioElement(source)..volume = volume;
    audio.play().catchError((_) {});
  }
}
