# Stride for Codex CLI

Task lifecycle skills and custom agents for [Stride](https://www.stridelikeaboss.com) kanban — a task management platform designed for AI agents.

This is the Codex CLI version of the Stride plugin. It provides workflow enforcement through Codex's skill and subagent systems.

## Installation

### One-liner (recommended)

Install globally so skills and agents are available in all projects:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex/main/install.sh | bash
```

Or install into the current project only:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex/main/install.sh | bash -s -- --project
```

### Windows (PowerShell)

Requires PowerShell 5.1+ or PowerShell Core 7+ and Git for Windows on `PATH`.

Install globally so skills and agents are available in all projects:

```powershell
irm https://raw.githubusercontent.com/cheezy/stride-codex/main/install.ps1 | iex
```

Or install into the current project only (the scriptblock wrapper is required to pass `-Project` through `irm | iex`):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cheezy/stride-codex/main/install.ps1))) -Project
```

Download and run manually if you prefer:

```powershell
irm https://raw.githubusercontent.com/cheezy/stride-codex/main/install.ps1 -OutFile install.ps1
.\install.ps1            # global install
.\install.ps1 -Project   # project-local install
.\install.ps1 -Help      # print usage and exit
```

### Manual installation

```bash
git clone https://github.com/cheezy/stride-codex.git

# Copy skills, agents and the hook surface
cp -r stride-codex/skills/ .agents/skills/
cp -r stride-codex/agents/ .agents/agents/
cp stride-codex/AGENTS.md AGENTS.md

# The hook surface. Only the runtime files; the test script stays in the
# repo. -p preserves the executable bit on the scripts.
mkdir -p .agents/hooks
cp -p stride-codex/hooks/stride-hook.sh .agents/hooks/stride-hook.sh
cp -p stride-codex/hooks/stride-stop-gate.sh .agents/hooks/stride-stop-gate.sh
cp stride-codex/hooks/hooks.json .agents/hooks/hooks.json

# The Step 0 update check, and the version record it reads in a loose copy
cp -p stride-codex/hooks/check-plugin-current.sh .agents/hooks/check-plugin-current.sh
jq -r .version stride-codex/.codex-plugin/plugin.json > .agents/hooks/stride-codex.version
```

For Windows manual installation, use `Copy-Item`:

```powershell
git clone https://github.com/cheezy/stride-codex.git

# Copy skills, agents and the hook surface
Copy-Item -Recurse stride-codex\skills\* .agents\skills\
Copy-Item -Recurse stride-codex\agents\*.md .agents\agents\
Copy-Item stride-codex\AGENTS.md .\AGENTS.md

# The hook surface. Only the runtime files; the test script stays in the repo.
New-Item -ItemType Directory -Force -Path .agents\hooks | Out-Null
Copy-Item stride-codex\hooks\stride-hook.sh .agents\hooks\stride-hook.sh
Copy-Item stride-codex\hooks\stride-stop-gate.sh .agents\hooks\stride-stop-gate.sh
Copy-Item stride-codex\hooks\hooks.json .agents\hooks\hooks.json

# The Step 0 update check, and the version record it reads in a loose copy
Copy-Item stride-codex\hooks\check-plugin-current.sh .agents\hooks\check-plugin-current.sh
(Get-Content -Raw stride-codex\.codex-plugin\plugin.json | ConvertFrom-Json).version | Set-Content -NoNewline .agents\hooks\stride-codex.version
```

Codex CLI discovers skills in `.agents/skills/` or `.codex/skills/` and agents in `.agents/agents/` automatically. **Hooks are the exception — `.agents/hooks/` is not a scanned location.** A `.agents/` install is a loose tree, not a plugin bundle, so the copied `hooks/hooks.json` is not picked up on its own and the handler must be registered once by hand; see [The Stride hook surface](#the-stride-hook-surface).

### Staying current

Codex runs whichever copy of the skills and agents is installed, and the Stride server cannot tell one release from another, so a fix shipped after you installed does nothing until you update. Step 0 of `stride-workflow` checks once per session: `hooks/check-plugin-current.sh` compares the installed version with the one [stride-codex-marketplace](https://github.com/cheezy/stride-codex-marketplace) publishes and prints one line when yours is older. That line says how to update: `codex plugin update stride-codex` for a plugin install, or re-running the installer for an `.agents/` copy. It is advice, never a block. The script reads a plugin install's `.codex-plugin/plugin.json`, or for an `.agents/` copy the `hooks/stride-codex.version` record the installers write. With neither, or with no network, it stays silent. The fetch is anonymous, HTTPS only and capped at three seconds.

## Setup

Before using the skills, create two configuration files in your project root — and add one block to your `.gitignore`.

### 0. `.gitignore` entries (do this first)

```gitignore
.stride_auth.md      # your API token — never commit this
.stride/             # agent-local state: the task base ref and the claim-time dirty baseline
.exploratory/        # exploratory-testing session artifacts, when that plugin is installed
```

`.exploratory/` is where exploratory-testing session artifacts land when that plugin is installed — they hold transcribed application output and arrive **untracked**, so a `## after_doing` section that stages everything (`git add -A`) would commit them, exactly as it would `.stride/`. (`git commit -a` does not sweep untracked files; `git add -A` and `git add .` do.)

