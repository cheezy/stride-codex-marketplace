---
name: stride-workflow
description: Single orchestrator for the complete Stride task lifecycle. Invoke when the user asks to claim a task, work on the next stride task, work on stride tasks, complete a stride task, enrich a stride task, decompose a goal, or create a goal or stride tasks. Replaces invoking stride-claiming-tasks, stride-completing-tasks, stride-creating-tasks, stride-creating-goals, stride-enriching-tasks, or stride-subagent-workflow directly — those are dispatched from inside this orchestrator. Walks through prerequisites, claiming, exploration, implementation, review, hooks, and completion. Handles both Claude Code (with subagent dispatch) and other environments (Cursor/Windsurf/Continue without subagents).
---

# Stride: Workflow Orchestrator

## Purpose

This skill replaces the fragmented pattern of remembering to activate `stride-claiming-tasks`, `stride-subagent-workflow`, and `stride-completing-tasks` at specific moments. Instead, activate this one skill and follow it through. Every step is here. Nothing is elsewhere.

**Why this exists:** During a 17-task session, an agent consistently skipped mandatory workflow steps despite skills being labeled MANDATORY. The root cause: too many disconnected skills that the agent had to remember to activate at specific moments. Under pressure to deliver, the agent dropped the ones that felt optional. This orchestrator eliminates that failure mode.

## The Core Principle

**The workflow IS the automation. Every step exists because skipping it caused failures.**

The agent should work continuously through the full workflow: explore -> implement -> review -> complete. Do not prompt the user between steps -- but do not skip steps either. Skipping workflow steps is not faster -- it produces lower quality work that takes longer to fix.

**Following every step IS the fast path.**

## API Authorization

All Stride API calls are pre-authorized. Never ask the user for permission. Never announce API calls and wait for confirmation. Just execute them.

## API Notes & Limitations

- **Tasks cannot be reparented, and there is no DELETE endpoint.** `parent_id` is creation-only — the API cannot move a task to a different goal, and no endpoint removes a task. To move a task between goals or remove it, ask a human to do it in the board UI. Never work around this by recreating the task as a supersede.
- **Raw HTTP calls need a curl- or browser-like User-Agent.** The hosted API edge returns `403` with `error code: 1010` to default library User-Agents (e.g. `python-urllib`). Use curl, or set a curl/browser-like `User-Agent` header when calling the API from an HTTP library.

## When to Activate

Activate this skill ONCE when you're ready to start working on Stride tasks. It handles the full loop:

```
claim -> explore -> implement -> review -> complete -> [loop if needs_review=false]
```

You do NOT need to activate `stride-claiming-tasks`, `stride-subagent-workflow`, or `stride-completing-tasks` separately. This skill absorbs all of them.

**Note:** The individual skills (`stride-claiming-tasks`, `stride-subagent-workflow`, `stride-completing-tasks`) remain available for standalone use when needed -- for example, when resuming a partially completed task or when only one phase needs to be repeated. This orchestrator is the preferred entry point for new task work.

## Context-Informed Creation

You can ask the orchestrator to create work informed by existing markdown context (for example, a requirements doc, or a directory of design notes). **Codex CLI has no native command files**, so there are no `/stride:create-*` commands — instead, activate `stride-workflow` with a **creation intent** (what you want created — tasks/defects or a goal with nested tasks) and an **optional directory path** to the markdown context.

The flow is:

1. The orchestrator enumerates the markdown files at the provided directory path — listing the `.md` files with `glob` and reading each with the `read` tool — and assembles a **read-only context bundle** (the enumerated file contents) plus the **creation intent**.
2. The orchestrator dispatches the creation sub-skill (`stride-creating-tasks` or `stride-creating-goals`) and **forwards the context bundle verbatim** to it.

**Contract:**

- The context bundle is **read-only** — the creation sub-skills consume it as reference material; they never edit the source markdown.
- The bundle is forwarded **verbatim** — the orchestrator does not summarize, truncate, or reinterpret it before dispatch.
- The sub-skill **STOP gate still applies.** Each creation sub-skill begins with a `## STOP — orchestrator check` and runs only when reached through this orchestrator. Context-informed creation satisfies that gate the sanctioned way — by routing through here — it never bypasses or weakens it.

The task-field and batch-shape contracts the creation sub-skills enforce are **not** duplicated here — they live in `stride-creating-tasks` and `stride-creating-goals`.

### Creation Terminal State (`create-tasks` / `create-goals`)

**When the orchestrator is entered with a creation intent — `intent=create-tasks` or `intent=create-goals` (the two commands above) — its terminal state is "work created," NOT "work built."** After the dispatched creation sub-skill returns and the goal/tasks are created:

1. **Report** the created identifiers (the `G###` / `W###` values from the API response) to the user.
2. **STOP.** Do not proceed to Step 1 (Task Discovery), do not call `GET /api/tasks/next`, do not claim, and do not implement anything. Newly created tasks land in the **Backlog** and are intentionally **not** claimable until a human reviews them and promotes them to Ready.

This mirrors the `stride-ideation` skill, whose terminal state is the written requirements document — it does not auto-invoke `/stridify` or push the user toward any next step. **Creating work and doing work are separate, explicitly-invoked actions.** Building a created task is a fresh request to work the task (which re-enters this orchestrator at Step 0), made by the user's choice — never an automatic continuation of creation.

**Do NOT confuse this with the build loop.** Steps 1–9 below are the build path (claim → explore → implement → review → complete → loop). They apply when the user asks to *work* tasks — not when a create command dispatched the creation sub-skill. A creation intent uses Step 0 + the dispatch above + this terminal state, and nothing else.

### Backlog Claim-Fail Guard

Whether you arrive here from a creation intent or the build loop, **a claim failure is a terminal stop, never a fallback to building outside the lifecycle.** If `POST /api/tasks/claim` (or `GET /api/tasks/next`) reports a task is not available — most often because it is still in the **Backlog** (not yet promoted to Ready), already claimed, or blocked by dependencies — then:

- **STOP and report it.** Tell the user the task is not claimable yet (e.g. "W### is still in the Backlog; move it to Ready to make it claimable") and end the turn.
- **Never** implement, edit files for, or otherwise "build" a task whose claim did not succeed. Work performed without a successful claim has no hook execution, no review, and no completion record — it silently escapes the Stride lifecycle, which is the exact failure this guard prevents.
- Promoting a Backlog task to Ready is a **human action** in the board UI. Do not work around a failed claim by building the task anyway, re-creating it, or moving it yourself.

