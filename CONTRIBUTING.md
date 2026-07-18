# Contributing to ConfAI

Two kinds of contribution are deliberately cheap: a new preset is one TOML file,
and a new agent is one module. Everything else in the tree is arranged so that
neither needs a change anywhere above it.

## Build, test, lint

These three commands are what CI runs, so run them before opening a pull request:

```sh
cargo build --locked
cargo test --locked
cargo clippy --locked --lib --bins --tests -- -D warnings
```

Formatting is checked separately with `cargo fmt --check`.

`build.rs` reads `presets/` and bakes every `.toml` file in it into the binary,
so a preset added to that directory is picked up by the next build with no
registration step. Nothing else about the build is unusual.

## Adding a preset

A preset describes one endpoint in agent-neutral terms, so the same recipe
applies to Codex, Claude Code and opencode without being rewritten. Drop a new
file in `presets/` and you are done — `build.rs` finds it, and `preset::all()`
parses it.

The fields, as `src/preset.rs` defines them:

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Preset id, and the default provider id. Lower case, no spaces. |
| `name` | yes | Human-readable name, and the default provider display name. |
| `description` | no | One line, shown by `confai preset list`. |
| `homepage` | no | Where a user goes to get a key. |
| `api_key_env` | no | Environment variable read when `--api-key` is not passed. |
| `default_model` | no | Model to select after applying, for agents that track one. |
| `[provider].id` | no | Provider id written into the config. Defaults to the preset `id`. |
| `[provider].display_name` | no | Defaults to the preset `name`. |
| `[provider].base_url` | yes | Endpoint base URL, including the version path. |
| `[provider].wire_api` | no | `chat`, `responses` or `anthropic`. |
| `[provider].extras` | no | Backend-specific string keys, passed through untouched. |
| `[[models]]` | no | `id`, and optionally `name`, `context`, `output`. |

Setting `api_key_env` is what makes `confai preset apply` tell the user their key
is missing instead of writing a broken endpoint.

**Do not hard-code a model list.** `[[models]]` exists for endpoints whose
catalogue is fixed and known, and almost none are. Leave it out: the endpoint
answers `/v1/models`, and `confai provider sync <id>` pulls the real list from
there and fills in context and output limits from models.dev. A list baked into a
preset goes stale the first time the gateway changes its catalogue, and there is
no mechanism to correct it short of another release.

`presets/byesu.toml` is the shape to copy.

A preset is tested by the suite as a matter of course:
`every_shipped_preset_parses_and_has_a_unique_id` in `src/preset.rs` parses every
built-in and rejects duplicate ids and unknown `wire_api` values.

## Adding an agent

One new module under `src/agent/`, implementing `Agent` and `AgentConfig` from
`src/agent/mod.rs`, and registered in `agent::all()`. Nothing above the agent
layer — `commands`, `tui`, `preset`, `net` — learns that it exists.

`Agent` locates and detects: `info()` returns the `AgentInfo` (id, display name,
binary names to look for on `PATH`, config path, `Capabilities`), and `load()`
parses the config into a `Box<dyn AgentConfig>`. The default `detect()` covers
both binary and config, so implementing it again is usually wrong. Honour the
agent's own config-directory environment variable if it has one, the way
`CODEX_HOME`, `CLAUDE_CONFIG_DIR` and `OPENCODE_CONFIG` are honoured today.

`Capabilities` is how the UI decides what to offer. Set the four flags to what
the format can actually express — claiming `per_provider_models` for an agent
that has no model list produces menu entries that do nothing.

Then the contract that matters:

- **Edit the parsed document in place.** Keep the `toml_edit::Document` or
  `serde_json::Value` you loaded and mutate it. Do not deserialise into your own
  structs and re-serialise: that silently drops comments, reorders keys and
  discards every key you did not model. `render()` must be byte-identical to the
  input when nothing changed, and there are tests that hold each backend to it.
- **`upsert_provider` is an overlay, not a replacement.** A `Provider` with
  `api_key: None` means "leave the key alone", not "delete the key". Only fields
  the caller actually set may be written. This is what makes
  `confai provider add <existing-id> --base-url ...` an edit of one field rather
  than a reset of the entry.
- **Writes go through `crate::store`.** The default `AgentConfig::save()` calls
  `store::write_atomic`, which backs the file up to `<name>.confai.bak` and then
  renames a temp file over the original. Do not call `fs::write` on a config
  path: it skips the backup, so it also breaks `confai undo`.
- **Refuse rather than mangle.** If the format can hold something you cannot
  round-trip — JSON with comments is the existing case, handled in
  `src/agent/json.rs` — return an error naming the file and what to do about it.
- **Never overwrite a credential you did not write.** An OAuth session belongs to
  the agent's own login flow; show it, and tell the user which command ends it.
  See `src/agent/opencode/auth.rs`.

If the agent stores only one endpoint at a time and has nowhere to keep the rest,
`src/agent/sidecar.rs` holds that roster in `~/.confai/agents/`, the way the
Claude Code backend does. Only the selected entry goes into the file the agent
owns.

Cover the new backend with tests in the module: a round trip that changes nothing
and proves the output is unchanged, an upsert that leaves unrelated keys and
unset fields alone, and a removal that does not take neighbours with it.

## House style

- Object-oriented: behaviour lives on the type that owns the data. A free
  function that takes a struct and reaches into its fields usually wants to be a
  method.
- DRY: one implementation of each rule. The write path exists once in `store`,
  the palette and wording exist once in `brand`, JSON helpers exist once in
  `agent/json.rs`. Reach for the shared one instead of writing a local variant.
- Comments explain why, not what. If a line needs a comment to say what it does,
  rename something instead. The comments worth writing are the ones that record a
  decision — why a key is left in place, why a session is not overwritten.
- No banner comments, no ASCII rules, no section dividers.
- Doc comments on public items, in whole sentences.

## Pull requests

Keep the diff to one thing. A pull request must leave `cargo test` and
`cargo clippy --locked --lib --bins --tests -- -D warnings` clean — CI runs both
on Linux, Windows and macOS, and a warning is an error there.

Fixtures and tests must not contain a real host, a real token or a personal path.
Use documentation ranges and obviously fake keys.
