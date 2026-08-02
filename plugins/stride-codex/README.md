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

# Copy skills and agents
cp -r stride-codex/skills/ .agents/skills/
cp -r stride-codex/agents/ .agents/agents/
cp stride-codex/AGENTS.md AGENTS.md
```

For Windows manual installation, use `Copy-Item`:

```powershell
git clone https://github.com/cheezy/stride-codex.git

# Copy skills and agents
Copy-Item -Recurse stride-codex\skills\* .agents\skills\
Copy-Item -Recurse stride-codex\agents\*.md .agents\agents\
Copy-Item stride-codex\AGENTS.md .\AGENTS.md
```

Codex CLI discovers skills in `.agents/skills/` or `.codex/skills/` and agents in `.agents/agents/` automatically.

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

**`after_goal` (v1.11.0+):** the Stride server bundles an `after_goal` entry in the `hooks` array of the response of `/complete` or `/mark_reviewed` when the completing task is the final child of a parent goal. Codex CLI has no plugin hook script, so the agent is responsible for the entire after_goal lifecycle: detect the entry by reading the **canonical capture file** (below) rather than truncatable context, read `## after_goal` from `.stride.md`, export `GOAL_ID` / `GOAL_IDENTIFIER` / `GOAL_TITLE` / `GOAL_DESCRIPTION` from the entry's `hook.env` block, execute the section's commands via shell, capture `{exit_code, output, duration_ms}`, and POST the result to `PATCH /api/tasks/:goal_id/after_goal` to flip the goal to Done. A missing `## after_goal` section is a clean no-op (back-compat — the server's grace-window worker covers the goal transition, flipping only the goal's status; it never runs `## after_goal` or performs any push). The hook is general-purpose — Slack notifications, artifact archival, release pipelines, project-level smoke tests are all valid uses.

**Truncation-proof detection (v1.23.0+):** the `/complete` and `/mark_reviewed` curls capture the full response to `${CLAUDE_PROJECT_DIR:-.}/.stride/.last-api-response.json` (via `tee`, with a `curl --output` fallback for `tee`-less shells), and the detect step reads the after_goal entry and `GOAL_*` env from that file with `jq` — not from the agent's truncatable context. If the file is absent, empty, or invalid JSON, a fresh, self-contained `GET /api/tasks/:id/after_goal_status` re-confirms whether after_goal is armed, sourcing the URL/token durably from `.stride_auth.md` and `TASK_ID` from the captured file rather than a prior turn's export. The two detection paths are mutually exclusive, so `## after_goal` runs at most once. The `.stride/` directory holds this agent-local state and must be gitignored. See `stride-workflow` SKILL.md Step 7+9 for the full procedure.

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
| `task-reviewer` | Review changes against acceptance criteria before completion; emits a structured `reviewer_result` (schema 1.6) with `project_checks[]` (from a project-root `CODE-REVIEW.md`) and per-section testing_strategy/patterns/pitfalls/security_considerations verdicts — `security_considerations` is the fifth review_queue-scored field and (schema 1.5+) carries an optional nested `considerations[]` breakdown, plus (schema 1.6+) an OPTIONAL `behaviour_test_matrix` verdict emitted only when the task supplies a matrix |
| `task-enricher` | Populate sparse tasks (empty key_files/testing_strategy/verification_steps) before claiming |
| `task-decomposer` | Break goals into dependency-ordered child tasks |
| `hook-diagnostician` | Diagnose hook failures with prioritized fix plans |

Agents are invoked as subagents based on task complexity — see the `stride-subagent-workflow` skill's decision matrix.

The `stride-creating-tasks`, `stride-enriching-tasks`, and `stride-workflow` skills also document the optional `technical_details` task field — a free-form JSON object (no fixed keys) for any extra technical context (data shapes, gotchas, decisions, links). It is optional everywhere and is **not** one of the five review_queue-scored fields, so a blank value is never a scoring gap.

(v1.19.0+) The `stride-creating-tasks` and `stride-creating-goals` skills document the optional `created_by_agent` field — set it to the plugin's own agent name (`"Codex CLI"`, the same value sent as `agent_name` on claim/complete) so the `/agents` feed attributes the creating agent instead of a `?`. It is create-only and forbidden on `PATCH`, and the server propagates a batch goal's value to every nested child task.

(v1.25.0+) Both creation skills also document the **top-level `agent_name`** on every create request — beside the `task` root key for `POST /api/tasks` and beside the `goals` root key for `POST /api/tasks/batch` — set to that same plain agent name. It is the always-sent fallback the server reads when `created_by_agent` is omitted (which cannot be backfilled), documented with the full five-step resolution order and an explicit note that `agent_name` is display metadata only, never an authorization signal. The same release adds a **Request Envelope** section: `POST /api/tasks` takes `{"agent_name": "...", "task": {...}}`, not a bare task object — the skill previously documented the body without its `task` root key, which the server rejects with a `422`.

