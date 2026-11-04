# Codex CLI hook research

This file keeps the evidence behind decisions in this port that depend on how
Codex CLI itself behaves. Each finding carries one of three labels:

- **measured**: seen in a running Codex CLI session, with the version named;
- **documented**: read in Codex's published documentation, which may lag or
  lead the installed release;
- **unmeasured**: neither observed nor settled by the documentation. An
  unmeasured result is a question, never a fact, and nothing here is built on
  one.

## W2594: is the turn handed back during a custom-agent call, and are running agents in the `Stop` input?

Recorded 2026-11-03 for stride's W2254 and W2255, which both shipped in stride
1.81.0 and both depend on host behaviour that stride observed only on Claude
Code. The porting guide asks each port to establish that behaviour on its own
runtime before porting either.

### Method

- **Codex CLI version: not installed.** No `codex` binary was on the machine
  where this was done, so nothing below is measured.
- The Codex documentation was read on 2026-11-03. Its old addresses,
  `developers.openai.com/codex/hooks` and `developers.openai.com/codex/subagents`,
  now redirect to:
  - <https://learn.chatgpt.com/docs/hooks>
  - <https://learn.chatgpt.com/docs/agent-configuration/subagents>
- Neither page names a Codex version or a date. The hooks page warns that the
  schemas on its linked `main` branch may hold fields the current release does
  not have.

### Question 1: does invoking `task-explorer` let the main agent keep working?

Label: **unmeasured**. The subagents page says Codex spawns agents in
parallel, and that when many are running it waits until every requested
result is available before it returns one consolidated response. It also mentions
switching between agent threads with `/subagents` while they run, and active
subagents shown above the composer when the background-agent UI is present.
That reads as more than one thread being alive at a time. It does not say
whether the agent that made the call gets its turn back before the result
arrives, and that is the only thing W2254 needs. Without a session to watch,
the question stays open.

### Question 2: does the `Stop` hook input list agents that are still running?

Label: **documented** (no such field). The hooks page lists the `Stop` input
as the common fields (`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`), plus
`turn_id`, `stop_hook_active` and `last_assistant_message`, and it also
mentions `permission_mode`. None of them names an agent. Agent fields
(`agent_id`, `agent_type`) appear only on the `SubagentStart` and
`SubagentStop` events, one subagent per event. The page's only use of
"background" is the `async` setting for running a hook command without
waiting for it, which is configuration, not input.

Whether a live `Stop` payload carries an undocumented field, the way Claude
Code's `background_tasks` turned out to, is **unmeasured**.

### Decisions

- **W2254: not applicable.** Nothing shows that a `task-explorer` call hands
  the turn back early, so the explorer phase of `stride-subagent-workflow` tells
  the orchestrator to wait for the explorer's summary, and stride's
  read-while-it-runs instruction stays out of this port: telling the agent to
  work during a call that may never release the turn asks for the impossible.
- **W2255: not applicable.** Neither the gate script nor its registration
  changes (`hooks/stride-stop-gate.sh`, `hooks/hooks.json`), so no hook needs
  re-approving. stride's permit and its time bound key on a running-agent
  list in the `Stop` input, and the documented input has none. A marker written from `SubagentStart` and removed on
  `SubagentStop` could stand in for it, but that is a new mechanism stride does
  not have, not a port, and it is not built here.

### Look again when

Once Codex CLI is installed somewhere it can run, set up a scratch project
whose `Stop` and `SubagentStart` hooks each append the **names** of their input
fields to a log (`jq -c keys`, never the whole input), then make one
`task-explorer` call. That settles both questions. Hook inputs carry session
ids, transcript and working-directory paths, the last assistant message and
possibly an agent's description, all of which can identify the user or carry
task text, so keep that log outside any repository, delete it when done, and
write into this file only field names, their types and whether they were
present, never a value. Then:

- if the main agent acts before the explorer's result arrives, revisit W2254;
- if the `Stop` input names a running agent, revisit W2255, matching agent
  types as exact whole strings and never echoing an agent's description. A
  permit must fail closed: when the running-agent state, or the time the wait
  began, cannot be read or recorded, the gate blocks as it does today. A marker
  kept from `SubagentStart` and `SubagentStop` would also need a time bound,
  because a subagent that crashes never sends its `SubagentStop` and a stale
  marker would otherwise permit every later stop.

Record the Codex version and the date beside the result.
