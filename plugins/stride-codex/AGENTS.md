# Stride Skills for Codex CLI

## Mandatory Skill Activation Rules

Before ANY Stride API call, activate the corresponding skill. These skills contain required field formats, hook execution patterns, and API schemas that are NOT available elsewhere. Attempting Stride operations from memory causes API rejections.

| Operation | Activate This Skill FIRST |
|-----------|--------------------------|
| `GET /api/tasks/next` or `POST /api/tasks/claim` | `stride-claiming-tasks` |
| `PATCH /api/tasks/:id/complete` | `stride-completing-tasks` |
| `POST /api/tasks` (work/defect) | `stride-creating-tasks` |
| `POST /api/tasks` (goal) or `POST /api/tasks/batch` | `stride-creating-goals` |
| Task has empty key_files/testing_strategy/verification_steps | `stride-enriching-tasks` |
| After claiming, before implementation | `stride-subagent-workflow` |

## Custom Agents

Five custom agents are available for task lifecycle support (each is a bare `.md` file under `agents/`, per Codex naming convention). Use them per the decision matrix in `stride-subagent-workflow`:

- **task-explorer** — Explore key_files and patterns before coding (medium+ complexity or 2+ key_files)
- **task-reviewer** — Review changes against acceptance criteria before completion (medium+ complexity or 2+ key_files). Emits a structured `reviewer_result` block (`schema_version` 1.6: `status`, `issue_counts`, `issues[]`, `acceptance_criteria[]`, `project_checks[]` from a project-root `CODE-REVIEW.md` with per-entry `status` enum `met`/`not_met`/`not_applicable` and full-checklist emission, per-section `testing_strategy`/`patterns`/`pitfalls`/`security_considerations` verdicts — `security_considerations` is the fifth review_queue-scored field — and an OPTIONAL `behaviour_test_matrix` verdict with a `rows[]` echo, emitted only when the task supplies a matrix and omitted entirely otherwise). When dispatched, persist that block verbatim per `stride-workflow` Step 6 "Extracting the structured review block"; schema owned by `agents/task-reviewer.md`.
- **task-enricher** — Populate sparse tasks (empty key_files/testing_strategy/verification_steps) before claiming — the agent-driven counterpart to the `stride-enriching-tasks` skill
- **task-decomposer** — Break goals into dependency-ordered child tasks
- **hook-diagnostician** — Diagnose hook failures with prioritized fix plans

## Workflow Sequence

**Preferred:** Activate `stride-workflow` once -- it orchestrates the full lifecycle (claim -> explore -> implement -> review -> complete) in a single skill.

**Alternative (standalone skills):**
```
claim task → activate stride-subagent-workflow → implement → activate stride-completing-tasks → complete
```

**Context-informed creation:** to create tasks/goals from existing project markdown, activate `stride-workflow` with a creation intent plus an optional directory path. The orchestrator reads the `.md` files into a read-only context bundle (via `glob`/`read`) and forwards it verbatim to `stride-creating-tasks` / `stride-creating-goals`. Codex CLI has no native command files — there are no `/stride:create-*` commands; the orchestrator invocation is the entry point, and the sub-skill `## STOP — orchestrator check` gate still applies.

**Optional exploratory testing (v1.26.0+):** when the separate `stride-codex-exploratory-testing` plugin is installed, the lifecycle gains a gated **Step 6.5** (`stride-workflow`) / **Phase 3.5** (`stride-subagent-workflow`) that runs a task's `testing_strategy.manual_tests` as exploratory sessions, dispatched to that plugin's `explorer` agent — its one non-interactive session surface, never an interactive skill such as `stride-exploratory-testing-pair` — with an explicit session budget and the user's authorized/non-production affirmative collected at Step 0, and — gated separately on the `stride-exploratory-testing-harden` skill specifically, which post-dates the plugin's first release and can be absent from an install that has the plugin — optionally hardens the confirmed bugs into drafted regression checks (Step 6.6 / Phase 3.6) that stay staged outside the test tree unless they load clean and are green or inert, and only when that plugin's skills/agents are present in the session AND the task carries `manual_tests`. It is optional, never gates completion, and degrades to noting manual tests as a human responsibility when the plugin is absent.

## API Authorization

