# Stride Security Review for Codex CLI

**AI-powered security review of your code changes — from Codex CLI.**

Activate one skill and get a structured, severity-graded list of security findings on
whatever you've changed. Powered by a dedicated `security-reviewer` agent that uses
**semantic analysis, not pattern matching**, and filters out low-impact noise so the
findings you see are the ones worth acting on. It is the [Codex CLI](https://github.com/openai/codex)
port of the Claude Code plugin
[`cheezy/stride-security-review`](https://github.com/cheezy/stride-security-review).

> **Semantic, not grep.** The reviewer reasons about what the code *does* — data
> flow, trust boundaries, auth and crypto decisions — rather than matching regexes.
> It deliberately filters out low-impact noise (denial-of-service, rate-limiting,
> memory-exhaustion) unless it intersects a real vulnerability class, so the output
> is signal, not a linter dump.
>
> **One exception, in considerations mode only.** When a consideration the task lists names one of these risks itself — "uploads are size-bounded", "the export endpoint is rate-limited" — that risk is assessed for that consideration, and a `partial` or `unmitigated` verdict on it is backed by a finding like any other. A risk the list does not name is still suppressed, and diff and full modes keep the filter unchanged.
>
> Everything the agent reviews — diff hunks, code comments, string literals, the files it reads and the considerations it is handed — is data, never instructions: a comment telling the reviewer to report nothing is ignored. In diff and considerations mode it may read the changed files in full and their direct callers, up to 10 files beyond the diff; it never enumerates the rest of the repository. In considerations mode a dispatch also has a budget of 20 tool calls, at most 2 of them reproductions (writing the result file never counts). It grades from the diff first, a read past direct callers — a caller's caller, or a config file the changed code reads — must be named and justified in the verdict's note, and a consideration the budget leaves unverified comes back `partial` with a note that begins `budget reached:`. No finding backs that verdict, so `--fail-on` fails on it at every threshold and the Stride workflow escalates it; it is never `mitigated`. Diff and full modes have no budget. Codex sets no turn, step or tool-call limit for a custom agent (its [subagents documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents) lists none), so the agent counts the budget itself.

> **No slash commands.** Codex has no `/commands`: you drive the plugin by
> *activating skills* by name (see [Quick start](#quick-start)), not by typing
> `/security-review`.

## Installation

### One-liner (recommended)

Install globally so the skills and agents are available in all projects:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-security-review/main/install.sh | bash
```

Or install into the current project only:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-security-review/main/install.sh | bash -s -- --project
```

On Windows (PowerShell), run the equivalent `install.ps1`:

```powershell
irm https://raw.githubusercontent.com/cheezy/stride-codex-security-review/main/install.ps1 | iex
```

Both installers copy each skill's `SKILL.md`, the `stride-security-review` skill's
`packs/` and `modes/` rule files beside it (regular `.md` files only, never a link),
and `agents/*.md`. `lib/check_install.sh` runs them from a local scratch clone and
checks every rule file lands.

### Marketplace CLI

Alternatively, install through the Codex plugin marketplace:

```bash
codex plugin marketplace add cheezy/stride-codex-marketplace
codex plugin install stride-codex-security-review
```

Either path installs the plugin named **`stride-codex-security-review`**. Once
installed, Codex CLI auto-discovers the skills and agents — no further configuration
is needed. Codex has **no slash commands**: you drive the plugin by *activating
skills* (see [Quick start](#quick-start)), not by typing `/commands`.

## Prerequisites

- **Codex CLI** — the plugin's skills and agent run inside it.
- **A git repository** — the reviewer works from a diff against `HEAD` (diff mode) or
  the tracked files (full mode).
- **No external accounts or API keys.** The plugin makes no network calls of its own;
  the `security-reviewer` agent only reads the code you hand it, and writes one file
  only when a caller supplies `SECURITY_RESULT_PATH` (see
  [Result file](#result-file-security_result_path)). Outside the repository it may also make one
  sandboxed temporary copy to run a single test in (see
  [Tools and the working tree](#tools-and-the-working-tree)).

## The model

A security review here has three moving parts:

| Part | What it does | Home |
|---|---|---|
| **Doctrine** | *When* to review and *what the findings mean* — the invocation rules and severity rubric. | `security-review-essentials` skill |
| **Operation** | Selects the review mode (diff / full / considerations) and flags, then dispatches the agent. | `security-review` command-skill |
| **Analysis** | The semantic vulnerability analysis itself, returning structured JSON findings. | `security-reviewer` agent |

The end-to-end flow is **Identify a change → Activate `security-review` → Read the
severity-grouped findings.**

## What's in this plugin

**1 doctrine skill** (the reusable knowledge the command-skill and agent draw on):

- **`security-review-essentials`** — when to run a review (diff mode vs. full mode),
  and how to read the structured, severity-graded output. Defers the analysis
  methodology to the `security-reviewer` agent so it is not duplicated.

**1 command-skill** (activate this by name — Codex has no slash commands):

- **`stride-security-review`** — the end-to-end operation. Parses its flags, gathers
  the input (a diff or a filtered file set), dispatches the `security-reviewer` agent
  (once in diff mode; batched in groups of ~10 in full mode), and renders the findings.
  Beside its `SKILL.md` it carries the agent's eleven rule packs (`packs/`) and three
  mode files (`modes/`), which it sends to the agent in each dispatch.
  Its full flag surface:

  | Flag | Effect |
  |---|---|
  | `--full` | Review every tracked text file (batched), not just the working-tree diff. |
  | `--json` | Raw JSON output for piping into tools. |
  | `--sarif` | SARIF v2.1.0 output for code-scanning integrations (mutually exclusive with `--json`). |
  | `--maestro` | Add a MAESTRO 7-layer classification per finding + a "By MAESTRO layer" summary. |
  | `--rci [N]` | Run N (≤3) recursive criticism-and-improvement passes to drop false positives / surface misses. Every pass re-sends the considerations, MAESTRO and patches directives of the first dispatch, so `consideration_verdicts`, `maestro_layer` and `patch` survive it. |
  | `--baseline [path]` | Suppress already-acknowledged findings recorded in a baseline file. A finding that backs a `partial` or `unmitigated` consideration verdict is never suppressed, so `suppressed_count` never counts it. |
  | `--update-baseline` | Rewrite the baseline from the current findings. |
  | `--patches` | Emit a surgical-fix unified diff alongside each finding where one exists. |
  | `--base <ref>` | Diff against `<ref>...HEAD` (PR-against-base CI scope). |
  | `--fail-on <severity>` | Exit non-zero when findings reach the threshold — the CI security gate. With `--considerations` it also fails closed, whatever the threshold, on an `unmitigated` verdict, a `partial` verdict no finding backs, and a missing or malformed `consideration_verdicts` array — including one whose entries do not answer the considerations in order. A backed `partial` is gated by its finding's severity. |
  | `--considerations <source>` | Assess the diff against a task's `security_considerations` list and return a per-consideration **mitigated / partial / unmitigated** verdict. |

  Opt-in output fields (`maestro_layer`, `patch`, `consideration_verdicts`) are omitted
  unless their flag is set, so output stays byte-identical for callers that don't opt
  in. The `0 / 1 / 2` exit-code contract (clean / findings-at-threshold / misuse) and
  the `--sarif`⊕`--json` mutual exclusion are preserved. The gate runs after every
  output form, so `--json --fail-on` and `--sarif --fail-on` gate like the report.

  A CI job that post-checks `--json` output with `jq`, as the skill's CI note advises,
  counts findings only unless it is extended. With `--considerations`, add the
  unmitigated verdicts, for example
  `([.findings[]? | select(.severity == "critical")] | length) + ([.consideration_verdicts[]? | select(.status == "unmitigated")] | length)`.
  That one-line filter still fails open on a `partial` verdict no finding backs and on
  a missing, short or malformed verdict array, which the skill's exit code covers. A
  job that has this repository checked out can gate fail-closed instead with
  `bash lib/sarif_transform.sh failon <severity> review.json <considerations-file>`,
  the tested reference of the same rules: it exits `1` on a trip and `2` on anything
  but one findings document, and given the considerations file it also checks that
  each verdict answers its consideration in order. `lib/` is not installed with the
  skills, so this is for CI only.

**1 agent** (dispatched by the command-skill, not activated directly):

- **`security-reviewer`** — analyzes code semantically (not by pattern-matching) for
  vulnerabilities across injection, authentication, authorization, data exposure,
  cryptography, input validation, race conditions, XSS/code execution, insecure
  configuration, and supply chain. Runs in `diff`, `full_file`, or `considerations`
  mode and returns structured JSON findings graded critical / high / medium / low /
  info (each with `cwe` + `owasp` identifiers), with low-impact noise
  (denial-of-service, rate-limiting, memory-exhaustion) filtered out, except a risk
  of those kinds that a task's own consideration names in considerations mode.
  In considerations mode each verdict is exactly one of `mitigated` / `partial` / `unmitigated` (there is no fourth value; a consideration the change has no surface for is `mitigated`), and a `partial`/`unmitigated` verdict is backed by a matching `findings[]` entry, which its `evidence` names by `file:line` (or a `file:start-end` range). A gap that predates the change is graded against the changed code and named in `note` plus one `info` finding. A consideration that embeds a credential, or names where one lives, is echoed as `[REDACTED — row text embedded a credential]` in its position rather than verbatim.

### What it catches

On top of the universal vulnerability classes, the agent carries **framework-aware
rule packs** that activate on a file's extension **and** its imports (never extension
alone):

- **Android / Kotlin**, **Django / Python**, **Express / Node.js**, **iOS / Swift**,
  **Phoenix / Elixir**, **Rails / Ruby**, and **React / Next.js** framework packs;
- a framework-agnostic **Web defense-in-depth** pack (CSP / HSTS / X-Frame-Options /
  secure-cookie), a **Supply-chain** pack (floating base images, pipe-to-shell
  installers, unpinned CI refs, lockfile drift, typosquats), and a **CI/CD pipeline**
  pack (unpinned actions, over-broad permissions, fork-PR secret exposure, expression
  injection).

The packs, and the full rules of three modes (considerations, result file and
reproduction), are files beside the `stride-security-review` command skill, in its
`packs/` and `modes/` directories, not in the agent's prompt. The agent is a core that
never reads a rule file itself: Codex documents no path by which an agent's
instructions reach an installed file, so the skill picks the packs from the reviewed
files' paths, extensions, structure and imports and sends each file verbatim in a
keyed block. An agent dispatched directly, without them, reviews with its core rules
alone, writes no result file and runs no reproduction. To add a pack, write
`packs/<name>.md` beside the others with an activation that needs a file extension
**and** an import or identifier signal, four to six rules mapped to existing
`vulnerability_class` values, and any prior-art SAST tool as context only (Sobelow,
Brakeman, Bandit, gosec, eslint-plugin-security); then add its row to the tables in
the agent's **Rule packs and mode files** and the skill's **Rule files**, which must
stay equal, to `RULE_NAMES` in `lib/check_agent_contract.sh` and
`lib/check_install.sh`, and to the eval's lists: `EVAL_PACKS` in `lib/run_eval.sh`
and the `names` list in `lib/check_eval_invocation.sh`'s blocks check.

For codebases that wire LLMs / AI agents / MCP clients into the request flow, five
**MAESTRO agentic** classes activate when a file imports a recognized LLM/agent/MCP
SDK: prompt injection, tool abuse, agent trust boundary, model output execution, and
vector store poisoning.

**`lib/`** — deterministic transform (SARIF / dedup / fingerprint / fail-on), eval, and
golden tooling that validate the plugin offline (no network) plus structure /
frontmatter self-tests. `./lib/test-all.sh` is the one-command release gate.

**`fixtures/`** — a corpus of ~70 deliberately-vulnerable code samples across every
framework pack, golden transform fixtures, and considerations-mode positive/negative
controls (a fully-mitigated list → all `mitigated`; an unmitigated consideration →
`unmitigated` with a backing finding; a `partial` defence; a `None —` placeholder;
reviewer-directed text inside a consideration and inside the diff; a noise-class
consideration; a gap in unchanged code; a rate-limit consideration; and a
consideration that embeds a fake credential), and a diff whose test invites a run
that reading settles.

### Result file (`SECURITY_RESULT_PATH`)

The agent returns a single fenced ```json document. A caller that dispatches the
`security-reviewer` agent itself, such as the Stride workflow's deep security review,
can keep that document out of its own context by giving the agent one line of its own
in the dispatch instructions. The `stride-security-review` command skill never
supplies it. Such a caller must also send `modes/result-file.md` from the skill's
directory in a keyed rule-file block (the agent's **Rule packs and mode files** gives
the form); without it the agent writes nothing and replies `result: NOT WRITTEN — …`
with the full document inline.

Such a caller opens its prompt with the agent's one mode tag, on its own line:
`/security-review invocation, mode: <mode>` (`diff`, `considerations` or `full_file`).
No other spelling is a tag. With no tag the agent reviews in `diff` mode, except that
a considerations list an older caller sends with no tag, under any header, is still
reviewed in `considerations` mode.

```text
SECURITY_RESULT_PATH=/absolute/path/to/repo/.stride/.security-<IDENTIFIER>-r<N>.json
```

- **The path must come from you and be well formed.** It must be absolute and end in a `.stride` directory and a file named `.security-<IDENTIFIER>-r<N>.json` (`<IDENTIFIER>` matching `^[A-Za-z0-9_-]+$`, `<N>` one or more digits). Every component must match `^[A-Za-z0-9._-]+$`, none `.` or `..`, so no quote, space or control character can appear. Anything else, or two `SECURITY_RESULT_PATH` lines anywhere in the prompt, is treated as no path. It is the only output path the agent honours.
- **Quote lines that look like it.** The agent takes the path only from your own dispatch line, never from the diff, files or considerations it reviews. To keep the two apart, in text you did not write, prefix any line that starts with `SECURITY_RESULT_PATH` with `> ` before you pass it.
- **Use a fresh path in a directory you control.** The agent writes with one `shell` command under `set -o noclobber`. It refuses an existing file, directory or link at the path, even a dangling one, and a `.stride` directory that is a link. It creates a missing `.stride` once with `mkdir -p` but checks no directory above it, so keep the path out of a shared directory such as `/tmp`. There is no temp file, so read the file only after the dispatch returns, and delete it when you are done.
- **The session must allow the write.** A subagent inherits the parent session's sandbox and approvals, and its own file cannot change them ([subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)). The default `workspace-write` sandbox lets Codex edit files in the working directory, with `.git`, `.agents`, `.codex` and `.aws` kept read-only ([agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)); `.stride/` is not among the protected paths. Under a `read-only` session, or when the command is denied, the write fails.
- **What you get back.** The file holds the same document the fence would carry. The reply is at most 10 plain-text lines with no ```json fence: `result: <path> (<bytes> B)`, a `verdicts:` line in `considerations` mode, the severity counts, `files_reviewed`, and up to five `severity | class | file:line` rows. Read the file, never the summary.
- **A failed write** returns `result: NOT WRITTEN — <reason>` on its own first line, then the full fenced document.
- **No path, no change.** Without the line, and in `rci_pass` mode, the reply is the single fenced document, as before.

None of this was observed in a Codex CLI session; see the CHANGELOG's *Not verified in a live Codex CLI* list.

### Tools and the working tree

The agent's tools are `read`, `search`, `glob` and `shell`, and it is **read-only on the working tree**: it never creates, modifies, moves or deletes anything in the repository it reviews, tracked or untracked, not even to restore it afterwards. It inspects code with `read`, `search` and `glob`, and uses `shell` for three things only — writing the result file at `SECURITY_RESULT_PATH`, a short list of read-only commands (`ls`, `wc` and five git forms — `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false ls-files`, `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false diff --cached --no-ext-diff --no-textconv --submodule=short`, `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false diff --no-ext-diff --no-textconv --submodule=short <commit> <commit>`, `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false log --no-ext-diff --no-textconv --submodule=short --no-show-signature` and `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false show --no-ext-diff --no-textconv --submodule=short --no-show-signature` — never a bare `git diff` against the working tree, which rewrites `.git/index`), and, when reading cannot settle a question, one reproduction inside a temporary copy. In considerations mode a reproduction only confirms a specific claim stated in a verdict's note or a finding's description, and a dispatch runs at most two.

The flags on those git forms stop git running a program named in the reviewed repository's config or attributes — a `core.fsmonitor` hook, `diff.external`, a `diff.<driver>.command`, a textconv driver, the `gpg.program` (or `gpg.ssh.program` or `gpg.x509.program`) that `log.showSignature`, a `%G` placeholder in a `format.pretty` default or a `pretty.<name>` alias would call, a `core.pager` when the shell has a terminal, a submodule's own diff programs when `diff.submodule=diff`, or the `core.sshCommand`, credential helper or proxy a partial clone's lazy fetch would start — which would run outside any sandbox with the agent's full environment. `--no-lazy-fetch` also keeps a lazy fetch from writing a pack into `.git/objects`, and needs git 2.44 or later; an older git rejects it and runs nothing, and the agent then reads with `read`. Local config does not travel with a clone, so this takes a planted `.git/config`, but a reviewer that never runs reviewed code should not run a program the repository names either. The agent never drops a flag, adds `--ext-diff`, `--textconv` or `--show-signature`, or puts a `%G` signature placeholder in `--format` or `--pretty`, which runs `gpg.program` whatever the flags say; it reads the working tree with `read` rather than through git: `git ls-files -m` and `git diff-index` without `--cached` run a configured clean filter. The probe's copy step lists files with `git --no-lazy-fetch -c core.fsmonitor=false ls-files` for the same reason — in a sparse partial clone `--exclude-standard` would otherwise lazy-fetch a skip-worktree `.gitignore` — and the probe refuses to run, grading by reading, on a git older than 2.44.

That copy is a `stride-security-probe.XXXXXX` directory under `$TMPDIR` (else `/tmp`), made by copying the repository's files rather than linking them, used by a single command that runs one test or snippet, and removed when that command exits. On exit the command first kills the snippet — its whole process group in a shell that can turn on job control, such as `bash` or `sh`, though not in `zsh` without a terminal — and unlocks the copy's directories, so a directory the snippet locked cannot keep it. The snippet's output comes back through a pipe, never a terminal, and on macOS the box also refuses to open `/dev/tty` or any other `/dev/tty*` device, so a snippet cannot push input into the terminal of the shell running it; the probe prints the snippet's exit status as `snippet exit: <n>`. The command refuses a copy that holds a symbolic link, and runs the snippet inside a sandbox that denies network access, every write outside the copy and every read under your home directory — on macOS (`sandbox-exec`) also every Unix socket, launchd job creation, mach service lookups, Launch Services, Apple Events, `open`/`launchctl`/`osascript`, signals, POSIX and System V IPC, process-information and task-port calls to any process outside the box, and running or loading as native code any file in the copy, so a script there runs through its interpreter (`sh test.sh`); on Linux (`bwrap`) new namespaces, an empty `/run`, `/tmp`, `/var` and home directory, so no Unix socket under them is reachable (one elsewhere still is, such as a Nix daemon's under `/nix/var`), and a new session — under `env -i`, so the credentials in your environment are not inherited and `HOME` and `TMPDIR` point into the copy. It refuses to run when `HOME` is unset, relative, `/`, not a directory or not your account's home directory, when it or the copy has a quote, backslash or newline in its path, or when the copy would sit under it. On macOS a snippet can still signal and inspect the processes it starts, but not your editor, agent or any other outside process, though it can still read their command lines (and, on a macOS release that returns them, their environments); a snippet that needs POSIX semaphores or shared memory, such as Python `multiprocessing` locks, fails in the box. With neither sandbox available the agent runs nothing and grades by reading, and it runs nothing in CI (the command checks `CI` first) or when the caller says the change comes from an untrusted contributor, because the sandbox hides your home directory but not the rest of the filesystem. A probe installs nothing and never runs a command written in the code under review. A dispatch killed mid-command, or a process the snippet started that outlives the command, can leave a copy behind; it holds only copied files, and an operator can clear stale ones with:

```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'stride-security-probe.*' -mmin +60 -exec rm -rf {} +
```

The guarantee is the agent's written contract, not the `tools:` line: Codex's [subagents documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents) describes no per-agent tool list, so `shell` is listed whole and the prompt says what it is for; its only shell control is turning the shell off (`features.shell_tool`). `lib/check_agent_contract.sh` pins that contract and checks the `tools:` line against it.

`lib/check_git_hardening.sh` runs the five git forms, the probe's guard line and its copy step, as these files write them, against a scratch repository whose own config names marker programs for `core.fsmonitor`, `diff.external`, a diff driver, a textconv driver and `gpg.program`, and against a sparse partial clone whose `core.sshCommand` is a marker. It fails if any marker ran, or if the same commands without their flags did not run one, so a scratch repository that could not catch a program fails too. It checks the guard against a stand-in for a git older than 2.44, and skips on a real one. It runs git directly, not through Codex, and runs from `./lib/test-all.sh`.

**Codex's own sandbox.** Unless the session bypasses it, Codex CLI runs the agent's `shell` commands inside its own sandbox: on macOS it "uses Seatbelt policies and runs commands using `sandbox-exec`", on Linux it "uses `bwrap` plus `seccomp` by default", network access is off by default, and the workspace includes the current directory and temporary directories like `/tmp` ([agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)). That page does not say whether a second `sandbox-exec` or `bwrap` can start inside Codex's sandbox, and it warns that in a container the sandbox may not work when the namespace, setuid `bwrap` or `seccomp` operations it needs are blocked. So the probe's own `box` may fail to start there. When it does, the snippet has not run: the agent runs nothing and grades by reading, and it never reruns the snippet without the wrapper or asks to run it outside Codex's sandbox. Under a `read-only` session the copy itself cannot be made, so nothing runs either. With Codex's sandbox bypassed, the probe's `box` is the snippet's only confinement, and every refusal above still applies.

**Unverified on Codex.** Codex CLI was not installed where this section was written, so nobody has seen whether `sandbox-exec` applies its profile, or `bwrap` starts, inside Codex's sandbox, whether Codex CLI asks before it runs the probe command, whether the temporary directory the probe uses is writable there, or that the agent refuses an edit under this contract. If the wrapper fails to start, the agent runs nothing and grades by reading. The eval turns the shell off (`features.shell_tool=false`, `--sandbox read-only`), so it never sees a probe. Nor has anyone seen the probe's `/var` mount or process-namespace cleanup on Linux: the git hardening and the macOS cleanup were checked on this machine (macOS, git 2.55.0) outside Codex, and `bwrap` was not run at all.

### Running the eval

`lib/run_eval.sh` runs the agent over the fixtures and scores each answer against `fixtures/EXPECTED.md`. It is a separate, paid step, not part of `./lib/test-all.sh`.

**Codex CLI cannot run a custom agent as the session agent of a headless run.** The `codex exec` section of the [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) has no agent flag, and Codex starts custom agents only as subagents on request ([subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)). So the runner does not select the installed `security-reviewer` agent. It hands this checkout's `agents/security-reviewer.md` to `codex exec` as the session's base instructions, with `-c model_instructions_file='<path>'` ([config reference](https://learn.chatgpt.com/docs/config-file/config-reference): "Replacement for built-in instructions"). The model then answers under this plugin's agent prompt rather than Codex's default one. That is what the eval scores.

Each fixture runs from an empty scratch directory outside any Git repository, so the agent sees only the prompt, never `EXPECTED.md` or the repo:

- `--skip-git-repo-check` and `--cd <scratch dir>`, with the scratch directory also the working directory;
- `--sandbox read-only`, `-c approval_policy="never"`, and the shell tool, web search, subagents and image viewing turned off with `-c` overrides;
- `--ignore-user-config`, so no MCP servers or settings from your `config.toml`, and `--ephemeral`, so no session files are saved;
- the prompt on stdin (`-`), carrying all eleven packs, `modes/considerations.md` in
  considerations mode and `modes/reproduction.md` in keyed rule-file blocks, as the
  command skill sends them, so each fixture is scored against the full rule set
  (`EVAL_RULES_DIR` overrides where they are read).

With the shell tool off and an empty scratch directory, the eval never exercises the agent's read scope, and it checks verdicts and whether a finding exists — not redaction, `note` text, or a finding's severity — so those are checked by hand in `logs/` where a row says so.

```bash
bash lib/run_eval.sh --dry-run                    # print the exact invocation; no CLI call, exit 0
bash lib/run_eval.sh --only considerations/       # the considerations-mode fixtures
bash lib/run_eval.sh --fixture sql_injection.py   # one fixture
bash lib/run_eval.sh                              # every fixture
```

Every run prints `# invocation: <argv>` and `# auth: <mode>` after the TAP plan line. Auth is `CODEX_API_KEY` when set, otherwise a saved login (`codex login status` exits 0); with neither, the runner exits 2 with a message. It never prints the key or the login status. `EVAL_AGENT_FILE` points the run at another instructions file and `EVAL_MODEL` passes `-m`. Logs go to `logs/` (or `LOG_DIR`): `<stem>.raw.txt` is the final message, `<stem>.err.txt` is Codex's stderr.

`lib/check_eval_invocation.sh` pins that invocation against a fake `codex` with no model, key or network, and runs from `./lib/test-all.sh`. Nothing above has been observed in a live Codex CLI. A run is recorded in the *Recorded runs* table at the end of `fixtures/EXPECTED.md`, and none has been recorded yet. This variant has no CI workflow, so the eval runs locally only.

## Quick start

A first review, end to end. You drive each step by **activating a skill** — describe
what you want in plain language and name the relevant skill; Codex has no slash
commands.

1. **Decide whether to review.** Activate **`security-review-essentials`** to confirm
   the change touches a security-sensitive surface (auth, crypto, input handling,
   queries, shell-outs, uploads, redirects, rendering) and to understand what the
   output will mean.

2. **Review.** Activate the **`security-review`** skill against your change — for
   example, *"security-review my staged diff"*, *"security-review lib/auth.ex"*, or
   *"security-review --full"* for a whole-tree scan. The `security-reviewer` agent
   analyzes the input and returns findings grouped by severity.

   To verify a task's declared security considerations were actually mitigated, pass
   **`--considerations <source>`** — a file (one consideration per non-empty line) or
   a single inline string — e.g. *"security-review --considerations threat-model.md"*.
   You get one **mitigated / partial / unmitigated** verdict per consideration
   alongside the findings (a `partial` or `unmitigated` verdict is backed by a
   corresponding finding). Add `--rci --fail-on high` to keep the verdicts through a
   critique pass and fail on any `unmitigated` verdict, e.g.
   *"security-review --considerations threat-model.md --rci --fail-on high"*.

3. **Act on the findings.** Fix the critical/high items before merging; the low/info
   items are context. Re-run the review to confirm the fixes.

The [`fixtures/`](fixtures/) directory shows the kinds of vulnerable code the reviewer
is designed to catch.

## Sources & attribution

This plugin is the Codex CLI port of
[`cheezy/stride-security-review`](https://github.com/cheezy/stride-security-review);
the analysis methodology, vulnerability classes, severity rubric, and realism filter
originate there. This port adapts the same doctrine to Codex CLI conventions (skills
activated by name, agents as bare `.md` files, no slash commands).

## Changelog

See [CHANGELOG.md](CHANGELOG.md). The version number is intentionally not repeated
here so this README stays accurate across releases.

## License

[MIT](LICENSE) © 2026 Jeff Morgan
