## The window manager: every program's window in a Windows 3.1 frame --
## its title bar, control-menu box, minimize and maximize buttons, sizing
## border -- moved, sized, maximized, minimized to an icon on the desktop,
## closed; click to focus, Alt+Tab, Alt+F4, Ctrl+Esc; dialogs over their
## windows, programs that go full screen, the screen turning (EWMH, ICCCM).
##
## It works on the X connection of the desktop's own window (Retro Nim UI's
## X11 driver), through `x11EventHook`: the desktop draws itself with the
## kit, the frames are drawn here (the title bars with the kit's canvas, in
## the kit's fonts and colors).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[math, tables, algorithm, strutils, os]
from std/posix import kill, Pid, SIGSTOP, SIGCONT
from std/times import epochTime
import retroui
import retroui/canvas2d
import retroui/uirelays/drivers/x11_driver
import retroui/uirelays/screen
import xlib, common

type
  Part* = enum
    ## Where in a frame the pointer is.
    pNone, pClient, pTitle, pMenu, pMin, pMax, pN, pS, pW, pE, pNW, pNE, pSW, pSE

  Client* = ref object
    ## A program's window and the frame around it.
    win*, frame*: Window
    title*: string
    x*, y*: int                ## the frame's place on the screen
    w*, h*: int                ## the window's size (inside the frame)
    iconic*, maximized*, fullscreen*: bool
    saved: tuple[x, y, w, h: int]
    transient*: Window
    canDelete, takeFocus, noInput, fixed: bool
      ## (`fixed`: the program asked for one size -- it can still be sized,
      ## no smaller than that)
    splash*: bool              ## a splash screen: not sized, no buttons
    zoned*: bool               ## snapped to a part of the screen (`zone`)
    zone*: Zone
    posGiven: bool             ## the program said where its window goes
    dialog*: bool              ## a dialog (centered when it belongs to no window)
    minW, minH: int
    icon*: Bitmap              ## its icon (_NET_WM_ICON), nil when it has none
    iconRead: bool
    pressed: Part
    class*: string             ## its WM_CLASS class ("Firefox", "Gimp")
    pid*: int                  ## its process (_NET_WM_PID), 0 when not said

  DragKind = enum dkNone, dkMove, dkResize, dkButton

  Zone* = tuple[x0, y0, x1, y1: float]
    ## A part of the work area, as fractions of it (the left half: 0, 0, 0.5, 1).

  MenuItem* = object
    label*, keys*: string
    enabled*: bool
    action*: proc ()
    icon*: Bitmap
    sub*: proc (): seq[MenuItem]
    ## A menu's item: its label ("&" before the letter to underline; "" a
    ## line between groups), its keys, whether it can be chosen, what it does,
    ## its picture (nil: none; `menuIconSize` pixels), the items of the menu
    ## it opens beside it (nil: none).

var
  dpy*: Display
  scr: cint
  root*, desk*, checkWin: Window
  clients*: seq[Client]          ## bottom to top
  active*: Client
  desktopShown: seq[Client]      # (Win+D: the windows it minimized, to bring back)
  gc: pointer
  running*: bool
  otherWm: bool
  changed*: proc () {.nimcall.}  ## the desktop should draw again (icons)
  taskList*: proc () {.nimcall.} ## Task List (Ctrl+Esc when there is no Start menu)
  startMenu*: proc (): bool {.nimcall.}
    ## Ctrl+Esc: the panel's Start menu (false: no panel, Task List then)
  keyboardChanged*: proc () {.nimcall.}
    ## the layout typing changed (the panel's mark follows)
  xkbBase = -1.cint               # (XKB's first event number)
  shortcut*: proc (action: string) {.nimcall.}
    ## a shortcut of the desktop's (programs, run, files, terminal, tasklist,
    ## control, lock): the desktop does it; the windows' own (left, right,
    ## maximize, minimize, desktop) the manager does
  command*: proc (n, arg: int) {.nimcall.}
    ## a _RETRO_DESKTOP message the desktop answers (3 arrange icons,
    ## 4 the settings changed, 5 exit)
  sound*: proc (event: string) {.nimcall.}
    ## a window opened, closed, was minimized, maximized, restored: its sound
  refresh*: proc () {.nimcall.}  ## the windows, their order or titles changed (the panel)
  bigFrames*: bool               ## title bars and borders for fingers
  maximizeNew*: bool             ## new windows open maximized (a phone)
  drag: tuple[kind: DragKind; c: Client; part: Part; rx, ry: int; x, y, w, h: int]
  lastClick: tuple[c: Client; part: Part; time: Time]
  pressTime: Time
  moved: bool
  fleur: culong
  shownCursor: Table[Window, Part]
  cascadeAt = 0
  switchWin: Window              # Alt+Tab's box (None: not shown)
  backKey = 0                    # Android's Back (XF86Back), 0 when the keyboard has none
  backCloses = false             # ... closes the window in front (Control Panel > Windows)
  backGrabbed = false
  switchTo: Client
  pending*: seq[tuple[class, title: string; x, y, w, h: int; maximized, iconic: bool; until: float]]
    ## where the programs the desktop opened again had their windows (by
    ## their class): the first window of each goes there
  aWmState, aWmProtocols, aWmDelete, aWmTakeFocus, aWmChangeState, aNetWmName, aUtf8,
    aNetActive, aNetClose, aNetState, aNetFullscreen, aNetMaxH, aNetMaxV, aNetHidden,
    aNetClientList, aNetType, aTypeDesktop, aTypeDock, aTypeDialog, aTypeSplash,
    aNetIcon, aNetFrameExtents, aRetro, aWmHints: Atom

proc changedNow() =
  if changed != nil: changed()
  if refresh != nil: refresh()
  ui.redraw = true
  x11Wake()

# ---- sizes and colors -------------------------------------------------------------------------------

proc snapshot(): seq[Client] =
  ## The windows as a list of their own, to walk while `clients` changes
  ## (raising one reorders it).
  for x in clients: result.add x

proc dpx*(v: int): int =
  ## `v` design pixels in the screen's own pixels: X windows are in them.
  if v <= 1 and v >= -1: v else: devPx(float(v))

proc bw*(): int = max(3, dpx(if bigFrames: 6 else: 4))
  ## The sizing border's width.
proc tbh*(): int = max(14, dpx(if bigFrames: 24 else: 19))
  ## The title bar's height.
proc topOf(): int = bw() + tbh() + 1
  ## From the frame's top to the window's.
proc frameW(c: Client): int = c.w + 2 * bw()
proc frameH(c: Client): int = c.h + bw() + topOf()

proc xcolor*(c: Color): culong = (culong(c.r) shl 16) or (culong(c.g) shl 8) or culong(c.b)

var screenW, screenH: int        # the root window's size, as X said it last

proc screenSize*(): tuple[w, h: int] =
  ## The screen's size now. (Xlib's DisplayWidth keeps the size the
  ## connection began with: Termux:X11 starts at one size and takes the
  ## tablet's own a moment later, and a tablet turns -- the root window's
  ## ConfigureNotify says the new one.)
  if screenW > 0 and screenH > 0: (screenW, screenH)
  else: (int(XDisplayWidth(dpy, scr)), int(XDisplayHeight(dpy, scr)))

proc readScreenSize() =
  var a: XWindowAttributes
  if XGetWindowAttributes(dpy, root, addr a) != 0:
    screenW = int(a.width)
    screenH = int(a.height)

var
  workInset*: tuple[left, top, right, bottom: int]
    ## pixels kept at each edge of the screen (the panel's, on the edge it is on)
  onTop*: seq[Window]            ## windows kept over the programs' (the panel)
  otherEvents*: proc (p: pointer): bool {.nimcall.}
    ## the events of windows of the desktop's own besides these (the panel's)

proc workRect*(): tuple[x, y, w, h: int] =
  ## The screen less the panel: where windows go, maximized windows too.
  let (sw, sh) = screenSize()
  let x = clamp(workInset.left, 0, max(0, sw - 1))
  let y = clamp(workInset.top, 0, max(0, sh - 1))
  (x, y, max(1, sw - x - workInset.right), max(1, sh - y - workInset.bottom))

proc workArea*(): tuple[w, h: int] =
  ## The work area's size (`workRect`).
  let r = workRect()
  (r.w, r.h)

proc titleColors(c: Client): tuple[bg, fg: Color] =
  let t = ui.theme
  if c == active: (t.select, t.selectText)
  else:
    let bg = if t.inactiveTitle.a == 0: t.window else: t.inactiveTitle
    let fg = if t.inactiveTitleText.a == 0: t.text else: t.inactiveTitleText
    (bg, fg)

# ---- drawing the frames -----------------------------------------------------------------------------

proc fillX(w: Window; x, y, ww, hh: int; c: Color) =
  if ww <= 0 or hh <= 0: return
  discard XSetForeground(dpy, gc, xcolor(c))
  discard XFillRectangle(dpy, w, gc, cint(x), cint(y), cuint(ww), cuint(hh))

proc putBitmap*(w: Window; b: Bitmap; x, y: int) =
  ## A picture from the kit's canvas put on a window (24-bit screens).
  if b == nil or b.w <= 0 or b.h <= 0 or XDefaultDepth(dpy, scr) < 24: return
  let img = XCreateImage(dpy, XDefaultVisual(dpy, scr), 24, ZPixmap, 0, addr b.px[0],
                         cuint(b.w), cuint(b.h), 32, cint(b.w * 4))
  if img == nil: return
  discard XPutImage(dpy, w, gc, img, 0, 0, cint(x), cint(y), cuint(b.w), cuint(b.h))
  img.data = nil                         # (the pixels are the canvas's)
  discard XFree(img)

proc hasButtons(c: Client): bool = c.transient == None and not c.splash

proc triangle(cv: Canvas2D; cx, cy, s: float; up: bool) =
  cv.beginPath()
  if up:
    cv.moveTo(cx - s, cy + s / 2); cv.lineTo(cx + s, cy + s / 2); cv.lineTo(cx, cy - s / 2)
  else:
    cv.moveTo(cx - s, cy - s / 2); cv.lineTo(cx + s, cy - s / 2); cv.lineTo(cx, cy + s / 2)
  cv.closePath()
  cv.fill()

proc bevelButton(cv: Canvas2D; x, y, s: int; down: bool) =
  ## A 3.1 title bar button's face: raised (or pressed).
  let t = ui.theme
  cv.fillStyle = t.frame
  cv.fillRect(float(x), float(y), float(s), float(s))
  cv.fillStyle = t.face
  cv.fillRect(float(x + 1), float(y), float(s - 1), float(s))
  let e = max(1, s div 10)
  if not down:
    cv.fillStyle = t.light
    cv.fillRect(float(x + 1), float(y), float(s - 1), float(e))
    cv.fillRect(float(x + 1), float(y), float(e), float(s))
    cv.fillStyle = t.shadow
    cv.fillRect(float(x + 1), float(y + s - 2 * e), float(s - 1), float(2 * e))
    cv.fillRect(float(x + s - 2 * e), float(y), float(2 * e), float(s))
  else:
    cv.fillStyle = t.shadow
    cv.fillRect(float(x + 1), float(y), float(s - 1), float(e))
    cv.fillRect(float(x + 1), float(y), float(e), float(s))

proc drawFrame*(c: Client) =
  ## The frame of `c`: its sizing border, its title bar.
  if c.fullscreen or c.iconic: return
  let t = ui.theme
  let b = bw()
  let th = tbh()
  let fw = c.frameW
  let fh = c.frameH
  let f = c.frame
  # the sizing border: black lines out and in, the face between, notches
  # across it where the corners end
  fillX(f, 0, 0, fw, b, t.face)
  fillX(f, 0, fh - b, fw, b, t.face)
  fillX(f, 0, 0, b, fh, t.face)
  fillX(f, fw - b, 0, b, fh, t.face)
  fillX(f, 0, 0, fw, 1, t.frame)
  fillX(f, 0, fh - 1, fw, 1, t.frame)
  fillX(f, 0, 0, 1, fh, t.frame)
  fillX(f, fw - 1, 0, 1, fh, t.frame)
  fillX(f, b - 1, b - 1, fw - 2 * b + 2, 1, t.frame)
  fillX(f, b - 1, fh - b, fw - 2 * b + 2, 1, t.frame)
  fillX(f, b - 1, b - 1, 1, fh - 2 * b + 2, t.frame)
  fillX(f, fw - b, b - 1, 1, fh - 2 * b + 2, t.frame)
  if not c.splash and not c.maximized:
    let cz = b + th
    for y in [cz, fh - cz - 1]:
      fillX(f, 0, y, b, 1, t.frame)
      fillX(f, fw - b, y, b, 1, t.frame)
    for x in [cz, fw - cz - 1]:
      fillX(f, x, 0, 1, b, t.frame)
      fillX(f, x, fh - b, 1, b, t.frame)
  # the title bar
  let tw = fw - 2 * b
  if tw > 4:
    let cv = newCanvas2D(tw, th)
    let (bg, fg) = titleColors(c)
    cv.fillStyle = bg
    cv.fillRect(0, 0, float(tw), float(th))
    # the control-menu box: a bar across its middle
    cv.fillStyle = t.face
    cv.fillRect(0, 0, float(th), float(th))
    cv.fillStyle = t.frame
    cv.fillRect(float(th - 1), 0, 1, float(th))
    let bwid = float(th) * 0.62
    let bh = max(2.0, float(th) * 0.16)
    let bx = (float(th - 1) - bwid) / 2
    let by = (float(th) - bh) / 2
    cv.fillStyle = t.shadow
    cv.fillRect(bx + 1, by + 1, bwid, bh)
    cv.fillStyle = t.light
    cv.fillRect(bx, by, bwid, bh)
    cv.strokeStyle = t.frame
    cv.lineWidth = 1
    cv.strokeRect(bx + 0.5, by + 0.5, bwid - 1, bh - 1)
    # minimize and maximize (restore)
    var right = tw
    if c.hasButtons:
      let s = th
      bevelButton(cv, tw - s, 0, s, c.pressed == pMax)
      bevelButton(cv, tw - 2 * s, 0, s, c.pressed == pMin)
      cv.fillStyle = t.text
      let ts = float(s) * 0.2
      let o = (if c.pressed == pMin: 1.0 else: 0.0)
      triangle(cv, float(tw - 2 * s) + float(s) / 2 + o, float(s) / 2 + o, ts, false)
      let om = (if c.pressed == pMax: 1.0 else: 0.0)
      if c.maximized:
        triangle(cv, float(tw - s) + float(s) / 2 + om, float(s) * 0.32 + om, ts * 0.8, true)
        triangle(cv, float(tw - s) + float(s) / 2 + om, float(s) * 0.68 + om, ts * 0.8, false)
      else:
        triangle(cv, float(tw - s) + float(s) / 2 + om, float(s) / 2 + om, ts, true)
      right = tw - 2 * s
    # the title, in the middle of what is left, cut short when it is long
    let px = max(9, int(round(float(th) * 0.62)))
    cv.font = "bold " & $px & "px sans-serif"
    cv.fillStyle = fg
    cv.textBaseline = "middle"
    cv.textAlign = "center"
    var title = tr(c.title)
    let room = float(right - th - 8)
    if room > 8:
      if cv.measureText(title).width > room:
        while title.len > 0 and cv.measureText(title & "...").width > room:
          title.setLen(title.len - 1)
          while title.len > 0 and (ord(title[^1]) and 0xC0) == 0x80: title.setLen(title.len - 1)
        title.add "..."
      cv.fillText(title, float(th + right) / 2, float(th) / 2 + 0.5)
    putBitmap(f, cv.toBitmap, b, b)
  fillX(f, b, b + th, tw, 1, t.frame)

