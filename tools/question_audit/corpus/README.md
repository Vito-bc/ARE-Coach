# Source corpus for RAG generation

Drop authoritative source files here (`.md`, `.txt`, `.pdf`). Each is split into
searchable chunks that ground generated questions in real material with real citations.

**The two .md files here are a small PUBLIC-FACT starter sample** (ADA 2010 Standards,
public NYC zoning/code basics) just to test the pipeline. Replace / expand with real materials:

- NCARB ARE 5.0 Handbook (free PDF from ncarb.org)
- NYC Building Code / Zoning Resolution chapters (public)
- ADA 2010 Standards (public, ada.gov)
- Your own study notes / outlines

⚠️ Do NOT ingest full copyrighted texts (AIA contract documents, the full IBC). Cite them
by document + section instead — the generator already knows them.

PDF files need `pip install pypdf` (only when you add PDFs; the .md sample works without it).

## Versioned source metadata and eligibility

Use `source_metadata.json` only for values and decisions explicitly established by
the source owner. The current `are-coach.corpus-source-metadata.v2` contract and a
complete example are documented in the parent
[question-audit README](../README.md#page-aware-provenance-and-fail-closed-source-policy).
It separates document identity, edition/revision, applicability, and permission for
`human_review`, `question_generation`, and `coach_index`.

Never infer edition, revision, jurisdiction, applicability, or permission from a
filename. Missing/unknown policy remains visible in inventory and reports but is
ineligible for generation and indexing. Human review may inspect a source with
pending applicability only when `human_review` is explicitly permitted, and the
policy decision reports that restriction. PDF chunk pages are physical, 1-based PDF
pages; printed page labels remain outside this ingestion stage.

Do not add AIA previews or other found material to the commercial corpus or index
without a separate owner-recorded rights decision. This code enforces recorded
status; it does not make the legal decision.
