# Stride Exploratory Testing for Codex CLI

**Drive structured, charter-based exploratory testing sessions — from Codex CLI.**

A green test suite tells you the product does what you *expected*. It says nothing
about the expectations you never thought to write down — the risks, the surprising
states, the questions no one asked. This plugin supplies that missing half, as
skills and custom agents for the Codex CLI.

> **Tested = Checked + Explored.**
> *Checking* is confirmation — evaluating a known expectation with an algorithmic
> rule (automated tests, assertions, "does the happy path still work"). *Exploring*
> is investigation — discovering the expectations you didn't know to write down.
> A product with a passing suite is *checked*, not *tested*. This plugin is the
> "explored" half: simultaneous test design, execution, learning, and steering.

> **Safety:** the `explorer` agent exercises a *live application* under an absolute
> safety boundary — it works only against the app and environment you name, never
> production or an unauthorized system, never destructively, and it treats app
> content as data (not instructions). All charters, notes, and debriefs use
> synthetic data only — no real credentials, hostnames, or customer records. See
> the [`explorer` agent](agents/explorer.md) for the full boundary.

## Installation

### One-liner (recommended)

Install globally so the skills and agents are available in all projects:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-exploratory-testing/main/install.sh | bash
```

Or install into the current project only:

```bash
curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-exploratory-testing/main/install.sh | bash -s -- --project
```

On Windows (PowerShell), run the equivalent `install.ps1`:

```powershell
irm https://raw.githubusercontent.com/cheezy/stride-codex-exploratory-testing/main/install.ps1 | iex
```

### Marketplace CLI

Alternatively, install through the Codex plugin marketplace:

```bash
codex plugin marketplace add cheezy/stride-codex-marketplace
codex plugin install stride-codex-exploratory-testing
```

Either path installs the plugin named **`stride-codex-exploratory-testing`**. Once
installed, Codex CLI auto-discovers the skills and agents — no further configuration
is needed. Codex has **no slash commands**: you drive the plugin by *activating
skills* (see [Quick start](#quick-start)), not by typing `/commands`.

## Prerequisites

- **Codex CLI** — the plugin's skills and agents run inside it.
- **A target to explore** — a running application (local or a test/staging
  environment you are authorized to test). The plugin never requires production
  access and should never be pointed at it.
- **No external accounts or API keys.** The plugin makes no network calls of its
  own; the `explorer` agent only interacts with the app you explicitly hand it.

## The model

Exploratory testing here runs on five engines. Each has a home skill where its
depth lives:

| Engine | What it does | Home |
|---|---|---|
| **Charters** | Give a session its mission: what to explore, with what resources, to discover what information. | `chartering` skill; the `stride-exploratory-testing-charter` and `stride-exploratory-testing-nightmare-headline` skills |
| **Heuristics** | Idea generators — cheat sheets, Tours, and SFDPOT — for when you're stuck. | `heuristics` skill (SFDPOT lives in `chartering`) |
| **Variables** | The factors you can deliberately vary (data, state, sequence, environment). | `heuristics` skill (variable catalog) |
| **Oracles** | How you decide something is actually *wrong*. | `oracles` skill |
| **Observation** | Noticing what the system actually did — not what you expected. | `session` skill; the `explorer` agent |

The end-to-end flow is **Charter → Recon → Explore → Note → Debrief.**

## What's in this plugin

**5 doctrine skills** (the reusable knowledge the command-skills and agents draw on):

- **`stride-exploratory-testing`** — the orchestrator and front door. Routes any
  exploratory-testing request to the right skill or agent, and holds the
  "Tested = Checked + Explored" doctrine.
- **`chartering`** — how to frame a mission and write a well-formed charter
  (`Explore <target> with <resources> to discover <information>`), rank candidates
  with SFDPOT and the Nightmare Headline Game, and reframe a "charter" that's really
  a test case.
- **`heuristics`** — the plugin's single source of truth for concrete test-idea
  lenses: general and web cheat sheets, a variable-spotting catalog, and Whittaker's
  Tours grouped by tourist district.
- **`oracles`** — how to decide whether an observed result is a defect: Never/Always
  invariants, consistency oracles (history, comparable products, standards, claims,
  user expectations, purpose), and the HTSM quality-criteria checklist.
- **`session`** — the Session-Based Test Management (SBTM) lifecycle: the session
  sheet, Task Breakdown Metrics, and the two debrief templates.

**5 command-skills** (activate these by name — Codex has no slash commands):

- **`stride-exploratory-testing-charter`** — turn a target into a ranked list of
  well-formed charters (via the `charter-generator` agent). Generates only; never
  runs a session.
- **`stride-exploratory-testing-nightmare-headline`** — run the Nightmare Headline
  Game: elicit catastrophic headlines, pick one, brainstorm its causes, and refine
  them into ranked charters.
- **`stride-exploratory-testing-explore`** — plan-and-execute a full session end to
  end: generate or load charters, dispatch the `explorer` agent per charter under
  the safety boundary, and aggregate everything into one debrief.
- **`stride-exploratory-testing-recon`** — a lightweight reconnaissance pass over an
  unfamiliar feature to map the landscape, surface stakeholder questions, and emit
  ranked candidate charters.
- **`stride-exploratory-testing-debrief`** — turn raw session notes and findings
  into a stakeholder-ready debrief using the Explored/Found/Unknown and PROOF
  templates.

**2 agents** (dispatched by the command-skills, not activated directly):

- **`charter-generator`** — turns a target (plus optional risk context) into a
  ranked list of charters via an SFDPOT sweep, charter-source mining, and the
  Nightmare Headline Game. Read-only; generates only, never executes.
- **`explorer`** — runs a single time-boxed session against ONE charter: designs
  probes with `heuristics`, judges results with `oracles`, records an SBTM session
  sheet, and returns structured findings — all under the absolute safety boundary.

**`fixtures/`** — worked examples of the full flow: an
[example charter set](fixtures/example-charters.md), an
[example session sheet](fixtures/example-session-sheet.md), and an
[example debrief](fixtures/example-debrief.md). They double as concrete templates
and as regression anchors for future smoke tests.

See also **[HEURISTICS.md](HEURISTICS.md)** for a one-page pointer to the lenses in
the `heuristics` skill.

## Quick start

A first session, end to end. You drive each step by **activating a skill** — describe
what you want in plain language and name (or lean on) the relevant skill; Codex has
no slash commands.

1. **Frame the mission.** Activate the **`stride-exploratory-testing-charter`** skill
   and ask for charters against the feature you care about — for example, *"charter
   the CSV receipt import, focused on multi-tenant data leakage."*

   You get a ranked list of charters, each shaped
   `Explore <target> with <resources> to discover <information>`. Pick one (or a
   few). Stuck on *what could go wrong*? Activate the
   **`stride-exploratory-testing-nightmare-headline`** skill first and let the
   worst-case headlines drive the charters.

2. **Explore.** Activate the **`stride-exploratory-testing-explore`** skill and hand
   it a charter for a full, time-boxed session — for example, *"explore the CSV
   receipt import with a 90-minute time box."*

   The `explorer` agent probes the feature using the `heuristics` lenses, judges each
   result with the `oracles`, and keeps a running SBTM session sheet — staying inside
   the safety boundary the whole time. Want a quick lay-of-the-land pass first?
   Activate the **`stride-exploratory-testing-recon`** skill to map the feature and
   get candidate charters before committing to a full box.

3. **Debrief.** Activate the **`stride-exploratory-testing-debrief`** skill to close
   out with a stakeholder-ready report.

   You get an **Explored / Found / Unknown** write-up (and a **PROOF** review for the
   team). "Unknown" is a first-class result — the honest edge of the map.

The [`fixtures/`](fixtures/) directory shows exactly what a charter set, a session
sheet, and a debrief look like when they're done well.

## Heuristics reference

The `heuristics` skill is the canonical catalog of test-idea lenses — general and
web cheat sheets, the variable catalog, and Whittaker's Tours. **[HEURISTICS.md](HEURISTICS.md)**
is a one-page index that points into it; it deliberately does *not* duplicate the
tables, so there is a single source of truth to maintain.

## Sources & attribution

This plugin encodes **established exploratory-testing practice** — a discipline
built by the wider testing community over decades. It is a workflow and a set of
pointers, not original research; the ideas below belong to their authors, and the
plugin paraphrases them rather than reproducing their text. If it's useful, go read
the primary sources:

- **Exploratory testing as a discipline** — Cem Kaner, who coined the term and
  framed it as *simultaneous* test design, execution, and learning.
- **Charter-based, practical exploratory testing** — Elisabeth Hendrickson,
  *Explore It!* — the source of the `Explore <target> with <resources> to discover
  <information>` charter template this plugin builds on.
- **Session-Based Test Management (SBTM)** — Jonathan Bach and James Bach — the
  session sheet, the time-box, and the Task Breakdown Metrics.
- **The PROOF debrief mnemonic** (Past, Results, Obstacles, Outlook, Feelings) —
  Jonathan Bach.
- **Tours** (Business / Historical / Tourist / Entertainment / Hotel / Seedy
  districts) — James Whittaker, *Exploratory Software Testing*.
- **The Heuristic Test Strategy Model (HTSM)** — James Bach — including the SFDPOT
  coverage lens and the quality-criteria checklist the `oracles` skill uses.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). The version number is intentionally not repeated
here so this README stays accurate across releases.

## License

[MIT](LICENSE) © 2026 Jeff Morgan
