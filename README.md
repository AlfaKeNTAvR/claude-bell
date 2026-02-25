# terminator-claude-bell

Flashes the Terminator terminal titlebar when Claude Code finishes or needs your attention.

- **Green slow flash** — Claude finished, waiting for your next message
- **Red fast flash** — Claude asked you a question, or a permission prompt appeared

The flash targets only the specific split pane where Claude is running and persists until you click or type in that pane.

## Requirements

- [Terminator](https://gnome-terminator.org/) terminal emulator
- [Claude Code](https://claude.ai/claude-code) CLI

## Installation

### Option A — script

```bash
./install.sh
```

Requires Python 3 (standard) and `jq` (for merging an existing `~/.claude/settings.json`).
Restart Terminator when done.

### Option B — ask Claude Code

Clone the repo, open a Claude Code session inside it, and say:

> Set up terminator-claude-bell for me.

Claude has full context in `CLAUDE.md` and handles the `settings.json` merge gracefully even if you have existing hooks.

### Option C — manual

<details>
<summary>Step-by-step instructions</summary>

**1. Terminator plugin**

```bash
mkdir -p ~/.config/terminator/plugins
cp plugins/bell_flash.py ~/.config/terminator/plugins/
```

Enable it: open Terminator → Preferences → Plugins → tick **BellFlashTitle**.

Add to your `~/.config/terminator/config` under `[[default]]` in the `[profiles]` section:

```ini
[profiles]
  [[default]]
    visible_bell = True
    icon_bell = False
```

Restart Terminator.

**2. Claude Code hooks**

```bash
mkdir -p ~/.claude/hooks
cp hooks/stop.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/stop.py
```

Merge the hooks from `settings-hooks.json` into your `~/.claude/settings.json`. If you don't have an existing settings file:

```bash
cp settings-hooks.json ~/.claude/settings.json
```

If you already have a settings file, add the `"hooks"` block from `settings-hooks.json` into it manually.

</details>

## How it works

Claude Code hooks write a type indicator to `/tmp/claude_bell_type` and ring the terminal bell (`\a`):

- `Stop` hook — runs `hooks/stop.py`, which reads `last_assistant_message` from stdin and writes `question` if the message ends with `?`, otherwise `done`
- `PermissionRequest` hook — writes `question` unconditionally (permission prompt = urgent)
- `Notification` hook — writes `question` unconditionally

The Terminator plugin (`plugins/bell_flash.py`) listens for the VTE `bell` signal on each pane, reads `/tmp/claude_bell_type`, and flashes the titlebar accordingly.

## Customisation

Edit the constants at the top of `plugins/bell_flash.py`:

```python
_PROFILES = {
    'done':     {'color': b'#2E7D32', 'ms': 800},   # green, slow
    'question': {'color': b'#CC0000', 'ms': 300},   # red, fast
}
_FLASH_HEIGHT = 40  # titlebar height in px while flashing; -1 to disable
```
