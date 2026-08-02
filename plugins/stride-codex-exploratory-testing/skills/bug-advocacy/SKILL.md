---
name: bug-advocacy
description: Use when a result has been judged a defect and needs to become a report someone will act on — isolating a minimal repro, pushing a bug toward its worst real consequence, generalizing it beyond the one case you found, naming who it harms, rating its severity, and writing it up. This skill supplies Cem Kaner's RIMGEA follow-through (Replicate, Isolate, Maximize, Generalize, Externalize, And say it clearly), a severity rubric with explicit per-level criteria, and the dispassionate-tone rule. Invoked by the exploratory-testing orchestrator, the explorer subagent, and the stride-exploratory-testing-explore command-skill at the moment the oracles skill classifies a result as a defect.
skills_version: "1.0"
---

# bug-advocacy

## STOP — orchestrator check

This is an internal doctrine skill, dispatched by the orchestrator. If you arrived here directly from a user prompt, activate the `stride-exploratory-testing` orchestrator skill first — it teaches the mental model and routes the request here with the right framing. Do not proceed from a cold user prompt; the orchestrator is the front door, this skill is not.

Finding a bug is half the work. **The tester who matters is the one whose bugs get fixed** — and between "an oracle says this is wrong" and "a developer can act on this" sits real work that neither the finding nor the writing covers. That work is this skill.

An unfixed bug report is wasted testing. Reports die for predictable reasons: nobody could reproduce it, so it was closed; it looked cosmetic, so it was deferred — and the cosmetic symptom was really data loss; it named no one who was harmed, so triage had nothing to weigh; it was written with enough heat that the reader discounted it. Every one of those is preventable by the six steps below, applied *before* the report is written.

## The judgment this skill supports

The `oracles` skill answers **"is this a bug?"** This skill answers the three questions that follow:

- **What exactly is the bug?** — the smallest set of conditions that triggers it, and the worst thing it actually does.
- **How bad is it?** — a severity level a second reader can re-derive from your evidence.
- **How do I say it?** — clearly, dispassionately, in terms of who is harmed.

## RIMGEA — the six steps

Run these in order on every defect, *before* you write it into a report. Each step is cheap; skipping one is what makes a report ignorable.

| | Step | What it is | The prompt to ask |
|---|---|---|---|
| **R** | **Replicate** | Confirm it happens again. A bug you saw once and cannot re-trigger is a report the reader will close. | *"Can I make it happen a second time, from a clean start, following my own written steps?"* |
| **I** | **Isolate** | Strip the trigger to its minimum. Remove one condition at a time and see whether it still fails. | *"What can I take away — this data, this setting, this prior step, this account — and still see the failure?"* |
| **M** | **Maximize** | Push it toward the worst consequence it can actually produce. A cosmetic bug that maximizes into data loss gets fixed; the same bug filed as cosmetic does not. | *"What is the worst thing this could do — and can I safely demonstrate that, rather than assert it?"* |
| **G** | **Generalize** | Show whether it fails beyond the one case you found — other inputs, records, accounts, browsers, surfaces. | *"Is this about this one record, or about every record of this kind?"* |
| **E** | **Externalize** | Say who is harmed and how, in their terms, not the code's. This is what triage weighs. | *"Who pays for this — which user, in what situation — and what does it cost them?"* |
| **A** | **And say it clearly** | Write it plainly and without heat. Steps, result, why it is wrong. | *"Could a reader who was not here reproduce this and agree it is wrong, without asking me anything?"* |

### Replicate

Reproduce the failure from a clean start, following the steps *as you wrote them* — not as you remember them. Writing the steps and then executing them is the point: it is how you discover the setup detail you left out.

If it does not reproduce, **say so and file it anyway**. An intermittent bug is real information; a suppressed one is not. Record what you did observe, how many attempts failed to re-trigger it, and what you suspect varies. "Observed once in 5 attempts; suspect it depends on the import running while the nightly job holds the row" is a useful report. Silence is not.

### Isolate

Cut the repro down. Drop a setup step, simplify the data, remove the second account, skip the intermediate page — after each cut, re-run. What survives is the `minimal_repro`, and it is the single highest-value field in the report: every condition you leave in is one the developer must rule out themselves.

Isolation also *sharpens the bug*. A repro that needed a 40-row CSV and turns out to need only one malformed row is a different, better-understood bug.

### Maximize

Ask what the same underlying failure could do at its worst, then try to demonstrate that — **within the safety boundary** (see below). A misaligned total that turns out to be a wrong total is not a layout bug. A dropped row that turns out to be a dropped *valid* row is not an edge case.

