# Background to the stride-workflow skill

Every task makes Codex CLI read the whole of `skills/stride-workflow/SKILL.md`, so prose that explains a rule without stating one costs context each time and helps no step. The passages below were taken out of that file for that reason. Each section names where it came from, and the skill keeps a one-line pointer there naming the section.

**Nothing here is a rule.** The skill is the authority; nothing in a task needs this page opened, and where the two ever disagree, follow the skill and fix this page. The text is kept as it stood in the skill, except where a clause had to become a sentence of its own: there the opening was rephrased, in three sections (Why Step 0 Is the Only Place to Ask, The Pre-Pull Base Ref Incident, and How a Re-Review Showed Six of Five Criteria).

## The Session That Led to One Orchestrator

*From `skills/stride-workflow/SKILL.md`, Purpose.*

During a 17-task session, an agent consistently skipped mandatory workflow steps despite skills being labeled MANDATORY. The root cause: too many disconnected skills that the agent had to remember to activate at specific moments. Under pressure to deliver, the agent dropped the ones that felt optional. This orchestrator eliminates that failure mode.

## Why Step 0 Is the Only Place to Ask

*From `skills/stride-workflow/SKILL.md`, Step 0, item 3.*

Step 0 being the one point where asking is legal is not a general property of orchestrators; it is specific to this port: Step 6.5's sanctioned-surface rule bars every plugin surface that collects this affirmative — `stride-exploratory-testing-explore` and `-recon` are disqualified *precisely because* their rounds include an authorization/non-production confirmation, which is a safety control this workflow may not satisfy on the user's behalf. So no other route to the affirmative exists.

## Why the Ignore-File Note Comes at Step 0

*From `skills/stride-workflow/SKILL.md`, Step 0, item 4.*

Step 0 is the only step that runs once per session and the only point where addressing the operator is sanctioned — Step 6.5 only runs once a session is already under way, so saying it there would be too late by construction.

## The Pre-Pull Base Ref Incident

*From `skills/stride-workflow/SKILL.md`, Step 2, the base-ref paragraph.*

A base captured before the pull is how D132 happened: a reviewer saw another machine's completed task inside an unrelated defect's Review diff.

## The Plan Trigger Branch C Once Carried

*From `skills/stride-workflow/SKILL.md`, Step 3, Branch C item 2.*

This item previously stated its own trigger ("medium+ OR 3+ key_files OR 3+ acceptance criteria lines"), which could fire on a row whose `Plan` column says Skip — the `small, 2+ key_files` row being the collision.

## Why New Tests Need Break-It Evidence

*From `skills/stride-workflow/SKILL.md`, Step 4, the break-it procedure.*

In stride the same mistake kept coming back, a test that still passed with its code broken: one task's assertions were all satisfied by prose elsewhere in the file (W2035), an `ok()` placed outside its loop passed unconditionally (W2036), a cap went from 8 to 1000 with the whole suite still passing (W2034), and an unclosed quote hid two assertions (W2171). Review fix rounds slipped back into it as well (W2181, D337). Each was found only because a reviewer happened to mutate the code by hand. The reviewer never runs code, so the evidence has to come from the implementer.

The tree hash adds content to `git status`, because at Step 4 every file you touched is already modified: a break left inside one of them does not change its status line, but it does change the diff the hash covers. The hash stays in your notes rather than a file because a file in the tree would change the very thing it records.

The procedure lives inline in Step 4 rather than in a sibling file, as it does in stride, because `install.sh` and `install.ps1` copy only each skill's `SKILL.md`; a sibling file would never reach an install.

What the record cannot do: the reviewer can check that each entry fits the diff, that its break lands on what the test asserts, but it cannot rerun one, so an entry is the implementer's word. What it does rule out is a test that goes in without anyone ever having watched it fail.

## Why Step 5 Is Blank

*From `skills/stride-workflow/SKILL.md`, Step 5.*