proc drawAll() =
  for c in snapshot(): drawFrame(c)

# ---- the window's properties ------------------------------------------------------------------------

proc findClient*(w: Window): Client =
  for c in clients:
    if c.win == w or c.frame == w: return c

proc readTitle(c: Client) =
  var t = propText(dpy, c.win, aNetWmName)
  if t.len == 0: t = propText(dpy, c.win, XA_WM_NAME)
  c.title = if t.len > 0: t else: "Untitled"

proc readClass(c: Client) =
  let wc = propText(dpy, c.win, XA_WM_CLASS).split('\0')
  c.class = if wc.len >= 2: wc[1] elif wc.len == 1: wc[0] else: ""
  let p = propLongs(dpy, c.win, XInternAtom(dpy, "_NET_WM_PID", 0), XA_CARDINAL)
  c.pid = if p.len > 0: int(p[0]) else: 0

proc readProtocols(c: Client) =
  let p = propLongs(dpy, c.win, aWmProtocols, XA_ATOM)
  c.canDelete = clong(aWmDelete) in p
  c.takeFocus = clong(aWmTakeFocus) in p
  # (WM_HINTS: flags, input, ... -- a window that takes no input is not given
  # the keyboard)
  let h = propLongs(dpy, c.win, aWmHints, aWmHints)
  c.noInput = h.len >= 2 and (h[0] and 1) != 0 and h[1] == 0 and not c.takeFocus

proc readHints(c: Client) =
  var hints: XSizeHints
  var supplied: clong
  if XGetWMNormalHints(dpy, c.win, addr hints, addr supplied) != 0:
    # (USPosition 1, PPosition 4: where the user or the program put it)
    c.posGiven = (hints.flags and 5) != 0
    if (hints.flags and PMinSize) != 0:
      c.minW = int(hints.minWidth)
      c.minH = int(hints.minHeight)
    if (hints.flags and PMinSize) != 0 and (hints.flags and PMaxSize) != 0 and
       hints.minWidth == hints.maxWidth and hints.minHeight == hints.maxHeight and hints.minWidth > 0:
      # (one size asked for: every window can be sized here all the same --
      # a dialog larger than a phone's screen too -- so its least size is
      # no more than any window's)
      c.fixed = true
      c.minW = 0
      c.minH = 0
  c.minW = max(c.minW, dpx(60))
  c.minH = max(c.minH, dpx(20))
  let tr = propLongs(dpy, c.win, XA_WM_TRANSIENT_FOR, XA_WINDOW)
  if tr.len > 0: c.transient = Window(tr[0])

proc readIcon*(c: Client; size: int): Bitmap =
  ## The window's icon nearest `size` pixels (_NET_WM_ICON), kept.
  if c.iconRead: return c.icon
  c.iconRead = true
  let v = propLongs(dpy, c.win, aNetIcon, XA_CARDINAL)
  var i = 0
  var best = -1
  var bestW = 0
  while i + 2 <= v.len:
    let w = int(v[i])
    let h = int(v[i + 1])
    if w <= 0 or h <= 0 or i + 2 + w * h > v.len: break
    if best < 0 or abs(w - size) < abs(bestW - size) or (w >= size and bestW < size):
      best = i
      bestW = w
    i += 2 + w * h
  if best >= 0:
    let w = int(v[best])
    let h = int(v[best + 1])
    var b = Bitmap(w: w, h: h, px: newSeq[uint32](w * h))
    for k in 0 ..< w * h: b.px[k] = uint32(v[best + 2 + k] and 0xFFFFFFFF)
    c.icon = b
  c.icon

proc setWmState(c: Client; state: int) =
  setLongs(dpy, c.win, aWmState, aWmState, [clong(state), 0])

proc setNetState(c: Client) =
  var s: seq[clong]
  if c.fullscreen: s.add clong(aNetFullscreen)
  if c.maximized: s.add [clong(aNetMaxH), clong(aNetMaxV)]
  if c.iconic: s.add clong(aNetHidden)
  setLongs(dpy, c.win, aNetState, XA_ATOM, s)

proc updateClientList() =
  var l: seq[clong]
  for c in clients: l.add clong(c.win)
  setLongs(dpy, root, aNetClientList, XA_WINDOW, l)
  setLongs(dpy, root, atom(dpy, "_NET_CLIENT_LIST_STACKING"), XA_WINDOW, l)
  if refresh != nil: refresh()

proc sendConfigure(c: Client) =
  ## Tells the program where its window is on the screen (it was moved
  ## inside its frame, which X does not tell it).
  var e: XEvent
  e.xconfigure.theType = ConfigureNotify
  e.xconfigure.event = c.win
  e.xconfigure.window = c.win
  e.xconfigure.x = cint(c.x + bw())
  e.xconfigure.y = cint(c.y + topOf())
  e.xconfigure.width = cint(c.w)
  e.xconfigure.height = cint(c.h)
  discard XSendEvent(dpy, c.win, 0, StructureNotifyMask, addr e)

proc sendMessage(w: Window; kind: Atom; a0: clong; a1: clong = 0) =
  var e: XEvent
  e.xclient.theType = ClientMessage
  e.xclient.window = w
  e.xclient.messageType = kind
  e.xclient.format = 32
  e.xclient.data[0] = a0
  e.xclient.data[1] = a1
  discard XSendEvent(dpy, w, 0, 0, addr e)

# ---- placing ----------------------------------------------------------------------------------------

proc applyGeometry(c: Client) =
  ## The frame and the window where `c` says.
  if c.fullscreen:
    let (sw, sh) = screenSize()
    discard XMoveResizeWindow(dpy, c.frame, cint(-bw()), cint(-topOf()),
                              cuint(sw + 2 * bw()), cuint(sh + bw() + topOf()))
    discard XMoveResizeWindow(dpy, c.win, cint(bw()), cint(topOf()), cuint(sw), cuint(sh))
    c.w = sw
    c.h = sh
    c.x = -bw()
    c.y = -topOf()
  else:
    discard XMoveResizeWindow(dpy, c.frame, cint(c.x), cint(c.y), cuint(c.frameW), cuint(c.frameH))
    discard XMoveResizeWindow(dpy, c.win, cint(bw()), cint(topOf()), cuint(c.w), cuint(c.h))
  setLongs(dpy, c.win, aNetFrameExtents, XA_CARDINAL,
           [clong(bw()), clong(bw()), clong(topOf()), clong(bw())])
  sendConfigure(c)

proc maximizeGeometry(c: Client) =
  let r = workRect()
  c.x = r.x - bw()
  c.y = r.y - bw()
  c.w = r.w
  c.h = r.h - tbh() - 1

proc zoneRect*(z: Zone): tuple[x, y, w, h: int] =
  ## Where zone `z` of the work area is on the screen.
  let r = workRect()
  let x0 = r.x + int(round(z.x0 * float(r.w)))
  let x1 = r.x + int(round(z.x1 * float(r.w)))
  let y0 = r.y + int(round(z.y0 * float(r.h)))
  let y1 = r.y + int(round(z.y1 * float(r.h)))
  (x0, y0, x1 - x0, y1 - y0)

proc zoneGeometry(c: Client; z: Zone) =
  ## The frame of `c` filling zone `z`.
  let r = zoneRect(z)
  c.x = r.x
  c.y = r.y
  c.w = max(c.minW, r.w - 2 * bw())
  c.h = max(c.minH, r.h - bw() - topOf())

proc fitOnScreen(c: Client) =
  ## Keeps the frame on the screen: no larger than it, its title bar in it.
  let r = workRect()
  c.w = clamp(c.w, 1, max(1, r.w - 2 * bw()))
  c.h = clamp(c.h, 1, max(1, r.h - bw() - topOf()))
  c.x = clamp(c.x, r.x - (c.frameW - dpx(60)), r.x + r.w - dpx(60))
  c.y = clamp(c.y, r.y, max(r.y, r.y + r.h - topOf()))

proc place(c: Client; x, y: int; given: bool) =
  ## Where a new window goes: where it asks, over the window it belongs to
  ## (a dialog), else the next step of a cascade from the top left.
  let wr = workRect()
  let (sw, sh) = (wr.w, wr.h)
  let parent = findClient(c.transient)
  if parent != nil:
    c.x = parent.x + (parent.frameW - c.frameW) div 2
    c.y = parent.y + (parent.frameH - c.frameH) div 3
  elif (given or c.posGiven) and (x != 0 or y != 0):
    c.x = x - bw()
    c.y = y - topOf()
  elif c.dialog:
    c.x = wr.x + (sw - c.frameW) div 2
    c.y = wr.y + (sh - c.frameH) div 3
  else:
    let step = topOf()
    let (aw, ah) = (c.frameW, c.frameH)
    if aw >= sw * 9 div 10 or ah >= sh * 9 div 10:
      c.x = wr.x + (sw - aw) div 2
      c.y = wr.y + (sh - ah) div 2
    else:
      c.x = dpx(16) + cascadeAt * step
      c.y = dpx(16) + cascadeAt * step
      if c.x + aw > sw or c.y + ah > sh:
        cascadeAt = 0
        c.x = dpx(16)
        c.y = dpx(16)
      inc cascadeAt
      c.x += wr.x
      c.y += wr.y
  fitOnScreen(c)

# ---- focus and order --------------------------------------------------------------------------------

proc raiseClient(c: Client) =
  # (a new list, `c` last: `c` may be the list's own element -- taken out of
  # the list in place, it could be freed before it was put back)
  var order: seq[Client]
  for x in clients:
    if x != c: order.add x
  order.add c
  clients = order
  discard XRaiseWindow(dpy, c.frame)
  # (its dialogs stay over it)
  for d in clients:
    if d.transient == c.win and not d.iconic:
      discard XRaiseWindow(dpy, d.frame)
  # (the panel over every window, but a full-screen one)
  if not c.fullscreen:
    for w in onTop: discard XRaiseWindow(dpy, w)

proc focus*(c: Client) =
  ## `c` in front and taking the keyboard (nil: the desktop).
  let old = active
  active = c
  if c != nil:
    raiseClient(c)
    if not c.noInput:
      discard XSetInputFocus(dpy, c.win, RevertToPointerRoot, CurrentTime)
    if c.takeFocus: sendMessage(c.win, aWmProtocols, clong(aWmTakeFocus))
    setLongs(dpy, root, aNetActive, XA_WINDOW, [clong(c.win)])
  else:
    discard XSetInputFocus(dpy, desk, RevertToPointerRoot, CurrentTime)
    setLongs(dpy, root, aNetActive, XA_WINDOW, [clong(0)])
  if old != nil and old != c and old in clients: drawFrame(old)
  if c != nil: drawFrame(c)
  updateClientList()

proc focusTop() =
  let l = snapshot()
  for i in countdown(l.high, 0):
    if not l[i].iconic:
      focus(l[i])
      return
  focus(nil)

# ---- what can be done to a window -------------------------------------------------------------------

# ---- programs paused while minimized ----------------------------------------------------------------

var
  pauseIconic*: bool
    ## a program whose windows are all minimized is stopped (SIGSTOP) until
    ## one comes back: no CPU, no battery
  paused: seq[int]               ## the processes stopped
  pausedFile*: string
    ## where they are written down: a desktop that ends without letting them
    ## go on, the next one does

proc familyOf(pid: int): seq[int] =
  ## `pid` and its children, theirs, and so on (Firefox's content processes).
  result = @[pid]
  var kids: Table[int, seq[int]]
  for kind, path in walkDir("/proc"):
    let p = try: parseInt(path.extractFilename) except ValueError: -1
    if p <= 0: continue
    try:
      let st = readFile(path / "stat")
      let f = st[st.rfind(')') + 2 .. ^1].splitWhitespace
      kids.mgetOrPut(parseInt(f[1]), @[]).add p
    except CatchableError: discard
  var i = 0
  while i < result.len:
    for k in kids.getOrDefault(result[i], @[]):
      if k notin result: result.add k
    inc i

proc writePaused() =
  if pausedFile.len == 0: return
  try: writeFile(pausedFile, paused.join("\n"))
  except CatchableError: discard

proc pause(c: Client) =
  if not pauseIconic or c.class == "Retro-desktop": return
  if c.pid <= 0:
    # (a program may say its process only after its window was shown)
    let p = propLongs(dpy, c.win, XInternAtom(dpy, "_NET_WM_PID", 0), XA_CARDINAL)
    if p.len > 0: c.pid = int(p[0])
  if c.pid <= 0: return
  let me = getCurrentProcessId()
  if c.pid == me: return
  for o in clients:
    if o.pid == c.pid and not o.iconic: return     # (a window of it still shown)
  for p in familyOf(c.pid):
    if p != me and p notin paused and kill(Pid(p), SIGSTOP) == 0: paused.add p
  writePaused()

proc resume(c: Client) =
  if c == nil or c.pid <= 0 or paused.len == 0: return
  let fam = familyOf(c.pid)
  var rest: seq[int]
  for p in paused:
    if p in fam: discard kill(Pid(p), SIGCONT) else: rest.add p
  paused = rest
  writePaused()

proc resumeAll*() =
  ## Every program paused goes on (the desktop ends, the setting is off).
  for p in paused: discard kill(Pid(p), SIGCONT)
  paused = @[]
  writePaused()

proc playSound(event: string) =
  if sound != nil: sound(event)

proc close*(c: Client) =
  ## Asks the program to close the window (WM_DELETE_WINDOW), else ends it.
  if c == nil: return
  resume(c)                              # (a paused program cannot answer)
  if c.canDelete: sendMessage(c.win, aWmProtocols, clong(aWmDelete))
  else: discard XKillClient(dpy, culong(c.win))

proc minimize*(c: Client) =
  ## The window to an icon on the desktop.
  if c == nil or c.iconic: return
  c.iconic = true
  discard XUnmapWindow(dpy, c.frame)
  setWmState(c, 3)
  setNetState(c)
  if active == c: focusTop()
  changedNow()
  playSound("minimize")
  pause(c)

proc restore*(c: Client) =
  ## An icon back to its window (or a maximized window to its size before).
  if c == nil: return
  if c.iconic or c.maximized: playSound("restore")
  if c.iconic:
    resume(c)
    c.iconic = false
    discard XMapWindow(dpy, c.frame)
    setWmState(c, 1)
  elif c.maximized:
    c.maximized = false
    if c.zoned: zoneGeometry(c, c.zone)
    else: (c.x, c.y, c.w, c.h) = c.saved
    applyGeometry(c)
  elif c.zoned:
    # (snapped: back to its size before)
    c.zoned = false
    (c.x, c.y, c.w, c.h) = c.saved
    applyGeometry(c)
  setNetState(c)
  focus(c)
  drawFrame(c)
  changedNow()

