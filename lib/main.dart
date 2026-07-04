import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (supportsMobileAds) {
    unawaited(MobileAds.instance.initialize());
  }
  runApp(const SnowCubeApp());
}

bool get supportsMobileAds =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

const String androidBannerAdUnitId = 'ca-app-pub-8887961232064587/6900879447';
const String bestIceLinesKey = 'best_ice_lines';

const int boardCols = 10;
const int boardRows = 20;
const double baseCellSize = 30;
const double stageSeconds = 5.5;

class SnowCubeApp extends StatelessWidget {
  const SnowCubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stack Over Snow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff82c9ff),
          brightness: Brightness.dark,
        ),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const SnowCubeScreen(),
    );
  }
}

enum GamePhase { title, playing, paused, gameOver }

enum CubeKind { snow, ice }

class CubeCell {
  CubeCell.snow() : kind = CubeKind.snow, age = 0, stage = 0;

  CubeCell.ice() : kind = CubeKind.ice, age = 0, stage = 0;

  CubeKind kind;
  double age;
  int stage;

  bool get isIce => kind == CubeKind.ice;
}

class Piece {
  Piece(this.type, this.shape, this.x, this.y);

  String type;
  List<List<int>> shape;
  int x;
  int y;
}

class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
  });

  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
}

class IceLineDrop {
  IceLineDrop({required this.row, required this.startOffsetRows});

  int row;
  double startOffsetRows;
  double age = 0;

  static const double duration = 0.26;

  double get progress => (age / duration).clamp(0, 1);

  double get currentOffsetRows {
    final eased = 1 - math.pow(1 - progress, 3).toDouble();
    return startOffsetRows * (1 - eased);
  }
}

const Map<String, List<List<int>>> tetrominoes = {
  'I': [
    [1, 1, 1, 1],
  ],
  'O': [
    [1, 1],
    [1, 1],
  ],
  'T': [
    [0, 1, 0],
    [1, 1, 1],
  ],
  'S': [
    [0, 1, 1],
    [1, 1, 0],
  ],
  'Z': [
    [1, 1, 0],
    [0, 1, 1],
  ],
  'J': [
    [1, 0, 0],
    [1, 1, 1],
  ],
  'L': [
    [0, 0, 1],
    [1, 1, 1],
  ],
};

class SnowGameModel {
  SnowGameModel() {
    reset();
  }

  final math.Random _random = math.Random();
  late List<List<CubeCell?>> board;
  Piece? current;
  late String nextType;
  GamePhase phase = GamePhase.title;
  int height = 0;
  int bestHeight = 0;
  int pieces = 0;
  int iceLines = 0;
  double elapsed = 0;
  double dropTimer = 0;
  double meltTimer = 0;
  double lineFlash = 0;
  double scrollPulse = 0;
  String status = '한 줄이 완성되면 얼음이 됩니다.';
  final List<Particle> particles = [];
  final List<IceLineDrop> iceLineDrops = [];

  void reset() {
    board = List.generate(
      boardRows,
      (_) => List<CubeCell?>.filled(boardCols, null),
    );
    current = null;
    nextType = _randomType();
    height = 0;
    pieces = 0;
    iceLines = 0;
    elapsed = 0;
    dropTimer = 0;
    meltTimer = 0;
    lineFlash = 0;
    scrollPulse = 0;
    particles.clear();
    status = '한 줄이 완성되면 얼음이 됩니다.';
  }

  void start() {
    reset();
    phase = GamePhase.playing;
    _spawnPiece();
  }

  void togglePause() {
    if (phase == GamePhase.playing) {
      phase = GamePhase.paused;
      status = '';
    } else if (phase == GamePhase.paused) {
      phase = GamePhase.playing;
      status = '';
    }
  }

