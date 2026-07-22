---
name: session
description: Use when you are running an exploratory-testing session end to end and need the discipline that turns wandering into reportable value — time-boxing, the SBTM session sheet, note conventions, stopping heuristics, and the debrief. Supplies the session lifecycle, Task Breakdown Metrics, the off-charter parking lot, and both debrief templates (explored/found/unknown and Jonathan Bach's PROOF). Invoked by the exploratory-testing orchestrator, the explorer subagent, the stride-exploratory-testing-explore command-skill, and the stride-exploratory-testing-debrief command-skill.
skills_version: "1.0"
---

# session

## STOP — orchestrator check

This is an internal doctrine skill, dispatched by the orchestrator. If you arrived here directly from a user prompt, activate the `stride-exploratory-testing` orchestrator skill first — it teaches the mental model and routes the request here with the right framing. Do not proceed from a cold user prompt; the orchestrator is the front door, this skill is not.

Unstructured exploration meanders. The **session** is the container that makes exploration reportable: a time-boxed, chartered, reviewable block of testing with notes taken as you go and a debrief at the end. This skill supplies that discipline — the lifecycle, the session sheet, the metrics, and the debrief — so a session produces information a stakeholder can act on, not just a vague "I poked at it."

## The time-boxed session

A session is:

- **Time-boxed** — one uninterrupted block, typically **60–120 minutes** (SBTM's default is ~90). Long enough to get deep, short enough to stay focused and to report on.
- **Chartered** — it has exactly one charter (from the `chartering` skill). One charter per session keeps the mission clear.
- **Uninterrupted** — no multitasking; the whole box is spent on this charter.
- **Reviewable** — it ends in a session sheet and a debrief that someone else can read.

## The session lifecycle

1. **Charter** — state the mission (target, resources, information sought). One charter.
2. **Set up** — prepare data, environment, tools, and accounts. Setup time is tracked separately (it's real, but it isn't testing).
3. **Explore** — run the design/execute/learn/steer loop, generating probes with `heuristics` and judging results with `oracles`.
4. **Note** — capture findings *as they happen* (see conventions below). Don't rely on memory to the end.
5. **Debrief** — review what was covered, what was found, and what's still at risk (see templates below).

## Note conventions

Capture these as you go, tagged so they're separable at debrief time:

| Tag | What it captures |
|---|---|
| **Test idea** | A probe worth running, now or later. Un-run ideas can become new charters. |
| **Question** | Something you don't understand or can't answer yet — for the team or the docs. |
| **Risk** | A way this could hurt someone if it's wrong; feeds future charters. |
| **Surprise** | Anything that didn't match your expectation — surprises are where bugs hide. |
| **Bug** | An oracle-confirmed problem: what you did, what happened, why it's wrong. |
| **Off-charter** | Anything interesting that is *not* this charter's mission — goes to the parking lot. |

## The off-charter parking lot

Exploration constantly surfaces interesting things outside the current charter. Chasing them all destroys focus; ignoring them loses information. The rule: **park it**. Write the off-charter item down and keep testing the charter. At debrief, the parking lot becomes a source of new charters. When the parking lot grows large, that's a signal in itself — an under-explored area worth its own session or two.

## The SBTM session sheet

The session's reviewable artifact. A minimal sheet:

```
CHARTER
  <the one-line charter>
TESTER / DATE / DURATION
  <who, when, time-box length>
AREAS COVERED
  <features, data, configurations, platforms actually touched>
TASK BREAKDOWN METRICS
  Test:  __%   Bug: __%   Setup: __%
  On-charter: __%   Off-charter (opportunity): __%
NOTES
  <the running log of test ideas, questions, risks, surprises>
BUGS
  <oracle-confirmed problems, each with repro + why-wrong>
QUESTIONS / RISKS
  <open questions and risks for the team>
OFF-CHARTER PARKING LOT
  <interesting items outside this charter -> candidate charters>
```

### Task Breakdown Metrics (TBS)

Divide the session's time across three activities and report each as a rough percentage — precision isn't the point; the *shape* is:

- **Test** (**T**) — test design and execution: the actual exploring.
- **Bug** (**B**) — bug investigation and reporting: reproducing, isolating, writing up.
- **Setup** (**S**) — session setup: getting data, environments, and tools ready.

Also report **on-charter vs. off-charter (opportunity) %** — how much of the box served the charter vs. valuable detours. A session that's 70% setup, or 60% off-charter, tells the team something about the product and the environment, not just the tester.

## Stopping heuristics — when you have explored enough

Stop the session (or the charter) when any of these holds:

- **The charter has stopped surfacing new information** — probes keep confirming what you already know. Diminishing returns.
- **The time box is up.** Stop, debrief, and charter a follow-up if risk remains.
- **Remaining risk is acceptable** — what's left unexplored isn't worth a stakeholder's worry.
- **You're blocked** — you need setup, data, access, or an answer you can't get now. Note the blocker and stop; don't burn the box spinning.

"Explored enough" is a judgment, not a coverage number — a charter that keeps finding things means there's more risk to chase; one that's gone quiet is done for now.

## Debrief templates

At the end of the box, produce a debrief. Two complementary formats:

**Explored / Found / Unknown** — the concise, stakeholder-facing summary:

- **What I explored** — the areas, data, and configurations actually covered (and what I deliberately did *not*).
- **What I found** — bugs, risks, and surprises, most important first.
- **What remains unknown** — the questions still open and the risk not yet covered — the honest edge of the map.

**PROOF** (Jonathan Bach's SBTM debrief mnemonic) — the fuller session review:

| Letter | Prompt |
|---|---|
| **P — Past** | What happened during the session — what was actually done. |
| **R — Results** | What was achieved — coverage reached, bugs and questions found. |
| **O — Obstacles** | What got in the way — blockers, missing tools, unclear requirements. |
| **O — Outlook** | What still needs doing — the charters and risks left for next time. |
| **F — Feelings** | How the tester feels about the product and the session — intuition is data; unease often precedes a found bug. |

Use Explored/Found/Unknown for the written report; use PROOF when reviewing the session with the team (or with yourself) to make sure nothing — including a gut feeling — goes uncaptured.

## Edge cases

- **The charter runs out mid-box.** If you've explored it enough before the time is up, either stop early (and say so in the debrief) or pull a related item from the parking lot and, if it deserves its own mission, charter it rather than silently drifting.
- **A large off-charter parking lot.** Don't try to test it all in this session. Convert the parked items into new charters at debrief and schedule them — a big parking lot is a map of under-explored territory, not overflow to cram in.

## Safety of session artifacts

Session notes and debriefs are examples and reports — they **must not include real user data, credentials, or internal hostnames**; use placeholders and redact. And a debrief reports **externally verifiable facts** — what actually happened and what was actually observed — never fabricated or assumed results. If a result wasn't observed, it belongs under "unknown," not "found."

## Handing off

The `chartering` skill produces the charter this session runs; `heuristics` and `oracles` drive and judge the exploration inside it. New charters discovered here flow back to `chartering`'s backlog. The `stride-exploratory-testing-explore` command-skill runs this whole lifecycle in one shot; the `stride-exploratory-testing-debrief` command-skill produces just the debrief from a completed session.
