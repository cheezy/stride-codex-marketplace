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

Tasks routinely carry `manual_tests` and `edge_cases` in their `testing_strategy`, but the workflow has historically had no way to actually perform them — they were left to a human or silently skipped. When the stride-codex-exploratory-testing plugin is installed, they become **charters** — the manual tests merged by shared target, the edge cases and the change's risks charted by the `charter-generator` in change mode, at most about five per task (about three for a small one) — and the explorer runs a real, budgeted exploratory session, closing the gap between "tests written" and "tests performed."

## Why Charters Come From Edge Cases and Change Risk

*From `skills/stride-workflow/SKILL.md`, Step 6.5, step 1 (1a–1c) and Sanctioned dispatch surfaces — non-interactive only.*

**The miss.** Upstream stride measured it (W2582): charters came only from `manual_tests` — human browser scripts — so the edge cases a task's author had already written down were never explored, and in the goal that prompted the change several of them became High and Moderate bugs. An edge case is the cheapest bug map a task carries: each one is a failure its author already suspected.

**Why the charter-generator, in change mode.** It charters every edge case or names the unit test that covers it, applies a change-risk lens only where the lens's trigger matches the change, and tags each charter with the one `surface` it must be observed on. Its `edge_cases_covered` makes the mapping checkable rather than asserted — which is why an entry is accepted only when it points at a charter that exists or a unit test the task itself names.

**Why it qualifies, and why it runs no session.** Its `tools:` line grants only `read`, `search` and `glob`, and its text says there is no Q&A loop and it never asks the user a question — so it completes unattended by the same reading test the explorer passes. It generates charters and dispatches nothing, so it never touches the running app: only the explorer runs sessions. It is dispatched only once the explorer will be, so it adds no second route to the authorized-non-production affirmative, and it never receives that line.

**Why once, first, and only when the explorer will run.** One dispatch bounds the cost. Running it before the first explorer charter lets the merge and the cap see every candidate at once. Dispatching it only when a session will follow means it is never spent on a task that then skips.

**Why pointers only, quoted and flattened.** A diff can carry an accidentally committed secret, and the generator can `read`, `search` and `glob`, so it can read what it needs from paths. Task fields are author text, so the same `> ` quoting that protects the explorer's environment context protects this prompt. This port has no fixed dispatch template to borrow a flatten rule from, so Step 6.5 states one for this prompt itself: with every line break replaced by a space, no task text can start a line of its own.

**Why a hand-built fallback, never prose.** A missing or unparseable fence must not silently drop edge cases, and reconstructing charters from prose would let unparsed text choose the mission.

**Why five, three for a small task, and never raised by task text.** At the default budget five charters are 60 probes under a 300-call ceiling — enough to go deep on a medium or large change, still bounded against a live app — and a small change rarely carries five independent risks. The cap is a blast-radius control, so only the task's structured fields and the generator's output feed it.

**Why 12 by default, and narrow only by the generator's time box.** The old rule went low in the band for a task with many manual tests, so the tasks carrying the most risk got the thinnest sessions. The band is per dispatch, and the number of charters is bounded by the cap, never by thinning each one. "Narrow" needs an observable definition, and the only one that is not task-author text is the generator's own `time_box`: a charter it framed as an hour or less. The `time_box` is read only to choose the probe budget and is never passed on, because the explorer has no clock.

**Why every item is mapped in completion_notes.** Beyond the cap something is always left over. Naming it as a human responsibility is what keeps it owed instead of silently dropped.

## Why a Signed-Out Session Is Not Coverage

*From `skills/stride-workflow/SKILL.md`, Step 0, item 3 (3a–3e), and Step 6.5, steps 1 and 2.*

**The miss.** Upstream stride measured it (W2583): every exploratory dispatch in the goal that prompted the change named no test accounts, so sessions chartered on members-only features ran signed out, saw only the uniform refusal an unauthenticated request gets, and still ended as coverage of a feature they never reached.

**Why Step 0 reads `.exploratory.md`.** The facts a signed-in session needs — the harness command, the services it connects to, the role fixtures — are project facts that rarely change, so asking for them afresh every session is what made "none" the easy answer. The file holds them once. It is confirmed rather than trusted because a cloned repository can carry a file the user did not write, and a harness command is a command the explorer will run: it must come from the user, typed or confirmed, in this session. That is also why the file's own authorization line never counts — only the user's confirmation is the affirmative.