  void update(double dt) {
    if (phase != GamePhase.playing) return;
    elapsed += dt;
    dropTimer += dt;
    meltTimer += dt;
    lineFlash = math.max(0, lineFlash - dt);
    scrollPulse = math.max(0, scrollPulse - dt);

    _ageSnow(dt);
    _updateParticles(dt);
    _updateIceLineDrops(dt);

    final dropEvery = math.max(0.18, 0.78 - height * 0.015);
    if (dropTimer >= dropEvery) {
      stepDown();
      dropTimer = 0;
    }
  }

  double get meltProgress => (meltTimer / stageSeconds).clamp(0, 1);

  void move(int dx) {
    if (phase != GamePhase.playing || current == null) return;
    final piece = current!;
    if (!_collides(piece, piece.x + dx, piece.y, piece.shape)) {
      piece.x += dx;
    }
  }

  void rotate() {
    if (phase != GamePhase.playing || current == null) return;
    final piece = current!;
    final rotated = _rotateShape(piece.shape);
    for (final kick in [0, -1, 1, -2, 2]) {
      if (!_collides(piece, piece.x + kick, piece.y, rotated)) {
        piece.x += kick;
        piece.shape = rotated;
        return;
      }
    }
  }

  void softDrop() {
    if (phase != GamePhase.playing) return;
    stepDown();
    dropTimer = 0;
  }

  void hardDrop() {
    if (phase != GamePhase.playing || current == null) return;
    final piece = current!;
    while (!_collides(piece, piece.x, piece.y + 1, piece.shape)) {
      piece.y += 1;
    }
    _lockPiece();
    dropTimer = 0;
  }

  void stepDown() {
    if (phase != GamePhase.playing || current == null) return;
    final piece = current!;
    if (!_collides(piece, piece.x, piece.y + 1, piece.shape)) {
      piece.y += 1;
    } else {
      _lockPiece();
    }
  }

  void _spawnPiece() {
    final type = nextType;
    nextType = _randomType();
    final shape = tetrominoes[type]!.map((row) => [...row]).toList();
    current = Piece(type, shape, (boardCols - shape.first.length) ~/ 2, 0);
    if (_collides(current!, current!.x, current!.y, current!.shape)) {
      phase = GamePhase.gameOver;
      bestHeight = math.max(bestHeight, iceLines);
      status = 'Game Over';
    }
  }

  void _lockPiece() {
    final piece = current;
    if (piece == null) return;
    for (var r = 0; r < piece.shape.length; r += 1) {
      for (var c = 0; c < piece.shape[r].length; c += 1) {
        if (piece.shape[r][c] == 0) continue;
        final x = piece.x + c;
        final y = piece.y + r;
        if (x >= 0 && x < boardCols && y >= 0 && y < boardRows) {
          board[y][x] = CubeCell.snow();
        }
      }
    }
    pieces += 1;
    current = null;
    _freezeCompletedLines();
    _spawnPiece();
  }

  void _ageSnow(double dt) {
    var removed = false;
    for (var y = 0; y < boardRows; y += 1) {
      for (var x = 0; x < boardCols; x += 1) {
        final cell = board[y][x];
        if (cell == null || cell.isIce) continue;
        cell.age += dt;
        cell.stage = (cell.age ~/ stageSeconds).clamp(0, 4);
        if (cell.age >= stageSeconds * 5) {
          board[y][x] = null;
          removed = true;
          _burst(x + 0.5, y + 0.5, const Color(0xffeaf5ff), 5);
        }
      }
    }
    if (removed) {
      _settleUnsupportedIceLines();
      status = '';
    }
  }

  int _settleUnsupportedIceLines() {
    var totalDrops = 0;
    var moved = true;
    while (moved) {
      moved = false;
      for (var y = boardRows - 2; y >= 0; y -= 1) {
        if (!_isFullIceRow(y)) continue;
        if (!_isEmptyRow(y + 1)) continue;
        if (_currentOccupiesRow(y + 1)) continue;
        _recordIceLineDrop(y, y + 1);
        board[y + 1] = board[y];
        board[y] = List<CubeCell?>.filled(boardCols, null);
        totalDrops += 1;
        moved = true;
      }
    }
    if (totalDrops > 0) {
      scrollPulse = 0.45;
    }
    return totalDrops;
  }

