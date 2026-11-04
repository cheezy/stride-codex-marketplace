# bug-advocacy — worked example and tone

Reference file for the `bug-advocacy` skill (`skills/bug-advocacy/SKILL.md`), kept out of it so the explorer does not carry it every time it loads the skill. The ladder, the modifiers and the rule for combining them stay in the skill; this file applies them and states the tone rule in full.

## Worked example — rating the CSV import session

The three bugs from the plugin's example session sheet and example debrief (`fixtures/`), rated against the ladder. (The Moderate row is an added illustration — no bug in that session rated Moderate.)

| Bug | Worst demonstrated failure | Ladder clause matched | Modifiers | Level |
|---|---|---|---|---|
| CSV import does not scope rows to the current tenant | `<tenant B>`'s exported rows accepted into `<tenant A>` with no tenant check | Critical — *data crossing a boundary that must contain it* | irrelevant; Critical is the ceiling | **Critical** |
| Non-UTF-8 CSVs import vendor names as mojibake | "Café" persisted as "CafÃ©" in the receipt list; it will export corrupt | High — *valid data persisted wrong, affected records still identifiable* | Reach: one UTF-16 file, not generalized — no. Avoidability: user can re-save as UTF-8 and repair the rows — no. Persistence: wrong state persists but is visible in the list — no. **0 of 3** | **High** |
| Truncated files drop the final partial row silently | 39 valid rows imported correctly; the partial 40th dropped with no warning | Minor — *only casualty is input the product could not have interpreted* | Reach: only truncated files — no. Avoidability: supply an intact file — no. Persistence: silent, but nothing wrong is left behind — no. **0 of 3** | **Minor** (provisional) |
| *(illustrative)* Receipt-list Date sort is ignored until the page is reloaded after an import | Clicking **Date** does not re-sort; a reload restores correct sorting | Moderate — *secondary feature broken while the primary path works* | none demonstrated | **Moderate** |

Three calibration notes, because these are the disagreements that actually happen:

- **Why the tenant leak is not High.** It was demonstrated exactly once, with two accounts and a CSV the tester built. None of that is mitigation — rule 3. A boundary that must hold did not hold.
- **Why the mojibake is not Critical.** No boundary was crossed, nothing was destroyed, and the affected records are identifiable and repairable. It is the High clause verbatim. It is also not Moderate: wrong data **persists**, which is exactly what separates High from Moderate.
- **Why the dropped row is Minor and not High.** Two High clauses pull at this one, and the word "silently" pulls hard toward both. The line in each case is *what the product accepted*.
  - Against the **valid-data-lost** clause: that clause covers data the product accepted as well-formed. A row cut mid-record was never that, and every valid row imported correctly. Had the import silently dropped a **complete, well-formed** row, it would be High.
  - Against the **false-report** clause: that clause covers a reported outcome that is false *about work the product accepted as well-formed*. Here the success report is true of everything accepted — all 39 valid rows imported. The product is silent about input it could not interpret, which is a gap in its reporting, not a false statement about the user's accepted work. Two variants would be High, and both turn on the product having accepted the work: reporting "40 rows imported" while importing 39; and reporting an unqualified "Import complete" while silently rejecting 5 **well-formed** rows on a business rule, since the user then believes 40 records are in their books when 35 are. "Accepted" means accepted as well-formed — not committed. A record the product parsed and then dropped was accepted; a row cut mid-record never was.

  The silence is what makes it a bug at all — that is the oracle's job. The demonstrated consequence is what sets the level — that is this rubric's job. Do not import the strength of the oracle violation into the severity.

## Say it clearly and dispassionately

Report the bug in neutral, precise language: what you did, what happened, why it is wrong. Nothing else. No blame, no sarcasm, no speculation about how anyone let this happen.

This is not politeness — it is **credibility, and credibility is the currency that gets your next bug fixed**. Inflated language costs it fastest. A reader who trips over "completely broken" and finds a broken filter learns to read your reports at a discount, and the discount is still applied when you file something that really is catastrophic.

**The severity field is where tone does the most damage**, because an inflated level is inflated language sitting in the one place a reader can check — and one Critical that a reader re-rates as Moderate teaches them to discount every Critical you file afterward, including the next real one. Spend no adjective that the demonstrated failure has not already earned: no all-caps, no exclamation marks, no "catastrophic" or "completely broken", and no level the ladder did not give you.

Deflation costs the same credibility from the other side — a Critical filed as Moderate to sound measured is not restraint, it is a boundary failure that someone will now schedule behind a typo.
