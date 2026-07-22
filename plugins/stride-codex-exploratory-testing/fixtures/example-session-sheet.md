# Example session sheet

A worked **SBTM session sheet** for charter #1 from the
[example charter set](example-charters.md), run against the fictional *ExpenseFlow*
demo target. It follows the section skeleton from the `session` skill exactly. All
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