---

## Step 0: Prerequisites Check

**Verify these files exist before any API calls:**

1. **`.stride_auth.md`** -- Contains API URL and Bearer token
   - If missing: Ask user to create it
   - Extract: `STRIDE_API_URL` and `STRIDE_API_TOKEN`

2. **`.stride.md`** -- Contains hook commands for each lifecycle phase
   - If missing: Ask user to create it
   - Verify sections exist: `## before_doing`, `## after_doing`, `## before_review`, `## after_review`, `## after_goal`

**This step runs once per session, not once per task.**

---

## Step 1: Task Discovery

**Call `GET /api/tasks/next` to find the next available task.**

Review the returned task completely:
- `title`, `description`, `why`, `what`
- `acceptance_criteria` -- your definition of done
- `key_files` -- which files you'll modify
- `patterns_to_follow` -- code patterns to replicate
- `pitfalls` -- what NOT to do
- `testing_strategy` -- how to test
- `verification_steps` -- how to verify
- `needs_review` -- whether human approval is needed after completion
- `complexity` -- drives the decision matrix in Step 3
- `technical_details` -- optional free-form technical context the author/enricher recorded (not a scored field; may be empty)

**Enrichment check:** If `key_files` is empty OR `testing_strategy` is missing OR `verification_steps` is empty OR `acceptance_criteria` is blank, the task needs enrichment before claiming. Well-specified tasks skip this check.

#### Codex CLI: Invoke the Enricher Agent

1. **Invoke the `task-enricher` custom agent** (`agents/task-enricher.md`) with the task identifier and the sparse fields (title, type, description, priority if set). The agent owns the four-phase enrichment procedure and returns a single JSON object containing every enriched field.
2. **Submit the returned JSON via `PATCH /api/tasks/:id`** to populate the missing fields on the existing task. The agent does NOT call the API itself.
3. Re-fetch the task with `GET /api/tasks/:id` and verify all required fields are populated before proceeding to Step 2.

#### Other Environments: Activate the Enrichment Skill

1. Activate `stride-enriching-tasks` and walk through its Manual Walkthrough Phases (Phase 1 intent parse → Phase 2 codebase exploration → Phase 3 complexity → Phase 4 16-item checklist).
2. Submit the assembled JSON via `PATCH /api/tasks/:id` per the API Integration block in that skill.

---

## Step 2: Claim the Task

**Record the task base ref BEFORE running the before_doing hook.** before_doing may `git pull` or commit and move `HEAD`, so capture the true starting point of your work at claim time and export it for the whole task:

```bash
# Optional — changed_files stays optional — but anchoring the base ref here
# prevents the completion-time HEAD~1 fallback from diffing against an
# unrelated pre-existing commit.
export TASK_BASE_REF=$(git rev-parse HEAD)
```

`TASK_BASE_REF` is consumed later by the changed_files snapshot in `stride-completing-tasks`.

