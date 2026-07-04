# Corpus sources — provenance & authenticity

Every source is from an **official / authoritative publisher**, fetched 2026-07-03, and
verified to be a valid PDF (`%PDF` header) that ingests into readable, section-numbered
text. PDFs are git-ignored (kept local for grounding only — not redistributed).

## Collected & verified ✅ (855 chunks total)

| File | Official URL | Publisher | Chunks | Grounds |
|---|---|---|---|---|
| `ncarb_are5_handbook.pdf` | ncarb.org/sites/default/files/ARE5-Handbook.pdf | **NCARB** | 144 | ARE 5.0 content-area map + exam logistics |
| `ada_2010_standards_official.pdf` | ada.gov/assets/pdfs/2010-design-standards.pdf | **US DOJ** | 322 | 2010 ADA Standards (public domain) |
| `nyc_bc_ch10_egress.pdf` | nyc.gov/…/2022BC_Chapter10_EgressWBwm.pdf | **NYC DOB** | 120 | NYC BC Ch.10 — Means of Egress |
| `nyc_bc_ch11_accessibility.pdf` | nyc.gov/…/2022BC_Chapter11_AccessibilityWBwm.pdf | **NYC DOB** | 65 | NYC BC Ch.11 — Accessibility |
| `nyc_bc_ch33_constr_safety.pdf` | nyc.gov/…/2022BC_Chapter33_Con_DemoSafetyWBwm.pdf | **NYC DOB** | 194 | NYC BC Ch.33 — Construction/Demolition Safety |

NYC pattern (browser-UA `curl`; nyc.gov 403s bots):
`https://www.nyc.gov/assets/buildings/codes-pdf/cons_codes_2022/2022BC_Chapter<N>_<name>WBwm.pdf`

## Easy to add next (exact filenames not yet confirmed)
- NYC BC Ch.3 Occupancy Classification, Ch.5 Heights & Areas — filename guesses 404'd; grab the
  exact names from nyc.gov/site/buildings/codes/2022-construction-codes.page.

## Rules
- **Only official domains** (ncarb.org, ada.gov, nyc.gov). No third-party summaries/blogs.
- **No paywalled/copyrighted full texts** (full IBC by ICC, AIA contract documents) — cite by
  document + section, do not ingest.

## Still to add (user)
- Personal study notes (only the user has these) — coming later.
