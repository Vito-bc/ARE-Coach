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

## Optional source metadata

Use `source_metadata.json` only for edition/revision values established from the
document or another reviewed source. Its schema and example are documented in the
parent [question-audit README](../README.md#page-aware-source-provenance). Never infer
an edition from the filename. PDF chunk pages are physical, 1-based PDF pages; printed
page labels remain outside this first ingestion stage.