  void _recordIceLineDrop(int fromRow, int toRow) {
    final existingIndex = iceLineDrops.indexWhere(
      (drop) => drop.row == fromRow,
    );
    final existing = existingIndex >= 0
        ? iceLineDrops.removeAt(existingIndex)
        : null;
    final visualStart = fromRow.toDouble() + (existing?.currentOffsetRows ?? 0);
    iceLineDrops.removeWhere((drop) => drop.row == toRow);
    iceLineDrops.add(
      IceLineDrop(row: toRow, startOffsetRows: visualStart - toRow.toDouble()),
    );
  }

  bool _isFullIceRow(int y) => board[y].every((cell) => cell?.isIce == true);

  bool _isEmptyRow(int y) => board[y].every((cell) => cell == null);

  bool _currentOccupiesRow(int row) {
    final piece = current;
    if (piece == null) return false;
    for (var r = 0; r < piece.shape.length; r += 1) {
      for (var c = 0; c < piece.shape[r].length; c += 1) {
        if (piece.shape[r][c] == 0) continue;
        if (piece.y + r == row) return true;
      }
    }
    return false;
  }

  void _freezeCompletedLines() {
    var froze = 0;
    for (var y = 0; y < boardRows; y += 1) {
      final row = board[y];
      if (row.every((cell) => cell != null) &&
          !row.every((cell) => cell!.isIce)) {
        for (var x = 0; x < boardCols; x += 1) {
          board[y][x] = CubeCell.ice();
          _burst(x + 0.5, y + 0.5, const Color(0xff90d7ff), 2);
        }
        froze += 1;
      }
    }
    if (froze > 0) {
      iceLines += froze;
      height += froze;
      bestHeight = math.max(bestHeight, iceLines);
      lineFlash = 0.55;
      scrollPulse = 0.5;
      final dropped = _settleUnsupportedIceLines();
      if (dropped > 0) {
        status = '';
      } else {
        status = '';
      }
    }
  }

  bool _collides(Piece piece, int px, int py, List<List<int>> shape) {
    for (var r = 0; r < shape.length; r += 1) {
      for (var c = 0; c < shape[r].length; c += 1) {
        if (shape[r][c] == 0) continue;
        final x = px + c;
        final y = py + r;
        if (x < 0 || x >= boardCols || y >= boardRows) return true;
        if (y >= 0 && board[y][x] != null) return true;
      }
    }
    return false;
  }

  List<List<int>> _rotateShape(List<List<int>> shape) {
    final rows = shape.length;
    final cols = shape.first.length;
    return List.generate(
      cols,
      (x) => List.generate(rows, (y) => shape[rows - 1 - y][x]),
    );
  }

  String _randomType() {
    final keys = tetrominoes.keys.toList(growable: false);
    return keys[_random.nextInt(keys.length)];
  }

  void _burst(double x, double y, Color color, int count) {
    for (var i = 0; i < count; i += 1) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 0.8 + _random.nextDouble() * 1.8;
      particles.add(
        Particle(
          x: x,
          y: y,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed - 0.8,
          life: 0.4 + _random.nextDouble() * 0.35,
          color: color,
        ),
      );
    }
  }

  void _updateParticles(double dt) {
    for (final particle in particles) {
      particle.life -= dt;
      particle.vy += dt * 3.5;
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
    }
    particles.removeWhere((particle) => particle.life <= 0);
  }

  void _updateIceLineDrops(double dt) {
    for (final drop in iceLineDrops) {
      drop.age += dt;
    }
    iceLineDrops.removeWhere((drop) => drop.progress >= 1);
  }
}

class CubeImages {
  CubeImages(this.stages, this.ice);

  final List<ui.Image> stages;
  final ui.Image ice;
}

class SnowCubeScreen extends StatefulWidget {
  const SnowCubeScreen({super.key});

