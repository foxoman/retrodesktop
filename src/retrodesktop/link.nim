## How the desktop's programs talk to the desktop, on the X screen they
## share: the windows it manages (_NET_CLIENT_LIST, their names, their
## processes), bringing one to the front or closing it (EWMH), the desktop's
## own requests (_RETRO_DESKTOP: cascade, tile, arrange icons, exit), and
## following the look Control Panel sets as it changes.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import retroui
import retroui/uirelays/drivers/x11_driver
import xlib, common, art

const
  RetroCascade* = 1
  RetroTile* = 2
  RetroArrange* = 3
  RetroLookChanged* = 4
  RetroExit* = 5
  RetroAskExit* = 6
  RetroPing* = 7
    ## (a desktop started again asks the one that runs whether it answers:
    ## it puts the number it was sent in the root's _RETRO_DESKTOP_PONG)

  LookAtom* = "_RETRO_DESKTOP_LOOK"
    ## a number on the root window the desktop counts up when the look
    ## changes (the desktop's programs follow it)

type
  WinInfo* = object
    ## A window the desktop manages.
    win*: Window
    title*: string
    pid*: int
    iconic*: bool

proc display(): Display = x11Display()

proc rootOf(d: Display): Window = XRootWindow(d, XDefaultScreen(d))

proc desktopRunning*(): bool =
  ## Retro Desktop manages the screen.
  let d = display()
  if d == nil: return false
  let r = rootOf(d)
  let c = propLongs(d, r, atom(d, "_NET_SUPPORTING_WM_CHECK"), XA_WINDOW)
  if c.len == 0: return false
  var name = ""
  trapErrors(d):
    name = propText(d, Window(c[0]), atom(d, "_NET_WM_NAME"))
  not xTrapped and name == DesktopName

proc sendToRoot(kind: Atom; win: Window; a0, a1, a2: clong) =
  let d = display()
  if d == nil: return
  var e: XEvent
  e.xclient.theType = ClientMessage
  e.xclient.window = win
  e.xclient.messageType = kind
  e.xclient.format = 32
  e.xclient.data[0] = a0
  e.xclient.data[1] = a1
  e.xclient.data[2] = a2
  discard XSendEvent(d, rootOf(d), 0, SubstructureRedirectMask or SubstructureNotifyMask, addr e)
  discard XFlush(d)

proc retroCommand*(n: int) =
  ## Asks the desktop to do `n` (RetroCascade, RetroTile, RetroArrange,
  ## RetroLookChanged, RetroExit, RetroAskExit).
  let d = display()
  if d == nil: return
  sendToRoot(atom(d, "_RETRO_DESKTOP"), rootOf(d), clong(n), 0, 0)

proc windows*(): seq[WinInfo] =
  ## The windows the desktop manages, the one in front last.
  let d = display()
  if d == nil: return
  let r = rootOf(d)
  let me = Window(x11Window())
  let netName = atom(d, "_NET_WM_NAME")
  let pidAtom = atom(d, "_NET_WM_PID")
  let state = atom(d, "_NET_WM_STATE")
  let hidden = clong(atom(d, "_NET_WM_STATE_HIDDEN"))
  # (a window may close while it is asked about: its error is no error)
  trapErrors(d):
    for w in propLongs(d, r, atom(d, "_NET_CLIENT_LIST_STACKING"), XA_WINDOW):
      let win = Window(w)
      if win == me: continue
      var t = propText(d, win, netName)
      if t.len == 0: t = propText(d, win, XA_WM_NAME)
      let p = propLongs(d, win, pidAtom, XA_CARDINAL)
      result.add WinInfo(win: win, title: (if t.len > 0: t else: "Untitled"),
                         pid: (if p.len > 0: int(p[0]) else: 0),
                         iconic: hidden in propLongs(d, win, state, XA_ATOM))

proc activate*(w: Window) =
  ## Brings `w` to the front (restored when it is an icon).
  let d = display()
  if d == nil: return
  sendToRoot(atom(d, "_NET_ACTIVE_WINDOW"), w, 2, 0, 0)

proc closeWindow*(w: Window) =
  ## Asks `w`'s program to close it.
  let d = display()
  if d == nil: return
  sendToRoot(atom(d, "_NET_CLOSE_WINDOW"), w, 0, 2, 0)

proc minimizeSelf*() =
  ## Makes this program's window an icon (WM_CHANGE_STATE, as ICCCM says).
  let d = display()
  if d == nil: return
  sendToRoot(atom(d, "WM_CHANGE_STATE"), Window(x11Window()), 3, 0, 0)

proc maximizeSelf*() =
  ## Asks for this program's window to fill the screen (_NET_WM_STATE).
  let d = display()
  if d == nil: return
  sendToRoot(atom(d, "_NET_WM_STATE"), Window(x11Window()), 1,
             clong(atom(d, "_NET_WM_STATE_MAXIMIZED_HORZ")), clong(atom(d, "_NET_WM_STATE_MAXIMIZED_VERT")))

proc resizeSelf*(w, h: int) =
  ## This program's window made `w` x `h` design pixels big (as `openApp`
  ## takes them), as far as the window manager lets it.
  let d = display()
  if d == nil: return
  let k = devScale()
  discard XResizeWindow(d, Window(x11Window()), cuint(max(1, int(float(w) * k))),
                        cuint(max(1, int(float(h) * k))))
  discard XFlush(d)

proc fullscreenSelf*() =
  ## Asks for this program's window to cover the whole screen (a screen saver).
  let d = display()
  if d == nil: return
  sendToRoot(atom(d, "_NET_WM_STATE"), Window(x11Window()), 1,
             clong(atom(d, "_NET_WM_STATE_FULLSCREEN")), 0)

