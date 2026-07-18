# Security Policy

ConfAI reads and writes the files your AI coding agents keep their credentials
in:

- `~/.codex/config.toml`
- `~/.claude/settings.json`
- `~/.local/share/opencode/auth.json`, alongside `opencode.json`
- its own state under `~/.confai/`

A bug in this tool can therefore put a secret somewhere it does not belong, or
destroy a working configuration. Please report those privately.

## Reporting a vulnerability

Use GitHub private security advisories:
<https://github.com/redstone-md/ConfAI/security/advisories/new>.

Do not open a public issue for a security bug, and do not include a real API key
in the report — a redacted key and the shape of the config are enough to
reproduce almost anything.

Please include the agent involved, your OS, the output of `confai --version`, and
the smallest config that reproduces the problem.

## Supported versions

ConfAI is at `0.1.0`. Fixes go into the latest release; there are no maintained
older branches.

## In scope

- Writing a secret into the wrong file — the wrong agent's config, the wrong
  provider entry, a world-readable location, or a file outside the agent's
  config directory.
- Leaking a key or token in terminal output, in an error message, in a panic
  backtrace, or in a request sent anywhere other than the endpoint the key
  belongs to.
- Destroying or corrupting a config: truncating it, dropping keys or comments it
  should have preserved, or leaving it unparseable to the agent that owns it.
- Ending or overwriting an OAuth session that ConfAI did not create.
- Path handling that lets a provider id, preset id or config value escape the
  directory it should stay in.

## Out of scope

- Vulnerabilities in the agents themselves (Codex, Claude Code, opencode) or in
  the provider endpoints you point them at. Report those upstream.
- A key you passed on the command line ending up in your shell history. Use the
  preset's `api_key_env` variable instead.
- Anything that requires an attacker who already has write access to your home
  directory.

## Existing mitigations

These are properties of the current code, not aspirations. They are what a report
should be measured against.

- **Every write is backed up.** `store::write_atomic` copies the existing file to
  `<name>.confai.bak` before replacing it. This is the only write path; each
  agent backend reaches disk through it.
- **Replacement is atomic.** New contents are written to a sibling temp file,
  flushed with `sync_all`, and renamed over the target. An interrupted write
  leaves either the old file or the new one, never a half-written config.
- **`confai undo` restores the backup** for the selected agents, from the same
  `.confai.bak` file.
- **Keys are masked in output.** `domain::mask` keeps the first and last four
  characters and hides the rest; short secrets are replaced entirely. The CLI
  listing and the TUI both display through it, so a full key is never printed
  back to the terminal.
- **OAuth sessions are never overwritten.** `agent::opencode::auth` refuses to
  write an API key over an entry of type `oauth`, and directs the user to
  `opencode auth logout` instead. OAuth access tokens are also never returned as
  keys, so they are not used for health checks or copied elsewhere.
- **Keys are not moved between files.** A key already inline in `opencode.json`
  is updated in place; only a new key is written to `auth.json`.
- **JSON with comments is refused, not rewritten**, because rewriting it would
  drop the comments.

## Known limitations

- The backup is one deep. A second write overwrites the previous backup, so
  `confai undo` reverses the last write only.
- `<name>.confai.bak` sits next to the original and contains whatever the
  original did, including secrets. It is created with the process default
  permissions rather than copied from the source file.
