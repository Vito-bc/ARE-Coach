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
