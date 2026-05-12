import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:architectula_education_app/app.dart';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_widget_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('shows splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ArchiEdApp(firebaseReady: false));
    await tester.pump(const Duration(seconds: 4));
  });
}
