## What changed

<!-- One or two sentences. -->

## Why

<!-- The problem this solves. Link the issue if there is one. -->

## How it was verified

<!-- What you ran, on which OS, and against which agent's config. -->

## Checklist

- [ ] `cargo test --locked` passes
- [ ] `cargo clippy --locked --lib --bins --tests -- -D warnings` is clean
- [ ] `cargo fmt --check` is clean
- [ ] No real hosts, tokens or personal paths in fixtures, tests or docs
- [ ] Config edits still preserve comments, key order and unknown keys