  @override
  State<SnowCubeScreen> createState() => _SnowCubeScreenState();
}

class _SnowCubeScreenState extends State<SnowCubeScreen> {
  final SnowGameModel game = SnowGameModel();
  final FocusNode focusNode = FocusNode();
  Timer? timer;
  CubeImages? images;
  BannerAd? bannerAd;
  bool bannerAdReady = false;
  int savedBestIceLines = 0;
  DateTime lastTick = DateTime.now();
  double backgroundTime = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _loadBestScore();
    _loadBannerAd();
    timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  @override
  void dispose() {
    timer?.cancel();
    bannerAd?.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    final best = prefs.getInt(bestIceLinesKey) ?? 0;
    if (!mounted) return;
    setState(() {
      savedBestIceLines = best;
      game.bestHeight = best;
    });
  }

  Future<void> _saveBestScoreIfNeeded() async {
    if (game.bestHeight <= savedBestIceLines) return;
    savedBestIceLines = game.bestHeight;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(bestIceLinesKey, savedBestIceLines);
  }

  void _loadBannerAd() {
    if (!supportsMobileAds) return;
    bannerAd = BannerAd(
      adUnitId: androidBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() => bannerAdReady = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() => bannerAdReady = false);
        },
      ),
    )..load();
  }

  Future<void> _loadImages() async {
    final loaded = await Future.wait([
      _loadUiImage('assets/cubes/cube_normal.png'),
      _loadUiImage('assets/cubes/cube_crack_1.png'),
      _loadUiImage('assets/cubes/cube_crack_2.png'),
      _loadUiImage('assets/cubes/cube_crack_3.png'),
      _loadUiImage('assets/cubes/cube_crack_4.png'),
      _loadUiImage('assets/cubes/cube_frozen.png'),
    ]);
    setState(() {
      images = CubeImages(loaded.take(5).toList(), loaded.last);
    });
  }

  Future<ui.Image> _loadUiImage(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(lastTick).inMicroseconds / 1000000;
    lastTick = now;
    final frameDt = dt.clamp(0, 0.05).toDouble();
    backgroundTime += frameDt;
    game.update(frameDt);
    unawaited(_saveBestScoreIfNeeded());
    if (mounted) setState(() {});
  }

  void _startGame() {
    focusNode.requestFocus();
    setState(game.start);
  }

  Future<void> _openPauseMenu() async {
    if (game.phase == GamePhase.playing) {
      setState(game.togglePause);
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PauseMenu(
        onResume: () {
          Navigator.of(context).pop();
          if (game.phase == GamePhase.paused) {
            setState(game.togglePause);
          }
        },
        onRestart: () {
          Navigator.of(context).pop();
          _startGame();
        },
        onHome: () {
          Navigator.of(context).pop();
          setState(() {
            game.phase = GamePhase.title;
            game.current = null;
          });
        },
      ),
    );
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyA:
        game.move(-1);
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyD:
        game.move(1);
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.keyW:
        game.rotate();
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.keyS:
        game.softDrop();
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.keyP:
        unawaited(_openPauseMenu());
      default:
        return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: const Color(0xff050817),
        bottomNavigationBar: bannerAdReady && bannerAd != null
            ? SafeArea(
                child: SizedBox(
                  height: bannerAd!.size.height.toDouble(),
                  child: Center(
                    child: SizedBox(
                      width: bannerAd!.size.width.toDouble(),
                      height: bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: bannerAd!),
                    ),
                  ),
                ),
              )
            : null,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final shortSide = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final cell = math
                .min(baseCellSize, (shortSide - 64) / boardCols)
                .clamp(18.0, 32.0);
            final boardSize = Size(cell * boardCols, cell * boardRows);
            return Stack(
              children: [
                Positioned.fill(
                  child: SnowNightBackground(time: backgroundTime),
                ),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: game.phase == GamePhase.title
                            ? TitlePanel(
                                bestHeight: game.bestHeight,
                                onStart: _startGame,
                              )
                            : GamePanel(
                                game: game,
                                images: images,
                                boardSize: boardSize,
                                cell: cell,
                                onPause: () => unawaited(_openPauseMenu()),
                                onRestart: _startGame,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SnowNightBackground extends StatelessWidget {
  const SnowNightBackground({super.key, required this.time});

  final double time;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: BackgroundPainter(time));
  }
}

class BackgroundPainter extends CustomPainter {
  BackgroundPainter(this.time);

  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final sky = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xff02030a), Color(0xff050817), Color(0xff090c18)],
    );
    paint.shader = sky.createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
    paint.shader = null;

    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.72);
    for (var i = 0; i < 70; i += 1) {
      final x = ((i * 137) % 997) / 997 * size.width;
      final y = ((i * 251) % 991) / 991 * size.height;
      final side = i % 11 == 0 ? 2.0 : 1.0;
      canvas.drawRect(
        Rect.fromLTWH(x.floorToDouble(), y.floorToDouble(), side, side),
        starPaint,
      );
    }

    for (var i = 0; i < 150; i += 1) {
      final lane = ((i * 67) % 1000) / 1000;
      final drift = math.sin(time * 0.55 + i) * 7;
      final speed = 16 + (i % 7) * 8;
      final x = (lane * size.width + drift) % size.width;
      final y = ((i * 113) % 1000) / 1000 * size.height + (time * speed);
      final wrappedY = y % size.height;
      final side = i % 5 == 0 ? 3.0 : 2.0;
      final alpha = 0.35 + (i % 4) * 0.12;
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawRect(
        Rect.fromLTWH(x.floorToDouble(), wrappedY.floorToDouble(), side, side),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundPainter oldDelegate) =>
      oldDelegate.time != time;
}