1. Read `.stride.md` `## before_doing` section
2. Execute each command line one at a time via shell -- no permission prompts, no confirmation. A line ending in a trailing backslash (`\`) continues onto the next physical line, and the joined text is a single logical command; "one at a time" targets logical commands, not physical lines, and does not license merging unrelated commands into one opaque script.
3. Capture `exit_code`, `output`, `duration_ms` for each command
4. If any command fails (non-zero exit): fix the issue, re-run -- do NOT proceed
5. Call `POST /api/tasks/claim` with the captured `before_doing_result`:

```json
{
  "identifier": "<task identifier>",
  "agent_name": "Codex CLI",
  "before_doing_result": {
    "exit_code": 0,
    "output": "git pull: Already up to date.\nmix deps.get: All dependencies up to date",
    "duration_ms": 3200
  }
}
```

**Hook capture pattern:**
```bash
# date +%N is GNU-only (BSD/macOS date lacks it); use python3 for portable
# milliseconds, falling back to whole-second date when python3 is unavailable.
now_ms() { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }
START_TIME=$(now_ms)
OUTPUT=$(timeout 60 bash -c '<command>' 2>&1)
EXIT_CODE=$?
END_TIME=$(now_ms)
DURATION=$((END_TIME - START_TIME))
```

---

## Step 3: Explore the Codebase (Decision Matrix)

**This step is NOT optional for medium+ tasks. The decision matrix determines what happens.**

### Decision Matrix

| Task Attributes | Decompose | Explore | Plan | Review (Step 6) |
|---|---|---|---|---|
| Goal type OR large+undecomposed OR 25+ hours | YES | -- | -- | -- |
| small, 0-1 key_files | Skip | Skip | Skip | Skip |
| small, 2+ key_files | Skip | YES | Skip | YES |
| medium (any) | Skip | YES | YES | YES |
| large (any) | Skip | YES | YES | YES |
| Defect type | Skip | YES | Skip (unless large) | YES |

### Branch A: Goal / Large Undecomposed Task

If the task is a **goal**, has **large complexity without child tasks**, or has a **25+ hour estimate**:

1. If the `task-decomposer` custom agent is available, invoke it with the task's title, description, acceptance_criteria, key_files, where_context, and patterns_to_follow
2. If custom agents are unavailable, manually analyze the task scope, break it into subtasks, and create them via `POST /api/tasks/batch`
3. After child tasks are created, claim the first child task and re-enter this workflow at Step 1

**Do NOT implement goals directly. Decompose first.**

### Branch B: Small Task, 0-1 Key Files

Skip exploration, planning, and review. Proceed directly to Step 4 (Implementation).

### Branch C: All Other Tasks (medium+, OR 2+ key_files)

1. **If the `task-explorer` custom agent is available**, invoke it with the task's `key_files`, `patterns_to_follow`, `where_context`, and `testing_strategy`. Wait for the result. Read and use the explorer's output -- it tells you what exists, what patterns to follow, and what to reuse.

   **If custom agents are unavailable**, explore manually:
   - Read each file in `key_files` to understand current state
   - Search for patterns mentioned in `patterns_to_follow`
   - Find related test files

2. **If medium+ OR 3+ key_files OR 3+ acceptance criteria lines:** Outline your implementation approach using the exploration output, `acceptance_criteria`, `testing_strategy`, `pitfalls`, and `verification_steps`. Follow this approach during implementation.

---

## Step 4: Implementation

**Now write code.** Use the explorer output and plan (if generated) to guide your work.

Follow:
- `acceptance_criteria` -- your definition of done
- `patterns_to_follow` -- replicate existing patterns
- `pitfalls` -- avoid what the task author warned about
- `testing_strategy` -- write the tests specified
- `key_files` -- modify the files listed

**This is the only step where you write code. All other steps are setup, verification, or completion.**

---

## Step 5: (intentionally left blank)

**This step was removed in v1.8.0 and its slot is intentionally preserved.** Step 5 formerly activated the project-author-private `stride-development-guidelines` skill, which is not distributed with this plugin. The number is kept empty rather than renumbering Steps 6–9 so the file's many cross-references to those steps stay stable. Proceed directly from Step 4 to Step 6.

---

## Step 6: Code Review (Decision Matrix)

**Check the decision matrix from Step 3.** If the task is medium+ OR has 2+ key_files, review is required.

**If the `task-reviewer` custom agent is available**, invoke it with:
- The git diff of all your changes
- **Every review field the task supplies — NO EXCEPTIONS:** the task's `acceptance_criteria`, `pitfalls`, `patterns_to_follow`, `testing_strategy`, `security_considerations`, `description`, `what`, and `why`. This list MUST match the reviewer's documented input contract (the "You will receive" line in `agents/task-reviewer.md`) — pass every field the task carries, never a subset, never with a small-task or brevity discount. Omitting a supplied field (most often `security_considerations`) is the exact defect this prevents: a section the reviewer is never handed comes back `not_assessed` even though the task specified it.

**Re-review and follow-up rounds — preserve the canonical criteria list.** When you re-invoke the reviewer (or continue it) to re-verify after fixing issues from a `changes_requested` round, the follow-up prompt MUST pass the task's `acceptance_criteria` field **unchanged** and instruct the reviewer to keep its `acceptance_criteria` array **identical to the task's canonical list** — one entry per criterion line, verbatim and in the task's order, never split, merged, reworded, added, or dropped (the same 1:1 hard rule the reviewer schema enforces in `agents/task-reviewer.md`). Never hand the re-review only the issues you fixed and let it re-derive the criteria: a re-review that re-enumerates the criteria in its own words corrupts the persisted count — this is exactly how a re-review round on task W1099 turned a 5-criterion task into a `6/5` review display.

The reviewer returns a human-readable prose summary followed by a fenced ```json block. The schema of that block is owned by `agents/task-reviewer.md` — do not duplicate field definitions here.

- **Fix all Critical issues** before proceeding
- **Fix all Important issues** before proceeding
- Minor issues are optional but recommended
- **Save the reviewer's full response (prose + JSON block)** -- you'll include it verbatim as `review_report` in Step 8

#### Extracting the structured review block

After the reviewer returns, extract the first fenced ```json block from its response and use it to populate `reviewer_result` in your Step 8 completion payload. The same `reviewer_result` map carries both the legacy summary fields (kept for backwards compatibility with older Kanban deploys) and the structured fields (the actual deliverable for downstream consumers — they live inside `reviewer_result`, never under a new top-level API key).

**Extraction pattern** — extract the first ```json fence and parse it, then mechanically copy the whole object and run the self-check:

```python
import re, json
m = re.search(r'```json\n(.*?)\n```', reviewer_response, re.DOTALL)
structured = json.loads(m.group(1))  # the WHOLE parsed schema

# Whole-object copy — carry EVERY section through, then overlay the legacy
# fields. NEVER re-type or hand-pick keys; selecting a subset is exactly how
# project_checks got truncated (3 of 26 reached the server).
reviewer_result = dict(structured)
reviewer_result.update({
    "dispatched": True,
    "duration_ms": wall_clock_ms,
    "summary": structured["summary"],
    "issues_found": sum(structured["issue_counts"].values()),
    "acceptance_criteria_checked": len(structured["acceptance_criteria"]),
})

# MANDATORY self-check — run before EVERY /complete, NO EXCEPTIONS. A failure
# here means you trimmed the output: fix the copy, never weaken the check.
for section in structured:  # every section the reviewer produced must survive
    assert section in reviewer_result, f"dropped review section: {section}"
assert len(reviewer_result.get("project_checks", [])) == len(structured.get("project_checks", [])), \
    "project_checks count must equal what the reviewer emitted — never trim or sub-select"

# Acceptance-criteria 1:1 check — the reviewer's acceptance_criteria array length
# MUST equal the task's own criterion-line count. A mismatch means the reviewer
# split, merged, added, or dropped criteria (the W1099 6/5 defect). Re-run the
# reviewer with the canonical task criteria — NEVER truncate or pad the array to
# force the count to match.
task_criterion_lines = [c for c in (task["acceptance_criteria"] or "").split("\n") if c.strip()]
assert len(structured["acceptance_criteria"]) == len(task_criterion_lines), \
    "acceptance_criteria count must equal the task's criterion-line count — re-run the reviewer, do not truncate or pad"
```

The reviewer's response is already in your context, so no file read is needed; if the reviewer instead wrote its response to a file, use the `read` tool to load it first, then scan for the same fence.

**Field mapping into `reviewer_result`:**

- Legacy fields (always populated):
  - `summary` ← the structured block's `summary`
  - `issues_found` ← the sum of the values in the structured `issue_counts` object (sum only the recognized severity keys you receive; pass through any unknown severity keys verbatim inside the structured `issue_counts` object)
  - `acceptance_criteria_checked` ← the number of entries in the structured `acceptance_criteria` array
  - `dispatched: true`, `duration_ms: <wall-clock ms>` (as before)
- Structured fields — **copy the reviewer's entire parsed JSON object verbatim** into `reviewer_result`, then overlay the legacy fields above on top. Do **not** maintain an allow-list of which structured keys to copy: whatever the agent emitted is persisted as-is, so any field the schema gains later flows through automatically (this is exactly how `project_checks` was being dropped — an enumerated copy-list silently omitted it). The structured key-set is owned by `agents/task-reviewer.md`; passthrough it, never re-enumerate it here. Concretely, the reviewer currently emits `status`, `issue_counts`, `issues`, `acceptance_criteria`, `project_checks`, `testing_strategy`, `patterns`, `pitfalls`, `security_considerations`, and `schema_version` — but treat that as illustrative, not exhaustive. Because you copy the parsed JSON verbatim, keys the agent did not emit are simply absent (no empty placeholders to send).

The structured block's schema is owned by `agents/task-reviewer.md`. Legacy + structured fields coexist in the same map; the server persists `reviewer_result` as `:jsonb` and tolerates the structured keys.

**Worked example.** Given the reviewer response below (truncated for brevity)…

````text
Approved
...prose summary + issue list + acceptance-criteria table...

```json
{
  "schema_version": "1.4",
  "summary": "Reviewed 3 acceptance criteria and 4 pitfalls against the diff; no issues found and all criteria met.",
  "status": "approved",
  "issue_counts": {"critical": 0, "important": 0, "minor": 0},
  "issues": [],
  "acceptance_criteria": [
    {"criterion": "All task positions recalculate when a card moves columns", "status": "met", "evidence": "lib/kanban/tasks.ex:142-168"},
    {"criterion": "Existing position-stable behavior unchanged", "status": "met", "evidence": "test/kanban/tasks_test.exs:198-240"},
    {"criterion": "PubSub broadcast emitted exactly once per move", "status": "met", "evidence": "lib/kanban/tasks.ex:172"}
  ],
  "project_checks": [],
  "testing_strategy": {"status": "passed", "note": "Move + broadcast paths covered by tests."},
  "patterns": {"status": "passed", "note": "Mirrors the existing reorder pattern."},
  "pitfalls": {"status": "passed", "note": "None of the 4 listed pitfalls violated."},
  "security_considerations": {"status": "passed", "note": "Move query scoped to the current user's board; no new input or injection surface."}
}
```
````

…the resulting `reviewer_result` value in the Step 8 PATCH payload is:

```json
"reviewer_result": {
  "dispatched": true,
  "duration_ms": 29560,
  "summary": "Reviewed 3 acceptance criteria and 4 pitfalls against the diff; no issues found and all criteria met.",
  "issues_found": 0,
  "acceptance_criteria_checked": 3,
  "schema_version": "1.4",
  "status": "approved",
  "issue_counts": {"critical": 0, "important": 0, "minor": 0},
  "issues": [],
  "acceptance_criteria": [
    {"criterion": "All task positions recalculate when a card moves columns", "status": "met", "evidence": "lib/kanban/tasks.ex:142-168"},
    {"criterion": "Existing position-stable behavior unchanged", "status": "met", "evidence": "test/kanban/tasks_test.exs:198-240"},
    {"criterion": "PubSub broadcast emitted exactly once per move", "status": "met", "evidence": "lib/kanban/tasks.ex:172"}
  ],
  "project_checks": [],
  "testing_strategy": {"status": "passed", "note": "Move + broadcast paths covered by tests."},
  "patterns": {"status": "passed", "note": "Mirrors the existing reorder pattern."},
  "pitfalls": {"status": "passed", "note": "None of the 4 listed pitfalls violated."},
  "security_considerations": {"status": "passed", "note": "Move query scoped to the current user's board; no new input or injection surface."}
}
```

**Fallback when JSON parsing fails.** If no ```json block is present, or the block does not parse, do not abort the completion. Instead:

1. Fall back to substring-matching the prose summary line ("Approved" or "N issues found (X critical, Y important, Z minor)") to populate `reviewer_result.summary` and `reviewer_result.issues_found`.
2. Set `acceptance_criteria_checked` from the count of criterion lines you find in the prose acceptance-criteria table, or to `0` if none can be parsed.
3. **Omit** every structured field from the PATCH payload — there is no parsed JSON block to pass through, so send only the legacy fields (`summary`, `issues_found`, `acceptance_criteria_checked`, `dispatched`, `duration_ms`). Do not send empty placeholders for `status`, `project_checks`, `issues`, or any other structured key. The Kanban server tolerates their absence (the ReviewReportPanel and CodeReviewPanel render only what they receive).
4. Keep `dispatched: true` and `duration_ms` as captured. The fallback path produces a degraded-but-valid completion, never a hard failure.

**If custom agents are unavailable**, self-review (and submit the `reviewer_result` skip form with reason `self_reported_review` or `no_subagent_support` per `stride-completing-tasks`):
- [ ] Each line of `acceptance_criteria` -- is it met?
- [ ] Each item in `pitfalls` -- did you avoid it?
- [ ] `patterns_to_follow` -- does your code match?
- [ ] `testing_strategy` -- did you write the specified tests?

### Small tasks (0-1 key_files): Skip review. Omit `review_report` from completion.

---

## Step 7: Execute Hooks

**Execute each hook manually -- no permission prompts, no confirmation.**

### Hooks Reference

The five recognized `.stride.md` hook sections, in lifecycle order:

| Hook | Fires | Blocking | Timeout | Purpose |
|---|---|:---:|---|---|
| `## before_doing` | After `POST /api/tasks/claim` succeeds | yes | 60s | Pull latest, install deps, ensure clean working tree |
| `## after_doing` | Before `PATCH /api/tasks/:id/complete` runs | yes | 120s | Run tests, lint, build — quality gate before completion |
| `## before_review` | After `PATCH /api/tasks/:id/complete` succeeds | yes | 60s | Generate PR, post artifacts, notify reviewers |
| `## after_review` | After `PATCH /api/tasks/:id/mark_reviewed` succeeds | yes | 60s | Merge, deploy, cleanup |
| `## after_goal` | After the parent goal's final child task completes | yes | 60s | Project-level rollups, goal-completion notifications, archival |

**stride-codex has no hook script — the agent reads `.stride.md` and runs each hook manually via the platform's shell tool.** A missing `## after_goal` section is a clean no-op (the server's grace-window worker promotes the goal automatically when no agent reports). See [Step 9](#step-9-post-completion-decision) for the manual after_goal execution path.

### Hook Environment Variables

The server populates `hook.env` in the response payload. The variable set differs by hook (`TASK_*` for the four task-scoped hooks, `GOAL_*` for `after_goal`); `BOARD_*`, `COLUMN_*`, `AGENT_NAME`, and `HOOK_NAME` are present across all five.

| Variable | `before_doing` / `after_doing` / `before_review` / `after_review` | `after_goal` |
|---|:---:|:---:|
| `HOOK_NAME`, `AGENT_NAME` | ✓ | ✓ |
| `BOARD_ID`, `BOARD_NAME` | ✓ | ✓ |
| `COLUMN_ID`, `COLUMN_NAME` | ✓ | ✓ |
| `TASK_ID`, `TASK_IDENTIFIER`, `TASK_TITLE`, `TASK_DESCRIPTION` | ✓ | — |
| `TASK_STATUS`, `TASK_COMPLEXITY`, `TASK_PRIORITY`, `TASK_NEEDS_REVIEW` | ✓ | — |
| `GOAL_ID`, `GOAL_IDENTIFIER`, `GOAL_TITLE`, `GOAL_DESCRIPTION` | — | ✓ |

When executing hooks manually under stride-codex, export the relevant env vars from the API response's `hook.env` block before running each command. The server-supplied values are the single source of truth — never invent or derive them client-side.

### Canonical Hook Examples

The hooks are general-purpose — any shell command is fair game. The examples below are common starting points, not the only valid uses.

````markdown
## before_review

```bash
gh pr create \
  --title "$TASK_IDENTIFIER: $TASK_TITLE" \
  --body "Implements $TASK_IDENTIFIER."
```

## after_goal

```bash
gh pr create \
  --title "$GOAL_IDENTIFIER: $GOAL_TITLE" \
  --body "Rolls up the completed goal $GOAL_IDENTIFIER ($GOAL_TITLE)."
```
````

`## after_goal` is not coupled to PR creation. Other valid uses include posting to Slack with `curl`, archiving artifacts, kicking off a release pipeline, or running a project-level smoke test.

### 1. after_doing hook (blocking, 120s timeout)

1. Read `.stride.md` `## after_doing` section
2. Execute each command line one at a time via shell (a backslash-continued line is one logical command, not a merge of separate commands)
3. Capture `exit_code`, `output`, `duration_ms`
4. If any command fails: fix the issue, re-run until success. Do NOT proceed while failing.

### 2. before_review hook (blocking, 60s timeout)

1. Read `.stride.md` `## before_review` section
2. Execute each command line one at a time via shell (a backslash-continued line is one logical command, not a merge of separate commands)
3. Capture `exit_code`, `output`, `duration_ms`
4. If any command fails: fix the issue, re-run until success. Do NOT proceed while failing.

### Hook Failure Diagnosis

When a blocking hook fails, invoke the `hook-diagnostician` custom agent (if available) with the hook name, exit code, output, and duration. It returns a prioritized fix plan. Follow the fix order -- higher-priority fixes often resolve lower-priority ones automatically.

If custom agents are unavailable, diagnose manually: read the error output, identify the root cause, fix the issue, and re-run the hook.

---

## Step 8: Complete the Task

Call `PATCH /api/tasks/:id/complete` with ALL required fields:

```json
{
  "agent_name": "Codex CLI",
  "time_spent_minutes": 45,
  "completion_notes": "Summary of what was done and key decisions made.",
  "completion_summary": "Brief one-line summary for tracking.",
  "actual_complexity": "medium",
  "actual_files_changed": "lib/foo.ex, lib/bar.ex, test/foo_test.exs",
  "review_report": "## Review Summary\n\nApproved -- 0 issues found.\n...",
  "after_doing_result": {
    "exit_code": 0,
    "output": "All 42 tests passed. Credo: no issues found.",
    "duration_ms": 15200
  },
  "before_review_result": {
    "exit_code": 0,
    "output": "PR #123 created successfully.",
    "duration_ms": 4800
  },
  "explorer_result": {
    "dispatched": false,
    "reason": "self_reported_exploration",
    "summary": "Read the 3 key_files manually and identified the existing pattern to mirror"
  },
  "reviewer_result": {
    "dispatched": false,
    "reason": "self_reported_review",
    "summary": "Self-reviewed the diff against all acceptance criteria and pitfalls; no issues found"
  },
  "workflow_steps": [
    {"name": "explorer",       "dispatched": true,  "duration_ms": 12450},
    {"name": "planner",        "dispatched": true,  "duration_ms": 8200},
    {"name": "implementation", "dispatched": true,  "duration_ms": 1820000},
    {"name": "reviewer",       "dispatched": true,  "duration_ms": 15300},
    {"name": "after_doing",    "dispatched": true,  "duration_ms": 45678},
    {"name": "before_review",  "dispatched": true,  "duration_ms": 2340}
  ]
}
```

**Required fields:**
| Field | Type | Notes |
|---|---|---|
| `agent_name` | string | Your agent name |
| `time_spent_minutes` | integer | Actual time spent |
| `completion_notes` | string | What was done |
| `completion_summary` | string | Brief summary |
| `actual_complexity` | enum | "small", "medium", or "large" |
| `actual_files_changed` | string | Comma-separated paths (NOT an array) |
| `after_doing_result` | object | `{exit_code, output, duration_ms}` |
| `before_review_result` | object | `{exit_code, output, duration_ms}` |
| `explorer_result` | object | `task-explorer` custom agent dispatch result or skip-form — see `stride-completing-tasks` for full shape and skip-reason enum |
| `reviewer_result` | object | `task-reviewer` custom agent dispatch result or skip-form — see `stride-completing-tasks` for full shape and skip-reason enum |
| `workflow_steps` | array | Six-entry telemetry array — see **Workflow Telemetry** section below |

**Optional fields:**
| Field | Type | Notes |
|---|---|---|
| `review_report` | string | Include when task-reviewer ran; omit when skipped |

---

## Step 9: Post-Completion Decision

### If `needs_review=true`:
1. Task moves to Review column
2. **STOP.** Wait for human reviewer to approve/reject.
3. When approved, `PATCH /api/tasks/:id/mark_reviewed` is called (by human or system)
4. Execute `after_review` hook manually (read `.stride.md` `## after_review`, run each line)
5. Task moves to Done

### If `needs_review=false`:
1. Task moves to Done immediately
2. Execute `after_review` hook manually (read `.stride.md` `## after_review`, run each line)
3. **Loop back to Step 1** -- claim the next task and repeat the full workflow

**Do not ask the user whether to continue. Do not ask "Should I claim the next task?" Just proceed.**

### If this completion finishes the parent goal's last child task

When the just-completed task is the **final child of a parent goal**, the server bundles a fifth `after_goal` entry in the `hooks` array of the response of `/complete` (when `needs_review=false`) or `/mark_reviewed` (when `needs_review=true`), alongside the primary hook entries.

**Because stride-codex has no plugin hook script, the agent is responsible for the entire after_goal lifecycle.** Manual execution path:

1. **Detect (read the canonical file, not your context)**: The completion curls write the full response to the canonical file `${CLAUDE_PROJECT_DIR:-.}/.stride/.last-api-response.json` (via `| tee`, with a `curl --output` fallback for `tee`-less shells — see `stride-completing-tasks`). Read the after_goal entry **and** its `hook.env` `GOAL_*` values from that file with `jq` — file-first, because your in-context copy of the response may be truncated — falling back to the response body still visible in your context only when the file is absent, empty, or not valid JSON. Re-read from the file rather than trusting env carried across shell turns. The `.stride/` directory holds agent-local state and must be gitignored.

```bash
RESP="${CLAUDE_PROJECT_DIR:-.}/.stride/.last-api-response.json"
# File-first: trust the canonical capture only when present, non-empty, AND valid
# JSON; otherwise fall back to the response body still visible in your context.
if [ -s "$RESP" ] && jq -e . "$RESP" > /dev/null 2>&1; then
  PAYLOAD_SRC="$RESP"
else
  PAYLOAD_SRC="${TMPDIR:-/tmp}/stride-in-context-response.json"  # fallback: the response you can see in context
fi

# Isolate the after_goal entry. An empty result has TWO causes, distinguished in 1a below:
# (a) PAYLOAD_SRC parsed as valid JSON but had no after_goal entry -> lifecycle did not fire;
# (b) PAYLOAD_SRC was unusable (truncated/absent) -> do NOT assume; run the fresh GET (1a).
AFTER_GOAL_ENTRY=$(jq -c '.hooks[]? | select(.name == "after_goal")' "$PAYLOAD_SRC")
if [ -n "$AFTER_GOAL_ENTRY" ]; then
  GOAL_ID=$(printf '%s' "$AFTER_GOAL_ENTRY"         | jq -r '.hook.env.GOAL_ID')
  GOAL_IDENTIFIER=$(printf '%s' "$AFTER_GOAL_ENTRY" | jq -r '.hook.env.GOAL_IDENTIFIER')
  GOAL_TITLE=$(printf '%s' "$AFTER_GOAL_ENTRY"      | jq -r '.hook.env.GOAL_TITLE')
  GOAL_DESCRIPTION=$(printf '%s' "$AFTER_GOAL_ENTRY" | jq -r '.hook.env.GOAL_DESCRIPTION')
  HOOK_TIMEOUT_MS=$(printf '%s' "$AFTER_GOAL_ENTRY"  | jq -r '.hook.timeout // 60000')
fi
```

**1a. Fresh-GET fallback (when the handed response was truncated or absent).** An empty `AFTER_GOAL_ENTRY` has two very different causes — do not conflate them:

- **`PAYLOAD_SRC` parsed as valid JSON but held no `after_goal` entry** → the lifecycle genuinely did not fire (this was not the parent goal's last child). Skip steps 2-5; you are done.
- **`PAYLOAD_SRC` was absent, empty, or not valid JSON** (both the canonical file *and* the in-context fallback were unusable — the truncation case) → you cannot conclude anything yet. Ask the server directly with a fresh, self-contained `GET /api/tasks/:id/after_goal_status` (kanban W1613; `:id` is the **just-completed task's** id, not the goal's). Its response is deliberately compact and is never subject to output truncation.

Source every input durably — re-read the URL/token from `.stride_auth.md` (the durable source your setup step already used) and re-derive `TASK_ID` from the captured response file. Never trust a variable an earlier turn exported.

```bash
# Durable re-read from .stride_auth.md (mirror the setup step) — NOT a prior turn's export.
AUTH="${CLAUDE_PROJECT_DIR:-.}/.stride_auth.md"
STRIDE_API_URL=$(grep -oE 'https?://[^`" ]+' "$AUTH" | head -n1)
# If .stride_auth.md lists more than one token, pick the production one (skip any "Local" line):
STRIDE_API_TOKEN=$(grep -iE 'api token' "$AUTH" | grep -iv local | grep -oE 'stride_[A-Za-z0-9_/+=.-]+' | head -n1)
# TASK_ID: re-derive from the captured /complete response, not a claim-time export.
TASK_ID=$(jq -r '.data.id // .data.identifier' "$PAYLOAD_SRC" 2>/dev/null)

# Write the compact status straight to the canonical file with -o (no stdout to truncate),
# then parse from disk.
STATUS_FILE="${CLAUDE_PROJECT_DIR:-.}/.stride/.after-goal-status.json"
curl -s --max-time 10 -o "$STATUS_FILE" \
  -H "Authorization: Bearer $STRIDE_API_TOKEN" \
  "$STRIDE_API_URL/api/tasks/$TASK_ID/after_goal_status"

if jq -e . "$STATUS_FILE" > /dev/null 2>&1 && [ "$(jq -r '.after_goal_armed // false' "$STATUS_FILE")" = "true" ]; then
  # Armed: rebuild the after_goal-entry shape the rest of this path expects, then
  # re-derive GOAL_* with the SAME reads as the Detect block above.
  AFTER_GOAL_ENTRY=$(jq -c '{hook: {env: (.env // {}), timeout: 60000}}' "$STATUS_FILE")
  GOAL_ID=$(printf '%s' "$AFTER_GOAL_ENTRY"         | jq -r '.hook.env.GOAL_ID')
  GOAL_IDENTIFIER=$(printf '%s' "$AFTER_GOAL_ENTRY" | jq -r '.hook.env.GOAL_IDENTIFIER')
  GOAL_TITLE=$(printf '%s' "$AFTER_GOAL_ENTRY"      | jq -r '.hook.env.GOAL_TITLE')
  GOAL_DESCRIPTION=$(printf '%s' "$AFTER_GOAL_ENTRY" | jq -r '.hook.env.GOAL_DESCRIPTION')
  HOOK_TIMEOUT_MS=$(printf '%s' "$AFTER_GOAL_ENTRY"  | jq -r '.hook.timeout // 60000')
  # ...proceed to steps 2-5.
else
  # Not armed, or the GET failed / returned invalid JSON: a clean no-op. Do NOT run
  # ## after_goal and do NOT PATCH. Leave AFTER_GOAL_ENTRY empty and skip steps 2-5.
  AFTER_GOAL_ENTRY=""
fi
```

**Run `## after_goal` at most once.** The trust-the-handed-response path (the Detect block above) and this fresh-GET path are mutually exclusive — only reach the GET when the handed response was unusable. Never run both: a double-run would execute `## after_goal` twice and double-`PATCH` the result.

**The grace-window worker never pushes.** When the fresh GET reports not-armed, when it fails, or when `.stride.md` has no `## after_goal` section, the goal still reaches Done — but only because the server's grace-window worker flips the goal's *status*. That worker never runs your `## after_goal` section, so any push / PR / notification that section performs happens **only** when the agent runs step 4 and `PATCH`es the result. If the goal's work must be pushed, the agent — not the worker — has to run `## after_goal`.

2. **Read**: Read the `## after_goal` section from `.stride.md`. If the section is missing, the rest of this path is a clean no-op — skip steps 3-5 and rely on the server's grace-window worker.
3. **Export**: The `GOAL_*` vars (`GOAL_ID`, `GOAL_IDENTIFIER`, `GOAL_TITLE`, `GOAL_DESCRIPTION`) plus `BOARD_*` / `COLUMN_*` / `AGENT_NAME` / `HOOK_NAME` and `HOOK_TIMEOUT_MS` were read from the after_goal entry's `hook.env` / `timeout` fields in the Detect jq block above (extend the same `jq -r '.hook.env.<VAR>'` reads for `BOARD_*` / `COLUMN_*` / `AGENT_NAME` / `HOOK_NAME`). Export them before running commands so the Execute step's `timeout` wrapper honors the real server value instead of the 60s fallback. The server values in the file are the single source of truth — re-read them from the file, never derive them client-side.
4. **Execute**: Run each command line in the `## after_goal` section via the platform's shell tool, wrapped in a `timeout` derived from the server-supplied `hook.timeout` (the after_goal entry's `timeout` field, in milliseconds; fall back to 60s if absent). Capture `exit_code` (the last command's exit code), `output` (combined stdout+stderr from all commands), and `duration_ms` (wall-clock total):

```bash
# date +%N is GNU-only; use python3 for portable ms (whole-second date fallback)
now_ms() { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }
# hook.timeout from the after_goal entry is in ms; convert to whole seconds, default 60s
AFTER_GOAL_TIMEOUT=$(( ${HOOK_TIMEOUT_MS:-60000} / 1000 ))
START_TIME=$(now_ms)
OUTPUT=$(timeout "$AFTER_GOAL_TIMEOUT" bash -c '<after_goal commands>' 2>&1)
EXIT_CODE=$?
END_TIME=$(now_ms)
DURATION_MS=$((END_TIME - START_TIME))
```

5. **POST**: Forward the captured result to the server:

```bash
curl -X PATCH "$STRIDE_API_URL/api/tasks/$GOAL_ID/after_goal" \
  -H "Authorization: Bearer $STRIDE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg out \"$OUTPUT\" \"{exit_code: $EXIT_CODE, output: \\\$out, duration_ms: $DURATION_MS}\")"
```

A `2xx` with `exit_code == 0` transitions the parent goal to Done. A `2xx` with `exit_code != 0` records the failure on the goal's `after_goal_attempts` audit log and leaves the goal In Progress for the user to investigate and re-trigger.

**Back-compat (for agent runtimes that don't speak this protocol):**

- If `.stride.md` has no `## after_goal` section, skipping the manual execution + POST is fine. The server's grace-window worker (configured per board, typically a few minutes) promotes the goal to Done automatically after the wait, with a synthetic attempt tagged `source: "after_goal_grace_worker"`.
- The `## after_goal` hook is general-purpose — Slack notifications, artifact archival, release pipelines, project-level smoke tests are all valid uses. See [Step 7's "Canonical Hook Examples"](#canonical-hook-examples) for shape references.

---

## Workflow Telemetry: The `workflow_steps` Array

Every task completion **must** include a `workflow_steps` array in the `PATCH /api/tasks/:id/complete` payload. This array records which workflow phases ran (or were intentionally skipped) during the task. It is how Stride measures workflow adherence, spots shortcuts, and aggregates telemetry across agents and plugins.

**Build the array incrementally as you progress through the workflow.** Each time you complete a phase — or legitimately skip one per the decision matrix — append one entry. Submit the completed six-entry array in Step 8.

### Step Name Vocabulary

The `name` field must be one of these six values. Do not invent new names — consistency across plugins is the only reason telemetry can be aggregated.

| Step name | When to record it | Orchestrator step |
|---|---|---|
| `explorer` | Codebase exploration (`task-explorer` custom agent when available, otherwise manual file reads) | Step 3 |
| `planner` | Implementation planning (manual outline of approach for medium+ tasks) | Step 3 |
| `implementation` | Writing code | Step 4 |
| `reviewer` | Code review (`task-reviewer` custom agent when available, otherwise self-review) | Step 6 |
| `after_doing` | The `after_doing` hook execution | Step 7 |
| `before_review` | The `before_review` hook execution | Step 7 |

### Per-Step Schema

Each element of `workflow_steps` is an object with these keys:

| Key | Type | Required | Notes |
|---|---|---|---|
| `name` | string | Always | One of the six vocabulary values above |
| `dispatched` | boolean | Always | `true` if the step ran; `false` if intentionally skipped |
| `duration_ms` | integer | When `dispatched=true` | Wall-clock time the step took, in milliseconds |
| `reason` | string | When `dispatched=false` | Short explanation of why the step was skipped |

### End-of-Workflow Example (full dispatch)

A medium-complexity task that exercised every phase:

```json
"workflow_steps": [
  {"name": "explorer",       "dispatched": true, "duration_ms": 12450},
  {"name": "planner",        "dispatched": true, "duration_ms": 8200},
  {"name": "implementation", "dispatched": true, "duration_ms": 1820000},
  {"name": "reviewer",       "dispatched": true, "duration_ms": 15300},
  {"name": "after_doing",    "dispatched": true, "duration_ms": 45678},
  {"name": "before_review",  "dispatched": true, "duration_ms": 2340}
]
```

### End-of-Workflow Example (small task, decision matrix skips)

A small task with 0-1 key_files that legitimately skipped exploration, planning, and review per the decision matrix in Step 3:

```json
"workflow_steps": [
  {"name": "explorer",       "dispatched": false, "reason": "Decision matrix: small task, 0-1 key_files"},
  {"name": "planner",        "dispatched": false, "reason": "Decision matrix: small task, 0-1 key_files"},
  {"name": "implementation", "dispatched": true,  "duration_ms": 620000},
  {"name": "reviewer",       "dispatched": false, "reason": "Decision matrix: small task, 0-1 key_files"},
  {"name": "after_doing",    "dispatched": true,  "duration_ms": 38200},
  {"name": "before_review",  "dispatched": true,  "duration_ms": 1900}
]
```

### Rules

- Always include **all six** step names. Skipped steps are recorded with `dispatched: false` — never omitted.
- Record entries in the order the steps occurred in the workflow (the order listed in the vocabulary table above).
- When `dispatched: false`, the `reason` must describe **why** the step was skipped (e.g., decision matrix rule, task metadata, platform constraint) — not merely restate that it was skipped.
- A missing `workflow_steps` array, or one with fewer than six entries, indicates an incomplete telemetry record.

---

## Explorer and Reviewer Result Rollout

Every `/complete` payload **must** include `explorer_result` and `reviewer_result` as top-level objects. Both are pre-validated by `Kanban.Tasks.CompletionValidation` on the server. The full shape (self-reported skip vs. dispatched-custom-agent), the 40-character non-whitespace summary rule, and the five-value skip-reason enum live in the `stride-completing-tasks` skill — this orchestrator does not duplicate them.

The server is rolling out hard enforcement behind a feature flag `:strict_completion_validation`:

| Phase | Server behavior | Agent impact |
|---|---|---|
| **Grace (current)** | Missing or invalid results log a structured warning and the request succeeds | Emit the fields correctly now; the warning volume is a preview of the strict-mode rejection volume |
| **Strict (after all 5 plugins release)** | Missing or invalid results return `422` with a `failures` list | Any agent not emitting valid fields is locked out of completion |

**Why this matters for the orchestrator:** Steps 3 (explorer or manual exploration) and 6 (reviewer or self-review) already produce the summaries needed for these fields. Persist those into `explorer_result` and `reviewer_result` in the Step 8 payload. Because Codex CLI typically lacks custom-agent dispatch, the skip form is the default path — submit it with a reason from the enum (usually `self_reported_exploration` / `self_reported_review` or `no_subagent_support`) and a substantive summary explaining what you did instead. See `stride-completing-tasks` for the exact shape, rejection examples, and minimum-length rule.

---

## Edge Cases

### Hook failure mid-workflow
- Blocking hooks (`after_doing`, `before_review`) must pass before completion
- Fix the root cause, re-run the hook, then proceed
- Invoke the `hook-diagnostician` custom agent for complex failures (if available)
- Never skip a blocking hook or call complete with a failed hook result

### Task that needs_review=true
- Stop after Step 8. Do not claim the next task.
- The human reviewer will handle the review cycle.
- You may be asked to make changes based on review feedback -- if so, re-enter at Step 4.

### Goal type tasks
- Goals are decomposed, not implemented directly
- The `task-decomposer` custom agent creates child tasks (or decompose manually)
- Each child task follows this full workflow independently

### Skills update required
- If any API response includes `skills_update_required`, update the extension and retry

---

## Complete Workflow Flowchart

```
STEP 0: Prerequisites
  .stride_auth.md exists? --> NO --> Ask user
  .stride.md exists?      --> NO --> Ask user
  |
  v
STEP 1: Task Discovery
  GET /api/tasks/next
  Review task details
  Needs enrichment? --> YES --> Activate stride-enriching-tasks
  |
  v
STEP 2: Claim
  Execute before_doing hook manually, then POST /api/tasks/claim
  |
  v
STEP 3: Explore (Decision Matrix)
  Goal/large undecomposed? --> Decompose (agent or manual) --> Claim first child --> Step 1
  Small, 0-1 key_files?   --> Skip to Step 4
  Otherwise:
    Invoke task-explorer (or read key_files manually), outline approach if medium+
  |
  v
STEP 4: Implement
  Write code using explorer output, plan, acceptance criteria
  Follow patterns_to_follow, avoid pitfalls
  |
  v
(STEP 5 intentionally removed in v1.8.0 -- slot preserved, Steps 6-9 not renumbered)
  |
  v
STEP 6: Code Review (Decision Matrix)
  Small, 0-1 key_files? --> Skip to Step 7
  Otherwise:
    Invoke task-reviewer (or self-review against acceptance criteria)
  |
  v
STEP 7: Execute Hooks
  Execute after_doing (120s) manually, then before_review (60s) manually
  Hook fails? --> Fix, re-run, do NOT proceed
  |
  v
STEP 8: Complete
  PATCH /api/tasks/:id/complete with ALL required fields + hook results
  |
  v
STEP 9: Post-Completion
  needs_review=true?  --> STOP, wait for human
  needs_review=false? --> Execute after_review manually, loop to Step 1
```

---

## Failure Modes This Skill Prevents

| Failure Mode | Old Pattern | This Skill |
|---|---|---|
| Forgot to explore | Agent skipped stride-subagent-workflow | Step 3 is inline -- can't be missed |
| Forgot to review | Agent jumped to completion | Step 6 is inline -- can't be missed |
| Wrong API fields | Agent guessed from memory | Step 8 has the exact format |
| Skipped hooks | Agent called complete directly | Step 7 blocks Step 8 |
| Asked user permission | Agent prompted between steps | Automation notice says don't |
| Speed over process | Agent optimized for throughput | Every step is framed as mandatory |

---

## Quick Reference Card

```
CODEX CLI WORKFLOW:
├─ 0. Prerequisites: .stride_auth.md + .stride.md exist
├─ 1. Discovery: GET /api/tasks/next, review task, enrich if needed
├─ 2. Claim: Execute before_doing manually, then POST /api/tasks/claim
├─ 3. Explore (check decision matrix):
│     ├─ Goal/large undecomposed → Decompose (agent or manual) → Claim children
│     ├─ Small, 0-1 key_files → Skip to Step 4
│     └─ Otherwise → Invoke task-explorer (or read manually), outline approach
├─ 4. Implement: Write code using explorer output and task metadata
├─ 5. (removed in v1.8.0 -- slot preserved to keep Step 6-9 numbers stable)
├─ 6. Review (check decision matrix):
│     ├─ Small, 0-1 key_files → Skip to Step 7
│     └─ Otherwise → Invoke task-reviewer (or self-review), fix issues
├─ 7. Hooks: Execute after_doing (120s) + before_review (60s) manually
├─ 8. Complete: PATCH /api/tasks/:id/complete with ALL fields + hook results
└─ 9. Loop: needs_review=false → Step 1 | needs_review=true → STOP

DECISION MATRIX QUICK CHECK:
  small + 0-1 key_files  → Skip explore, plan, review
  small + 2+ key_files   → Explore + Review
  medium/large           → Explore + Plan + Review
  goal/undecomposed      → Decompose first
```

---

## Red Flags -- STOP

If you catch yourself thinking any of these, go back to the decision matrix:

- "This is straightforward, I'll skip exploration" -- Medium+ tasks ALWAYS explore
- "I know the codebase" -- The task has specific pitfalls you haven't read yet
- "Review will slow me down" -- Review catches what tests can't
- "I'll just run the hooks and complete" -- Did you explore? Did you review?
- "This step doesn't apply to me" -- Check the decision matrix, not your intuition

**The workflow IS the automation. Follow every step.**