**Add these before your first session.** `.gitignore` is inert for a path git already tracks — that needs `git rm --cached` — so doing it afterwards is the difference between the line working and doing nothing. `.exploratory/` is only the default location: a command-skill's `--output` can redirect one document elsewhere, and a redirected path needs its own entry.

### 1. `.stride_auth.md` (required, never commit)

```markdown
- **API URL:** `https://www.stridelikeaboss.com`
- **API Token:** `stride_dev_your_token_here`
- **User Email:** `your-email@example.com`
```

Add `.stride_auth.md` to your `.gitignore` — it contains secrets.

### 2. `.stride.md` (required, version controlled)

Define hook commands that run at each lifecycle point:

```markdown
## before_doing

` ` `bash
git pull origin main
mix deps.get
mix ecto.migrate
` ` `

## after_doing

` ` `bash
mix test --cover
mix format --check-formatted
mix credo --strict
` ` `

## before_review

` ` `bash
git fetch origin
git rebase origin/main
mix test
` ` `

## after_review

` ` `bash
git push origin main
` ` `

## after_goal

` ` `bash
# Optional fifth hook — fires after the parent goal's final child task
# completes. Omit entirely for the back-compat no-op path.
./scripts/notify-team.sh "$GOAL_IDENTIFIER" "$GOAL_TITLE"
` ` `
```

**`after_goal` (v1.11.0+):** the Stride server bundles an `after_goal` entry in the `hooks` array of the response of `/complete` or `/mark_reviewed` when the completing task is the final child of a parent goal. Codex CLI's plugin hook script never executes a `.stride.md` section, so the agent remains responsible for the entire after_goal lifecycle: detect the entry by reading the **canonical capture file** (below) rather than truncatable context, read `## after_goal` from `.stride.md`, export `GOAL_ID` / `GOAL_IDENTIFIER` / `GOAL_TITLE` / `GOAL_DESCRIPTION` from the entry's `hook.env` block, execute the section's commands via shell, capture `{exit_code, output, duration_ms}`, and POST the result to `PATCH /api/tasks/:goal_id/after_goal` to flip the goal to Done. A missing `## after_goal` section is a clean no-op (back-compat — the server's grace-window worker covers the goal transition, flipping only the goal's status; it never runs `## after_goal` or performs any push). The hook is general-purpose — Slack notifications, artifact archival, release pipelines, project-level smoke tests are all valid uses.

**Truncation-proof detection (v1.23.0+):** the `/complete` and `/mark_reviewed` curls capture the full response to `.stride/.last-api-response.json` under the project root — `CODEX_PROJECT_DIR`, then `CLAUDE_PROJECT_DIR`, then the nearest `.stride.md` above, made absolute, the same root for the curl and the detect step whichever directory each runs from (D411) — (via `tee`; there is **no** `curl --output` fallback as of 1.38.0 — the `PreToolUse` guard refuses it, because taking the response off stdout is what loses the loop-state record), and the detect step reads the after_goal entry and `GOAL_*` env from that file with `jq` — not from the agent's truncatable context. If the file is absent, empty, or invalid JSON, a fresh, self-contained `GET /api/tasks/:id/after_goal_status` re-confirms whether after_goal is armed, sourcing the URL/token durably from `.stride_auth.md` and `TASK_ID` from the captured file rather than a prior turn's export. The two detection paths are mutually exclusive, so `## after_goal` runs at most once. The `.stride/` directory holds this agent-local state and must be gitignored. See `stride-workflow` SKILL.md Step 7+9 for the full procedure.

## Mandatory Skill Chain

Every Stride skill is **mandatory** — not optional. Each skill contains required API fields, hook execution patterns, and validation rules that are only documented in that skill. Attempting to call Stride API endpoints without the corresponding skill results in API rejections.

### Workflow Order

**Recommended:** Use the single orchestrator skill for the complete lifecycle:

```
stride-workflow                  ← Activate ONCE — handles claim → explore → implement → review → complete
```

**Standalone mode** (when you need individual skills):

```
stride-claiming-tasks            ← BEFORE calling GET /api/tasks/next or POST /api/tasks/claim
    ↓
stride-subagent-workflow         ← AFTER claim succeeds, BEFORE implementation
    ↓
[implementation]
    ↓
stride-completing-tasks          ← BEFORE calling PATCH /api/tasks/:id/complete
```

When creating tasks or goals:

```
stride-creating-tasks            ← BEFORE calling POST /api/tasks (work/defect)
stride-creating-goals            ← BEFORE calling POST /api/tasks/batch (goals)
stride-enriching-tasks           ← WHEN a task has empty key_files/testing_strategy
```

