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

import std/[math, tables, algorithm, strutils]
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
    posGiven: bool             ## the program said where its window goes
    dialog: bool               ## a dialog (centered when it belongs to no window)
    minW, minH: int
    icon*: Bitmap              ## its icon (_NET_WM_ICON), nil when it has none
    iconRead: bool
    pressed: Part

  DragKind = enum dkNone, dkMove, dkResize, dkButton

  MenuItem* = tuple[label, keys: string; enabled: bool; action: proc ()]
    ## A menu's item: its label ("&" before the letter to underline; "" a
    ## line between groups), its keys, whether it can be chosen, what it does.

var
  dpy*: Display
  scr: cint
  root*, desk*, checkWin, menuWin: Window
  clients*: seq[Client]          ## bottom to top
  active*: Client
  gc: pointer
  running*: bool
  otherWm: bool
  changed*: proc () {.nimcall.}  ## the desktop should draw again (icons)
  taskList*: proc () {.nimcall.} ## Ctrl+Esc
  command*: proc (n, arg: int) {.nimcall.}
    ## a _RETRO_DESKTOP message the desktop answers (3 arrange icons,
    ## 4 the settings changed, 5 exit)
  bigFrames*: bool               ## title bars and borders for fingers
  maximizeNew*: bool             ## new windows open maximized (a phone)
  drag: tuple[kind: DragKind; c: Client; part: Part; rx, ry: int; x, y, w, h: int]
  lastClick: tuple[c: Client; part: Part; time: Time]
  pressTime: Time
  moved: bool
  fleur: culong
  shownCursor: Table[Window, Part]
  cascadeAt = 0
  menu: tuple[c: Client; items: seq[MenuItem]; hot: int; x, y, w, h, itemH: int;
              fromX, fromY: int; armed: bool]
  aWmState, aWmProtocols, aWmDelete, aWmTakeFocus, aWmChangeState, aNetWmName, aUtf8,
    aNetActive, aNetClose, aNetState, aNetFullscreen, aNetMaxH, aNetMaxV, aNetHidden,
    aNetClientList, aNetType, aTypeDesktop, aTypeDock, aTypeDialog, aTypeSplash,
    aNetIcon, aNetFrameExtents, aRetro, aWmHints: Atom

proc changedNow() =
  if changed != nil: changed()
  ui.redraw = true
  x11Wake()

# ---- sizes and colors -------------------------------------------------------------------------------

proc snapshot(): seq[Client] =
  ## The windows as a list of their own, to walk while `clients` changes
  ## (raising one reorders it).
  for x in clients: result.add x

proc dpx(v: int): int =
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

proc xcolor(c: Color): culong = (culong(c.r) shl 16) or (culong(c.g) shl 8) or culong(c.b)

proc screenSize*(): tuple[w, h: int] =
  (int(XDisplayWidth(dpy, scr)), int(XDisplayHeight(dpy, scr)))

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

proc putBitmap(w: Window; b: Bitmap; x, y: int) =
  ## A picture from the kit's canvas put on a window (24-bit screens).
  if b == nil or b.w <= 0 or b.h <= 0 or XDefaultDepth(dpy, scr) < 24: return
  let img = XCreateImage(dpy, XDefaultVisual(dpy, scr), 24, ZPixmap, 0, addr b.px[0],
                         cuint(b.w), cuint(b.h), 32, cint(b.w * 4))
  if img == nil: return
  discard XPutImage(dpy, w, gc, img, 0, 0, cint(x), cint(y), cuint(b.w), cuint(b.h))
  img.data = nil                         # (the pixels are the canvas's)
  discard XFree(img)

proc hasButtons(c: Client): bool = c.transient == None and not c.fixed

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
  if not c.fixed and not c.maximized:
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
    var title = c.title
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
      c.fixed = true
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
  let (sw, sh) = screenSize()
  c.x = -bw()
  c.y = -bw()
  c.w = sw
  c.h = sh - tbh() - 1

proc fitOnScreen(c: Client) =
  ## Keeps the frame on the screen: no larger than it, its title bar in it.
  let (sw, sh) = screenSize()
  c.w = clamp(c.w, 1, max(1, sw - 2 * bw()))
  c.h = clamp(c.h, 1, max(1, sh - bw() - topOf()))
  c.x = clamp(c.x, -(c.frameW - dpx(60)), sw - dpx(60))
  c.y = clamp(c.y, 0, max(0, sh - topOf()))