Step 5 formerly activated the project-author-private `stride-development-guidelines` skill, which is not distributed with this plugin. The number is kept empty rather than renumbering Steps 6–9 so the file's many cross-references to those steps stay stable.

## The Review Trigger Step 6 Once Carried

*From `skills/stride-workflow/SKILL.md`, Step 6, opening paragraph.*

This line previously restated its own trigger ("medium+ OR 2+ key_files"), which disagreed with the matrix for a `small` defect with 1 `key_file` — the same defect class, in the Review column instead of the Plan column.

## How a Re-Review Showed Six of Five Criteria

*From `skills/stride-workflow/SKILL.md`, Step 6, re-review and follow-up rounds.*

A re-review that re-enumerated the criteria in its own words is how a re-review round on task W1099 turned a 5-criterion task into a `6/5` review display.

## Why Review Rounds Are Capped

*From `skills/stride-workflow/SKILL.md`, Step 6, the round-cap paragraph.*

The round cap exists because an uncapped review loop does not converge: a reviewer asked to review always finds something, and every additional round costs a full reviewer invocation to buy progressively less.

## Why a Round Is Counted From the Parsed Block

*From `skills/stride-workflow/SKILL.md`, Step 6, what counts as a round.*

Stride keys its count on a merged result file, because that file is the *product* of a dispatch rather than the dispatch itself — and that indirection is the whole load-bearing property. This port writes no such file: its reviewer returns the structured block inline, so **the parsed block is the only artifact an invocation here produces**, and it carries the same property on a surface this port actually has.

## Why a Specialist Reviews the Security Considerations

*From `skills/stride-workflow/SKILL.md`, Step 6, deep security-considerations review.*

The task-reviewer already records a `security_considerations` section verdict, but as a generalist. When the stride-codex-security-review plugin is installed, this sub-step runs the *specialist* `security-reviewer` agent against each of the task's `security_considerations`, folds a per-consideration verdict into the completion payload, and routes any un-addressed consideration through the same gate that already blocks on a failed section — so a real, unmitigated security implication cannot reach Done.

## Why Manual Tests Become Charters

*From `skills/stride-workflow/SKILL.md`, Step 6.5, Why this step exists.*

Tasks routinely carry `manual_tests` in their `testing_strategy`, but the workflow has historically had no way to actually perform them — they were left to a human or silently skipped. When the stride-codex-exploratory-testing plugin is installed, each manual test becomes a **charter** and the explorer runs a real, budgeted exploratory session, closing the gap between "tests written" and "tests performed."

## Turning a Found Bug Into a Regression Check

*From `skills/stride-workflow/SKILL.md`, Step 6.6.*

A session that finds a bug and stops has closed nothing — the same bug can return unnoticed. The harden skill reads the bugs a session confirmed and drafts one regression check per convertible bug, which is the step that turns *Explored* back into *Checked*. It is the only place the workflow can close that loop automatically.

## Why dispatch_count Records No Token Count

*From `skills/stride-workflow/SKILL.md`, Workflow telemetry, Why not a token count.*

The obvious fix for limit 1 is to record tokens, the only figure observed to rank correctly, and this task explicitly ruled that out: **do not invent a token count — record what is actually measurable.** Be precise about why, though, because the usual justification is wrong: in at least some runtimes a per-dispatch token cost **is** measured and available, so recording it would not be inventing it. The open question is **portability** — whether every runtime this schema serves can produce one — and that is unsettled. Until it is, this pair is what there is, read within the limits above.

## The Strict-Validation Rollout

*From `skills/stride-workflow/SKILL.md`, Explorer and Reviewer Result Rollout.*

The server is rolling out hard enforcement behind a feature flag `:strict_completion_validation`:

| Phase | Server behavior | Agent impact |
|---|---|---|
| **Grace (current)** | Missing or invalid results log a structured warning and the request succeeds | Emit the fields correctly now; the warning volume is a preview of the strict-mode rejection volume |
| **Strict (after all 5 plugins release)** | Missing or invalid results return `422` with a `failures` list | Any agent not emitting valid fields is locked out of completion |
