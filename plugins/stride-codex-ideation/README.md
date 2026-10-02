# Stride Ideation for Codex CLI

Turn an idea into shipped Stride tasks — from Codex CLI.

This plugin provides brainstorming and ideation skills for projects that use [Stride](https://www.stridelikeaboss.com). It is the Codex CLI port of [`cheezy/stride-ideation`](https://github.com/cheezy/stride-ideation) (Claude Code). Activate the `stride-ideation-ideate` skill to drive an interactive ideation session that produces a committed requirements markdown document. Stop there if you just want a written spec — or activate the `stride-ideation-stridify` skill to decompose the requirements into a Stride batch JSON, commit it for audit, and POST it to the Stride API in a single invocation.

## Overview

The two user-facing skills:

```text
stride-ideation-ideate [<topic>] [--continue <path>] [--input <path>] [--profile <name>]
  (each flag also takes the --flag=<value> form)
  Interactive ideation session. Drives a Q&A loop with you to produce a
  timestamped requirements markdown doc. Stop here if you only want a spec.

stride-ideation-stridify <path-to-requirements.md> [--goal <name|index>] [--yes]
stride-ideation-stridify --batch <path-to-stride-batch.json> [--yes]
  End-to-end pipeline: validates the requirements doc, preflights auth,
  dispatches the decomposer agent, stamps audit metadata, writes and
  commits a sibling Stride batch JSON, then POSTs it to /api/tasks/batch
  on your Stride instance and renders the created G/W identifiers.
  Before anything is sent it previews the goals and tasks and asks for
  your approval; --yes (alias --auto-approve) skips that question.
  --batch ships a batch JSON already on disk without decomposing again.
  --goal scopes the dispatch to one surface from the doc's
  ## Decomposition seams section (see the upstream "Resilience model" below).
```

The first skill is hard-gated on seven required sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success metrics) plus shape requirements on Assumptions (ranked, riskiest marked, premortem-derived) and Success metrics (both leading and lagging indicators). The second skill is gated on a passing structural validation of the decomposer's output before it commits or POSTs anything.

## Installation

Codex CLI discovers skills in `.agents/skills/` (or `.codex/skills/`). The agents are not discovered by Codex: the skills read the agent files from this plugin's helper root (see **Where the files go**) and run each one as a Codex sub-agent, or inline as a read-only pass when sub-agents are unavailable. Use the installer below; it puts every file where the skills look for it.

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

Requires PowerShell 5.1+ or PowerShell 7+ and Git on `PATH`. `install.ps1` also runs under PowerShell 7 on macOS and Linux, where it installs into `~/.agents/` just as `install.sh` does.

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

- **Markers count only as whole lines.** A marker quoted inside a line of your
  prose is ignored, and an orphaned or out-of-order marker (a `BEGIN` with no
  `END`, an `END` before any `BEGIN`) never causes any of your text to be
  replaced — the block is appended instead, and later runs refresh that block.
  A marker line ending in CRLF still counts, so a block checked out with Windows
  line endings is refreshed, not duplicated.
- **Your bytes are kept as they are** — whatever encoding your `AGENTS.md` uses
  (UTF-8 with or without a BOM, or a legacy code page), only the managed block
  changes.
- **A symlinked `AGENTS.md` is refused**, never written through, so a project
  cannot redirect the installer into another file.

`install.sh` and `install.ps1` install the same layout and write byte-identical `AGENTS.md` files for the same input (`lib/test-install.sh` and `lib/test-install.ps1` check this offline). They differ where the platforms do: the flags are `--project` / `--help` for `install.sh` and `-Project` / `-Help` for `install.ps1`; `install.ps1` resolves the home directory from `USERPROFILE`, then `HOME`; and its link checks also refuse Windows junctions and other reparse points.

### Where the files go

```
<install-dir>/                    ~/.agents/ (global) or ./.agents/ (--project)
├── skills/<skill>/SKILL.md       where Codex discovers skills
├── agents/<agent>.md             a copy of the agents (the skills use the helper root's)
└── stride-codex-ideation/        this plugin's helper root
    ├── lib/                      helper scripts the skills run
    ├── agents/                   the agent files the skills dispatch
    └── fixtures/                 calibration fixtures for the smoke test
```

The skills find the helper root themselves, tied to where Codex loaded them from: `$STRIDE_IDEATION_HOME` if you set it, else the `stride-codex-ideation/` directory of the `.agents/` install the skill was loaded from (the project install or the global one, whichever Codex used), else the plugin directory of a marketplace install. A repository's own `.agents/stride-codex-ideation/` is never picked up just because it exists — the helpers are executed, so they come only from an install Codex already loaded. If nothing qualifies, the skill stops and names every path it tried. Set `STRIDE_IDEATION_HOME` to a checkout of this repository to run the skills against it directly.

The helper root is this plugin's own directory, so no other tool installing into the same `.agents/` can overwrite its helpers. Each install clears and rewrites it, so files a newer release no longer ships disappear; nothing outside it is ever deleted. The installer prints the resolved helper root at the end. Releases before this layout copied the helpers into the shared `<install-dir>/lib/` and `<install-dir>/fixtures/`; the installer points those out when it finds them but never deletes them, since other tools may use the same directories.