proc place(c: Client; x, y: int; given: bool) =
  ## Where a new window goes: where it asks, over the window it belongs to
  ## (a dialog), else the next step of a cascade from the top left.
  let (sw, sh) = screenSize()
  let parent = findClient(c.transient)
  if parent != nil:
    c.x = parent.x + (parent.frameW - c.frameW) div 2
    c.y = parent.y + (parent.frameH - c.frameH) div 3
  elif (given or c.posGiven) and (x != 0 or y != 0):
    c.x = x - bw()
    c.y = y - topOf()
  elif c.dialog:
    c.x = (sw - c.frameW) div 2
    c.y = (sh - c.frameH) div 3
  else:
    let step = topOf()
    let (aw, ah) = (c.frameW, c.frameH)
    if aw >= sw * 9 div 10 or ah >= sh * 9 div 10:
      c.x = (sw - aw) div 2
      c.y = (sh - ah) div 2
    else:
      c.x = dpx(16) + cascadeAt * step
      c.y = dpx(16) + cascadeAt * step
      if c.x + aw > sw or c.y + ah > sh:
        cascadeAt = 0
        c.x = dpx(16)
        c.y = dpx(16)
      inc cascadeAt
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

proc close*(c: Client) =
  ## Asks the program to close the window (WM_DELETE_WINDOW), else ends it.
  if c == nil: return
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

proc restore*(c: Client) =
  ## An icon back to its window (or a maximized window to its size before).
  if c == nil: return
  if c.iconic:
    c.iconic = false
    discard XMapWindow(dpy, c.frame)
    setWmState(c, 1)
  elif c.maximized:
    c.maximized = false
    (c.x, c.y, c.w, c.h) = c.saved
    applyGeometry(c)
  setNetState(c)
  focus(c)
  drawFrame(c)
  changedNow()

proc maximize*(c: Client) =
  ## The window as large as the screen (its border off it).
  if c == nil or c.fixed or c.transient != None: return
  if c.maximized:
    restore(c)
    return
  if c.iconic: restore(c)
  c.saved = (c.x, c.y, c.w, c.h)
  c.maximized = true
  maximizeGeometry(c)
  applyGeometry(c)
  setNetState(c)
  focus(c)
  drawFrame(c)

proc setFullscreen(c: Client; on: bool) =
  if on == c.fullscreen: return
  if on:
    if not c.maximized: c.saved = (c.x, c.y, c.w, c.h)
    c.fullscreen = true
  else:
    c.fullscreen = false
    if c.maximized: maximizeGeometry(c)
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
  let (sw, sh) = screenSize()
  for c in snapshot():
    if c.iconic or c.fullscreen or c.transient != None: continue
    if c.maximized:
      c.maximized = false
    c.w = min(c.w, sw * 2 div 3)
    c.h = min(c.h, sh * 2 div 3)
    c.x = dpx(16) + cascadeAt * topOf()
    c.y = dpx(16) + cascadeAt * topOf()
    inc cascadeAt
    fitOnScreen(c)
    applyGeometry(c)
    setNetState(c)
    raiseClient(c)
    drawFrame(c)
  if active != nil: focus(active)

proc tile*() =
  ## The windows side by side, filling the screen.
  var l: seq[Client]
  for c in snapshot():
    if not c.iconic and not c.fullscreen and c.transient == None and not c.fixed: l.add c
  if l.len == 0: return
  let (sw, sh) = screenSize()
  let cols = int(ceil(sqrt(float(l.len))))
  let rows = (l.len + cols - 1) div cols
  let reserve = if iconicClients().len > 0: dpx(76) else: 0
  for i, c in l:
    let col = i mod cols
    let row = i div cols
    c.maximized = false
    c.x = col * sw div cols
    c.y = row * (sh - reserve) div rows
    c.w = sw div cols - 2 * bw()
    c.h = (sh - reserve) div rows - bw() - topOf()
    applyGeometry(c)
    setNetState(c)
    drawFrame(c)

var
  cycleList: seq[Client]
  cycleAt: int
  cycleTime: Time

