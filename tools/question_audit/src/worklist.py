"""Build maryana_worklist.csv — ONE self-contained, priority-sorted editing sheet.

Each row = the full question (stem, options with the correct one marked,
explanation, citation) + issue tags + the AI's reasons + any duplicate partner.
The architect opens this single file (Excel-friendly) and works top-down.

Usage (from tools/question_audit/):
    python -m src.worklist                 # severity >= 4 (+ all duplicates/consistency)
    python -m src.worklist --min-severity 6
"""
from __future__ import annotations

import argparse
import csv
import json
from collections import Counter

from src import config
from src.schema import load_questions


# Dropdown choices for the architect's verdict column.
VERDICTS = [
    "OK - оставить",
    "Исправить ответ",
    "Заменить обманки",
    "Переписать",
    "Удалить",
    "Удалить дубликат",
]

# Guide sheet content: (style, text). style in {title, h, body}.
GUIDE = [
    ("title", "Проверка вопросов ARE — инструкция для Марианны"),
    ("body", "Ты практикующий архитектор в Нью-Йорке — твоя экспертиза здесь главное. Задача: пройти список на вкладке «worklist» и по каждому вопросу выбрать решение в колонке «REVIEW: verdict». Писать вопросы с нуля НЕ нужно — только оценить и поправить существующие. AI уже отметил подозрительные; ты подтверждаешь и правишь как профессионал."),
    ("h", "Главный вопрос к каждому пункту"),
    ("body", "«Столкнулся бы реальный архитектор с этим на практике — и правильный ли здесь ответ?» Твой практический опыт важнее всего: чаще всего именно ты ловишь неверный «правильный» ответ."),
    ("h", "Что значат метки (колонка issues)"),
    ("body", "FACTUAL — вопрос на зубрёжку факта, а не на суждение. Хороший ARE-вопрос спрашивает «что архитектор должен СДЕЛАТЬ в ситуации», а не «что такое X»."),
    ("body", "WEAK_DISTRACTORS — неправильные варианты слишком очевидно неверны. Хорошая «обманка» должна быть правдоподобной."),
    ("body", "LEAKAGE — ответ угадывается по формулировке вопроса, даже не глядя на варианты."),
    ("body", "CONSISTENCY — ответ, объяснение и ссылка на норму противоречат друг другу. Проверь по коду/практике."),
    ("body", "DUPLICATE — почти такой же вопрос уже есть (см. колонку duplicate_of)."),
    ("h", "Как проверять — по шагам (~2 минуты на вопрос)"),
    ("body", "1. Прочитай вопрос и правильный ответ (помечен >> в колонке options)."),
    ("body", "2. Ответ действительно верный? Если нет → «Исправить ответ», впиши верный в «REVIEW: fix / notes»."),
    ("body", "3. Три неправильных варианта правдоподобны? Если мусор → «Заменить обманки», предложи лучше в notes."),
    ("body", "4. Это суждение или тупая зубрёжка? Слабая зубрёжка → «Переписать»; совсем плохой → «Удалить»."),
    ("body", "5. Дубликат? → «Удалить дубликат»."),
    ("body", "6. Всё хорошо → «OK - оставить»."),
    ("h", "Колонка REVIEW: verdict — выбери из выпадающего списка"),
    ("body", "OK - оставить — вопрос хороший, не трогаем."),
    ("body", "Исправить ответ — вопрос ок, но «правильный» ответ неверный (верный пиши в notes)."),
    ("body", "Заменить обманки — правильный ответ ок, но неправильные слишком очевидны (лучше пиши в notes)."),
    ("body", "Переписать — тема нужная, но формулировка/зубрёжка плохая."),
    ("body", "Удалить — вопрос плохой или нерелевантный, убрать совсем."),
    ("body", "Удалить дубликат — повтор, убрать."),
    ("h", "ВАЖНО: не проверяй весь список подряд"),
    ("body", "Честная арифметика: в списке ~692 вопроса, по ~2 минуты это примерно 23 ЧАСА, а не пара вечеров. Полностью проходить его не нужно и не надо. Мы разбили список на три очереди — колонка «priority». Фильтруй по ней (стрелка в шапке колонки)."),
    ("body", "КРАСНАЯ (RED) — только ты. Здесь конфликт ответа/объяснения/ссылки на норму, самые тяжёлые вопросы и дубликаты. AI тут не судья: нужен живой архитектор. Это ~80-120 вопросов, ~10-20 часов. НАЧНИ С НЕЁ и, если времени мало, ограничься ею."),
    ("body", "ЖЁЛТАЯ (YELLOW) — слабые обманки и подсказки в формулировке. Это AI умеет чинить сам; он предложит правку, а ты только утвердишь. Отдельно проходить не обязательно."),
    ("body", "ЗЕЛЁНАЯ (GREEN) — вопросы без конфликтов. Достаточно выборочно глянуть 10-15%."),
    ("h", "Про метку FACTUAL — не переписывай всё подряд"),
    ("body", "FACTUAL значит «проверяет знание факта», а НЕ «плохой вопрос». Настоящий ARE тоже спрашивает факты, поэтому выбрасывать вопрос только за то, что он FACTUAL, НЕ нужно. Переписывай, только если факт мелкий/бесполезный или формулировка плохая."),
    ("h", "Как писать правку"),
    ("body", "В колонку «REVIEW: fix / notes» пиши: верный ответ, лучшую обманку или короткий комментарий."),
]

