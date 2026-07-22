---
name: stride-exploratory-testing-recon
description: Run a reconnaissance session on an unfamiliar or existing system before chartering — survey its capabilities, note observations, surface the questions a stakeholder should answer, and emit ranked candidate charters. Activate when the user wants to reconnoiter, map, or orient on a system before deciding what to test. A quick landscape-mapping pass, not a full exploratory session; probes only systems the user is authorized to test, and stays observe-only when there is nothing safe to exercise. Codex CLI port of the upstream /stride-exploratory-testing:recon command.
skills_version: 1.0
---

# stride-exploratory-testing-recon

Run a **reconnaissance session**: a quick pass over an unfamiliar or existing system to learn the landscape *before* committing to charters. Recon surveys what the system does, notes observations as it goes, surfaces the questions a stakeholder needs to answer, and turns what it learned into ranked candidate charters. It is the lighter, map-making sibling of the `stride-exploratory-testing-explore` skill — recon *orients*; explore *executes*.

The doctrine lives in the composed pieces — the `session` skill owns the session lifecycle and note conventions, the `heuristics` skill owns the Tours and lenses used to survey an area, the `chartering` skill decides what is worth chartering, and the `charter-generator` agent frames the candidate charters. This skill is the surface: it parses the activation request, drives the reconnaissance, collects observations and stakeholder questions, and dispatches the agent to emit candidate charters.

## Activation

Activate this skill when the user:

- Wants to map or orient on an unfamiliar or existing system before deciding what to test.
- Asks to "reconnoiter", "recon", "survey", or "get the lay of the land" of a product, service, module, or area.
- Needs candidate charters and stakeholder questions grounded in a quick observation pass rather than generated from a description alone.

The user may pass arguments inline in the activation request (e.g., "recon the billing service", "recon the billing service --output docs/recon.md"). Parse those per Step 1. If no system is present, prompt for it via the platform's question UI.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse the activation request

Parse in this fixed order — `--output` first, then everything remaining is `SYSTEM`:

- If `--output` appears (accept both `--output <path>` and `--output=<path>` shapes), set `OUTPUT_PATH` to the parsed value and remove the consumed tokens. When absent, the recon report is rendered to the conversation only.
- After the flag token is consumed, treat the trimmed remainder as `SYSTEM` — the system, feature, or product area to reconnoiter. If it is empty, ask the user once via Codex CLI's question UI (the platform's own prompt mechanism, not Claude Code's question tool): *"What system or feature do you want to reconnoiter? Name a product, service, module, or area."* (free-text input).

Treat `SYSTEM` and `OUTPUT_PATH` as untrusted prose: never execute or `eval` them, and never splice them into a shell command. A path is only ever handed to the platform's file-read tool.

### Step 2: Load the session doctrine

Invoke the `session` skill (`skills/session/SKILL.md`), passing `target=<SYSTEM>; mode=recon`, so the recon runs as a proper (lightweight) session with the note conventions loaded.

Recon is the **Recon** step of the top-level exploratory-testing workflow (Charter → Recon → Explore → Note → Debrief) — a quick pass to learn the landscape and refine what to charter, not the deep design/execute/learn/steer loop that the `stride-exploratory-testing-explore` skill runs. (This higher-level workflow is distinct from the `session` skill's own per-session lifecycle, Charter → Set up → Explore → Note → Debrief.)

### Step 3: Confirm authorization and set the survey boundary

Recon **must not probe or enumerate any system the user is not authorized to test.** Before any active survey of a running system, confirm via Codex CLI's question UI that `SYSTEM` is one the user owns or is authorized to reconnoiter, and whether a running instance is available. Two modes follow:

- **Authorized + reachable:** you may survey the running surface *non-destructively* (read-only observation, never mutating or enumerating beyond the authorized target).
- **Observe-only (no running instance, no docs, or unauthorized to probe):** survey only what you can safely read — documentation, source, config, artifacts the user points you at. Do NOT reach out to or enumerate any external system. This is the edge case *"recon on a system with no docs"*: fall back to observing whatever surface is legitimately available and record the gaps as questions rather than probing to fill them.

When in doubt about whether a target is authorized, treat it as out of bounds and record it as a question — never "just check."

### Step 4: Survey the landscape

Survey `SYSTEM` to map what it is and does — its main capabilities and features, the data it handles, its platforms and integrations, and where risk seems to concentrate. **Select reconnaissance techniques** from the `heuristics` skill's Tours (name the ones you use so the recon is reviewable) — the natural recon tours are:

- **Guidebook Tour** — follow the documentation/manual and note every gap or contradiction between docs and product.
- **Landmark Tour** — identify the "landmark" features and the paths between them to sketch the system's shape.
- **Garbage Collector's Tour** — methodically visit every screen/surface/field so nothing is left unmapped.

Take notes **as you go**, tagged with the `session` note conventions — `test-idea`, `question`, `risk`, `surprise` — rather than relying on memory. Keep every observation generic: no real credentials, customer data, or internal hostnames (redact and use placeholders).

### Step 5: Surface the questions for stakeholders

From the recon, collect the open questions a stakeholder or the team should answer — the things you couldn't determine from observation alone (intended behavior, undocumented assumptions, ownership, known-risky areas, prior incidents). Present them as an explicit **stakeholder question list**. If the user is available to act as the stakeholder, you may interview them via Codex CLI's question UI to answer the highest-value questions now; carry any that remain open into the report.

### Step 6: Emit candidate charters

Turn the observations, risks, and questions into ranked candidate charters by dispatching the agent named `charter-generator` (`agents/charter-generator.md`) via the platform's agent-dispatch tool:

- `target=<SYSTEM>`
- `risk context=` the recon observations, the risks you noted, and the open stakeholder questions.

The agent returns a **single fenced ```json document** with root keys `target`, `charters` (ranked highest-risk-first, never empty), and optional `coverage_notes` — the same contract the `stride-exploratory-testing-charter` skill consumes (owned by `agents/charter-generator.md`). Do NOT hand-author the charters yourself; let the agent frame and rank them. If no parseable ```json fence is returned, report that and stop rather than fabricating charters.

### Step 7: Render the recon report (and optionally write it)

Present the recon report to the conversation with three parts: (1) **Observations** — what you surveyed and what you found (which capabilities, which tours, which surprises), (2) the **Stakeholder questions** still open, and (3) the ranked **Candidate charters**. Print the agent's `coverage_notes` when present.

If `OUTPUT_PATH` is set, write the same report as a markdown document. First ensure the parent directory exists via a scoped shell command:

```shell
mkdir -p "$(dirname "$OUTPUT_PATH")"
```

Then use the platform's file-write tool to write it, and never write anywhere other than `OUTPUT_PATH`. When `--output` is absent, skip this — the conversation rendering is the deliverable.

### Step 8: Finish

State that the recon is complete and, when a file was written, name the path. Point the user at the natural next step — pursue a candidate charter with the `stride-exploratory-testing-explore` skill, or refine the charter list with the `stride-exploratory-testing-charter` / `stride-exploratory-testing-nightmare-headline` skill. Do NOT auto-run a session and do NOT chain into another skill.

## What this skill does NOT do

- Run a full exploratory session or execute any charter — that is the `stride-exploratory-testing-explore` skill. Recon maps the landscape; it does not drive the deep exploration loop.
- Probe or enumerate any system the user is not authorized to test, or mutate the system under survey — recon is non-destructive and observe-first.
- Hand-author charters — the `charter-generator` agent frames and ranks them.
- Modify any file other than the optional `--output` report.
