import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snowcube/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each bag contains all seven pieces', () {
    final game = SnowGameModel()..start();
    for (var bag = 0; bag < 4; bag++) {
      final types = <String>{};
      for (var i = 0; i < 7; i++) {
        types.add(game.current!.type);
        game.board = List.generate(
          boardRows,
          (_) => List<CubeCell?>.filled(boardCols, null),
        );
        game.hardDrop();
      }
      expect(types, tetrominoes.keys.toSet());
    }
  });

  test('landing preview matches hard drop and freezes a completed row', () {
    final game = SnowGameModel()..start();
    for (var x = 0; x < 6; x++) {
      game.board[19][x] = CubeCell.snow();
    }
    game.current = Piece(
      'I',
      [
        [1, 1, 1, 1],
      ],
      6,
      0,
    );
    expect(game.landingY, 19);
    game.hardDrop();
    expect(game.iceLines, 1);
    expect(game.board[19].every((c) => c?.isIce == true), isTrue);
    game.update(stageSeconds * 5);
    expect(game.board[19].every((c) => c?.isIce == true), isTrue);
  });

  test('pause freezes movement and snow aging; snow eventually melts', () {
    final game = SnowGameModel()..start();
    final snow = CubeCell.snow();
    game.board[19][0] = snow;
    final x = game.current!.x;
    game.togglePause();
    game.move(-1);
    game.hardDrop();
    game.update(30);
    expect(game.current!.x, x);
    expect(game.pieces, 0);
    expect(snow.age, 0);
    game.togglePause();
    game.update(28);
    expect(game.board[19][0], isNull);
  });

  test('ice resumes settling after the active piece clears its path', () {
    final game = SnowGameModel()..start();
    game.board[16] = List.generate(boardCols, (_) => CubeCell.ice());
    game.current = Piece(
      'O',
      [
        [1, 1],
        [1, 1],
      ],
      4,
      17,
    );
    game.hardDrop();
    expect(game.board[16].every((c) => c == null), isTrue);
    expect(game.board[17].every((c) => c?.isIce == true), isTrue);
  });
  testWidgets('title explains the rules', (tester) async {
    await tester.pumpWidget(const SnowCubeApp());
    expect(
      find.image(const AssetImage('assets/ui/btn_game_start.png')),
      findsOneWidget,
    );
    expect(find.text('녹기 전에 한 줄을 채워 얼음으로!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('game fits $size and offers immediate retry', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final game = SnowGameModel()..start();
      Widget panel() => MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GamePanel(
                game: game,
                images: null,
                boardSize: const Size(300, 600),
                cell: 30,
                onPause: () {},
                onRestart: game.start,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(panel());
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('즉시 놓기 · Space'));
      expect(game.pieces, 1);
      game.phase = GamePhase.gameOver;
      await tester.pumpWidget(panel());
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('다시 도전'));
      expect(game.phase, GamePhase.playing);
      expect(game.pieces, 0);
    });
  }

  testWidgets('backgrounding pauses the game and resume returns to play', (
    tester,
  ) async {
    await tester.pumpWidget(const SnowCubeApp());
    await tester.tap(
      find.image(const AssetImage('assets/ui/btn_game_start.png')),
    );
    await tester.pump();
    final game = tester.widget<GamePanel>(find.byType(GamePanel)).game;
    expect(game.phase, GamePhase.playing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(game.phase, GamePhase.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PauseMenu), findsOneWidget);
    await tester.tap(find.text('계속하기'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.phase, GamePhase.playing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('pause menu buttons are independently reachable', (tester) async {
    var action = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PauseMenu(
            onResume: () => action = 'resume',
            onRestart: () => action = 'restart',
            onHome: () => action = 'home',
          ),
        ),
      ),
    );
    for (final entry in {
      '계속하기': 'resume',
      '새 게임': 'restart',
      '처음으로': 'home',
    }.entries) {
      await tester.tap(find.text(entry.key));
      expect(action, entry.value);
    }
  });
}
