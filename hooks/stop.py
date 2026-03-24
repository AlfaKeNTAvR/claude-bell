#!/usr/bin/env python3
"""Claude Code Stop hook: ring the terminal bell with a type indicator.

Writes 'question' or 'done' to /tmp/claude_bell_type based on whether the
last plain-text sentence of the assistant message ends with '?'.
Code blocks are stripped before checking.
"""
import json
import os
import re
import sys

data = json.load(sys.stdin)
msg = data.get('last_assistant_message', '').strip()

# Strip fenced code blocks, then check the last non-empty line
stripped = re.sub(r'```[\s\S]*?```', '', msg).strip()
last_line = stripped.rsplit('\n', 1)[-1].strip() if stripped else ''
bell_type = 'question' if last_line.endswith('?') else 'done'

with open('/tmp/claude_bell_type', 'w') as f:
    f.write(bell_type)

os.system("printf '\\a' > /dev/tty")
