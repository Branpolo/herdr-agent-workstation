# SPEC: herdr agent workstation

This document describes a **target end state**, not a script. Hand it (or [`AGENT_BRIEF.md`](AGENT_BRIEF.md)) to your coding agent and let it adapt the steps to your machines, shell, agent and tastes. A build is correct when it meets every requirement in [Invariants](#invariants) and passes [Verification](#verification).

Keywords: **MUST** means required for the setup to work or be safe. **SHOULD** is strongly recommended. **MAY** is optional.

---

## 1. Goal

A persistent workspace where **coding agents have centre stage** and editing files is the side part:

- Agents (Claude Code, Codex, …) run on a **server** inside [herdr](https://herdr.dev), a terminal multiplexer that knows about agents. It shows which agent is `working`, `blocked` (waiting for you) or `done`, across every project.
- You attach from a **client** (your desktop or laptop) with `herdr --remote <host>`. The client only draws the UI; it holds no state.
- File viewing, diff review, markdown preview and editing are panes **beside** the agents, not the other way round.

Non-goals: replacing your IDE for long stretches of hand-editing; mobile clients (herdr works over plain SSH on a phone, but that isn't covered here); scripting a per-project pane layout (build it by hand once).

## 2. Topology

```
 client (desktop/laptop)                    server (dev box)
┌───────────────────────────┐   SSH    ┌──────────────────────────────────────┐
│ terminal (kitty or other  │◄────────►│ herdr server (detached daemon)       │
│  kitty-graphics terminal) │          │  ├─ workspaces / tabs / panes        │
│ herdr --remote <host>     │          │  ├─ agents: claude, codex, …         │
│   (thin client: UI only)  │          │  ├─ plugins: file viewer, review, …  │
│ launcher / shell alias    │          │  └─ editor (hx) + language servers   │
└───────────────────────────┘          │ renderers: delta, bat, glow          │
                                       │ optional: GitHub-style md preview    │
                                       └──────────────────────────────────────┘
```

Example per-project layout (built by hand on first attach):

```
┌──────────────┬───────────────────────┬──────────────────┐
│ file viewer  │ editor (hx)           │ agent 1          │
│ (tree/diff)  │                       ├──────────────────┤
│              │                       │ agent N          │
│              │                       ├──────────────────┤
│              │                       │ shell            │
└──────────────┴───────────────────────┴──────────────────┘
```

## 3. Components

| Component | Side | Required | Notes |
|---|---|---|---|
| herdr | both | MUST | Same install on both sides; `--remote` can also install it on the server for you. |
| SSH access, key in an agent | client→server | MUST | Plain `ssh <host> true` must work first. |
| Terminal with kitty graphics | client | SHOULD | kitty, Ghostty, WezTerm… Needed for inline images. |
| `xterm-kitty` terminfo (or your terminal's) | server | MUST if using kitty | Often already present via `ncurses-term`. |
| Coding agent CLI(s) | server | MUST | Logged in on the server. |
| Editor + language servers | server | SHOULD | Reference: Helix (`hx`). |
| `delta`, `bat`, `glow` | server | SHOULD | Used by the file viewer to render diffs, code and markdown. |
| herdr plugins | server | MAY | Reference: [file-viewer], [reviewr], [whichkey]. |
| GitHub-style markdown preview | server | MAY | Reference: [go-grip], opened from the file viewer. |
| Launcher (`.desktop`, alias) | client | MAY | One command or click to attach. |

[file-viewer]: https://github.com/smarzban/herdr-file-viewer
[reviewr]: https://github.com/persiyanov/herdr-reviewr
[whichkey]: https://github.com/Qu4tro/herdr-whichkey
[go-grip]: https://github.com/chrishrb/go-grip

## Invariants

Each one exists because breaking it caused a real failure.

### I-1 Tools resolve in non-interactive SSH
Everything herdr or its plugins call (`herdr`, the editor, agents, `node`, renderers, helper scripts) **MUST** be on `PATH` for a **non-interactive** SSH command on the server, not just in an interactive shell.

*Why:* `herdr --remote` starts the server through a non-interactive SSH command, and the herdr server, its plugins and every pane inherit that environment. Many setups only set `PATH` in `~/.zshrc` or `~/.bashrc`, which non-interactive shells skip (Ubuntu's `.bashrc` returns early; zsh only reads `~/.zshenv`).
*Fix pattern:* put `~/.local/bin`, plus your node manager's default `bin`, in `~/.zshenv` (zsh) or in `BASH_ENV` / `~/.profile` (bash, depending on how your sshd invokes it). Don't load heavyweight managers like nvm there; add their `bin` path directly. See [`reference/config/zshenv`](reference/config/zshenv).
*Check:* `ssh <host> 'command -v herdr hx claude node delta bat glow'` resolves every name.

### I-2 Shell auto-start hooks skip herdr panes
If your shell rc auto-starts or attaches tmux/zellij/screen on SSH login, it **MUST NOT** do so inside herdr panes. Plain SSH logins **SHOULD** keep their old behaviour.

*Why:* panes inherit `SSH_CONNECTION` from the server's launch environment, so an `if [[ -n $SSH_CONNECTION ]]; then exec tmux attach …` hook makes **every herdr pane attach to your existing tmux session**.
*Fix pattern:* herdr sets `HERDR_ENV=1` in its panes; add `&& [[ -z "$HERDR_ENV" ]]` to the hook's condition. See [`reference/config/tmux-guard.zsh`](reference/config/tmux-guard.zsh).
*Check:* `HERDR_ENV=1 SSH_CONNECTION=x bash -c 'zsh -i -c "echo \${TMUX:-none}"'` prints `none`.

### I-3 Key bindings live on the server
Custom and plugin key bindings **MUST** be defined in the **server's** `~/.config/herdr/config.toml`, and the client **MUST** attach with `--remote-keybindings server`.

*Why:* by default `--remote` uses the client's key bindings and **does not send** custom/plugin bindings, since those commands run on the remote host. Bindings defined on the server silently do nothing.

### I-4 Prefix doesn't fight the agent
The prefix key **SHOULD NOT** collide with a key your agent needs, or you **MUST** know how to send it through.

*Why:* herdr's default prefix is `ctrl+b`, which Claude Code uses to background a running command. `ctrl+b ctrl+b` sends a literal `ctrl+b`. Alternatively change `[keys] prefix`.
Also check custom bindings against herdr's defaults (`herdr --default-config`), e.g. `prefix+r` is resize mode.

### I-5 The server outlives the session
The herdr server **MUST** keep running after the client detaches or the SSH connection drops. Agents **MUST** still be running on reattach.

*Notes:* herdr runs as a detached daemon, like tmux. If your system kills user processes on logout (`KillUserProcesses=yes`) or you run herdr under systemd `--user`, enable lingering (`loginctl enable-linger $USER`). After a server **reboot** herdr restores the layout; agents resume their conversations only with an integration (`herdr integration install claude`).

### I-6 Third-party code is reviewed and pinned
Plugins **MUST** be reviewed before installing (manifest, build script, action scripts) and **SHOULD** be pinned with `herdr plugin install <owner/repo> --ref <commit> --yes`. Download scripts **SHOULD** be read before piping to a shell.

*Why:* herdr doesn't sandbox plugins; they run as your user, beside your agents' repos.

### I-7 Idempotent, minimal-privilege install
Every install step **MUST** be safe to re-run. Installs **SHOULD** avoid sudo: static binaries into `~/.local/bin` or `~/.local/opt/<tool>`. Configs **MUST** be backed up (`<file>.bak.YYYY-MM-DD`) before changing, and merged rather than overwritten.

### I-8 Locale and terminal type are honest
The server **MUST** have the locale your client sends (`LANG`), or the UI mangles UTF-8 box drawing. Overriding `TERM` (e.g. `export TERM=xterm-256color` in a shell rc) **MAY** hide your terminal's capabilities; if images don't render, test with the real `TERM` first.

## 4. Optional features (reference implementations included)

### F-1 Images from the file viewer
Selecting an image and pressing `O` opens a split that draws it with the kitty graphics protocol through `--remote`. Any key closes it.
→ [`reference/bin/herdr-fv-open`](reference/bin/herdr-fv-open) + [`reference/bin/kitty-img-view`](reference/bin/kitty-img-view) (Python + Pillow), wired through the file viewer's `open = "herdr-fv-open"` setting.

### F-2 GitHub-style markdown preview
Pressing `O` on a `.md` file opens a split running [go-grip] (offline, GitHub styling, tables, mermaid, live reload), bound to the server's **private-network** address (e.g. Tailscale), and prints a URL to ctrl+click in your desktop browser. Closing the pane stops it.
*Security:* while it runs, the preview serves the file's directory. Bind it to a private interface (tailnet, LAN, VPN), **never** `0.0.0.0` on a public host. Without a private network, bind `127.0.0.1` and use `ssh -L`.

### F-3 Image paste into agents
Nothing to set up: in `--remote`, `ctrl+v` (herdr's `remote_image_paste`) uploads the client's clipboard image to a server temp file and pastes its path. Copy *image data* (screenshot → Copy, browser → Copy Image), not an image *file*. Your terminal's own paste shortcut (e.g. kitty's `ctrl+shift+v`) pastes text only.

### F-4 Plugin bindings (reference)
| Key | Action id |
|---|---|
| `prefix+f` | `herdr-file-viewer.open-file-viewer` |
| `prefix+d` | `persiyanov.reviewr.toggle` |
| `prefix+space` | `herdr-whichkey.open` |

Action ids are `<plugin id>.<action id>` from each plugin's `herdr-plugin.toml`. The plugin id isn't always the repo name.

## Verification

Run the checks that apply to you. An agent can do everything except the last block over plain SSH.

**Agent-checkable**
- [ ] `ssh <host> true`
- [ ] client and server: `herdr --version`
- [ ] `ssh <host> 'command -v herdr hx <agent> node delta bat glow'` all resolve (I-1)
- [ ] shell auto-start guard proven with a simulated herdr pane (I-2)
- [ ] `ssh <host> 'infocmp xterm-kitty'` succeeds (or your terminal's terminfo)
- [ ] `ssh <host> 'locale -a'` includes the client's `LANG` (I-8)
- [ ] `hx --health <lang>` finds each language server you need
- [ ] `herdr plugin list` shows the plugins enabled at the pinned commits (I-6)
- [ ] `herdr config check` returns `ok`, and bindings use real action ids (I-3, I-4)
- [ ] the launcher/alias passes `--remote-keybindings server` (I-3)

**Human-checkable (the agent can't drive the TUI)**
- [ ] a new pane gives a plain shell, not tmux (I-2)
- [ ] the prefix chords work; `prefix prefix` reaches the agent (I-4)
- [ ] `kitty-img-test <png>` draws an image through `--remote` (F-1)
- [ ] `O` on an image / `.md` file opens the split / preview (F-1, F-2)
- [ ] `ctrl+v` pastes a screenshot into the agent (F-3)
- [ ] detach (`prefix+q`), reattach: agents still running (I-5)
