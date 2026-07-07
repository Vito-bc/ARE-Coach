# Corpus sources — provenance & authenticity

Every source is from an **official / authoritative publisher**, fetched 2026-07-03, and
verified to be a valid PDF (`%PDF` header) that ingests into readable, section-numbered
text. PDFs are git-ignored (kept local for grounding only — not redistributed).

## Collected & verified ✅ — 23 PDFs, 2,769 chunks

| Source | Publisher | Grounds |
|---|---|---|
| `ncarb_are5_handbook.pdf` | **NCARB** (ncarb.org) | ARE 5.0 content-area map + exam logistics |
| `ada_2010_standards_official.pdf` | **US DOJ** (ada.gov, public domain) | 2010 ADA Standards for Accessible Design |
| `nyc_zoning_handbook_2025.pdf` | **NYC DCP** (nyc.gov) | Zoning concepts for Programming & Analysis (FAR, use groups, bulk, yards) |
| `gsa_p100_facilities_standards_2024.pdf` | **US GSA** (gsa.gov, public) | Building systems / structural / mechanical / materials / sustainability — public substitute for MEEB & Ching (PPD/PDD) |
| `leed_v41_bdc_rating_system.pdf` | **USGBC** (usgbc.org, free) | LEED v4.1 BD+C — sustainability credits, energy, water, materials (PPD) |
| `nyc_energy_code_2020_guide.pdf` | **NYC DOB** (nyc.gov) | 2020 NYC Energy Conservation Code — envelope, mechanical, lighting energy compliance (PPD, sustainability) |
| `nps_historic_treatment_guidelines_2017.pdf` | **US NPS** (nps.gov, public) | Secretary of the Interior's Standards — treatment of historic properties: preservation & rehabilitation (PPD/PDD historic) |
| `osha_2202_construction_industry_digest.pdf` | **US OSHA** (osha.gov, public) | Construction Industry Digest — key 29 CFR 1926 jobsite-safety requirements (Construction & Evaluation) |
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

Public sources are now essentially exhausted for the ARE content areas. (Full 29 CFR 1926 exists only
as per-section HTML/dense CFR legalese — the concise OSHA 2202 digest above is the exam-relevant subset,
and NYC BC Ch.33 already grounds jobsite safety. Only marginal public add left: NYC Fire Code / FDNY.)
Evaluated & excluded: the full NYC Zoning Resolution PDF (3,475 pages of legalese) — it would
dominate the corpus and slow every run; the concept-focused Zoning Handbook is the better PA source.

## How to add more NYC chapters
nyc.gov 403s bots, so use a browser-UA `curl`. Exact filenames use a **zero-padded** chapter
number: `.../cons_codes_2022/2022BC_Chapter<NN>_<Name>WBwm.pdf` (e.g. `Chapter03_OccupancyClass`).
Full list at nyc.gov/site/buildings/codes/2022-construction-codes.page (also fetch via curl).

## Rules
- **Only official domains** (ncarb.org, ada.gov, nyc.gov). No third-party summaries/blogs.
- **No paywalled/copyrighted full texts** (full IBC by ICC, AIA contract documents) — cite by
  document + section, do not ingest.

## Still to add (user)
Public sources are now largely exhausted. Remaining gaps are copyrighted and must come from the
user's own books / study notes:
- **AIA Contract Documents** (B101, A201, C401, A101, G-series) -> PcM / PjM / PDD / CE. User HAS, uploading.
- **AHPP** (Architect's Handbook of Professional Practice) -> PcM / PjM. User HAS, uploading.
- **CSI MasterFormat / spec writing** -> PDD. User HAS, uploading.
- **MEEB / Ching (Building Construction Illustrated) / Problem Seeking** -> PPD / PDD / PA. User must
  still find these; GSA P100 + WBDG(public web) partially substitute the systems/materials content.
- **AIA Code of Ethics** -> PcM. Free at aia.org but the site blocks bot download; user can grab it.