def queue_for(tags: list[str], severity: float) -> str:
    """Triage a flagged question into the queue that decides WHO reviews it.

    RED    - needs a licensed architect's judgment and nothing less: the answer,
             explanation and citation disagree; or the question is among the worst
             scored; or it duplicates another and someone must pick the survivor.
    YELLOW - mechanical weaknesses (throwaway distractors, answer telegraphed by
             the stem). An LLM can propose a fix; the architect only approves it.
    GREEN  - flagged but with no conflict. Spot-check a sample; do not rewrite a
             question merely for being factual -- the real ARE tests facts too.
    """
    if "CONSISTENCY" in tags or "DUPLICATE" in tags or severity >= 7:
        return "RED"
    if "WEAK_DISTRACTORS" in tags or "LEAKAGE" in tags:
        return "YELLOW"
    return "GREEN"


# Column order for the worklist sheet — review columns first (frozen).
_ORDER = [
    "REVIEW: verdict", "REVIEW: fix / notes",
    "priority", "severity", "id", "section", "issues",
    "question", "options (>> = correct)", "correct", "explanation", "codeReference",
    "why_factual", "distractor_notes", "consistency_problem", "leakage_note",
    "difficulty", "duplicate_of",
]
_WIDTHS = {
    "REVIEW: verdict": 20, "REVIEW: fix / notes": 34, "priority": 9, "severity": 8, "id": 11, "section": 20,
    "issues": 20, "question": 55, "options (>> = correct)": 50, "correct": 36, "explanation": 58,
    "codeReference": 26, "why_factual": 36, "distractor_notes": 52, "consistency_problem": 34,
    "leakage_note": 34, "difficulty": 10, "duplicate_of": 16,
}
_WRAP = {
    "REVIEW: fix / notes", "question", "options (>> = correct)", "correct", "explanation",
    "codeReference", "why_factual", "distractor_notes", "consistency_problem", "leakage_note",
}


