import 'package:are_coach/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots in fallback mode without crashing', (tester) async {
    // ArchiEdApp now lands directly on the Riverpod-backed home shell, so it
    // needs a ProviderScope ancestor. Avoid pumpAndSettle — the dashboard
    // shows a progress spinner while loading, which never settles.
    await tester.pumpWidget(
      const ProviderScope(child: ArchiEdApp(firebaseReady: false)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ArchiEdApp), findsOneWidget);
  });
}
