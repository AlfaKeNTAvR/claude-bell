# terminator-claude-bell

Flashes the Terminator terminal titlebar when Claude Code finishes or needs your attention.

- **Green slow flash** — Claude finished, waiting for your next message
- **Red fast flash** — Claude asked you a question, or a permission prompt appeared

The flash targets only the specific split pane where Claude is running and persists until you click or type in that pane.

## Requirements

**Linux (Terminator)**
- [Terminator](https://gnome-terminator.org/) terminal emulator
- [Claude Code](https://claude.ai/claude-code) CLI

**Windows (Windows Terminal)**
- Windows 11
- [Windows Terminal](https://aka.ms/terminal)
- [Claude Code](https://claude.ai/claude-code) CLI (native Win32, no WSL)
- Windows PowerShell 5.1 (built into Windows 11)

## Installation

### Windows (Windows Terminal)

#### Option A — script

```powershell
.\install.ps1
```

No dependencies beyond what ships with Windows 11. Does not require admin rights.

#### Option B — ask Claude Code

Clone the repo, open a Claude Code session inside it, and say:

> Set up claude-bell for me.

Claude has full context in `CLAUDE.md`.

#### Option C — manual

<details>
<summary>Step-by-step instructions</summary>

**1. Copy hook scripts**

```powershell
New-Item -ItemType Directory -Force "$HOME\.claude\hooks"
Copy-Item hooks\stop.ps1   "$HOME\.claude\hooks\"
Copy-Item hooks\notify.ps1 "$HOME\.claude\hooks\"
```

**2. Register the app ID** (so toasts show "Claude Code" as the source in Windows Settings)

```powershell
$r = "HKCU:\Software\Classes\AppUserModelId\ClaudeCode"
New-Item -Path $r -Force | Out-Null
New-ItemProperty -Path $r -Name DisplayName      -Value "Claude Code" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $r -Name ShowInSettings   -Value 1             -PropertyType DWord  -Force | Out-Null
```

**3. Register the `windowsterminal:` URI handler** (so clicking a toast focuses Windows Terminal)

```powershell
$wt = (Get-Command wt.exe).Source
$u  = "HKCU:\Software\Classes\windowsterminal"
New-Item -Path "$u\shell\open\command" -Force | Out-Null
New-ItemProperty -Path $u -Name "(default)"    -Value "URL:Windows Terminal" -Force | Out-Null
New-ItemProperty -Path $u -Name "URL Protocol" -Value ""                     -Force | Out-Null
New-ItemProperty -Path "$u\shell\open\command" -Name "(default)" -Value "`"$wt`" -w 0 focus-tab" -Force | Out-Null
```

**4. Merge hooks into `~/.claude/settings.json`**

If you don't have an existing settings file:
```powershell
Copy-Item settings-hooks-windows.json "$HOME\.claude\settings.json"
```

Otherwise add the `"hooks"` block from `settings-hooks-windows.json` into it manually.

</details>

---

### Linux (Terminator)

#### Option A — script

```bash
./install.sh
```

Requires Python 3 (standard) and `jq` (for merging an existing `~/.claude/settings.json`).
Restart Terminator when done.

#### Option B — ask Claude Code

Clone the repo, open a Claude Code session inside it, and say:

> Set up claude-bell for me.

Claude has full context in `CLAUDE.md` and handles the `settings.json` merge gracefully even if you have existing hooks.

#### Option C — manual

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
    visible_bell = False
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

### Windows (Windows Terminal)

Claude Code hooks fire PowerShell scripts that call the Windows Runtime toast API directly —
no external modules required.

- `Stop` hook — runs `hooks/stop.ps1`, reads `last_assistant_message` from stdin JSON, shows a
  **default** toast ("Response is ready") or a **reminder** toast ("Claude has a question") depending
  on whether the message ends with `?`
- `PermissionRequest` hook — runs `hooks/notify.ps1`, always shows the **reminder** toast ("Claude is waiting")
- `Notification` hook — runs `hooks/notify.ps1`, always shows the **reminder** toast ("Claude is waiting")

Toasts are suppressed when Windows Terminal is already the foreground window (no point notifying
if you're already there). They are attributed to "Claude Code" in the notification center (Win+N)
and respect Focus Assist / Do Not Disturb, still landing in the notification center when suppressed.
Rapid events replace rather than stack in the action center thanks to tag deduplication.

### Linux (Terminator)

Claude Code hooks write a type indicator to `/tmp/claude_bell_type` and ring the terminal bell (`\a`):

- `Stop` hook — runs `hooks/stop.py`, which reads `last_assistant_message` from stdin and writes `question` if the message ends with `?`, otherwise `done`
- `PermissionRequest` hook — writes `question` unconditionally (permission prompt = urgent)
- `Notification` hook — writes `question` unconditionally

The Terminator plugin (`plugins/bell_flash.py`) listens for the VTE `bell` signal on each pane, reads `/tmp/claude_bell_type`, and flashes the titlebar accordingly.

## Customisation

**Windows:** Edit the toast XML strings and sound references at the top of `hooks/stop.ps1` and
`hooks/notify.ps1`. Available sounds: `Notification.Default`, `Notification.Reminder`,
`Notification.IM`, `Notification.Mail`, `Notification.Alarm2`, etc.

**Linux:** Edit the constants at the top of `plugins/bell_flash.py`:

```python
_PROFILES = {
    'done':     {'color': b'#2E7D32', 'ms': 800},   # green, slow
    'question': {'color': b'#CC0000', 'ms': 300},   # red, fast
}
_FLASH_HEIGHT = 30  # permanent titlebar height in px; -1 to keep default height
_MAX_AGE_S = 2.0    # ignore bells where the type file is older than this
```
