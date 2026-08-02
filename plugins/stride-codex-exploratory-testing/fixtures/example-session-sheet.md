# Example session sheet

A worked **human-run SBTM session sheet** for charter #1 from the
[example charter set](example-charters.md), run against the fictional *ExpenseFlow*
demo target. It follows the section skeleton from the `session` skill exactly — the
human-run form, with a wall-clock `DURATION` and Task Breakdown Metric percentages a
tester with a clock can report honestly. An **agent-run** session is bounded by a
probe budget instead and reports counts; that contract is the `session_sheet` object
in `agents/explorer.md`, and the split is *Who the box binds* in the `session` skill. All
data is synthetic; `demo.example.com` and `<tenant A>` / `<tenant B>` are
placeholders standing in for anything real.

---

```
CHARTER
  Explore the CSV receipt import with malformed, oversized, and wrong-encoding
  files (and files from another tenant's export) to discover how the parser fails,
  whether it corrupts existing receipts, and whether any row can leak across tenants.

TESTER / DATE / DURATION
  Sam Rivera / 2026-07-20 / 90 min (time-boxed)

AREAS COVERED
  - CSV import screen (demo.example.com, <tenant A> account)
  - Parser behavior on: valid file, truncated file, 250 MB file, UTF-16 file,
    file with embedded commas/quotes, and a CSV exported from <tenant B>'s account
  - Post-import receipt list and running expense total
  - Import error banner and per-row rejection report

TASK BREAKDOWN METRICS
  Test:  60%   Bug: 25%   Setup: 15%
  On-charter: 85%   Off-charter (opportunity): 15%

NOTES
  - Baseline: a clean 40-row CSV imports cleanly; total updates correctly. Good oracle
    for "did I break something."
  - Truncated file (cut mid-row): parser imports the first 39 rows, silently drops the
    partial 40th, no warning. Idea: is a silently-dropped row a data-integrity risk?
    -> filed as QUESTION, needs product intent.
  - 250 MB file: browser upload spinner ran the full 90s, then a generic "Something
    went wrong" with no row detail. Setup cost real time; capped further size probes.
  - UTF-16-encoded file with accented vendor names ("Café Subroute"): names imported as
    mojibake ("CafÃ©"). Oracle = consistency with claims (the UI claims UTF-8 support in
    the help text). -> BUG.
  - Embedded-comma vendor ("Smith, Jones & Co"): parsed correctly (quoted field
    honored). No issue.
  - CRITICAL probe: imported <tenant B>'s exported CSV while logged in as <tenant A>.
    Rows imported into <tenant A> WITHOUT any tenant check. Cross-tenant data accepted.
    -> BUG (highest severity). Stopped to investigate and write repro.
  - Off-charter (opportunity): noticed the import screen has no file-type restriction —
    a .exe renamed to .csv is accepted for upload. Parked as a candidate charter.

BUGS
  1. [High] UTF-16 / non-UTF-8 CSVs import vendor names as mojibake, silently.
     Repro: import fixtures/utf16-vendors.csv as <tenant A> -> receipt list shows
     "CafÃ©" instead of "Café". Why wrong: UI help text claims UTF-8 support; the
     imported data is now corrupt and will export corrupt.
  2. [Critical] CSV import does not scope rows to the current tenant.
     Repro: while logged in as <tenant A>, import a CSV exported from <tenant B>;
     all rows are accepted and attributed to <tenant A>. Why wrong: violates tenant
     isolation — a Never/Always invariant ("data never crosses tenants").

QUESTIONS / RISKS
  - Is silently dropping a truncated final row acceptable, or should the import fail
    loudly? (product intent unknown)
  - What is the intended max file size, and should the generic error name the row/limit?
  - Is there any server-side file-type validation, or only the (absent) client check?

OFF-CHARTER PARKING LOT
  - No file-type restriction on the import upload (a renamed .exe is accepted).
    -> candidate charter: "Explore the import upload with disallowed and disguised
    file types to discover missing server-side validation."
  - Rapid double-submit of the same import — did it double-count? Not tested here.
    -> candidate charter (relates to charter #5, export double-count).
```

---

## How to read this sheet

- **Task Breakdown Metrics** report the *shape* of the time, not precise accounting:
  most of the box went to actual testing (**Test 60%**), a meaningful chunk to
  investigating and writing up the two bugs (**Bug 25%**), and the rest to setup
  (**Setup 15%** — the oversized-file probe ate most of it). **85% on-charter** with a
  useful **15% off-charter** detour that produced a new candidate charter.
- **BUGS** are oracle-confirmed problems, each with a repro and a *why-wrong* — never
  just "looks off."
- **QUESTIONS / RISKS** hold things that need a human decision (product intent), which
  are not yet bugs.
- **OFF-CHARTER PARKING LOT** captures valuable detours as future charters instead of
  letting them derail this box.

---

## The same session, agent-run

The sheet above is what a **human** tester produces. An `explorer` agent running the
same charter cannot report a `DURATION` or Task Breakdown Metric percentages — it has
no clock — so its sheet swaps those two blocks for the counts it kept as it went.
`AREAS COVERED`, `BUGS`, `QUESTIONS / RISKS`, and the parking lot are identical in
form. `NOTES` is too, with one exception: the two wall-clock asides in the 250 MB note
("ran the full 90s", "Setup cost real time") are things an agent cannot observe either,
so it records that cost in the unit it does have — "this one probe plus its setup cost
9 of the session's 34 tool calls".

```
TESTER / DATE
  explorer subagent / 2026-07-20

SESSION BUDGET
  Probe budget: 12 (band 8-20)        Tool-call ceiling: 60
  Probes attempted: 7 (on-charter 6, off-charter 1)
  Probes that produced a finding: 5
  Tool calls used: 34
  Heuristics applied: Violate Format, Goldilocks, Follow the Data, Interrupt
  Stopped: charter_quiet (5 of the 12 probes unspent — the budget is a ceiling,
    not a quota)
```

Read as JSON, that is the `session_sheet` object in `agents/explorer.md`: `tester`,
`probe_budget`, `probes_attempted`, `probes_with_finding`, `on_charter_probes`,
`off_charter_probes`, `tool_calls_used`, `areas_covered`, `heuristics_applied`, and
`stop_reason`.

The *shape* the percentages carried survives — most of the session served the charter,
one detour produced a new candidate charter — but nothing here is estimated. And
`Stopped: charter_quiet` with probes unspent is the point of the budget: a session that
stops because the charter went quiet is **complete**, while one that stops on
`probe_budget_exhausted` was budget-bound and probably has more to find. A session
blocked before its first probe reports these counters as **zero**, not absent.
