"""Phase 2b — source corpus: ingest documents, chunk, embed, retrieve.

Put source files (.md/.txt/.pdf) in tools/question_audit/corpus/. This module
splits them into chunks, embeds with sentence-transformers, and returns the most
relevant chunks for a topic — the RETRIEVAL half of RAG. No API cost.

Usage (from tools/question_audit/):
    python -m src.corpus --query "minimum accessible route width" --k 3
"""
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

from src import config

CORPUS_DIR = config.TOOL_DIR / "corpus"


@dataclass
class Chunk:
    source: str  # filename
    ref: str     # citation hint (nearest heading, else filename)
    text: str


def _read(path: Path) -> str:
    if path.suffix.lower() == ".pdf":
        from pypdf import PdfReader  # optional; only needed for PDF sources

        return "\n\n".join((pg.extract_text() or "") for pg in PdfReader(str(path)).pages)
    return path.read_text(encoding="utf-8", errors="ignore")


def _split_size(body: str, max_len: int) -> list[str]:
    """Pack paragraphs of an over-long section into <= max_len pieces."""
    paras = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    out, cur = [], ""
    for p in paras:
        if len(cur) + len(p) + 1 <= max_len:
            cur = (cur + "\n" + p).strip()
        else:
            if cur:
                out.append(cur)
            cur = p
    if cur:
        out.append(cur)
    return out or ([body] if body else [])


def load_chunks(min_len: int = 80, max_len: int = 1200) -> list[Chunk]:
    """One chunk per heading-section (ref = the heading), size-split if too long.

    Files without headings (plain .txt / PDF) are chunked purely by size.
    """
    chunks: list[Chunk] = []
    if not CORPUS_DIR.exists():
        return chunks
    for path in sorted(CORPUS_DIR.glob("**/*")):
        if not path.is_file() or path.suffix.lower() not in (".md", ".txt", ".pdf"):
            continue
        if path.name.lower() == "readme.md":
            continue

        heading, buf, sections = path.stem, [], []
        for line in _read(path).splitlines():
            if line.strip().startswith("#"):
                if buf:
                    sections.append((heading, "\n".join(buf).strip()))
                heading, buf = line.strip().lstrip("# ").strip(), []
            else:
                buf.append(line)
        if buf:
            sections.append((heading, "\n".join(buf).strip()))
        if not sections:  # no headings at all
            sections = [(path.stem, _read(path).strip())]

        for h, body in sections:
            for piece in _split_size(body, max_len):
                if len(piece) >= min_len:
                    chunks.append(Chunk(path.name, h, piece))
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

    chunks = load_chunks()
    print(f"Corpus: {len(chunks)} chunks from {CORPUS_DIR}")
    if not chunks:
        print("EMPTY — add .md/.txt/.pdf files to the corpus/ folder.")
        return
    for c, s in Retriever(chunks).search(args.query, args.k):
        print(f"\n[{s:.3f}] {c.source} :: {c.ref}")
        print("   " + c.text[:280].replace("\n", " ") + " ...")


if __name__ == "__main__":
    main()
