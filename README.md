# codex-kitty-bridge.nvim

`codex-kitty-bridge.nvim` forwards Kitty Unicode-placeholder image traffic from
programs running in Neovim terminal buffers to the outer terminal through
[Snacks.nvim](https://github.com/folke/snacks.nvim).

It is intended for the Codex TUI math renderer, but the bridge is protocol
based: any embedded application using direct PNG (`f=100`, `t=d`) virtual
placements can use it.

[Relevant Codex fork and branch here](https://github.com/a-alveyblanc/codex/tree/20cbb5106b45952735863b4c22c5785967509f84)

## Requirements

- Neovim 0.11+
- Snacks.nvim with its image module enabled
- Kitty or Ghostty (tmux works with `allow-passthrough`)

## Setup

```lua
{
    "a-alveyblanc/codex-kitty-bridge.nvim",
    main = "codex_kitty_bridge",
    lazy = false,
    dependencies = { "folke/snacks.nvim" },
    opts = {},
}
```

Setup exports `CODEX_NEOVIM_KITTY_BRIDGE=1` to subsequently launched terminal
jobs. The Codex fork uses that capability marker to emit raw Kitty APC packets
for Neovim to consume. The plugin forwards the image bytes, while Neovim
naturally renders the Unicode placeholder cells at their correct pane
positions.

Only bounded direct-PNG virtual transmissions and per-image deletions are
forwarded. Payloads are capped at 6 MiB encoded, and images are reference
counted across terminal buffers.

For Codex running across SSH, forward the capability environment variables or
set `CODEX_NEOVIM_KITTY_BRIDGE=1` and `CODEX_NEOVIM_OUTER_TMUX=` for the remote
command. Image bytes travel in the terminal stream, so no shared filesystem is
required.

Run `:checkhealth codex_kitty_bridge` or
`:CodexKittyBridgeStatus` to inspect the bridge.