class TitlePanel extends StatelessWidget {
  const TitlePanel({
    super.key,
    required this.bestHeight,
    required this.onStart,
  });

  final int bestHeight;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Image.asset(
          'assets/ui/logo_no_bg.png',
          width: MediaQuery.sizeOf(context).width < 520 ? 300 : 430,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          errorBuilder: (context, error, stackTrace) => Text(
            'STACK\nOVER\nSNOW',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: MediaQuery.sizeOf(context).width < 520 ? 52 : 72,
              height: 0.92,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: const Color(0xffdff4ff),
              shadows: const [
                Shadow(offset: Offset(0, 5), color: Color(0xff24518e)),
                Shadow(offset: Offset(4, 8), color: Color(0xff071124)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 56),
        PixelButton(label: 'GAME START', large: true, onPressed: onStart),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SquareIconButton(icon: Icons.settings, onPressed: () {}),
                const SizedBox(width: 10),
                SquareIconButton(icon: Icons.music_note, onPressed: () {}),
              ],
            ),
            Column(
              children: [
                const Text(
                  'BEST ICE LINES',
                  style: TextStyle(color: Color(0xffb7d7ff), fontSize: 13),
                ),
                Text(
                  '$bestHeight',
                  style: const TextStyle(
                    color: Color(0xff8fd7ff),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SquareIconButton(icon: Icons.emoji_events, onPressed: () {}),
          ],
        ),
      ],
    );
  }
}

class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.game,
    required this.images,
    required this.boardSize,
    required this.cell,
    required this.onPause,
    required this.onRestart,
  });

  final SnowGameModel game;
  final CubeImages? images;
  final Size boardSize;
  final double cell;
  final VoidCallback onPause;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final board = SizedBox(
      width: boardSize.width,
      height: boardSize.height,
      child: CustomPaint(
        painter: BoardPainter(game: game, images: images, cell: cell),
      ),
    );

    final side = SideHud(
      game: game,
      images: images,
      cell: cell,
      onPause: onPause,
      onRestart: onRestart,
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ICE LINES',
              style: TextStyle(
                color: Color(0xffe6f4ff),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${game.iceLines}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: wide
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [board, const SizedBox(width: 18), side],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [board, const SizedBox(height: 12), side],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TouchControls(game: game),
      ],
    );
  }
}

