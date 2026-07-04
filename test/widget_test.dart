import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowcube/main.dart';

void main() {
  testWidgets('Stack Over Snow title screen renders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SnowCubeApp());

    expect(
      find.image(const AssetImage('assets/ui/btn_game_start.png')),
      findsOneWidget,
    );
  });
}