proc maximize*(c: Client) =
  ## The window as large as the screen (its border off it).
  if c == nil or c.splash or c.transient != None: return
  if c.maximized:
    restore(c)
    return
  if c.iconic: restore(c)
  if not c.zoned: c.saved = (c.x, c.y, c.w, c.h)
  c.maximized = true
  playSound("maximize")
  maximizeGeometry(c)
  applyGeometry(c)
  setNetState(c)
  focus(c)
  drawFrame(c)

proc setFullscreen(c: Client; on: bool) =
  if on == c.fullscreen: return
  if on:
    if not c.maximized and not c.zoned: c.saved = (c.x, c.y, c.w, c.h)
    c.fullscreen = true
  else:
    c.fullscreen = false
    if c.maximized: maximizeGeometry(c)
    elif c.zoned: zoneGeometry(c, c.zone)
    else: (c.x, c.y, c.w, c.h) = c.saved
  applyGeometry(c)
  setNetState(c)
  focus(c)
  drawFrame(c)

proc iconicClients*(): seq[Client] =
  ## The windows minimized to icons, in the order they were made.
  for c in clients:
    if c.iconic: result.add c

proc cascade*() =
  ## The windows one over another, from the top left.
  cascadeAt = 0
  let wr = workRect()
  let (sw, sh) = (wr.w, wr.h)
  for c in snapshot():
    if c.iconic or c.fullscreen or c.transient != None: continue
    if c.maximized:
      c.maximized = false
    c.zoned = false
    c.w = min(c.w, sw * 2 div 3)
    c.h = min(c.h, sh * 2 div 3)
    c.x = wr.x + dpx(16) + cascadeAt * topOf()
    c.y = wr.y + dpx(16) + cascadeAt * topOf()
    inc cascadeAt
    fitOnScreen(c)
    applyGeometry(c)
    setNetState(c)
    raiseClient(c)
    drawFrame(c)
  if active != nil: focus(active)

proc tile*(across = false; down = false) =
  ## The windows side by side, filling the screen (`across`: one above
  ## another, as 95's Tile Horizontally; `down`: in a row, Tile Vertically).
  var l: seq[Client]
  for c in snapshot():
    if not c.iconic and not c.fullscreen and c.transient == None and not c.splash: l.add c
  if l.len == 0: return
  let wr = workRect()
  let (sw, sh) = (wr.w, wr.h)
  let cols = if across: 1 elif down: l.len else: int(ceil(sqrt(float(l.len))))
  let rows = (l.len + cols - 1) div cols
  let reserve = if iconicClients().len > 0 and workInset == (0, 0, 0, 0): dpx(76) else: 0
  for i, c in l:
    let col = i mod cols
    let row = i div cols
    c.maximized = false
    c.zoned = false
    c.x = wr.x + col * sw div cols
    c.y = wr.y + row * (sh - reserve) div rows
    c.w = sw div cols - 2 * bw()
    c.h = (sh - reserve) div rows - bw() - topOf()
    applyGeometry(c)
    setNetState(c)
    drawFrame(c)

var
  cycleList: seq[Client]
  cycleAt: int
  cycleTime: Time

proc cycleStep(back: bool; time: Time): Client =
  ## The window Alt+Tab goes to: the one behind; pressed again soon after
  ## (or while Alt is held), the one behind that, and so on through all of
  ## them (Alt+Shift+Tab: back).
  var fresh = time == CurrentTime or time < cycleTime or time - cycleTime > 1500 or
              cycleList.len == 0
  if switchWin != None: fresh = false
  for c in cycleList:
    if c notin clients: fresh = true
  if fresh:
    cycleList = @[]
    for i in countdown(clients.high, 0):
      if clients[i].transient == None: cycleList.add clients[i]
    cycleAt = 0
  cycleTime = time
  if cycleList.len < 2: return nil
  cycleAt = (cycleAt + (if back: -1 else: 1) + cycleList.len) mod cycleList.len
  cycleList[cycleAt]

proc goTo(c: Client) =
  if c == nil or c notin clients: return
  if c.iconic: restore(c) else: focus(c)

proc cycle*(back = false; time: Time = CurrentTime) =
  ## Alt+Tab without its box: the next window to the front at once.
  goTo(cycleStep(back, time))

# ---- Alt+Tab's box ----------------------------------------------------------------------------------

proc altHeld(): bool =
  ## Alt is down on the keyboard now.
  var keys: array[32, char]
  discard XQueryKeymap(dpy, addr keys)
  for sym in [XK_Alt_L, XK_Alt_R, XK_Meta_L]:
    let k = int(XKeysymToKeycode(dpy, sym))
    if k > 0 and (ord(keys[k div 8]) and (1 shl (k mod 8))) != 0: return true
  false

proc drawSwitch() =
  ## 3.1's Alt+Tab: a box in the middle of the screen with the icon and the
  ## title of the window that comes when Alt is let go.
  if switchWin == None or switchTo == nil: return
  var a: XWindowAttributes
  if XGetWindowAttributes(dpy, switchWin, addr a) == 0: return
  let w = int(a.width)
  let h = int(a.height)
  let t = ui.theme
  let cv = newCanvas2D(w, h)
  cv.fillStyle = t.frame
  cv.fillRect(0, 0, float(w), float(h))
  cv.fillStyle = t.face
  cv.fillRect(2, 2, float(w - 4), float(h - 4))
  cv.fillStyle = t.light
  cv.fillRect(2, 2, float(w - 4), 1)
  cv.fillRect(2, 2, 1, float(h - 4))
  cv.fillStyle = t.shadow
  cv.fillRect(2, float(h - 3), float(w - 4), 1)
  cv.fillRect(float(w - 3), 2, 1, float(h - 4))
  let isz = dpx(32)
  let pad = dpx(12)
  let ic = switchTo.readIcon(isz)
  if ic != nil: cv.drawImage(ic, float(pad), float((h - isz) div 2), float(isz), float(isz))
  else:
    # (no icon of its own: a little window)
    let x0 = float(pad)
    let y0 = float((h - isz) div 2)
    cv.fillStyle = t.frame
    cv.fillRect(x0, y0 + 2, float(isz), float(isz - 4))
    cv.fillStyle = t.window
    cv.fillRect(x0 + 1, y0 + 3, float(isz - 2), float(isz - 6))
    cv.fillStyle = t.select
    cv.fillRect(x0 + 1, y0 + 3, float(isz - 2), float(isz) * 0.2)
  let px = max(10, dpx(13))
  cv.font = "bold " & $px & "px sans-serif"
  cv.fillStyle = t.text
  cv.textBaseline = "middle"
  cv.textAlign = "left"
  var title = tr(switchTo.title)
  let room = float(w - isz - 3 * pad)
  while title.len > 3 and cv.measureText(title).width > room:
    title = title[0 ..< title.len - 4] & "..."
  cv.fillText(title, float(isz + 2 * pad), float(h) / 2)
  putBitmap(switchWin, cv.toBitmap, 0, 0)

proc closeSwitch() =
  if switchWin != None:
    discard XUngrabKeyboard(dpy, CurrentTime)
    discard XDestroyWindow(dpy, switchWin)
    switchWin = None

proc switchKey(back: bool; time: Time) =
  ## Alt+Tab pressed: the box shown (or its next window) while Alt is held;
  ## without Alt held (a keyboard bar's Alt, let go at once) straight there.
  let c = cycleStep(back, time)
  if c == nil:
    closeSwitch()
    return
  switchTo = c
  if switchWin == None:
    if not altHeld():
      goTo(c)
      return
    let (sw, sh) = screenSize()
    let w = min(sw - dpx(20), dpx(400))
    let h = dpx(64)
    switchWin = XCreateSimpleWindow(dpy, root, cint((sw - w) div 2), cint((sh - h) div 2),
                                    cuint(w), cuint(h), 0, 0, xcolor(ui.theme.face))
    var attrs: XSetWindowAttributes
    attrs.overrideRedirect = 1
    discard XChangeWindowAttributes(dpy, switchWin, CWOverrideRedirect, addr attrs)
    discard XSelectInput(dpy, switchWin, ExposureMask or KeyPressMask or KeyReleaseMask)
    discard XMapWindow(dpy, switchWin)
    discard XRaiseWindow(dpy, switchWin)
    let grabbed = XGrabKeyboard(dpy, switchWin, 0, GrabModeAsync, GrabModeAsync, CurrentTime) == 0
    # (Alt let go before the keyboard was ours, or the keyboard is another
    # program's: no release will come)
    if not grabbed or not altHeld():
      closeSwitch()
      goTo(c)
      return
  drawSwitch()

proc switchKeyEvent(e: XKeyEvent; press: bool) =
  var ek = e
  let sym = XLookupKeysym(addr ek, 0)
  if press:
    if sym == XK_Tab: switchKey((e.state and ShiftMask) != 0, e.time)
    elif sym == XK_Escape: closeSwitch()
  elif sym in [XK_Alt_L, XK_Alt_R, XK_Meta_L]:
    let c = switchTo
    closeSwitch()
    goTo(c)

# ---- snapping ---------------------------------------------------------------------------------------

proc snapped(c: Client; x, y: int): (int, int) =
  ## A frame moved near an edge of the screen or of another window: against
  ## it (side by side, or lined up), as a finger cannot place it to the pixel.
  let near = dpx(if bigFrames: 16 else: 10)
  let wr = workRect()
  let fw = c.frameW
  let fh = c.frameH
  var bx = x
  var by = y
  var dx = near + 1
  var dy = near + 1
  template tryX(edge, target: int) =
    if abs(target - edge) < dx:
      dx = abs(target - edge)
      bx = x + target - edge
  template tryY(edge, target: int) =
    if abs(target - edge) < dy:
      dy = abs(target - edge)
      by = y + target - edge
  tryX(x, wr.x)
  tryX(x + fw, wr.x + wr.w)
  tryY(y, wr.y)
  tryY(y + fh, wr.y + wr.h)
  for o in clients:
    if o == c or o.iconic or o.fullscreen or o.maximized: continue
    let ow = o.frameW
    let oh = o.frameH
    if y < o.y + oh + near and y + fh > o.y - near:
      tryX(x, o.x + ow)
      tryX(x + fw, o.x)
      tryX(x, o.x)
      tryX(x + fw, o.x + ow)
    if x < o.x + ow + near and x + fw > o.x - near:
      tryY(y, o.y + oh)
      tryY(y + fh, o.y)
      tryY(y, o.y)
      tryY(y + fh, o.y + oh)
  (bx, by)

# ---- menus -----------------------------------------------------------------------------------------
#
# The menus the manager shows on its own windows (override-redirect, over
# every program): a window's control menu, the desktop's, the panel's Start
# menu and its other menus. A menu can open others beside it -- an item with
# `sub` -- as Windows 95's do: the pointer resting on the item opens it (a
# moment later, so a pointer on its way to it does not close it), a click
# opens it at once, Right and Left go in and out, Esc closes one, a click
# outside all of them closes them all. They keep 3.1's look -- white, a
# black line, the selection navy; the first menu of the Start menu has a
# band down its side and large pictures, as 95's has.

type
  MenuLevel = object
    win: Window
    items: seq[MenuItem]
    hot: int                     ## the item under the pointer or the keys (-1 none)
    x, y, w, h: int
    itemH, iconW, iconSize, band: int
    opened: int                  ## the item whose menu is open beside this one (-1 none)

var
  levels: seq[MenuLevel]         ## the menus open, the first the one shown first
  menuClient: Client             ## the window a control menu is for
  menuBig = false                ## the first menu's large pictures and band
  menuArmed = false
  menuFrom: tuple[x, y: int]     ## where the pointer was when it opened
  menuDue = 0.0                  ## when the item rested on opens (or the menu beside closes)
  menuDueLevel = -1
  menuButton*: tuple[x, y, w, h: int]
    ## the button that opened the menu (the panel's Start): a press on it
    ## closes the menu and does not open it again
  menuClosedAt*: float           ## when a press on `menuButton` closed it
  menuClosed*: proc () {.nimcall.}
    ## told when the menus close (the panel lets its button up)

proc menuOpen*(): bool = levels.len > 0
  ## A menu is shown.

proc isMenuWin(w: Window): bool =
  if w == None: return false
  for l in levels:
    if l.win == w: return true

proc closeLevels(fromLevel: int) =
  ## The menus from `fromLevel` on closed (0: all of them).
  var i = levels.high
  while i >= max(0, fromLevel):
    discard XDestroyWindow(dpy, levels[i].win)
    dec i
  levels.setLen(max(0, fromLevel))
  if levels.len > 0: levels[^1].opened = -1
  menuDueLevel = -1

proc closeMenu*() =
  ## The menus that are open (a control menu, the desktop's, the Start
  ## menu) closed.
  if levels.len == 0: return
  discard XUngrabPointer(dpy, CurrentTime)
  discard XUngrabKeyboard(dpy, CurrentTime)
  closeLevels(0)
  menuClient = nil
  if menuClosed != nil:
    let f = menuClosed
    menuClosed = nil
    f()

proc menuIconSize*(): int =
  ## The size of a menu item's picture (the screen's pixels).
  max(16, dpx(if bigFrames: 32 else: 22)) - dpx(6)

proc menuBigIconSize*(): int =
  ## The size of the Start menu's large pictures.
  dpx(if bigFrames: 40 else: 32)

proc itemHeight(l: MenuLevel; it: MenuItem): int =
  if it.label.len == 0: max(dpx(8), l.itemH div 3) else: l.itemH