### Manual installation

```bash
git clone https://github.com/cheezy/stride-codex-ideation.git

# Skills go where Codex discovers them.
mkdir -p .agents/skills .agents/stride-codex-ideation
cp -R stride-codex-ideation/skills/. .agents/skills/

# The helpers, fixtures and agents go in the plugin's own helper root,
# where the skills look them up.
cp -R stride-codex-ideation/lib stride-codex-ideation/fixtures stride-codex-ideation/agents .agents/stride-codex-ideation/
```

Do not copy this repository's `AGENTS.md` over your own. Paste its contents into your project's `AGENTS.md` between a `<!-- BEGIN stride-ideation -->` line and a `<!-- END stride-ideation -->` line (create the file if you have none), which is the managed block the installer would write. To get the installer's exact behavior from a local checkout instead — managed block, helper-root refresh and link checks included — run `INSTALL_SOURCE_DIR=./stride-codex-ideation bash stride-codex-ideation/install.sh --project` from the project root.

On Windows, use `Copy-Item -Recurse` for the equivalent copies, or run `install.ps1 -Project` with `INSTALL_SOURCE_DIR` set.

### Auth file

The `stride-ideation-stridify` skill reads `.stride_auth.md` in the project root to obtain `STRIDE_API_URL` and `STRIDE_API_TOKEN`. Create it once per project:

```markdown
- **API URL:** `https://www.stridelikeaboss.com`
- **API Token:** `stride_dev_abc123...`
```

Add `.stride_auth.md` to your project's `.gitignore` — it contains a secret. The bundled `.gitignore` template already excludes it.

## Usage

### `stride-ideation-ideate` — drive a session, produce a requirements doc

Activate the skill in chat with an inline topic, or without one and answer the topic question it asks:

```
> Activate stride-ideation-ideate with "Add notifications system"
```

The skill drives a round-based question loop (≤ 4 questions per round) and gates the seven required sections before writing. The terminal state is a committed `docs/ideation/<timestamp>-<slug>-requirements.md` file. Profiles are selected via `--profile lean|product|discovery|lean-startup`; the default `lean` runs the shared core only — the seven gated sections, the round recap, the uncertainty path, the mandatory framing checkpoint, premortem and challenge gate, the reviewer pass and draft autosave — with no profile-specific forcing questions or optional document sections. Without `--profile` the skill first recommends one. `--input <path>` seeds the draft from a freeform notes file (read only, never committed), and `--continue <path>` refines a prior requirements doc into a new sibling file.

Every question the skills ask — the round questions, the recommendation, the slug confirmation, the draft-resume choice, the challenge gate and the reviewer decision — is plain text in one chat turn with numbered options: answer with a number, or with several numbers for a multi-select question.

```
> Activate stride-ideation-ideate with "--profile=product Review queue UX"
> Activate stride-ideation-ideate with "--continue docs/ideation/2026-05-12T120000-foo-requirements.md"
> Activate stride-ideation-ideate with "--input notes/slack-thread.md Digest emails"
```

#### Session experience

The `stride-ideation-ideate` session is guided, recoverable, and human-in-control. Before every round a display-only recap shows each of the seven gated sections as `solid` / `thin` / `empty`; every gated-section question carries an "I'm not sure — propose candidates" option; and the in-progress draft is autosaved to a gitignored scratch file under `.stride/` so an interruption is recoverable. Two mandatory, profile-independent checkpoints stress-test the design before the doc is written:

- **Round-4 premortem** — inverts the framing to surface the *single* most likely failure mode, folded back into Assumptions as the riskiest entry.
- **Challenge gate** — runs after the premortem (and the Round-5 MVP-design batch under `lean-startup`) and **before** the reviewer pass. It stress-tests the design via four components: an assumption-confidence audit (rate every assumption `high` / `medium` / `low`), a blind-spot scan, two distinct alternative approaches, and a cost / risk / complexity / timeline trade-off comparison. The gate is surfaced as a single numbered multi-select question with an explicit **"Challenge nothing — write as-is"** choice. It is **advisory and never blocks the write**, and runs identically under every profile. Confidence ratings fold into the Assumptions entries in place; the blind spots, the two alternatives, and the trade-off comparison fold into a new optional **Design challenge** section (not one of the seven gated sections).

After the gate, the advisory `requirements-reviewer` pass surfaces any findings as a numbered multi-select question (with an "Address none — write as-is" choice) that feeds at most one refinement round; like the gate, it never blocks the write.

### `stride-ideation-stridify` — decompose + POST to Stride

After ideating (or against any compatible requirements doc), activate the second skill against the requirements path:

```
> Activate stride-ideation-stridify with docs/ideation/2026-05-12T120000-foo-requirements.md
```

The skill validates the seven required sections, preflights auth from `.stride_auth.md`, dispatches the `requirements-decomposer` agent (with a bounded 3-attempt retry on transient failures), stamps `source_spec` + `source_spec_sha256` at the JSON root, writes a sibling `*-stride-batch.json` to disk, commits it, previews the goals and tasks and asks for your approval (skip the question with `--yes`, alias `--auto-approve`), then POSTs to `/api/tasks/batch` and renders the created G/W identifier table. Declining leaves the committed batch on disk to ship later with `--batch`.

When the requirements doc has many surfaces (`## Decomposition seams` with > 3 items), partition with `--goal`:

```
> Activate stride-ideation-stridify with <path> --goal kanban-app
> Activate stride-ideation-stridify with <path> --goal 2
```

Each `--goal` run produces a sibling batch JSON named `<source-slug>-<goal-slug>-stride-batch.json`.

To ship a batch JSON that is already on disk — one you declined at the approval gate, one a failed POST left behind, or one saved from a retry-exhaustion recovery — use `--batch` instead of a requirements path:

```
> Activate stride-ideation-stridify with --batch docs/ideation/2026-05-12T120000-foo-stride-batch.json
```

`--batch` validates the file, refuses it if it contains your API token, previews the goals and tasks, asks for approval (unless `--yes`), and ships it. It never re-runs the decomposer, never rewrites the file, and creates no commit. It cannot be combined with `--goal`. Shipping a batch that was already shipped creates every goal and task a second time, so check the Backlog column first.

Every POST goes through `lib/ship.py`, one Python script that bash and PowerShell hosts both call (`python3`, or `python` / `py -3` on Windows). It reads `.stride_auth.md`, strips the local audit fields, validates the exact payload, and POSTs with curl — the token on curl's stdin, never on a command line, in a file or in a log — then renders the created identifiers. It never retries the POST.

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

This plugin is a port of [`cheezy/stride-ideation`](https://github.com/cheezy/stride-ideation) to Codex CLI. The protocol — round-based question batching, hard-gated sections, advisory reviewer pass, decomposer dispatch with bounded retry, retry-exhaustion fallback, source_spec stamping, validator-before-commit, never-retry-POST — is the same; the wording and the helpers are adapted to Codex CLI. The main differences:

| Upstream (Claude Code) | This plugin (Codex CLI) |
|---|---|
| Two slash commands (`/stride-ideation:ideate`, `/stride-ideation:stridify`) | Two named skills (`stride-ideation-ideate`, `stride-ideation-stridify`) — Codex CLI has no slash-command mechanism |
| `commands/*.md` directory | `skills/<name>/SKILL.md` directories |
| `agents/*.md` agent files | `agents/*.md` agent files (same bare-`.md` convention) |
| `AskUserQuestion` tool | Plain chat: each question has numbered options, answered by number (several numbers for a multi-select question); a round asks up to four related questions in one chat turn |
| Agents dispatched by the `Agent` tool | The skills read `agents/*.md` from the plugin's helper root and run each as a Codex sub-agent, or inline as a read-only pass when sub-agents are unavailable |
| `Bash`, `Read`, `Write`, `Skill`, `Agent` tool names | Codex equivalents (`shell`, `read`, `write`, plus the skill-activation contract documented in `AGENTS.md`) |
| `lib/filename.sh` only | `lib/filename.sh` + `lib/filename.ps1` mirror for Windows users |
| `lib/test-*.sh` only | `lib/test-*.sh` + `lib/test-*.ps1` mirrors for Windows users: every bash case has a PowerShell counterpart of the same strength, except the inherently bash-only ones listed below, so PASS counts can differ: a twin may keep extra PowerShell-only cases, and it is short only by those bash-only cases. The inherently bash-only cases are `eval` of `read_auth.py` output, the executable-bit check, the terminal-stdin draft case, and running a skill's bash block, which the PowerShell twin replays as git commands. `lib/test-skill-blocks.sh` has no twin |
| `lib/ship.sh` (bash) | `lib/ship.py` — one Python script both bash and PowerShell hosts call |

The four calibration requirements docs in `fixtures/` are copied from upstream. The batch fixtures, the two agent prompts and the `lib/` helpers have diverged — Codex tool and skill names, the helper-root lookup, `lib/ship.py`, the scored-field backfill — so expect the same protocol, not identical bytes.

## Re-running the interactive end-to-end test

To verify the plugin works against your Codex CLI install:

1. Activate `stride-ideation-ideate` with a small topic (e.g. "Add a dark-mode toggle"). Walk through the Q&A loop. Confirm a `docs/ideation/<timestamp>-dark-mode-toggle-requirements.md` is committed.
2. Activate `stride-ideation-stridify` against that committed path. Confirm a sibling `*-stride-batch.json` is committed and the G/W identifier table is rendered. (Use a non-prod Stride workspace — the POST creates real tasks.)
3. Run the smoke test suite: `bash lib/run_smoke_test.sh` (or `pwsh -File lib\run_smoke_test.ps1` on Windows). All stages should pass.

## License

MIT. See [LICENSE](./LICENSE).