Maximization is why severity is rated **last**, on the worst failure you demonstrated, never on the first symptom you noticed. What you believe could be worse but did not show does not raise the rating — see *Rate on the worst demonstrated failure*.

### Generalize

Vary the one thing you happened to use. Another input shape, another record, another account, another role, another browser, another entry point to the same code. A bug that fails for every account is a different bug from one that fails for yours, and the report should say which you established.

If the budget ran out before you could generalize, **write that** — `"not established: probe budget exhausted after isolation"` is honest and useful. A guess is neither.

### Externalize

Translate the failure out of the product's vocabulary and into a person's. Not "the tenant scope is missing from the import query" but "a customer importing their own export can pull another customer's receipts into their books, and neither of them can tell."

Name the harmed party, the situation in which they meet it, and what it costs them. This is the field triage actually reads. If the impact is genuinely unknown, see *When the impact is genuinely unknown* — say it is unknown, do not invent it.

### And say it clearly

Steps, result, why it is wrong. No blame, no theory about how the code got that way, no adjective the evidence has not earned. Tone is covered in full below — it is not politeness, it is credibility, and credibility is what gets the *next* bug fixed.

## Severity is a property of the failure, not a decision about the fix

**Severity** is how bad the failure is. It is a fact about what the product did, rated from evidence you produced, and it does not change when the schedule does. **Priority** is when someone will fix it — a scheduling decision that weighs severity against cost, release timing, how often real users will hit it, and who is asking. Different people, different question, different artifact.

You rate severity. You do **not** set priority, and you do not imply it: no "P1", no "fix before release", no "blocker". A Minor bug can be top priority (a typo on the pricing page the morning of a launch). A Critical bug can be deferred (it needs a migration and the only affected customer has not gone live). Neither fact touches the severity. Everything you know that bears on the *scheduling* call — how contrived your repro was, how often you would expect this in the field, who is harmed — goes in `stakeholder_impact`, where the person making that call will find it.

Severity is also not a measure of how confident your oracle is. The `oracles` skill tells you *whether* it is a bug; this rubric tells you how bad the **consequence you demonstrated** was. A rock-solid Never/Always violation with a trivial consequence is still Minor.

Rank order is **Critical > High > Moderate > Minor**; the `stride-exploratory-testing-explore` command-skill sorts the aggregated bug list by it. Write the level word in full — never `Crit.`, `Mod.`, an `S1`–`S4`, or a P-number.

### The four levels

| Level | It means | The one-line test |
|---|---|---|
| **Critical** | The failure crosses a boundary that must hold, destroys what the user committed, or takes the product's purpose away. | Someone is harmed and the product gave them no way to prevent or undo it. |
| **High** | The failure damages the work product — wrong, lost, or falsely-reported data, or a main path that does not work — but the damage is bounded and identifiable. | The user's work is wrong, and they will need help or rework to make it right. |
| **Moderate** | The failure degrades a real workflow — visible, wrong, or expensive in effort — but nothing incorrect survives it. | The user is slowed, confused, or made to retry; the data they end up with is right. |
| **Minor** | The failure costs the user's work product nothing. What is wrong is presentation, wording, or an edge case whose only casualty was already-invalid input. | The task completed and the data is correct; something looks or reads wrong. |

### The impact ladder — look up the class, do not judge the adjective

Find the **worst failure you actually demonstrated** in this table. The class you match sets the level. This is a lookup, not an impression; a second reader performing the same lookup on the same evidence must land in the same row.

| Level | Rate here when the worst demonstrated failure is… |
|---|---|
| **Critical** | data crossing a boundary that must contain it — another tenant, account, role, or permission scope. |
| **Critical** | committed data destroyed, or corrupted such that the affected records cannot be identified. |
| **Critical** | money or a legal/contractual obligation wrong — a double charge, a wrong recipient, a broken retention or audit requirement. |
| **Critical** | a secret, credential, or token exposed — in a response, a log, a URL, or an exported artifact. |
| **Critical** | the product's primary purpose unavailable, with nothing the user can do about it. |
| **High** | **valid** data — data the product accepted as well-formed — persisted wrong, lost, or silently altered, with the affected records still identifiable. |
| **High** | a main workflow blocked or failing outright. |
| **High** | a failed operation reporting success (or a successful one reporting failure) **about work the product accepted as well-formed** — whether or not it ultimately committed that work — so the user acts on a false result. |
| **High** | a control that must exist demonstrably absent, where no boundary was actually crossed this session — e.g. no server-side validation, or no authorization check on a path you could not exploit. |
| **Moderate** | behavior wrong or misleading while the user works, where no wrong state survives a retry or a reload. |
| **Moderate** | a secondary feature broken — a filter, a sort, an export option, a notification — while the primary path works. |
| **Moderate** | an error the user cannot act on: they cannot tell what to change, and pay a retry cycle for it. |
| **Moderate** | a claimed or documented behavior unmet, with no data consequence. |
| **Minor** | presentation only: layout, spacing, wording, inconsistent terminology, a truncated label. |
| **Minor** | an edge case failing whose only casualty is input the product could not have interpreted — truncated, malformed, or otherwise invalid — while every valid record is handled correctly. |
| **Minor** | an internal-consistency or polish oracle violated with no demonstrated cost to the user's work product. |

