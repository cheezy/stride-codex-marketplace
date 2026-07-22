---
name: heuristics
description: Use when you need concrete test ideas — a named lens to get unstuck, decide what to vary, or systematically walk a feature. This is the plugin's single source of truth for heuristics: the general and web cheat sheets, the variable-spotting catalog, and Whittaker's Tours grouped by district. Every other skill and agent links here rather than duplicating the catalog. Invoked by the exploratory-testing orchestrator, the explorer subagent, and the stride-exploratory-testing-explore command-skill whenever a charter needs to be turned into specific probes.
skills_version: "1.0"
---

# heuristics

## STOP — orchestrator check

This is an internal doctrine skill, dispatched by the orchestrator. If you arrived here directly from a user prompt, activate the `stride-exploratory-testing` orchestrator skill first — it teaches the mental model and routes the request here with the right framing. Do not proceed from a cold user prompt; the orchestrator is the front door, this skill is not.

Heuristics are the engine that turns a charter into concrete experiments. A heuristic is a **fallible idea generator** — a named lens that suggests what to try next. None is a rule; each is a prompt. You apply them inside the design/execute/learn/steer loop: pick a lens, generate a probe, run it, and let what you learn choose the next lens.

**This file is the canonical catalog.** Other skills and agents reference these lenses *by name* (e.g. "apply Goldilocks and Follow the Data") instead of re-listing them. When you add a heuristic, add it here.

## How to use this catalog

1. Start from the charter's target and the information you're chasing.
2. Scan the **General Heuristics** for lenses that fit the target.
3. If it's a web/HTTP surface, add the **Web Heuristics**.
4. Use the **Variable Catalog** to decide *what to vary* within a chosen lens.
5. Use the **Tours** when you want a themed walkthrough of a whole area rather than a single probe.

Two working rules:

- **Web-only lenses don't apply to non-web targets.** If the charter's target is a CLI, a library, or a background job, skip the Web Heuristics section — forcing URL/cookie lenses onto a non-web target generates noise, not risk.
- **Disambiguate overlapping lenses.** Some lenses are refinements of others: **Zero, One, Many** is the general count lens; the standalone **Zero** case (empty collection, null, "" , 0) is the single most productive slice of it — call out which you mean. **Goldilocks** (too big / too small / just right) overlaps **Too Many, Too Few** — use Goldilocks for a single value's magnitude, Too Many/Too Few for the size of a collection.

## General Heuristics

| Heuristic | What to try |
|---|---|
| **Zero, One, Many** | A collection with zero items, exactly one, and many. Zero and one expose the empty-state and singular-plural bugs. |
| **Goldilocks** | A value that is too big, too small, and just right. Push both extremes and the boundary between them. |
| **Some, None, All** | For selections, filters, permissions, bulk actions: choose some, none, and all. |
| **CRUD** | Exercise Create, Read, Update, and Delete on each entity — and combinations (delete then read, update a deleted item). |
| **Follow the Data** | Create a datum, then read / update / delete it from every place it surfaces. Verify it stays consistent end to end. |
| **Interrupt** | Cancel, close, log off, restart, kill the process, lose the network, or let it time out **mid-operation**. |
| **Reverse** | Do the steps in the opposite order; undo then redo; navigate backward through a wizard. |
| **Starve** | Deny resources: low memory or disk, slow CPU, throttled or dropped network, an exhausted quota or rate limit. |
| **Violate Format** | Feed values that break the expected format — wrong type, encoding, delimiter, length, or schema. |
| **Beginning, Middle, End** | Act at the start, the middle, and the end of a sequence, range, document, or list — boundaries live at the seams. |
| **Centralize / Decentralize** | Put everything in one place (one giant record, one account) vs. spread thin across many. |
| **Change the Model** | Vary the mental model: a different role, locale, currency, unit, time zone, or workflow than the "happy" one assumed. |
| **Zoom In / Zoom Out** | Examine a single item in fine detail; then step back to the aggregate, the report, the whole-system view. |
| **Too Many, Too Few** | Exceed and undershoot expected quantities and configured limits (max upload count, min required fields). |
| **Back, Forward, History** | Navigate backward and forward, replay history, resubmit a prior step. |
| **Bookmark It** | Capture a deep state (a saved link, a mid-flow token) and return to it later, out of order, or from a fresh session. |

## Web Heuristics

Apply these when the target is a web/HTTP surface. (Skip for non-web targets.)

| Heuristic | What to try |
|---|---|
| **Tamper the URL** | Edit the path, query params, and record IDs of **your own** app to probe access control and input validation. |
| **Back / Forward / Resubmit** | Browser back after a submit, forward into a stale page, double-submit a form, F5 on a POST. |
| **Deep Link / Bookmark** | Enter mid-flow through a saved deep link — unauthenticated, out of sequence, or after the underlying record changed. |
| **Refresh / Reload** | Reload during a long operation; reload after partial input; reload a page whose data has since changed. |
| **Multiple Tabs / Windows** | Two tabs sharing one session; concurrent edits of the same record; log out in one tab while acting in another. |
| **Cookies / Session** | Let the session time out mid-action; clear, expire, or tamper cookies; act with a stale CSRF token. |
| **Special Characters & Injection** | Unicode, emoji, RTL marks, long strings, and HTML/script/SQL metacharacters in inputs — observe how they're escaped, encoded, or stored. Framed for **authorized testing of your own system only**; keep payloads illustrative and non-destructive. |
| **Copy / Paste / Autocomplete** | Paste rich or multi-line text, browser autofill, and values with leading/trailing whitespace. |
| **Resize / Zoom / Responsive** | Narrow viewport, high browser zoom, orientation change — layout, focus order, and hidden-control bugs. |

