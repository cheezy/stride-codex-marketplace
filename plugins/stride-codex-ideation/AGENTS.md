# Stride Ideation Skills for Codex CLI

## Skill Activation

Activate the corresponding skill before performing each step of the ideation workflow. These skills carry the round structure, hard-gated section list, decomposer dispatch contract, and Stride API batch shape — driving them from memory will skip the seven-section gate or emit invalid batches.

| User intent | Activate this skill |
|---|---|
| Brainstorm, scope a fuzzy idea, write a requirements doc, refine an existing requirements doc | `stride-ideation-ideate` |
| Decompose a committed requirements doc into Stride tasks and POST them to a Stride workspace | `stride-ideation-stridify` |
| Internal protocol reference (round structure, hard gates, premortem, profile augmentations) — invoked transitively by the above | `stride-ideation` |

`stride-ideation-ideate` and `stride-ideation-stridify` are the user-facing skills. `stride-ideation` is the protocol contract that the ideate skill drives — readers usually do not activate it directly.

## Custom Agents

Two subagents are dispatched by the user-facing skills. They are not invoked directly from a user prompt.

- **requirements-reviewer** — Advisory pass over a draft requirements document. Reports gaps, contradictions, and ambiguous acceptance criteria; never edits the doc. Dispatched by `stride-ideation-ideate` after the seven sections have draft content and before the doc is committed.
- **requirements-decomposer** — Reads a committed requirements document end-to-end and emits a single fenced JSON batch document matching the Stride API `POST /api/tasks/batch` shape. Dispatched by `stride-ideation-stridify` before the batch JSON is written and committed.

Both agents live at `agents/<name>.md` (bare `.md`, per Codex naming convention).

## Workflow Sequence

```
activate stride-ideation-ideate
  → drives the question loop, gates on the seven required sections,
    dispatches requirements-reviewer, writes and commits the
    requirements doc
  → STOP — the committed doc is a valid terminal state

activate stride-ideation-stridify <path-to-requirements.md>
  → validates the seven sections, preflights .stride_auth.md,
    dispatches requirements-decomposer (with bounded retry on
    transient failures), stamps audit metadata, writes and commits
    the batch JSON, POSTs to /api/tasks/batch, renders the created
    G/W identifier table
```

The stridify step is optional — the requirements doc is a deliverable on its own. Activate stridify only when the user wants the tasks created in Stride.

## API Authorization

The `stride-ideation-stridify` skill reads `.stride_auth.md` from the project root for `STRIDE_API_URL` and `STRIDE_API_TOKEN`. The user authorizes Stride API calls by initiating the workflow — never prompt for permission before the POST. Never log the token, even in error paths.

`.stride_auth.md` must be listed in `.gitignore`. The bundled `.gitignore` template already excludes it.

## Tool Name Mapping

When skill bodies reference tool names from other platforms (the upstream Claude Code plugin or the Copilot port), use the Codex equivalents:

| Skill Reference | Codex Tool |
|---|---|
| `Read` / `read_file` | `read` |
| `Grep` / `grep_search` | `search` |
| `Glob` | `glob` |
| `Bash` / `run_shell_command` | `shell` |
| `Edit` / `replace` | `edit` |
| `Write` / `write_file` | `write` |

The skill bodies in `skills/` have already been adapted to Codex vocabulary; this table is the reference for users porting their own skills or prompts that originated on a different platform.

## How this plugin relates to `stride-codex`

`stride-codex` covers the **task lifecycle** (claiming, hook execution, completion). This plugin covers **ideation** — turning a fuzzy idea into a requirements doc and seeding a Stride backlog from it. A typical full loop installs both: ideate → stridify with this plugin, then claim and ship the resulting tasks with `stride-codex`.