proc asDialog*() =
  ## This program's window is a dialog: no sizing, no minimize or maximize
  ## button, in the middle of the screen (the desktop's Run, About, Exit).
  let d = display()
  if d == nil: return
  let w = Window(x11Window())
  var a: XWindowAttributes
  if XGetWindowAttributes(d, w, addr a) == 0: return
  var h: XSizeHints
  h.flags = PMinSize or PMaxSize
  h.minWidth = a.width
  h.maxWidth = a.width
  h.minHeight = a.height
  h.maxHeight = a.height
  XSetWMNormalHints(d, w, addr h)
  setLongs(d, w, atom(d, "_NET_WM_WINDOW_TYPE"), XA_ATOM,
           [clong(atom(d, "_NET_WM_WINDOW_TYPE_DIALOG"))])
  # (in the middle: the window manager may have placed it before it knew)
  let s = XDefaultScreen(d)
  discard XMoveWindow(d, w, max(0, (XDisplayWidth(d, s) - a.width) div 2),
                      max(0, (XDisplayHeight(d, s) - a.height) div 3))
  discard XFlush(d)

proc showArt*(kind: string) =
  ## The desktop's icon `kind` (art.nim) as this window's own icon
  ## (_NET_WM_ICON, at 16, 32 and 48 pixels): on the desktop when it is
  ## minimized, in Alt+Tab's box.
  let d = display()
  if d == nil: return
  var data: seq[clong]
  for size in [16, 32, 48]:
    let b = appIcon(kind, size)
    if b == nil: continue
    data.add clong(b.w)
    data.add clong(b.h)
    for p in b.px: data.add clong(p)
  if data.len > 0:
    setLongs(d, Window(x11Window()), atom(d, "_NET_WM_ICON"), XA_CARDINAL, data)
    discard XFlush(d)

proc findWindow*(title: string): Window =
  ## A managed window called `title` (0 when there is none).
  for w in windows():
    if w.title == title: return w.win

# ---- following the look --------------------------------------------------------------------------

var
  lookAtomId: Atom
  lookSerial: clong
  onLook: proc () {.nimcall.}

proc readSerial(d: Display): clong =
  let v = propLongs(d, rootOf(d), lookAtomId, XA_CARDINAL)
  if v.len > 0: v[0] else: 0

proc lookHook(p: pointer): bool {.nimcall.} =
  let e = cast[ptr XEvent](p)
  if e.theType == PropertyNotify and e.xproperty.atom == lookAtomId and lookAtomId != 0:
    let d = display()
    let s = readSerial(d)
    if s != lookSerial:
      lookSerial = s
      applyDesktopLook()
      if onLook != nil: onLook()
      ui.redraw = true
      x11Wake()
    return true
  false

proc followLook*(changed: proc () {.nimcall.} = nil) =
  ## The program takes the look Control Panel sets now (`applyDesktopLook`)
  ## and again each time it changes (`changed` too, when given). Call it
  ## after the window is open.
  applyDesktopLook()
  let d = display()
  if d == nil or x11EventHook != nil: return
  onLook = changed
  lookAtomId = atom(d, LookAtom)
  lookSerial = readSerial(d)
  var a: XWindowAttributes
  let r = rootOf(d)
  if XGetWindowAttributes(d, r, addr a) != 0:
    discard XSelectInput(d, r, a.yourEventMask or PropertyChangeMask)
  x11EventHook = lookHook

proc announceLook*() =
  ## Tells the desktop's programs the look changed (the desktop calls it).
  let d = display()
  if d == nil: return
  let a = atom(d, LookAtom)
  let v = propLongs(d, rootOf(d), a, XA_CARDINAL)
  setLongs(d, rootOf(d), a, XA_CARDINAL, [(if v.len > 0: v[0] + 1 else: 1)])
  discard XFlush(d)

# ---- processes ------------------------------------------------------------------------------------

proc processMemory*(pid: int): int64 =
  ## How much memory process `pid` holds, bytes (0 when it cannot be read):
  ## its own share (Pss: its own pages, and its part of the pages it shares
  ## with the desktop's other programs -- the code, the libraries), else
  ## its resident set.
  try:
    for line in lines("/proc/" & $pid & "/smaps_rollup"):
      if line.len > 4 and line[0 .. 3] == "Pss:":
        var n: int64 = 0
        for ch in line:
          if ch in {'0' .. '9'}: n = n * 10 + int64(ord(ch) - ord('0'))
        return n * 1024
  except CatchableError: discard
  try:
    for line in lines("/proc/" & $pid & "/status"):
      if line.len > 6 and line[0 .. 5] == "VmRSS:":
        var n: int64 = 0
        for ch in line:
          if ch in {'0' .. '9'}: n = n * 10 + int64(ord(ch) - ord('0'))
        return n * 1024
  except CatchableError: discard
  0

proc sendRetroCommand*(n: int) =
  ## `retroCommand` from a program with no window of its own (a script, the
  ## checks): `retro-desktop --retro-command 1` cascades.
  let d = XOpenDisplay(nil)
  if d == nil: return
  let r = rootOf(d)
  var e: XEvent
  e.xclient.theType = ClientMessage
  e.xclient.window = r
  e.xclient.messageType = atom(d, "_RETRO_DESKTOP")
  e.xclient.format = 32
  e.xclient.data[0] = clong(n)
  discard XSendEvent(d, r, 0, SubstructureRedirectMask or SubstructureNotifyMask, addr e)
  discard XSync(d, 0)
  discard XCloseDisplay(d)
