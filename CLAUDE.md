# CLAUDE.md — claude-bell

This file is for Claude Code agents setting up or maintaining this project.

## What this repo does

Provides notifications when Claude Code finishes a response or needs user input.

- **Linux (Terminator):** A Claude Code hook rings the terminal bell (`\a`), and a Terminator plugin flashes the titlebar of the specific pane.
- **Windows (Windows Terminal):** Claude Code hooks fire PowerShell scripts that show WinRT toast notifications. Clicking a toast focuses the existing WT window.

## File map

### Linux (Terminator)

| File | Purpose |
|------|---------|
| `plugins/bell_flash.py` | Terminator plugin — listens for VTE bell, flashes titlebar |
| `hooks/stop.py` | Claude Code Stop hook — classifies response as `done` or `question` |
| `settings-hooks.json` | Hook config snippet to merge into `~/.claude/settings.json` |
| `install.sh` | Idempotent installer for Linux |

### Windows (Windows Terminal)

| File | Purpose |
|------|---------|
| `hooks/stop.ps1` | Stop hook — reads JSON stdin, shows done/question toast via WinRT |
| `hooks/notify.ps1` | PermissionRequest/Notification hook — always shows reminder toast |
| `settings-hooks-windows.json` | Hook config snippet to merge into `~/.claude/settings.json` |
| `install.ps1` | Idempotent installer for Windows (no admin rights required) |

## Claude Code hooks used

Three hooks in `~/.claude/settings.json`:

### Stop
Fires when Claude finishes a response turn.

- **Linux:** `hooks/stop.py` reads `last_assistant_message` from stdin, writes `question` or `done` to `/tmp/claude_bell_type`, then rings the terminal bell (`\a`).
- **Windows:** `hooks/stop.ps1` reads `last_assistant_message` from stdin, shows a **"Response is ready"** or **"Claude has a question"** toast depending on whether the message ends with `?`.

**Key field:** `last_assistant_message` (string) — the last assistant message text. Used to detect questions by checking `.endswith('?')` (Linux) / `.EndsWith('?')` (Windows).

**If this breaks:** Verify the Stop hook still receives `last_assistant_message` in its stdin JSON. See Debugging hooks below.

### PermissionRequest
Fires when Claude Code is about to show a tool permission prompt.

- **Linux:** writes `question` unconditionally to `/tmp/claude_bell_type` and rings the bell.
- **Windows:** `hooks/notify.ps1` shows a **"Claude is waiting"** reminder toast.

**If this breaks:** Check if the hook event name has changed. The hook receives a JSON object with `hook_event_name`, `tool_name`, and `tool_input` fields.

### Notification
Fires for general Claude Code notifications. Catch-all for anything not covered by Stop or PermissionRequest. Same behavior as PermissionRequest on both platforms.

## Terminator plugin internals (`plugins/bell_flash.py`)

- Uses `terminatorlib.plugin.Plugin` with `terminal_menu` capability
- Scans `Terminator().terminals` on startup and every 3 s to attach to new split panes
- On each terminal attach: calls `set_size_request(-1, _FLASH_HEIGHT)` once to permanently widen the titlebar (avoids resize events during flash that would reset VTE scroll position), then connects to: `vte.bell`, `vte.button-press-event`, `vte.key-press-event`
- On bell: checks `/tmp/claude_bell_type` freshness (`_MAX_AGE_S`); ignores stale bells (e.g. bash Tab completion). If fresh, picks a color profile, applies GTK3 CSS to `terminal.titlebar`, disables `scroll-on-output` on the VTE, starts a GLib timeout for color flashing
- On interact (click/keypress): stops flashing for that specific pane
- Focus poll (`_focus_poll`, 200 ms): stops flashing only when `window.is_active() AND vte.is_focus() AND scroll is at bottom` — ensures flash persists when user is on another monitor or has scrolled up to read history

**If flash stops too early:** Check `_focus_poll` — `is_focus()` returns True for the last-focused pane even when the window isn't active. The `window.is_active()` guard prevents this. If it regresses, check GTK version behaviour of `Gtk.Widget.is_focus()` and `Gtk.Window.is_active()`.

**If scroll jumps when flash fires:** The titlebar height is set permanently on attach (`_attach_new_terminals`) to avoid resize events. If VTE scroll still resets, check whether Terminator is overriding `set_size_request` on attach and re-evaluate using `_FLASH_HEIGHT = -1` (colour-only flash).

**If the plugin doesn't load:** Confirm `BellFlashTitle` is listed in `enabled_plugins` in `~/.config/terminator/config` and that the plugin is enabled in Terminator Preferences → Plugins.