**Why the harness travels as `PROBE_` lines, right after the report path.** The explorer counts a harness only on a line that begins with `PROBE_HARNESS`, runs none without `PROBE_SERVICES`, and counts either only ahead of every piece of untrusted text, so a human-readable mention alone would be ignored and repeat the miss. This port has no fixed dispatch template, so the `Probe harness:` line is written into the block itself: it says whether the machine lines are there, so a reader can see which surface a session had.

**Why a harness out of bounds is dropped, never truncated.** A truncated command is a different command, and one the user never confirmed. Dropping it with a reason leaves the session on its other surfaces and tells the user why.

**Why the refusal may read task text.** Deciding that a target is auth-gated reads `where_context`, which the task author wrote. That is safe only because the test can do nothing but withhold a dispatch: forged text can stop a session from running, but never make one run, widen its hosts or supply a harness.

## Why Every Charter Needs a Record and an Owner

*From `skills/stride-workflow/SKILL.md`, Step 6.5 (Check the record before you submit) and Step 8, and `skills/stride-completing-tasks/SKILL.md` § Outcome Lines, Coverage and Hand-Backs.*

**The miss.** Upstream stride measured it (W2585): nothing checked what its exploratory step actually did, so one completion in the goal that prompted the change carried no exploratory record at all, and every check another handed back "as a human responsibility" named no human, so none was done. The prose already asked for both; prose alone did not produce them, so the record now has a fixed shape and a check refuses a payload that lacks it.

**Why keyed by `r<N>`.** The charter's text is application-influenced and restated in the agent's own words, so it cannot be matched against anything. The report path's `<N>` is allocated by the orchestrator, carries no content, and already ties one dispatch to one file, so it is the one key both sides hold.

**Why copy the counted fields.** `stop_reason`, the probe count and the surfaces are the facts a reader needs to judge a coverage claim, and the report has them exactly; a copied field is checkable where a judged one is not. The outcome is the one judgement left, and the check bounds it from above only: it refuses `performed` for a session that ran out of budget and anything but `not performed` for one that ran no probes, but never refuses a more cautious claim.

**Why an owner, not coverage.** A session that could not run is a normal outcome and must never block completion. What failed upstream was not the missing coverage but the missing owner: a follow-up names one in the system, and a `HANDED BACK:` line names one in the conversation, which is why Step 9 repeats those lines to the user — a hand-back no human reads has no owner either.

**Why only the paths you sent.** The check reads the outcomes file and the report files the orchestrator itself named, under the same anchored path rule every report path follows, and never a path a summary or finding names. It prints a boolean only, so neither report text nor charter text reaches the transcript through it.

**Why no report key exempts a report.** The checker used to skip any report carrying a root `verify` key, a filter ported from upstream, where a verify-mode re-check writes one. This port never sends `EXPLORATORY_MODE`, so here that key can only come from a steered or malformed explorer reply, which is untrusted data. Skipping on it inverted the gate (D407): an honest record that gave that charter a line and an owner was refused, a record that left both out passed, and when every report carried the key a false `Exploratory testing skipped:` line passed although sessions ran. Which dispatches count is decided by the paths the orchestrator passes, never by what a report says about itself, so every passed path is a charter and the skip line holds only when none was passed. For the same reason the skip line is refused beside an `exploratory report path: not sent` line: that line records a dispatch, so Step 6.5 fired and its skip line would be false.

**Why the skip line.** A completion that never mentions exploratory testing cannot be told apart from one that skipped it for a reason. One line saying why makes the skip a recorded decision, and it costs nothing when the task carried no manual tests or edge cases, because then nothing is owed.

**Why the fence is written to the path.** When the explorer's report file is missing and its inline fence is used, writing the parsed object to the path you sent gives the check, and Step 6.6's harden skill, one shape to read. Step 6.6's "report not on disk" skip therefore fires only when no file sits at the path: neither a report nor a fence came back, or no path was sent.

