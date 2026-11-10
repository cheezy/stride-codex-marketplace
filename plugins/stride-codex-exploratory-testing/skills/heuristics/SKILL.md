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
2. Scan the **General Heuristics** for lenses that fit the target. If the charter comes out of a change (a diff, a new feature, a fix), start with its **change-risk lenses**: the *When it applies* column of each one names the kind of change it is meant for.
3. If it's a web/HTTP surface, add the **Web Heuristics**, and its change-risk lenses with them.
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
| **Interrupt** | Break off what the app is doing **mid-operation**, using in-app means only: log off, navigate elsewhere, close the tab, cancel, or leave a request to time out. Restart or stop a process only when you launched it yourself; every other process, the network and the machine itself stay out of bounds. |
| **Reverse** | Do the steps in the opposite order; undo then redo; navigate backward through a wizard. |
| **Starve** | Run the app short of a resource, by in-app means only: push an app-level quota or a rate limit to its end with disposable test data, or reduce a limit by way of an app setting or feature flag that the environment you were given lets you change, then restore it. Operating-system, memory, disk, CPU and network resources stay untouched, and so does every other host. |
| **Violate Format** | Feed values that break the expected format — wrong type, encoding, delimiter, length, or schema. |
| **Beginning, Middle, End** | Act at the start, the middle, and the end of a sequence, range, document, or list — boundaries live at the seams. |
| **Centralize / Decentralize** | Put everything in one place (one giant record, one account) vs. spread thin across many. |
| **Change the Model** | Vary the mental model: a different role, locale, currency, unit, time zone, or workflow than the "happy" one assumed. |
| **Zoom In / Zoom Out** | Examine a single item in fine detail; then step back to the aggregate, the report, the whole-system view. |
| **Too Many, Too Few** | Exceed and undershoot expected quantities and configured limits (max upload count, min required fields). |
| **Back, Forward, History** | Navigate backward and forward, replay history, resubmit a prior step. |
| **Bookmark It** | Capture a deep state (a saved link, a mid-flow token) and return to it later, out of order, or from a fresh session. |

### General change-risk lenses

Choose these by what the change under test touches; the *When it applies* cell of each row names the change it suits. Four of them build on lenses found elsewhere in this catalog: **Pull the Rug** works like Interrupt and keeps the same in-app limits (see *Safety of security-flavored heuristics*), **Developer Guidebook** extends the **Guidebook Tour**, **Every Locale** narrows **Change the Model** and the Geography / locale variable, and **Who Else Is Watching** widens **Multiple Tabs / Windows** from the Web Heuristics.

| Heuristic | What to try | When it applies |
|---|---|---|
| **Change the Rights** | With the user's view still open, lower, give back or take away their role, membership or plan from a second session, then act in the old view: each control, count and save has to follow the rights as they are now, not as they were when the page loaded. E.g. drop a test member from a shared workspace you set up, then edit an item from the member's view that never reloaded. | When a change touches roles, membership, plans, quotas or anything else that limits what a user is allowed to do. |
| **Shadow Decision** | Find each spot where the client repeats a decision the server owns — a control shown, hidden or enabled, a "remaining" counter, a guessed file type, a plan badge — and set the two against each other; the server is right and the client has to follow it. E.g. from a second session, fill a quota to one short of its limit, then press the still-enabled add button twice. | When a change adds, moves or copies a rule that the server enforces and the client also shows or checks in advance. |
| **Who Else Is Watching** | For each write, name every open view that shows the data it changes — other tabs, other users, lists, counters, badges, notifications — and confirm each one updates, or clearly says it is out of date, with no reload. E.g. rename a record in one session and watch its title in another user's list, detail page and breadcrumb. | When a change adds or alters a create, update or delete, or a real-time broadcast. |
| **Pull the Rug** | Using in-app means only, and only on test data you created, delete, archive or move the parent of a view that is still open — the folder of an open document, the project of an open task — then act in that child view: save, navigate, refresh. E.g. in a second tab, delete a folder you made while a document in it is open for editing, then save the document. | When a change adds or alters a child view, a nested route, or a delete or move of a parent entity. |
| **Every Surface** | List every place that shows or edits the entity — each route, page, template, modal, list, archive or history view, second edit route, export, email, API response and command-line output — and check that the change arrived in all of them. E.g. once a field is added to a record's edit form, look for it on the archived-record page and in the bulk-edit dialog. | When a change alters how an entity is shown, validated or edited. |
| **Every Locale** | Read each new or changed string in every locale the product ships: plural forms, formal and informal register, number, date and size formats, text that outgrows its space, and CJK punctuation where pieces of a sentence are joined. E.g. in each shipped language, look at "1 file", "2 files" and a size such as 1.5 MB. | When a change adds or edits user-visible text, a message assembled from pieces, or a formatted number, date or size. |
| **Developer Guidebook** | Carry the **Guidebook Tour** over to the documents developers read — module docs, design docs, the README and the changelog: each thing they say about the change is a probe, and each place where behaviour departs from what they say is a finding. E.g. the changelog says deleting a list archives its items; delete a list you created and look for those items in the archive. | When a change ships with module docs, a design doc or a changelog entry, or ought to have. |
| **Leave No Trace** | When the feature or its tests have finished, look for what they left behind in places you may read — temporary files, uploads, generated reports, cache or lock files, jobs still waiting to run — and note what you find instead of deleting it. List those places with `ls` through `shell`. E.g. run one export, then list the app's temp and upload directories for files that outlasted it. | When a change writes files, starts background jobs, or adds tests that leave state on disk. |
| **Telemetry Semantics** | For each event, metric or log line the change emits, check that it fires exactly when its name says it does, once, with the documented fields and units — and not on a failed attempt, a retry or a reload. E.g. an order-completed event must not fire when payment fails or when the confirmation page is reloaded. | When a change adds or alters telemetry, metrics, audit logs or analytics events. |

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

