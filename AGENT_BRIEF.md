# Agent brief: set up a herdr agent workstation

Paste this into your coding agent (Claude Code, Codex, …), running **on your client machine**, after filling in the blanks. The agent builds the setup described in [`SPEC.md`](SPEC.md) and adapts it to your machines. Delete anything you don't want.

## Fill in

- **Client:** `<OS, e.g. Ubuntu 26.04 / macOS 15>`, terminal `<kitty / Ghostty / WezTerm>`
- **Server:** `<user>@<host>`, reached over `<Tailscale / LAN / public SSH>`
- **Agent(s) on the server:** `<claude / codex / …>`
- **Editor:** `<hx (reference) / nvim / …>`, languages: `<php, bash, json, …>`
- **Optional features wanted:** `<F-1 images, F-2 markdown preview, plugins: file-viewer / reviewr / whichkey>`
- **Existing multiplexer on the server:** `<tmux session "main" with live agents / none>`

## Context for the agent

- You are on the **client**. Reach the server with plain `ssh` for everything you do. The human attaches with `herdr --remote`; you can't drive a TUI.
- Read `SPEC.md` first. Its **Invariants** (I-1…I-8) are the hard requirements; its **Verification** list is your definition of done.
- herdr docs: https://herdr.dev/docs/ (raw pages are listed in https://herdr.dev/llms.txt). Agent guide: https://herdr.dev/agent-guide.md. Verify every flag, config key and action id against them or the CLI's `--help`. Don't guess.

## Rules

- **Recon first, read-only.** Report OS/arch, shell, sudo (`sudo -n true`), what's already installed, where `PATH` is set, any rc-file hooks that auto-start a multiplexer, locale, and existing multiplexer sessions. Then summarise and continue.
- **Check before installing.** Every step idempotent; skip anything present at a sane version.
- **Prefer no-sudo installs** (static binaries into `~/.local/bin`). If something truly needs sudo, collect it into one block, show the human early, and verify after they run it. Never ask for a password in chat.
- **Never launch the herdr TUI.** Non-interactive subcommands only (`--version`, `status`, `config check`, `plugin …`, `server reload-config`, `pane …` API calls). Starting a herdr server is fine only if the human asks.
- **Don't touch existing multiplexer sessions or running agents.**
- **Back up before changing any config** (`<file>.bak.YYYY-MM-DD`), merge rather than overwrite, and **show a diff** for anything under `~/.ssh/` and for shell rc files.
- **Read scripts before running them** (`curl … -o file && read it && sh file`). **Review plugins** (manifest, build script, action scripts) and **pin** them to the reviewed commit.
- If the GitHub API rate-limits you (HTTP 403), resolve release tags from `https://github.com/<owner>/<repo>/releases/latest` redirects instead.
- Verify each step as you go.

## Phases

### 0. Recon (read-only)
As above. Stop and ask only if something blocks the goal (e.g. no SSH, a sandboxed terminal that can't reach `~/.ssh`, no runtime for the agent CLI).

### 1. Client
1. SSH alias for the server (reuse an existing one; otherwise propose one and show the diff).
2. Install herdr (`https://herdr.dev/install.sh`, read it first). Note the default prefix and detach key from `herdr --default-config`.
3. Terminfo for your terminal on the server (check first; push with `infocmp -x <term> | ssh <host> -- tic -x -` only if missing).
4. Launcher: a shell alias and/or `.desktop` entry running `herdr --remote <host> --remote-keybindings server`. Use absolute paths in `.desktop` `Exec=` lines.

### 2. Server
0. **Shell environment first:** I-1 (`PATH` for non-interactive SSH) and I-2 (multiplexer hook guard). Show diffs. Prove both with simulated commands.
1. Editor (+ runtime files) and language servers.
2. Renderers: `delta`, `bat` (Debian/Ubuntu ship `batcat`; symlink `bat`), `glow`.
3. herdr (same version as the client).
4. Plugins: review, pin, install; read each README for config keys and dependencies.
5. herdr config on the server: plugin bindings with real action ids, no clashes with defaults or the agent (I-3, I-4). `herdr config check`.
6. Editor config (minimal; leave the theme to the human).
7. Agent CLI present and logged in (login is interactive: hand it to the human).
8. Optional features from SPEC §4.
9. Persistence (I-5): how the herdr server survives logout/reboot on this host. Report; propose linger or the agent integration if needed.

### 3. Hand-off
Give the human: any sudo block; a summary of rc-file changes and how to undo them; how to attach; the human-checkable items from SPEC **Verification**; and the filled-in agent-checkable list.
