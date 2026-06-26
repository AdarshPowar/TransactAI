import 'package:flutter_test/flutter_test.dart';
import 'package:transact_ai_mobile/main.dart';

void main() {
  testWidgets('App loads and displays launch screen title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TransactAIApp());

    // Verify that the title is present on the launch screen
    expect(find.text('TRANSACT AI'), findsOneWidget);
  });
}
