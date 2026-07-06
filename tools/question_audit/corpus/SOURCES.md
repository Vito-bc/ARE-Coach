# Corpus sources — provenance & authenticity

Every source is from an **official / authoritative publisher**, fetched 2026-07-03, and
verified to be a valid PDF (`%PDF` header) that ingests into readable, section-numbered
text. PDFs are git-ignored (kept local for grounding only — not redistributed).

## Collected & verified ✅ — 17 PDFs, 1,535 chunks

| Source | Publisher | Grounds |
|---|---|---|
| `ncarb_are5_handbook.pdf` | **NCARB** (ncarb.org) | ARE 5.0 content-area map + exam logistics |
| `ada_2010_standards_official.pdf` | **US DOJ** (ada.gov, public domain) | 2010 ADA Standards for Accessible Design |
| **NYC Building Code chapters** (all **NYC DOB**, nyc.gov) | | |
| `nyc_bc_ch03_occupancy.pdf` | NYC DOB | Use & Occupancy Classification |
| `nyc_bc_ch05_height_area.pdf` | NYC DOB | General Building Heights & Areas |
| `nyc_bc_ch06_construction_type.pdf` | NYC DOB | Types of Construction |
| `nyc_bc_ch07_fire_resistance.pdf` | NYC DOB | Fire & Smoke Protection |
| `nyc_bc_ch08_interior_finishes.pdf` | NYC DOB | Interior Finishes |
| `nyc_bc_ch09_fire_protection.pdf` | NYC DOB | Fire Protection Systems |
| `nyc_bc_ch10_egress.pdf` | NYC DOB | Means of Egress |
| `nyc_bc_ch11_accessibility.pdf` | NYC DOB | Accessibility |
| `nyc_bc_ch12_interior_environment.pdf` | NYC DOB | Light, Ventilation, Sound |
| `nyc_bc_ch14_exterior_walls.pdf` | NYC DOB | Exterior Walls |
| `nyc_bc_ch16_structural_design.pdf` | NYC DOB | Structural Design |
| `nyc_bc_ch17_special_inspections.pdf` | NYC DOB | Special Inspections & Tests |
| `nyc_bc_ch18_soils_foundations.pdf` | NYC DOB | Soils & Foundations |
| `nyc_bc_ch30_elevators.pdf` | NYC DOB | Elevators & Conveying Systems |
| `nyc_bc_ch33_constr_safety.pdf` | NYC DOB | Safeguards During Construction/Demolition |

Easy future adds (public): NYC Energy Conservation Code (sustainability), NYC Fire Code (FDNY),
NYC Zoning Resolution (PA — bigger/different structure), federal OSHA 1926 (CE construction safety).

## How to add more NYC chapters
nyc.gov 403s bots, so use a browser-UA `curl`. Exact filenames use a **zero-padded** chapter
number: `.../cons_codes_2022/2022BC_Chapter<NN>_<Name>WBwm.pdf` (e.g. `Chapter03_OccupancyClass`).
Full list at nyc.gov/site/buildings/codes/2022-construction-codes.page (also fetch via curl).

## Rules
- **Only official domains** (ncarb.org, ada.gov, nyc.gov). No third-party summaries/blogs.
- **No paywalled/copyrighted full texts** (full IBC by ICC, AIA contract documents) — cite by
  document + section, do not ingest.

## Still to add (user)
- Personal study notes — will broaden coverage to PcM / PjM / PA / PDD divisions (the corpus is
  currently strong on NYC codes + accessibility). Coming next.