proc cycle*(back = false; time: Time = CurrentTime) =
  ## Alt+Tab: the window behind to the front; pressed again soon after, the
  ## one behind that, and so on through all of them (Alt+Shift+Tab: back).
  var fresh = time == CurrentTime or time < cycleTime or time - cycleTime > 1500 or
              cycleList.len == 0
  for c in cycleList:
    if c notin clients: fresh = true
  if fresh:
    cycleList = @[]
    for i in countdown(clients.high, 0):
      if clients[i].transient == None: cycleList.add clients[i]
    cycleAt = 0
  cycleTime = time
  if cycleList.len < 2: return
  cycleAt = (cycleAt + (if back: -1 else: 1) + cycleList.len) mod cycleList.len
  let c = cycleList[cycleAt]
  if c.iconic: restore(c) else: focus(c)

# ---- the control menu -------------------------------------------------------------------------------

proc closeMenu*() =
  ## The menu that is open (the control menu, the desktop's) closed.
  if menuWin != None:
    discard XUngrabPointer(dpy, CurrentTime)
    discard XUngrabKeyboard(dpy, CurrentTime)
    discard XDestroyWindow(dpy, menuWin)
    menuWin = None
    menu.items = @[]

proc drawMenu() =
  if menuWin == None: return
  let t = ui.theme
  let cv = newCanvas2D(menu.w, menu.h)
  cv.fillStyle = t.frame
  cv.fillRect(0, 0, float(menu.w), float(menu.h))
  cv.fillStyle = t.window
  cv.fillRect(1, 1, float(menu.w - 2), float(menu.h - 2))
  let px = max(9, int(round(float(menu.itemH) * 0.5)))
  cv.font = $px & "px sans-serif"
  cv.textBaseline = "middle"
  var y = 2
  for i, it in menu.items:
    if it.label.len == 0:
      cv.fillStyle = t.frame
      cv.fillRect(1, float(y + menu.itemH div 4), float(menu.w - 2), 1)
      y += menu.itemH div 2
      continue
    let hot = i == menu.hot and it.enabled
    if hot:
      cv.fillStyle = t.select
      cv.fillRect(2, float(y), float(menu.w - 4), float(menu.itemH))
    let ink = if not it.enabled: t.gray elif hot: t.selectText else: t.text
    cv.fillStyle = ink
    cv.textAlign = "left"
    # (the letter after "&" underlined, as 3.1's menus have it)
    let amp = it.label.find('&')
    let shown = it.label.replace("&", "")
    let tx = float(dpx(14))
    let ty = float(y + menu.itemH div 2)
    cv.fillText(shown, tx, ty)
    if amp >= 0 and amp < shown.len:
      let x0 = tx + cv.measureText(shown[0 ..< amp]).width
      let w = cv.measureText(shown[amp .. amp]).width
      cv.fillRect(x0, ty + float(px) * 0.45, w, max(1.0, float(px) / 12))
    if it.keys.len > 0:
      cv.textAlign = "right"
      cv.fillText(it.keys, float(menu.w - dpx(10)), float(y + menu.itemH div 2))
    y += menu.itemH
  putBitmap(menuWin, cv.toBitmap, 0, 0)

proc menuItemAt(x, y: int): int =
  var yy = 2
  for i, it in menu.items:
    let h = if it.label.len == 0: menu.itemH div 2 else: menu.itemH
    if y >= yy and y < yy + h and x >= 0 and x < menu.w: return (if it.label.len == 0: -1 else: i)
    yy += h
  -1

proc menuItem*(label, keys: string; enabled: bool; action: proc ()): MenuItem =
  ## An item for `showMenu`.
  (label, keys, enabled, action)

proc menuLine*(): MenuItem =
  ## A line between groups of items.
  ("", "", false, nil)