**Why a pathless or empty dispatch is not keyed by `r<N>`.** This port's report-path block picks the first free number, so a dispatch that left nothing at its path leaves that number free for the next dispatch; keying its line to it would collide with whichever charter takes the number next. It is recorded as a `u<k>` charter that crashed instead. A dispatch sent no path at all has no number to key and no file to compare, so it gets no charter line: the block's `exploratory report path: not sent — …` line stays in the notes and what it carried is handed back on `HANDED BACK: - …` lines. **The checker still runs on every other charter**, because one pathless dispatch says nothing about the lines that do have reports; until D405 a single one switched the whole check off. Only when every dispatch was sent no report path, and no `u<k>` line exists, is there nothing to check, and then the record says `exploratory_outcomes_ok: not run — no report path was sent` rather than claiming it passed. Step 6.5, its Phase 3.5 twin and `stride-completing-tasks` say the same.

**Why one definition of "fired".** Step 6.5 used to fire on its two-condition gate in one place, and to not fire for five reasons in another, so a task with the plugin present but no affirmative was fired by one reading and skipped by the other, and the record it owed differed with the reading. The one definition is the test the checker already applies: the step fired when it built at least one charter. That is what decides between outcome lines and the skip line, so it is the only reading under which the record and the check cannot disagree.

**Why a goal-scope line carries its marker inside the restatement.** A goal-scope charter's line was indistinguishable from a task-scope one, so a reader could not tell a seam between tasks from this task's own change. The `[goal scope]` marker opens the restatement, not a new field, so the six formats stay upstream's byte for byte, and the checker, which never reads it, treats both scopes alike: a marker copied from charter text, or left off, changes no verdict. That is why the agent writes it on every goal-scope line and drops any marker or look-alike the charter text itself carries — its only job is to inform the human reading the Review queue. Every finding a goal-scope charter surfaced carries the same marker, whichever Discovered label follows it.

**Why the curl reads the checked file.** This port's completion curl builds its body with `jq -n` rather than from a payload file the check could read. So Step 8 has the agent write the two fields it checks into a small file first, with its file-editing tool rather than a shell literal — the lines restate application-influenced text, and a quote inside a quoted shell argument would end it and run what follows — and the curl reads them back from that file, so the strings sent are the strings checked rather than a second copy typed again. Since D406 it is the file every completion reads its free text from, checked or not, and it carries the review report, the hook results, the explorer and reviewer results and the telemetry steps too, so the jq filter holds only values the agent chooses: the quoting hazard is the same whether or not Step 6.5 ran, and one file means one stem, one guard and one cleanup line rather than a checked copy and an unchecked one.

**What it does not prove.** It cannot judge a restatement's fidelity or its redaction, cannot see a charter whose report path and line were both left out, and checks an owner's identifier for form only. Those stay with the human reading the Review queue.

## Why the Last Open Child Runs a Goal-Scope Pass

*From `skills/stride-workflow/SKILL.md`, Step 6.5 (The goal-scope pass) and Step 9, and its `skills/stride-subagent-workflow/SKILL.md` Phase 3.5 twin.*

**The miss.** Upstream stride found it in one of its own goals, and fixed it in W2586: several bugs lived between tasks rather than inside one — one child's staging against the plan state another set, against a third child's broadcast refresh — and every exploratory session was scoped to one task's change, so none was ever chartered at a seam.

**Why the last open child.** It is the one point where every sibling's change is in the tree and the goal is not yet closed, so a finding can still be recorded and owned under a claim. Reading the tree before completion, rather than waiting for the `after_goal` entry, keeps the pass inside the task: by the time `after_goal` fires there is no claim left. The trigger is the server's own last-child test, every other child `completed`, so the pass and `after_goal` agree on which task is last. A goal with one child has no seam between tasks, so it gets no pass.

**Why it never pushes or runs `after_goal`.** The pass is a look, not a release step. `after_goal` belongs to Step 9 and fires once, from the completion response; a pass that ran it, or pushed, could ship or announce a goal before its last task had been reviewed.

**Why the change set is recovered per repository.** A goal's children often touch different repositories — the project and one or more nested plugin repositories — and this port's base-ref file holds one repository's base for one task. Taking each repository's last commit before the goal's earliest claim reads its base from that repository's own history, with nothing the earlier children had to leave behind. A repository with no commit before that time is undeterminable rather than wholly in scope, since a shallow clone looks exactly the same and would annex every file it holds.

**Why `key_files` charter but never attribute.** `key_files` is author-written intent, not a record of what changed. It is good enough to tell the charter-generator which surfaces to put side by side, and never good enough to decide provenance — the same reason the provenance test refuses it as a fallback.