proc drawLevel(i: int) =
  if i < 0 or i >= levels.len: return
  let l = levels[i]
  let t = ui.theme
  let cv = newCanvas2D(l.w, l.h)
  cv.fillStyle = t.frame
  cv.fillRect(0, 0, float(l.w), float(l.h))
  cv.fillStyle = t.window
  cv.fillRect(1, 1, float(l.w - 2), float(l.h - 2))
  let rtl = ui.rtl
  # (the Start menu's band down its side, in the title bars' color; no words on it)
  if l.band > 0:
    cv.fillStyle = t.select
    let bx = if rtl: l.w - 1 - l.band else: 1
    cv.fillRect(float(bx), 1, float(l.band), float(l.h - 2))
  let left = 3 + (if rtl: 0 else: l.band)
  let right = l.w - 3 - (if rtl: l.band else: 0)
  let px = max(9, int(round(float(min(l.itemH, dpx(if bigFrames: 32 else: 22))) * 0.5)))
  cv.font = $px & "px sans-serif"
  cv.textBaseline = "middle"
  var y = 3
  for k, it in l.items:
    let ih = itemHeight(l, it)
    if it.label.len == 0:
      cv.fillStyle = t.frame
      cv.fillRect(float(left - 2), float(y + ih div 2), float(right - left + 4), 1)
      y += ih
      continue
    let hot = (k == l.hot or k == l.opened) and it.enabled
    if hot:
      cv.fillStyle = t.select
      cv.fillRect(float(left), float(y), float(right - left), float(ih))
    let ink = if not it.enabled: t.gray elif hot: t.selectText else: t.text
    let ty = float(y + ih div 2)
    if it.icon != nil:
      let isz = l.iconSize
      let ix = if rtl: right - dpx(4) - isz else: left + dpx(4)
      cv.drawImage(it.icon, float(ix), float(y + (ih - isz) div 2), float(isz), float(isz))
    let shown = it.label.replace("&&", "\1").replace("&", "").replace("\1", "&")
    let amp = block:
      var a = -1
      var j = 0
      var n = 0
      while j < it.label.len:
        if it.label[j] == '&' and j + 1 < it.label.len and it.label[j + 1] != '&':
          a = n
          break
        if it.label[j] == '&' and j + 1 < it.label.len: inc j
        inc j
        inc n
      a
    let pad = if l.iconW > 0: l.iconW + dpx(8) else: dpx(14)
    let arrowW = dpx(16)
    template label(at: float; align: string) =
      cv.textAlign = align
      cv.fillStyle = ink
      cv.fillText(shown, at, ty)
    if rtl:
      label(float(right - pad), "right")
      if it.keys.len > 0 and it.sub == nil:
        cv.textAlign = "left"
        cv.fillText(it.keys, float(left + arrowW), ty)
    else:
      label(float(left + pad), "left")
      if amp >= 0 and amp < shown.len and it.enabled:
        let x0 = float(left + pad) + cv.measureText(shown[0 ..< amp]).width
        let w = cv.measureText(shown[amp .. amp]).width
        cv.fillRect(x0, ty + float(px) * 0.45, w, max(1.0, float(px) / 12))
      if it.keys.len > 0 and it.sub == nil:
        cv.textAlign = "right"
        cv.fillText(it.keys, float(right - arrowW), ty)
    if it.sub != nil:
      # (the arrow of an item that opens a menu beside it, at the far side)
      let s = max(3.0, float(px) * 0.32)
      let ax = if rtl: float(left + dpx(8)) else: float(right - dpx(8))
      cv.fillStyle = ink
      cv.beginPath()
      if rtl:
        cv.moveTo(ax - s / 2, ty); cv.lineTo(ax + s / 2, ty - s); cv.lineTo(ax + s / 2, ty + s)
      else:
        cv.moveTo(ax + s / 2, ty); cv.lineTo(ax - s / 2, ty - s); cv.lineTo(ax - s / 2, ty + s)
      cv.closePath()
      cv.fill()
    y += ih
  putBitmap(l.win, cv.toBitmap, 0, 0)

proc drawMenu() =
  for i in 0 ..< levels.len: drawLevel(i)

proc levelAt(rx, ry: int): int =
  ## The menu under a point of the screen (the one shown last first), -1 none.
  for i in countdown(levels.high, 0):
    let l = levels[i]
    if rx >= l.x and rx < l.x + l.w and ry >= l.y and ry < l.y + l.h: return i
  -1

proc itemAt(i: int; rx, ry: int): int =
  ## The item of menu `i` at a point of the screen (-1: none, or a line).
  if i < 0 or i >= levels.len: return -1
  let l = levels[i]
  var yy = l.y + 3
  for k, it in l.items:
    let h = itemHeight(l, it)
    if ry >= yy and ry < yy + h and rx >= l.x and rx < l.x + l.w:
      return (if it.label.len == 0: -1 else: k)
    yy += h
  -1

proc itemTop(i, k: int): int =
  ## Where item `k` of menu `i` starts on the screen.
  let l = levels[i]
  result = l.y + 3
  for j in 0 ..< k: result += itemHeight(l, l.items[j])

proc menuItem*(label, keys: string; enabled: bool; action: proc (); icon: Bitmap = nil;
               sub: proc (): seq[MenuItem] = nil): MenuItem =
  ## An item for `showMenu` (`icon`: its picture at the left; `sub`: the
  ## items of the menu it opens beside it, made when it opens).
  MenuItem(label: label, keys: keys, enabled: enabled, action: action, icon: icon, sub: sub)

proc menuLine*(): MenuItem =
  ## A line between groups of items.
  MenuItem()

proc openLevel(items: seq[MenuItem]; x, y: int; above, toLeft, big: bool;
               beside: tuple[x, w: int] = (-1, 0)) =
  ## A menu shown: at `x`, `y` (`above`: its bottom at `y`; `toLeft`: its
  ## right edge at `x`); `beside`: the menu it opens from, which it goes
  ## beside, on the other side when there is no room.
  if items.len == 0: return
  var l = MenuLevel(items: items, hot: -1, opened: -1)
  # (in the interface's language: a label translated loses its "&")
  for it in l.items.mitems:
    if it.label.len > 0:
      let bare = it.label.replace("&&", "\1").replace("&", "").replace("\1", "&")
      let t = tr(bare)
      if t != bare: it.label = t
  let normalH = max(16, dpx(if bigFrames: 32 else: 22))
  if big:
    l.iconSize = menuBigIconSize()
    l.itemH = l.iconSize + dpx(if bigFrames: 10 else: 8)
    l.band = dpx(if bigFrames: 28 else: 21)
  else:
    l.iconSize = menuIconSize()
    l.itemH = normalH
  l.iconW = 0
  for it in l.items:
    if it.icon != nil: l.iconW = l.iconSize
  # (as wide as its widest label and keys)
  let probe = newCanvas2D(4, 4)
  let px = max(9, int(round(float(normalH) * 0.5)))
  probe.font = $px & "px sans-serif"
  var lw, kw = 0.0
  var anySub = false
  for it in l.items:
    lw = max(lw, probe.measureText(it.label.replace("&", "")).width)
    kw = max(kw, probe.measureText(it.keys).width)
    if it.sub != nil: anySub = true
  l.w = max(dpx(if big: 180 else: 140),
            int(lw + kw) + dpx(14 + 24 + 10) + l.iconW + l.band + (if anySub: dpx(16) else: 0))
  l.h = 6
  for it in l.items: l.h += itemHeight(l, it)
  let (sw, sh) = screenSize()
  if beside.x >= 0:
    # (beside the menu it comes from: after it, else before it)
    let after = if ui.rtl: beside.x - l.w + dpx(3) else: beside.x + beside.w - dpx(3)
    let before = if ui.rtl: beside.x + beside.w - dpx(3) else: beside.x - l.w + dpx(3)
    l.x = if after >= 0 and after + l.w <= sw: after else: before
  else:
    l.x = if toLeft: x - l.w else: x
  l.x = clamp(l.x, 0, max(0, sw - l.w))
  l.y = clamp((if above: y - l.h else: y), 0, max(0, sh - l.h))
  l.win = XCreateSimpleWindow(dpy, root, cint(l.x), cint(l.y), cuint(l.w), cuint(l.h), 0, 0,
                              xcolor(ui.theme.window))
  # (override-redirect: a menu is not a window to manage)
  var attrs: XSetWindowAttributes
  attrs.overrideRedirect = 1
  discard XChangeWindowAttributes(dpy, l.win, CWOverrideRedirect, addr attrs)
  discard XSelectInput(dpy, l.win, ExposureMask or ButtonPressMask or ButtonReleaseMask or
                       PointerMotionMask or KeyPressMask)
  discard XMapWindow(dpy, l.win)
  discard XRaiseWindow(dpy, l.win)
  levels.add l
  drawLevel(levels.high)

proc showMenu*(items: seq[MenuItem]; x, y: int; above = false; big = false; toLeft = false) =
  ## A menu at `x`, `y` on the screen (the screen's pixels; `above`: its
  ## bottom at `y`; `toLeft`: its right edge at `x`), over every window:
  ## the pointer and the keyboard its own until an item is chosen (a click,
  ## a letter, Enter) or it is left (a click outside, Esc). `big`: the
  ## Start menu's large pictures and band.
  let keepClient = menuClient
  let keepClosed = menuClosed
  menuClosed = nil
  closeMenu()
  menuClosed = keepClosed
  menuClient = keepClient
  if items.len == 0: return
  menuBig = big
  # (the button that opened it, let go where it was pressed, leaves it open;
  # moved onto an item first, the item is chosen -- 3.1's press, drag, let go)
  menuFrom = (x, y)
  menuArmed = false
  openLevel(items, x, y, above, toLeft, big)
  if levels.len == 0: return
  discard XGrabPointer(dpy, levels[0].win, 1, cuint(ButtonPressMask or ButtonReleaseMask or PointerMotionMask),
                       GrabModeAsync, GrabModeAsync, None, 0, CurrentTime)
  discard XGrabKeyboard(dpy, levels[0].win, 0, GrabModeAsync, GrabModeAsync, CurrentTime)

proc openSub(i: int; focusFirst = false) =
  ## The menu of the hot item of menu `i` opened beside it (the ones after
  ## it closed first).
  if i < 0 or i >= levels.len: return
  let k = levels[i].hot
  if levels.len > i + 1:
    if levels[i].opened == k and k >= 0: return
    closeLevels(i + 1)
  if k < 0 or k >= levels[i].items.len: return
  let it = levels[i].items[k]
  if it.sub == nil or not it.enabled: return
  let items = it.sub()
  if items.len == 0: return
  levels[i].opened = k
  drawLevel(i)
  openLevel(items, 0, itemTop(i, k) - 3, false, false, false, (levels[i].x, levels[i].w))
  if focusFirst and levels.len > i + 1:
    for j, x in levels[^1].items:
      if x.label.len > 0 and x.enabled:
        levels[^1].hot = j
        break
    drawLevel(levels.high)

proc choose(i, k: int) =
  ## Item `k` of menu `i` chosen: its menu opened, or what it does done.
  if i < 0 or i >= levels.len or k < 0 or k >= levels[i].items.len: return
  let it = levels[i].items[k]
  if not it.enabled: return
  if it.sub != nil:
    levels[i].hot = k
    openSub(i, focusFirst = false)
    return
  let act = it.action
  closeMenu()
  if act != nil: act()

proc menuTick*(): int =
  ## The pointer resting on an item: its menu opens (or the one beside
  ## closes) when the moment came. The milliseconds until the next look
  ## (0: nothing waiting).
  if menuDueLevel < 0 or levels.len == 0: return 0
  let now = epochTime()
  if now < menuDue: return max(1, int((menuDue - now) * 1000))
  let i = menuDueLevel
  menuDueLevel = -1
  if i < levels.len:
    if levels.len > i + 1 and levels[i].opened != levels[i].hot: closeLevels(i + 1)
    openSub(i)
    drawLevel(i)
  0

proc menuMotion(rx, ry: int) =
  if not menuArmed and (abs(rx - menuFrom.x) > dpx(6) or abs(ry - menuFrom.y) > dpx(6)):
    menuArmed = true
  let i = levelAt(rx, ry)
  if i < 0: return
  let k = itemAt(i, rx, ry)
  if k == levels[i].hot: return
  levels[i].hot = k
  drawLevel(i)
  if i > 0 and levels[i - 1].opened >= 0 and levels[i - 1].hot != levels[i - 1].opened:
    # (back in the menu that was open: its item lit again, nothing to close)
    levels[i - 1].hot = levels[i - 1].opened
    drawLevel(i - 1)
  # (a moment later: the menu of the item rested on, or none)
  let opens = k >= 0 and levels[i].items[k].sub != nil
  if opens or levels.len > i + 1:
    menuDue = epochTime() + 0.35
    menuDueLevel = i
    wakeIn(360)
  else:
    menuDueLevel = -1

proc menuPress(rx, ry: int): bool =
  ## A press while the menus are shown: true when it was theirs.
  menuArmed = true
  let i = levelAt(rx, ry)
  if i >= 0:
    let k = itemAt(i, rx, ry)
    if k >= 0 and levels[i].items[k].sub != nil:
      levels[i].hot = k
      openSub(i)
    return true
  if menuButton.w > 0 and rx >= menuButton.x and rx < menuButton.x + menuButton.w and
     ry >= menuButton.y and ry < menuButton.y + menuButton.h:
    menuClosedAt = epochTime()
  closeMenu()
  true

proc menuRelease(rx, ry: int) =
  let i = levelAt(rx, ry)
  if i < 0: return
  let k = itemAt(i, rx, ry)
  if menuArmed and k >= 0: choose(i, k)

proc menuKey(e: XKeyEvent) =
  ## Up and Down through the items of the menu shown last, Right into the
  ## menu of an item, Left out of it, Enter chooses, Esc closes one.
  if levels.len == 0: return
  let code = e.keycode
  template isKey(sym: culong): bool = code == cuint(XKeysymToKeycode(dpy, sym))
  let i = levels.high
  var step = 0
  if isKey(XK_Escape):
    if levels.len > 1:
      closeLevels(i)
      drawLevel(levels.high)
    else: closeMenu()
    return
  elif isKey(XK_Down): step = 1
  elif isKey(XK_Up): step = -1
  elif isKey(if ui.rtl: XK_Left else: XK_Right):
    let k = levels[i].hot
    if k >= 0 and levels[i].items[k].sub != nil: openSub(i, focusFirst = true)
    return
  elif isKey(if ui.rtl: XK_Right else: XK_Left):
    if levels.len > 1:
      closeLevels(i)
      drawLevel(levels.high)
    return
  elif isKey(XK_Return) or isKey(culong(0xff8d)):
    let k = levels[i].hot
    if k >= 0:
      if levels[i].items[k].sub != nil: openSub(i, focusFirst = true)
      else: choose(i, k)
    return
  if step == 0:
    # (the underlined letter of an item chooses it; without one, its first)
    var ek = e
    let sym = XLookupKeysym(addr ek, 0)
    if sym >= culong('a') and sym <= culong('z'):
      let ch = char(sym)
      var found = -1
      for k, it in levels[i].items:
        let amp = it.label.find('&')
        if it.enabled and amp >= 0 and amp + 1 < it.label.len and it.label[amp + 1].toLowerAscii == ch:
          found = k
          break
      if found < 0:
        for k, it in levels[i].items:
          if it.enabled and it.label.len > 0 and it.label.replace("&", "")[0].toLowerAscii == ch:
            found = k
            break
      if found >= 0:
        levels[i].hot = found
        drawLevel(i)
        if levels[i].items[found].sub != nil: openSub(i, focusFirst = true)
        else: choose(i, found)
    return
  let n = levels[i].items.len
  var k = levels[i].hot
  if k < 0: k = (if step > 0: -1 else: 0)   # (none yet: Down the first, Up the last)
  for _ in 0 ..< n:
    k = (k + step + n) mod n
    if levels[i].items[k].label.len > 0 and levels[i].items[k].enabled: break
  levels[i].hot = k
  drawLevel(i)

proc openMenu*(c: Client; x, y: int) =
  ## The control menu of `c` (Restore, Minimize, Maximize, Close, Switch
  ## To...) at `x`, `y` on the screen.
  if c == nil: return
  let isDialog = c.transient != None or c.splash
  # (the window may be gone by the time an item is chosen)
  template its(body: untyped): proc () =
    proc () =
      if menuClient != nil and menuClient in clients: body
  showMenu(@[
    menuItem("&Restore", "", c.maximized or c.iconic or c.zoned, its(restore(menuClient))),
    menuItem("Mi&nimize", "", not isDialog and not c.iconic, its(minimize(menuClient))),
    menuItem("Ma&ximize", "", not isDialog and not c.maximized, its(maximize(menuClient))),
    menuLine(),
    menuItem("&Close", "Alt+F4", true, its(close(menuClient))),
    menuLine(),
    menuItem("S&witch To...", "Ctrl+Shift+Esc", true, proc () = (if taskList != nil: taskList()))], x, y)
  menuClient = c