If a bug matches clauses at two levels, take the **higher** one — but only if you demonstrated it. Matching a Critical clause "in principle" is not matching it.

### The three modifiers

The ladder is about the **kind** of harm. The modifiers are about its **breadth, its avoidability, and what it leaves behind**. They only ever aggravate; a mitigation is a priority input, not a severity discount.

| Modifier | It aggravates only when you demonstrated that… | It does not aggravate when… |
|---|---|---|
| **Reach** | the same failure happens beyond the first case you produced — another input, record, account, surface, or platform (the Generalize step) — or it happens on the ordinary path for any user. | the failure is confined to the one case you produced, or you never tried a second. |
| **Avoidability** | the user can **neither** prevent it by changing what they do **nor** undo its effect using the product. | either one is available — some in-product action prevents it or repairs it. |
| **Persistence** | the failure is silent **and** leaves wrong state behind — no signal to the user, and the wrong state outlives the action. | the user can see it happen, or nothing wrong is left behind. |

**The combination rule.**

1. **The ladder sets the level.** Start at the level of the worst failure class you demonstrated.
2. **Two or more aggravating modifiers raise it exactly one level.** One never moves a rating. Two do not move it two levels.
3. **Modifiers never lower a rating.** How contrived your setup was, or how easy the workaround is, is a fact about your test and about scheduling — not about the failure.
4. **Modifiers never produce a Critical.** Critical is set only by a ladder clause. If the modifiers genuinely justify Critical, a Critical ladder clause already matches — use it and name it.
5. Ceiling **Critical**, floor **Minor**.

**The tie-break, stated plainly.** When one dimension says Critical and another says Minor, take **the highest ladder clause you actually demonstrated — never the highest you can imagine, and never an average**. A cross-tenant leak you produced once, with two hand-built accounts and a CSV you crafted yourself, is Critical. The rig you needed to show it is a fact about your test; the boundary that failed to hold is the fact about the product. How likely a real user is to assemble those conditions is the *priority* question — write it in `stakeholder_impact` and let the person making that call weigh it.

**Why likelihood is not a severity input.** How often this would happen in production is not observable from a session — it is a guess, and guesses are exactly where two raters diverge. *Reach* (how broadly you **demonstrated** the failure) is observable; likelihood is not. Likelihood is a priority input, and it belongs in `stakeholder_impact`.

### The agreement test

Before you emit a level, run this check:

> Could a second reader, given only `minimal_repro`, `worst_observed`, `generalization`, and `stakeholder_impact` — and no conversation with you — reach this level from the ladder?

If not, one of two things is true, and it is usually the second: the level is wrong, or those four fields are underwritten. **Fix the fields first.** A severity a reader cannot re-derive from the evidence is an opinion wearing a label.

### Rate on the worst demonstrated failure (Maximize)

Severity is rated **last**, after RIMGEA's **Maximize** step, on the worst consequence you demonstrated — never on the first symptom you noticed. That ordering is the whole point of Maximize: a cosmetic misalignment that maximizes into a lost record is not a cosmetic bug that happens to be worse than it looks, it *is* the data-loss bug, and it is rated as one. Do not rate a bug you have not yet tried to push.

**"I think this could be worse but I did not show it."** That belief does not touch the number. A level is a claim about evidence, and inflating one on a hypothesis is the fastest way to make every level you file worth less. But the belief is not thrown away either — it is often the most valuable thing in the session. It goes in three places, none of them the rating:

- **The session's questions and risks** — as the risk, stated as a hypothesis with the probe that would settle it.
- **The off-charter parking lot** — as a candidate charter, so the next session can demonstrate it or rule it out.
- **The debrief's Unknown section, and PROOF's Feelings** — a result you did not observe belongs under Unknown, never under Found. If the hunch is that a whole class of failure is systemic, say so; that unease is data, and it is what promotes a follow-up charter up the queue.

Write it in that form: *"Rated High on the corruption demonstrated on import. Unverified escalation: if the same missing check applies to export, this becomes cross-tenant exposure — not demonstrated; charter filed."* The hypothesis changes **what you test next**, not the level you file today.