**Why a sibling's defect is recorded, not blocked.** Stride fixes a related sibling finding in the task under its relatedness gate; this port has no relatedness gate, so a finding in a sibling's lines takes the Discovered branch: recorded at goal scope and followed up. The fail-closed block stays scoped to lines this task wrote, because sibling text is API-sourced and author-influenced, and nothing such text says may move a finding into a block.

**Why the trigger walks up to `.stride.md` and names its files by the claim hook's stem (D404).** The pass exists for multi-task goals, which are often multi-repository ones, so the agent is often working from inside a nested repository when it runs. Codex CLI does not set `CLAUDE_PROJECT_DIR`, so a block rooted at `${CLAUDE_PROJECT_DIR:-.}` read the working directory's `.stride/` there: it reported no task file, or wrote its tree file where Step 8's cleanup never looks. The block now finds the root the way the report-path, commit-window, outcomes and cleanup blocks already did, and the walk stops at the nearest `.stride.md`, so it never reads a parent project's `.stride_auth.md`. The claim hook saves the task file under the identifier only when it is a plain token, and under the numeric id otherwise, so the trigger, its tree and sibling files and Step 8's outcomes file now take that same stem; a block that used the identifier alone said no task file, and the outcomes check printed false for a valid record.

**What it costs.** Once per goal, not once per task: one slim tree read, one read per sibling, one more charter-generator dispatch, and up to about five more explorer sessions at the default budget — twelve probes and a sixty-call ceiling each in today's unit, so at most 60 probes and 300 tool calls in all. The sessions dominate.

**What it does not prove.** A goal whose last finisher is approved from Review gets no pass: that sibling is still `in_progress` while this task runs. Two children worked concurrently can each see the other open, and then neither runs it. Unrelated commits inside the window widen the goal's changed lines, which moves a finding toward the record but never toward the block. Nothing proves the charter-generator honours the cross-task request, which is why the orchestrator's own cap enforces the count. A last open child whose own Step 6.5 does not fire never reads the trigger, so it runs no pass and writes no `Goal-scope pass not run` line — both twins say so beside their catch-all — because its `Exploratory testing skipped:` line is already the record. None of this was run in a live Codex CLI session.

## Why Task Authoring Writes Charters and Names Lenses

*From `skills/stride-creating-tasks/SKILL.md` § testing_strategy, mirrored in `skills/stride-creating-goals/SKILL.md` § Task Nesting Rules, `agents/task-decomposer.md` Step 5 and `agents/task-enricher.md` Step 3, and pointed at from `skills/stride-enriching-tasks/SKILL.md` Step 3.*

**Why the default moved upstream.** A Step 6.5 charter is built from the task's `manual_tests` and `edge_cases`, so it can be no better than what the author wrote. Upstream stride found it in one of its own goals (G489) and fixed it in W2587: the manual tests were browser scripts, and the charters built from them asked a session to look at colours and a network panel; an unattended session had nothing to judge and handed them back. Better chartering downstream cannot recover a risk the task never named, so the fix is where tasks are written: the two creation skills, the decomposer and enricher agents, and the enriching skill's walkthrough, which points at them.

**Why a rule and not an advisory.** The advisory existed and was not followed: a task author copying a familiar shape writes a script. Stating the charter form as the default, with a before/after, changes the shape authors copy. It stays authoring guidance rather than validation because a terse entry is still better than none, and rejecting it would push authors to delete manual tests rather than improve them.

**Why lenses by name.** The change-risk lenses are a short list of the questions those bugs answered wrongly — rights changed mid-session, a refresh nobody watched, a second surface the change never reached. The stride-codex-exploratory-testing `heuristics` skill is their only catalog; copying the text here would fork it, and the copies would drift the first time a lens is refined. A name is enough to send an author to the trigger, and the trigger is what decides whether the lens applies.

**Why nine of the catalog's twelve.** The rule names the same nine lenses upstream's does. Leave No Trace, Telemetry Semantics and Response Hardening stay in the catalog and are not named at authoring time, so a task author is not asked to weigh them for every UI or HTTP change.

**What it does not prove.** Nothing checks that a live decomposer or enricher writes charters; the hook suite pins the wording, not the behaviour. A terse or scripted manual test still validates, so a task created by another client can still arrive with one, and Step 6.5 still hands back a charter it cannot judge.

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