## Skills

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `stride-workflow` | Starting task work | **RECOMMENDED** — Single orchestrator for the full lifecycle; also supports context-informed creation (activate with a creation intent + optional directory path; no command files in Codex); (v1.28.0+) threads the optional `behaviour_test_matrix` through Step 4 (implementation driver) and Step 6 (reviewer dispatch) |
| `stride-claiming-tasks` | `GET /api/tasks/next` or `POST /api/tasks/claim` | Claim tasks with before_doing hook execution |
| `stride-completing-tasks` | `PATCH /api/tasks/:id/complete` | Complete tasks with after_doing/before_review hooks |
| `stride-creating-tasks` | `POST /api/tasks` (work/defect) | Create tasks with correct field formats |
| `stride-creating-goals` | `POST /api/tasks/batch` | Create goals with batch format (root key must be "goals") |
| `stride-enriching-tasks` | Task has empty key_files/testing_strategy | Transform minimal specs into complete tasks |
| `stride-subagent-workflow` | After claiming, before implementation | Decision matrix for dispatching explorer/reviewer agents |

## Agents

| Agent | Purpose |
|-------|---------|
| `task-explorer` | Explore key_files and patterns before implementation |
| `task-reviewer` | Review changes against acceptance criteria before completion; emits a structured `reviewer_result` (schema 1.7 — `issues[]` entries carry an optional `cosmetic` boolean, presentational-only findings that are still reported but buy no re-review round) with `project_checks[]` (from a project-root `CODE-REVIEW.md`) and per-section testing_strategy/patterns/pitfalls/security_considerations verdicts — `security_considerations` is the fifth review_queue-scored field and (schema 1.5+) carries an optional nested `considerations[]` breakdown, plus (schema 1.6+) an OPTIONAL `behaviour_test_matrix` verdict emitted only when the task supplies a matrix |
| `task-enricher` | Populate sparse tasks (empty key_files/testing_strategy/verification_steps) after the claim, before any work |
| `task-decomposer` | Break goals into dependency-ordered child tasks |
| `hook-diagnostician` | Diagnose hook failures with prioritized fix plans |

Agents are invoked as subagents based on task complexity — see the `stride-subagent-workflow` skill's decision matrix.

The `stride-creating-tasks`, `stride-enriching-tasks`, and `stride-workflow` skills also document the optional `technical_details` task field — a free-form JSON object (no fixed keys) for any extra technical context (data shapes, gotchas, decisions, links). It is optional everywhere and is **not** one of the five review_queue-scored fields, so a blank value is never a scoring gap.

(v1.19.0+) The `stride-creating-tasks` and `stride-creating-goals` skills document the optional `created_by_agent` field — set it to the plugin's own agent name (`"Codex CLI"`, the same value sent as `agent_name` on claim/complete) so the `/agents` feed attributes the creating agent instead of a `?`. It is create-only and forbidden on `PATCH`, and the server propagates a batch goal's value to every nested child task.

(v1.25.0+) Both creation skills also document the **top-level `agent_name`** on every create request — beside the `task` root key for `POST /api/tasks` and beside the `goals` root key for `POST /api/tasks/batch` — set to that same plain agent name. It is the always-sent fallback the server reads when `created_by_agent` is omitted (which cannot be backfilled), documented with the full five-step resolution order and an explicit note that `agent_name` is display metadata only, never an authorization signal. The same release adds a **Request Envelope** section: `POST /api/tasks` takes `{"agent_name": "...", "task": {...}}`, not a bare task object — the skill previously documented the body without its `task` root key, which the server rejects with a `422`.

