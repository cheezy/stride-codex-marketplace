---
name: chartering
description: Use when you need to decide WHAT to explore and frame it as a charter before a testing session — writing a charter, splitting an overbroad one, turning a risk or requirement into a mission, or enumerating candidate targets across a product. Produces concise, time-boxed charters in the form "Explore <target> with <resources> to discover <information>". Invoked by the exploratory-testing orchestrator and by the stride-exploratory-testing-charter and stride-exploratory-testing-nightmare-headline command-skills.
skills_version: "1.0"
---

# chartering

## STOP — orchestrator check

This is an internal doctrine skill, dispatched by the orchestrator. If you arrived here directly from a user prompt, activate the `stride-exploratory-testing` orchestrator skill first — it teaches the mental model and routes the request here with the right framing. Do not proceed from a cold user prompt; the orchestrator is the front door, this skill is not.

A **charter** is the mission for an exploratory session: a short statement of what to explore, with what, to learn what. It is the central artifact of exploratory testing — it gives a session *direction* without scripting the steps, leaving the tester free to design each probe from what the last one revealed.

This skill produces good charters and enumerates candidate targets. It does not run the session (that's the `session` skill) or generate the probes (that's `heuristics`) — it decides what the session is *about*.

## The charter template

Every charter fits this shape:

> **Explore** `<target>`
> **with** `<resources>`
> **to discover** `<information>`

- **Target** — what you're exploring: a feature, a component, a data flow, an interaction, a quality (performance, security, accessibility).
- **Resources** — what you'll use: tools, data sets, personas, environments, documents, a domain expert's time. Resources are optional but sharpen a charter.
- **Information** — what you hope to learn: the risk you're chasing, the question you're answering. This is the *point* of the session.

Examples:

- *Explore* the CSV import *with* malformed and oversized files *to discover* how the parser fails and whether it corrupts existing data.
- *Explore* multi-tab session handling *with* two browser tabs logged in as the same user *to discover* state-desync and stale-write problems.
- *Explore* the date-range filter *with* boundary and reversed ranges *to discover* off-by-one and empty-result handling.

## What makes a good charter

A good charter **gives direction, not steps**. It points the tester at a risk and trusts them to find the path.

- **It fits in a tweet.** If you can't state the charter in a sentence or two, it's too big — split it. Concise charters keep the session focused.
- **It is time-boxed.** A charter should be explorable in a single session of **no more than ~2 hours**. If it clearly can't be, it's really several charters.
- **It is not a test case.** "Verify that uploading a 5 MB PDF returns a 200 and shows a success toast" is a *check* with a known expected result — write that as an automated test. A charter has an *open* question: "…to discover how uploads fail," not "…to confirm uploads succeed."
- **It is not too broad.** "Explore the app to discover bugs" gives no direction at all. Name a target and the information you're after.
- **It names the information, not just the target.** "Explore checkout" is a target with no mission. "Explore checkout with expired and mismatched payment methods to discover how declines are surfaced" is a charter.

### Good vs. bad

| Weak | Why | Reframed |
|---|---|---|
| Explore the whole application. | No target, no mission — unbounded. | Explore the notification preferences page to discover which changes silently fail to persist. |
| Verify the login form rejects a blank password. | A test case with a known expected result — that's a check. | Explore the login form with unusual and boundary credentials to discover inconsistent validation and error messaging. |
| Explore reporting, exports, dashboards, and scheduling. | Four charters wearing a trench coat — can't fit a session. | Explore scheduled-report delivery with time-zone and DST-boundary schedules to discover missed or duplicated runs. |

## Where charters come from

You rarely start from a blank page. Charter sources, in rough order of how often they pay off:

- **Requirements and specs** — each stated behavior implies a charter to probe its edges and its unstated assumptions.
- **Implicit expectations** — the things no one wrote down but everyone assumes (data survives a refresh, concurrent edits don't clobber each other, errors are recoverable).
- **Stakeholder questions** — "does this hold up under load?", "what happens on a flaky network?" Each worried question is a charter.
- **Existing artifacts** — logs, past bug reports, support tickets, analytics, and the code itself. A cluster of past defects marks a neighborhood worth re-exploring.
- **The Nightmare Headline Game** — risk-storming for the worst plausible outcome (see below).
- **New realizations mid-session** — the richest source. Exploration constantly surfaces new questions; capture them as follow-up charters rather than chasing every rabbit hole immediately.

## The Nightmare Headline Game

A fast way to turn *risk* into charters. Ask:

> **"What is the worst, most embarrassing headline someone could write about this feature?"**

Brainstorm the nightmares — "App Bills Customers Twice on Retry", "Export Leaks Other Tenants' Records", "Password Reset Emails Sent to Wrong User". Each nightmare names a risk; each risk becomes a charter aimed at discovering whether that failure can actually happen.

- *Nightmare:* "Export Leaks Other Tenants' Records" → *Charter:* Explore the report export with two tenants' data present to discover any cross-tenant leakage in filenames, contents, or cached results.
- *Nightmare:* "App Bills Customers Twice on Retry" → *Charter:* Explore the payment flow with retried and double-submitted requests to discover duplicate charges and missing idempotency.

This is the risk-driven engine behind the `stride-exploratory-testing-nightmare-headline` command-skill.

## Enumerating targets with SFDPOT

When you need to be *systematic* about what to charter — to make sure you looked at the whole product, not just the obvious parts — walk the **SFDPOT** lens from the Heuristic Test Strategy Model. It is a coverage heuristic for generating candidate targets:

| | Dimension | Charter prompts |
|---|---|---|
| **S** | **Structure** | What the product is made of — files, code, modules, hardware. What component's internals carry risk? |
| **F** | **Function** | What the product does — every feature and how they interact. Which function is new, complex, or error-prone? |
| **D** | **Data** | What it processes — inputs, outputs, states, big/small/null/malformed values, sequences over time. What data shapes break it? |
| **P** | **Platform** | What it depends on — OS, browser, hardware, third-party services, configuration. Which platform combination is under-tested? |
| **O** | **Operations** | How it's used — real personas, usage patterns, environments, edge-case workflows. Whose real-world use is unusual? |
| **T** | **Time** | How timing affects it — sequences, races, timeouts, scheduling, DST, order-of-operations. Where does timing matter? |

Sweep SFDPOT over a feature and you get a spread of candidate charters that a single obvious angle would miss. Use it as an idea generator, not a checklist to grind through — stop when you have enough charters to fill the sessions you can actually run.

## Handling the two common failure shapes

- **Overbroad charter → split it.** If a charter names several targets or clearly can't fit a session, break it into one charter per target/risk, each independently explorable in ≤2 hours.
- **"Charter" that is really a test case → reframe it.** If it has a single known expected result, it's a check. Either write it as an automated test, or widen it into an open question ("…to discover how X behaves under Y") that a session can genuinely *explore*.

## Safety of charter examples

Keep every example **generic**: no real credentials, customer data, or internal system or host names — use placeholders (`<tenant A>`, a sample dataset, `example.com`). Frame any **security-focused** charter (injection, auth bypass, data exposure) strictly for **authorized testing of your own system** — a charter is a mission for testing the product in front of you, never a plan to attack a third party.

## Handing off

Once you have charters, the tester picks one and runs a time-boxed session with the `session` skill, generating probes with `heuristics` and judging them with `oracles`. Un-run charters go on a backlog; new charters discovered mid-session are added to it.
