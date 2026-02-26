# CLAUDE.md — terminator-claude-bell

This file is for Claude Code agents setting up or maintaining this project.

## What this repo does

Provides visual notifications in Terminator when Claude Code finishes a response or needs user input. A Claude Code hook rings the terminal bell (`\a`), and a Terminator plugin flashes the titlebar of the specific pane.

## File map

| File | Purpose |
|------|---------|
| `plugins/bell_flash.py` | Terminator plugin — listens for VTE bell, flashes titlebar |
| `hooks/stop.py` | Claude Code Stop hook — classifies response as `done` or `question` |
| `settings-hooks.json` | Hook config snippet to merge into `~/.claude/settings.json` |

## Claude Code hooks used

Three hooks in `~/.claude/settings.json`:

### Stop
Fires when Claude finishes a response turn. `hooks/stop.py` reads JSON from stdin, checks `last_assistant_message`, and writes `question` or `done` to `/tmp/claude_bell_type` before ringing the bell.

**Key field:** `last_assistant_message` (string) — the last assistant message text. Currently used to detect questions by checking `.endswith('?')`.

**If this breaks:** Verify the Stop hook still receives `last_assistant_message` in its stdin JSON. To debug, temporarily replace the hook command with `cat > /tmp/claude_hook_debug.json` and inspect the output.

### PermissionRequest
Fires when Claude Code is about to show a tool permission prompt. Always writes `question` (urgent). Confirmed working as of Claude Code with hook event name `PermissionRequest`.

**If this breaks:** Check if the hook event name has changed. The hook receives a JSON object with `hook_event_name`, `tool_name`, and `tool_input` fields.

### Notification
Fires for general Claude Code notifications. Always writes `question`. Currently a catch-all for anything not covered by Stop or PermissionRequest.

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

## Testing after setup

1. Start Claude Code in a Terminator pane
2. Move focus to another monitor or application
3. Send Claude a statement — expect **green slow flash** on that pane
4. Send Claude a question that it responds to with a question — expect **red fast flash**
5. Trigger a permission prompt — expect **red fast flash**
6. Click or type in the flashing pane — flash should stop

## Debugging hooks

To inspect what a hook receives on stdin:

```bash
# In ~/.claude/settings.json, temporarily replace a hook command with:
"command": "cat > /tmp/claude_hook_debug.json"
# Then trigger the hook and inspect:
cat /tmp/claude_hook_debug.json
```
