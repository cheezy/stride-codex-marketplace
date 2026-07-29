# Stride Ideation for Codex CLI

Turn an idea into shipped Stride tasks — from Codex CLI.

This plugin provides brainstorming and ideation skills for projects that use [Stride](https://www.stridelikeaboss.com). It is the Codex CLI port of [`cheezy/stride-ideation`](https://github.com/cheezy/stride-ideation) (Claude Code). Activate the `stride-ideation-ideate` skill to drive an interactive ideation session that produces a committed requirements markdown document. Stop there if you just want a written spec — or activate the `stride-ideation-stridify` skill to decompose the requirements into a Stride batch JSON, commit it for audit, and POST it to the Stride API in a single invocation.

## Overview

The two user-facing skills:

```text
stride-ideation-ideate [<topic>] [--continue <path>] [--profile <name>]
  Interactive ideation session. Drives a Q&A loop with you to produce a
  timestamped requirements markdown doc. Stop here if you only want a spec.

stride-ideation-stridify <path-to-requirements.md> [--goal <name|index>]
  End-to-end pipeline: validates the requirements doc, preflights auth,
  dispatches the decomposer agent, stamps audit metadata, writes and
  commits a sibling Stride batch JSON, then POSTs it to /api/tasks/batch
  on your Stride instance and renders the created G/W identifiers.
  --goal scopes the dispatch to one surface from the doc's
  ## Decomposition seams section (see the upstream "Resilience model" below).
```

The first skill is hard-gated on seven required sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success metrics) plus shape requirements on Assumptions (ranked, riskiest marked, premortem-derived) and Success metrics (both leading and lagging indicators). The second skill is gated on a passing structural validation of the decomposer's output before it commits or POSTs anything.

## Installation

Codex CLI discovers skills in `.agents/skills/` (or `.codex/skills/`) and agents in `.agents/agents/` automatically. Drop the skills and agents from this repo into either location.

### One-liner (recommended)

Install globally so the skills and agents are available in all projects:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.sh | bash
```

Or install into the current project only:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.sh | bash -s -- --project
```

### Windows (PowerShell)

Requires PowerShell 5.1+ or PowerShell Core 7+ and Git for Windows on `PATH`.

```powershell
irm https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.ps1 | iex
```

Or project-local:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.ps1))) -Project
```

### Your existing `AGENTS.md` is preserved

The installer never overwrites a user-authored `AGENTS.md`. Its guidance is
confined to a clearly delimited **managed block** (`<!-- BEGIN stride-ideation -->`
… `<!-- END stride-ideation -->`):

- **No `AGENTS.md` yet** — the file is created containing the managed block.
- **You already have an `AGENTS.md`** — all of your content is kept; the managed
  block is appended, or refreshed in place if already present.
- **Re-running the installer is idempotent** — it updates only the managed block
  and never duplicates the guidance. Keep your own notes *outside* the markers;
  anything between them is regenerated on each install.

`install.sh` and `install.ps1` behave identically.

### Manual installation

```bash
git clone https://github.com/cheezy/stride-codex-ideation.git

# Copy skills, agents, and helpers into the location Codex auto-discovers
cp -r stride-codex-ideation/skills/ .agents/skills/
cp -r stride-codex-ideation/agents/ .agents/agents/
cp stride-codex-ideation/AGENTS.md AGENTS.md

# The lib/ helpers and fixtures/ stay alongside the skills — the
# stridify skill resolves them via <plugin-root>/lib/.
```

On Windows, use `Copy-Item -Recurse` for the equivalent.

### Auth file

The `stride-ideation-stridify` skill reads `.stride_auth.md` in the project root to obtain `STRIDE_API_URL` and `STRIDE_API_TOKEN`. Create it once per project:

```markdown
- **API URL:** `https://www.stridelikeaboss.com`
- **API Token:** `stride_dev_abc123...`
```

Add `.stride_auth.md` to your project's `.gitignore` — it contains a secret. The bundled `.gitignore` template already excludes it.

## Usage

### `stride-ideation-ideate` — drive a session, produce a requirements doc

Activate the skill in chat with an inline topic or with the topic via the platform's question UI:

```
> Activate stride-ideation-ideate with "Add notifications system"
```

The skill drives a round-based question loop (≤ 4 questions per round) and gates the seven required sections before writing. The terminal state is a committed `docs/ideation/<timestamp>-<slug>-requirements.md` file. Profiles are selected via `--profile lean|product|discovery|lean-startup`; the default `lean` runs the shared core only — the seven gated sections plus the mandatory framing checkpoint, premortem, and challenge gate — with no profile-specific forcing questions or optional document sections.

```
> Activate stride-ideation-ideate with "--profile=product Review queue UX"
> Activate stride-ideation-ideate with "--continue docs/ideation/2026-05-12T120000-foo-requirements.md"
```

#### Session experience

The `stride-ideation-ideate` session is guided, recoverable, and human-in-control. Before every round a display-only recap shows each of the seven gated sections as `solid` / `thin` / `empty`; every gated-section question carries an "I'm not sure — propose candidates" option; and the in-progress draft is autosaved to a gitignored scratch file under `.stride/` so an interruption is recoverable. Two mandatory, profile-independent checkpoints stress-test the design before the doc is written:

- **Round-4 premortem** — inverts the framing to surface the *single* most likely failure mode, folded back into Assumptions as the riskiest entry.
- **Challenge gate** — runs after the premortem (and the Round-5 MVP-design batch under `lean-startup`) and **before** the reviewer pass. It stress-tests the design via four components: an assumption-confidence audit (rate every assumption `high` / `medium` / `low`), a blind-spot scan, two distinct alternative approaches, and a cost / risk / complexity / timeline trade-off comparison. The gate is surfaced as a single multi-select decision through Codex CLI's question UI with an explicit **"Challenge nothing — write as-is"** choice. It is **advisory and never blocks the write**, and runs identically under every profile. Confidence ratings fold into the Assumptions entries in place; the blind spots, the two alternatives, and the trade-off comparison fold into a new optional **Design challenge** section (not one of the seven gated sections).

After the gate, the advisory `requirements-reviewer` pass surfaces any findings as a multi-select decision (with an "Address none — write as-is" choice) that feeds at most one refinement round; like the gate, it never blocks the write.

### `stride-ideation-stridify` — decompose + POST to Stride

After ideating (or against any compatible requirements doc), activate the second skill against the requirements path:

```
> Activate stride-ideation-stridify with docs/ideation/2026-05-12T120000-foo-requirements.md
```

The skill validates the seven required sections, preflights auth from `.stride_auth.md`, dispatches the `requirements-decomposer` agent (with a bounded 3-attempt retry on transient failures), stamps `source_spec` + `source_spec_sha256` at the JSON root, writes a sibling `*-stride-batch.json` to disk, commits it, then POSTs to `/api/tasks/batch` and renders the created G/W identifier table.

When the requirements doc has many surfaces (`## Decomposition seams` with > 3 items), partition with `--goal`:

