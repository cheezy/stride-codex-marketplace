# Stride for Codex — Marketplace

Marketplace catalog for [Stride](https://www.stridelikeaboss.com) plugins
targeting [OpenAI Codex](https://developers.openai.com/codex/) — a kanban-based
task management platform designed for AI coding agents.

The catalog file lives at
[`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json), and
every plugin's files are vendored in-repo under `plugins/<name>/` so a
local-source catalog entry always resolves to a real directory.

## Adding the marketplace

Register this marketplace with the Codex CLI:

```bash
codex plugin marketplace add cheezy/stride-codex-marketplace
```

Then install a plugin from it:

```bash
codex plugin install stride-codex
```

### Managing the marketplace and plugins

```bash
codex plugin marketplace list          # View registered marketplaces
codex plugin list                      # View installed plugins
codex plugin update stride-codex       # Update a plugin to the latest version
codex plugin uninstall stride-codex    # Remove a plugin
```

## Plugins

| Plugin | Version | Description |
| --- | --- | --- |
| [stride-codex](plugins/stride-codex) | 1.24.0 | Task lifecycle skills and custom agents for Stride kanban — Codex CLI edition. |

The plugin list above is kept in sync with the `plugins[]` array in
[`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json), and each
version matches the vendored plugin's `.codex-plugin/plugin.json`.

## How the catalog works

`.agents/plugins/marketplace.json` follows the Codex marketplace schema:

```json
{
  "name": "stride-codex-marketplace",
  "interface": {
    "displayName": "Stride for Codex"
  },
  "plugins": [
    {
      "name": "stride-codex",
      "source": { "source": "local", "path": "./plugins/stride-codex" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Productivity"
    }
  ]
}
```

Each plugin entry uses a `local` source whose `path` is an in-repo relative
directory containing the vendored plugin (including its
`.codex-plugin/plugin.json` manifest). The `policy` block controls install
availability and when authentication is requested; `category` groups the plugin
in the marketplace UI.

## Maintenance

Re-syncing a plugin to a newer version, or adding a new plugin to the catalog,
follows the documented process in [RELEASE.md](RELEASE.md) (re-vendor with
`rsync`, add/update the `plugins[]` entry, validate, secret-scan, push,
release).

## License

[MIT](LICENSE) © 2026 Jeff Morgan
