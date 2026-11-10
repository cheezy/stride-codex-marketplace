# Releasing stride-codex

A release of this plugin has two halves: this repository (manifest, changelog,
tag, GitHub release) and `stride-codex-marketplace`, which carries a vendored
copy of this whole tree. Users of the catalog get whatever was last vendored
there, so a release that stops at this repository has not reached them.

## The three facts

**Where the version lives.** `.codex-plugin/plugin.json` (`"version"`). That
is the only file in this repository carrying the release version; the other
version-looking strings in the README, AGENTS.md and the skills are feature
markers. Nothing tests the manifest against the changelog. In the catalog the
same value travels inside the vendored `plugins/stride-codex/.codex-plugin/plugin.json`
and is repeated once by hand, in the catalog README's Plugins table.

**Changelog shape: two shapes in the record, and the switch is recent.**

- **Through 1.38.0, lockstep.** A version's heading, entry and manifest bump
  landed together — usually in a release commit, and for 1.38.0 in the work
  commit itself, which was tagged later.
- **Since 1.38.0, appended.** Work commits add entries under
  `## [Unreleased]` and leave the manifest alone, which means the next release
  commit gives those entries their version heading and bumps
  `.codex-plugin/plugin.json`. Not every work commit has written an entry, so
  check the log. Through 1.40.0 the release commit renamed `[Unreleased]`;
  since 1.41.0 it keeps an empty `## [Unreleased]` first and inserts the
  version heading directly under it (step 2).

The repository has no written rule choosing between them; the current file is
set up for the appended shape.

**Catalog: `stride-codex-marketplace` (vendored).** The catalog keeps a full
copy of this tree under `plugins/stride-codex/` and registers it in
`.agents/plugins/marketplace.json`, which has no version field. A sync is an
`rsync` of this repository into that directory, a README version-cell update,
validation, a drift check, a secret scan of the staged tree and of the
history, then a catalog tag and GitHub release. The catalog's `RELEASE.md` is
the runbook — follow it rather than any summary here. Its tag numbers are the
catalog's own sequence and do not track this plugin's version. Note that this
file is vendored along with everything else; that is expected.

Several older changelog entries (1.16.0 through 1.22.0) say this plugin is
not distributed through any marketplace, so there is "no marketplace pin to
update". That is not true today, and the 1.33.0 entry corrects it; the
catalog above is the current state.

## Before you add to the changelog: is the top heading already tagged?

```bash
git tag -l "v$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md | head -n 1)"
```

It checks the newest numbered heading, skipping `[Unreleased]`. Any output
means that version shipped: put new entries under `[Unreleased]`, never under
the tagged heading. (The lite ports once appended to a released heading and
had to move the entries; this is the check that catches it.)

## Steps

1. Run the gates:

   ```bash
   bash hooks/test-stride-hook.sh
   ```

   and the fleet drift check from the `stride` repository
   (`bash scripts/check-port-canon.sh`, run there).

2. Run the top-heading check. Make sure every commit since the last tag
   (`git log --oneline "$(git describe --tags --abbrev=0)"..HEAD`) has an
   entry. Then, in one commit on `main`, keep `## [Unreleased]` as the first
   section, left empty, and insert `## [X.Y.Z] - YYYY-MM-DD` directly under
   it, so the entries that sat under `[Unreleased]` now sit under the new
   heading; set `"version"` in `.codex-plugin/plugin.json` to `X.Y.Z`. Do not
   rename `[Unreleased]`: Groups 23h and 24j of `hooks/test-stride-hook.sh`
   pin it as the changelog's first section. A suite check that reads its entry
   from `[Unreleased]` up to the next `## [` heading finds nothing once the
   entry moves, so widen it to end at the previous release's heading, as the
   1.43.0 and 1.43.1 release commits did, and run the suite again. Push
   `main`.

   This repository's steps run no secret scan of their own. The secret scan
   is step 5 of `stride-codex-marketplace`'s `RELEASE.md`, run in the
   catalog after the re-vendor in step 5 below. It stages the re-vendored
   tree first (`git add -A`) and scans the index (`git grep --cached`) as
   well as committed history (`$(git rev-list --all)`), so the files a
   re-vendor has just copied in are scanned before that step commits and
   pushes them.

3. Tag the release commit (annotated) and push the tag:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

4. Publish the GitHub release from the changelog entry:

   ```bash
   gh release create vX.Y.Z --repo cheezy/stride-codex --notes-file <notes.md>
   ```

5. Re-vendor into `stride-codex-marketplace` by following its `RELEASE.md`,
   then tag and release the catalog under its own next number.

## Known gaps on the record

- Some early changelog versions were never tagged, and three tags have no
  GitHub release; the latter is recorded in the changelog's
  release-record note. Do not backfill either.
- Tags are a mix of annotated and lightweight; use annotated.
