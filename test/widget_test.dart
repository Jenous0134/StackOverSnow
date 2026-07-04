import 'package:flutter_test/flutter_test.dart';
import 'package:snowcube/main.dart';

void main() {
  testWidgets('Stack Over Snow title screen renders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SnowCubeApp());

    expect(find.text('GAME START'), findsOneWidget);
    expect(find.text('BEST ICE LINES'), findsOneWidget);
  });
}
