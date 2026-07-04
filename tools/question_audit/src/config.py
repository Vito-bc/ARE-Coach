"""Paths and constants for the audit tool.

Everything is derived from this file's location so the tool works no matter
where the repo lives on disk.
"""
from __future__ import annotations

from pathlib import Path

# .../ARE-Coach/tools/question_audit/src/config.py
SRC_DIR = Path(__file__).resolve().parent
TOOL_DIR = SRC_DIR.parent                  # tools/question_audit
REPO_ROOT = TOOL_DIR.parent.parent         # ARE-Coach

# The bank we audit. READ-ONLY — the tool never writes here.
QUESTIONS_PATH = REPO_ROOT / "assets" / "seeds" / "questions_ny.json"

# Where every report is written.
REPORTS_DIR = TOOL_DIR / "reports"

# Fixed seed so the 50-item sample (and any sampling) is reproducible.
RANDOM_SEED = 42
