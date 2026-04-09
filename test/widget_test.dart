import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:architectula_education_app/app.dart';

void main() {
  testWidgets('shows splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ArchiEdApp(
        firebaseReady: false,
        initialThemeMode: ThemeMode.dark,
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
  });
}
