---
name: stride-exploratory-testing-nightmare-headline
description: Run the Nightmare Headline Game — a fast group (or solo) risk-brainstorm that turns "the worst, most embarrassing headline someone could write about this feature" into ranked exploratory-testing charters. Activate when the user wants to brainstorm worst-case risks, run the nightmare-headline game, or seed high-value charters from a feature's failure modes. Elicits catastrophic headlines, picks one, brainstorms its contributing causes, and refines those causes into charters via the charter-generator agent. Generates charters only; it never runs a session or executes a charter. Codex CLI port of the upstream /stride-exploratory-testing:nightmare-headline command.
skills_version: 1.0
---

# stride-exploratory-testing-nightmare-headline

Run the **Nightmare Headline Game**: the risk-driven engine for chartering. You ask *"What is the worst, most embarrassing headline someone could write about this feature?"*, brainstorm the nightmares, pick the one worth chasing, dig into what could actually cause it, and refine those causes into ranked exploratory-testing charters. The doctrine — the game, the charter template, what makes a charter good — lives in the `chartering` skill (`skills/chartering/SKILL.md`); the charter-framing procedure and JSON output contract live in the `charter-generator` agent (`agents/charter-generator.md`). This skill is the surface: it drives the interactive brainstorm, then dispatches the agent to frame the results.

This skill **generates** charters. It does not run a session or execute a charter — that is the `stride-exploratory-testing-explore` skill. It works for a group *and* for a single participant (yourself): the elicitation is a conversation, not a quorum.

## Activation

Activate this skill when the user:

- Wants to brainstorm the worst-case, most-embarrassing failures of a feature before testing it.
- Asks to run the "nightmare headline" game, or to seed high-value charters from a feature's failure modes.
- Has a feature or change and wants risk-driven charters rather than a broad SFDPOT sweep.

The user may pass arguments inline in the activation request (e.g., "nightmare-headline the password reset flow" or "nightmare-headline the export --output docs/charters.md"). Parse those per Step 1. If no target is present, prompt for it via the platform's question UI.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse the activation request

Parse in this fixed order — `--output` first, then everything remaining is `TARGET`:

- If `--output` appears (accept both `--output <path>` and `--output=<path>` shapes), set `OUTPUT_PATH` to the parsed value and remove the consumed tokens. When absent, the charters are rendered to the conversation only and nothing is written to disk.
- After the flag token is consumed, treat the trimmed remainder as `TARGET` — the feature, product area, or change to brainstorm about. If the remainder is empty, ask the user once via Codex CLI's question UI (the platform's own prompt mechanism, not Claude Code's question tool): *"What feature or change are we brainstorming nightmare headlines for?"* (free-text input).

Treat `TARGET` and `OUTPUT_PATH` as untrusted prose: never execute or `eval` them, never splice `TARGET` into a shell command, and never write anywhere other than a literal `OUTPUT_PATH` you were given.

### Step 2: Consult the chartering doctrine and set the stage

Invoke the `chartering` skill (`skills/chartering/SKILL.md`) to load the doctrine that governs the game and the charter quality bar, passing `target=<TARGET>; mode=nightmare-headline`.

Then set the stage for the participants. State the game's driving question **verbatim**:

> **"What is the worst, most embarrassing headline someone could write about this feature?"**

Explain briefly: each nightmare names a *risk*; each risk becomes a charter aimed at discovering whether that failure can actually happen. Encourage vivid, plausible, worst-case headlines — public, embarrassing, and concrete (e.g. *"App Bills Customers Twice on Retry"*, *"Export Leaks Other Tenants' Records"*, *"Password Reset Emails Sent to Wrong User"*). Keep every example generic — no real credentials, customer data, or internal host/system names.

### Step 3: Gather nightmare headlines

