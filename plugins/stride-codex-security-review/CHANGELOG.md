# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-07-23

### Fixed

- **The agent-dispatch-failure exit-code contract now matches the procedure (G377: D174).** Ported from the upstream source-of-truth fix (`cheezy/stride-security-review` D170). The Step 6 exit-code table documented exit `2` for an "agent dispatch failure", but the three agent-response-failure branches — Step 4a (diff-mode dispatch), Step 4b (full-mode batch), and Step 4.5 (RCI pass) — only printed a one-line error and "stopped", never running `exit 2`. A `--fail-on` CI gate therefore observed an unspecified exit code (not the documented `2`) when the reviewer returned unparseable JSON. Applying the identical **Option A** resolution: each of the three branches now runs a final `exit 2` via `shell` after printing its error, mirroring the Step 1 misuse pattern used by every other exit-2 case (`--fail-on`, `--base`, `--considerations`, `--sarif`/`--json` conflict — the same "fail closed on misuse" discipline the skill already states). The exit-code table's `0`/`1`/`2` meanings are unchanged; the exit-code semantics are identical to the corrected CC source, adapted only to the Codex port's `` `shell` `` tool vocabulary.

## [0.1.0] - 2026-07-23

Initial release of `stride-codex-security-review` — the Codex CLI edition of the
Stride security-review plugin. AI-powered, semantic (not pattern-matching) security
review of code changes, ported from the Claude Code plugin
[`cheezy/stride-security-review`](https://github.com/cheezy/stride-security-review).

### Added

- **Manifest & packaging** — `.codex-plugin/plugin.json` (name, version,
  description, skills), MIT `LICENSE`, `.gitignore`, and POSIX/PowerShell installers
  (`install.sh`, `install.ps1`).
- **Codex root context** — `AGENTS.md` describing the plugin for Codex CLI (skill
  activation rules, the custom agent, the review guarantees, and the tool-name
  mapping).
- **`security-reviewer` agent** — semantic (not pattern-matching) vulnerability
  analysis in `diff`, `full_file`, and `considerations` modes. Covers the universal
  vulnerability classes plus seven framework rule packs (Android/Kotlin, Django,
  Express, iOS/Swift, Phoenix, Rails, React/Next), a Web defense-in-depth pack, a
  supply-chain pack, and a CI/CD pipeline pack, plus the five MAESTRO agentic classes.
  Returns severity-graded JSON findings with `cwe`/`owasp` identifiers; `maestro_layer`,
  `patch`, and `consideration_verdicts` are opt-in (byte-identical default output).
- **`stride-security-review` command-equivalent skill** — the Codex entry point
  (Codex has no slash commands). Full flag parity: `--full`, `--json`, `--sarif`,
  `--maestro`, `--rci`, `--baseline`, `--update-baseline`, `--patches`, `--base`,
  `--fail-on`, and `--considerations`, plus path scoping; renders findings grouped by
  severity, by MAESTRO layer, and per-consideration verdicts; preserves the
  `0/1/2` exit-code contract and the `--sarif`⊕`--json` mutual exclusion, behind a
  STOP-gated untrusted-input discipline.
- **`security-review-essentials` doctrine skill** — *when* to review and *what the
  output means*, plus the Codex integration/detection contract (the sanctioned skill
  + agent surface stride-codex detects by availability, never by executing plugin
  content).
- **`lib/` tooling** — deterministic SARIF/dedup/fingerprint/fail-on transforms
  (`sarif_transform.sh`), the eval harness (`run_eval.sh`), golden transform tests
  (`run_transform_tests.sh`), fixture-consistency checks (`check_fixtures.sh`), and
  structure/frontmatter self-tests (`test-structure`, `test-frontmatter`, `test-all` —
  each `.sh` + `.ps1`). `./lib/test-all.sh` is the offline release gate.
- **`fixtures/` corpus** — ~70 deliberately-vulnerable code samples across every
  framework pack, `golden/` transform fixtures, and considerations-mode positive
  (all-mitigated) and negative (unmitigated + backing finding) controls, with an
  `EXPECTED.md` smoke-test runbook.
- **Documentation** — `README.md` (install, model, full feature list, quick-start,
  attribution) and this `CHANGELOG.md`.

## Releasing (cross-repo sync)

This plugin ships through the shared **[stride-codex-marketplace](https://github.com/cheezy/stride-codex-marketplace)**
catalog, which **vendors** the full plugin tree under
`plugins/stride-codex-security-review/` and registers a `local` source in
`.agents/plugins/marketplace.json` (the catalog entry carries **no** version field).
The single source of truth for the version is this repo's `.codex-plugin/plugin.json`;
the marketplace README's Plugins table mirrors it.

To keep the plugin and marketplace in sync on every release, bump the version in one
place and let it propagate:

1. Bump `version` in `.codex-plugin/plugin.json` and add a new section here.
2. In `stride-codex-marketplace`, re-vendor this tree with
   `rsync -a --delete` (excluding `.git`, `.stride`, `.env`, and secret files) so the
   new `plugin.json` version moves with it.
3. Update the marketplace README Plugins-table version cell to match, then run the
   marketplace `RELEASE.md` node validator and secret scan.
4. Tag and publish both repos per their `RELEASE.md` steps.