class BoardPainter extends CustomPainter {
  BoardPainter({required this.game, required this.images, required this.cell});

  final SnowGameModel game;
  final CubeImages? images;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final boardRect = Offset.zero & size;
    final bgPaint = Paint()
      ..color = const Color(0xff071127).withValues(alpha: 0.72);
    canvas.drawRect(boardRect, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0xff34507a).withValues(alpha: 0.32)
      ..strokeWidth = 1;
    for (var x = 0; x <= boardCols; x += 1) {
      canvas.drawLine(
        Offset(x * cell, 0),
        Offset(x * cell, size.height),
        gridPaint,
      );
    }
    for (var y = 0; y <= boardRows; y += 1) {
      canvas.drawLine(
        Offset(0, y * cell),
        Offset(size.width, y * cell),
        gridPaint,
      );
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xff8fa8e8);
    canvas.drawRect(boardRect.deflate(1), borderPaint);

    final offsetY = game.scrollPulse > 0
        ? math.sin(game.scrollPulse * math.pi * 8) * 1.5
        : 0.0;
    canvas.save();
    canvas.translate(0, offsetY);
    for (var y = 0; y < boardRows; y += 1) {
      final drop = _dropForRow(y);
      final visualY = y.toDouble() + (drop?.currentOffsetRows ?? 0);
      for (var x = 0; x < boardCols; x += 1) {
        final cellData = game.board[y][x];
        if (cellData == null) continue;
        _drawCube(canvas, x, visualY, cellData.isIce ? -1 : cellData.stage);
      }
    }

    final piece = game.current;
    if (piece != null) {
      for (var r = 0; r < piece.shape.length; r += 1) {
        for (var c = 0; c < piece.shape[r].length; c += 1) {
          if (piece.shape[r][c] == 0) continue;
          _drawCube(canvas, piece.x + c, (piece.y + r).toDouble(), 0);
        }
      }
    }
    canvas.restore();

    for (final particle in game.particles) {
      final alpha = particle.life.clamp(0, 1).toDouble();
      final paint = Paint()..color = particle.color.withValues(alpha: alpha);
      canvas.drawRect(
        Rect.fromLTWH(particle.x * cell - 1.5, particle.y * cell - 1.5, 3, 3),
        paint,
      );
    }

    if (game.phase == GamePhase.paused || game.phase == GamePhase.gameOver) {
      final overlay = Paint()
        ..color = const Color(0xff030612).withValues(alpha: 0.7);
      canvas.drawRect(boardRect, overlay);
      final text = game.phase == GamePhase.paused ? 'PAUSED' : 'GAME OVER';
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontSize: 28,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (size.width - painter.width) / 2,
          (size.height - painter.height) / 2,
        ),
      );
    }
  }

  IceLineDrop? _dropForRow(int row) {
    for (final drop in game.iceLineDrops) {
      if (drop.row == row) return drop;
    }
    return null;
  }

  void _drawCube(Canvas canvas, int x, double y, int stage) {
    final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
    if (images != null) {
      final image = stage < 0 ? images!.ice : images!.stages[stage.clamp(0, 4)];
      paintImage(
        canvas: canvas,
        rect: rect.inflate(cell * (stage == 0 ? 0.23 : 0.17)),
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      );
      return;
    }
    final fallback = Paint()
      ..color = stage < 0
          ? const Color(0xff79c8ef)
          : Color.lerp(Colors.white, const Color(0xffb7c3de), stage / 4)!;
    canvas.drawRect(rect, fallback);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xff14233f),
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}

class SideHud extends StatelessWidget {
  const SideHud({
    super.key,
    required this.game,
    required this.images,
    required this.cell,
    required this.onPause,
    required this.onRestart,
  });