def _write_xlsx(rows: list[dict], path) -> None:
    """Two-sheet workbook: a Russian guide, then the review sheet with a verdict
    dropdown + notes column, frozen header/review-columns, autofilter, wrap."""
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation

    dark = PatternFill("solid", fgColor="1F2937")
    yellow = PatternFill("solid", fgColor="F2B807")
    wrap_top = Alignment(vertical="top", wrap_text=True)

    wb = Workbook()

    # ── Sheet 1: guide ───────────────────────────────────────────────────────
    g = wb.active
    g.title = "Инструкция"
    g.sheet_properties.tabColor = "F2B807"
    g.column_dimensions["A"].width = 118
    for i, (style, text) in enumerate(GUIDE, 1):
        c = g.cell(row=i, column=1, value=text)
        c.alignment = Alignment(wrap_text=True, vertical="top")
        if style == "title":
            c.font = Font(bold=True, size=14, color="1F2937")
        elif style == "h":
            c.font = Font(bold=True, size=11, color="FFFFFF")
            c.fill = dark
        else:
            c.font = Font(size=10)

    # ── Sheet 2: worklist ────────────────────────────────────────────────────
    ws = wb.create_sheet("worklist")
    ws.append(_ORDER)
    for r in rows:
        ws.append(["" if h.startswith("REVIEW") else r.get(h, "") for h in _ORDER])

    for c in ws[1]:
        c.fill = dark
        c.font = Font(bold=True, color="FFFFFF")
        c.alignment = Alignment(vertical="center", wrap_text=True)
    for i in (1, 2):  # highlight the two review columns in the header
        hc = ws.cell(row=1, column=i)
        hc.fill = yellow
        hc.font = Font(bold=True, color="1F2937")

    last = len(rows) + 1
    ncol = len(_ORDER)
    ws.freeze_panes = "C2"  # keep header row + the two review columns visible
    ws.auto_filter.ref = f"A1:{get_column_letter(ncol)}{last}"
    for i, h in enumerate(_ORDER, 1):
        col = get_column_letter(i)
        ws.column_dimensions[col].width = _WIDTHS.get(h, 16)
        if h in _WRAP:
            for cell in ws[col][1:]:
                cell.alignment = wrap_top

    # Verdict dropdown — values live in a hidden helper column on this sheet.
    helper = ncol + 3
    hcol = get_column_letter(helper)
    for idx, v in enumerate(VERDICTS, start=2):
        ws.cell(row=idx, column=helper, value=v)
    ws.column_dimensions[hcol].hidden = True
    dv = DataValidation(
        type="list", formula1=f"${hcol}$2:${hcol}${1 + len(VERDICTS)}", allow_blank=True
    )
    dv.add(f"A2:A{last}")
    ws.add_data_validation(dv)

    try:
        wb.save(path)
    except PermissionError:
        alt = path.with_name(path.stem + "_new.xlsx")
        wb.save(alt)
        print(f"NOTE: {path.name} is open in Excel (locked) — wrote {alt.name} instead. "
              f"Close Excel and re-run to update the main file.")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-severity", type=float, default=4.0)
    args = ap.parse_args()

    audit = {
        r["id"]: r
        for r in json.loads((config.REPORTS_DIR / "audit_1100.json").read_text(encoding="utf-8"))[
            "results"
        ]
    }
    qs = {q.id: q for q in load_questions(config.QUESTIONS_PATH).valid}

    # Duplicate partners from the 0.90 list.
    dup: dict[str, list[str]] = {}
    dpath = config.REPORTS_DIR / "duplicates_090.csv"
    if dpath.exists():
        with dpath.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                a, b, s = row["id_a"], row["id_b"], row["similarity"]
                dup.setdefault(a, []).append(f"{b} ({s})")
                dup.setdefault(b, []).append(f"{a} ({s})")

    rows = []
    for qid, r in audit.items():
        q = qs.get(qid)
        if not q:
            continue
        d = r["distractors"]["distractors"]
        davg = sum(x["plausibility"] for x in d) / len(d) if d else 0

        tags = []
        if r["judgment"]["label"] == "factual":
            tags.append("FACTUAL")
        if davg < 2.5:
            tags.append("WEAK_DISTRACTORS")
        if r["leakage"]["leakage_prone"]:
            tags.append("LEAKAGE")
        if r["consistency"]["verdict"] == "fail":
            tags.append("CONSISTENCY")
        if qid in dup:
            tags.append("DUPLICATE")

        # Keep if it clears the bar OR has a hard flag we always want reviewed.
        hard = "DUPLICATE" in tags or "CONSISTENCY" in tags
        if r["severity"] < args.min_severity and not hard:
            continue

        opts = "\n".join(f"{'>>' if o == q.correctOption else '  '} {o}" for o in q.options)
        dnotes = " | ".join(
            f"{x['plausibility']}/5 [{x['option'][:22]}]: {x['reason'][:55]}" for x in d
        )
        lk = r["leakage"]
        lnote = (
            f"answerable from stem alone: '{lk['model_answer'][:45]}' (conf {lk['confidence']}/5)"
            if lk["leakage_prone"]
            else ""
        )
        rows.append(
            {
                "priority": queue_for(tags, r["severity"]),
                "severity": r["severity"],
                "id": qid,
                "section": q.section,
                "difficulty": q.difficulty,
                "issues": ",".join(tags),
                "duplicate_of": "; ".join(dup.get(qid, [])),
                "question": q.question,
                "options (>> = correct)": opts,
                "correct": q.correctOption,
                "explanation": q.explanation,
                "codeReference": q.codeReference,
                "why_factual": r["judgment"]["reason"] if "FACTUAL" in tags else "",
                "distractor_notes": dnotes,
                "consistency_problem": r["consistency"]["reason"] if "CONSISTENCY" in tags else "",
                "leakage_note": lnote,
            }
        )

    # RED first, then worst-scored within each queue.
    _RANK = {"RED": 0, "YELLOW": 1, "GREEN": 2}
    rows.sort(key=lambda x: (_RANK[x["priority"]], -x["severity"]))

    counts = Counter(x["priority"] for x in rows)
    red, yellow, green = counts["RED"], counts["YELLOW"], counts["GREEN"]
    print(
        f"Queues: RED {red} (architect only, ~{round(red * 2 / 60)}-{round(red * 8 / 60)} h) | "
        f"YELLOW {yellow} (AI proposes, architect approves) | "
        f"GREEN {green} (spot-check ~10-15%)"
    )
    print(f"All {len(rows)} rows at ~2 min each would be ~{round(len(rows) * 2 / 60)} h -- don't do that.")

    out = config.REPORTS_DIR / "maryana_worklist.csv"
    with out.open("w", newline="", encoding="utf-8-sig") as f:  # utf-8-sig = clean in Excel
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    xlsx = config.REPORTS_DIR / "maryana_worklist.xlsx"
    _write_xlsx(rows, xlsx)

    tally: Counter = Counter()
    for r in rows:
        for t in r["issues"].split(","):
            if t:
                tally[t] += 1
    print(f"Wrote {out.name}: {len(rows)} questions to review (severity>={args.min_severity} + all duplicates/consistency).")
    print("Issue tag tally:", dict(tally))


if __name__ == "__main__":
    main()
