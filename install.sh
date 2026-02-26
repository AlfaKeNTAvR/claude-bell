#!/usr/bin/env bash
# install.sh — set up claude-bell
#
# Idempotent for Terminator config edits and file copies.
# Skips settings.json merge if a Stop hook is already present there.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing claude-bell..."
echo

# ── 1. Terminator plugin ──────────────────────────────────────────────────────
mkdir -p ~/.config/terminator/plugins
cp "$REPO/plugins/bell_flash.py" ~/.config/terminator/plugins/
echo "  ✓ Plugin → ~/.config/terminator/plugins/bell_flash.py"

# ── 2. Claude Code hook ───────────────────────────────────────────────────────
mkdir -p ~/.claude/hooks
cp "$REPO/hooks/stop.py" ~/.claude/hooks/
chmod +x ~/.claude/hooks/stop.py
echo "  ✓ Hook → ~/.claude/hooks/stop.py"

# ── 3. Claude Code settings.json ─────────────────────────────────────────────
SETTINGS=~/.claude/settings.json
if [ ! -f "$SETTINGS" ]; then
    cp "$REPO/settings-hooks.json" "$SETTINGS"
    echo "  ✓ Settings → $SETTINGS (created)"
elif ! command -v jq &>/dev/null; then
    echo "  ⚠ jq not found — manually merge settings-hooks.json into $SETTINGS"
    echo "    (apt install jq and re-run, or ask Claude Code to do it)"
elif jq -e '.hooks.Stop // empty' "$SETTINGS" &>/dev/null; then
    echo "  ✓ Hooks already present in $SETTINGS (skipped)"
else
    tmp=$(mktemp)
    jq -s '
      .[0] as $e | .[1].hooks as $nh |
      $e | .hooks = (
        (($e.hooks // {}) | to_entries) + ($nh | to_entries) |
        group_by(.key) |
        map({key: .[0].key, value: ([.[].value] | add)}) |
        from_entries
      )
    ' "$SETTINGS" "$REPO/settings-hooks.json" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  ✓ Hooks merged → $SETTINGS"
fi

# ── 4. Terminator config: bell settings + enable plugin ──────────────────────
python3 - <<'PYEOF'
import os, re

cfg = os.path.expanduser("~/.config/terminator/config")
os.makedirs(os.path.dirname(cfg), exist_ok=True)

text = open(cfg).read() if os.path.exists(cfg) else ""
changed = []

def set_bell_key(text, key, value):
    """Set key = value; updates in-place if present, else inserts under [[default]]."""
    pat = re.compile(r'^([ \t]*)' + re.escape(key) + r'[ \t]*=[ \t]*\S+', re.MULTILINE)
    if pat.search(text):
        def repl(m):
            cur = m.group(0).split('=', 1)[1].strip()
            if cur == value:
                return m.group(0)
            changed.append(f'updated {key} = {value}')
            return m.group(1) + f'{key} = {value}'
        return pat.sub(repl, text)
    # Not found — insert after [[default]] header
    sec = re.compile(r'^([ \t]*\[\[default\]\][ \t]*)$', re.MULTILINE)
    m = sec.search(text)
    if m:
        changed.append(f'added {key} = {value}')
        return text[:m.end()] + f'\n    {key} = {value}' + text[m.end():]
    # No [[default]] at all — append a minimal profiles block
    changed.append(f'created [[default]] with {key} = {value}')
    return text + f'\n[profiles]\n  [[default]]\n    {key} = {value}\n'

def enable_plugin(text, name):
    """Add name to enabled_plugins; creates the line if absent."""
    pat = re.compile(r'^([ \t]*enabled_plugins[ \t]*=[ \t]*)(.*)$', re.MULTILINE)
    m = pat.search(text)
    if m:
        plugins = [p.strip() for p in m.group(2).split(',') if p.strip()]
        if name in plugins:
            return text
        plugins.append(name)
        changed.append(f'added {name} to enabled_plugins')
        return pat.sub(m.group(1) + ', '.join(plugins), text)
    # No enabled_plugins line — add under [global_config]
    gc = re.compile(r'^([ \t]*\[global_config\][ \t]*)$', re.MULTILINE)
    m = gc.search(text)
    if m:
        changed.append(f'set enabled_plugins = {name}')
        return text[:m.end()] + f'\n  enabled_plugins = {name}' + text[m.end():]
    # No [global_config] either — prepend one
    changed.append(f'prepended [global_config] with enabled_plugins = {name}')
    return f'[global_config]\n  enabled_plugins = {name}\n' + text

text = set_bell_key(text, 'visible_bell', 'False')
text = set_bell_key(text, 'icon_bell', 'False')
text = enable_plugin(text, 'BellFlashTitle')

if changed:
    open(cfg, 'w').write(text)
    for c in changed:
        print(f'  ✓ Terminator config: {c}')
else:
    print('  ✓ Terminator config: already up to date')
PYEOF

echo
echo "Done. Restart Terminator to apply changes."