proc showMenu*(items: seq[MenuItem]; x, y: int; above = false) =
  ## A menu at `x`, `y` on the screen (the screen's pixels; `above`: its
  ## bottom at `y`), over every window: the pointer and the keyboard its own
  ## until an item is chosen (a click, a letter, Enter) or it is left (a
  ## click outside, Esc).
  closeMenu()
  if items.len == 0: return
  menu.items = items
  menu.itemH = max(16, dpx(if bigFrames: 32 else: 22))
  # (as wide as its widest label and keys)
  let probe = newCanvas2D(4, 4)
  let px = max(9, int(round(float(menu.itemH) * 0.5)))
  probe.font = $px & "px sans-serif"
  var lw, kw = 0.0
  for it in items:
    lw = max(lw, probe.measureText(it.label.replace("&", "")).width)
    kw = max(kw, probe.measureText(it.keys).width)
  menu.w = max(dpx(140), int(lw + kw) + dpx(14 + 24 + 10))
  menu.h = 4
  for it in menu.items: menu.h += (if it.label.len == 0: menu.itemH div 2 else: menu.itemH)
  let (sw, sh) = screenSize()
  menu.x = clamp(x, 0, max(0, sw - menu.w))
  menu.y = clamp((if above: y - menu.h else: y), 0, max(0, sh - menu.h))
  menu.hot = -1
  # (the button that opened it, let go where it was pressed, leaves it open;
  # moved onto an item first, the item is chosen -- 3.1's press, drag, let go)
  menu.fromX = x
  menu.fromY = y
  menu.armed = false
  menuWin = XCreateSimpleWindow(dpy, root, cint(menu.x), cint(menu.y), cuint(menu.w), cuint(menu.h),
                                0, 0, xcolor(ui.theme.window))
  # (override-redirect: a menu is not a window to manage)
  var attrs: XSetWindowAttributes
  attrs.overrideRedirect = 1
  discard XChangeWindowAttributes(dpy, menuWin, CWOverrideRedirect, addr attrs)
  discard XSelectInput(dpy, menuWin, ExposureMask or ButtonPressMask or ButtonReleaseMask or
                       PointerMotionMask or KeyPressMask)
  discard XMapWindow(dpy, menuWin)
  discard XRaiseWindow(dpy, menuWin)
  discard XGrabPointer(dpy, menuWin, 1, cuint(ButtonPressMask or ButtonReleaseMask or PointerMotionMask),
                       GrabModeAsync, GrabModeAsync, None, 0, CurrentTime)
  discard XGrabKeyboard(dpy, menuWin, 0, GrabModeAsync, GrabModeAsync, CurrentTime)
  drawMenu()

proc menuKey(e: XKeyEvent) =
  ## Up and Down through the items, Enter chooses, Esc closes.
  let code = e.keycode
  template isKey(sym: culong): bool = code == cuint(XKeysymToKeycode(dpy, sym))
  var step = 0
  if isKey(XK_Escape):
    closeMenu()
    return
  elif isKey(XK_Down): step = 1
  elif isKey(XK_Up): step = -1
  elif isKey(XK_Return):
    let i = menu.hot
    if i >= 0 and i < menu.items.len and menu.items[i].enabled:
      let act = menu.items[i].action
      closeMenu()
      if act != nil: act()
    return
  if step == 0:
    # (the underlined letter of an item chooses it)
    var ek = e
    let sym = XLookupKeysym(addr ek, 0)
    if sym >= culong('a') and sym <= culong('z'):
      for i, it in menu.items:
        let amp = it.label.find('&')
        if it.enabled and amp >= 0 and amp + 1 < it.label.len and
           it.label[amp + 1].toLowerAscii == char(sym):
          let act = it.action
          closeMenu()
          if act != nil: act()
          return
    return
  if step != 0 and menu.items.len > 0:
    var i = menu.hot
    for _ in 0 ..< menu.items.len:
      i = (i + step + menu.items.len) mod menu.items.len
      if menu.items[i].label.len > 0 and menu.items[i].enabled: break
    menu.hot = i
    drawMenu()

proc openMenu*(c: Client; x, y: int) =
  ## The control menu of `c` (Restore, Minimize, Maximize, Close, Switch
  ## To...) at `x`, `y` on the screen.
  if c == nil: return
  let isDialog = c.transient != None or c.fixed
  menu.c = c
  # (the window may be gone by the time an item is chosen)
  template its(body: untyped): proc () =
    proc () =
      if menu.c != nil and menu.c in clients: body
  showMenu(@[
    menuItem("&Restore", "", c.maximized or c.iconic, its(restore(menu.c))),
    menuItem("Mi&nimize", "", not isDialog and not c.iconic, its(minimize(menu.c))),
    menuItem("Ma&ximize", "", not isDialog and not c.maximized, its(maximize(menu.c))),
    menuLine(),
    menuItem("&Close", "Alt+F4", true, its(close(menu.c))),
    menuLine(),
    menuItem("S&witch To...", "Ctrl+Esc", true, proc () = (if taskList != nil: taskList()))], x, y)

