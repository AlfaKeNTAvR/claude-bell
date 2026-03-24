"""BellFlashTitle - Terminator plugin

Flashes the terminal titlebar on bell; color and speed depend on the
notification type written to /tmp/claude_bell_type:
  done     -> green, slow flash (800 ms)
  question -> red,   fast flash (500 ms)

Stops flashing only on explicit interaction (click, keypress, scroll, mouse move).

Install: place in ~/.config/terminator/plugins/
Enable:  Terminator Preferences → Plugins → BellFlashTitle
"""

import os
import time
import terminatorlib.plugin as plugin
from terminatorlib.terminator import Terminator

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import GLib, Gtk

AVAILABLE = ['BellFlashTitle']

_TYPE_FILE = '/tmp/claude_bell_type'

_PROFILES = {
    'done':     {'color': b'#2E7D32', 'alt': b'#C0C0C0', 'ms': 800},   # green / gray
    'question': {'color': b'#CC0000', 'alt': b'#C0C0C0', 'ms': 500},   # red / gray
}
_DEFAULT_PROFILE = 'done'

_CSS_TEMPLATE = b'* { background-color: %b; color: #FFFFFF; }'
_MAX_AGE_S = 2.0    # ignore bells where the type file is older than this
_GRACE_S = 3.0      # ignore interaction events this long after flash starts


def _read_type():
    """Return the flash profile name, or None if the type file is stale/missing."""
    try:
        stat = os.stat(_TYPE_FILE)
        if time.time() - stat.st_mtime > _MAX_AGE_S:
            return None
        with open(_TYPE_FILE) as f:
            t = f.read().strip()
        return t if t in _PROFILES else _DEFAULT_PROFILE
    except OSError:
        return None


class BellFlashTitle(plugin.Plugin):
    capabilities = ['terminal_menu']

    def __init__(self):
        super().__init__()
        self._state = {}  # terminal -> flash state dict
        GLib.idle_add(self._initial_scan)
        GLib.timeout_add(3000, self._periodic_scan)

    # --- terminal discovery -------------------------------------------

    def _initial_scan(self):
        self._attach_new_terminals()
        return False

    def _periodic_scan(self):
        self._attach_new_terminals()
        return True

    def _attach_new_terminals(self):
        try:
            terminals = Terminator().terminals
        except Exception:
            return
        for t in terminals:
            if not getattr(t, '_bft_attached', False):
                t._bft_attached = True
                t.vte.connect('bell', self._on_bell, t)
                t.vte.connect('button-press-event', self._on_interact, t)
                t.vte.connect('key-press-event', self._on_interact, t)
                t.vte.connect('scroll-event', self._on_interact, t)
                t.vte.connect('motion-notify-event', self._on_motion, t)

    # --- bell / flash logic -------------------------------------------

    def _on_bell(self, _vte, terminal):
        if terminal in self._state:
            return  # already flashing
        bell_type = _read_type()
        if bell_type is None:
            return  # stale or missing type file — not a Claude bell
        profile = _PROFILES[bell_type]
        provider_on = Gtk.CssProvider()
        provider_on.load_from_data(_CSS_TEMPLATE % profile['color'])
        provider_off = Gtk.CssProvider()
        provider_off.load_from_data(_CSS_TEMPLATE % profile['alt'])
        terminal.titlebar.get_style_context().add_provider(
            provider_on, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        scroll_on_output = terminal.vte.get_property('scroll-on-output')
        terminal.vte.set_property('scroll-on-output', False)
        ms = profile['ms']
        tid = GLib.timeout_add(ms, self._tick, terminal)
        self._state[terminal] = {'timeout': tid, 'provider_on': provider_on,
                                 'provider_off': provider_off, 'on': True,
                                 'scroll_on_output': scroll_on_output,
                                 'started': time.monotonic()}
        window = terminal.vte.get_toplevel()
        if window:
            window.set_urgency_hint(True)

    def _on_interact(self, _vte, _event, terminal):
        self._stop(terminal)
        return False  # don't consume the event

    def _on_motion(self, _vte, _event, terminal):
        s = self._state.get(terminal)
        if s and time.monotonic() - s['started'] < _GRACE_S:
            return False  # ignore spurious motion events right after flash starts
        self._stop(terminal)
        return False  # don't consume the event

    def _tick(self, terminal):
        if terminal not in self._state:
            return False
        s = self._state[terminal]
        s['on'] = not s['on']
        ctx = terminal.titlebar.get_style_context()
        if s['on']:
            ctx.remove_provider(s['provider_off'])
            ctx.add_provider(s['provider_on'], Gtk.STYLE_PROVIDER_PRIORITY_USER)
        else:
            ctx.remove_provider(s['provider_on'])
            ctx.add_provider(s['provider_off'], Gtk.STYLE_PROVIDER_PRIORITY_USER)
        return True

    def _stop(self, terminal):
        s = self._state.pop(terminal, None)
        if not s:
            return
        GLib.source_remove(s['timeout'])
        ctx = terminal.titlebar.get_style_context()
        ctx.remove_provider(s['provider_on'])
        ctx.remove_provider(s['provider_off'])
        terminal.vte.set_property('scroll-on-output', s['scroll_on_output'])
        if not self._state:
            window = terminal.vte.get_toplevel()
            if window:
                window.set_urgency_hint(False)

    # --- required by terminal_menu capability -------------------------

    def callback(self, menuitems, menu, terminal):
        pass
