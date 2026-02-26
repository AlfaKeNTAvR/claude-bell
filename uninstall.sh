#!/usr/bin/env bash
# uninstall.sh — remove claude-bell
#
# Mirrors install.sh in reverse. Safe to run multiple times.

set -euo pipefail

echo "Uninstalling claude-bell..."
echo

# ── 1. Terminator plugin ──────────────────────────────────────────────────────
plugin=~/.config/terminator/plugins/bell_flash.py
if [ -f "$plugin" ]; then
    rm "$plugin"
    echo "  ✓ Removed ~/.config/terminator/plugins/bell_flash.py"
else
    echo "  - Plugin not found (skipped)"
fi

# ── 2. Claude Code hook ───────────────────────────────────────────────────────
hook=~/.claude/hooks/stop.py
if [ -f "$hook" ]; then
    rm "$hook"
    echo "  ✓ Removed ~/.claude/hooks/stop.py"
else
    echo "  - Hook not found (skipped)"
fi

# ── 3. Temp file ──────────────────────────────────────────────────────────────
if [ -f /tmp/claude_bell_type ]; then
    rm /tmp/claude_bell_type
    echo "  ✓ Removed /tmp/claude_bell_type"
fi

# ── 4. Claude Code settings.json ─────────────────────────────────────────────
SETTINGS=~/.claude/settings.json
if [ ! -f "$SETTINGS" ]; then
    echo "  - $SETTINGS not found (skipped)"
elif ! command -v jq &>/dev/null; then
    echo "  ⚠ jq not found — manually remove claude-bell hooks from $SETTINGS"
    echo "    (apt install jq and re-run, or ask Claude Code to do it)"
else
    tmp=$(mktemp)
    jq '
      def drop_bell_hooks(event; pattern):
        if .hooks[event] then
          .hooks[event] |= map(
            select(.hooks | all(.command | test(pattern) | not))
          )
          | if (.hooks[event] | length) == 0 then del(.hooks[event]) else . end
        else . end;

      drop_bell_hooks("Stop"; "stop\\.py")
      | drop_bell_hooks("PermissionRequest"; "claude_bell_type")
      | drop_bell_hooks("Notification"; "claude_bell_type")
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  ✓ Hooks removed from $SETTINGS"
fi

# ── 5. Terminator config: bell settings + plugin ─────────────────────────────
python3 - <<'PYEOF'
import os, re

cfg = os.path.expanduser("~/.config/terminator/config")
if not os.path.exists(cfg):
    print("  - Terminator config not found (skipped)")
    raise SystemExit(0)

text = open(cfg).read()
changed = []
original = text

# Remove visible_bell and icon_bell lines set by the installer
for key in ('visible_bell', 'icon_bell'):
    pat = re.compile(r'^[ \t]*' + re.escape(key) + r'[ \t]*=[ \t]*False[ \t]*\n', re.MULTILINE)
    new = pat.sub('', text)
    if new != text:
        changed.append(f'removed {key} = False')
        text = new

# Remove BellFlashTitle from enabled_plugins
pat = re.compile(r'^([ \t]*enabled_plugins[ \t]*=[ \t]*)(.*)$', re.MULTILINE)
m = pat.search(text)
if m:
    plugins = [p.strip() for p in m.group(2).split(',') if p.strip() and p.strip() != 'BellFlashTitle']
    if m.group(2).strip() != ', '.join(plugins):
        changed.append('removed BellFlashTitle from enabled_plugins')
        if plugins:
            text = pat.sub(m.group(1) + ', '.join(plugins), text)
        else:
            # Remove the whole enabled_plugins line
            text = re.sub(r'^[ \t]*enabled_plugins[ \t]*=.*\n', '', text, flags=re.MULTILINE)

if changed:
    open(cfg, 'w').write(text)
    for c in changed:
        print(f'  ✓ Terminator config: {c}')
else:
    print('  ✓ Terminator config: nothing to remove')
PYEOF

echo
echo "Done. Restart Terminator to apply changes."
