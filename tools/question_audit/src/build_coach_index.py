"""Build the AI Coach's retrieval index from the RAG corpus.

Emits functions/coach_index.json — the chunks the Cloud Function retrieves from
so the Coach can ground its answers in real code text and cite real sections.

The index is deliberately NOT committed (see functions/.gitignore): it contains
extracted text from the source documents, and our corpus rule is "grounding
only, not redistributed". Firebase uploads everything under functions/ on
deploy regardless of .gitignore, so the function still gets it.

Usage (from tools/question_audit/):
    python -m src.build_coach_index
    python -m src.build_coach_index --max-chunks 2500
"""
from __future__ import annotations

import argparse
import json
import re

from src import config
from src.corpus import load_chunks

# The Coach answers exam questions, so a chunk is only useful if it carries
# substantive prose or a numbered requirement. Table-of-contents fragments and
# stray headers are noise that crowds out real sections in retrieval.
MIN_CHARS = 200
MAX_CHARS = 1600

_SECTION_RE = re.compile(r"\b(?:§+\s*)?\d{3,4}(?:\.\d+){1,3}\b")
_TOC_RE = re.compile(r"\.{4,}\s*\d+\s*$", re.MULTILINE)  # "Foo....... 12"


def _useful(text: str) -> bool:
    if not (MIN_CHARS <= len(text) <= MAX_CHARS):
        return False
    if len(_TOC_RE.findall(text)) >= 2:  # a table-of-contents block
        return False
    # Needs some actual sentences, not just a column of numbers.
    letters = sum(ch.isalpha() for ch in text)
    return letters / len(text) > 0.55


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-chunks", type=int, default=0, help="0 = no cap")
    args = ap.parse_args()

    chunks = load_chunks()
    print(f"corpus chunks: {len(chunks)}")

    rows = []
    for c in chunks:
        text = " ".join(c.text.split())  # normalise whitespace; shrinks the file
        if not _useful(text):
            continue
        rows.append(
            {
                "source": c.source,
                "ref": c.ref,
                "text": text,
                # Real section numbers found in the chunk. The Coach may only
                # cite a section that actually appears in a retrieved chunk --
                # this is what makes fabricated citations impossible.
                "sections": sorted(set(_SECTION_RE.findall(text)))[:8],
            }
        )

    # Prefer chunks that actually carry section numbers -- those are what a
    # candidate needs cited back at them.
    rows.sort(key=lambda r: (-len(r["sections"]), -len(r["text"])))
    if args.max_chunks:
        rows = rows[: args.max_chunks]

    out = config.REPO_ROOT / "functions" / "coach_index.json"
    out.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")

    size_mb = out.stat().st_size / 1_000_000
    with_sections = sum(1 for r in rows if r["sections"])
    print(f"kept {len(rows)} chunks ({with_sections} carry section numbers)")
    print(f"wrote {out.relative_to(config.REPO_ROOT)} -- {size_mb:.1f} MB")
    print("NOTE: git-ignored on purpose; `firebase deploy` still uploads it.")


if __name__ == "__main__":
    main()
