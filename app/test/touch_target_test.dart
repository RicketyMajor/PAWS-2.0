// Touch target guard.
//
// Measured on the deployed app at 393px, before the theme carried minimum
// sizes: the primary button painted 39px tall, the two text buttons 32px, and
// the password eye 40x40 -- all under the 44px floor. A tap 5px above a text
// button did not register, while the same tap at its centre navigated, so the
// painted box was the whole target and Material's padded tap area did not
// survive the web build.
//
// The buttons render under the app's own theme rather than being asserted on as
// ThemeData fields, so this also fails if something else starts overriding them.
//
// ponytail: this catches the density regression and nothing else. Under the
// mutation battery, removing the TextButton or IconButton minimum size leaves it
// green in both passes -- a widget test renders those at 48px whatever the
// density, so it cannot reproduce the 32px and 40px the web build actually
// paints. Ceiling: the real check is measuring the deployed app. Upgrade path:
// an integration test on a real web build, the day one exists.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paws_app/main.dart' show pawsTheme;

const double _minTarget = 44;

void main() {
  Future<void> checkAll(
    WidgetTester tester,
    ThemeData theme,
    String pass,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Entrar')),
              ElevatedButton(onPressed: () {}, child: const Text('Guardar')),
              OutlinedButton(onPressed: () {}, child: const Text('Cancelar')),
              TextButton(onPressed: () {}, child: const Text('¿Olvidaste?')),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.visibility),
                tooltip: 'Mostrar contraseña',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final entry in <String, Finder>{
      'FilledButton': find.byType(FilledButton),
      'ElevatedButton': find.byType(ElevatedButton),
      'OutlinedButton': find.byType(OutlinedButton),
      'TextButton': find.byType(TextButton),
      'IconButton': find.byType(IconButton),
    }.entries) {
      final size = tester.getSize(entry.value);
      expect(
        size.height,
        greaterThanOrEqualTo(_minTarget),
        reason:
            '[$pass] ${entry.key} is ${size.height}px tall, under the '
            '${_minTarget}px touch target floor',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(_minTarget),
        reason:
            '[$pass] ${entry.key} is ${size.width}px wide, under the '
            '${_minTarget}px touch target floor',
      );
    }
  }

  testWidgets('every button type meets the minimum touch target', (
    tester,
  ) async {
    await checkAll(tester, pawsTheme, 'tema tal cual');
    await checkAll(
      tester,
      pawsTheme.copyWith(visualDensity: VisualDensity.compact),
      'densidad compacta, como en web',
    );
  });
}