```
> Activate stride-ideation-stridify with <path> --goal kanban-app
> Activate stride-ideation-stridify with <path> --goal 2
```

Each `--goal` run produces a sibling batch JSON named `<source-slug>-<goal-slug>-stride-batch.json`.

## How this plugin relates to `stride-codex`

[`stride-codex`](https://github.com/cheezy/stride-codex) and `stride-codex-ideation` are sibling plugins with different scopes:

- **`stride-codex`** handles the **task lifecycle** — claiming a task from a backlog, decomposing goals, executing the five-stage hook workflow (`before_doing` / `after_doing` / `before_review` / `after_review` / `after_goal`), and completing tasks back to the Stride API.
- **`stride-codex-ideation`** (this plugin) handles **ideation** — turning a fuzzy idea into a requirements doc, decomposing that doc into a Stride batch, and seeding the Stride backlog.

A typical full-loop usage installs both:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex/main/install.sh | bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.sh | bash
```

Then: activate `stride-ideation-ideate` to scope the work, activate `stride-ideation-stridify` to seed the backlog, then activate `stride-workflow` (from `stride-codex`) to claim and ship the resulting tasks.

## How this plugin relates to upstream `stride-ideation`

This plugin is a faithful port of [`cheezy/stride-ideation`](https://github.com/cheezy/stride-ideation) to Codex CLI. The protocol — round-based question batching, hard-gated sections, advisory reviewer pass, decomposer dispatch with bounded retry, retry-exhaustion fallback, source_spec stamping, validator-before-commit, never-retry-POST — is preserved verbatim. The differences are mechanical adaptations:

| Upstream (Claude Code) | This plugin (Codex CLI) |
|---|---|
| Two slash commands (`/stride-ideation:ideate`, `/stride-ideation:stridify`) | Two named skills (`stride-ideation-ideate`, `stride-ideation-stridify`) — Codex CLI has no slash-command mechanism |
| `commands/*.md` directory | `skills/<name>/SKILL.md` directories |
| `agents/*.md` agent files | `agents/*.md` agent files (same bare-`.md` convention) |
| `AskUserQuestion` tool name | "interactive question batch" — a single chat turn asking the user up to four related questions |
| `Bash`, `Read`, `Write`, `Skill`, `Agent` tool names | Codex equivalents (`shell`, `read`, `write`, plus the skill-activation contract documented in `AGENTS.md`) |
| `lib/filename.sh` only | `lib/filename.sh` + `lib/filename.ps1` mirror for Windows users |
| `lib/test-*.sh` only | `lib/test-*.sh` + `lib/test-*.ps1` mirrors for Windows users |

The fixtures, the decomposer agent prompt, the reviewer agent rubric, and the lib/ helpers' Python scripts are byte-identical to upstream.

## Re-running the interactive end-to-end test

To verify the plugin works against your Codex CLI install:

1. Activate `stride-ideation-ideate` with a small topic (e.g. "Add a dark-mode toggle"). Walk through the Q&A loop. Confirm a `docs/ideation/<timestamp>-dark-mode-toggle-requirements.md` is committed.
2. Activate `stride-ideation-stridify` against that committed path. Confirm a sibling `*-stride-batch.json` is committed and the G/W identifier table is rendered. (Use a non-prod Stride workspace — the POST creates real tasks.)
3. Run the smoke test suite: `bash lib/run_smoke_test.sh` (or `pwsh -File lib\run_smoke_test.ps1` on Windows). All stages should pass.

## License

MIT. See [LICENSE](./LICENSE).
