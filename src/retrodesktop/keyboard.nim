## The keyboard: its layouts (English and Arabic, or others) and the keys
## that switch them, how fast a held key repeats, and the shortcuts' names.
## The layouts go to the X server through setxkbmap (Setup > System >
## Keyboard layouts), so every program types in the one chosen; the repeat
## through XKB itself.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retroui
import xlib, common

const
  Layouts* = [("us", "English (US)", "EN"), ("ara", "Arabic", "ع"), ("gb", "English (UK)", "GB"),
              ("fr", "French", "FR"), ("de", "German", "DE"), ("es", "Spanish", "ES"),
              ("it", "Italian", "IT"), ("tr", "Turkish", "TR"), ("fa", "Persian", "فا"),
              ("ur", "Urdu", "UR"), ("in", "Hindi", "HI"), ("ru", "Russian", "RU")]
    ## The layouts offered: XKB's name, the name shown, the panel's mark.
  Switches* = [("Alt+Shift", "grp:alt_shift_toggle"), ("Ctrl+Shift", "grp:ctrl_shift_toggle"),
               ("Win+Space", "grp:win_space_toggle"), ("Caps Lock", "grp:caps_toggle")]
    ## The keys that go to the next layout, and XKB's option for them.
  DefaultShortcuts* = [
    ("programs", "Win"), ("run", "Win+R"), ("files", "Win+E"), ("desktop", "Win+D"),
    ("left", "Win+Left"), ("right", "Win+Right"), ("maximize", "Win+Up"), ("minimize", "Win+Down"),
    ("terminal", "Ctrl+Alt+T"), ("tasklist", "Ctrl+Shift+Esc"), ("control", "Win+I"), ("lock", "Win+L"),
    ("layouts", "Win+Z")]
    ## Every shortcut and its keys at first (Control Panel > Keyboard changes them).
  ShortcutNames* = [("programs", "Open the Start menu"), ("run", "Run a program"),
                    ("files", "Open File Manager"), ("desktop", "Show the desktop (and back)"),
                    ("left", "The window on the left half"), ("right", "The window on the right half"),
                    ("maximize", "Maximize the window"), ("minimize", "Restore or minimize the window"),
                    ("terminal", "Open the Terminal"), ("tasklist", "Open Task List"),
                    ("control", "Open Control Panel"), ("lock", "Lock the screen (screen saver)"),
                    ("layouts", "Snap the window: its layouts")]
    ## What each shortcut does, as Control Panel shows it.

proc layoutsOf*(s: Settings): seq[string] =
  ## The layouts chosen ("us,ara" -> @["us", "ara"]); English alone at first.
  for x in s.setting("layouts", "us").split(','):
    if x.strip.len > 0: result.add x.strip
  if result.len == 0: result = @["us"]

proc markOf*(layout: string): string =
  ## The panel's mark for a layout ("EN", "ع").
  for (k, _, m) in Layouts:
    if k == layout: return m
  layout.toUpperAscii[0 ..< min(2, layout.len)]

var applied = ""

proc applyLayouts*(s: Settings) =
  ## The layouts and their switch to the X server (when they changed).
  let lays = layoutsOf(s)
  var opt = ""
  for (k, o) in Switches:
    if k == s.setting("layoutSwitch", "Alt+Shift"): opt = o
  let want = lays.join(",") & "|" & opt
  if want == applied: return
  applied = want
  if findExe("setxkbmap").len == 0: return
  launch("setxkbmap -layout " & quoteShell(lays.join(",")) & " -option '' " &
         (if lays.len > 1 and opt.len > 0: "-option " & opt else: ""))

proc applyRepeat*(d: Display; s: Settings) =
  ## How long a held key waits before it repeats, and how fast it repeats.
  if d == nil: return
  var delay = 500
  var rate = 25
  try:
    delay = clamp(parseInt(s.setting("repeatDelay", "500")), 150, 1000)
    rate = clamp(parseInt(s.setting("repeatRate", "25")), 2, 60)
  except ValueError: discard
  discard XAutoRepeatOn(d)
  discard XkbSetAutoRepeatRate(d, XkbUseCoreKbd, cuint(delay), cuint(1000 div rate))

proc currentGroup*(d: Display): int =
  ## The layout typing now (0 the first).
  if d == nil: return 0
  var st: array[32, uint8]
  if XkbGetState(d, XkbUseCoreKbd, addr st[0]) == 0: int(st[0]) else: 0

proc nextLayout*(d: Display; count: int) =
  ## Typing in the next layout (as the switch keys would).
  if d == nil or count < 2: return
  discard XkbLockGroup(d, XkbUseCoreKbd, cuint((currentGroup(d) + 1) mod count))
