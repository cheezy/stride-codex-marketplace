# Example debrief

A worked debrief for the session captured in the
[example session sheet](example-session-sheet.md) — charter #1 against the fictional
*ExpenseFlow* demo target. It uses **both** templates from the `session` skill:
**Explored / Found / Unknown** for the written report, and **PROOF** for the team
review. All content is synthetic.

A debrief reports **externally verifiable facts** — what actually happened and what
was actually observed. Nothing here is fabricated: results that were not observed
live under **Unknown**, never under **Found**.

---

## Explored / Found / Unknown

*(the written report — hand this to stakeholders)*

### What I explored

The CSV receipt import for `<tenant A>` on `demo.example.com`, across a spread of
input shapes: a clean baseline file, a truncated file, a 250 MB file, a UTF-16 file
with accented vendor names, a file with embedded commas/quotes, and — the key probe —
a CSV exported from a *different* tenant (`<tenant B>`). I also confirmed the
post-import receipt list and running total updated correctly on the baseline.

I did **not** cover disguised file types (a `.exe` renamed `.csv`), rapid
double-submits, or files larger than 250 MB — the oversized probe consumed the setup
budget. Those are parked as candidate charters, not tested.

### What I found

*Most important first:*

1. **[Critical] CSV import ignores tenant scope.** Importing `<tenant B>`'s exported
   CSV while logged in as `<tenant A>` accepted every row into `<tenant A>`, with no
   tenant check. This violates tenant isolation — a data-leak class defect.
2. **[High] Non-UTF-8 CSVs corrupt vendor names silently.** A UTF-16 file imported
   "Café" as "CafÃ©". The UI's help text claims UTF-8 support, so this is a
   consistency-with-claims failure, and the corrupt data will export corrupt.
3. **[Minor] Truncated files drop the final partial row silently** — imported
   without warning, which may or may not be intended (see Unknown).

### What remains unknown

- Whether silently dropping a truncated final row is acceptable or a bug — needs
  product intent.
- The intended maximum file size, and whether the generic "Something went wrong"
  error should name the limit or offending row.
- Whether any server-side file-type validation exists at all (the client has none).
- Whether a rapid double-submit of the same import double-counts — untested this box.

---

## PROOF

*(the team-review lens — run through this out loud so nothing, including a gut
feeling, goes uncaptured)*

- **Past** — What happened: a 90-minute time-boxed session against the CSV import,
  probing malformed, oversized, wrong-encoding, and cross-tenant files, with a clean
  baseline as the oracle.
- **Results** — What was achieved: two real bugs (one Critical tenant-isolation leak,
  one High encoding-corruption), three open questions for product, and one new
  candidate charter (disguised file types). Coverage: input-shape and tenant-scope
  dimensions of the import; not size beyond 250 MB, not double-submit.
- **Obstacles** — What got in the way: the 250 MB upload ate most of the setup budget
  and the generic error gave no row-level detail, so I couldn't isolate the
  size-failure boundary within the box.
- **Outlook** — What's left: charter #5 (export tenant isolation) is now higher
  priority given the import leak; add charters for disguised file types and
  double-submit double-counting; get product intent on the truncated-row behavior.
- **Feelings** — How I feel about it: uneasy. The tenant-scope miss on *import*
  strongly suggests the same class of miss may exist on *export* and on the
  report-detail cache — the leak felt systemic, not isolated. That hunch is data;
  it's why charter #5 jumps the queue.

---

## Why both templates

Use **Explored / Found / Unknown** for the artifact you circulate — it maps directly
to coverage, risk, and the honest edge of the map. Use **PROOF** when you walk the
session with the team (or yourself): the **Feelings** prompt in particular surfaces
the intuition — "this leak felt systemic" — that a purely factual report leaves out,
and that unease is often the first sign of the *next* bug.
