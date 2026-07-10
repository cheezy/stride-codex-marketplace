# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.23.0] - 2026-07-10

after_goal reliability port (**G319 — after_goal reliability port — stride-codex (docs-only)**): documents the canonical-file capture and the agent-run fresh-GET fallback so `after_goal` detection is truncation-proof on Codex CLI (which has no plugin hook script and reads the response from truncatable context). Feature minor (1.22.0 → 1.23.0). Every change is documentation/skill-text only — no hook logic, `.stride.md`, env-var matrix, or wire-shape change.

### Added — capture the `/complete` and `/mark_reviewed` response to a canonical file (W1646)

`skills/stride-completing-tasks/SKILL.md` now appends `| tee "${CLAUDE_PROJECT_DIR:-.}/.stride/.last-api-response.json"` to the `/complete` curl so the full, untruncated response is written to a canonical file (with a `curl --output` fallback for `tee`-less shells), documents that `/mark_reviewed` uses the identical capture, and notes that `.stride/` must be gitignored (the root-level `.stride-changed-files.json` is a separate entry). `skills/stride-workflow/SKILL.md` references the capture from its after_goal detect step. Framing is adapted for Codex CLI — the capture is a durable record the agent itself can read, not a hook-truncation workaround (Codex has no hook script).

### Changed — read the after_goal entry from the canonical file, not from context (W1647)

The "Detect after_goal" step in both `skills/stride-completing-tasks/SKILL.md` and `skills/stride-workflow/SKILL.md` was rewritten from a "cat the file to eyeball it" note into a file-first `jq` read: it validity-gates the canonical file with `jq -e .`, isolates the after_goal entry with `.hooks[]? | select(.name == "after_goal")`, and reads `GOAL_*` / `HOOK_TIMEOUT_MS` from `.hook.env.*` / `.hook.timeout`, falling back to the in-context response only when the file is absent, empty, or invalid — and re-reads from the file rather than trusting env carried across shell turns. Both skills carry the identical `jq` block.

### Added — the agent-run fresh `GET after_goal_status` as the truncation guarantee (W1648)

