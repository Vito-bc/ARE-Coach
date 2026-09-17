/// The public, citation-safe projection of one retrieved source, mirroring
/// the HTTP `sources` array documented in functions/lib/retrieval.js
/// (sourceProvenance() / PUBLIC_SOURCE_FIELDS). Every field is optional
/// because every PUBLIC_SOURCE_FIELDS field is optional server-side, and
/// legacy index rows (pre page-aware ingestion) carry only {source, ref}.
///
/// Internal governance fields (applicability/usage-permission status,
/// permitted uses, permission notes, policy profiles, policy decisions) are
/// deliberately excluded from the HTTP contract and therefore have no field
/// here -- there is nothing to parse, so there is nothing to leak.
class CoachSource {
  const CoachSource({
    this.source,
    this.ref,
    this.title,
    this.issuingAuthority,
    this.edition,
    this.revision,
    this.jurisdictions,
    this.scope,
    this.page,
    this.locator,
    this.document,
    this.path,
    this.chunkId,
    this.examDivisions,
    this.sha256,
    this.metadataSchema,
    this.extractionVersion,
    this.policySchema,
    this.familyId,
    this.missingMetadata,
    this.notApplicableMetadata,
  });

  final String? source;
  final String? ref;
  final String? title;
  final String? issuingAuthority;
  final String? edition;
  final String? revision;
  final List<String>? jurisdictions;
  final String? scope;
  final int? page;
  final String? locator;
  final String? document;
  final String? path;
  final String? chunkId;
  final List<String>? examDivisions;
  final String? sha256;
  final String? metadataSchema;
  final String? extractionVersion;
  final String? policySchema;
  final String? familyId;
  final List<String>? missingMetadata;
  final List<String>? notApplicableMetadata;

  /// True when nothing citation-worthy survived parsing -- e.g. the backend
  /// sent a non-map element, or every field was an unrecognised shape. Kept
  /// so a caller can render an unusable slot without dropping it: dropping
  /// would shift every later index, and the model's inline "[Source N]"
  /// labels refer to the original backend order, not a re-numbered one.
  bool get isEmpty =>
      source == null &&
      ref == null &&
      title == null &&
      issuingAuthority == null &&
      edition == null &&
      revision == null &&
      jurisdictions == null &&
      scope == null &&
      page == null &&
      locator == null &&
      document == null &&
      path == null &&
      chunkId == null &&
      examDivisions == null &&
      sha256 == null &&
      metadataSchema == null &&
      extractionVersion == null &&
      policySchema == null &&
      familyId == null &&
      missingMetadata == null &&
      notApplicableMetadata == null;

  /// Parses one element of the HTTP `sources` array. Never throws: an
  /// element that isn't a map, or a field of the wrong type, degrades that
  /// field (or the whole entry) to null instead of crashing the chat.
  /// Unknown keys are ignored, which is what keeps this forward-compatible
  /// with future additions to PUBLIC_SOURCE_FIELDS.
  factory CoachSource.fromJson(Object? json) {
    if (json is! Map) return const CoachSource();
    try {
      return CoachSource(
        source: _string(json['source']),
        ref: _string(json['ref']),
        title: _string(json['source_title']),
        issuingAuthority: _string(json['source_issuing_authority']),
        edition: _string(json['source_edition']),
        revision: _string(json['source_revision']),
        jurisdictions: _stringList(json['source_jurisdictions']),
        scope: _string(json['source_scope']),
        page: _int(json['source_page']),
        locator: _string(json['source_locator']),
        document: _string(json['source_document']),
        path: _string(json['source_path']),
        chunkId: _string(json['source_chunk_id']),
        examDivisions: _stringList(json['source_exam_divisions']),
        sha256: _string(json['source_sha256']),
        metadataSchema: _string(json['source_metadata_schema']),
        extractionVersion: _string(json['source_extraction_version']),
        policySchema: _string(json['source_policy_schema']),
        familyId: _string(json['source_family_id']),
        missingMetadata: _stringList(json['source_missing_metadata']),
        notApplicableMetadata: _stringList(json['source_not_applicable_metadata']),
      );
    } catch (_) {
      return const CoachSource();
    }
  }

  /// Parses the whole `sources` array, one output entry per input entry, in
  /// the same order. A malformed entry degrades to an empty [CoachSource]
  /// rather than being dropped, so [Source N] positions can never shift
  /// relative to what the model actually cited inline.
  static List<CoachSource> listFromJson(Object? json) {
    if (json is! List) return const [];
    return json.map(CoachSource.fromJson).toList(growable: false);
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    final items = value
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return items.isEmpty ? null : items;
  }
}