## Variable Catalog

When a lens says "vary it," this catalog says *what dimensions exist to vary*. Spot the variables in the target, then push each one with the general heuristics above.

| Variable | Dimensions to push |
|---|---|
| **Count** | Number of items: zero, one, many, too many, exactly at the limit. |
| **Position** | Where in a sequence or range: beginning, middle, end, just inside/outside a boundary. |
| **Files & storage** | File type, size, name (Unicode, spaces, very long), permissions, missing / locked / corrupt / zero-byte. |
| **Geography / locale** | Country, language, time zone, currency, number and address formats, right-to-left scripts. |
| **Format** | Encoding, delimiters, MIME type, schema version, structured vs. malformed. |
| **Size** | Length, magnitude, dimensions — empty, tiny, huge, at and beyond the maximum. |
| **Depth** | Levels of nesting or recursion — flat vs. deeply nested structures, self-reference. |
| **Timing / frequency / duration** | How fast, how often, how long — concurrency, ordering, races, retries, timeouts, very short and very long durations. |
| **Input / navigation method** | Keyboard vs. mouse vs. touch vs. API; the path taken through the UI; the entry point into a flow. |

## Tours

A **Tour** is a themed walkthrough of an area, biased toward one kind of risk — a way to cover a whole district with a consistent intent instead of a single probe. Whittaker groups tours by *tourist district*; pick the district whose risk matters for your charter.

### Business District — the features that deliver the most value
- **Guidebook Tour** — follow the documentation/manual exactly; every gap or lie between docs and product is a finding.
- **Money Tour** — walk the features that sell the product or make the money; these deserve the most scrutiny.
- **Landmark Tour** — pick the "landmark" features and visit them in varied orders, mapping the paths between them.
- **Intellectual Tour** — ask the software the hardest questions it should be able to answer (max inputs, edge configurations).
- **FedEx Tour** — follow a piece of data like a package from entry to every place it's stored, transformed, and displayed.
- **Garbage Collector's Tour** — visit every screen/field methodically, shortest-path, leaving nothing unvisited.
- **After-Hours Tour** — exercise what runs when users are away: batch jobs, backups, scheduled tasks, end-of-day processing.

### Historical District — old and previously-broken code
- **Bad-Neighborhood Tour** — revisit the areas where bugs have clustered before; defects breed near defects.
- **Museum Tour** — exercise legacy features and old code paths that survived into the current version.
- **Prior Version Tour** — rerun scenarios that worked in the last release, hunting regressions.

### Tourist District — features you visit quickly to gawk
- **Collector's Tour** — collect every output, result, and message the software can produce; enumerate the range.
- **Lonely Businessman Tour** — follow the longest, most convoluted path a determined user might take.
- **Supermodel Tour** — attend only to the surface: layout, styling, labels, focus, animation — pure UI.
- **Scottish Pub Tour** — seek out the obscure, hidden, and hard-to-find features nobody advertises.

### Entertainment District — supporting features
- **Supporting Actor Tour** — test the features adjacent to the main ones (the fields and controls next to the star feature).
- **Back Alley Tour** — exercise the least-used, least-loved features — the ones most likely under-tested.
- **All-Nighter Tour** — never close or log off; keep the app running for a long time to surface leaks and stale state.

### Hotel District — the "resting" features
- **Rained-Out Tour** — start operations and then cancel, pause, or abandon them; poke what happens when nothing finishes.
- **Couch Potato Tour** — do as little as possible: accept every default, leave fields blank, click straight through.

### Seedy District — the mean, nasty tours
- **Saboteur Tour** — actively try to break it: pull the network, corrupt the input, kill the process at the worst moment.
- **Antisocial Tour** — do the opposite of what's expected — the least-likely inputs and out-of-order actions.
- **Obsessive-Compulsive Tour** — repeat the same action over and over; redo, resubmit, re-enter; do it again immediately.

## Safety of security-flavored heuristics

The injection and Saboteur-style lenses are for **authorized testing of a system you own or are permitted to test** — never for attacking third parties. Keep example payloads clearly illustrative and non-destructive; this catalog contains no live exploit code targeting external systems, and neither should the probes you derive from it.

## Handing off

The `chartering` skill decides *what* to explore; this skill supplies the lenses to probe it; the `oracles` skill decides whether what you observed is a *problem*; the `session` skill wraps it all in a time-boxed session. Reach for a Tour when you want breadth over an area, and a single heuristic when you want depth on a specific risk.
