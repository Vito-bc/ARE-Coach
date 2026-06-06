import 'package:are_coach/core/ui/app_tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('fires onTap when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(AppTappable(onTap: () => taps++, child: const Text('hit'))),
    );

    await tester.tap(find.text('hit'));
    expect(taps, 1);
  });

  testWidgets('does not fire when onTap is null', (tester) async {
    // No onTap → inert. Tapping should be a no-op and must not throw.
    await tester.pumpWidget(host(const AppTappable(child: Text('inert'))));
    await tester.tap(find.text('inert'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not fire when disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(AppTappable(
        enabled: false,
        onTap: () => taps++,
        child: const Text('off'),
      )),
    );

    await tester.tap(find.text('off'));
    expect(taps, 0);
  });
}
