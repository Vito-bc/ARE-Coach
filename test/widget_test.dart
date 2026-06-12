import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:are_coach/main.dart';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_widget_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('first launch boots into onboarding before login', (tester) async {
    // Use a phone-sized portrait surface; the default 800x600 test window is
    // too short for the onboarding layout and reports a harmless overflow.
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Fresh Hive → "onboarded" flag is false → the boot flow must show the
    // onboarding screen first (it precedes the login gate by design).
    // runAsync lets the real Hive box open and _load() flip out of the
    // loading state; avoid pumpAndSettle because the loading spinner animates
    // forever and would never settle.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(child: ArchiEdBootstrap(firebaseReady: false)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ARE prep for NYC'), findsOneWidget);
  });
}
