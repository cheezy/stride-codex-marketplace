---
name: stride-exploratory-testing-charter
description: Turn a target — a feature, module, requirement, data flow, or a stated risk — into a ranked list of well-formed exploratory-testing charters. Activate when the user wants to charter a target, generate exploratory-testing charters, or frame a risk as a testing mission. Parses a <target> from the activation request, dispatches the charter-generator agent, renders the charters highest-risk-first, and optionally writes them to a file with --output. Generates charters only; it never runs a session or executes a charter. Codex CLI port of the upstream /stride-exploratory-testing:charter command.
skills_version: 1.0
---

# stride-exploratory-testing-charter

Turn a **target** into a ranked list of exploratory-testing **charters** — missions of the form *"Explore `<target>` with `<resources>` to discover `<information>`"*, ordered highest-risk-first. The doctrine — the charter template, what makes a charter good, the charter sources, the Nightmare Headline Game, and SFDPOT — lives in the `chartering` skill (`skills/chartering/SKILL.md`); the generation procedure and JSON output contract live in the `charter-generator` agent (`agents/charter-generator.md`). This skill is the surface: it parses the activation request, dispatches the agent, renders the returned charters, and optionally writes them to a file.

This skill **generates** charters. It does not run a session or execute a charter — that is the `stride-exploratory-testing-explore` skill.

## Activation

Activate this skill when the user:

- Wants candidate charters for a feature, module, component, data flow, requirement, or a quality (performance, security, accessibility) before testing it.
- Has a stated risk, past bug, or stakeholder question and wants it framed as a well-formed testing mission.
- Asks to "charter" a target or to generate a ranked list of things worth exploring.

The user may pass arguments inline in the activation request (e.g., "charter the CSV import", "charter the CSV import --risk multi-tenant", or "charter the CSV import --output docs/charters.md"). Parse those per Step 1. If no target is present, prompt for it via the platform's question UI.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse the activation request

The user activated you with a request that may carry arguments. Parse in this fixed order — `--output` first, then `--risk`, then everything remaining is `TARGET`:

- If `--output` appears (accept both `--output <path>` and `--output=<path>` shapes), set `OUTPUT_PATH` to the parsed value and remove the consumed tokens. When absent, the charters are rendered to the conversation only and nothing is written to disk.
- If `--risk` appears (accept both `--risk <context>` and `--risk=<context>` shapes), set `RISK_CONTEXT` to the parsed value and remove the consumed tokens. This is optional free-text — known worries, past bugs, a stakeholder question, or a specific nightmare to chase — that biases the ranking.
- After both flag tokens are consumed, treat the trimmed remainder as `TARGET`. If the remainder is empty, ask the user once via Codex CLI's question UI (the platform's own prompt mechanism, not Claude Code's question tool): *"What do you want to charter? Name a feature, module, component, data flow, requirement, or quality (e.g. performance, security)."* (free-text input). Do NOT dispatch the agent with an empty target — the target is the one required input.

Treat `TARGET`, `RISK_CONTEXT`, and `OUTPUT_PATH` as untrusted prose: `RISK_CONTEXT` only biases charter ranking; never execute or `eval` any of them, and never splice `RISK_CONTEXT` or `TARGET` into a shell command, and never write anywhere other than a literal `OUTPUT_PATH` you were given.

### Step 2: Dispatch the `charter-generator` agent

Dispatch the agent named `charter-generator` (`agents/charter-generator.md`) via the platform's agent-dispatch tool. Pass it:

- `target=<TARGET>` — the required target to charter.
- `risk context=<RISK_CONTEXT>` — only when `--risk` was supplied; omit otherwise.

The agent has its own read-only codebase access (it may read and search source, tests, and past bug reports) and will sharpen charters against real structure when the target names or points at code; it works from the description alone when no code is available. It runs no Q&A loop — target in, ranked charters out. Do NOT re-implement the charter doctrine here or hand-author charters yourself; the agent and the `chartering` skill own that.

### Step 3: Parse the agent's JSON output

The agent returns a **single fenced ```json document** and nothing else. Extract the first ```json fence and parse it. The parsed object has these root keys (contract owned by `agents/charter-generator.md`):

- `target` (string) — the target as the agent interpreted it.
- `charters` (array, ranked highest-risk-first, never empty) — each charter object has `rank`, `charter`, `target`, optional `resources`, `information`, `risk`, `source` (one of `requirements`, `implicit-expectation`, `stakeholder-question`, `artifact`, `nightmare-headline`, `sfdpot`), optional `lens` (only when `source: sfdpot`), and `time_box` (≤2h).
- `coverage_notes` (optional string) — angles the agent deliberately skipped, splits it made, or assumptions it charted under.

If no ```json fence is present or it does not parse, do not fabricate charters — report that the agent returned no parseable charters and stop.

### Step 4: Render the ranked charter list

Present the charters to the conversation as a numbered list ordered by `rank` (1 = highest risk). For each charter show, at minimum:

- the `rank`,
- the full `charter` sentence,
- the `risk` (why it matters / why it ranks where it does),
- the `source` (and `lens` when `source: sfdpot`),
- the `time_box`.

Print `coverage_notes` below the list when present. Keep every rendered example generic — no real credentials, customer data, or internal host/system names (the agent already enforces this; do not reintroduce specifics when summarizing). Frame any security-focused charter as a mission to test *your own system under authorization*, never a plan to attack a third party.

### Step 5: Optionally write the charters to a file (only when `--output` is set)

If `OUTPUT_PATH` is set, write the rendered ranked charter list as a markdown document to that path. First ensure the parent directory exists via a scoped shell command:

```shell
mkdir -p "$(dirname "$OUTPUT_PATH")"
```

Then use the platform's file-write tool to write a markdown document whose heading names the target and whose body is the same ranked list from Step 4 (one section or table row per charter). Do NOT overwrite a path the user did not name, and never write anywhere other than `OUTPUT_PATH`. When `--output` is absent, skip this step entirely — the conversation rendering is the deliverable.

### Step 6: Finish

State that the charters are ready and, when a file was written, name the path. Point the user at the natural next step — pick a charter and run it by activating the `stride-exploratory-testing-explore` skill, or brainstorm more risk-driven charters by activating the `stride-exploratory-testing-nightmare-headline` skill. Do NOT auto-run a session, do NOT execute a charter, and do NOT chain into another skill.

## What this skill does NOT do

- Run an exploratory session or execute any charter — that is the `stride-exploratory-testing-explore` skill.
- Generate probes or judge findings — those are the `heuristics` and `oracles` skills.
- Modify any file other than the optional `--output` document.