### Web change-risk lenses

Picked the same way, and for web/HTTP targets only. **After the Headers** works like Interrupt and keeps its in-app limits; **Other Verbs** takes **Tamper the URL** past the path to the method and the headers. Make these requests with `curl -q -sS -i` through `shell`, so the status line and headers stay visible, and never follow a redirect with `-L`.

| Heuristic | What to try | When it applies |
|---|---|---|
| **Other Verbs** | Send the route ordinary requests with other methods and headers — HEAD, OPTIONS, a Range header, a conditional If-None-Match or If-Modified-Since — and check that the status, headers and body are consistent with GET. Framed for **authorized testing of your own system only**. E.g. a HEAD on a new download route should come back with GET's headers and no body, and a Range request with either a correct 206 or a plain 200. | When a change adds or alters a route, a download, or a cached or streamed response. |
| **After the Headers** | Using in-app means only, make the source of a streamed response fail once its status and headers have been sent: change or delete the disposable test record or file it is streaming, through the app's own UI or API, or cancel the job feeding it. Watch for it on a **real server**, with a client that prints the raw response, such as `curl -q -sS -i` through `shell`; an in-process test adapter holds the whole response back and never shows that window. E.g. start a large export of test data you created, delete its source from another session while it streams, and see whether the client receives a cut-short file under a 200. | When a change adds or alters a streamed, chunked or long-running response. |
| **Response Hardening** | Check the security headers on every kind of response the change can produce — HTML, JSON, downloads, redirects, error pages, not-found pages — and not just the main page: content security policy, framing, content-type sniffing, caching of private data, cookie flags. Framed for **authorized testing of your own system only**: send ordinary requests and read the headers that come back. E.g. compare a new download's headers with an ordinary page's, watching for a private file served with a public cache header. | When a change adds a route, a response type, a file download or an error path. |

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
- **Saboteur Tour** — set out to break it using in-app means only: feed it corrupted input, abandon or cancel a flow at the worst possible moment, exhaust an app-level quota using disposable test data. The network, a process someone else started, the operating system and other hosts are off limits.
- **Antisocial Tour** — do the opposite of what's expected — the least-likely inputs and out-of-order actions.
- **Obsessive-Compulsive Tour** — repeat the same action over and over; redo, resubmit, re-enter; do it again immediately.

## Safety of security-flavored heuristics

The injection and Saboteur-style lenses are for **authorized testing of a system you own or are permitted to test** — never for attacking third parties. Keep example payloads clearly illustrative and non-destructive; this catalog contains no live exploit code targeting external systems, and neither should the probes you derive from it.

**Interrupt, Starve and the Saboteur Tour are limited to in-app means.** In practice: a cancel sent through the UI or API, a closed tab, a log-off, a request left to time out, a limit lowered by an app setting or a feature flag you may change in the environment you were given (never shared state, and put back afterwards), or an app-level quota exhausted using disposable test data. Never stop a process you did not start, leave operating-system, network and other system resources unaltered, and stay off every host outside the authorized target.

**Pull the Rug and After the Headers share the Interrupt limits.** Pull the rug, or make a streamed source fail, only through the app's own UI or API and only on test data you created. Never stop the server or a process you did not start, leave the network as it is, and stay off every other host. **Other Verbs and Response Hardening are for authorized testing of your own system only**: send ordinary requests to the authorized target with `curl` through `shell` and read what comes back — no scanners, no floods, no other host.

## Handing off

The `chartering` skill decides *what* to explore; this skill supplies the lenses to probe it; the `oracles` skill decides whether what you observed is a *problem*; the `session` skill wraps it all in a time-boxed session. Reach for a Tour when you want breadth over an area, and a single heuristic when you want depth on a specific risk.
