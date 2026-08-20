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

5. Secret-scan the whole history, then commit and push:

   ```bash
   git grep -nI 'BEGIN .*PRIVATE KEY\|stride_dev_[A-Za-z0-9+/]\|stride_prod_' $(git rev-list --all) \
     | grep -vE 'your_token_here|TEST_TOKEN|DO_NOT_LEAK|SHOULD_NOT_MATCH|should_not_match|abc123'   # expect empty
   git add -A
   git commit -m "Sync <name> to X.Y.Z"
   git push origin main
   ```

   The `grep -vE` filter suppresses **self-describing synthetic fixtures** that vendored plugins
   legitimately ship — negative-test canaries and documentation placeholders whose names announce
   what they are (`..._your_token_here`, `..._TEST_TOKEN_FOR_SMOKE_TEST_ONLY`, `..._DO_NOT_LEAK`,
   the last being a string whose whole purpose is to prove a redaction path works). Each is
   byte-identical to its public upstream repo. Without the filter the scan returns those hits on
   every release and the checklist item becomes unsatisfiable — which trains the next engineer to
   wave it through, the opposite of what a gate is for.

   **If the scan returns a hit that is not obviously one of those, treat it as a real credential:
   stop, do not commit, and rotate it.** Widen this filter only for a fixture you have actually
   opened and read.

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
- [ ] Secret scan returns empty
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

6. Secret-scan, commit, push, and publish the release exactly as in the Sync
   steps above.

### Add-a-plugin checklist

- [ ] New plugin tree vendored; no `.git`, `.stride`, or secret files present
- [ ] New `plugins[]` entry added with `source`, `policy`, and `category`
- [ ] Existing `plugins[]` entries left untouched
- [ ] README Plugins table row added
- [ ] Validation node one-liner passes for every plugin
- [ ] Port-canon drift check run; the new vendored copy does not appear in its output
- [ ] Secret scan empty, commit pushed, GitHub release tagged
