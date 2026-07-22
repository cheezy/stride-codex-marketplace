# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-22

Initial release of `stride-codex-exploratory-testing` — the Codex CLI edition of
the Stride exploratory-testing plugin (the "explored" half of *Tested = Checked +
Explored*).

### Added

- **Manifest & packaging** — `.codex-plugin/plugin.json` (name, version,
  description, skills), MIT `LICENSE`, `.gitignore`, and POSIX/PowerShell
  installers (`install.sh`, `install.ps1`).
- **Codex root context** — `AGENTS.md` describing the plugin for Codex CLI.
- **Five doctrine skills** — `stride-exploratory-testing` (orchestrator),
  `chartering`, `heuristics`, `oracles`, and `session`.
- **Five command-skills** (activated by name; Codex has no slash commands) —
  `stride-exploratory-testing-charter`, `stride-exploratory-testing-nightmare-headline`,
  `stride-exploratory-testing-explore`, `stride-exploratory-testing-recon`, and
  `stride-exploratory-testing-debrief`.
- **Two agents** — `charter-generator` (ranked charters from a target) and
  `explorer` (runs one time-boxed session under an absolute safety boundary).
- **Documentation** — `README.md` (install, model, skill/agent reference,
  quick-start, attribution) and `HEURISTICS.md` (pointer to the `heuristics`
  skill catalog).
- **Fixtures** — worked `fixtures/example-charters.md`,
  `fixtures/example-session-sheet.md`, and `fixtures/example-debrief.md` built on
  a synthetic target; they double as templates and regression anchors.
- **Smoke-test harness** — `lib/test-structure.{sh,ps1}`,
  `lib/test-frontmatter.{sh,ps1}`, and `lib/test-all.{sh,ps1}`: offline
  structure + frontmatter validators (no network, no jq) that gate a release.

## Releasing (cross-repo sync)

This plugin ships through the shared **[stride-codex-marketplace](https://github.com/cheezy/stride-codex-marketplace)**
catalog, which **vendors** the full plugin tree under
`plugins/stride-codex-exploratory-testing/` and registers a `local` source in
`.agents/plugins/marketplace.json` (the catalog entry carries **no** version
field). The single source of truth for the version is this repo's
`.codex-plugin/plugin.json`; the marketplace README's Plugins table mirrors it.

To keep the plugin and marketplace in sync on every release, bump the version in
one place and let it propagate:

1. Bump `version` in `.codex-plugin/plugin.json` and add a new section here.
2. In `stride-codex-marketplace`, re-vendor this tree with
   `rsync -a --delete` (excluding `.git`, `.stride`, `.env`, and secret files) so
   the new `plugin.json` version moves with it.
3. Update the marketplace README Plugins-table version cell to match, then run
   the marketplace `RELEASE.md` node validator and secret scan.
4. Tag and publish both repos per their `RELEASE.md` steps.
