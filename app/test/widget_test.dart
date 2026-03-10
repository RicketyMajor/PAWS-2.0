// This is the default basic Flutter widget test.
//
// NOTE: This test was generated with the default Flutter counter app and
// does not reflect the current functionality of the PAWS application. It will
// likely fail or is irrelevant. It should be replaced with meaningful tests
// for the actual widgets in the app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paws_app/main.dart';

void main() {
  // This test simulates a user tapping a '+' icon to increment a counter.
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const PawsApp());

    // Verify that a counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that the counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
