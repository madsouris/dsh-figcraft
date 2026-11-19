# FigCraft for DeepSeek Harness

A [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH)
bundle that connects the [FigCraft](https://getartcraft.com/apps/figcraft)
desktop app to your agent over MCP.

![FigCraft showing a design created through DeepSeek Harness](docs/preview.png)

FigCraft serves MCP over stdio in attach mode. The agent gets FigCraft's tools
under `mcp__figcraft__*`: create and edit layers, run menu commands, inspect the
open document, take screenshots, and read or reply to comments. Attach mode
means the agent works in the document you already have open, and you watch the
changes happen.

## On-demand by design

FigCraft exposes its control port only when it starts with `--control PORT`.
macOS `open` drops that flag, so the bundle ships a launcher that writes a
per-user launchd job and starts the app through it. Nothing starts at login, and
nothing stays loaded after `figoff`.

```text
figon [file]   start FigCraft, optionally opening a .figcraft file
figoff         quit FigCraft and unload the job
figstat        show app, control port, CLI and launchd state
figcli ...     run figcraft-cli itself (info, export, render, run, ...)
```

Start FigCraft before DSH:

```bash
figon ~/Designs/MyApp.figcraft
# then launch DeepSeek Harness
```

If DSH is already running when you start FigCraft, restart DSH or open a new
session. The MCP client retries a closed server until its attempt budget runs
out, then removes the tools; a fresh session connects on the first try.

## Requirements

- macOS. The launcher uses `launchctl`, and the FigCraft CLI release is
  `macos-universal`.
- FigCraft 0.18.1 or later at `/Applications/FigCraft.app`:
  `brew install --cask figcraft`.
- `figcraft-cli` 0.18.1 or later. There is no Homebrew formula; the installer
  can download the release ZIP.
- DeepSeek Harness with the `plugin_manager` tool. The desktop and web profiles
  include it.

## Install

1. Clone the repository:

   ```bash
   git clone https://github.com/madsouris/dsh-figcraft.git
   cd dsh-figcraft
   ```

2. Install the launchers and, if needed, the CLI:

   ```bash
   ./scripts/install.sh --with-cli
   ```

   Without `--with-cli`, the script installs `figcraft-mcp` and
   `figcraft-session` into `~/.local/bin` and reuses an existing
   `figcraft-cli`. The download checks the release SHA-256 and lands in
   `~/.local/share/figcraft-cli/<version>/`.

3. Add the aliases to zsh:

   ```zsh
   echo 'source ~/.config/dsh-figcraft/aliases.zsh' >> ~/.zshrc
   ```

   You can also paste the four aliases from `shell/figcraft.zsh` into an
   existing file.

4. Install the bundle in DSH. In a session:

   ```text
   plugin_manager install_bundle target=/absolute/path/to/dsh-figcraft
   ```

   Or open **Plugins** and add the cloned directory. Restart DSH if the tools do
   not appear.

5. Start FigCraft, then start or restart DSH:

   ```bash
   figon
   ```

The package is named `@local/dsh-figcraft` and marked `private`, so installing
from the directory links it into your profile and it cannot be pushed to npm by
accident.

## How it works

The bundle patch inserts one `@deepseek-ai/dsh-mcp-client` row. That row runs
`figcraft-mcp`, which finds `figcraft-cli` and replaces itself with:

```text
figcraft-cli mcp --attach 7979
```

`figon` writes
`~/Library/Application Support/dsh-figcraft/local.dsh.figcraft.control.plist`
with the resolved app and log paths, loads it with `launchctl bootstrap`, and
waits for `127.0.0.1:7979` to accept connections. `figoff` unloads the job and
waits for FigCraft to exit. Logs go to
`~/Library/Logs/dsh-figcraft/control.log`.

The control server binds to `127.0.0.1` only. File access follows the app, not
DSH, so the agent can open and save files that FigCraft can reach. Attach mode
does not accept `--automation-read-root` or `--automation-write-root`.

`figon` starts the app through launchd instead of from your shell. A sandboxed
parent, such as an agent's bash tool, would make FigCraft inherit that sandbox,
and saving a file outside it would fail with `Operation not permitted`.

## Configuration

| Variable | Default | Used by |
| --- | --- | --- |
| `FIGCRAFT_APP` | `/Applications/FigCraft.app` | launcher |
| `FIGCRAFT_CLI` | searched | launcher and MCP wrapper |

The CLI search checks `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, then
`PATH`. DSH started from Finder inherits little of your shell environment, so
the default `~/.local/bin` location is the reliable one. For another location,
edit the wrapper path in `cordis.patch.yml` or point `FIGCRAFT_CLI` at the
binary before launching DSH.

The control port is fixed at `7979` in `bin/figcraft-session` and
`bin/figcraft-mcp`. Change both if you need a different port.

## Updating

The app and CLI ship from the same release and have no version handshake, so
update them together.

```bash
brew upgrade --cask figcraft
./scripts/install.sh --with-cli --version <new-version>
figoff
figon
```

## Troubleshooting

`figstat` says **running WITHOUT the control port**. FigCraft was started by
LaunchServices or by opening the app from Finder. Save your work, quit it, then
run `figon`.

The control port never opens. Read
`~/Library/Logs/dsh-figcraft/control.log`. Another process may already hold
7979; check with `lsof -nP -iTCP:7979 -sTCP:LISTEN`.

DSH shows no `mcp__figcraft__*` tools. Run `figstat` first. If FigCraft is
running with the port open, restart DSH or open a new session so the MCP row
reconnects.

`figcraft-cli not found`. Re-run `./scripts/install.sh --with-cli`, or install
the binary yourself and put it in `~/.local/bin`.

Saving fails with `Operation not permitted`. The app was started inside a
sandboxed shell. Quit it and use `figon`, which starts it through launchd.

## Uninstall

```bash
figoff
```

Remove the bundle from **Plugins** in DSH, then delete the installed files:

```bash
rm -f ~/.local/bin/figcraft-mcp ~/.local/bin/figcraft-session ~/.local/bin/figcraft-cli
rm -rf ~/.local/share/figcraft-cli ~/.config/dsh-figcraft
rm -rf ~/Library/Application\ Support/dsh-figcraft ~/Library/Logs/dsh-figcraft
```

## Repository layout

```text
bin/figcraft-mcp          MCP stdio wrapper used by the bundle patch
bin/figcraft-session      launchd-based on-demand launcher
cordis.patch.yml          DSH bundle patch
scripts/install.sh        wrapper and CLI installer
shell/figcraft.zsh        figon, figoff, figstat, figcli aliases
locale/en.json            plugin title and description
docs/preview.png          preview image
```

## License

MIT. FigCraft is a separate project by the ArtCraft Team; this bundle ships an
original icon and no FigCraft binaries, and it is not affiliated with the
FigCraft project.