Both skills gained an identical "Fresh-GET fallback" subsection: when the captured response is truncated or absent, the agent issues a fresh, self-contained `GET /api/tasks/:id/after_goal_status` (`:id` is the just-completed task's id; the endpoint is server-side, kanban W1613), writing the compact response to the canonical file with `curl -o` and parsing `.after_goal_armed` / `.env` from disk. URL/token are re-read durably from `.stride_auth.md` and `TASK_ID` is re-derived from the captured file — never a prior turn's export. The two detection paths are mutually exclusive (`## after_goal` runs at most once), and the docs make explicit that the grace-window worker only flips the goal's status and never performs the push.

### Changed — AGENTS.md / README.md parity (W1649)

`AGENTS.md` and `README.md` now describe the canonical-file capture and fresh-GET reliability model consistently with the skills, so the top-level docs no longer imply detection reads from truncatable context.

### Backward compatibility

Documentation/skill-text only across all four changes. No hook logic, `.stride.md`, env-var matrix, or wire-shape change; the `{exit_code, output, duration_ms}` hook-result shape, the completion payload contract, and the `capture_changed_files` snapshot format are all unchanged. The `.last-api-response.json` capture and the `GET /api/tasks/:id/after_goal_status` fallback are best-effort and additive — agents that skip them fall back to the server's grace-window worker exactly as before.

### Release

stride-codex is distributed through its own vendored marketplace **`stride-codex-marketplace`** (which in-repo copies `plugins/stride-codex/`), not the Claude Code `stride-marketplace`. A release is therefore two repos: (1) tag + `gh release` **v1.23.0** on the `stride-codex` plugin repo, and (2) re-vendor the plugin tree into `stride-codex-marketplace`, bump its README plugins-table version to match `plugin.json`, then commit + tag + `gh release` **v1.23.0** there (per that repo's `RELEASE.md`).

### Source

G319 — after_goal reliability port — stride-codex (docs-only) (W1646, W1647, W1648, W1649).

## [1.22.0] - 2026-07-03

Enhancements release (**G297 — Stride-Codex Enhancements**): a batch of documentation-consistency, portability, and clarity fixes across the Codex skills and agents. Feature minor (1.21.0 → 1.22.0). Every change is documentation/skill-text only — no hook logic, `.stride.md`, env-var matrix, or wire-shape change.

### Fixed — reviewer `schema_version` drift reconciled to 1.4 (W1505)

`README.md` and `skills/stride-subagent-workflow/SKILL.md` still advertised a stale reviewer structured-block version (README said schema 1.3; the subagent-workflow worked examples used `schema_version` 1.2 and omitted the `security_considerations` verdict). Both were reconciled to the canonical **1.4** shape already defined in `agents/task-reviewer.md`, and both worked-example objects gained the missing `security_considerations` `{status, note}` verdict. The single-source-of-truth `agents/task-reviewer.md` was left unchanged.

### Added — `after_goal` (fifth hook) awareness in the hook-diagnostician (W1506)

`agents/hook-diagnostician.md` predated the `after_goal` hook: its frontmatter and Hook Timeout Handling section knew only the four task-scoped hooks. It now lists `after_goal` in the frontmatter hook set, adds an `after_goal` timeout row noting the timeout is **server-supplied** (honors the response `hook.timeout`, typically ~60s) rather than a fixed client constant, and explains that `after_goal` runs under `GOAL_*` (not `TASK_*`) env vars — so a failure referencing an unset `GOAL_*` points at the manual export step, not the hook body.

### Fixed — the unexplained Step 5 numbering gap in stride-workflow (W1507)

The orchestrator's steps ran 0,1,2,3,4,6,7,8,9 with the flowchart and Quick Reference silently skipping 5. Added a `## Step 5: (intentionally left blank)` placeholder noting the former *Activate Development Guidelines* step was removed in v1.8.0 (that skill is not distributed with the plugin) and the slot is preserved to keep the Steps 6–9 cross-references stable, and annotated the flowchart and Quick Reference 4-to-6 jump. No later steps were renumbered.

### Changed — portable millisecond hook clock + `after_goal` timeout wrapper (W1508)

Every GNU-only `date +%s%3N` in the manual hook-capture snippets (across `stride-workflow`, `stride-completing-tasks`, `stride-claiming-tasks`) was replaced with a portable `now_ms()` helper (`python3` milliseconds, with a whole-second `date +%s` fallback) plus a note that `%N` is GNU-only. The manual `after_goal` execution path now wraps its commands in a `timeout` derived from the server-supplied `hook.timeout` (ms → whole seconds, 60s fallback), with `HOOK_TIMEOUT_MS` added to the Step 3 export list. Per-hook timeout values (60/120/60) and the `{exit_code, output, duration_ms}` result shape are unchanged.

### Changed — clarified the "one command at a time" hook rule for backslash continuation (W1509)

Every hook-execution "one at a time" rule location (`AGENTS.md`, `README.md`, `skills/stride-workflow`, `skills/stride-completing-tasks`, `skills/stride-claiming-tasks`) now states that a trailing-backslash line continues onto the next physical line and the joined text is one logical command — so the rule targets logical commands, not physical lines — while preserving the intent against merging unrelated commands into one opaque script. The backslash-continued `gh pr create` examples are unchanged.

### Added — document capturing `TASK_BASE_REF` at claim time (W1510)

`skills/stride-claiming-tasks/SKILL.md` and `skills/stride-workflow/SKILL.md` Step 2 now instruct capturing `export TASK_BASE_REF=$(git rev-parse HEAD)` at claim time, **before** `before_doing` runs (which may `git pull`/commit and move HEAD), and `skills/stride-completing-tasks/SKILL.md` gained a warning that the `${TASK_BASE_REF:-HEAD~1}` fallback can diff against an unrelated pre-existing commit. `changed_files` remains optional and the `capture_changed_files` wire shape is unchanged.

### Backward compatibility

Documentation/skill-text only across all six changes. No hook logic, `.stride.md`, env-var matrix, or wire-shape change; the `{exit_code, output, duration_ms}` hook-result shape, the completion payload contract, and the `capture_changed_files` snapshot format are all unchanged.

### Release

stride-codex is **not** distributed through `stride-marketplace` (or any marketplace), so there is **no marketplace pin to update**. Release is **tag + `gh release`** on the `stride-codex` repository only.

### Source

G297 — Stride-Codex Enhancements (W1505, W1506, W1507, W1508, W1509, W1510).

## [1.21.0] - 2026-07-01

### Added — `API Notes & Limitations` section in the workflow orchestrator skill (G286 / W1418)

Two recurring API gotchas were undocumented, and agents kept rediscovering them the hard way: attempting to move a task to a different goal via `PATCH` (impossible — `parent_id` is creation-only and there is no DELETE endpoint), and calling the hosted API from an HTTP library whose default User-Agent the edge rejects.

- **`skills/stride-workflow/SKILL.md`** — Added an **API Notes & Limitations** section directly after **API Authorization**, mirroring the canonical stride wording: (a) tasks cannot be reparented and there is no DELETE endpoint — moving a task between goals or removing it is a human board-UI action, never to be worked around by recreating the task as a supersede; (b) raw HTTP calls must use curl or a curl/browser-like `User-Agent`, because the hosted API edge returns `403` with `error code: 1010` to default library User-Agents (e.g. `python-urllib`).

### Backward compatibility

Documentation/skill-text only. No skill logic, hook, or wire-shape changes.

### Source

G286 — W1418 (mirrors the canonical stride W1416 wording).

## [1.20.0] - 2026-06-29

### Added — `create-tasks`/`create-goals` now have an explicit terminal state, plus a Backlog claim-fail guard (G284 / W1402)

In an autonomous/build context the create-tasks/create-goals flow could create a task and then fall straight through the `stride-workflow` orchestrator's build loop — auto-claiming and building the just-created task. The claim fails because newly created tasks sit in the Backlog (not Ready), and the agent would then build the work outside the Stride lifecycle (no claim, no hooks, no completion record). The orchestrator had no terminal state for the create intent, unlike `stride-ideation` which stops at the written document.

- **`skills/stride-workflow/SKILL.md`** — Added a **Creation Terminal State** section: on a create-tasks/create-goals intent the orchestrator now reports the created identifiers and STOPS without entering Task Discovery, claiming, or implementation (no-marker variant — Codex satisfies the sub-skill STOP gate by routing through the orchestrator). Added a **Backlog Claim-Fail Guard**: a failed claim is a terminal stop, never a fallback to building outside the lifecycle. The build loop (Steps 1–9) is unchanged.
- **`skills/stride-creating-tasks/SKILL.md`**, **`skills/stride-creating-goals/SKILL.md`** — Added a `## Terminal state` note: creation ends the turn; building is a separate, explicitly-invoked action.

### Backward compatibility

Documentation/skill-text only. No hook, `.stride.md`, or wire-shape change. The build loop is unchanged; only the create-intent path gains an explicit stop.

## [1.19.0] - 2026-06-20

Documentation parity release: brings the Codex variant to canonical `stride` **v1.30.0 (G254)**, porting the `created_by_agent` creation-skill documentation into the Codex skills. Feature minor (1.18.0 → 1.19.0).

### Added — the creation skills now document `created_by_agent`

Agent-created tasks previously landed with `created_by_agent` nil, so the `/agents` activity feed rendered an uninformative `?` avatar on every `created` row. The creation skills now document the field on the create request bodies:

- **`skills/stride-creating-tasks/SKILL.md`** — `created_by_agent` added to the complete-task example, the Field Quick Reference table (string, create-only, forbidden on `PATCH`), and an explanatory note: set it to the plugin's own agent name (`"Codex CLI"` — the exact value sent as `agent_name` on claim/complete), never the `ai_agent:<model>` token form, so one agent stays one roster identity.
- **`skills/stride-creating-goals/SKILL.md`** — `created_by_agent` added to the batch goal example with a note that the server propagates the goal's value to every nested child task.

Documentation-only: no wire-shape, hook, or auth change; `created_by_agent` is optional on create, was already accepted by the API, and is forbidden on `PATCH`. stride-codex is not distributed through a marketplace, so there is no marketplace pin to update.

## [1.18.0] - 2026-06-19

Documentation parity release: brings the Codex variant to canonical `stride` **v1.29.0 (G225)**, porting the `technical_details` task-field documentation rollout into the Codex skills and agents. Feature minor (1.17.0 → 1.18.0).

### Added — the `technical_details` task field is now documented across the plugin

`technical_details` is an **optional, free-form JSON object** a task may carry to hold any additional technical context that does not fit the structured fields — data shapes, gotchas, key decisions, reference links. Unlike `testing_strategy`, it has **no fixed keys**: a task author or enricher uses whatever keys best describe the work, and leaves it as `{}` when there is nothing substantive to record. It is **not** one of the five review_queue-scored fields (`acceptance_criteria`, `testing_strategy`, `security_considerations`, `pitfalls`, `patterns_to_follow`), so a blank value is never a scoring gap. The plugin previously had no documentation for this field; agents now have one consistent definition to follow.

- **`skills/stride-creating-tasks/SKILL.md`** (W1198) — documents `technical_details` in the Field Quick Reference table, the complete-task example, and the Embedded Object Formats section (as a free-form object, explicitly contrasted with `testing_strategy`, which has fixed `valid_keys`).
- **`skills/stride-creating-goals/SKILL.md`** (W1198) — notes that nested tasks MAY carry an optional free-form `technical_details` object and that it is not a review_queue-scored field.
- **`agents/task-enricher.md` + `skills/stride-enriching-tasks/SKILL.md`** (W1199) — add `technical_details` to the enrichment guidance as an optional field the enricher MAY populate from discovered context — never fabricated, left as `{}` otherwise — with a no-secrets reminder since the object is free-form.
- **`agents/task-decomposer.md`** (W1199) — notes that a decomposed task MAY include an optional `technical_details` object.
- **`skills/stride-workflow/SKILL.md`** (W1200) — adds `technical_details` to the Step 1 task-field review list (optional free-form context; not a scored field).
- **`agents/task-explorer.md`** (W1200) — the explorer folds any recorded `technical_details` into its summary so implementation benefits from it.

### Backward compatibility

Documentation-only. No wire-shape, `.stride.md`, or `.stride_auth.md` changes; `technical_details` is optional everywhere it appears and is never added to any scored-field set. Tasks that omit it behave exactly as before.

### Source

Goal G247 — the Codex port of canonical stride v1.29.0 (G225 / G243, W1179–W1182), across child tasks W1198 (creation contracts), W1199 (enrichment + decomposition), W1200 (workflow + exploration surfacing), and W1201 (this release-notes/version task). stride-codex is not distributed through a marketplace, so no marketplace pin update.

## [1.17.0] - 2026-06-14

Parity release: brings the Codex variant to canonical `stride` **v1.24.0 (G222)** and **v1.26.0 (D66)** for the review-report-completeness contract and the `acceptance_criteria` 1:1 hard rule. Feature minor (1.16.0 → 1.17.0).

### Updated

- **`agents/task-reviewer.md`** (D70 / W1073 + D66) — Added the **strict `not_assessed` reception clause** to the "You will receive" line: every task-supplied field is passed, a field is absent only when the task itself genuinely left it empty, so a task-supplied section MUST get a real `passed`/`failed` verdict and `not_assessed` is reserved strictly for task-empty sections. Added the **D66 `acceptance_criteria` 1:1 verbatim hard rule** to both the step-1 Acceptance Criteria Verification list and the `acceptance_criteria` schema entry — exactly one entry per criterion line, copied verbatim in the task's wording and order, never split/merged/reworded/added/dropped, array length == the task's criterion-line count (prevents the W1099 `6/5` mismatched-count display).
- **`skills/stride-workflow/SKILL.md`** (D71 / W1072 + W1074 + D66) — The reviewer-dispatch field list now lists **all 8 fields** (`acceptance_criteria`, `pitfalls`, `patterns_to_follow`, `testing_strategy`, `security_considerations`, `description`, `what`, `why`) with NO-EXCEPTIONS prose; the "Extracting the structured review block" section gains the **whole-object-copy self-check** (every section survives into `reviewer_result`; submitted `project_checks` count == the reviewer's) and the **D66 re-review rule** (re-reviews pass `acceptance_criteria` unchanged and keep the array identical to the task's canonical list) plus the `acceptance_criteria`-count == criterion-line-count self-check.
- **`skills/stride-completing-tasks/SKILL.md`** (D71 / W1075) — Added the **MANDATORY pre-submission self-check (hard gate)** section and a matching Verification Checklist item: before every `/complete`, confirm every reviewer section is present, `project_checks` is complete, and no task-supplied section came back `not_assessed`. There is no bypass — not for small tasks, not for trivial tasks.
- **`skills/stride-subagent-workflow/SKILL.md`** (D71 / W1076) — The Phase 3 reviewer-input list now passes **all 8 fields** (single-sourced against `agents/task-reviewer.md`), plus the whole-object-copy reminder pointing at the orchestrator and completing-tasks self-checks.

### Behavior change

The new hard gate is an **intended forcing function**: completions that previously submitted a thin or count-inconsistent `reviewer_result` (a dropped section, a trimmed `project_checks`, or a task-supplied section left `not_assessed`) will now fail the pre-submission self-check and must be fixed before `/complete`. This matches the canonical Kanban server contract, which now hard-rejects such reports.

### Not applicable to Codex

Of the canonical releases after stride v1.23.0, the **hook-script releases are N/A for the Codex variant**, which ships no hook script and has no `.stride-env-cache` / `TASK_BASE_REF` / `.stride-diff-upload-state` mechanism (Codex executes `.stride.md` hooks agent-manually):

- **stride v1.25.0** — hook-script change; no codex equivalent.
- **stride v1.26.0 (D65 half)** — the hook-script half of the release; N/A. Only the **D66** agent-prompt half (the `acceptance_criteria` 1:1 rule) applies and is ported above.
- **stride v1.27.0 (D67)** — hook-script change; no codex equivalent.
- **stride v1.28.0 (G224)** — hook-script change; no codex equivalent.

No hook-script files were invented for codex.

### Source

Goal G230 (children D70, D71) — the Codex port of canonical stride v1.24.0 (G222: W1072-W1076) and v1.26.0 (D66). stride-codex is not distributed through a marketplace, so no marketplace pin update.

## [1.16.0] - 2026-06-08

Parity release: brings the Codex variant to G220/G219 parity for the reviewer `project_checks` `not_applicable` status and full-checklist emission (canonical: stride v1.23.0, commit a4e7e6f, W1057). Feature minor (1.15.0 → 1.16.0).

### Updated

- **`agents/task-reviewer.md`** — The `project_checks[]` per-entry `status` enum gains a third value, **`not_applicable`**, alongside `met` / `not_met`, and the reviewer is now required to **emit one entry for every top-level `CODE-REVIEW.md` bullet — never omit one**. Previously, with only `met` / `not_met` available, the reviewer silently dropped bullets that had no bearing on the diff under review (a small one-line fix surfaced only 2 of ~9 checks), so the Kanban review queue's "Code review" panel rendered a partial, ambiguous checklist. Now bullets that do not apply are marked `not_applicable` with a one-line reason in `evidence`; `not_applicable` is **approval-neutral** — it produces no paired `issues[]` entry and never contributes to `changes_requested` (only `not_met` does). `schema_version` bumps `"1.3"` → `"1.4"`, and the worked example demonstrates a `not_applicable` row.
- **`AGENTS.md`, `skills/stride-completing-tasks/SKILL.md`, `skills/stride-workflow/SKILL.md`** — All example/prose `schema_version` strings bumped `"1.3"` → `"1.4"` in lockstep so no stale `"1.3"` remains; the AGENTS.md reviewer summary now notes the `met`/`not_met`/`not_applicable` enum and full-checklist emission.

### Backward compatibility

Documentation/agent-prompt change only — no wire-shape, hook, `.stride.md`, `.stride_auth.md`, or `.gitignore` changes. The change is additive: `reviewer_result` is stored as `:jsonb` by the Kanban server and persisted verbatim (the v1.15.0 passthrough change), so the new `not_applicable` status value flows through with no consumer edit. Payloads from reviewers on the prior `"1.3"` schema (emitting only `met` / `not_met`) remain valid. The Kanban review-queue panel renders `not_applicable` as a neutral "N/A" pill (kanban-side, ships independently).

### Source

W1061 under goal G220 — the Codex port of W1057 (reviewer `not_applicable` status + full-checklist emission) from goal G219. The canonical implementation is stride v1.23.0 (commit a4e7e6f). stride-codex is not distributed through a marketplace, so no marketplace pin update.

## [1.15.0] - 2026-06-08

Bundled release covering two ports from the main `stride` plugin (G217 + G218 parity).

### Added

- **`skills/stride-completing-tasks/SKILL.md`** (W1048 / D61) — The manual wrapped-body PUT section now documents the **transport-encoded envelope** `{"changed_files":{"encoding":"base64","data":"<single-line-base64>"}}` (with a raw-object fallback when `base64` is unavailable, and the WAF rationale) for agents who PUT the `changed_files` snapshot to a v1.16.0+ server. Codex CLI has no automated hook, so the encoding is documented for the copy-pasteable `## after_doing` block rather than executed by a plugin hook. The diff-shape rules remain referenced from `docs/diff-contract.md`, not duplicated.

### Fixed

- **`skills/stride-workflow/SKILL.md`, `skills/stride-subagent-workflow/SKILL.md`** (W1056 / D63) — Both skills' "Extracting the structured review block" guidance built `reviewer_result` from a hand-maintained enumerated copy-list of structured keys. `stride-workflow` omitted `project_checks`; `stride-subagent-workflow` omitted **both** `project_checks` and `security_considerations`. The result: the reviewer's CODE-REVIEW.md per-bullet audit (and, on the subagent path, the security verdict) was silently dropped on completion, so the Kanban review queue's **Code review** panel (and security tile) rendered nothing. Both skills now use a **verbatim passthrough**: copy the reviewer's entire parsed JSON object into `reviewer_result` and overlay only the legacy summary fields — fixing both omissions at once. Both fallbacks were inverted to legacy-only send lists.

### Updated

- **`agents/task-reviewer.md`** (W1056 / W1049) — Added an explicit **consumption invariant**: the canonical schema is the only place the structured key-set is enumerated, and the completion path MUST persist the reviewer's emitted JSON verbatim and MUST NOT maintain its own allow-list of keys to copy.

### Backward compatibility

Documentation/skill-instruction change only — no wire-shape, hook, or config changes (Codex CLI has no automated hook). The `changed_files` base64 envelope is documented for v1.16.0+ servers that accept it (ships in the kanban repo), with the raw-object fallback for older deployments. `project_checks[]` and `security_considerations` already existed and are already rendered by the review queue; this release simply stops dropping them. Not distributed through a marketplace.

### Source

W1048 (D61 base64 changed_files transport documentation), W1056 (D63 reviewer_result verbatim passthrough + W1049 consumption invariant). Mirrors the main `stride` plugin's 1.22.0 (D61) and 1.22.1 (project_checks) releases.

## [1.14.0] - 2026-06-06

Parity release: brings the Codex variant up to the canonical stride G210 feature set, which adds `security_considerations` as the **fifth** review_queue-scored field (alongside `acceptance_criteria`, `testing_strategy`, `pitfalls`, `patterns_to_follow`). Feature minor. All five content-bearing skill/agent files now treat `security_considerations` as a first-class scored deliverable, and the reviewer emits a fifth section verdict at `schema_version` **1.3**.

### Added

- **`skills/stride-creating-goals/SKILL.md` + `skills/stride-creating-tasks/SKILL.md` — `security_considerations` as the 5th scored field (W1024).** Adds `security_considerations` to the review_queue-scoring banner, the required/nesting field lists, the minimum-bar list, the Red Flags, the Rationalization Table, and the example JSON in both creation skills; creating-tasks also gains the `### security_considerations` Embedded-Object-Formats subsection (array-of-strings shape + the `"None — …"` escape hatch). Codex port wording (plain WRONG/RIGHT labels, the "NESTED TASKS ARE NOT EXEMPT" banner heading) preserved.
- **`skills/stride-enriching-tasks/SKILL.md` + `agents/task-enricher.md` — security pass + 17-item checklist (W1025).** Step 5 now covers security analysis (input validation, authorization boundaries, secret handling, injection surfaces, data exposure) producing `security_considerations`; the pre-submission checklist grows 16 → 17 items; `security_considerations` is added to the PATCH/output example JSON, the field-type reminders, and the Red Flags.
- **`agents/task-decomposer.md` + `agents/task-reviewer.md` — decomposer Required field + reviewer security verdict (W1026).** task-decomposer marks `security_considerations` Required in the field table, the output template, and every worked-example task. task-reviewer adds the Step 5 "Security Considerations Alignment" review step (steps renumbered), the `security_considerations` section verdict object, the `"security"` issue category, the expanded consistency rule, and bumps the reviewer `schema_version` **1.2 → 1.3**.
- **`skills/stride-completing-tasks/SKILL.md` + `skills/stride-workflow/SKILL.md` — persist & extract the security verdict (W1027).** The `reviewer_result` structured block in completing-tasks lists the `security_considerations` section verdict; stride-workflow Step 6 copies `security_considerations` verbatim in the field map and the fallback omit-list, and adds a worked example at `schema_version` 1.3 carrying the security verdict.

### Changed

- **Manifest/docs reflect the fifth scored field (W1028).** `AGENTS.md` and `README.md` updated to describe the reviewer's `schema_version` 1.3 block with the `security_considerations` per-section verdict and to name `security_considerations` as the fifth review_queue-scored field. Version bumped 1.13.0 → 1.14.0 in `.codex-plugin/plugin.json`.

### Backward compatibility

Documentation/contract additions only. Older completions that omit `security_considerations` (or send the thin `reviewer_result` envelope / self-reported-skip form) continue to validate — the server tolerates the absent structured key. No hook script, parser contract, env-var matrix, or `.stride.md` change is required. The version bump affects discovery metadata only. All intentional Codex adaptations (manual hook execution, self-reported-skip primary path, `read`/`search`/`glob`/`shell` tool vocabulary, AGENTS.md context file, no command files) are preserved.

### Source

G210 (canonical) / W1024 (creation skills), W1025 (enrichment skill + enricher agent), W1026 (decomposer + reviewer agents), W1027 (completing-tasks + workflow skills), W1028 (release). Mirrors the canonical stride G210 `security_considerations` fifth-scored-field rollout into the Codex variant. No marketplace pin update — stride-codex is not distributed through stride-marketplace.

## [1.13.0] - 2026-06-06

Parity release: brings the Codex variant up to the canonical stride 1.18.0–1.20.0 reviewer/creation feature set, plus a Codex-adapter review and an accuracy reconciliation. Feature minor. This release also reconciles the version metadata — `.codex-plugin/plugin.json` had lagged at 1.11.0 while the CHANGELOG was at 1.12.1; both are now coherent at 1.13.0.

### Added

- **`agents/task-reviewer.md` — project-level checks (mirrors stride 1.18.0).** Adds a step 6 "Project-Level Checks": read `CODE-REVIEW.md` from the project root (via the `read` tool), parse each top-level Markdown bullet as a standing check (nested sub-bullets are context, not separate checks), map a case-sensitive `CRITICAL:` prefix to severity `critical` (default `important`, prefix stripped), and emit `project_checks[]` (`check` / `source` / `status` / `evidence`). Every `not_met` check requires a paired `issues[]` entry with `category: "project_check"`. When `CODE-REVIEW.md` is absent, `project_checks` renders as `[]`. Bumps the reviewer `schema_version` 1.0 → 1.1 and extends the `issues[]` category enum + the `changes_requested` status rule.
- **`agents/task-reviewer.md` — per-section verdicts + schema 1.2 (mirrors stride 1.19.0 / D58).** Adds the `testing_strategy` / `patterns` / `pitfalls` verdict objects (`passed` | `failed` | `not_assessed` + one-line `note`), the consistency rule (a `failed` verdict must be backed by a matching-category `issues[]` entry and vice-versa), and the three step verdict-recording lines (Pitfall Detection / Pattern Compliance / Testing Strategy Alignment). Bumps the reviewer `schema_version` 1.1 → **1.2**.
- **`skills/stride-completing-tasks/SKILL.md` + `skills/stride-workflow/SKILL.md` — structured `reviewer_result` persistence (mirrors stride 1.19.0 / D57).** Documents persisting the reviewer's full structured block verbatim as `reviewer_result` (the rich `schema_version` / `status` / `issue_counts` / `issues[]` / `acceptance_criteria[]` / `project_checks[]` / `testing_strategy` / `patterns` / `pitfalls` keys merged with the legacy `dispatched` / `duration_ms` / `issues_found` / `acceptance_criteria_checked` envelope) for the dispatched-agent case. The "Extracting the structured review block" subsection (conceptual extraction, field mapping, omit-unemitted-keys rule, JSON-parse-failure fallback) lives in **`stride-workflow` Step 6** (canonical location). The schema is cited (`agents/task-reviewer.md`), not redefined. Codex's primary reviewer path remains the self-reported skip (limited custom-agent dispatch); the rich block applies when a reviewer agent is dispatched.
- **`skills/stride-workflow/SKILL.md` + `skills/stride-creating-tasks/SKILL.md` + `skills/stride-creating-goals/SKILL.md` — context-informed creation docs (mirrors stride 1.20.0).** Adds a "Context-Informed Creation" section to the orchestrator and "Consuming Provided Context" sections to the two creation skills (context→field mapping, augment-never-override rule, still-required four review_queue fields, and the unchanged `"goals"` root-key / index-dependency rules). Framed for Codex's command-less model: invocation is activating `stride-workflow` with a creation intent + optional directory path (the orchestrator reads the `.md` bundle via `glob`/`read`), **not** `/stride:create-*` commands or command files — the sub-skill `## STOP — orchestrator check` gate is referenced (Codex has no activation-marker file).

### Changed

- **Codex-adapter review (AGENTS.md, install.sh, install.ps1, README.md).** Corrected the agent count (Four → Five, added `task-enricher`); documented the full five-section manual hook-execution model incl. `after_goal` (hook lifecycle table, env-var matrix, accurate result-field-to-endpoint mapping); added a `git` pre-check to `install.sh` (parity with `install.ps1`); replaced hardcoded install counts with dynamic counts; added `@()` array-forcing to `install.ps1`; and added the `after_goal` row + corrected the result-field bullet in README.
- **Accuracy reconciliation.** Reconciled all 7 skills + 5 agents + AGENTS.md against canonical: ported the previously-stubbed `task-decomposer` and `hook-diagnostician` agent bodies to their full canonical form (hook-diagnostician reframed for Codex's manual hook model — raw-text input primary), restored dropped `task-reviewer` review-step bullets, bumped the stale `stride-subagent-workflow` extraction example to schema 1.2, and aligned residual tool-name vocabulary — all while preserving the intentional Codex adaptations (manual hook execution, self-reported-skip primary path, `read`/`search`/`glob`/`shell` tool vocabulary, `.agents/` install destinations, AGENTS.md context file, no command files).

### Backward compatibility

The reviewer-schema, structured-`reviewer_result`, and context-creation changes are documentation/contract additions — older completions that still send the thin `reviewer_result` envelope (or the self-reported-skip form) continue to validate. No hook script, parser contract, env-var matrix, or `.stride.md` change is required. The version-metadata reconciliation (plugin.json 1.11.0 → 1.13.0) is the only non-documentation change and affects discovery metadata only.

### Source

G_codex_parity / W976 (adapter review), W977 (1.18.0 project_checks), W978 (1.19.0/D58 section verdicts), W979 (1.19.0/D57 structured reviewer_result persistence), W980 (1.20.0 context-threading docs), W981 (accuracy reconciliation + version-mismatch identification), W982 (release). Mirrors the stride/ **1.18.0** (project_checks), **1.19.0** (section verdicts + structured persistence), and **1.20.0** (context-informed creation) releases into the Codex variant. No marketplace pin update — stride-codex is not distributed through stride-marketplace. No gh release is cut here — that step is human-triggered.

## [1.12.1] - 2026-05-25

### Updated

- **`skills/stride-creating-tasks/SKILL.md`** (W865) — Adds a top-of-file "⚠️ REVIEW QUEUE SCORING" callout that names the four fields the review_queue dashboard scores on every completion (`acceptance_criteria`, `testing_strategy`, `pitfalls`, `patterns_to_follow`) and frames the consequence of omitting any of them: a visible, public, persistent **empty pill** on the dashboard that does not get back-filled later. Reinforces with four new bullets in the existing **Red Flags - STOP** list and four new rows in the existing **Rationalization Table**. Wording matches the stride/ Claude Code variant for cross-plugin consistency.
- **`skills/stride-enriching-tasks/SKILL.md`** (W866) — Adds a top-of-file "⚠️ REVIEW QUEUE SCORING — ENRICHMENT IS THE LAST CHANCE" callout. Promotes the four scored fields to individual mandatory-for-review items in the Phase 4 16-item pre-submission checklist (replacing the prior single-line bundling), each with its specific empty-pill condition. Adds four new Red Flags - STOP bullets.
- **`skills/stride-creating-goals/SKILL.md`** (W867) — Adds a top-of-file "⚠️ REVIEW QUEUE SCORING — NESTED TASKS ARE NOT EXEMPT" callout stressing the four-field minimum bar applies to every nested task individually — no "it's just a subtask" discount. Strengthens Task Nesting Rules with a per-field block enumerating each scored field with its empty-pill condition. Adds four new Red Flags - STOP bullets and four new Rationalization Table rows.

### Backward compatibility

Content-only release. No hook script, parser contract, env-var matrix, API field shape, or workflow step changed — every behavior is byte-identical to 1.12.0. The three SKILL.md edits strengthen guidance only; existing task-creation, enrichment, and goal-creation calls continue to validate without modification. No `.stride.md`, `.stride_auth.md`, or `.gitignore` changes are required.

### Source

G166 / W865 / W866 / W867 / W868. Patch release — documentation-only emphasis updates across three SKILL.md files. The change set mirrors the stride/ plugin's 1.17.3 release (Claude Code variant) and the goal is to raise the floor on the four fields the review_queue dashboard scores at completion, so empty pills become rare rather than common.

## [1.12.0] - 2026-05-25

### Added

- **`skills/stride-completing-tasks/SKILL.md`** — New subsection "Per-File Diff Capture (Manual, Wrapped-Body PUT — for v1.16.0+ servers)" documenting the optional agent-manual flow that mirrors what the auto-PUT hook does on other Stride plugins. Codex CLI has no plugin-side hook surface to host the auto-PUT, so this is documentation only — the existing inline-cat-in-complete flow remains the recommended default. The new section walks through a copy-pasteable `.stride.md` `## after_doing` block that (1) sources the canonical `capture_changed_files` function and writes the snapshot to `.stride-changed-files.json`, then (2) `curl -s -X PUT`s the snapshot to `$STRIDE_API_URL/api/tasks/$TASK_ID/changed_files` with the body wrapped as `{"changed_files": [...]}`. The body shape rule is documented explicitly with a side-by-side bare-vs-wrapped JSON comparison and an explicit reference to G174 / Plug.Parsers `_json` behavior so future readers do not accidentally simplify the body to a bare top-level array (which the server would persist as NULL, silently clearing the snapshot — this was the critical regression that made stride 1.17.2 a critical fix). Implemented as W848.

### Why this release

The Stride server's `PUT /api/tasks/:id/changed_files` endpoint has existed since 1.16.0 but stride-codex's completion guidance only ever showed the inline-in-complete shape — so Codex agents targeting v1.16.0+ servers who wanted to fire the snapshot up early (live diff panel, review-queue webhook) had to figure out the wrapped body shape from external references. This release closes that gap by documenting the wire-shape rule in the skill that every Codex agent reads before /complete.

### Backward compatibility

Behavior unchanged. Codex's existing inline-cat-in-complete flow remains the recommended default — the new subsection is presented as an alternative, not a replacement. No `.stride.md`, `.stride_auth.md`, or `.gitignore` changes are required.

### Migration

Update via your normal stride-codex install flow. No marketplace pin update — stride-codex is not distributed through stride-marketplace.

### Source

W848. Documentation-only release that mirrors the G174 wrapped-body rule from main stride 1.17.2 into the Codex variant's completion skill. No code surface in stride-codex (Codex CLI has no hook surface), hence no plugin.json version pin to bump — the version lives only in this CHANGELOG.

## [1.11.0] - 2026-05-22

### Added

- **`## after_goal` hook documentation** — fifth `.stride.md` hook documented across two skills. stride-codex has no plugin hook script (unlike stride-claude / stride-copilot / stride-gemini / stride-opencode), so this release is **documentation-only**: it teaches Codex CLI agents how to handle the `after_goal` lifecycle manually when the Stride server bundles an `after_goal` entry in the response of `/complete` or `/mark_reviewed`.
- **`skills/stride-workflow/SKILL.md`** (W801) — Step 7 (Execute Hooks) gains a Hooks Reference table listing all five hooks (timing/blocking/timeout/purpose) with an explicit note that codex has no hook script so the agent runs each hook manually via the platform's shell tool. New Hook Environment Variables matrix shows `GOAL_*` (`GOAL_ID`, `GOAL_IDENTIFIER`, `GOAL_TITLE`, `GOAL_DESCRIPTION`) alongside `TASK_*` / `BOARD_*` / `COLUMN_*` / `AGENT_NAME` / `HOOK_NAME`, with guidance to export from the response's `hook.env` block. New Canonical Hook Examples block with an explicit general-purpose disclaimer (Slack notifications, artifact archival, release pipelines, project-level smoke tests are all valid uses — not just PR creation). Step 9 (Post-Completion Decision) gains a new subsection with a five-step manual execution path: detect after_goal entry in response → read `## after_goal` from `.stride.md` → export GOAL_* from hook.env → execute commands via shell → POST captured `{exit_code, output, duration_ms}` to `PATCH /api/tasks/:goal_id/after_goal`.
- **`skills/stride-completing-tasks/SKILL.md`** (W802) — New subsection in the "Review vs Auto-Approval Decision" block surfacing the after_goal entry in the `/complete` and `/mark_reviewed` response payload's `hooks` array. Documents the same five-step manual execution path with the curl shape for the agent's PATCH POST. Includes pitfall: non-zero exit must be surfaced, never silently retried.

### Backward compatibility

A `.stride.md` without a `## after_goal` section continues to work unchanged — the agent simply skips the manual execution path and the server's grace-window worker promotes the goal to Done automatically with a synthetic attempt tagged `source: "after_goal_grace_worker"`. Older agent runtimes that don't speak the after_goal protocol — including those that don't make the PATCH POST — are covered by the same grace-window worker.

### Note on the v1.10.x tag gap

Commits `8f7a986 Default CLAUDE_PROJECT_DIR to . in inline-cat pattern (W771)` and `01f85a5 Release 1.10.1` and `a965a4e Release 1.10.0` were committed but never tagged on origin. This v1.11.0 release captures all of that prepared work alongside the new after_goal documentation — installing v1.11.0 picks up everything.

### Migration

Install via your normal stride-codex install flow. No `.stride.md`, `.stride_auth.md`, or `.gitignore` changes are required. To opt into the new hook, add a `## after_goal` section to `.stride.md` AND follow the five-step manual execution path documented in stride-workflow Step 9 / stride-completing-tasks "Additional hook in the response" subsection.

### Source

G167 / W801 (stride-workflow SKILL.md), W802 (stride-completing-tasks SKILL.md), W803 (this release). Pattern mirrors the Claude plugin's v1.17.1 release — the after_goal feature shipped first on the Claude plugin and is being ported to the other Stride agent plugins. For stride-codex, the port is documentation-only because there's no hook script to update.

## [1.10.1] - 2026-05-21

### Fixed

- **`skills/stride-completing-tasks/SKILL.md`** — Replaced five occurrences of `"$CLAUDE_PROJECT_DIR/.stride-changed-files.json"` with the defaulted form `"${CLAUDE_PROJECT_DIR:-.}/.stride-changed-files.json"` in the canonical inline-cat pattern. The inline structure, the `--argjson cf "$(cat ... 2>/dev/null || echo '[]')"` shape, and the binary/truncation contract are unchanged — only the variable expansion is defaulted.
- **`.codex-plugin/plugin.json`** — Version field corrected to `1.10.1`. The repository carried a pre-existing version-tag drift (the v1.10.0 release was tagged without bumping `plugin.json` from `1.9.0`); this hotfix re-syncs the manifest with the release tag in the same commit.

### Why this release

Under runtimes where `$CLAUDE_PROJECT_DIR` is unset/empty (notably Claude Code's TypeScript SDK when bridging from Codex CLI), the bare expansion produced `/.stride-changed-files.json`. The `cat` failed, the `|| echo '[]'` fallback fired, and agents POSTed `changed_files: []` even when the hook had correctly written the snapshot. The defaulted form `${CLAUDE_PROJECT_DIR:-.}` falls back to the current working directory when the variable is unset or empty.

### Backward compatibility

Wire shape unchanged. Behavior under a non-empty `$CLAUDE_PROJECT_DIR` is byte-identical to v1.10.0.

### Source

Mirrors the stride v1.15.1 fix (W767/W768) for the Codex variant. Implemented as W771 (SKILL.md hotfix) and W772 (release coordination). No marketplace pin update — stride-codex is not distributed through stride-marketplace; consumers install directly from this repository.

## [1.10.0] - 2026-05-20

### Added

- **`skills/stride-completing-tasks/SKILL.md`** — New `## Per-File Diff Capture (Manual)` section that documents the optional top-level `changed_files` field on completion payloads, citing [`docs/diff-contract.md`](https://raw.githubusercontent.com/cheezy/kanban/refs/heads/main/docs/diff-contract.md) as the encoding source-of-truth (field shape, 500-line truncation marker, binary placeholder string). The section explains the Codex-specific architecture — Codex CLI has no automatic hook interception, so the snapshot is produced by the agent (typically as a line in the user's `.stride.md` `## after_doing` block) rather than by an auto-firing PreToolUse handler the way other Stride plugins do it. Includes a "Why inline?" paragraph explaining that a separate shell turn before the completion curl would read a stale snapshot from a prior task, and a "Working-tree semantic" paragraph documenting the canonical Option D capture (committed + staged + modified-uncommitted + untracked-new files in a single pass against `$TASK_BASE_REF`, not `..HEAD`).
- **`skills/stride-completing-tasks/SKILL.md`** — New pre-completion verification checklist item explicitly testing for the inline-cat-in-jq pattern with the absolute `$CLAUDE_PROJECT_DIR/.stride-changed-files.json` path, including the rationale that reading the snapshot in an earlier shell turn picks up the prior task's snapshot.

### Changed

- **`skills/stride-completing-tasks/SKILL.md`** — Rewrote the `## API Request Format` section to lead with a `bash`/`curl` example that inlines the snapshot read via `--argjson cf "$(cat \"$CLAUDE_PROJECT_DIR/.stride-changed-files.json\" 2>/dev/null || echo '[]')"` INSIDE the `jq -n` invocation that builds the curl's `-d` payload. The JSON body shape is kept as an illustrative supplement below the bash example. A new `**Optional:**` paragraph after the `**Critical:**` line documents the snapshot-absent fallback (`changed_files: []` is a valid completion).

### Why this release (and what's NOT in it)

Mirrors stride 1.15.0 (G157/W758) into stride-codex as far as the platform allows. Other Stride plugins ship a `hooks/stride-hook.sh` that the host CLI fires as a PreToolUse / BeforeTool handler on the completion curl — the handler writes `.stride-changed-files.json` automatically. Codex CLI has no equivalent hook surface, so stride-codex's port is **SKILL.md-only**: the wire shape (`changed_files: [{path, diff}, …]`), the encoding contract, and the inline-cat-in-jq read pattern are byte-identical to the other plugins, but the *writer* is the agent (typically via a line added to the user's `.stride.md` `## after_doing` block) rather than an auto-firing handler. **No `hooks/` directory was added.** The canonical `capture_changed_files()` bash function lives in `stride/hooks/stride-hook.sh` and can be sourced or pasted by users who want byte-identical capture behavior.

### Backward compatibility

The wire shape of `changed_files` is unchanged. Completion payloads that omit `changed_files` entirely continue to validate (the empty-array form produced by the inline `|| echo '[]'` fallback is also valid). Codex tasks that ran before this release simply did not produce snapshots; their `actual_files_changed` lists still surface in `/review`.

### Source

Implemented as W735 (combined SKILL.md docs + CHANGELOG entry). No marketplace coordination — stride-codex ships by tag directly.

## [1.9.0] - 2026-05-19

### Changed

- **`agents/task-reviewer.md`** — Rewrote Step 6 ("Return Structured Review") and the Output persistence paragraph to require an unconditional fenced ```json block alongside the existing markdown prose. The block matches the canonical `reviewer_result` schema documented in [`stride/agents/task-reviewer.md`](https://github.com/cheezy/stride/blob/main/agents/task-reviewer.md) — `schema_version`, `summary`, `status`, `issue_counts`, `issues[]` (with `severity`/`category` enums), and `acceptance_criteria[]` (with `met`/`not_met` enum). Includes a verbatim worked `changes_requested` example. The prose summary line is preserved above the JSON block so orchestrator fallback paths that grep substring summaries continue to work when JSON parsing fails. No codex-specific schema variant introduced — the canonical schema is cited by path.
- **`skills/stride-subagent-workflow/SKILL.md`** — Added an "Extracting the structured review block" subsection to Phase 3 (Code Review). The orchestrator now extracts the first fenced ```json fence from the reviewer's response and populates `reviewer_result` in the completion PATCH payload with both (a) the legacy summary fields (`summary`, `issues_found` from `sum(issue_counts.values())`, `acceptance_criteria_checked` from the length of the structured array) and (b) the structured fields verbatim (`status`, `issue_counts`, `issues`, `acceptance_criteria`, `schema_version`). Includes a worked example and a documented fallback path that keeps older agent versions and parse failures working: substring-match the prose summary, omit structured fields from the PATCH (never empty placeholders), do not abort the completion.

### Source

Ported from stride 1.13.0 (commits 9c19359 "Define structured JSON review-report schema in task-reviewer agent" and 8e94eca "Extract structured review block into reviewer_result PATCH payload"). Cross-plugin parity for Stride W685/W686 (implemented in stride-codex as W696).

## [1.8.0] - 2026-05-08

### Removed

- **`skills/stride-workflow/SKILL.md`** — Removed all three references to the user-private `stride-development-guidelines` skill: the Step 5 ("Activate Development Guidelines") section, the corresponding flowchart node, and the Quick Reference Card line. That skill is project-local to the plugin author's machine and is not distributed with this plugin, so end users would have seen Step 5 instructing them to activate a skill that does not exist for them. The Step 5 slot is left empty rather than renumbered to avoid breaking step-number cross-references elsewhere in the file.

### Why this release

Cross-skill references to non-plugin skills break the workflow for end users. This guard rail is being applied to all five Stride plugins (`stride`, `stride-codex`, `stride-gemini`, `stride-opencode`, `stride-pi`) in a coordinated release.

## [1.7.0] - 2026-05-06

### Added

- **`agents/task-enricher.md`** — New custom agent that owns the four-phase enrichment procedure (intent parse, codebase exploration, complexity heuristic, 16-item validation checklist). Receives sparse task fields from the orchestrator and returns a single enriched-task JSON object ready for `PATCH /api/tasks/:id`. Ported from stride 1.11.0 (`stride/agents/task-enricher.md`) with Codex-specific frontmatter (`tools: ["read", "search", "glob"]`, no `model` field, no `skills_version` field, `.md` filename suffix). The body is platform-neutral.

### Changed

- **`skills/stride-enriching-tasks/SKILL.md`** — Slimmed from 779 lines to 268 lines. The four-phase manual enrichment procedure now lives in `agents/task-enricher.md`. The skill retains the STOP preamble, MANDATORY warning, API Authorization block, Iron Law, API integration curl examples, and output example, but the Codex CLI path now invokes `task-enricher` instead of walking the procedure inline. Other environments still follow the condensed manual walkthrough phases (Phases 1-4 retained in summary form, with the 16-item Phase 4 checklist preserved verbatim).
- **`skills/stride-subagent-workflow/SKILL.md`** — Added `task-enricher` to the agent inventory in the MANDATORY teaser block. Added a new `## Pre-Claim: Enrichment (Sparse Tasks)` section documenting when and how to invoke the enricher before claiming a task. Added `task-enricher` to the Quick Reference Card and References section. Updated the frontmatter `description:` to enumerate `task-enricher` alongside the other custom agents.
- **`skills/stride-workflow/SKILL.md`** — Step 1 enrichment check expanded into two platform subsections: `#### Codex CLI: Invoke the Enricher Agent` (3-step invoke + PATCH flow) and `#### Other Environments: Activate the Enrichment Skill` (manual-phase fallback). Matches the stride 1.11.0 platform-split pattern.
- **`.codex-plugin/plugin.json`** — Version bumped from `1.6.0` to `1.7.0`.

### Source

Ported from stride 1.11.0 (commit 92b72ea). Cross-plugin parity goal G86 / W350.

## [1.6.0] - 2026-04-29

### Platform constraint — read this first

The Codex CLI does not expose a hook system: there are no `BeforeTool` /
`AfterTool` lifecycle events, no skill-activation event, and no documented
mechanism for an extension to intercept and deny a tool call before it runs.
This means the **Layer-1 mechanical gate** that ships with stride 1.10.0 for
Claude Code (a `PreToolUse(Skill)` hook that blocks direct activation of
internal Stride sub-skills) is **not implementable on Codex today**.

This release ships the two prose-only enforcement layers from stride 1.10.0
(Layer 2 — description reframing; Layer 3 — `## STOP — orchestrator check`
preamble). Both layers are runtime-independent and rely on the Codex skill
matcher and the agent's attention to the in-body STOP block; together they
steer user prompts toward `stride-workflow` and instruct an agent that lands
in a sub-skill to back out and invoke the orchestrator instead. They are
guidance, not enforcement.

Users who expect a hard runtime gate should know it is a **platform
limitation**, not a missing implementation. If Codex CLI later adds hook
events with a documented skill-activation interception point, the gate
scripts from stride 1.10.0 can be ported with the same three-adapter pattern
used for stride-gemini 1.6.0 (see that plugin's `docs/HOOK_RESEARCH.md` for a
worked example). Until then, layers 2 and 3 are the available enforcement.

### Changed

- **All 6 sub-skill `description:` fields** (`stride-claiming-tasks`,
  `stride-completing-tasks`, `stride-creating-tasks`, `stride-creating-goals`,
  `stride-enriching-tasks`, `stride-subagent-workflow`) — Reframed as
  `INTERNAL — invoked only by stride:stride-workflow. Do NOT invoke from a
  user prompt.` Removed user-intent verbs (`claim a task`, `complete a task`,
  etc.) so Codex's auto-activation matcher no longer routes user prompts to
  the sub-skills. Wording is byte-identical to stride 1.10.0 for cross-plugin
  consistency. Frontmatter shape preserved — no `skills_version` field added
  (the stride-codex convention is `name` + `description` only).
- **`stride-workflow` `description:`** — Amplified to enumerate the explicit
  user-intent phrases that should match the orchestrator: "claim a task",
  "work on the next stride task", "complete a stride task", "enrich a stride
  task", "decompose a goal", "create a goal or stride tasks". The phrase list
  is load-bearing for Codex's matcher and should not be diluted.
- **`.codex-plugin/plugin.json`** — Version bumped from 1.4.0 to 1.6.0 (the
  manifest was inadvertently not bumped during the 1.5.0 release; this
  release re-aligns it with the CHANGELOG header).

### Added

- **`## STOP — orchestrator check` preamble** — Inserted as the first H2 of
  every sub-skill body (6 files). The 5-line block tells an agent that
  arrived at a sub-skill directly to back out and invoke
  `stride:stride-workflow` instead. Wording is byte-identical to stride
  1.10.0; the block is plain text with no emojis so it matches stride-codex's
  emoji-free header style.

### Source

Motivated by the three-layer defense designed in
`docs/plans/stride-plugin-feedback.md` (kanban repo) and ported from stride
1.10.0 (commit 5c30036).

## [1.5.0] - 2026-04-24

### Added

- **`install.ps1`** — Windows PowerShell installer mirroring the behavior of `install.sh`. Defaults to global install at `$env:USERPROFILE\.agents\`; `-Project` switch installs into `.\.agents\` in the current directory; `-Help` prints usage and exits. Uses `$ErrorActionPreference = 'Stop'`, cleans up its temp clone directory in a `finally` block, checks for `git` on `PATH` with a friendly error if missing, and preserves the per-skill `skills/<name>/SKILL.md` layout the Codex CLI expects. Can be invoked via `irm https://raw.githubusercontent.com/cheezy/stride-codex/main/install.ps1 | iex` or the scriptblock wrapper `& ([scriptblock]::Create((irm ...))) -Project` for project-local installs.
- **`README.md`** — New "Windows (PowerShell)" section under Installation documenting the global one-liner, the project-scoped scriptblock-wrapper one-liner, and a download-then-run variant. Added a Windows manual-install block using `Copy-Item` alongside the existing bash `cp -r` version. Notes PowerShell 5.1+ / PowerShell Core 7+ and Git for Windows as prerequisites.

## [1.4.0] - 2026-04-16

### Added

- **`stride-completing-tasks` skill** — Surfaced `explorer_result` and `reviewer_result` in six places so agents cannot forget them: (1) the MANDATORY teaser at the top of the skill lists both as required alongside the hook results; (2) the pre-completion Verification Checklist asks whether both are included; (3) the primary API Request Format example includes both in the self-reported skip shape (Codex's weaker custom-agent support makes skip the primary path); (4) a new "Explorer/Reviewer Result Schema" section leads with the skip shape, then documents the dispatched shape, the five-value skip-reason enum (`no_subagent_support`, `small_task_0_1_key_files`, `trivial_change_docs_only`, `self_reported_exploration`, `self_reported_review`), the 40-character non-whitespace summary minimum, a 422 rejection example, and the feature-flag grace-period rollout; (5) the Completion Request Field Reference table lists both as required objects; (6) the Quick Reference Card's `REQUIRED BODY` includes both plus a SKIP FORM snippet.
- **`stride-workflow` skill** — Step 8's Required Fields table and JSON payload example now include `explorer_result` and `reviewer_result` using the skip shape as the default. A new "Explorer and Reviewer Result Rollout" section after "Workflow Telemetry" describes the grace-mode/strict-mode feature-flag phases and directs readers to `stride-completing-tasks` for the full shape (no schema duplication). Orchestrator prose explains that Steps 3 and 6 already produce the data needed to populate these fields in Step 8, and that the skip form is the default path on Codex.

## [1.3.0] - 2026-04-14

### Added

- **`stride-workflow` skill** — New "Workflow Telemetry: The `workflow_steps` Array" section documenting the six-entry step-name vocabulary (`explorer`, `planner`, `implementation`, `reviewer`, `after_doing`, `before_review`), per-step schema (`name`, `dispatched`, `duration_ms`, `reason`), full-dispatch and skipped-step examples, and rules for assembling the array. Step names are identical to the main stride plugin so Stride can aggregate telemetry across agents and plugins.
- **`stride-completing-tasks` skill** — `workflow_steps` now appears in the verification checklist, the API Request Format example, the Completion Request Field Reference table, and the Quick Reference Card REQUIRED BODY. Added a Schema Reference paragraph pointing at `stride-workflow` as the source of truth for the array shape.

### Changed

- **`stride-completing-tasks` skill** — "Critical" note under the payload example now lists `workflow_steps` alongside the two hook-result fields as required. The API will reject completions that omit it.

## [1.2.0] - 2026-04-13

### Changed

- **`stride-claiming-tasks`** — Replaced soft "Recommended" orchestrator section with non-negotiable "YOUR NEXT STEP" gate demanding stride-workflow activation immediately after claiming. Added workflow violation warning to standalone mode.
- **`stride-completing-tasks`** — Added "BEFORE CALLING COMPLETE: Verification Checklist" with 4 yes/no items covering orchestrator activation, codebase exploration, acceptance criteria review, and hook readiness.

## [1.1.0] - 2026-04-13

### Added

- **`stride-workflow` skill** — Single orchestrator for the complete Stride task lifecycle adapted for Codex CLI. Walks through prerequisites, claiming, codebase exploration (via custom agents with graceful fallback), implementation, code review, manual hook execution, and completion in a single skill. Uses process-over-speed messaging. Eliminates the need to remember which skills to activate at which moments.

### Changed

- **`stride-claiming-tasks` skill** — Reframed automation notice from throughput-emphasizing ("FULLY AUTOMATED") to process-over-speed ("The workflow IS the automation"). Added "Recommended: Use the Workflow Orchestrator" section pointing to `stride-workflow`. Renamed "MANDATORY: Next Skill After Claiming" to "Next Skill After Claiming (Standalone Mode)".
- **`stride-completing-tasks` skill** — Reframed automation notice from throughput-emphasizing to process-over-speed. Added "Arriving from stride-workflow" section. Renamed "MANDATORY: Previous Skill Before Completing" to "Previous Skill Before Completing (Standalone Mode)". Added `stride-workflow` as first entry in the prerequisite skills list.
- **`AGENTS.md`** — Updated Workflow Sequence to recommend `stride-workflow` as preferred entry point, with standalone skill chain as alternative.
- **`README.md`** — Added `stride-workflow` to Workflow Order (as recommended) and Skills table. Existing standalone workflow preserved as alternative.

## [1.0.0] - 2026-03-26

### Added

**Skills (6)**
- `stride-claiming-tasks` — Task claiming with manual before_doing hook execution
- `stride-completing-tasks` — Task completion with manual after_doing and before_review hooks
- `stride-creating-tasks` — Task creation with field format validation
- `stride-creating-goals` — Goal and batch creation with dependency management
- `stride-enriching-tasks` — Automated codebase exploration to enrich minimal tasks
- `stride-subagent-workflow` — Decision matrix for agent dispatch based on complexity

**Agents (4)**
- `task-explorer` — Read-only codebase exploration for key_files and patterns
- `task-reviewer` — Code review against acceptance criteria, pitfalls, and patterns
- `task-decomposer` — Goal decomposition into dependency-ordered child tasks
- `hook-diagnostician` — Hook failure diagnosis with prioritized fix plans

**Configuration**
- `AGENTS.md` — Codex configuration bridge with skill activation rules and tool mapping

**Documentation**
- `README.md` — Installation, skill chain, manual hook execution, troubleshooting
- `CHANGELOG.md` — This file
