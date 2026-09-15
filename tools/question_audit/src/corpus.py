"""Phase 2b — source corpus: ingest documents, chunk, embed, retrieve.

Put source files (.md/.txt/.pdf) in tools/question_audit/corpus/. This module
splits them into chunks, embeds with sentence-transformers, and returns the most
relevant chunks for a topic — the RETRIEVAL half of RAG. No API cost.

Usage (from tools/question_audit/):
    python -m src.corpus --query "minimum accessible route width" --k 3
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src import config

CORPUS_DIR = config.TOOL_DIR / "corpus"
SOURCE_METADATA_SCHEMA = "are-coach.corpus-source-metadata.v1"
CHUNK_METADATA_SCHEMA = "are-coach.corpus-chunk.v1"
DIAGNOSTIC_SCHEMA = "are-coach.corpus-ingestion-diagnostic.v1"
DOCUMENT_ID_SCHEMA = "are-coach.source-document.v1"
PDF_PROCESSING_VERSION = "are-coach.pypdf-page-chunker.v1"
TEXT_PROCESSING_VERSION = "are-coach.text-heading-chunker.v1"

SOURCE_METADATA_FIELDS = (
    "source_metadata_schema",
    "source_document",
    "source_sha256",
    "source_path",
    "source_page",
    "source_locator",
    "source_chunk_id",
    "source_extraction_version",
    "source_edition",
    "source_revision",
    "source_missing_metadata",
    "source_not_applicable_metadata",
)


@dataclass(frozen=True)
class Chunk:
    source: str  # filename
    ref: str     # citation hint (nearest heading, else filename)
    text: str
    source_metadata_schema: str | None = None
    source_document: str | None = None
    source_sha256: str | None = None
    source_path: str | None = None
    source_page: int | None = None
    source_locator: str | None = None
    source_chunk_id: str | None = None
    source_extraction_version: str | None = None
    source_edition: str | None = None
    source_revision: str | None = None
    source_missing_metadata: tuple[str, ...] = ()
    source_not_applicable_metadata: tuple[str, ...] = ()

    def candidate_source_metadata(self) -> dict[str, Any]:
        """Return JSON-safe, versioned provenance fields for a candidate/index row."""
        result = {field: getattr(self, field) for field in SOURCE_METADATA_FIELDS}
        result["source_missing_metadata"] = list(self.source_missing_metadata)
        result["source_not_applicable_metadata"] = list(
            self.source_not_applicable_metadata
        )
        return result

    def grounding_label(self) -> str:
        """Human-readable label; PDF page is explicitly physical and 1-based."""
        path = self.source_path or self.source
        location = (
            f"physical PDF page {self.source_page}"
            if self.source_page is not None
            else self.ref
        )
        chunk = f" :: {self.source_chunk_id}" if self.source_chunk_id else ""
        return f"{path} :: {location}{chunk}"


@dataclass(frozen=True)
class IngestionDiagnostic:
    code: str
    message: str
    source_path: str
    source_document: str
    source_sha256: str
    source_page: int | None
    schema: str = DIAGNOSTIC_SCHEMA

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema": self.schema,
            "code": self.code,
            "message": self.message,
            "source_path": self.source_path,
            "source_document": self.source_document,
            "source_sha256": self.source_sha256,
            "source_page": self.source_page,
        }


class CorpusMetadataError(ValueError):
    """A corpus metadata sidecar is malformed or ambiguous."""


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _sha256(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


def _identity(prefix: str, schema: str, payload: dict[str, Any]) -> str:
    digest = hashlib.sha256(_canonical_json({"schema": schema, **payload})).hexdigest()
    return f"{prefix}:{digest}"


def _load_source_metadata(corpus_dir: Path, metadata_path: Path | None) -> dict[str, dict[str, str | None]]:
    path = metadata_path or corpus_dir / "source_metadata.json"
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CorpusMetadataError(f"cannot read source metadata {path}: {exc}") from exc
    if not isinstance(raw, dict) or raw.get("schema") != SOURCE_METADATA_SCHEMA:
        raise CorpusMetadataError(f"unsupported or missing source metadata schema: {path}")
    sources = raw.get("sources")
    if not isinstance(sources, dict):
        raise CorpusMetadataError("source metadata must contain an object named 'sources'")
    result: dict[str, dict[str, str | None]] = {}
    for source_path, values in sources.items():
        if not isinstance(source_path, str) or not source_path or "\\" in source_path:
            raise CorpusMetadataError("source metadata paths must be non-empty POSIX relative paths")
        relative = Path(source_path)
        if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != source_path:
            raise CorpusMetadataError(f"invalid source metadata path: {source_path!r}")
        if not isinstance(values, dict):
            raise CorpusMetadataError(f"source metadata for {source_path!r} must be an object")
        unknown_fields = sorted(set(values) - {"edition", "revision"})
        if unknown_fields:
            raise CorpusMetadataError(
                f"unknown source metadata fields for {source_path!r}: {unknown_fields}"
            )
        entry: dict[str, str | None] = {}
        for field in ("edition", "revision"):
            value = values.get(field)
            if value is not None and (not isinstance(value, str) or not value.strip()):
                raise CorpusMetadataError(f"{field} for {source_path!r} must be a non-empty string or null")
            entry[field] = value.strip() if isinstance(value, str) else None
        result[source_path] = entry
    return result


def _split_long_paragraph(paragraph: str, max_len: int) -> list[str]:
    pieces: list[str] = []
    remaining = paragraph.strip()
    while len(remaining) > max_len:
        cut = remaining.rfind(" ", 0, max_len + 1)
        if cut <= 0:
            cut = max_len
        piece = remaining[:cut].strip()
        if piece:
            pieces.append(piece)
        remaining = remaining[cut:].strip()
    if remaining:
        pieces.append(remaining)
    return pieces


def _split_size(body: str, max_len: int) -> list[str]:
    """Pack paragraphs of an over-long section into <= max_len pieces."""
    paras = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    units = [piece for paragraph in paras for piece in _split_long_paragraph(paragraph, max_len)]
    out, cur = [], ""
    for p in units:
        if len(cur) + len(p) + 1 <= max_len:
            cur = (cur + "\n" + p).strip()
        else:
            if cur:
                out.append(cur)
            cur = p
    if cur:
        out.append(cur)
    return out or _split_long_paragraph(body, max_len)


def _sections(text: str, default_heading: str) -> list[tuple[str, str]]:
    heading, buf, sections = default_heading, [], []
    for line in text.splitlines():
        if line.strip().startswith("#"):
            if buf:
                sections.append((heading, "\n".join(buf).strip()))
            heading, buf = line.strip().lstrip("# ").strip(), []
        else:
            buf.append(line)
    if buf:
        sections.append((heading, "\n".join(buf).strip()))
    if not sections and text.strip():
        sections = [(default_heading, text.strip())]
    return sections


def print_ingestion_diagnostics(diagnostics: list[IngestionDiagnostic]) -> None:
    for item in diagnostics:
        page = (
            f", physical PDF page {item.source_page}"
            if item.source_page is not None
            else ""
        )
        print(
            f"INGESTION {item.code}: {item.source_path}{page}; "
            f"document={item.source_document}; source={item.source_sha256}; {item.message}"
        )


def load_chunks(
    min_len: int = 80,
    max_len: int = 1200,
    *,
    corpus_dir: Path | None = None,
    metadata_path: Path | None = None,
    diagnostics: list[IngestionDiagnostic] | None = None,
) -> list[Chunk]:
    """One chunk per heading-section (ref = the heading), size-split if too long.

    PDF pages are processed independently and keep their physical 1-based page.
    Files without headings are chunked purely by size. Empty/unreadable pages
    produce diagnostics; OCR is deliberately outside this stage.
    """
    if min_len < 0 or max_len <= 0:
        raise ValueError("min_len must be >= 0 and max_len must be > 0")
    corpus_dir = (corpus_dir or CORPUS_DIR).resolve()
    chunks: list[Chunk] = []
    if not corpus_dir.exists():
        return chunks
    declared = _load_source_metadata(corpus_dir, metadata_path)
    source_paths = [
        path
        for path in sorted(corpus_dir.glob("**/*"))
        if path.is_file()
        and path.suffix.lower() in (".md", ".txt", ".pdf")
        and path.name.lower() not in ("readme.md", "sources.md")
    ]
    available = {path.relative_to(corpus_dir).as_posix() for path in source_paths}
    undeclared_files = sorted(set(declared) - available)
    if undeclared_files:
        raise CorpusMetadataError(
            f"source metadata names files that are not ingestible: {undeclared_files}"
        )
    for path in source_paths:
        source_bytes = path.read_bytes()
        source_sha256 = _sha256(source_bytes)
        source_path = path.relative_to(corpus_dir).as_posix()
        source_document = _identity(
            "doc",
            DOCUMENT_ID_SCHEMA,
            {"source_path": source_path, "source_sha256": source_sha256},
        )
        explicit = declared.get(source_path, {})
        edition = explicit.get("edition")
        revision = explicit.get("revision")
        suffix = path.suffix.lower()
        base_version = PDF_PROCESSING_VERSION if suffix == ".pdf" else TEXT_PROCESSING_VERSION
        processing_version = f"{base_version};min_len={min_len};max_len={max_len}"

        units: list[tuple[int | None, str]] = []
        if suffix == ".pdf":
            from pypdf import PdfReader  # optional; only needed for PDF sources

            reader = PdfReader(io.BytesIO(source_bytes))
            if not reader.pages and diagnostics is not None:
                diagnostics.append(
                    IngestionDiagnostic(
                        code="no_extracted_text",
                        message="PDF has no physical pages; OCR was not attempted",
                        source_path=source_path,
                        source_document=source_document,
                        source_sha256=source_sha256,
                        source_page=None,
                    )
                )
            for page_number, page in enumerate(reader.pages, start=1):
                try:
                    text = page.extract_text() or ""
                except Exception as exc:
                    if diagnostics is not None:
                        diagnostics.append(
                            IngestionDiagnostic(
                                code="text_extraction_failed",
                                message=(
                                    f"physical PDF page {page_number} could not be extracted; "
                                    f"OCR was not attempted: {type(exc).__name__}"
                                ),
                                source_path=source_path,
                                source_document=source_document,
                                source_sha256=source_sha256,
                                source_page=page_number,
                            )
                        )
                    continue
                units.append((page_number, text))
        else:
            units.append((None, source_bytes.decode("utf-8", errors="ignore")))

        for page_number, text in units:
            if not text.strip():
                if diagnostics is not None:
                    where = f"physical PDF page {page_number}" if page_number else "text document"
                    diagnostics.append(
                        IngestionDiagnostic(
                            code="no_extracted_text",
                            message=f"{where} produced no extracted text; OCR was not attempted",
                            source_path=source_path,
                            source_document=source_document,
                            source_sha256=source_sha256,
                            source_page=page_number,
                        )
                    )
                continue
            for section_index, (heading, body) in enumerate(
                _sections(text, path.stem), start=1
            ):
                for piece_index, piece in enumerate(_split_size(body, max_len), start=1):
                    if len(piece) < min_len:
                        continue
                    locator_prefix = (
                        f"pdf-page:{page_number}" if page_number is not None else "text-document"
                    )
                    locator = (
                        f"{locator_prefix}:section:{section_index}:piece:{piece_index}"
                    )
                    source_chunk_id = _identity(
                        "chunk",
                        CHUNK_METADATA_SCHEMA,
                        {
                            "source_document": source_document,
                            "source_locator": locator,
                            "source_extraction_version": processing_version,
                        },
                    )
                    missing = [
                        field
                        for field, value in (
                            ("source_edition", edition),
                            ("source_revision", revision),
                        )
                        if value is None
                    ]
                    not_applicable = [] if page_number is not None else ["source_page"]
                    chunks.append(
                        Chunk(
                            source=path.name,
                            ref=heading,
                            text=piece,
                            source_metadata_schema=CHUNK_METADATA_SCHEMA,
                            source_document=source_document,
                            source_sha256=source_sha256,
                            source_path=source_path,
                            source_page=page_number,
                            source_locator=locator,
                            source_chunk_id=source_chunk_id,
                            source_extraction_version=processing_version,
                            source_edition=edition,
                            source_revision=revision,
                            source_missing_metadata=tuple(missing),
                            source_not_applicable_metadata=tuple(not_applicable),
                        )
                    )
    return chunks


class Retriever:
    """Embeds the corpus once; returns the top-k chunks most similar to a query."""

    def __init__(self, chunks: list[Chunk]):
        from sentence_transformers import SentenceTransformer

        self.chunks = chunks
        self.model = SentenceTransformer("all-MiniLM-L6-v2")
        self.emb = (
            self.model.encode([c.text for c in chunks], normalize_embeddings=True)
            if chunks
            else None
        )

    def search(self, query: str, k: int = 3) -> list[tuple[Chunk, float]]:
        if not self.chunks:
            return []
        import numpy as np

        q = self.model.encode([query], normalize_embeddings=True)[0]
        sims = self.emb @ q
        idx = np.argsort(-sims)[:k]
        return [(self.chunks[i], float(sims[i])) for i in idx]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", required=True)
    ap.add_argument("--k", type=int, default=3)
    args = ap.parse_args()

    diagnostics: list[IngestionDiagnostic] = []
    chunks = load_chunks(diagnostics=diagnostics)
    print_ingestion_diagnostics(diagnostics)
    print(f"Corpus: {len(chunks)} chunks from {CORPUS_DIR}")
    if not chunks:
        print("EMPTY — add .md/.txt/.pdf files to the corpus/ folder.")
        return
    for c, s in Retriever(chunks).search(args.query, args.k):
        print(f"\n[{s:.3f}] {c.source} :: {c.ref}")
        print("   " + c.text[:280].replace("\n", " ") + " ...")


if __name__ == "__main__":
    main()
