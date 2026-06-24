# Stride for Codex — Marketplace

Marketplace catalog for [Stride](https://www.stridelikeaboss.com) plugins
targeting [OpenAI Codex](https://developers.openai.com/codex/).

Stride is a kanban-based task management platform designed for AI coding
agents, with client-side hook execution at four lifecycle points
(`before_doing`, `after_doing`, `before_review`, `after_review`) and a
`Ready → Doing → Review → Done` workflow.

## Catalog

The marketplace catalog lives at
[`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json). It
follows the Codex marketplace schema:

```json
{
  "name": "stride-codex-marketplace",
  "interface": {
    "displayName": "Stride for Codex"
  },
  "plugins": []
}
```

Plugins are registered by adding entries to the `plugins` array.

## License

[MIT](LICENSE) © 2026 Jeff Morgan
