"""BellFlashTitle - Terminator plugin

Flashes the terminal titlebar on bell; color and speed depend on the
notification type written to /tmp/claude_bell_type:
  done     -> green, slow flash (800 ms)
  question -> red,   fast flash (300 ms)

Stops flashing when that specific pane is focused.

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

_POLL_MS = 200
_TYPE_FILE = '/tmp/claude_bell_type'

_PROFILES = {
    'done':     {'color': b'#2E7D32', 'ms': 800},   # dark green, slow
    'question': {'color': b'#CC0000', 'ms': 300},   # red, fast
}
_DEFAULT_PROFILE = 'done'

_CSS_TEMPLATE = b'* { background-color: %b; color: #FFFFFF; }'
_FLASH_HEIGHT = 30  # px; titlebar is set to this height permanently on attach
_MAX_AGE_S = 2.0    # ignore bells where the type file is older than this


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
        self._state   = {}    # terminal -> {timeout_id, provider, on, ms}
        self._poll_id = None
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
                if _FLASH_HEIGHT > 0:
                    t.titlebar.set_size_request(-1, _FLASH_HEIGHT)
                t.vte.connect('bell', self._on_bell, t)
                t.vte.connect('button-press-event', self._on_interact, t)
                t.vte.connect('key-press-event', self._on_interact, t)

    # --- bell / flash logic -------------------------------------------

    def _on_bell(self, _vte, terminal):
        if terminal in self._state:
            return  # already flashing
        bell_type = _read_type()
        if bell_type is None:
            return  # stale or missing type file — not a Claude bell
        profile = _PROFILES[bell_type]
        css = _CSS_TEMPLATE % profile['color']
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        terminal.titlebar.get_style_context().add_provider(
            provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        scroll_on_output = terminal.vte.get_property('scroll-on-output')
        terminal.vte.set_property('scroll-on-output', False)
        ms = profile['ms']
        tid = GLib.timeout_add(ms, self._tick, terminal)
        self._state[terminal] = {'timeout': tid, 'provider': provider, 'on': True,
                                 'scroll_on_output': scroll_on_output}
        if self._poll_id is None:
            self._poll_id = GLib.timeout_add(_POLL_MS, self._focus_poll)

    def _on_interact(self, _vte, _event, terminal):
        self._stop(terminal)
        return False  # don't consume the event

    def _tick(self, terminal):
        if terminal not in self._state:
            return False
        s = self._state[terminal]
        s['on'] = not s['on']
        ctx = terminal.titlebar.get_style_context()
        if s['on']:
            ctx.add_provider(s['provider'], Gtk.STYLE_PROVIDER_PRIORITY_USER)
        else:
            ctx.remove_provider(s['provider'])
        return True

    def _focus_poll(self):
        if not self._state:
            self._poll_id = None
            return False
        for terminal in list(self._state.keys()):
            window = terminal.vte.get_toplevel()
            if window and window.is_active() and terminal.vte.is_focus():
                adj = terminal.vte.get_vadjustment()
                at_bottom = adj.get_value() >= adj.get_upper() - adj.get_page_size()
                if at_bottom:
                    self._stop(terminal)
        return True

    def _stop(self, terminal):
        s = self._state.pop(terminal, None)
        if not s:
            return
        GLib.source_remove(s['timeout'])
        terminal.titlebar.get_style_context().remove_provider(s['provider'])
        terminal.vte.set_property('scroll-on-output', s['scroll_on_output'])

    # --- required by terminal_menu capability -------------------------

    def callback(self, menuitems, menu, terminal):
        pass
