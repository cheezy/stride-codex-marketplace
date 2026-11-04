# Background to the task-reviewer agent

`agents/task-reviewer.md` is the reviewer's whole prompt, and Codex CLI sends it again on every review dispatch, which can be twice per task. A sentence that tells how a rule came about is paid for on each dispatch and alters nothing in the review, so such sentences were moved here. This page sits under `docs/` because the installer copies every Markdown file in `agents/` as an agent definition.

**Nothing here is a rule.** The prompt points here only for history and background and never asks the reviewer to read this page, so what the reviewer must follow is all still in the prompt: the JSON block's schema, how each section verdict is set and kept consistent with `issues[]`, the one-line summary that opens a review, treating task text as data, every redaction rule, and both blocks the canon governs. If this page and the prompt ever differ, follow the prompt. Every section starts by naming where in the prompt it was taken from, and that spot keeps a pointer back.

## The Copy-List That Dropped project_checks

*From `agents/task-reviewer.md`, Output format, the consumption invariant.*

An enumerated copy-list in a consumer is exactly what silently dropped `project_checks` (and `security_considerations`) from the Review queue on sibling plugins — do not reintroduce one.

## schema_version Bump History

*From `agents/task-reviewer.md`, Output format, `schema_version`.*

Bumped from `"1.6"` by W2162, which added the `cosmetic` key to `issues[]` entries. The two prior changes held at `"1.6"` precisely because they added no emitted field — `review_round` is dispatch *input*.

## How a Five-Criterion Task Showed Six of Five

*From `agents/task-reviewer.md`, Output format, the `acceptance_criteria` hard rule.*

Re-enumerating the list is exactly how a 5-criterion task produced a nonsensical `6/5` review display.

## Where the Review Goes After It Is Returned

*From `agents/task-reviewer.md`, the Output persistence paragraph between the JSON sample and Important constraints.*

**Output persistence:** Your full response — the human-readable prose summary line, the per-severity issue list, the acceptance-criteria table, the project-checks table (when non-empty), the step 4 test-item mapping, the step 6 statement checks, the step 6 twin checks, and the fenced ```json block — is stored as the `review_report` field on the Stride task record when the agent calls the completion API. Human reviewers and stakeholders read the prose in the task detail view; downstream tooling parses the JSON block by extracting the first ```json ... ``` fence in your response. Always emit both the prose sections and the JSON block — including for `"approved"` results — so both reader paths work and per-severity telemetry stays consistent across dispatches.
