#!/usr/bin/env python3
"""Claude Code Stop hook: ring the terminal bell with a type indicator.

Writes 'question' to /tmp/claude_bell_type if the last assistant message
ends with a question mark, otherwise writes 'done'.
"""
import json
import os
import sys

data = json.load(sys.stdin)
msg = data.get('last_assistant_message', '').strip()
bell_type = 'question' if msg.endswith('?') else 'done'

with open('/tmp/claude_bell_type', 'w') as f:
    f.write(bell_type)

os.system("printf '\\a' > /dev/tty")
