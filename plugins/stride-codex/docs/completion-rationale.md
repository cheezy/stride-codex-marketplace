# Background to the stride-completing-tasks skill

Codex CLI reads `skills/stride-completing-tasks/SKILL.md` in full each time a task reaches `/complete`. A paragraph there that argues for a step, or recounts where a step came from, is paid for on every one of those reads and puts nothing into the payload, so those paragraphs were moved to this page. Each section names the place in the skill it came from, and that place keeps a one-line pointer here.

**Nothing here is a rule.** The Completion Request Field Reference, Shape 1 and Shape 2, the enum of skip reasons, the pre-submission self-check and the redaction rules are all still in the skill, and a completion assembled without ever opening this page is still correct. If the two disagree, follow the skill and fix this page. The moved text is kept as it stood, apart from the excuses table and the before-and-after figures, which each gained a sentence saying their numbers have no recorded source, the diff-capture section, which gained a note on what has changed since, and the severity table, whose dropped column is shown on its own.

## Fields Discovered One Rejection at a Time

*From `skills/stride-completing-tasks/SKILL.md`, THIS SKILL IS MANDATORY, the paragraph under the required-field list.*

**Attempting to complete a task from memory without this skill results in 3+ failed API calls** as you discover each missing field one at a time. This has been observed in practice.

## The Steps Agents Dropped Under Pressure

*From `skills/stride-completing-tasks/SKILL.md`, BEFORE CALLING COMPLETE: Verification Checklist, the closing paragraph.*

Skipping these steps is not faster — it produces lower quality work that takes longer to fix. This checklist exists because agents consistently skipped these steps under pressure to deliver quickly.

## Why Diff Capture Is Manual in Codex

*From `skills/stride-completing-tasks/SKILL.md`, Per-File Diff Capture (Manual).*

**Why this is manual in Codex.** Codex CLI does not support automatic hook
interception. The other Stride plugins (stride, stride-copilot, stride-gemini,
stride-pi, stride-opencode) ship a `hooks/stride-hook.sh` that the host CLI
fires as a PreToolUse / BeforeTool handler on the completion curl — the
handler writes `.stride-changed-files.json` automatically during the curl
call. Codex CLI has no equivalent surface, so the agent is responsible for
producing the snapshot itself. The wire shape and the inline-cat-in-jq read
pattern are identical to the other plugins — only the writer changes.

That passage was written before W2141 and W2181 gave this port a hook surface. Those hooks record loop state and refuse a Stride call that hides its response, but they never write `.stride-changed-files.json`, so the conclusion still holds while "does not support automatic hook interception" no longer does. Of the plugins it names, only stride, stride-copilot and stride-gemini ship a `hooks/stride-hook.sh`; stride-pi and stride-opencode have no `hooks/` directory.

## Why stride-codex Does Not Vendor the Trust Guard

*From `skills/stride-completing-tasks/SKILL.md`, Per-File Diff Capture (Manual), the trust-guard decision.*

The trust guard exists to repair a base ref that was captured
*before* `before_doing`'s pull, or inherited stale from a prior task/session —
both of which this skill set now prevents at the source: the base is captured
*after* `before_doing` completes and persisted to a fresh `.stride/task-base-ref`
each claim (`stride-claiming-tasks` step 6 `unset`s any inherited value first).
With the pre-pull and inherited-base vectors already closed, the guard's only
remaining benefit is the push-in-`after_doing` / push-before-complete edge, which
the guard resolves against `origin` refs and a once-per-task-window memoization —
machinery that has no home in Codex's manual, hook-less, single-capture flow
(there is no persisted `base=` self-heal to share a judgment with). Vendoring it
would add a second function and a per-capture `origin`-diffing step for a
narrow edge that the post-`before_doing` capture already makes rare.

## Why the Summary Line Matters When No Reviewer Ran

*From `skills/stride-completing-tasks/SKILL.md`, Recording Manual & Exploratory Testing Findings, carrier 3 (`completion_summary`).*

This matters most in exactly the case carrier 2 cannot cover — when no reviewer ran, `completion_notes` is otherwise the sole carrier.

## Which Severity Boundary the Mapping Gives Up

*From `skills/stride-completing-tasks/SKILL.md`, Recording Manual & Exploratory Testing Findings › Severity mapping.*

The mapping table once carried a third column that summed up each exploratory level. It shortened the `bug-advocacy` ladder for orientation and was never authoritative. It read:

| Exploratory severity | Why it lands there |
|---|---|
| **Critical** | A boundary that must hold was crossed, committed data destroyed, money or a legal obligation wrong, a secret exposed, or the product's primary purpose taken away. `critical` is the only reviewer value carrying the same cannot-ship disposition. |
| **High** | Something incorrect survives — valid data persisted wrong or lost but identifiable, a main workflow blocked, success falsely reported. *Fix before proceeding.* |
| **Moderate** | A real workflow degraded, a secondary feature broken, or an error the user cannot act on. Nothing incorrect survives, but it is still *fix before proceeding*, which is what `important` means. |
| **Minor** | Presentation only, or the only casualty was already-invalid input. *Optional but recommended*, which is what `minor` means. |

**Where the four-into-three collapse falls, and why it falls there.** One boundary has to be lost. The exploratory ladder's sharpest *descriptive* line is High/Moderate — whether wrong state survives — but the reviewer enum is not descriptive: its three values are **dispositions at the completion gate** (`critical` and `important` both mean *fix before proceeding*; `minor` means *optional but recommended*). So the boundary to lose is the one whose two sides share a disposition, and that is High/Moderate. Collapsing Moderate into `minor` instead would file a broken export or an unactionable error alongside a truncated label — the deflation `bug-advocacy` warns costs exactly as much credibility as inflation.

## The Excuses Table and Its Unsourced Figures

*From `skills/stride-completing-tasks/SKILL.md`, the Rationalization Table section, which followed Red Flags - STOP.*

No source, sample size or date was ever recorded for the percentages and durations in this table, so read them as a picture of the intended effect, not as a measurement.

| Excuse | Reality | Consequence |
|--------|---------|-------------|
| "Tests probably pass" | after_doing catches 40% of issues | Task marked done with failing tests |
| "I can fix later" | Task already marked complete | Have to reopen, wastes review cycle |
| "Just this once" | Becomes a habit | Quality standards erode completely |
| "before_review can wait" | API requires both hook results | Request rejected with 422 error |
| "Hooks take too long" | 2-3 minutes prevents 2+ hours rework | Rushing causes failed deployments |

## Before and After Figures for Running Hooks First

*From `skills/stride-completing-tasks/SKILL.md`, the Real-World Impact section, which came after the Quick Reference Card.*

These figures have the same gap as the excuses table above: nothing says where or over how many completions they were measured.

**Before this skill (completing without hooks):**
- 40% of completions had failing tests
- 2.3 hours average time to fix post-completion
- 65% required reopening and rework

**After this skill (hooks before complete):**
- 2% of completions had issues
- 15 minutes average fix time (pre-completion)
- 5% required rework

**Time savings: 2+ hours per task (90% reduction in post-completion rework)**
