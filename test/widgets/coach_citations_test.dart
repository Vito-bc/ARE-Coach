import 'package:are_coach/models/coach_source.dart';
import 'package:are_coach/widgets/coach_citations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320, // mimics the ~80%-of-screen chat bubble width
            child: child,
          ),
        ),
      );

  const modern = CoachSource(
    source: 'nyc_bc_ch10_egress.pdf',
    ref: '1005.3',
    title: 'New York City Building Code',
    issuingAuthority: 'NYC Department of Buildings',
    edition: '2022',
    revision: 'Local Law 126',
    jurisdictions: ['NYC'],
    scope: 'NYC Building Code requirements in the reviewed chapters',
    page: 17,
    locator: 'pdf-page:17:section:1:piece:1',
  );

  const legacy = CoachSource(source: 'ada_2010_standards.pdf', ref: '403.5.1');

  testWidgets('a modern source renders every present field', (tester) async {
    await tester.pumpWidget(
      host(const CoachCitations(sources: [modern], grounded: true)),
    );

    expect(find.textContaining('[Source 1] New York City Building Code'), findsOneWidget);
    expect(find.text('Issuing authority: NYC Department of Buildings'), findsOneWidget);
    expect(find.text('Edition: 2022'), findsOneWidget);
    expect(find.text('Revision: Local Law 126'), findsOneWidget);
    expect(find.text('Jurisdiction(s): NYC'), findsOneWidget);
    expect(
      find.text('Scope: NYC Building Code requirements in the reviewed chapters'),
      findsOneWidget,
    );
    expect(find.text('Page: 17'), findsOneWidget);
    expect(find.text('Locator: pdf-page:17:section:1:piece:1'), findsOneWidget);
    expect(find.text('Ref: 1005.3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a legacy source renders a valid citation with just source and ref', (tester) async {
    await tester.pumpWidget(
      host(const CoachCitations(sources: [legacy], grounded: true)),
    );

    expect(find.text('[Source 1] ada_2010_standards.pdf'), findsOneWidget);
    expect(find.text('Ref: 403.5.1'), findsOneWidget);
    // None of the modern-only field labels are present.
    for (final label in [
      'Issuing authority:',
      'Edition:',
      'Revision:',
      'Jurisdiction(s):',
      'Scope:',
      'Page:',
      'Locator:',
    ]) {
      expect(find.textContaining(label), findsNothing);
    }
    // No placeholder for anything absent.
    for (final placeholder in ['unknown', 'n/a', 'N/A', '—', 'null']) {
      expect(find.textContaining(placeholder), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('citation order matches the sources list order element-by-element', (tester) async {
    await tester.pumpWidget(
      host(const CoachCitations(sources: [modern, legacy], grounded: true)),
    );

    expect(find.textContaining('[Source 1] New York City Building Code'), findsOneWidget);
    expect(find.text('[Source 2] ada_2010_standards.pdf'), findsOneWidget);
    // And not swapped.
    expect(find.textContaining('[Source 2] New York City Building Code'), findsNothing);
    expect(find.text('[Source 1] ada_2010_standards.pdf'), findsNothing);
  });

  testWidgets('a malformed / entirely empty source renders just its label, never a crash', (tester) async {
    await tester.pumpWidget(
      host(const CoachCitations(sources: [CoachSource(), modern], grounded: true)),
    );

    expect(find.text('[Source 1]'), findsOneWidget);
    expect(find.textContaining('[Source 2] New York City Building Code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grounded:false with no sources shows an honest note, not an empty box or a warning', (tester) async {
    await tester.pumpWidget(
      host(const CoachCitations(sources: [], grounded: false)),
    );

    expect(
      find.text('General knowledge — no specific code citation for this answer.'),
      findsOneWidget,
    );
    expect(find.textContaining('Source'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grounded:true with no sources (welcome/demo messages) renders nothing', (tester) async {
    await tester.pumpWidget(
      host(const CoachCitations(sources: [], grounded: true)),
    );

    expect(find.byType(CoachCitations), findsOneWidget);
    expect(find.textContaining('Source'), findsNothing);
    expect(find.textContaining('General knowledge'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long title, multi-jurisdiction list, and missing page do not overflow', (tester) async {
    const wide = CoachSource(
      source: 'very_long_document_name_that_keeps_going_and_going.pdf',
      ref: '9999.99.99',
      title:
          'A Very Long Title For A Building Code Document That Keeps Going On And On '
          'Well Past What Fits On One Line Of A Narrow Chat Bubble',
      issuingAuthority: 'NYC Department of Buildings',
      jurisdictions: ['NYC', 'New York State', 'Five Boroughs Joint Authority'],
      scope: 'A similarly long scope description meant to force text wrapping '
          'across multiple lines inside a narrow container without throwing '
          'a render overflow error',
      // No page -- must simply be omitted, not shown as missing.
    );

    await tester.pumpWidget(host(const CoachCitations(sources: [wide], grounded: true)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Page:'), findsNothing);
  });
}
