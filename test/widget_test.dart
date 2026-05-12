import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:architectula_education_app/app.dart';

void main() {
  setUpAll(() async {
    await Hive.initFlutter();
  });

  testWidgets('shows splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ArchiEdApp(firebaseReady: false));
    await tester.pump(const Duration(seconds: 4));
  });
}