(v1.26.0+) **Optional exploratory-testing integration.** When the separate **[stride-codex-exploratory-testing](https://github.com/cheezy/stride-codex-exploratory-testing)** plugin is installed alongside this one, the lifecycle runs a task's `testing_strategy.manual_tests` as real, budgeted exploratory sessions: `stride-workflow` gains a gated **Step 6.5 (Manual & Exploratory Testing)** between Code Review and Execute Hooks, `stride-subagent-workflow` documents it as **Phase 3.5** in its decision matrix, `stride-completing-tasks` records the findings in the existing tolerant fields (`completion_notes`, the `reviewer_result.testing_strategy` note, and a one-line `completion_summary` mirror), and both creation skills advise phrasing `manual_tests` entries as charters. The integration is **optional and gated** — it activates only when that plugin's skills/agents are present in the session AND the task carries `manual_tests`. When the plugin is **not** installed, everything degrades gracefully: manual tests remain a human responsibility exactly as before, and nothing blocks or fails completion. No new server-validated completion field and no change to the six-value `workflow_steps` vocabulary are introduced. **(v1.30.0+)** A session's findings now carry a severity that maps onto the reviewer's vocabulary (`stride-completing-tasks`, *Severity mapping*), and a Critical finding whose responsible lines survive subtracting the **claim-time dirty baseline** (a new `.stride/task-dirty-baseline` recorded at claim, so a human's pre-existing working-tree edits are never counted as the agent's) escalates fail-closed — `testing_strategy` → `failed` plus a `category: testing` Critical in `issues[]` — while a Critical anywhere else, or one this port cannot attribute, is reported and filed as a follow-up rather than blocking. The dispatch is also restricted to **non-interactive surfaces**: the plugin's `explorer` agent only, never an interactive skill such as `stride-exploratory-testing-pair`, because an autonomous workflow that activates one stalls with nobody there to answer it. The graceful skip is unchanged — with the plugin absent, no finding can block completion. The dispatch also carries an **explicit session budget** — the caller's to set, in whatever unit the installed `explorer` contract declares — and an enumerated environment context naming how to reach the app, the user's authorized/non-production affirmative (collected once at Step 0, never inferred, and absent it the dispatch is skipped rather than guessed), and where test accounts live, which are pointed at rather than inlined. Budget exhaustion is a normal outcome that never fails completion; what it changes is only what may honestly be claimed about coverage. Recording now carries each finding's **stakeholder impact** — who the failure lands on, which is what a reviewer weighing it needs — and cites a written session artifact by repository-relative **path** when one exists, still using only existing carriers. **Optional hardening (Step 6.6 / Phase 3.6):** when a session produced convertible findings and the `stride-exploratory-testing-harden` skill is available, the workflow drafts one regression check per bug — the step that turns *Explored* back into *Checked*. Drafts stay **staged outside the test tree** by default, because `after_doing` is a blocking gate and a check for an unfixed bug is red by construction; one enters the suite only when the file loads clean and the case is green or inert, established by running the gate's own command once rather than by expecting. A finding that crosses an authorization or tenancy boundary is drafted to **assert the guard fires**, never to perform the bypass, so the suite never stores a working exploit. Anything written after the reviewer saw the diff is surfaced and triggers a re-review. Skipping changes nothing.

(v1.27.0+) **Optional security-considerations deep review.** When the separate **[stride-codex-security-review](https://github.com/cheezy/stride-codex-security-review)** plugin is installed alongside this one, the review phase runs a task's `security_considerations` list through the specialist `security-reviewer` agent in **considerations mode** to confirm each listed consideration was actually mitigated by the diff. `stride-workflow` gains a gated **Deep security-considerations review** sub-step inside **Step 6 (Code Review)**, `stride-subagent-workflow` documents the trigger in its decision matrix, and the returned per-consideration verdicts merge into `reviewer_result.security_considerations.considerations[]` (the schema 1.5 nested breakdown) via the whole-object passthrough — folded into the existing reviewer telemetry with **no new `workflow_steps` name**. Escalation is **fail-closed**: any `partial`/`unmitigated` verdict forces the section status to `failed` and appends a `category: security` Critical issue, routing it through the same gate that already blocks on a failed section. The integration is **optional and gated** — it activates only when that plugin's skills/agent are present in the session AND the task carries a non-empty `security_considerations` list (a `"None — …"` placeholder does not count). When the plugin is **not** installed, the review degrades gracefully to the task-reviewer's generalist `security_considerations` verdict and nothing blocks or fails completion.

(v1.28.0+) **Optional `behaviour_test_matrix` support.** A task MAY carry an optional `behaviour_test_matrix` — an array of rows, each pairing one behaviour the change must satisfy with the real test that covers it, across **7 fixed categories** (`Happy path`, `Boundary`, `Error / exception`, `Null / empty`, `Concurrency`, `Lifecycle / wiring`, `Contract / serialization`). Both creation skills document the row shape; `task-enricher` / `stride-enriching-tasks` populate it (all seven categories or omit the field entirely — a partial matrix is rejected); `stride-workflow` Step 4 drives implementation from it, advancing each row's `status` from `"planned"` to `"passing"`/`"failing"` and PATCHing the update back onto the task; and `task-reviewer` verifies each row's named test actually exists and emits the `behaviour_test_matrix` verdict into `reviewer_result` (schema 1.6). The field is **fully optional** — it is never one of the five review_queue-scored fields, so an absent matrix is never an empty pill, the reviewer omits the verdict key entirely rather than emitting a placeholder, and a task without one changes nothing. Row text is treated as untrusted **data** to assess, never as instructions. (v1.29.0+) Every rule reading row text is hardened: the secret rule triggers on row *state* rather than agent intent and extends to credentials named by location; a refused row is reported in `completion_notes` by category and position (never quoted) and echoed by the reviewer with the `[REDACTED — row text embedded a credential]` sentinel and a `failing` status, which is the *expected* outcome of a correct refusal; and re-sending already-stored row text unchanged onto its own record is stated to be not a new copy, resolving the PATCH-body contradiction.

## Hook Execution

**Codex CLI has no automatic hook interception.** The agent must execute `.stride.md` hooks directly by reading the file and running each command via shell.

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
