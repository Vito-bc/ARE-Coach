import 'package:are_coach/widgets/terms_assent_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders unticked and reports ticks via onChanged', (tester) async {
    var value = false;
    await tester.pumpWidget(
      host(StatefulBuilder(
        builder: (context, setState) => TermsAssentCheckbox(
          value: value,
          onChanged: (v) => setState(() => value = v),
        ),
      )),
    );

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('shows both documents as separately tappable links', (tester) async {
    await tester.pumpWidget(host(TermsAssentCheckbox(value: false, onChanged: (_) {})));

    expect(find.textContaining('I have read and agree to the'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('tapping a link invokes the launcher with the correct URL', (tester) async {
    final launched = <Uri>[];
    Future<bool> fakeLauncher(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async {
      launched.add(url);
      return true;
    }

    await tester.pumpWidget(
      host(TermsAssentCheckbox(value: false, onChanged: (_) {}, launcher: fakeLauncher)),
    );

    await tester.tap(find.text('Terms of Service'));
    await tester.pump();
    expect(launched, [Uri.parse(TermsAssentCheckbox.termsUrl)]);

    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    expect(launched, [
      Uri.parse(TermsAssentCheckbox.termsUrl),
      Uri.parse(TermsAssentCheckbox.privacyUrl),
    ]);
  });

  testWidgets('a link that fails to launch (launcher returns false) shows a message, not silence', (tester) async {
    Future<bool> fakeLauncher(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async => false;

    await tester.pumpWidget(
      host(TermsAssentCheckbox(value: false, onChanged: (_) {}, launcher: fakeLauncher)),
    );

    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the link'), findsOneWidget);
  });

  testWidgets('a link whose launcher throws shows a message, not silence or a crash', (tester) async {
    Future<bool> fakeLauncher(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async {
      throw Exception('no browser available');
    }

    await tester.pumpWidget(
      host(TermsAssentCheckbox(value: false, onChanged: (_) {}, launcher: fakeLauncher)),
    );

    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful launch shows no failure message', (tester) async {
    Future<bool> fakeLauncher(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async => true;

    await tester.pumpWidget(
      host(TermsAssentCheckbox(value: false, onChanged: (_) {}, launcher: fakeLauncher)),
    );

    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the link'), findsNothing);
  });

  testWidgets('tapping a link does not toggle the checkbox', (tester) async {
    var value = false;
    Future<bool> fakeLauncher(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async => true;

    await tester.pumpWidget(
      host(StatefulBuilder(
        builder: (context, setState) => TermsAssentCheckbox(
          value: value,
          onChanged: (v) => setState(() => value = v),
          launcher: fakeLauncher,
        ),
      )),
    );

    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });
}
