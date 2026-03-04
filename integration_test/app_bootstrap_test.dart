import 'package:architectula_education_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots in fallback mode without crashing', (tester) async {
    await tester.pumpWidget(
      const ArchitectulaApp(
        firebaseReady: false,
        initialThemeMode: ThemeMode.light,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Architectula Education'), findsOneWidget);
  });
}