# ---- snapping to parts of the screen, as Windows 11 ----------------------------------------------
#
# A window dragged by its title to an edge of the work area goes on that
# half, to a corner on that quarter, to the top maximized: a frame shows
# where while it is held there. Dragged away again, a snapped or maximized
# window takes back its size from before, under the pointer as it was held.
# The pointer resting on the maximize button (or Win+Z) shows the layouts:
# halves, two thirds and one, thirds, a half and two quarters, quarters;
# a part clicked puts the window there. Then the other windows are offered
# for the parts left (Snap Assist). Win+Left, Right, Up, Down go from part
# to part. A screen taller than wide has the layouts the other way round.

const
  zLeft*: Zone = (0.0, 0.0, 0.5, 1.0)
  zRight*: Zone = (0.5, 0.0, 1.0, 1.0)
  zTopLeft*: Zone = (0.0, 0.0, 0.5, 0.5)
  zTopRight*: Zone = (0.5, 0.0, 1.0, 0.5)
  zBottomLeft*: Zone = (0.0, 0.5, 0.5, 1.0)
  zBottomRight*: Zone = (0.5, 0.5, 1.0, 1.0)
  zWhole: Zone = (0.0, 0.0, 1.0, 1.0)

proc layouts(): seq[seq[Zone]] =
  ## The layouts the maximize button offers (a screen taller than wide:
  ## turned, the parts one above another).
  result = @[@[zLeft, zRight],
             @[(0.0, 0.0, 2/3, 1.0), (2/3, 0.0, 1.0, 1.0)],
             @[(0.0, 0.0, 1/3, 1.0), (1/3, 0.0, 2/3, 1.0), (2/3, 0.0, 1.0, 1.0)],
             @[zLeft, zTopRight, zBottomRight],
             @[zTopLeft, zTopRight, zBottomLeft, zBottomRight]]
  let r = workRect()
  if r.h > r.w:
    for l in result.mitems:
      for z in l.mitems: z = (z.y0, z.x0, z.y1, z.x1)

proc toZone*(c: Client; z: Zone) =
  ## `c` snapped to zone `z` of the work area (its size before kept, for
  ## when it leaves it).
  if c == nil or c.splash or c.transient != None or c.fullscreen: return
  if c.iconic: restore(c)
  if not c.zoned and not c.maximized: c.saved = (c.x, c.y, c.w, c.h)
  if c.maximized:
    c.maximized = false
    setNetState(c)
  c.zoned = true
  c.zone = z
  zoneGeometry(c, z)
  applyGeometry(c)
  focus(c)
  drawFrame(c)
  changedNow()

proc workChanged*() =
  ## The work area changed (the panel moved, grew, hid): maximized and
  ## snapped windows fill their part of it again, the others stay in it.
  for c in snapshot():
    if c.fullscreen: applyGeometry(c)
    elif c.maximized: (maximizeGeometry(c); applyGeometry(c))
    elif c.zoned: (zoneGeometry(c, c.zone); applyGeometry(c))
    else:
      fitOnScreen(c)
      applyGeometry(c)
    drawFrame(c)
  let r = workRect()
  setLongs(dpy, root, atom(dpy, "_NET_WORKAREA"), XA_CARDINAL,
           [clong(r.x), clong(r.y), clong(r.w), clong(r.h)])

# -- where a dragged window would go, shown --

var previewWins: array[4, Window]

proc showPreview(r: tuple[x, y, w, h: int]) =
  ## A frame in the selection's color round where a window would snap.
  let t = max(2, dpx(4))
  let parts = [(r.x, r.y, r.w, t), (r.x, r.y + r.h - t, r.w, t),
               (r.x, r.y, t, r.h), (r.x + r.w - t, r.y, t, r.h)]
  for i, (x, y, w, h) in parts:
    if previewWins[i] == None:
      previewWins[i] = XCreateSimpleWindow(dpy, root, cint(x), cint(y), cuint(max(1, w)), cuint(max(1, h)),
                                           0, 0, xcolor(ui.theme.select))
      var attrs: XSetWindowAttributes
      attrs.overrideRedirect = 1
      discard XChangeWindowAttributes(dpy, previewWins[i], CWOverrideRedirect, addr attrs)
      discard XMapWindow(dpy, previewWins[i])
    else:
      discard XMoveResizeWindow(dpy, previewWins[i], cint(x), cint(y), cuint(max(1, w)), cuint(max(1, h)))
    discard XRaiseWindow(dpy, previewWins[i])

proc hidePreview() =
  for w in previewWins.mitems:
    if w != None:
      discard XDestroyWindow(dpy, w)
      w = None

type SnapAim = tuple[on, whole: bool; z: Zone]

var aim: SnapAim                 # where the window dragged now would snap

proc aimAt(rx, ry: int): SnapAim =
  ## Where a window held at this point of the screen would snap.
  let r = workRect()
  let edge = dpx(if bigFrames: 14 else: 6)
  let corner = dpx(if bigFrames: 80 else: 56)
  let atL = rx <= r.x + edge
  let atR = rx >= r.x + r.w - 1 - edge
  let atT = ry <= r.y + edge
  let atB = ry >= r.y + r.h - 1 - edge
  if atL or atR:
    let z = if ry <= r.y + corner: (if atL: zTopLeft else: zTopRight)
            elif ry >= r.y + r.h - corner: (if atL: zBottomLeft else: zBottomRight)
            else: (if atL: zLeft else: zRight)
    return (true, false, z)
  if atT:
    if rx <= r.x + corner: return (true, false, zTopLeft)
    if rx >= r.x + r.w - corner: return (true, false, zTopRight)
    return (true, true, zWhole)
  if atB:
    if rx <= r.x + corner: return (true, false, zBottomLeft)
    if rx >= r.x + r.w - corner: return (true, false, zBottomRight)
  (false, false, zWhole)

# -- Snap Assist: the other windows offered for the parts left --

var
  assistWin: Window
  assistZone: Zone
  assistNext: seq[Zone]          ## the parts after this one
  assistList: seq[Client]
  assistTiles: seq[tuple[x, y, w, h: int]]    ## where each is in the box
  assistHot = -1
  assistRect: tuple[x, y, w, h: int]

proc closeAssist*() =
  if assistWin != None:
    discard XUngrabPointer(dpy, CurrentTime)
    discard XUngrabKeyboard(dpy, CurrentTime)
    discard XDestroyWindow(dpy, assistWin)
    assistWin = None
  assistList = @[]
  assistNext = @[]

proc drawAssist() =
  if assistWin == None: return
  let (w, h) = (assistRect.w, assistRect.h)
  let t = ui.theme
  let cv = newCanvas2D(w, h)
  cv.fillStyle = t.frame
  cv.fillRect(0, 0, float(w), float(h))
  cv.fillStyle = t.face
  cv.fillRect(1, 1, float(w - 2), float(h - 2))
  let px = max(9, dpx(12))
  cv.textBaseline = "middle"
  cv.font = "bold " & $px & "px sans-serif"
  cv.fillStyle = t.text
  cv.textAlign = "center"
  cv.fillText(tr("Choose the window for this part"), float(w) / 2, float(dpx(20)))
  cv.font = $px & "px sans-serif"
  let isz = dpx(32)
  for i, c in assistList:
    if i >= assistTiles.len: break
    let r = assistTiles[i]
    let hot = i == assistHot
    cv.fillStyle = t.frame
    cv.fillRect(float(r.x), float(r.y), float(r.w), float(r.h))
    cv.fillStyle = (if hot: t.select else: t.window)
    cv.fillRect(float(r.x + 1), float(r.y + 1), float(r.w - 2), float(r.h - 2))
    let ic = c.readIcon(isz)
    if ic != nil:
      cv.drawImage(ic, float(r.x + dpx(8)), float(r.y + (r.h - isz) div 2), float(isz), float(isz))
    var title = tr(c.title)
    let room = float(r.w - isz - dpx(24))
    while title.len > 3 and cv.measureText(title).width > room:
      title = title[0 ..< title.len - 4] & "..."
      while title.len > 3 and (ord(title[^4]) and 0xC0) == 0x80: title = title[0 ..< title.len - 4] & "..."
    cv.fillStyle = (if hot: t.selectText else: t.text)
    cv.textAlign = "left"
    cv.fillText(title, float(r.x + isz + dpx(16)), float(r.y + r.h div 2))
  putBitmap(assistWin, cv.toBitmap, 0, 0)

proc openAssist(zones: seq[Zone]; taken: seq[Client]) =
  ## The windows not snapped yet, offered for `zones[0]` (then the next).
  closeAssist()
  if zones.len == 0: return
  var list: seq[Client]
  for i in countdown(clients.high, 0):
    let c = clients[i]
    if c in taken or c.transient != None or c.splash or c.dialog or c.fullscreen: continue
    list.add c
  if list.len == 0: return
  assistZone = zones[0]
  assistNext = zones[1 .. ^1]
  assistList = list
  assistRect = zoneRect(zones[0])
  let (w, h) = (assistRect.w, assistRect.h)
  # (the windows as tiles, as many as there is room for)
  let tw = min(w - dpx(24), dpx(260))
  let th = dpx(48)
  let cols = max(1, (w - dpx(16)) div (tw + dpx(8)))
  let rows = max(1, (h - dpx(48)) div (th + dpx(8)))
  if assistList.len > cols * rows: assistList.setLen(cols * rows)
  let usedW = cols * (tw + dpx(8)) - dpx(8)
  assistTiles = @[]
  for i in 0 ..< assistList.len:
    assistTiles.add ((w - usedW) div 2 + (i mod cols) * (tw + dpx(8)), dpx(40) + (i div cols) * (th + dpx(8)), tw, th)
  assistHot = 0
  assistWin = XCreateSimpleWindow(dpy, root, cint(assistRect.x), cint(assistRect.y), cuint(max(1, w)),
                                  cuint(max(1, h)), 0, 0, xcolor(ui.theme.face))
  var attrs: XSetWindowAttributes
  attrs.overrideRedirect = 1
  discard XChangeWindowAttributes(dpy, assistWin, CWOverrideRedirect, addr attrs)
  discard XSelectInput(dpy, assistWin, ExposureMask or ButtonPressMask or ButtonReleaseMask or
                       PointerMotionMask or KeyPressMask)
  discard XMapWindow(dpy, assistWin)
  discard XRaiseWindow(dpy, assistWin)
  discard XGrabPointer(dpy, assistWin, 1, cuint(ButtonPressMask or ButtonReleaseMask or PointerMotionMask),
                       GrabModeAsync, GrabModeAsync, None, 0, CurrentTime)
  discard XGrabKeyboard(dpy, assistWin, 0, GrabModeAsync, GrabModeAsync, CurrentTime)
  drawAssist()

proc assistAt(rx, ry: int): int =
  for i, r in assistTiles:
    let x = rx - assistRect.x
    let y = ry - assistRect.y
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h: return i
  -1

proc assistChoose(i: int) =
  if i < 0 or i >= assistList.len: return
  let c = assistList[i]
  let z = assistZone
  let rest = assistNext
  var taken: seq[Client]
  for o in clients:
    if o.zoned: taken.add o
  closeAssist()
  if c in clients:
    toZone(c, z)
    taken.add c
    openAssist(rest, taken)

# -- the layouts, on the maximize button --

var
  flyWin: Window
  flyClient: Client
  flyKeys = false                ## opened by Win+Z: the keys and the pointer its own
  flyZones: seq[tuple[layout, part: int; x, y, w, h: int]]
  flyHot = -1
  flyRect: tuple[x, y, w, h: int]
  flyFrom: tuple[x, y, w, h: int]   ## the maximize button it came from
  flyLeft = 0.0                  ## when the pointer left it and its button
  hoverMax: tuple[c: Client; since: float]

proc closeFly*() =
  if flyWin != None:
    if flyKeys:
      discard XUngrabPointer(dpy, CurrentTime)
      discard XUngrabKeyboard(dpy, CurrentTime)
    discard XDestroyWindow(dpy, flyWin)
    flyWin = None
  flyClient = nil
  flyLeft = 0

proc drawFly() =
  if flyWin == None: return
  let (w, h) = (flyRect.w, flyRect.h)
  let t = ui.theme
  let cv = newCanvas2D(w, h)
  cv.fillStyle = t.frame
  cv.fillRect(0, 0, float(w), float(h))
  cv.fillStyle = t.face
  cv.fillRect(1, 1, float(w - 2), float(h - 2))
  cv.fillStyle = t.light
  cv.fillRect(1, 1, float(w - 2), 1)
  cv.fillRect(1, 1, 1, float(h - 2))
  cv.fillStyle = t.shadow
  cv.fillRect(1, float(h - 2), float(w - 2), 1)
  cv.fillRect(float(w - 2), 1, 1, float(h - 2))
  for i, z in flyZones:
    cv.fillStyle = t.frame
    cv.fillRect(float(z.x), float(z.y), float(z.w), float(z.h))
    cv.fillStyle = (if i == flyHot: t.select else: t.window)
    cv.fillRect(float(z.x + 1), float(z.y + 1), float(z.w - 2), float(z.h - 2))
  putBitmap(flyWin, cv.toBitmap, 0, 0)

proc openFly*(c: Client; x, y: int; keys = false) =
  ## The layouts for `c`, their box's top middle at `x`, `y` on the screen.
  closeFly()
  if c == nil or c.splash or c.transient != None or c.fullscreen: return
  let ls = layouts()
  let r = workRect()
  let ratio = float(r.h) / float(max(1, r.w))
  let cw = dpx(if bigFrames: 104 else: 84)
  let ch = max(dpx(30), int(float(cw) * ratio))
  let gap = dpx(10)
  let per = 3
  let rowsN = (ls.len + per - 1) div per
  flyRect.w = per * cw + (per + 1) * gap
  flyRect.h = rowsN * ch + (rowsN + 1) * gap
  let (sw, sh) = screenSize()
  flyRect.x = clamp(x - flyRect.w div 2, 0, max(0, sw - flyRect.w))
  flyRect.y = clamp(y, 0, max(0, sh - flyRect.h))
  flyZones = @[]
  for li, l in ls:
    let cx = gap + (li mod per) * (cw + gap)
    let cy = gap + (li div per) * (ch + gap)
    let g = max(2, dpx(2))
    for pi, z in l:
      let x0 = cx + int(z.x0 * float(cw))
      let x1 = cx + int(z.x1 * float(cw))
      let y0 = cy + int(z.y0 * float(ch))
      let y1 = cy + int(z.y1 * float(ch))
      flyZones.add (li, pi, x0 + (if z.x0 > 0: g div 2 else: 0), y0 + (if z.y0 > 0: g div 2 else: 0),
                    x1 - x0 - (if z.x0 > 0: g div 2 else: 0) - (if z.x1 < 1: g div 2 else: 0),
                    y1 - y0 - (if z.y0 > 0: g div 2 else: 0) - (if z.y1 < 1: g div 2 else: 0))
  flyClient = c
  flyKeys = keys
  flyHot = if keys: 0 else: -1
  flyWin = XCreateSimpleWindow(dpy, root, cint(flyRect.x), cint(flyRect.y), cuint(flyRect.w),
                               cuint(flyRect.h), 0, 0, xcolor(ui.theme.face))
  var attrs: XSetWindowAttributes
  attrs.overrideRedirect = 1
  discard XChangeWindowAttributes(dpy, flyWin, CWOverrideRedirect, addr attrs)
  discard XSelectInput(dpy, flyWin, ExposureMask or ButtonPressMask or ButtonReleaseMask or
                       PointerMotionMask or KeyPressMask or LeaveWindowMask)
  discard XMapWindow(dpy, flyWin)
  discard XRaiseWindow(dpy, flyWin)
  if keys:
    discard XGrabPointer(dpy, flyWin, 1, cuint(ButtonPressMask or ButtonReleaseMask or PointerMotionMask),
                         GrabModeAsync, GrabModeAsync, None, 0, CurrentTime)
    discard XGrabKeyboard(dpy, flyWin, 0, GrabModeAsync, GrabModeAsync, CurrentTime)
  drawFly()

