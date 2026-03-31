import 'package:flutter_test/flutter_test.dart';

import 'package:dinner_duck/main.dart';

void main() {
  testWidgets('Dinner Duck App loads', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DinnerDuckApp());

    // Verify that the app title is present.
    expect(find.text('Dinner Duck'), findsOneWidget);
  });
}

