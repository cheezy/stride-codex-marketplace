# Releasing / syncing the marketplace

This marketplace vendors each plugin's files in-repo under `plugins/<name>/`
and registers them in
[`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json). Keeping
the vendored tree and the catalog entry in sync is the whole job of a release.

## Where the version lives

Unlike a string-source catalog, the Codex catalog entry does **not** carry a
`version` field — a plugin's version lives only in its vendored
`plugins/<name>/.codex-plugin/plugin.json`. So a "release" of this marketplace
is really:

- **Re-vendoring** a plugin's tree when its upstream repo cuts a new version
  (the version moves automatically because it is part of the vendored
  `plugin.json`), and/or
- **Adding** a new plugin entry to the `plugins[]` array.

The README Plugins table is the one place a human-readable version is repeated,
so it must be updated to match the vendored `plugin.json` on every sync.

## Sync steps (re-syncing an existing plugin)

1. Re-vendor the plugin tree with `rsync`, excluding git/runtime/secret files:

   ```bash
   rsync -a --delete \
     --exclude='.git' \
     --exclude='.stride' \
     --exclude='.stride_auth.md' \
     --exclude='.env' \
     --exclude='.env.local' \
     --exclude='*.local' \
     --exclude='.stride-env-cache' \
     --exclude='.stride-changed-files.json' \
     /path/to/<name>/ plugins/<name>/
   ```

2. Update the README Plugins table version cell to match the new
   `plugins/<name>/.codex-plugin/plugin.json` version.

3. Validate — the catalog parses, every entry's `source.path` resolves to a
   directory containing `.codex-plugin/plugin.json`, and the README version
   matches the vendored manifest:

   ```bash
   node -e "const m=require('./.agents/plugins/marketplace.json'); const fs=require('fs'); m.plugins.forEach(p=>{const mf=require('./'+p.source.path+'/.codex-plugin/plugin.json'); if(p.name!==mf.name) throw new Error('name mismatch: '+p.name); if(!fs.existsSync(p.source.path+'/.codex-plugin/plugin.json')) throw new Error('missing manifest: '+p.name); console.log(p.name, mf.version, 'ok');});"
   ```

4. Check the fleet against the port canon — a stale vendored copy blocks the sync:

   ```bash
   bash ../stride/scripts/check-port-canon.sh
   ```

   Exit `0` means every applicable cell is ok. Exit `1` lists the drift; if any
   line names a copy vendored from this repo, the copy is stale — re-vendor it
   from its source port with step 1 rather than editing the vendored tree. If a
   line names a *port* rather than a copy, the fix belongs in that port — add the
   anchor beside its own statement of the rule; never edit an `applies_to` row in
   the canon to clear the line.
   Exit `2` means no verdict was possible, so the run proved nothing and must
   not be read as a pass. Run it here, before the commit in the next step,
   while acting on a red result still costs only a re-run of step 1.

5. Stage the re-vendored tree and secret-scan it and the whole history, from the repository
   root:

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   git add -A
   SECRET_RE='BEGIN [A-Z ]*PRIVATE KEY\|ghp_[A-Za-z0-9]\{20,\}\|github_pat_[A-Za-z0-9_]\{20,\}\|stride_dev_[A-Za-z0-9+/=]\{30,\}\|stride_prod_[A-Za-z0-9+/=]\{30,\}'
   git --no-pager grep -n -G --cached "$SECRET_RE"
   git --no-pager grep -n -G "$SECRET_RE" $(git rev-list --all)
   ```

   **Expect literally zero output from both scans.** Any hit is a real finding — stop, do not
   commit, and rotate the credential. There is no allow-list to consult and none to widen.

   Only when both scans printed nothing, commit and push:

   ```bash
   git commit -m "Sync <name> to X.Y.Z"
   git push origin main
   ```

   **The scans and the commit are separate blocks on purpose.** `git grep` prints a hit and
   carries on, so a single block pasted whole would commit and push whatever the scans had just
   reported. Its exit status also reads backwards for a gate — `0` means it found a match — so
   do not chain the commit onto a scan with `&&` or run the block under `set -e`.

   **Stage first, because history alone cannot see what you are about to commit.**
   `$(git rev-list --all)` lists commits, so the second scan reads committed history only, and
   the files step 1's `rsync` has just copied in sit in no commit yet. `git add -A` puts every one
   of them in the index — new files, changed files, and the removal of any file `rsync --delete`
   dropped — and `git grep --cached` reads the index, which is exactly the tree the commit
   records. Keep the history scan as well: the index cannot see a credential that an earlier
   commit added and a later one removed.

   **Run from the root, and without `-I`.** `git grep` searches only the current directory and
   below, while `git add -A` stages the whole tree, so from a subdirectory both scans would come
   back empty over files they never read; the `cd` removes that. And `-I` would skip every file
   git treats as binary — including any plain-text file a vendored `.gitattributes` marks
   `binary` or `-diff` — so a credential there would reach the commit with no output at all.
   Without it, a match in such a file is reported as `Binary file <path> matches`, which is a hit
   like any other. A compressed archive or non-UTF-8 text is opaque to both scans either way, so
   a vendored tree should not carry one.

   **Keep `-G`.** `SECRET_RE` is a basic regular expression — its `\|` and `\{30,\}` mean
   alternation and a repeat count only in that mode — and `git grep` otherwise takes its mode
   from the operator's `grep.patternType` or `grep.extendedRegexp` setting. Under `extended` or
   `perl` those characters are literals, the pattern matches nothing, and both scans print the
   empty output this step reads as a pass. Under `fixed` the whole pattern is one literal string
   that matches only a copy of its own definition, so a real token goes unreported beside that
   self-match. `-G` (`--basic-regexp`) fixes the mode on the command line, so the gate means the
   same thing on every machine.

   **Keep `--no-pager`.** In a terminal, `git grep` starts the pager, and a pager started by the
   first scan reads the keystrokes of the lines pasted after it, so the history scan is swallowed
   or mangled and never runs, or worse, `less` treats the pasted text as its own commands. Under
   git's default `LESS=FRX` that happens on any index hit, however short; with a `LESS` or
   `core.pager` that drops `-F`, the pager holds the terminal even when the index scan found
   nothing. `--no-pager` prints straight to the terminal, so a pasted block runs every line it
   shows. It is an option to `git` itself, so it goes before `grep`, never after.

   **What a hit costs depends on which scan printed it.** An index hit (`<path>:<line>:`) has not
   left your machine: `git restore --staged .` unstages the tree, the fix belongs in the source
   plugin, and you re-vendor from step 1 and scan again. A history hit (`<commit>:<path>:<line>:`)
   is already in a commit, normally one that has been pushed, and neither unstaging nor a
   re-vendor clears it — rotate the credential at once, and stop the release for a human to
   decide what happens to that history.

   Each clause of `SECRET_RE` bounds the *shape* of a real credential rather than listing
   exceptions, which is what lets the gate be satisfiable. A genuine token is a long run of
   unbroken base64; the
   self-describing fixtures a vendored plugin legitimately ships — negative-test canaries and
   documentation placeholders whose names announce what they are — are short and word-shaped, so
   the `{30,}` bound excludes them by construction instead of by name. `BEGIN [A-Z ]*PRIVATE KEY`
   still matches every real PEM header (`RSA`, `EC`, `OPENSSH`, and the bare form) while no longer
   matching the line you are reading.

   That last point is why this shape replaced an earlier bare-prefix pattern plus a `grep -vE`
   allow-list, rather than the allow-list simply being extended. Two defects made that form
   unsatisfiable, and only one of them was fixable by extension. The list had stopped covering the
   fixtures actually in the tree, which a wider list would have solved. But the pattern also
   matched **its own definition in this file**, and it did so in every historical commit of it —
   and an allow-list cannot fix that without suppressing `RELEASE.md` itself, which would blind the
   scan to a real key committed here. A gate that cannot return empty trains its reader to wave
   hits through, which is the failure worth caring about on a public repository.

6. Tag and publish the GitHub release:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "Sync <name> to X.Y.Z"
   ```

### Sync checklist

- [ ] Vendored tree re-synced; no `.git`, `.stride`, or secret files present
- [ ] README Plugins table version matches the vendored `plugin.json`
- [ ] Validation node one-liner prints `<name> <version> ok` for every plugin
- [ ] Port-canon drift check run; no vendored copy of this repo appears in its output
- [ ] From the repository root, tree staged with `git add -A`, then both secret scans — the
      staged tree (`--cached`) and the history, each run as `git --no-pager grep -n -G` — return
      empty, before the commit block runs
- [ ] Commit pushed and GitHub release tagged

## Adding a new plugin

1. Vendor the new plugin tree with the same `rsync` command as above
   (substituting the new `<name>`). The `--exclude` list is identical — it
   strips git history, the `.stride/` runtime dir, and every secret file before
   the public repo ever sees them.

2. Add a new entry to the `plugins[]` array in
   `.agents/plugins/marketplace.json`, leaving existing entries untouched:

   ```json
   {
     "name": "<name>",
     "source": { "source": "local", "path": "./plugins/<name>" },
     "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
     "category": "Productivity"
   }
   ```

3. Add a README Plugins table row for the new plugin (version from its vendored
   `.codex-plugin/plugin.json`).

4. Validate all entries with the node one-liner from the Sync steps (it iterates
   every `plugins[]` entry, not just one).

5. Run the port-canon drift check, exactly as in the Sync steps above. A new
   vendored copy is a copy like any other, so it is subject to the same check
   from its first commit rather than from its first re-sync.

6. Stage, secret-scan, commit, push, and publish the release exactly as in the
   Sync steps above, running the same two scans from step 5 with `-G` and
   `--no-pager` kept. Run `git add -A` first: the new plugin tree is entirely
   untracked, so the history scan alone sees none of it, and only the staged-tree
   scan (`git grep --cached`) reads it before the commit. Read step 5 there for
   why the blocks are separate, why the scan runs from the root without `-I` and
   with `-G` and `--no-pager`, and what an index hit costs against a history hit.

### Add-a-plugin checklist

- [ ] New plugin tree vendored; no `.git`, `.stride`, or secret files present
- [ ] New `plugins[]` entry added with `source`, `policy`, and `category`
- [ ] Existing `plugins[]` entries left untouched
- [ ] README Plugins table row added
- [ ] Validation node one-liner passes for every plugin
- [ ] Port-canon drift check run; the new vendored copy does not appear in its output
- [ ] Tree staged from the root, then both secret scans (staged tree and history, each run as
      `git --no-pager grep -n -G`) empty before the commit
- [ ] Commit pushed, GitHub release tagged