# ---- managing a window ------------------------------------------------------------------------------

proc manage(w: Window; adopt: bool) =
  if w == desk or w == checkWin or w == menuWin or findClient(w) != nil: return
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
  readProtocols(c)
  readHints(c)
  if clong(aTypeSplash) in types: c.fixed = true
  c.dialog = clong(aTypeDialog) in types
  c.w = max(c.w, 1)
  place(c, int(a.x), int(a.y), adopt)
  c.frame = XCreateSimpleWindow(dpy, root, cint(c.x), cint(c.y), cuint(c.frameW), cuint(c.frameH),
                                0, 0, xcolor(ui.theme.face))
  discard XSelectInput(dpy, c.frame, SubstructureRedirectMask or SubstructureNotifyMask or
                       ButtonPressMask or ButtonReleaseMask or PointerMotionMask or ExposureMask)
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
  elif (maximizeNew and c.hasButtons and not adopt) or
       (clong(aNetMaxH) in st and clong(aNetMaxV) in st and c.hasButtons):
    focus(c)
    maximize(c)
  focus(c)
  updateClientList()
  changedNow()

proc unmanage(c: Client; destroyed: bool) =
  if not destroyed:
    let (x, y) = (c.x + bw(), c.y + topOf())
    discard XUngrabButton(dpy, AnyButton, AnyModifier, c.win)
    discard XReparentWindow(dpy, c.win, root, cint(x), cint(y))
    discard XRemoveFromSaveSet(dpy, c.win)
    setWmState(c, 0)
  discard XDestroyWindow(dpy, c.frame)
  shownCursor.del(c.frame)
  var rest: seq[Client]
  for x in clients:
    if x != c: rest.add x
  clients = rest
  if menu.c == c: closeMenu()
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
  if y >= b and y < b + th and x >= b and x < fw - b:
    let tx = x - b
    if tx < th: return pMenu
    if c.hasButtons:
      if tx >= fw - 2 * b - th: return pMax
      if tx >= fw - 2 * b - 2 * th: return pMin
    return pTitle
  if c.fixed or c.maximized:
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

proc cursorScale(): int = max(1, int(round(devScale())))

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
      # (a maximized window does not move; holding a finger on its title
      # still opens its menu)
      drag = (dkMove, c, part, int(e.xRoot), int(e.yRoot), c.x, c.y, c.w, c.h)
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
    if c.maximized or c.fullscreen: return
    let (sw, sh) = screenSize()
    c.x = clamp(drag.x + dx, -(c.frameW - dpx(40)), sw - dpx(40))
    c.y = clamp(drag.y + dy, 0, max(0, sh - topOf()))
    discard XMoveWindow(dpy, c.frame, cint(c.x), cint(c.y))
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
    if not moved and kind == dkMove and e.time >= pressTime and e.time - pressTime >= 550:
      openMenu(c, int(e.xRoot), int(e.yRoot))       # (held: the control menu)
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

proc onKey(e: XKeyEvent) =
  let tab = cuint(XKeysymToKeycode(dpy, XK_Tab))
  let f4 = cuint(XKeysymToKeycode(dpy, XK_F4))
  let esc = cuint(XKeysymToKeycode(dpy, XK_Escape))
  let mods = e.state and (ShiftMask or ControlMask or Mod1Mask)
  if e.keycode == tab and (mods and Mod1Mask) != 0: cycle((mods and ShiftMask) != 0, e.time)
  elif e.keycode == f4 and mods == Mod1Mask: close(active)
  elif e.keycode == esc and mods == ControlMask:
    if taskList != nil: taskList()
  elif e.keycode == esc and mods == Mod1Mask:
    if active != nil: minimize(active)

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
  ## The screen's size changed (the tablet turned): maximized and full
  ## screen windows follow, the others stay on it.
  for c in snapshot():
    if c.fullscreen: applyGeometry(c)
    elif c.maximized:
      maximizeGeometry(c)
      applyGeometry(c)
    else:
      fitOnScreen(c)
      applyGeometry(c)
    drawFrame(c)
  let (sw, sh) = screenSize()
  discard XMoveResizeWindow(dpy, desk, 0, 0, cuint(sw), cuint(sh))
  setLongs(dpy, root, atom(dpy, "_NET_DESKTOP_GEOMETRY"), XA_CARDINAL, [clong(sw), clong(sh)])
  setLongs(dpy, root, atom(dpy, "_NET_WORKAREA"), XA_CARDINAL, [0.clong, 0, clong(sw), clong(sh)])
  changedNow()