(v1.26.0+) **Optional exploratory-testing integration.** When the separate **[stride-codex-exploratory-testing](https://github.com/cheezy/stride-codex-exploratory-testing)** plugin is installed alongside this one, the lifecycle runs a task's `testing_strategy.manual_tests` and `edge_cases` as real, budgeted exploratory sessions: `stride-workflow` gains a gated **Step 6.5 (Manual & Exploratory Testing)** between Code Review and Execute Hooks, `stride-subagent-workflow` documents it as **Phase 3.5** in its decision matrix, `stride-completing-tasks` records the findings in the existing tolerant fields (`completion_notes`, the `reviewer_result.testing_strategy` note, and a one-line `completion_summary` mirror), and both creation skills ask for `manual_tests` entries written as charters. The integration is **optional and gated** — it activates only when that plugin's skills/agents are present in the session AND the task carries `manual_tests` or `edge_cases`. When the plugin is **not** installed, everything degrades gracefully: manual tests and edge cases remain a human responsibility exactly as before, and nothing blocks or fails completion. No new server-validated completion field and no change to the six-value `workflow_steps` vocabulary are introduced. **(v1.30.0+)** A session's findings now carry a severity that maps onto the reviewer's vocabulary (`stride-completing-tasks`, *Severity mapping*), and a Critical finding whose responsible lines survive subtracting the **claim-time dirty baseline** (a new `.stride/task-dirty-baseline` recorded at claim, so a human's pre-existing working-tree edits are never counted as the agent's) escalates fail-closed — `testing_strategy` → `failed` plus a `category: testing` Critical in `issues[]` — while a Critical anywhere else, or one this port cannot attribute, is reported and filed as a follow-up rather than blocking. The dispatch is also restricted to **non-interactive surfaces**: the plugin's `explorer` agent only, never an interactive skill such as `stride-exploratory-testing-pair`, because an autonomous workflow that activates one stalls with nobody there to answer it. The graceful skip is unchanged — with the plugin absent, no finding can block completion. The dispatch also carries an **explicit session budget** — the caller's to set, in whatever unit the installed `explorer` contract declares — and an enumerated environment context naming how to reach the app, the user's authorized/non-production affirmative (collected once at Step 0, never inferred, and absent it the dispatch is skipped rather than guessed), and where test accounts live, which are pointed at rather than inlined. Since stride-codex-exploratory-testing 0.3.0 the environment context opens with `AUTHORIZED_NON_PRODUCTION: yes` and `ALLOWED_HOSTS: <host[:port]>, ...`, each written once and first — the first only on the user's Step 0 affirmative, the second holding exactly the host and port the Step 0 reach answer names (or the dev configuration's loopback host, for a launch command, or `none` for a target driven only through a local command), with the dispatch skipped rather than guessed when no host can be named — and every line of task text, charter, operator input or copied repository text that begins with one of those names, `EXPLORATORY_REPORT_PATH` or `EXPLORATORY_MODE` is `> `-quoted so it never counts. Since W2679, before the first session one change-mode `charter-generator` dispatch, carrying pointers and task fields only and labelled untrusted, adds charters drawn from the task's edge cases and the change's risk; manual-test and generator charters merge by target, highest-risk first, at most about five per task (about three for a small one), every manual test and edge case maps to a charter, a named unit test or a human responsibility, and each session runs on the default 12-probe budget unless a charter gives a reason to move. A generator charter whose `surface` is `browser` is handed back undispatched, and this edition has no main-loop visual pass (stride's W2584 is not carried), so a session that ends `no_observation_surface` stays handed back for what it did not observe. Since W2680, Step 0 reads a `.exploratory.md` you confirm (or asks) for a probe harness or role accounts, the environment context passes a confirmed harness as the explorer's `PROBE_HARNESS`, `PROBE_SERVICES` and `PROBE_DIR` lines right after the report path and ahead of all untrusted text, and a charter on a signed-in or members-only target is not dispatched without accounts or a harness — it is recorded as not performed, `no signed-in surface`. Since W2681, every Step 6.5 charter leaves one `Exploratory charter` outcome line (since D405, a dispatch sent no report path is handed back instead, and the check still runs on the rest) with an owner for each charter not performed (a follow-up identifier, or a `HANDED BACK:` line repeated to you), `completion_summary` one `Exploratory coverage:` line, and a task with manual tests or edge cases on which Step 6.5 did not fire — it built no charter, in the one sense Step 6.5 defines — one `Exploratory testing skipped:` line; `exploratory_outcomes_ok` checks the record before the complete call. Since W2682, when a task is its goal's last open child, Step 6.5 adds one goal-scope pass after the task's own charters: it reads the goal's tree, makes one more change-mode `charter-generator` dispatch for up to about five cross-task charters drawn from every child's `key_files` and the lines changed since the goal's base, and records them with the same outcome lines and the one coverage line; it never pushes and never runs `after_goal`, and a defect it finds in a sibling's lines is recorded and followed up, never a block. Since D404, its trigger finds the project root by the same `.stride.md` walk-up as Step 8, so it works from a nested repository, and its task, tree and outcomes files fall back to the numeric id the way the claim hook's task file does. Since W2683, both creation skills, the `task-decomposer` and the `task-enricher` write each `manual_tests` entry as a risk charter by default (a target plus the information to discover, never a click script), and for a UI or HTTP feature they write `edge_cases` after considering each change-risk lens of the plugin's `heuristics` skill whose trigger matches, naming the lens; the `testing_strategy` shape and its validation are unchanged, and terse entries still validate. An `EXPLORATORY_REPORT_PATH` under `.stride/` lets the session write its findings to a file and reply with a short summary; the workflow reads back only the path it sent, and uses the reply's fenced JSON on `report: NOT WRITTEN`, writing it to that path (since W2681). The dispatch names the explorer's own tools (`read`, `search`, `glob`, `shell`), and a manual test that needs a view they cannot give ends `no_observation_surface`, read as not performed for the unobserved part. Step 6.6 hands the harden skill that same report path and an explicit `--framework` named from the project's own test command, so it asks nothing. Budget exhaustion is a normal outcome that never fails completion; what it changes is only what may honestly be claimed about coverage. Recording now carries each finding's **stakeholder impact** — who the failure lands on, which is what a reviewer weighing it needs — and cites a written session artifact by repository-relative **path** when one exists, still using only existing carriers. **Optional hardening (Step 6.6 / Phase 3.6):** when a session produced convertible findings and the `stride-exploratory-testing-harden` skill is available, the workflow drafts one regression check per bug — the step that turns *Explored* back into *Checked*. Drafts stay **staged outside the test tree** by default, because `after_doing` is a blocking gate and a check for an unfixed bug is red by construction; one enters the suite only when the file loads clean and the case is green or inert, established by running the gate's own command once rather than by expecting. A finding that crosses an authorization or tenancy boundary is drafted to **assert the guard fires**, never to perform the bypass, so the suite never stores a working exploit. Anything written after the reviewer saw the diff is surfaced and triggers a re-review. Skipping changes nothing.

(v1.27.0+) **Optional security-considerations deep review.** When the separate **[stride-codex-security-review](https://github.com/cheezy/stride-codex-security-review)** plugin is installed alongside this one, the review phase runs a task's `security_considerations` list through the specialist `security-reviewer` agent in **considerations mode** to confirm each listed consideration was actually mitigated by the diff. `stride-workflow` gains a gated **Deep security-considerations review** sub-step inside **Step 6 (Code Review)**, `stride-subagent-workflow` documents the trigger in its decision matrix, and the returned per-consideration verdicts merge into `reviewer_result.security_considerations.considerations[]` (the schema 1.5 nested breakdown) via the whole-object passthrough — folded into the existing reviewer telemetry with **no new `workflow_steps` name**. Escalation is **fail-closed**: any `partial`/`unmitigated` verdict forces the section status to `failed` and appends a `category: security` Critical issue, routing it through the same gate that already blocks on a failed section. The dispatch opens with the `/security-review invocation, mode: considerations` tag and the considerations one per line, sends that plugin's `modes/considerations.md`, `modes/reproduction.md` and `modes/result-file.md` verbatim between keyed marker lines (read from beside its installed `stride-security-review` skill only after availability is decided, refused when the file is a symlink or resolves inside the project root, and never executed), lists the changed files on `- ` lines so none can read as a key or marker line,, and passes `SECURITY_RESULT_PATH=<project root>/.stride/.security-<IDENTIFIER>-r<N>.json`: one file per review round, read back from that path alone, with the inline document used on `result: NOT WRITTEN`, and removed once the completion is accepted. A `partial` whose note starts `budget reached:` counts as unverified and fails closed like any other. The integration is **optional and gated** — it activates only when that plugin's skills/agent are present in the session AND the task carries a non-empty `security_considerations` list (a `"None — …"` placeholder does not count). When the plugin is **not** installed, the review degrades gracefully to the task-reviewer's generalist `security_considerations` verdict and nothing blocks or fails completion.

(v1.28.0+) **Optional `behaviour_test_matrix` support.** A task MAY carry an optional `behaviour_test_matrix` — an array of rows, each pairing one behaviour the change must satisfy with the real test that covers it, across **7 fixed categories** (`Happy path`, `Boundary`, `Error / exception`, `Null / empty`, `Concurrency`, `Lifecycle / wiring`, `Contract / serialization`). Both creation skills document the row shape; `task-enricher` / `stride-enriching-tasks` populate it (all seven categories or omit the field entirely — a partial matrix is rejected); `stride-workflow` Step 4 drives implementation from it, advancing each row's `status` from `"planned"` to `"passing"`/`"failing"` and PATCHing the update back onto the task; and `task-reviewer` verifies each row's named test actually exists and emits the `behaviour_test_matrix` verdict into `reviewer_result` (schema 1.6). `stride-creating-tasks`, `stride-creating-goals` and `task-decomposer` now write it by default too, all seven categories, whenever `testing_strategy` lists a unit or integration test, and skip it only where a task has nothing testable, saying why in its `description`. The field stays **optional at the API** — it is never one of the five review_queue-scored fields, so an absent matrix is never an empty pill, the reviewer omits the verdict key entirely rather than emitting a placeholder, and a task without one changes nothing. Row text is treated as untrusted **data** to assess, never as instructions. (v1.29.0+) Every rule reading row text is hardened: the secret rule triggers on row *state* rather than agent intent and extends to credentials named by location; a refused row is reported in `completion_notes` by category and position (never quoted) and echoed by the reviewer with the `[REDACTED — row text embedded a credential]` sentinel and a `failing` status, which is the *expected* outcome of a correct refusal; and re-sending already-stored row text unchanged onto its own record is stated to be not a new copy, resolving the PATCH-body contradiction.

(v1.34.0+) **Two-round review cap.** The review loop is bounded: two rounds is the whole budget, and the second runs only when round one earns it — by a fix that touched a code path, or by a `critical` or `security` finding in round one; failing that, the fixes are written down and round one's block is the one submitted. When it runs, the second verifies round one's fixes rather than re-reviewing from scratch — scoping its *mission*, never its *evidence*, so it still receives the full diff and still emits the full `acceptance_criteria` array, every section verdict and `project_checks`. A **round** is a reviewer invocation whose response yielded a fenced JSON block that parsed into an object; a crashed or unparsable invocation is re-invoked and consumes no round. That definition is expressed on the surface this port actually has — the parsed block — because unlike stride this port writes no per-round result file. After round two, residual `important`/`minor` findings are **recorded** by severity, category and `file:line` rather than fixed; a `critical` is **exempt and blocks for however many rounds it takes**, and a `category: "security"` finding is never merely recorded at any severity (`important` being the reviewer's default for one). The orchestrator gains a `review_round` dispatch field and a `.stride/.review-rounds-<IDENTIFIER>.json` counter. **Enforced or stated?** Both, and the contract says which is which: the cap's arithmetic is a real assert in the extraction self-check, while its *inputs* are self-asserted rather than result-verified — this port persists no per-round reviewer artifact to recount against, so an orchestrator that never increments makes the cap read green. That limit is stated on the same footing as the pin's `critical_cleared` input rather than left implied.

## Hook Execution

**Codex CLI does have a hook system** (stable since rust-v0.124.0), and this plugin registers one hook — see [The Stride hook surface](#the-stride-hook-surface) below. That hook records loop state and downloads a claimed task's attachments; **it never executes a `.stride.md` section.** Executing those remains the agent's job: it reads the file and runs each command via shell.

### The Stride hook surface

`hooks/hooks.json` registers **two** handlers: a `PostToolUse` handler on the
`Bash` matcher running `hooks/stride-hook.sh post`, and a `Stop` handler
running `hooks/stride-stop-gate.sh`. Codex discovers a plugin-bundled
`hooks/hooks.json` by default, alongside `~/.codex/hooks.json`,
`<repo>/.codex/hooks.json` and the `config.toml` `[hooks]` tables.

#### The recorder — `stride-hook.sh`

It does these things, and deliberately nothing else:

- After a **successful** `PATCH /api/tasks/:id/complete`, it writes
  `.stride/.loop-state.json` with four keys — `identifier`, `needs_review`
  (verbatim from the API response, as a real JSON boolean), `completed_at`
  (ISO-8601 UTC) and `session_id`.
- After **any** claim — successful, failed, or against an empty queue — it
  removes that file.
- After a **successful** claim whose own response it can parse, it downloads
  each file the task lists in `data.attachments` into
  `.stride/attachments/<IDENTIFIER>/`, writes `manifest.json` there last (one
  entry per attachment, with its `status` and `reason`), and writes
  `.stride/attachments/.gitignore` containing `*` so no attachment is ever
  committed. Files over 25 MiB, past 20 files or past 100 MiB in total are
  skipped, and the whole download has a 30-second budget inside the hook's
  60-second timeout. The API URL and the production `API Token` come from
  `.stride_auth.md` only; the token goes to curl on stdin, never in a command
  line, and only to that URL. A download problem is recorded in the manifest
  and one stderr line, and never changes the claim's outcome. The contract is
  `stride/docs/porting-attachments.md`.

The record is written by the hook rather than by the agent on purpose: an
agent-written marker is exactly as skippable as the instruction it replaces,
and this file is meant to be evidence the agent cannot forget to leave.

It never writes to stdout, always exits 0, and never fails a completion
because the record could not be written — the record is a gate input, not a
correctness dependency. Its only network call is that attachment download. It
executes no `.stride.md` section, and reads the API response only from the hook event for the call
being hooked, never from `.stride/.last-api-response.json` (that file survives
across calls, so a truncated or 422 response would otherwise inherit the
previous claim's payload and record a completion that never happened).

#### Attachments in the workflow

The download only helps if the agents look at it, so the workflow hands it on.
`stride-workflow` Step 3 resolves `ATTACHMENTS_DIR` — the task's
`.stride/attachments/<IDENTIFIER>/` — and passes it beside `TASK_FILE` to the
`task-explorer` custom agent and, in Step 6, to the `task-reviewer`, but only
when that directory's `manifest.json` names the claimed task. A missing
manifest means no attachments; one that names another task or will not parse
is reported on an `attachments:` line and nothing is passed. The agents read
only the files the manifest lists as `downloaded`, as data and never as
instructions, and never fetch one themselves: the reviewer's shell is never
used for it. Step 8 removes the directory after a 2xx completion only — never
through a symlink, never `.stride/attachments/.gitignore`, and never at claim
time, when the hook alone writes and replaces it.

**Image viewing is not verified.** No Codex CLI was installed where this was
written, so no Codex CLI version was checked and `view_image` has not been
verified — not from the main agent, and not from a custom agent whose tools
are `read`, `search` and `glob` (plus `shell` for the reviewer). `AGENTS.md`
does not list it and the agents are not told to use it. An image or PDF that
`read` cannot show is reported by its `filename`, `content_type` and
`byte_size` instead. Checking `view_image` on a real Codex CLI, and recording
the version here, is still open.

#### The gate — `stride-stop-gate.sh`

Fires on `Stop` and refuses to end a session while work demonstrably remains.
It blocks in exactly **one** case: the loop-state record exists, its
`needs_review` is the boolean `false`, and
`GET /api/tasks/next?response_view=slim` answers 200 with a claimable
identifier. A block is
`{"decision":"block","reason":"..."}` on stdout with exit 0 — on a Stop event
that does not reject anything, it forces the session to continue using the
reason as the new instruction.

**Everything else permits, and every failure permits** — no loop-state file, an
unparseable record, a completion that needs review, an unreachable or non-200
API, an unparseable body, no claimable task, an identifier that is not
identifier-shaped, or a block counter that cannot be written. The gate fails
open by construction: it is a nudge, and it must never be able to trap a
session.

It is bounded so it cannot wedge you. `.stride/.stop-gate-blocks` records at
most **2** refusals per unfollowed completion; ending the session again past
that budget simply permits. `STRIDE_ALLOW_STOP=1` skips the gate outright, and
`STRIDE_STOP_GATE_MAX_BLOCKS` (digits only) changes the bound. The counter is
written *before* the block is emitted, so a block that happened is always a
block that was counted.

The API token reaches only curl's `Authorization` header — never stdout,
stderr, or the block reason — and the call is bounded by
`--connect-timeout 3 --max-time 5`.

`.stride/` must be gitignored — see step 1 of the installer's next steps; it
holds the block counter as well as the loop-state record.

#### Where the hooks look — the project root

Both hooks find the project root the way the skills do, so the records they
write and read are the ones the skills write and read:

1. `CODEX_PROJECT_DIR`, when set;
2. otherwise `CLAUDE_PROJECT_DIR`, when set;
3. otherwise the nearest directory at or above the event's `.cwd` (or, on an
   event without one, the hook's own working directory) that holds a
   `.stride.md`. The walk stops at that nearest `.stride.md`, so a nested
   project's records, and the `.stride_auth.md` they read, are never a parent
   project's. The start is folded first, so a `..` in it never walks below an existing
   directory, and the root found is canonicalised with `CDPATH` cleared.

With no `.stride.md` anywhere above, the root is the event's `.cwd`, then `.`
— the hook's behaviour before the walk existed. The skills have no root at all
in that case and do nothing, but the recorder must still write its record, and
it never writes above the event's working directory. The two hooks carry one
copy of this block, byte for byte.

Two limits remain. The hook walks the event's `.cwd` as given and the skills
walk their shell's `$PWD`, so when one sees a symlinked path and the other the
physical one, they can still pick different roots. And a relative
`CODEX_PROJECT_DIR` or `CLAUDE_PROJECT_DIR` is resolved against each process's
own working directory, so set either variable to an absolute path.

### Where Codex sits in the stop-hook capability matrix

<!-- canon:stop-hook-capability v1 -->

Blocking a session end is a **per-runtime capability**, not one surface with one
spelling across the fleet. Three things differ between runtimes, and a port must
settle all three before wiring a gate: whether a session-end event exists that
can refuse at all, what value expresses the refusal, and what stops a refused
stop from looping. Codex CLI's answers:

| | Codex CLI |
|---|---|
| State | **Blocks** — the event exists and its value is honoured |
| Session-end event | `Stop` |
| How a refusal is expressed | `{"decision":"block","reason":...}` on stdout at exit 0, or exit 2 with the prompt on stderr |
| Loop guard | **None supplied by the runtime — the handler must bound itself** |

**Exit 2 is not portable, which is why this port does not use it.** It blocks on
Codex and Claude Code, is a retry on Gemini (whose `deny` reason returns as the
agent's next prompt), and on Copilot's `agentStop` it is a *warning only* — the
session ends anyway, with no error and nothing to distinguish it from a gate
that correctly found no work. So `stride-stop-gate.sh` expresses its refusal as
a JSON decision on stdout and no code path in it exits 2.

**Codex adds three conditions of its own, each of which fails quietly rather
than loudly:**

- the handler must be declared **`async: false`** — an async handler runs and
  then has its control effect discarded, so the gate would silently do nothing;
- hook definitions are **trust-hash pinned**, so every edit to one needs
  re-approval before it takes effect again;
- a `block` whose `reason` is **blank degrades to a FAILURE** rather than a
  block, and the session ends.

**The portable shape, which this port implements:** emit the runtime's own JSON
decision on stdout at exit 0, never rely on exit 2 to carry the refusal, give
the decision a non-empty reason, and **self-limit** — bound the consecutive
refusals in the gate's own state rather than trusting the runtime to. Codex
supplies `stop_hook_active` on a re-firing stop and the gate honours it, but as
a bonus only; the guarantee is its own persisted counter.

**Canon-governed — entry `stop-hook-capability` in `stride/docs/port-canon.md`.** A change to the substance above owes a version bump in **two** places before the next release: that entry in the canon, and this file's own `<!-- canon:stop-hook-capability ... -->` anchor above.

### Registering the hook

There are two install shapes, and they differ here:

- **Plugin-bundled install.** `hooks/hooks.json` sits at the plugin's default
  bundled path and Codex loads it alongside `~/.codex/hooks.json`,
  `<repo>/.codex/hooks.json` and the `config.toml` `[hooks]` tables. Nothing to
  do; `${PLUGIN_ROOT}` is set for you.
- **`.agents/` install (both installers, and the manual instructions above).**
  This is a loose tree rather than a plugin bundle, so `.agents/hooks/` is
  **not** scanned and `${PLUGIN_ROOT}` is not set. Register the handler once,
  by hand, with an absolute path — in `~/.codex/hooks.json` for a global
  install or `<repo>/.codex/hooks.json` for a project-local one:

  ```json
  {
    "hooks": {
      "PostToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "/absolute/path/to/.agents/hooks/stride-hook.sh post",
              "async": false,
              "timeout": 60
            }
          ]
        }
      ],
      "Stop": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/absolute/path/to/.agents/hooks/stride-stop-gate.sh",
              "async": false,
              "timeout": 10
            }
          ]
        }
      ]
    }
  }
  ```

  `Stop` takes no `matcher` — it is not tool-scoped. Register it under the
  `Stop` spelling only: a loader honouring a second spelling would fire the
  gate twice and double-spend its block budget.

  Both installers print this snippet with your actual install path filled in.

Two operational notes:

- **Trust-hash pinning.** Codex pins hook definitions by hash, so Codex
  prompts for approval on first use and again after any update that changes
  `hooks/stride-hook.sh` or `hooks/hooks.json`.
- **Windows.** This port ships no `.ps1` twin for either hook, so on native
  Windows without a bash on `PATH` no loop state is recorded and the Stop gate
  never runs. Git Bash and WSL run the `.sh` files directly and are unaffected.

If the hook never appears to fire, check these in order:

1. **Is it registered at all?** This is the likeliest cause by far on a
   `.agents/` install, because that destination is not a scanned location —
   see "Registering the hook" above. A plugin-bundled install does not need
   this step; a loose one always does.
2. **Did you approve it?** Codex pins hook definitions by trust hash and will
   not run an unapproved or changed definition.
3. **Only if you registered with `${PLUGIN_ROOT}`:** that variable is set for
   plugin hooks only, and its expansion depends on the command being run
   through a shell. Substitute the absolute installed path instead.

### How Hooks Work in Codex

1. The skill instructs the agent which `.stride.md` section to execute
2. The agent reads the `## section_name` from `.stride.md`
3. The agent extracts commands from the ` ` `bash code block
4. The agent executes each command **one at a time** via shell (a backslash-continued line is one logical command, not a merge of separate commands)
5. If any command fails, the agent stops and fixes the issue before proceeding

### Hook Lifecycle

| Hook | When | Blocking | Timeout |
|------|------|----------|---------|
| `before_doing` | After claiming a task | Yes | 60s |
| `after_doing` | Before marking complete | Yes | 120s |
| `before_review` | After marking complete | Yes | 60s |
| `after_review` | After review approval | Yes | 60s |
| `after_goal` | After the parent goal's final child task completes | Yes | 60s typical (honors server `hook.timeout`) |

**Blocking hooks** prevent the next step if any command fails. The agent must fix the issue and re-run the hook before proceeding.

### Hook Execution Rules

- Execute each command line **one at a time** — do not combine into a single script. A line ending in a trailing backslash (`\`) continues onto the next physical line, and the joined text is a single logical command; "one at a time" targets logical commands, not physical lines, and does not license merging unrelated commands into one opaque script.
- **Never prompt for permission** — hooks are pre-authorized by the user who authored them
- Capture exit codes — a non-zero exit code means the hook failed
- Include each hook result in the matching API call: `before_doing_result` on the `POST /api/tasks/claim` body; `after_doing_result` and `before_review_result` on the `PATCH /api/tasks/:id/complete` body. (`after_goal` results POST separately to `PATCH /api/tasks/:goal_id/after_goal`.)

## API Authorization

All Stride API calls are pre-authorized when the user initiates a Stride workflow. Agents should never prompt for permission to call Stride endpoints or execute hooks.

## Troubleshooting

### Skills not discovered

- Verify skills are in `.agents/skills/<name>/SKILL.md` or `.codex/skills/<name>/SKILL.md`
- Skill names must match their directory name exactly

### Agents not available

- Verify agent files are in `.agents/agents/<name>.md`
- Agents are invoked as subagents via the Codex agent system

### Hook commands fail

- Check the specific command that failed in the shell output
- Fix the issue and re-run — the skill will instruct you to retry
- Common causes: merge conflicts, failing tests, missing dependencies

### Missing environment variables in hooks

- Task metadata (`$TASK_ID`, `$TASK_IDENTIFIER`, etc.) must be set manually from the claim API response
- The claiming skill provides the exact fields to extract

## License

MIT
