import 'package:architectula_education_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots in fallback mode without crashing', (tester) async {
    await tester.pumpWidget(
      const ArchiEdApp(
        firebaseReady: false,
        initialThemeMode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
