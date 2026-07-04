import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class GameAudioController {
  final AudioPlayer _bgmPlayer = AudioPlayer(playerId: 'bgm');
  final AudioPlayer _clickPlayer = AudioPlayer(playerId: 'click_sfx');
  final AudioPlayer _landPlayer = AudioPlayer(playerId: 'land_sfx');
  final AudioPlayer _freezePlayer = AudioPlayer(playerId: 'freeze_sfx');
  bool _bgmStarted = false;

  Future<void> startBgm() async {
    if (_bgmStarted) return;
    _bgmStarted = true;
    try {
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(0.45);
      await _bgmPlayer.play(AssetSource('bgm/moonlight.ogg'));
    } catch (_) {
      _bgmStarted = false;
    }
  }

  Future<void> pauseBgm() async {
    if (!_bgmStarted) return;
    try {
      await _bgmPlayer.pause();
    } catch (_) {}
  }

  Future<void> resumeBgm() async {
    if (!_bgmStarted) {
      await startBgm();
      return;
    }
    try {
      await _bgmPlayer.resume();
    } catch (_) {}
  }

  Future<void> restartBgm() async {
    _bgmStarted = false;
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
    await startBgm();
  }

  Future<void> stopBgm() async {
    _bgmStarted = false;
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  void playClick() {
    unawaited(_playSfx(_clickPlayer, 'audio/click.ogg', volume: 0.55));
  }

  void playLand() {
    unawaited(_playSfx(_landPlayer, 'audio/footstep_snow.ogg', volume: 0.65));
  }

  void playFreeze() {
    unawaited(_playSfx(_freezePlayer, 'audio/ice-freezing.mp3', volume: 0.75));
  }

  Future<void> dispose() async {
    await Future.wait([
      _bgmPlayer.dispose(),
      _clickPlayer.dispose(),
      _landPlayer.dispose(),
      _freezePlayer.dispose(),
    ]);
  }

  Future<void> _playSfx(
    AudioPlayer player,
    String asset, {
    double volume = 0.7,
  }) async {
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(asset));
    } catch (_) {}
  }
}