  final SnowGameModel game;
  final CubeImages? images;
  final double cell;
  final VoidCallback onPause;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SquareIconButton(
                icon: game.phase == GamePhase.paused
                    ? Icons.play_arrow
                    : Icons.pause,
                onPressed: onPause,
              ),
              const SizedBox(width: 8),
              SquareIconButton(icon: Icons.restart_alt, onPressed: onRestart),
            ],
          ),
          const SizedBox(height: 18),
          HudBox(
            title: 'NEXT',
            child: SizedBox(
              height: 76,
              child: CustomPaint(
                painter: NextPiecePainter(type: game.nextType, images: images),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NextPiecePainter extends CustomPainter {
  NextPiecePainter({required this.type, required this.images});

  final String type;
  final CubeImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = tetrominoes[type]!;
    final cell = math.min(size.width / 5, size.height / 4);
    final totalW = shape.first.length * cell;
    final totalH = shape.length * cell;
    final ox = (size.width - totalW) / 2;
    final oy = (size.height - totalH) / 2;
    final fill = Paint()..color = const Color(0xff61c7ff);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xff102544);
    for (var y = 0; y < shape.length; y += 1) {
      for (var x = 0; x < shape[y].length; x += 1) {
        if (shape[y][x] == 0) continue;
        final rect = Rect.fromLTWH(ox + x * cell, oy + y * cell, cell, cell);
        if (images != null) {
          paintImage(
            canvas: canvas,
            rect: rect.inflate(cell * 0.18),
            image: images!.stages.first,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
          );
        } else {
          canvas.drawRect(rect, fill);
          canvas.drawRect(rect, stroke);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant NextPiecePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.images != images;
}

class HudBox extends StatelessWidget {
  const HudBox({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff101837).withValues(alpha: 0.72),
        border: Border.all(color: const Color(0xff6d82c4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xff111936).withValues(alpha: 0.92),
        border: Border.all(color: const Color(0xff6073ad), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.ac_unit, color: Color(0xff8fd7ff), size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xffe6f4ff), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class TouchControls extends StatelessWidget {
  const TouchControls({super.key, required this.game});

  final SnowGameModel game;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        SquareIconButton(
          icon: Icons.keyboard_arrow_left,
          onPressed: () => game.move(-1),
        ),
        SquareIconButton(icon: Icons.rotate_right, onPressed: game.rotate),
        SquareIconButton(
          icon: Icons.keyboard_arrow_right,
          onPressed: () => game.move(1),
        ),
        SquareIconButton(
          icon: Icons.keyboard_arrow_down,
          onPressed: game.softDrop,
        ),
      ],
    );
  }
}

class PauseMenu extends StatelessWidget {
  const PauseMenu({
    super.key,
    required this.onResume,
    required this.onRestart,
    required this.onHome,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xff080b16).withValues(alpha: 0.96),
          border: Border.all(color: const Color(0xffd9f1ff), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x99000000), blurRadius: 22),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUSED',
              style: TextStyle(
                color: Color(0xffe9f8ff),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 18),
            PixelButton(label: 'RESUME', onPressed: onResume),
            const SizedBox(height: 10),
            PixelButton(label: 'RESTART', onPressed: onRestart),
            const SizedBox(height: 10),
            PixelButton(label: 'HOME', onPressed: onHome),
            const SizedBox(height: 14),
            const Text(
              'Settings will be added here.',
              style: TextStyle(color: Color(0xff8fa8c8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class PixelButton extends StatelessWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.large = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xff142347),
        backgroundColor: const Color(0xffcae9ff),
        padding: EdgeInsets.symmetric(
          horizontal: large ? 44 : 18,
          vertical: large ? 18 : 12,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: const BorderSide(color: Color(0xff6576a8), width: 3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: large ? 26 : 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: const Color(0xffdff4ff),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xff111936).withValues(alpha: 0.82),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: const BorderSide(color: Color(0xff6d82c4), width: 2),
        fixedSize: const Size(48, 48),
      ),
    );
  }
}