proc handle(p: pointer): bool {.nimcall.} =
  ## The hook: the events of the windows the manager owns; the desktop's own
  ## window's are left to the kit.
  if not running: return false
  let e = cast[ptr XEvent](p)
  let kind = e.theType
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
      if c.iconic: changedNow()
    elif a == aWmProtocols or a == aWmHints:
      readProtocols(c)
    elif a == aNetIcon:
      c.iconRead = false
      c.icon = nil
      if c.iconic: changedNow()
    return true
  of ClientMessage:
    if e.xclient.window == desk: return false
    onClientMessage(e.xclient)
    return true
  of Expose:
    let w = e.xexpose.window
    if w == menuWin and menuWin != None:
      if e.xexpose.count == 0: drawMenu()
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
    if menuWin != None and w == menuWin:
      menu.armed = true
      let i = menuItemAt(int(e.xbutton.x), int(e.xbutton.y))
      if i < 0 and (e.xbutton.x < 0 or e.xbutton.y < 0 or e.xbutton.x >= cint(menu.w) or
                    e.xbutton.y >= cint(menu.h)):
        closeMenu()
      return true
    let c = findClient(w)
    if c == nil: return true
    if w == c.win:
      # (a click in a window: it comes to the front, and the click goes on to it)
      closeMenu()
      if c != active or clients[^1] != c: focus(c)
      discard XAllowEvents(dpy, ReplayPointer, e.xbutton.time)
    else:
      closeMenu()
      pressFrame(c, e.xbutton)
    return true
  of MotionNotify:
    let w = e.xmotion.window
    if menuWin != None and w == menuWin:
      let i = menuItemAt(int(e.xmotion.x), int(e.xmotion.y))
      if not menu.armed and (abs(int(e.xmotion.xRoot) - menu.fromX) > dpx(6) or
                             abs(int(e.xmotion.yRoot) - menu.fromY) > dpx(6)):
        menu.armed = true
      if i != menu.hot:
        menu.hot = i
        drawMenu()
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
    return w != desk
  of ButtonRelease:
    let w = e.xbutton.window
    if menuWin != None and w == menuWin:
      let i = menuItemAt(int(e.xbutton.x), int(e.xbutton.y))
      if menu.armed and i >= 0 and menu.items[i].enabled:
        let act = menu.items[i].action
        closeMenu()
        if act != nil: act()
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
    if menuWin != None and e.xkey.window == menuWin:
      menuKey(e.xkey)
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

proc grabKeys() =
  for (sym, mods) in [(XK_Tab, Mod1Mask), (XK_Tab, Mod1Mask or ShiftMask), (XK_F4, Mod1Mask),
                      (XK_Escape, ControlMask), (XK_Escape, Mod1Mask)]:
    let code = cint(XKeysymToKeycode(dpy, sym))
    if code == 0: continue
    for extra in [0.cuint, LockMask, Mod2Mask, LockMask or Mod2Mask]:
      discard XGrabKey(dpy, code, mods or extra, root, 1, GrabModeAsync, GrabModeAsync)

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
  let (sw, sh) = screenSize()
  discard XMoveResizeWindow(dpy, desk, 0, 0, cuint(sw), cuint(sh))
  discard XLowerWindow(dpy, desk)
  grabKeys()
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

proc closeAll*() =
  ## Asks every program to close its windows (Exit Retro Desktop).
  for c in snapshot(): close(c)

proc relook*() =
  ## Draws every frame again (the colors changed).
  drawAll()
  discard XFlush(dpy)