## Windows hook internals (`hooks/stop.ps1`, `hooks/notify.ps1`)

- Both scripts use `powershell.exe` (Windows PowerShell 5.1), not `pwsh` — faster startup and
  native WinRT API access without assembly downloads
- `stop.ps1` reads stdin via `[Console]::In.ReadToEnd()` (more reliable than `$Input` under
  `-File` invocation), parses with `ConvertFrom-Json`, checks `last_assistant_message.EndsWith('?')`
- Toast XML uses `scenario="reminder"` for urgent (question) and no scenario for done.
  `scenario="urgent"` requires a packaged app; `reminder` gives the same prominent display for
  unpackaged callers
- App ID `ClaudeCode` is registered in `HKCU:\Software\Classes\AppUserModelId\ClaudeCode` by
  `install.ps1` — this makes "Claude Code" appear as the notification source in the action center
- Both scripts wrap the WinRT call in `try/catch` — toast failures are silent so they never
  break Claude Code
- Both scripts wrap the focus check (`Add-Type` + P/invoke) in a separate `try/catch` that
  falls through on error — if the focus check fails for any reason, the toast still fires
- Focus suppression: `GetForegroundWindow` → `GetWindowThreadProcessId` → `Get-Process` — if
  the foreground process is `WindowsTerminal`, the script exits 0 silently (no toast needed)
- Tag deduplication: `$toast.Tag = 'claude-bell'` and `$toast.Group = 'claude-bell'` ensure
  rapid back-to-back events replace rather than stack in the action center
- Toast XML includes `activationType="protocol" launch="windowsterminal:"` — clicking a toast
  focuses the existing WT window via the `windowsterminal:` URI handler
- `install.ps1` registers `HKCU:\Software\Classes\windowsterminal\shell\open\command` pointing
  at `wt.exe -w 0 focus-tab` — this is needed because winget-installed WT does not register the
  URI handler automatically (only Store installs do)
- `install.ps1` comment lines use plain ASCII dashes (`--`) not Unicode box-drawing characters
  (`──`) — PS5.1 reads UTF-8 files as Windows-1252 by default, and box-drawing bytes contain
  `0x94` which decodes as `"`, producing stray quote characters that break the parser

**If toasts don't appear:** Check Windows Settings → System → Notifications → ensure
"Claude Code" is listed and enabled. Run `install.ps1` again to re-register the app ID.

**Hook command path format:** Uses `"$USERPROFILE/.claude/hooks/stop.ps1"` (bash variable +
forward slashes + double quotes). Claude Code runs hooks via bash on Windows, so `%USERPROFILE%`
and backslash paths don't work — bash strips unquoted backslashes and doesn't expand `%VAR%`.

**If the hook command fails:** Verify `$USERPROFILE/.claude/hooks/stop.ps1` exists.
Check execution policy: the hook command uses `-ExecutionPolicy Bypass` so policy shouldn't
matter, but confirm with `Get-ExecutionPolicy`.

## Testing after setup

### Windows

1. Run `.\install.ps1`
2. Start Claude Code in Windows Terminal
3. Send Claude a statement — expect a **"Response is ready"** toast (default sound)
4. Send something Claude responds to with a question — expect **"Claude has a question"** toast (reminder sound)
5. Trigger a permission prompt — expect **"Claude is waiting"** toast (reminder sound)
6. Open notification center (Win+N) — all toasts should be attributed to "Claude Code"
7. Keep Windows Terminal focused and send another message — no toast should appear (suppressed while WT is foreground)
8. Switch away from WT, trigger a response, click the toast — expect WT to come to front with no new tab or window opened

### Linux (Terminator)

1. Start Claude Code in a Terminator pane
2. Move focus to another monitor or application
3. Send Claude a statement — expect **green slow flash** on that pane
4. Send Claude a question that it responds to with a question — expect **red fast flash**
5. Trigger a permission prompt — expect **red fast flash**
6. Click or type in the flashing pane — flash should stop

## Debugging hooks

To inspect what a hook receives on stdin:

**Linux:**
```bash
# In ~/.claude/settings.json, temporarily replace a hook command with:
"command": "cat > /tmp/claude_hook_debug.json"
# Then trigger the hook and inspect:
cat /tmp/claude_hook_debug.json
```

**Windows:**
```json
"command": "powershell.exe -NoProfile -Command \"$input | Set-Content $env:TEMP\\claude_hook_debug.json\""
```
Then inspect `%TEMP%\claude_hook_debug.json`.