proc flyAt(rx, ry: int): int =
  let x = rx - flyRect.x
  let y = ry - flyRect.y
  for i, z in flyZones:
    if x >= z.x and x < z.x + z.w and y >= z.y and y < z.y + z.h: return i
  -1

proc flyChoose(i: int) =
  ## A part of a layout chosen: the window there, the others offered for the rest.
  if i < 0 or i >= flyZones.len: return
  let c = flyClient
  let l = layouts()[flyZones[i].layout]
  let part = flyZones[i].part
  closeFly()
  if c == nil or c notin clients: return
  toZone(c, l[part])
  var rest: seq[Zone]
  for k, z in l:
    if k != part: rest.add z
  openAssist(rest, @[c])

proc maxButtonRect(c: Client): tuple[x, y, w, h: int] =
  let th = tbh()
  (c.x + c.frameW - bw() - th, c.y + bw(), th, th)

proc snapTick*(): int =
  ## The pointer resting on a maximize button: its layouts shown; a box
  ## shown by it and left: closed. The milliseconds until the next look.
  let now = epochTime()
  if flyWin != None and not flyKeys:
    var r, child: Window
    var rx, ry, wx, wy: cint
    var mask: cuint
    discard XQueryPointer(dpy, root, addr r, addr child, addr rx, addr ry, addr wx, addr wy, addr mask)
    let inFly = rx >= flyRect.x and rx < flyRect.x + flyRect.w and ry >= flyRect.y - dpx(4) and
                ry < flyRect.y + flyRect.h
    let b = flyFrom
    let inBtn = rx >= b.x and rx < b.x + b.w and ry >= b.y and ry < b.y + b.h
    if inFly or inBtn:
      flyLeft = 0
    elif flyLeft == 0: flyLeft = now
    elif now - flyLeft > 0.4:
      closeFly()
      return 0
    return 150
  if hoverMax.c != nil and flyWin == None:
    let c = hoverMax.c
    if c notin clients or drag.kind != dkNone or menuOpen():
      hoverMax.c = nil
      return 0
    if now - hoverMax.since >= 0.6:
      hoverMax.c = nil
      let b = maxButtonRect(c)
      flyFrom = b
      openFly(c, b.x + b.w div 2, b.y + b.h)
      return 150
    return max(1, int((hoverMax.since + 0.6 - now) * 1000))
  0

proc flyKey(e: XKeyEvent) =
  ## Win+Z's box: the arrows go from part to part, Enter puts the window
  ## there, Esc closes it.
  var ek = e
  let sym = XLookupKeysym(addr ek, 0)
  if sym == XK_Escape:
    closeFly()
  elif sym == XK_Return:
    flyChoose(flyHot)
  elif sym in [XK_Right, XK_Down, XK_Tab]:
    flyHot = (flyHot + 1) mod max(1, flyZones.len)
    drawFly()
  elif sym in [XK_Left, XK_Up]:
    flyHot = (flyHot - 1 + flyZones.len) mod max(1, flyZones.len)
    drawFly()

proc assistKey(e: XKeyEvent) =
  var ek = e
  let sym = XLookupKeysym(addr ek, 0)
  if sym == XK_Escape: closeAssist()
  elif sym == XK_Return: assistChoose(assistHot)
  elif sym in [XK_Right, XK_Down, XK_Tab]:
    assistHot = (assistHot + 1) mod max(1, assistList.len)
    drawAssist()
  elif sym in [XK_Left, XK_Up]:
    assistHot = (assistHot - 1 + assistList.len) mod max(1, assistList.len)
    drawAssist()

proc winArrow*(c: Client; dir: char) =
  ## Win+Left, Right, Up, Down: from part to part of the screen (Up from a
  ## half to its top quarter, Down to its bottom one; Left from the right
  ## half back to the window's own size; Up maximizes, Down restores, then
  ## minimizes).
  if c == nil or c.splash or c.transient != None or c.fullscreen: return
  let z = c.zone
  let zoned = c.zoned
  case dir
  of 'L':
    if zoned and z == zRight: restore(c)
    elif zoned and z == zTopRight: toZone(c, zTopLeft)
    elif zoned and z == zBottomRight: toZone(c, zBottomLeft)
    else: toZone(c, zLeft)
  of 'R':
    if zoned and z == zLeft: restore(c)
    elif zoned and z == zTopLeft: toZone(c, zTopRight)
    elif zoned and z == zBottomLeft: toZone(c, zBottomRight)
    else: toZone(c, zRight)
  of 'U':
    if zoned and z == zLeft: toZone(c, zTopLeft)
    elif zoned and z == zRight: toZone(c, zTopRight)
    elif zoned and z == zBottomLeft: toZone(c, zLeft)
    elif zoned and z == zBottomRight: toZone(c, zRight)
    elif not c.maximized: maximize(c)
  of 'D':
    if c.maximized: restore(c)
    elif zoned and z == zLeft: toZone(c, zBottomLeft)
    elif zoned and z == zRight: toZone(c, zBottomRight)
    elif zoned and z == zTopLeft: toZone(c, zLeft)
    elif zoned and z == zTopRight: toZone(c, zRight)
    elif zoned: restore(c)
    else: minimize(c)
  else: discard

proc tick*(): int =
  ## The manager's moments: a menu to open, the layouts to show or close.
  ## The milliseconds until it wants to look again (0: nothing waiting).
  let a = menuTick()
  let b = snapTick()
  if a > 0 and b > 0: min(a, b) else: max(a, b)

# ---- managing a window ------------------------------------------------------------------------------

proc manage(w: Window; adopt: bool) =
  if w == desk or w == checkWin or isMenuWin(w) or w in onTop or findClient(w) != nil: return
  var a: XWindowAttributes
  if XGetWindowAttributes(dpy, w, addr a) == 0: return
  if a.overrideRedirect != 0: return
  if adopt and a.mapState != IsViewable: return
  let types = propLongs(dpy, w, aNetType, XA_ATOM)
  if clong(aTypeDesktop) in types or clong(aTypeDock) in types:
    discard XMapWindow(dpy, w)         # (a panel or another desktop: as it is)
    return
  let c = Client(win: w, w: max(1, int(a.width)), h: max(1, int(a.height)))
  readTitle(c)
  readClass(c)
  readProtocols(c)
  readHints(c)
  if clong(aTypeSplash) in types:
    c.fixed = true
    c.splash = true
  c.dialog = clong(aTypeDialog) in types
  c.w = max(c.w, 1)
  place(c, int(a.x), int(a.y), adopt)
  # (a program the desktop opened again: its window where it was)
  var again = -1
  if not adopt and c.class.len > 0 and c.transient == None:
    let now = epochTime()
    # (the desktop's own programs share one class: theirs by the title too)
    for i, p in pending:
      if p.class == c.class and p.until > now and p.title == c.title:
        again = i
        break
    if again < 0 and c.class != "Retro-desktop":
      for i, p in pending:
        if p.class == c.class and p.until > now:
          again = i
          break
  var wasMax, wasIcon = false
  if again >= 0:
    let p = pending[again]
    pending.delete(again)
    # (a size kept from a window caught half made -- a few pixels -- is not
    # one to give it again)
    if not c.splash and p.w >= dpx(120) and p.h >= dpx(60):
      c.w = max(c.minW, p.w)
      c.h = max(c.minH, p.h)
    c.x = p.x
    c.y = p.y
    fitOnScreen(c)
    wasMax = p.maximized
    wasIcon = p.iconic
  c.frame = XCreateSimpleWindow(dpy, root, cint(c.x), cint(c.y), cuint(c.frameW), cuint(c.frameH),
                                0, 0, xcolor(ui.theme.face))
  discard XSelectInput(dpy, c.frame, SubstructureRedirectMask or SubstructureNotifyMask or
                       ButtonPressMask or ButtonReleaseMask or PointerMotionMask or ExposureMask or
                       LeaveWindowMask)
  discard XSelectInput(dpy, w, PropertyChangeMask or StructureNotifyMask)
  discard XAddToSaveSet(dpy, w)
  discard XSetWindowBorderWidth(dpy, w, 0)
  discard XReparentWindow(dpy, w, c.frame, cint(bw()), cint(topOf()))
  discard XResizeWindow(dpy, w, cuint(c.w), cuint(c.h))
  discard XGrabButton(dpy, AnyButton, AnyModifier, w, 0, cuint(ButtonPressMask),
                      GrabModeSync, GrabModeAsync, None, 0)
  clients.add c
  discard XMapWindow(dpy, w)
  discard XMapWindow(dpy, c.frame)
  setWmState(c, 1)
  applyGeometry(c)
  let st = propLongs(dpy, w, aNetState, XA_ATOM)
  if clong(aNetFullscreen) in st: setFullscreen(c, true)
  elif again >= 0:
    if wasMax and c.hasButtons:
      focus(c)
      maximize(c)
  elif (maximizeNew and c.hasButtons and not adopt) or
       (clong(aNetMaxH) in st and clong(aNetMaxV) in st and c.hasButtons):
    focus(c)
    maximize(c)
  focus(c)
  if wasIcon and c.hasButtons: minimize(c)
  if not adopt and c.transient == None and not c.dialog and not c.splash: playSound("open")
  updateClientList()
  changedNow()

proc unmanage(c: Client; destroyed: bool) =
  resume(c)
  if c.transient == None and not c.dialog: playSound("close")
  if not destroyed:
    let (x, y) = (c.x + bw(), c.y + topOf())
    discard XUngrabButton(dpy, AnyButton, AnyModifier, c.win)
    discard XReparentWindow(dpy, c.win, root, cint(x), cint(y))
    discard XRemoveFromSaveSet(dpy, c.win)
    setWmState(c, 0)
  discard XDestroyWindow(dpy, c.frame)
  shownCursor.del(c.frame)
  for i in countdown(desktopShown.high, 0):
    if desktopShown[i] == c: desktopShown.delete(i)
  var rest: seq[Client]
  for x in clients:
    if x != c: rest.add x
  clients = rest
  if menuClient == c: closeMenu()
  if flyClient == c: closeFly()
  if hoverMax.c == c: hoverMax.c = nil
  if c in assistList: closeAssist()
  if drag.c == c:
    drag.kind = dkNone
    discard XUngrabPointer(dpy, CurrentTime)
  if active == c:
    active = nil
    focusTop()
  updateClientList()
  changedNow()

# ---- the pointer on a frame -------------------------------------------------------------------------

proc partAt(c: Client; x, y: int): Part =
  let b = bw()
  let th = tbh()
  let fw = c.frameW
  let fh = c.frameH
  if x < 0 or y < 0 or x >= fw or y >= fh: return pNone
  # (the top few pixels of the title bar size the window too: a thin
  # border is hard to catch, with a finger above all)
  let band = dpx(if bigFrames: 6 else: 3)
  if not c.splash and not c.maximized and y < b + band and y >= b:
    let cz = b + th
    if x < cz: return pNW
    if x >= fw - cz: return pNE
    return pN
  if y >= b and y < b + th and x >= b and x < fw - b:
    let tx = x - b
    if tx < th: return pMenu
    if c.hasButtons:
      if tx >= fw - 2 * b - th: return pMax
      if tx >= fw - 2 * b - 2 * th: return pMin
    return pTitle
  if c.splash or c.maximized:
    return (if y < b + th: pTitle else: pClient)
  let cz = b + th
  let left = x < b
  let right = x >= fw - b
  let top = y < b
  let bottom = y >= fh - b
  if left or right or top or bottom:
    if (top or left) and x < cz and y < cz: return pNW
    if (top or right) and x >= fw - cz and y < cz: return pNE
    if (bottom or left) and x < cz and y >= fh - cz: return pSW
    if (bottom or right) and x >= fw - cz and y >= fh - cz: return pSE
    if left: return pW
    if right: return pE
    if top: return pN
    return pS
  pClient

proc cursorScale*(): int = max(1, int(round(devScale())))

proc cursorFor(p: Part): culong =
  ## The classic cursors (as 3.1 had them), at the screen's scale: the
  ## arrow, the sizing arrows of the borders and corners.
  let kind = case p
             of pN, pS: curSizeNS
             of pW, pE: curSizeWE
             of pNW, pSE: curSizeNWSE
             of pNE, pSW: curSizeNESW
             else: curArrow
  culong(x11ClassicCursor(kind, cursorScale()))

proc pressFrame(c: Client; e: XButtonEvent) =
  let part = partAt(c, int(e.x), int(e.y))
  if c != active or clients.len == 0 or clients[^1] != c: focus(c)
  if e.button != 1:
    if e.button == 3 and part in {pTitle, pMenu}:
      openMenu(c, int(e.xRoot), int(e.yRoot))
    return
  let double = lastClick.c == c and lastClick.part == part and
               e.time >= lastClick.time and e.time - lastClick.time < 450
  lastClick = (c, part, e.time)
  pressTime = e.time
  moved = false
  case part
  of pMenu:
    if double:
      lastClick.c = nil
      closeMenu()
      close(c)
    else:
      openMenu(c, c.x + bw(), c.y + bw() + tbh())
  of pTitle:
    if double and c.hasButtons:
      lastClick.c = nil
      maximize(c)
    else:
      # (a maximized or snapped window comes off its place when dragged;
      # holding a finger on the title still opens its menu)
      drag = (dkMove, c, part, int(e.xRoot), int(e.yRoot), c.x, c.y, c.w, c.h)
      aim = (false, false, zWhole)
  of pMin, pMax:
    c.pressed = part
    drag = (dkButton, c, part, int(e.xRoot), int(e.yRoot), c.x, c.y, c.w, c.h)
    drawFrame(c)
  of pN, pS, pW, pE, pNW, pNE, pSW, pSE:
    drag = (dkResize, c, part, int(e.xRoot), int(e.yRoot), c.x, c.y, c.w, c.h)
  else: discard
  if drag.kind != dkNone:
    discard XGrabPointer(dpy, c.frame, 0, cuint(ButtonReleaseMask or PointerMotionMask),
                         GrabModeAsync, GrabModeAsync, None,
                         (if drag.kind == dkMove: fleur else: cursorFor(drag.part)), CurrentTime)

