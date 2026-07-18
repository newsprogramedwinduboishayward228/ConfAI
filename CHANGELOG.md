# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2026-07-18

First tagged build. Everything below works and is covered by tests, but the
version says what it means: the interfaces are still free to move.

### Added

- One CLI over the configs of Codex, Claude Code and opencode. `confai list`
  shows which agents are installed, how many endpoints each has, which one is
  active, and where its config lives.
- Endpoint management with `confai provider`: `list` (with `--check`), `add`,
  `remove`, `use`, `check` and `sync`. `--agent` targets one agent and `--all`
  targets every installed one.
- `confai provider sync <id>` pulls an endpoint's model list from `/v1/models`
  and fills in context and output limits from models.dev, caching the catalogue
  for a day. Syncing merges, so nothing you configured is lost; `--prune` drops
  models the endpoint no longer serves and moves the selection to a surviving
  model if it removed the selected one. `--dry-run` shows what would change.
- Presets: agent-neutral endpoint recipes applied with
  `confai preset apply <id>`, plus `preset list` and `preset show`. Built-in
  presets live in `presets/` and are baked into the binary at build time; user
  presets in `~/.confai/presets/` override a built-in with the same id.
- Interactive TUI, launched by running `confai` with no arguments: two panes of
  agents and endpoints, a `Ctrl+P` command palette, filtering, health checks,
  model sync, preset application, and mouse support. Keys are matched by
  physical position so they work on non-Latin keyboard layouts.
- `confai model`, `confai path`, `confai edit`, `confai doctor`, `confai about`
  and `confai undo`.
- File-safety guarantees: comments, key order and unknown keys survive an edit,
  because every backend edits the parsed document in place. Every write is
  backed up next to the original as `<name>.confai.bak` and replaces the file
  atomically, and `confai undo` restores it. JSON containing comments is refused
  rather than silently rewritten without them.
- Agent-specific handling: a roster of unused endpoints for Claude Code in
  `~/.confai/agents/`, since its config holds only one at a time; and, for
  opencode, reading keys from both `opencode.json` and
  `~/.local/share/opencode/auth.json`, updating an inline key where it already
  is, and showing but never overwriting an OAuth session.
- `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `OPENCODE_CONFIG` and `XDG_CONFIG_HOME` are
  honoured, matching the agents' own behaviour.

[Unreleased]: https://github.com/redstone-md/ConfAI/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/redstone-md/ConfAI/releases/tag/v0.0.1
