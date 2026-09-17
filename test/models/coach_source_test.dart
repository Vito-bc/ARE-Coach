import 'package:are_coach/models/coach_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoachSource.fromJson', () {
    test('a fully-populated modern source parses every field', () {
      final source = CoachSource.fromJson({
        'source': 'nyc_bc_ch10_egress.pdf',
        'ref': '1005.3',
        'source_title': 'New York City Building Code',
        'source_issuing_authority': 'NYC Department of Buildings',
        'source_edition': '2022',
        'source_revision': 'Local Law 126',
        'source_jurisdictions': ['NYC'],
        'source_scope': 'NYC Building Code requirements in the reviewed chapters',
        'source_page': 17,
        'source_locator': 'pdf-page:17:section:1:piece:1',
        'source_document': 'doc:synthetic-egress',
        'source_path': 'codes/nyc_bc_ch10_egress.pdf',
        'source_chunk_id': 'chunk:synthetic-egress-page-17',
        'source_exam_divisions': ['NYC Building Codes'],
        'source_sha256': 'sha256:synthetic-egress',
        'source_metadata_schema': 'are-coach.corpus-chunk.v1',
        'source_extraction_version': 'are-coach.pypdf-page-chunker.v1',
        'source_policy_schema': 'are-coach.source-policy.v1',
        'source_family_id': 'nyc.building-code',
        'source_missing_metadata': <String>[],
        'source_not_applicable_metadata': <String>[],
      });

      expect(source.source, 'nyc_bc_ch10_egress.pdf');
      expect(source.ref, '1005.3');
      expect(source.title, 'New York City Building Code');
      expect(source.issuingAuthority, 'NYC Department of Buildings');
      expect(source.edition, '2022');
      expect(source.revision, 'Local Law 126');
      expect(source.jurisdictions, ['NYC']);
      expect(source.scope, 'NYC Building Code requirements in the reviewed chapters');
      expect(source.page, 17);
      expect(source.locator, 'pdf-page:17:section:1:piece:1');
      expect(source.document, 'doc:synthetic-egress');
      expect(source.path, 'codes/nyc_bc_ch10_egress.pdf');
      expect(source.chunkId, 'chunk:synthetic-egress-page-17');
      expect(source.examDivisions, ['NYC Building Codes']);
      expect(source.sha256, 'sha256:synthetic-egress');
      expect(source.metadataSchema, 'are-coach.corpus-chunk.v1');
      expect(source.extractionVersion, 'are-coach.pypdf-page-chunker.v1');
      expect(source.policySchema, 'are-coach.source-policy.v1');
      expect(source.familyId, 'nyc.building-code');
      // Empty arrays carry no citation-worthy content -- treated as absent,
      // same as a missing key.
      expect(source.missingMetadata, isNull);
      expect(source.notApplicableMetadata, isNull);
      expect(source.isEmpty, isFalse);
    });

    test('a legacy {source, ref} entry parses without inventing any other field', () {
      final source = CoachSource.fromJson({
        'source': 'ada_2010_standards.pdf',
        'ref': '403.5.1',
      });

      expect(source.source, 'ada_2010_standards.pdf');
      expect(source.ref, '403.5.1');
      expect(source.title, isNull);
      expect(source.issuingAuthority, isNull);
      expect(source.edition, isNull);
      expect(source.revision, isNull);
      expect(source.jurisdictions, isNull);
      expect(source.scope, isNull);
      expect(source.page, isNull);
      expect(source.locator, isNull);
      expect(source.document, isNull);
      expect(source.path, isNull);
      expect(source.isEmpty, isFalse);
    });

    test('an unknown extra key is ignored rather than crashing parsing', () {
      final source = CoachSource.fromJson({
        'source': 'ada_2010_standards.pdf',
        'ref': '403.5.1',
        'a_field_added_by_a_future_backend_release': {'nested': 'value'},
      });

      expect(source.source, 'ada_2010_standards.pdf');
      expect(source.ref, '403.5.1');
    });

    test('a non-map element degrades to an empty source instead of throwing', () {
      expect(() => CoachSource.fromJson('just a string'), returnsNormally);
      expect(() => CoachSource.fromJson(42), returnsNormally);
      expect(() => CoachSource.fromJson(null), returnsNormally);
      expect(() => CoachSource.fromJson(<dynamic>['a', 'list']), returnsNormally);

      expect(CoachSource.fromJson('just a string').isEmpty, isTrue);
      expect(CoachSource.fromJson(null).isEmpty, isTrue);
    });

    test('wrong-typed fields are ignored, not coerced or thrown on', () {
      final source = CoachSource.fromJson({
        'source': 12345, // should be a String
        'ref': null,
        'source_title': ['not', 'a', 'string'],
        'source_page': 'seventeen', // should be a number
        'source_jurisdictions': 'NYC', // should be a List
        'source_missing_metadata': [1, 2, 3], // should be List<String>
      });

      expect(source.source, isNull);
      expect(source.ref, isNull);
      expect(source.title, isNull);
      expect(source.page, isNull);
      expect(source.jurisdictions, isNull);
      expect(source.missingMetadata, isNull);
      expect(source.isEmpty, isTrue);
    });

    test('an integral double for source_page is accepted as a page number', () {
      final source = CoachSource.fromJson({'source_page': 17.0});
      expect(source.page, 17);
    });

    test('blank/whitespace-only strings are treated as absent', () {
      final source = CoachSource.fromJson({
        'source': '   ',
        'ref': '',
        'source_title': 'Real Title',
      });
      expect(source.source, isNull);
      expect(source.ref, isNull);
      expect(source.title, 'Real Title');
    });
  });

  group('CoachSource.listFromJson', () {
    test('preserves order element-by-element, including malformed entries', () {
      final list = CoachSource.listFromJson([
        {'source': 'first.pdf', 'ref': 'A'},
        'garbage',
        {'source': 'third.pdf', 'ref': 'C'},
      ]);

      expect(list, hasLength(3));
      expect(list[0].source, 'first.pdf');
      expect(list[1].isEmpty, isTrue); // malformed, degraded, position kept
      expect(list[2].source, 'third.pdf');
    });

    test('a non-list payload never throws and yields an empty list', () {
      expect(CoachSource.listFromJson(null), isEmpty);
      expect(CoachSource.listFromJson('not a list'), isEmpty);
      expect(CoachSource.listFromJson({'not': 'a list'}), isEmpty);
    });

    test('an empty list round-trips to an empty list', () {
      expect(CoachSource.listFromJson(<dynamic>[]), isEmpty);
    });
  });
}