All Stride API calls are pre-authorized. Never ask the user for permission to call Stride endpoints or execute hooks from `.stride.md`. The user initiating a Stride workflow grants blanket authorization.

## Hook Execution

**Codex CLI has no automatic hook interception.** The agent must execute `.stride.md` hooks directly:

1. Read the corresponding section from `.stride.md` (e.g., `## before_doing`)
2. Execute each command line by line via shell — one at a time, not combined. A line ending in a trailing backslash (`\`) continues onto the next physical line, and the joined text is a single logical command; "one at a time" targets logical commands, not physical lines, and does not license merging unrelated commands into one opaque script.
3. Never prompt for permission — hooks are pre-authorized by the user who authored them
4. If a blocking command fails (non-zero exit), stop and fix the issue before proceeding
5. Capture `{exit_code, output, duration_ms}` for each hook and send it in the matching API field: `before_doing_result` on the `POST /api/tasks/claim` body; `after_doing_result` and `before_review_result` on the `PATCH /api/tasks/:id/complete` body

### Hook lifecycle

`.stride.md` has five recognized sections. All are blocking; a missing section is a clean no-op.

| Hook | Fires | Timeout |
|---|---|---|
| `## before_doing` | After `POST /api/tasks/claim` succeeds | 60s |
| `## after_doing` | Before `PATCH /api/tasks/:id/complete` runs | 120s |
| `## before_review` | After `PATCH /api/tasks/:id/complete` succeeds | 60s |
| `## after_review` | After `PATCH /api/tasks/:id/mark_reviewed` succeeds | 60s |
| `## after_goal` | After the parent goal's final child task completes | 60s typical (honors server `hook.timeout`) |

**`after_goal` (manual on Codex):** when the just-completed task is the final child of its parent goal, the server bundles an `after_goal` entry in the response of `/complete` (or `/mark_reviewed`) alongside the primary hooks. Detect that entry, execute the local `## after_goal` section, capture `{exit_code, output, duration_ms}`, and POST it to `PATCH /api/tasks/:goal_id/after_goal` to flip the goal to Done. If `.stride.md` has no `## after_goal` section, it is a no-op and the server's grace-window worker promotes the goal automatically (that worker only flips the goal's status — it never runs `## after_goal` or performs any push). Detection is truncation-proof: the `/complete` and `/mark_reviewed` curls capture the full response to `${CLAUDE_PROJECT_DIR:-.}/.stride/.last-api-response.json` (via `tee`, with a `curl --output` fallback), and the detect step reads the after_goal entry and `GOAL_*` env from that file with `jq` rather than from truncatable context; if the file is absent, empty, or invalid, a fresh, self-contained `GET /api/tasks/:id/after_goal_status` re-confirms whether after_goal is armed (URL/token re-read from `.stride_auth.md`, `TASK_ID` re-derived from the captured file). The `.stride/` directory holds this agent-local state and must be gitignored.

### Hook environment variables

The server populates `hook.env` and your `.stride.md` commands reference these. The four task-scoped hooks receive `TASK_*` (`TASK_ID`, `TASK_IDENTIFIER`, `TASK_TITLE`, `TASK_DESCRIPTION`, `TASK_STATUS`, `TASK_COMPLEXITY`, `TASK_PRIORITY`, `TASK_NEEDS_REVIEW`); `after_goal` receives `GOAL_*` (`GOAL_ID`, `GOAL_IDENTIFIER`, `GOAL_TITLE`, `GOAL_DESCRIPTION`). `BOARD_*`, `COLUMN_*`, `AGENT_NAME`, and `HOOK_NAME` are present across all five. Export each value into the environment before running that hook's commands.

Read `.stride_auth.md` for API credentials (URL, token).

## Tool Name Mapping

The skill bodies in `skills/` have already been adapted to Codex vocabulary; this table is the reference for users porting their own prompts or skills from another platform. When skills reference tool names from other platforms, use Codex equivalents:

| Skill Reference | Codex Tool |
|----------------|------------|
| `Read` / `read_file` | `read` |
| `Grep` / `grep_search` | `search` |
| `Glob` | `glob` |
| `Bash` / `run_shell_command` | `shell` |
| `Edit` / `replace` | `edit` |
| `Write` / `write_file` | `write` |