Keep the four RIMGEA fields clean of it. `worst_observed` and `generalization` hold what you **showed**; an unverified escalation in either of them contaminates the field a triager relies on.

### When the impact is genuinely unknown

Sometimes the oracle is satisfied that the behavior is wrong, but nobody can say what it costs — the product intent has never been decided, or the downstream consequence is outside what you could observe. Two doors, and taking the right one is what keeps this honest:

- **You cannot tell whether it is wrong at all.** Then it is not a bug with a severity. File it as a question and under Unknown. Do not manufacture a level for something you have not established is a defect.
- **It is wrong, but the magnitude is unknown.** Rate it at the level the **demonstrated facts alone** support, and mark the rating **provisional**, naming the question that would settle it.

Two guardrails keep a provisional rating from sliding to either extreme:

- **Never Critical, never High on an unknown.** Both require a demonstrated harm class from the ladder. If you can point at the clause, the impact is not unknown — what is unknown is *how much worse*, and that is an escalation hypothesis (above), not an unknown impact.
- **Never quietly Minor either.** Minor is not a shrug; it is a set of clauses. Rate Minor only because the demonstrated facts *match a Minor clause* — say, "the only casualty was input the product could not have interpreted." If nothing matches, you are in the first door: it is a question, not a bug.

Record it like this — the level stays a bare word in `severity`, and the provisional marker plus the deciding question go in `stakeholder_impact`:

> `severity: "Minor"`
> `stakeholder_impact: "Provisional — pending product intent: should a truncated final row fail the import loudly? If yes, this is silent loss of a row the user believed was imported, and it re-rates against the ladder. Demonstrated harm: one partial row from a malformed file dropped without warning; every valid row imported correctly."`

A provisional rating is a promise that the question is filed, not a placeholder. File it in the session's questions and under Unknown in the debrief as well.

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

## Safety of bug advocacy

**Maximize is bounded by the explorer's absolute safety boundary, and never overrides it.** Pushing a bug toward a worse failure means *further safe probing* — more inputs, more surfaces, more observation. It never means a destructive action, and "to prove severity" is not a justification. Never intentionally corrupt, delete, or degrade shared state, drop or truncate data, or mutate schema or config to demonstrate impact. A worse failure you could not safely demonstrate is a **risk to name**, not a result to claim — file it as a hypothesis with the probe that would settle it, and leave the severity where the evidence puts it.

**Security bugs are maximized by reasoning, not by exploitation.** Do not escalate a security finding beyond the authorized, non-production target you were given — no pivoting to another system, no widening an exploit to show how far it reaches, no accessing real user data to prove exposure is possible. Demonstrate the boundary failure at its minimum and describe the consequence; that is enough to rate it Critical, and the ladder is written so it is.

**Every one of these fields carries observed system output, so the redaction rule applies to all of them.** `minimal_repro`, `worst_observed`, `generalization`, and `stakeholder_impact` must contain no real credentials, tokens, session identifiers, customer data, or internal hostnames — use placeholders (`<tenant A>`, `<redacted token>`, `example.com`), exactly as everywhere else in a session's output. A repro that only works with a real secret pasted into it is a repro that must be rewritten to name where the secret lives instead.

## Handing off

**A third consumer sits downstream of `minimal_repro` specifically: the `stride-exploratory-testing-harden` skill.** An isolated minimal repro is a test case that has not been written down yet — it is the shortest set of conditions that still triggers the failure, which is precisely what a minimal test case is. That skill reads a session's confirmed bugs, detects the project's own test framework, and drafts a regression check per bug from that field, so the bug cannot come back unnoticed. This is why **Isolate** repays its cost twice: once in the report a developer can act on, and again in the check that keeps the fix honest. It is also why `"not established: …"` matters rather than embarrassing — a bug whose repro was never isolated is one that skill will honestly report as not convertible instead of guessing a trigger for it.

The `oracles` skill decides *whether* a result is a defect; this skill decides what that defect looks like by the time anyone reads it, and how bad it is. The finished write-up flows into the session notes and the debrief (the `session` skill), and the `explorer` agent emits it as a `bugs[]` entry — `minimal_repro`, `worst_observed`, `generalization`, `stakeholder_impact`, and `severity` are the four RIMGEA products plus the rating.

Two of the steps feed work back upstream rather than into the report. **Generalize** often reveals a whole class of failure worth its own mission — that goes to `chartering` as a candidate charter. And an **unverified escalation** from Maximize goes to the off-charter parking lot for the same reason: the next session demonstrates it or rules it out, and only then does it touch a severity.