proc moveDrag(rx, ry: int) =
  let c = drag.c
  if c == nil: return
  let dx = rx - drag.rx
  let dy = ry - drag.ry
  if abs(dx) + abs(dy) > dpx(4): moved = true
  if not moved: return
  case drag.kind
  of dkMove:
    if c.fullscreen: return
    if c.maximized or c.zoned:
      # (dragged off its place: its size from before, under the pointer
      # where the title was held)
      let frac = float(drag.rx - drag.x) / float(max(1, drag.w + 2 * bw()))
      let grabY = drag.ry - drag.y
      c.maximized = false
      c.zoned = false
      c.w = c.saved.w
      c.h = c.saved.h
      c.x = rx - int(frac * float(c.frameW))
      c.y = ry - grabY
      setNetState(c)
      applyGeometry(c)
      drawFrame(c)
      drag.x = c.x
      drag.y = c.y
      drag.w = c.w
      drag.h = c.h
      drag.rx = rx
      drag.ry = ry
      changedNow()
      return
    let (sw, sh) = screenSize()
    let wr = workRect()
    let (sx, sy) = snapped(c, drag.x + dx, drag.y + dy)
    c.x = clamp(sx, -(c.frameW - dpx(40)), sw - dpx(40))
    c.y = clamp(sy, wr.y, max(wr.y, sh - topOf()))
    discard XMoveWindow(dpy, c.frame, cint(c.x), cint(c.y))
    # (at an edge, a corner, the top: where it would snap, shown)
    var a: SnapAim = (false, false, zWhole)
    if not c.splash and c.transient == None: a = aimAt(rx, ry)
    if a != aim:
      aim = a
      if a.on: showPreview(if a.whole: workRect() else: zoneRect(a.z))
      else: hidePreview()
  of dkResize:
    var x = drag.x
    var y = drag.y
    var w = drag.w
    var h = drag.h
    if drag.part in {pE, pNE, pSE}: w = drag.w + dx
    if drag.part in {pS, pSW, pSE}: h = drag.h + dy
    if drag.part in {pW, pNW, pSW}:
      w = drag.w - dx
      x = drag.x + dx
    if drag.part in {pN, pNW, pNE}:
      h = drag.h - dy
      y = drag.y + dy
    let nw = max(c.minW, w)
    let nh = max(c.minH, h)
    if drag.part in {pW, pNW, pSW}: x += w - nw
    if drag.part in {pN, pNW, pNE}: y += h - nh
    if nw != c.w or nh != c.h or x != c.x or y != c.y:
      c.zoned = false                    # (sized by hand: no longer snapped)
      c.x = x
      c.y = max(0, y)
      c.w = nw
      c.h = nh
      discard XMoveResizeWindow(dpy, c.frame, cint(c.x), cint(c.y), cuint(c.frameW), cuint(c.frameH))
      discard XResizeWindow(dpy, c.win, cuint(c.w), cuint(c.h))
      drawFrame(c)
  of dkButton:
    discard
  of dkNone: discard

proc endDrag(e: XButtonEvent) =
  let c = drag.c
  let kind = drag.kind
  drag.kind = dkNone
  discard XUngrabPointer(dpy, CurrentTime)
  if c == nil or c notin clients: return
  case kind
  of dkMove, dkResize:
    let a = aim
    aim = (false, false, zWhole)
    hidePreview()
    if not moved and kind == dkMove and e.time >= pressTime and e.time - pressTime >= 550:
      openMenu(c, int(e.xRoot), int(e.yRoot))       # (held: the control menu)
    elif moved and kind == dkMove and a.on:
      # (let go at an edge: snapped there, its size kept for when it leaves)
      c.saved = (drag.x, drag.y, drag.w, drag.h)
      if a.whole:
        maximize(c)
      else:
        toZone(c, a.z)
        # (a half: the other windows offered for the other half)
        if a.z == zLeft: openAssist(@[zRight], @[c])
        elif a.z == zRight: openAssist(@[zLeft], @[c])
    elif moved:
      applyGeometry(c)
      drawFrame(c)
  of dkButton:
    let part = drag.part
    c.pressed = pNone
    drawFrame(c)
    let over = partAt(c, int(e.xRoot) - c.x, int(e.yRoot) - c.y) == part
    if over:
      if part == pMin: minimize(c)
      elif part == pMax: maximize(c)
  of dkNone: discard

# ---- the events -------------------------------------------------------------------------------------

# ---- the keyboard's shortcuts ------------------------------------------------------------------------

var
  shortcuts: seq[tuple[action: string; mods: cuint; sym: culong]]
  superHeld = false              # the Windows key is down ...
  superUsed = false              # ... and another key went with it

proc keysOf*(s: string): tuple[mods: cuint; sym: culong] =
  ## "Ctrl+Alt+T", "Win+Left", "Win" -> the modifiers and the key (0 when it
  ## is not a key X knows).
  for part in s.split('+'):
    case part.strip.toLowerAscii
    of "ctrl", "control": result.mods = result.mods or ControlMask
    of "alt": result.mods = result.mods or Mod1Mask
    of "shift": result.mods = result.mods or ShiftMask
    of "win", "super", "meta": result.mods = result.mods or Mod4Mask
    of "": discard
    else:
      let name = case part.strip.toLowerAscii
                 of "esc": "Escape"
                 of "enter": "Return"
                 of "space": "space"
                 of "del": "Delete"
                 of "left", "right", "up", "down", "tab", "home", "end", "delete", "insert", "print":
                   part.strip[0 .. 0].toUpperAscii & part.strip[1 .. ^1].toLowerAscii
                 else:
                   if part.strip.len == 1: part.strip.toLowerAscii else: part.strip
      result.sym = XStringToKeysym(cstring(name))
  if result.sym == 0 and result.mods == Mod4Mask: result.sym = XK_Super_L   # (the key alone)

proc grabKeys()

proc setShortcuts*(list: openArray[(string, string)]) =
  ## The shortcuts to answer (an action and its keys, "" none); the keys are
  ## taken from every program while the desktop runs.
  shortcuts = @[]
  for (action, keys) in list:
    if keys.len == 0: continue
    let (m, k) = keysOf(keys)
    if k != 0: shortcuts.add (action, m, k)
  if dpy != nil:
    discard XUngrabKey(dpy, 0, AnyModifier, root)
    grabKeys()

proc showDesktopToggle() =
  ## Win+D: every window minimized; again, they come back.
  if desktopShown.len > 0:
    for c in desktopShown:
      if c in clients and c.iconic: restore(c)
    desktopShown = @[]
  else:
    for c in snapshot():
      if not c.iconic and c.transient == None:
        desktopShown.add c
        minimize(c)

proc doShortcut(action: string) =
  case action
  of "left": winArrow(active, 'L')
  of "right": winArrow(active, 'R')
  of "maximize": winArrow(active, 'U')
  of "minimize": winArrow(active, 'D')
  of "layouts":
    if active != nil:
      let r = workRect()
      openFly(active, r.x + r.w div 2, r.y + dpx(8), keys = true)
  of "desktop": showDesktopToggle()
  else:
    if shortcut != nil: shortcut(action)

proc onSuperKey(e: XKeyEvent; press: bool): bool =
  ## The Windows key: alone (pressed and let go), its own shortcut; with
  ## another key, that key's. True when it was the Windows key's business.
  let sym = XLookupKeysym(unsafeAddr e, 0)
  if sym == XK_Super_L or sym == XK_Super_R:
    if press:
      superHeld = true
      superUsed = false
    else:
      if superHeld and not superUsed:
        for s in shortcuts:
          if s.sym == XK_Super_L and s.mods == Mod4Mask: doShortcut(s.action)
      superHeld = false
    return true
  if not press or (e.state and Mod4Mask) == 0: return false
  superUsed = true
  let mods = e.state and (ShiftMask or ControlMask or Mod1Mask or Mod4Mask)
  for s in shortcuts:
    if s.sym == sym and s.mods == mods:
      doShortcut(s.action)
      return true
  true                                  # (the Windows key held: nothing else gets it)

proc onKey(e: XKeyEvent) =
  let tab = cuint(XKeysymToKeycode(dpy, XK_Tab))
  let f4 = cuint(XKeysymToKeycode(dpy, XK_F4))
  let esc = cuint(XKeysymToKeycode(dpy, XK_Escape))
  if onSuperKey(e, true): return
  let mods = e.state and (ShiftMask or ControlMask or Mod1Mask)
  let sym = XLookupKeysym(unsafeAddr e, 0)
  for s in shortcuts:
    if s.sym == sym and s.mods == mods and (s.mods and Mod4Mask) == 0:
      doShortcut(s.action)
      return
  if e.keycode == tab and (mods and Mod1Mask) != 0: switchKey((mods and ShiftMask) != 0, e.time)
  elif e.keycode == f4 and mods == Mod1Mask: close(active)
  elif e.keycode == esc and mods == ControlMask:
    if menuOpen(): closeMenu()
    elif startMenu == nil or not startMenu():
      if taskList != nil: taskList()
  elif e.keycode == esc and mods == Mod1Mask:
    if active != nil: minimize(active)
  elif backKey != 0 and backCloses and e.keycode == cuint(backKey):
    # (Android's Back, when Termux:X11 gives it as XF86Back: the window in front closes)
    if menuOpen(): closeMenu()
    elif switchWin != None: closeSwitch()
    elif active != nil: close(active)

proc onClientMessage(e: XClientMessageEvent) =
  let c = findClient(e.window)
  if e.messageType == aNetActive:
    if c != nil:
      if c.iconic: restore(c) else: focus(c)
  elif e.messageType == aNetClose:
    close(c)
  elif e.messageType == aWmChangeState:
    if c != nil and e.data[0] == 3: minimize(c)
  elif e.messageType == aNetState and c != nil:
    # (remove 0, add 1, toggle 2)
    for k in 1 .. 2:
      let a = Atom(e.data[k])
      if a == aNetFullscreen:
        let on = case e.data[0]
                 of 0: false
                 of 1: true
                 else: not c.fullscreen
        setFullscreen(c, on)
      elif a == aNetMaxH or a == aNetMaxV:
        let on = case e.data[0]
                 of 0: false
                 of 1: true
                 else: not c.maximized
        if on != c.maximized: maximize(c)
        break
  elif e.messageType == aRetro and e.window == root:
    case e.data[0]
    of 1: cascade()
    of 2: tile()
    else:
      if command != nil: command(int(e.data[0]), int(e.data[1]))

proc onConfigureRequest(e: XConfigureRequestEvent) =
  let c = findClient(e.window)
  if c == nil:
    var ch = XWindowChanges(x: e.x, y: e.y, width: e.width, height: e.height,
                            borderWidth: e.borderWidth, sibling: e.above, stackMode: e.detail)
    discard XConfigureWindow(dpy, e.window, cuint(e.valueMask), addr ch)
    return
  if c.fullscreen or c.maximized:
    sendConfigure(c)
    return
  if (e.valueMask and CWWidth) != 0: c.w = max(1, int(e.width))
  if (e.valueMask and CWHeight) != 0: c.h = max(1, int(e.height))
  if (e.valueMask and CWX) != 0: c.x = int(e.x) - bw()
  if (e.valueMask and CWY) != 0: c.y = int(e.y) - topOf()
  fitOnScreen(c)
  applyGeometry(c)
  drawFrame(c)

proc screenChanged() =
  ## The screen's size changed (the tablet turned): maximized, snapped and
  ## full screen windows follow, the others stay on it.
  workChanged()
  let (sw, sh) = screenSize()
  discard XMoveResizeWindow(dpy, desk, 0, 0, cuint(sw), cuint(sh))
  setLongs(dpy, root, atom(dpy, "_NET_DESKTOP_GEOMETRY"), XA_CARDINAL, [clong(sw), clong(sh)])
  changedNow()

