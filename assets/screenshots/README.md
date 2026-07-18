# Screenshots

Two images, referenced from the root `README.md`. Uncomment the block there once
both exist.

| file | what it shows |
|---|---|
| `tui.png` | the main two-pane view, an agent selected, several endpoints listed, at least one with a green health dot from a `c` check |
| `palette.png` | the command palette open on `Ctrl+P`, with a few characters typed so the ranking is visible |

## Capturing

- Terminal sized to **120×32**. Narrower and the hint bar starts dropping keys;
  shorter and the header collapses to its one-line form.
- A **true-colour** terminal, or the redstone palette degrades to approximations.
  Windows Terminal, WezTerm, kitty and Ghostty are all fine.
- A **dark background** near `#171514`, so the panes do not sit on a lighter
  rectangle.
- Capture the terminal contents only — no window chrome, no desktop behind it.

## Before you publish one

These are going into a public repository, so check the frame for anything you
would not post:

- **Endpoint hosts and IP addresses.** The provider pane shows the host of every
  endpoint. Internal addresses are the easy thing to miss.
- **Provider ids** that name a private service.
- Anything in the terminal's title bar or a visible prompt: paths, hostname,
  username, branch names.

Keys are masked to `abcd…wxyz` everywhere in the interface, so a screenshot
cannot leak a whole one — but the first and last four characters are real. If
that bothers you, point ConfAI at a scratch config first:

```sh
CODEX_HOME=/tmp/demo OPENCODE_CONFIG=/tmp/demo/opencode.json confai
```

and add a few endpoints with obviously fake values.