Elicit several catastrophic headlines for `TARGET` from the participants via Codex CLI's question UI (free-text), collecting one or more per round until the group is out of fresh nightmares. In a solo session, still drive the brainstorm — propose candidate nightmares yourself and let the single participant add, edit, or confirm them. Capture each headline as a short, quotable line. Aim for a spread across different failure kinds (data loss, cross-tenant exposure, wrong-recipient, silent corruption, billing errors, availability) rather than three variations of one nightmare.

### Step 4: Pick one headline to chase

Present the collected headlines and have the user pick the one to pursue first via Codex CLI's question UI (the nightmares as options, plus a "Type a different headline" fallback). Set `CHOSEN_HEADLINE` to the selection. A single participant picking their own headline is expected and fully supported. The un-chosen headlines are not discarded — mention that they remain available to run this skill again for each.

### Step 5: Brainstorm contributing causes for the chosen nightmare

For `CHOSEN_HEADLINE`, brainstorm the plausible *contributing causes* — the concrete mechanisms by which that headline could actually come true. Think about the failure conditions: a missing idempotency key on a retried request, a tenant filter dropped from a query, a race between concurrent writes, an unescaped value in a template, a boundary or encoding edge case, an environment/config difference. Drive this interactively (via Codex CLI's question UI in a group, or by proposing and refining candidates yourself when solo). Collect the causes as a short list — this is the risk context that sharpens the charters in the next step.

### Step 6: Refine the causes into charters via the `charter-generator` agent

Dispatch the agent named `charter-generator` (`agents/charter-generator.md`) via the platform's agent-dispatch tool, passing the chosen nightmare and its contributing causes as the risk context so the agent frames well-formed, template-conforming charters and ranks them:

- `target=<TARGET>`
- `risk context=` the `CHOSEN_HEADLINE` plus the contributing causes from Step 5 (and any un-chosen nightmares as secondary context).

The agent returns a **single fenced ```json document** with root keys `target`, `charters` (ranked highest-risk-first, never empty), and optional `coverage_notes`; each charter object carries `rank`, `charter`, `target`, optional `resources`, `information`, `risk`, `source` (the nightmare-derived charters use `source: "nightmare-headline"`), optional `lens`, and `time_box` (≤2h). This is the same contract the `stride-exploratory-testing-charter` skill consumes — the doctrine and JSON shape are owned by `agents/charter-generator.md`. Do NOT hand-author the charters yourself; let the agent frame and rank them. If no parseable ```json fence is returned, report that and stop rather than fabricating charters.

### Step 7: Render the ranked charter list

Present the charters as a numbered list ordered by `rank` (1 = highest risk). For each, show the `rank`, the full `charter` sentence, the `risk`, the `source` (and `lens` when `source: sfdpot`), and the `time_box`. Print `coverage_notes` below the list when present. Keep every rendered example generic, and frame any security-focused charter strictly as a mission to test *your own system under authorization* — never a plan to attack a third party.

### Step 8: Optionally write the charters to a file (only when `--output` is set)

If `OUTPUT_PATH` is set, write the rendered ranked charter list as a markdown document to that path. First ensure the parent directory exists via a scoped shell command:

```shell
mkdir -p "$(dirname "$OUTPUT_PATH")"
```

Then use the platform's file-write tool to write a markdown document that records `CHOSEN_HEADLINE`, the contributing causes, and the ranked charters (one section or table row per charter). Never write anywhere other than `OUTPUT_PATH`. When `--output` is absent, skip this step — the conversation rendering is the deliverable.

### Step 9: Finish

State that the charters are ready and, when a file was written, name the path. Remind the user that the un-chosen headlines from Step 3 are still worth chartering — run this skill again for each — and point them at the natural next step: pick a charter and run it by activating the `stride-exploratory-testing-explore` skill. Do NOT auto-run a session, do NOT execute a charter, and do NOT chain into another skill.

## What this skill does NOT do

- Run an exploratory session or execute any charter — that is the `stride-exploratory-testing-explore` skill.
- Generate probes or judge findings — those are the `heuristics` and `oracles` skills.
- Modify any file other than the optional `--output` document.