proc handle(p: pointer): bool {.nimcall.} =
  ## The hook: the events of the windows the manager owns; the desktop's own
  ## window's are left to the kit.
  if not running: return false
  if otherEvents != nil and otherEvents(p): return true
  let e = cast[ptr XEvent](p)
  let kind = e.theType
  if xkbBase > 0 and kind == xkbBase:
    if keyboardChanged != nil: keyboardChanged()
    return true
  case kind
  of MapRequest:
    let w = e.xmaprequest.window
    let c = findClient(w)
    if c != nil:
      if c.iconic: restore(c)
    elif w != desk:
      manage(w, false)
    return true
  of ConfigureRequest:
    if e.xconfigurerequest.window == desk: return false
    onConfigureRequest(e.xconfigurerequest)
    return true
  of UnmapNotify:
    let w = e.xunmap.window
    if w == desk or e.xany.window == desk: return false
    let c = findClient(w)
    if c != nil and c.win == w:
      # (only the program's own unmapping counts -- in its frame, or ICCCM's
      # synthetic one to the root; not the copies X sends the window itself,
      # nor the root's when the window was put into its frame: counting those
      # let go of windows the desktop took from a desktop before it)
      if e.xunmap.event == c.frame or (e.xunmap.sendEvent != 0 and e.xunmap.event == root):
        unmanage(c, false)
    return true
  of DestroyNotify:
    let w = e.xdestroywindow.window
    if w == desk or e.xany.window == desk: return false
    let c = findClient(w)
    if c != nil and c.win == w: unmanage(c, true)
    return true
  of ConfigureNotify:
    if e.xconfigure.window == root:
      screenW = int(e.xconfigure.width)
      screenH = int(e.xconfigure.height)
      screenChanged()                    # (the desktop's window follows it)
      return true
    return e.xany.window != desk
  of PropertyNotify:
    let c = findClient(e.xproperty.window)
    if e.xproperty.window == desk: return false
    if c == nil or c.win != e.xproperty.window: return true
    let a = e.xproperty.atom
    if a == aNetWmName or a == XA_WM_NAME:
      readTitle(c)
      drawFrame(c)
      if refresh != nil: refresh()
      if c.iconic: changedNow()
    elif a == aWmProtocols or a == aWmHints:
      readProtocols(c)
    elif a == aNetType or a == XA_WM_NORMAL_HINTS:
      # (a program that says what its window is only once it is shown -- a
      # dialog, a size it keeps: its frame changes, a dialog to the middle)
      let wasDialog = c.dialog
      let wasFixed = c.fixed
      readHints(c)
      c.dialog = clong(aTypeDialog) in propLongs(dpy, c.win, aNetType, XA_ATOM)
      if c.fixed and not wasFixed and c.maximized: restore(c)   # (a phone's: its own size)
      if c.dialog and not wasDialog and not c.iconic and c.transient == None:
        if c.maximized: restore(c)
        let wr = workRect()
        c.x = max(wr.x, wr.x + (wr.w - c.frameW) div 2)
        c.y = max(wr.y, wr.y + (wr.h - c.frameH) div 3)
        applyGeometry(c)
      if c.dialog != wasDialog or c.fixed != wasFixed: drawFrame(c)
    elif a == aNetIcon:
      c.iconRead = false
      c.icon = nil
      if c.iconic: changedNow()
    return true
  of ClientMessage:
    if e.xclient.window == desk: return false
    onClientMessage(e.xclient)
    return true
  of LeaveNotify:
    let w = e.xcrossing.window
    if w == desk: return false
    let c = findClient(w)
    if c != nil and c.frame == w and hoverMax.c == c: hoverMax.c = nil
    return true
  of KeyRelease:
    if switchWin != None and e.xkey.window == switchWin:
      switchKeyEvent(e.xkey, false)
      return true
    if e.xkey.window == root:
      discard onSuperKey(e.xkey, false)
      return true
    return e.xkey.window != desk
  of Expose:
    let w = e.xexpose.window
    if w == switchWin and switchWin != None:
      if e.xexpose.count == 0: drawSwitch()
      return true
    if isMenuWin(w):
      if e.xexpose.count == 0:
        for i, l in levels:
          if l.win == w: drawLevel(i)
      return true
    if w == flyWin and flyWin != None:
      if e.xexpose.count == 0: drawFly()
      return true
    if w == assistWin and assistWin != None:
      if e.xexpose.count == 0: drawAssist()
      return true
    let c = findClient(w)
    if c != nil and c.frame == w:
      if e.xexpose.count == 0: drawFrame(c)
    return w != desk
  of ButtonPress:
    let w = e.xbutton.window
    if w == desk:
      closeMenu()
      if active != nil: focus(nil)
      return false
    if menuOpen() and isMenuWin(w):
      discard menuPress(int(e.xbutton.xRoot), int(e.xbutton.yRoot))
      return true
    if assistWin != None and w == assistWin:
      let i = assistAt(int(e.xbutton.xRoot), int(e.xbutton.yRoot))
      if i >= 0: assistChoose(i) else: closeAssist()
      return true
    if flyWin != None and w == flyWin:
      let i = flyAt(int(e.xbutton.xRoot), int(e.xbutton.yRoot))
      if i >= 0: flyChoose(i)
      elif flyKeys: closeFly()
      return true
    if flyWin != None: closeFly()
    if assistWin != None: closeAssist()
    let c = findClient(w)
    if c == nil: return true
    if w == c.win:
      closeMenu()
      if c != active or clients[^1] != c: focus(c)
      if (e.xbutton.state and Mod1Mask) != 0 and e.xbutton.button in [1.cuint, 3] and
         not c.fullscreen and not c.splash:
        # (Alt held: the window moved by the left button, sized by the
        # right one from its nearest corner; the click is not the program's)
        discard XAllowEvents(dpy, AsyncPointer, e.xbutton.time)
        moved = false
        pressTime = e.xbutton.time
        if e.xbutton.button == 1:
          drag = (dkMove, c, pTitle, int(e.xbutton.xRoot), int(e.xbutton.yRoot), c.x, c.y, c.w, c.h)
          aim = (false, false, zWhole)
        else:
          if c.maximized or c.zoned:
            c.maximized = false
            c.zoned = false
            setNetState(c)
          let left = int(e.xbutton.x) < c.w div 2
          let top = int(e.xbutton.y) < c.h div 2
          let part = if top: (if left: pNW else: pNE) else: (if left: pSW else: pSE)
          drag = (dkResize, c, part, int(e.xbutton.xRoot), int(e.xbutton.yRoot), c.x, c.y, c.w, c.h)
        discard XGrabPointer(dpy, c.frame, 0, cuint(ButtonReleaseMask or PointerMotionMask),
                             GrabModeAsync, GrabModeAsync, None,
                             (if drag.kind == dkMove: fleur else: cursorFor(drag.part)), CurrentTime)
        return true
      # (a click in a window: it comes to the front, and the click goes on to it)
      discard XAllowEvents(dpy, ReplayPointer, e.xbutton.time)
    else:
      closeMenu()
      pressFrame(c, e.xbutton)
    return true
  of MotionNotify:
    let w = e.xmotion.window
    if menuOpen() and isMenuWin(w):
      menuMotion(int(e.xmotion.xRoot), int(e.xmotion.yRoot))
      return true
    if assistWin != None and w == assistWin:
      let i = assistAt(int(e.xmotion.xRoot), int(e.xmotion.yRoot))
      if i != assistHot and i >= 0:
        assistHot = i
        drawAssist()
      return true
    if flyWin != None and w == flyWin:
      let i = flyAt(int(e.xmotion.xRoot), int(e.xmotion.yRoot))
      if i != flyHot:
        flyHot = i
        drawFly()
      return true
    if drag.kind in {dkMove, dkResize}:
      moveDrag(int(e.xmotion.xRoot), int(e.xmotion.yRoot))
      return true
    let c = findClient(w)
    if c != nil and c.frame == w:
      let part = partAt(c, int(e.xmotion.x), int(e.xmotion.y))
      if shownCursor.getOrDefault(w, pNone) != part:
        shownCursor[w] = part
        discard XDefineCursor(dpy, w, cursorFor(part))
      # (resting on the maximize button: the layouts, a moment later)
      if part == pMax and c.hasButtons and drag.kind == dkNone:
        if hoverMax.c != c and flyWin == None:
          hoverMax = (c, epochTime())
          wakeIn(650)
      elif hoverMax.c == c: hoverMax.c = nil
    return w != desk
  of ButtonRelease:
    let w = e.xbutton.window
    if menuOpen() and isMenuWin(w):
      menuRelease(int(e.xbutton.xRoot), int(e.xbutton.yRoot))
      # (the release goes on to the desktop too, where it was let go: a menu
      # opened by the desktop's press -- a right click, a finger held -- would
      # leave the desktop thinking the button is still down)
      e.xbutton.window = desk
      e.xbutton.x = e.xbutton.xRoot
      e.xbutton.y = e.xbutton.yRoot
      return false
    if drag.kind != dkNone:
      endDrag(e.xbutton)
      return true
    return w != desk
  of KeyPress:
    if menuOpen() and isMenuWin(e.xkey.window):
      menuKey(e.xkey)
      return true
    if flyWin != None and e.xkey.window == flyWin:
      flyKey(e.xkey)
      return true
    if assistWin != None and e.xkey.window == assistWin:
      assistKey(e.xkey)
      return true
    if switchWin != None and e.xkey.window == switchWin:
      switchKeyEvent(e.xkey, true)
      return true
    if e.xkey.window == root:
      onKey(e.xkey)
      return true
    return false
  else:
    # (any other event of a window that is not the desktop's is the
    # manager's: a frame's, a program's, the root's; events without a window
    # -- the keyboard's, the extensions' -- are the kit's)
    if kind >= 35 or kind == 11 or kind == 34: return false
    return e.xany.window != desk

# ---- starting and stopping --------------------------------------------------------------------------

proc onXError(d: Display; e: ptr XErrorEvent): cint {.cdecl.} =
  ## (a window gone before a request about it arrived is no error here; a
  ## second manager is)
  if e.errorCode == 10 and e.requestCode == 2: otherWm = true     # BadAccess on ChangeWindowAttributes
  0

proc setBackCloses*(on: bool) =
  ## Android's Back key (XF86Back, when Termux:X11 gives it to X) closes the
  ## window in front (`on`), or goes to the program in front as any key
  ## (off, the default: Termux:X11's own use of Back -- its keyboard -- and
  ## a browser's Back are left alone).
  backCloses = on
  if dpy == nil: return
  if backKey == 0: backKey = int(XKeysymToKeycode(dpy, 0x1008FF26.culong))
  if backKey == 0 or on == backGrabbed: return
  for extra in [0.cuint, LockMask, Mod2Mask, LockMask or Mod2Mask]:
    if on: discard XGrabKey(dpy, cint(backKey), extra, root, 1, GrabModeAsync, GrabModeAsync)
    else: discard XUngrabKey(dpy, cint(backKey), extra, root)
  backGrabbed = on

proc grabKeys() =
  var keys = @[(XK_Tab, Mod1Mask), (XK_Tab, Mod1Mask or ShiftMask), (XK_F4, Mod1Mask),
               (XK_Escape, ControlMask), (XK_Escape, Mod1Mask)]
  var superToo = false
  for s in shortcuts:
    if (s.mods and Mod4Mask) != 0: superToo = true
    else: keys.add (s.sym, s.mods)
  for (sym, mods) in keys:
    let code = cint(XKeysymToKeycode(dpy, sym))
    if code == 0: continue
    for extra in [0.cuint, LockMask, Mod2Mask, LockMask or Mod2Mask]:
      discard XGrabKey(dpy, code, mods or extra, root, 0, GrabModeAsync, GrabModeAsync)
  if superToo:
    # (the Windows key itself: while it is down every key comes here, the
    # shortcuts with it are the desktop's)
    # (every key that is one: a keyboard can have two of each)
    # (not owner_events: the keys pressed with it come to the root, even
    # when the desktop's own window has the focus)
    for code in 8 .. 255:
      let sym = XKeycodeToKeysym(dpy, uint8(code), 0)
      if sym == XK_Super_L or sym == XK_Super_R:
        discard XGrabKey(dpy, cint(code), AnyModifier, root, 0, GrabModeAsync, GrabModeAsync)
  backGrabbed = false
  setBackCloses(backCloses)

proc start*(): bool =
  ## Becomes the screen's window manager, on the connection of the desktop's
  ## window; false when another one is running.
  dpy = x11Display()
  if dpy == nil: return false
  desk = Window(x11Window())
  scr = XDefaultScreen(dpy)
  root = XRootWindow(dpy, scr)
  gc = XCreateGC(dpy, root, 0, nil)
  discard XSetErrorHandler(onXError)
  otherWm = false
  discard XSelectInput(dpy, root, SubstructureRedirectMask or SubstructureNotifyMask or
                       StructureNotifyMask or PropertyChangeMask or KeyPressMask)
  discard XSync(dpy, 0)
  if otherWm: return false
  for (name, a) in [("WM_STATE", addr aWmState), ("WM_PROTOCOLS", addr aWmProtocols),
                  ("WM_DELETE_WINDOW", addr aWmDelete), ("WM_TAKE_FOCUS", addr aWmTakeFocus),
                  ("WM_CHANGE_STATE", addr aWmChangeState), ("_NET_WM_NAME", addr aNetWmName),
                  ("UTF8_STRING", addr aUtf8), ("_NET_ACTIVE_WINDOW", addr aNetActive),
                  ("_NET_CLOSE_WINDOW", addr aNetClose), ("_NET_WM_STATE", addr aNetState),
                  ("_NET_WM_STATE_FULLSCREEN", addr aNetFullscreen),
                  ("_NET_WM_STATE_MAXIMIZED_HORZ", addr aNetMaxH),
                  ("_NET_WM_STATE_MAXIMIZED_VERT", addr aNetMaxV),
                  ("_NET_WM_STATE_HIDDEN", addr aNetHidden),
                  ("_NET_CLIENT_LIST", addr aNetClientList), ("_NET_WM_WINDOW_TYPE", addr aNetType),
                  ("_NET_WM_WINDOW_TYPE_DESKTOP", addr aTypeDesktop),
                  ("_NET_WM_WINDOW_TYPE_DOCK", addr aTypeDock),
                  ("_NET_WM_WINDOW_TYPE_DIALOG", addr aTypeDialog),
                  ("_NET_WM_WINDOW_TYPE_SPLASH", addr aTypeSplash),
                  ("_NET_WM_ICON", addr aNetIcon), ("_NET_FRAME_EXTENTS", addr aNetFrameExtents),
                  ("_RETRO_DESKTOP", addr aRetro), ("WM_HINTS", addr aWmHints)]:
    a[] = atom(dpy, name)
  # (who manages the screen: EWMH's check window, with its name)
  checkWin = XCreateSimpleWindow(dpy, root, -10, -10, 1, 1, 0, 0, 0)
  let check = atom(dpy, "_NET_SUPPORTING_WM_CHECK")
  setLongs(dpy, root, check, XA_WINDOW, [clong(checkWin)])
  setLongs(dpy, checkWin, check, XA_WINDOW, [clong(checkWin)])
  setText(dpy, checkWin, aNetWmName, aUtf8, "Retro Desktop")
  # (whose it is: a desktop started again finds the one that runs, and ends
  # it when it no longer answers)
  block:
    proc c_getpid(): cint {.importc: "getpid", header: "<unistd.h>".}
    setLongs(dpy, checkWin, atom(dpy, "_NET_WM_PID"), XA_CARDINAL, [clong(c_getpid())])
  var supported: seq[clong]
  for a in [aNetActive, aNetClose, aNetState, aNetFullscreen, aNetMaxH, aNetMaxV, aNetHidden,
            aNetClientList, aNetType, aTypeDesktop, aTypeDock, aTypeDialog, aNetWmName,
            aNetIcon, aNetFrameExtents, check]:
    supported.add clong(a)
  setLongs(dpy, root, atom(dpy, "_NET_SUPPORTED"), XA_ATOM, supported)
  setLongs(dpy, root, atom(dpy, "_NET_NUMBER_OF_DESKTOPS"), XA_CARDINAL, [1.clong])
  setLongs(dpy, root, atom(dpy, "_NET_CURRENT_DESKTOP"), XA_CARDINAL, [0.clong])
  # (the desktop's own window: at the bottom, the whole screen)
  setLongs(dpy, desk, aNetType, XA_ATOM, [clong(aTypeDesktop)])
  readScreenSize()
  let (sw, sh) = screenSize()
  discard XMoveResizeWindow(dpy, desk, 0, 0, cuint(sw), cuint(sh))
  discard XLowerWindow(dpy, desk)
  grabKeys()
  # (the keyboard's layout changing: XKB says it)
  var op, ev, er: cint
  var major = 1.cint
  var minor = 0.cint
  if XkbQueryExtension(dpy, addr op, addr ev, addr er, addr major, addr minor) != 0:
    xkbBase = ev
    discard XkbSelectEventDetails(dpy, XkbUseCoreKbd, XkbStateNotify, XkbGroupStateMask, XkbGroupStateMask)
  fleur = culong(x11ClassicCursor(curMove, cursorScale()))
  discard XDefineCursor(dpy, root, cursorFor(pNone))
  running = true
  x11EventHook = handle
  screenChanged()
  # (the windows already on the screen)
  var r, parent: Window
  var kids: ptr UncheckedArray[Window]
  var n: cuint
  if XQueryTree(dpy, root, addr r, addr parent, addr kids, addr n) != 0 and kids != nil:
    var list: seq[Window]
    for i in 0 ..< int(n): list.add kids[i]
    discard XFree(kids)
    for w in list: manage(w, true)
  discard XFlush(dpy)
  true

proc stop*() =
  ## Gives every window back to the screen, as it was, and stops managing.
  if not running: return
  closeMenu()
  resumeAll()
  for c in clients.reversed:
    let x = c.x + bw()
    let y = c.y + topOf()
    discard XUngrabButton(dpy, AnyButton, AnyModifier, c.win)
    discard XReparentWindow(dpy, c.win, root, cint(max(0, x)), cint(max(0, y)))
    discard XMapWindow(dpy, c.win)
    discard XRemoveFromSaveSet(dpy, c.win)
    discard XDestroyWindow(dpy, c.frame)
  clients.setLen(0)
  x11EventHook = nil
  running = false
  discard XSync(dpy, 0)

proc sessionWindows*(): seq[Client] =
  ## The programs' windows, bottom to top, for the desktop to keep (which
  ## programs were open, where): not the dialogs.
  for c in clients:
    if c.transient == None and not c.dialog and c.pid > 0: result.add c

proc savedGeometry*(c: Client): tuple[x, y, w, h: int] =
  ## Where `c` is, or was before it was maximized.
  if c.maximized: c.saved else: (c.x, c.y, c.w, c.h)

proc closeAll*() =
  ## Asks every program to close its windows (Exit Retro Desktop).
  resumeAll()
  for c in snapshot(): close(c)

proc relook*() =
  ## Draws every frame again (the colors changed).
  drawAll()
  discard XFlush(dpy)
