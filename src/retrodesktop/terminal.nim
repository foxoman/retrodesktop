## Terminal: a shell in a window, as the desktop's own MS-DOS Prompt -- in
## the 16 colors of a PC's text screen, black on white as Windows' windows
## (or MS-DOS's gray on black), the line-drawing characters drawn whole, xterm's escape
## sequences (`vt.nim`) for full-screen programs (vim, nano, htop, mc, less),
## mouse reports for the ones that take the mouse, a scrollback to wheel
## through, selecting with the mouse, copy and paste.
##
## The shell runs on a pseudo-terminal. A thread waits for what it writes
## and wakes the window through the X server (a ClientMessage on a
## connection of its own): the terminal takes no CPU while nothing happens.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, unicode, posix, locks, math]
import retroui
import retroui/uirelays/drivers/x11_driver
from retroui/typeset import hasGlyphs
import xlib, common, link
import vt

# ---- the pseudo-terminal --------------------------------------------------------------------------

type Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
  ws_row, ws_col, ws_xpixel, ws_ypixel: cushort

proc c_ioctl(fd: cint; req: culong): cint {.importc: "ioctl", header: "<sys/ioctl.h>", varargs.}
var TIOCSWINSZ {.importc, header: "<sys/ioctl.h>".}: culong
var TIOCSCTTY {.importc, header: "<sys/ioctl.h>".}: culong
proc posix_openpt(flags: cint): cint {.importc, header: "<stdlib.h>".}
proc grantpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
proc unlockpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
proc ptsname(fd: cint): cstring {.importc, header: "<stdlib.h>".}
proc c_exit(code: cint) {.importc: "_exit", header: "<unistd.h>", noreturn.}

const TermSettings = "retrodesktop-terminal"

var
  ptyFd: cint = -1
  child: Pid
  inLock: Lock
  inbox: string                  # what the shell wrote, not read yet (under inLock)
  ended: bool                    # the shell is gone (under inLock)
  outbox: string                 # what is to be written to the shell
  wakeAtom: Atom
  termWin: uint
  prevHook: proc (ev: pointer): bool {.nimcall.}

proc setSize(cols, rows: int) =
  if ptyFd < 0: return
  var ws = Winsize(ws_row: cushort(rows), ws_col: cushort(cols))
  discard c_ioctl(ptyFd, TIOCSWINSZ, addr ws)

proc shellCommand(args: seq[string]): seq[string] =
  ## What runs in the terminal: the command after -e, else the user's shell
  ## (Termux's login, which sets Termux up; $SHELL; bash; sh).
  if args.len > 0:
    return @["/bin/sh", "-c", args.join(" ")]
  let pfx = prefixDir()
  if existsEnv("TERMUX_VERSION") and fileExists(pfx / "bin" / "login"):
    return @[pfx / "bin" / "login"]
  let sh = getEnv("SHELL")
  if sh.len > 0 and fileExists(sh): return @[sh, "-l"]
  for s in ["bash", "zsh", "sh"]:
    let p = findExe(s)
    if p.len > 0: return @[p, "-l"]
  @["/bin/sh"]

proc spawn(cmd: seq[string]; cols, rows: int): bool =
  ## The shell on a new pseudo-terminal of `cols` x `rows`.
  let m = posix_openpt(O_RDWR or O_NOCTTY)
  if m < 0: return false
  if grantpt(m) != 0 or unlockpt(m) != 0:
    discard close(m)
    return false
  let slave = $ptsname(m)
  ptyFd = m
  setSize(cols, rows)
  putEnv("TERM", "xterm-256color")
  putEnv("COLORTERM", "truecolor")
  delEnv("COLUMNS")
  delEnv("LINES")
  # (everything the child needs, made before fork: after it, no allocating)
  var sh = cmd
  if sh.len > 0 and not sh[0].contains('/'):
    let p = findExe(sh[0])
    if p.len > 0: sh[0] = p
  let argv = allocCStringArray(sh)
  let slaveC = slave.cstring
  let home = getHomeDir()
  let homeC = home.cstring
  let pid = fork()
  if pid < 0:
    deallocCStringArray(argv)
    return false
  if pid == 0:
    discard setsid()
    let s = posix.open(slaveC, O_RDWR)
    if s < 0: c_exit(127)
    discard c_ioctl(s, TIOCSCTTY, 0)
    discard dup2(s, 0)
    discard dup2(s, 1)
    discard dup2(s, 2)
    if s > 2: discard close(s)
    discard close(m)
    discard chdir(homeC)
    discard signal(SIGPIPE, SIG_DFL)
    discard signal(SIGCHLD, SIG_DFL)
    discard signal(SIGINT, SIG_DFL)
    discard signal(SIGQUIT, SIG_DFL)
    discard execv(argv[0], argv)
    c_exit(127)
  deallocCStringArray(argv)
  child = pid
  discard fcntl(m, F_SETFL, fcntl(m, F_GETFL) or O_NONBLOCK)
  true

proc sendWake(d: Display) =
  ## (from the reader thread, on its own connection: the window's own
  ## connection wakes with this ClientMessage)
  if d == nil or termWin == 0: return
  var e: XEvent
  e.xclient.theType = ClientMessage
  e.xclient.window = Window(termWin)
  e.xclient.messageType = wakeAtom
  e.xclient.format = 32
  discard XSendEvent(d, Window(termWin), 0, 0, addr e)
  discard XFlush(d)

proc reader() {.thread.} =
  ## Waits for what the shell writes; puts it in the inbox and wakes the
  ## window (once, until the window took it).
  {.cast(gcsafe).}:
    let d = XOpenDisplay(nil)
    var buf = newString(32768)
    while true:
      var pfd = TPollfd(fd: ptyFd, events: POLLIN)
      let r = poll(addr pfd, 1, -1)
      if r < 0:
        if errno == EINTR: continue
        break
      let n = read(ptyFd, addr buf[0], buf.len)
      if n > 0:
        var wasEmpty = false
        var big = false
        withLock inLock:
          wasEmpty = inbox.len == 0
          inbox.add buf[0 ..< n]
          big = inbox.len > 2_000_000
        if wasEmpty: sendWake(d)
        # (a program writing faster than the screen takes it: it waits)
        while big:
          sleep(5)
          withLock inLock: big = inbox.len > 500_000
      elif n == 0 or (errno != EAGAIN and errno != EINTR):
        break
    withLock inLock: ended = true
    sendWake(d)
    if d != nil: discard XCloseDisplay(d)

proc termHook(p: pointer): bool {.nimcall.} =
  let e = cast[ptr XEvent](p)
  if e.theType == ClientMessage and e.xclient.messageType == wakeAtom and wakeAtom != 0:
    ui.redraw = true
    x11Wake()
    return true
  if prevHook != nil: prevHook(p) else: false

proc flushOut() =
  while outbox.len > 0 and ptyFd >= 0:
    let n = write(ptyFd, addr outbox[0], outbox.len)
    if n > 0: outbox = outbox[n .. ^1]
    else: break

proc send(s: string) =
  outbox.add s
  flushOut()

# ---- colors -----------------------------------------------------------------------------------------

const Cga = [
  # (a PC's 16 text colors, as MS-DOS showed them)
  (0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0), (0, 0, 170), (170, 0, 170),
  (0, 170, 170), (170, 170, 170), (85, 85, 85), (255, 85, 85), (85, 255, 85),
  (255, 255, 85), (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255)]

var
  whiteScheme = true             ## black on white, as Windows' own windows (MS-DOS Colors: gray on black)
  boldLetters = true             ## every letter bold: chunky, as a PC's text screen had them
  fontK = 1.0
  scrollLines = 3000

proc palette(i: int): Color =
  if i < 16:
    let (r, g, b) = Cga[i]
    return color(uint8(r), uint8(g), uint8(b))
  if i < 232:
    let n = i - 16
    let lv = [0, 95, 135, 175, 215, 255]
    return color(uint8(lv[n div 36]), uint8(lv[(n div 6) mod 6]), uint8(lv[n mod 6]))
  let v = uint8(8 + (i - 232) * 10)
  color(v, v, v)

proc defaultFg(): Color = (if whiteScheme: color(0, 0, 0) else: palette(7))
proc defaultBg(): Color = (if whiteScheme: color(255, 255, 255) else: color(0, 0, 0))

proc inkColor(k: Ink; fg: bool; bold: bool): Color =
  case k.kind
  of 1:
    var i = int(k.index)
    if fg and bold and i < 8: i += 8
    palette(i)
  of 2: color(k.r, k.g, k.b)
  else:
    if fg: (if bold and not whiteScheme: palette(15) else: defaultFg()) else: defaultBg()

# ---- the screen and its geometry ----------------------------------------------------------------

var
  scr: Screen
  view = 0                       # lines scrolled back
  cw = 8.0                       # a character's width (logical pixels)
  chH = 16                       # a line's height
  area: Rect                     # where the characters are
  st: TextStyle
  sel: tuple[on, active: bool; a, b: tuple[row, col: int]]   # rows: counted from the scrollback's first
  showAbout = false

proc measure() =
  st = style(mono = true, size = fontK, bold = boldLetters)
  cw = float(textWidth(repeat('M', 100), st)) / 100
  chH = max(4, lineHeight(st))

proc absRow(row: int): int = scr.scrollback.len + row - view

proc cellAt(x, y: int): tuple[row, col: int] =
  let col = clamp(int(float(x - area.x) / cw), 0, scr.cols - 1)
  let row = clamp((y - area.y) div chH, 0, scr.rows - 1)
  (absRow(row), col)

proc selected(abs, col: int): bool =
  if not sel.on: return false
  var a = sel.a
  var b = sel.b
  if (b.row, b.col) < (a.row, a.col): swap(a, b)
  if abs < a.row or abs > b.row: return false
  if abs == a.row and col < a.col: return false
  if abs == b.row and col > b.col: return false
  true

proc lineAbs(abs: int): vt.Line =
  if abs < scr.scrollback.len: scr.scrollback[abs]
  else:
    let i = abs - scr.scrollback.len
    if i >= 0 and i < scr.rows: scr.lines[i] else: @[]

proc selectionText(): string =
  if not sel.on: return ""
  var a = sel.a
  var b = sel.b
  if (b.row, b.col) < (a.row, a.col): swap(a, b)
  var parts: seq[string]
  for r in a.row .. b.row:
    let l = lineAbs(r)
    let x0 = if r == a.row: a.col else: 0
    let x1 = if r == b.row: b.col else: -1
    parts.add lineText(l, x0, x1)
  parts.join("\n")

proc wordAt(abs, col: int): (int, int) =
  let l = lineAbs(abs)
  if col >= l.len: return (col, col)
  proc isWord(c: vt.Cell): bool =
    let r = c.ch
    int(r) != 0 and (r.isAlpha or int(r) in {ord('0') .. ord('9')} or
                     int(r) in [ord('_'), ord('-'), ord('.'), ord('/'), ord('~')])
  if not isWord(l[col]): return (col, col)
  var a = col
  var b = col
  while a > 0 and isWord(l[a - 1]): dec a
  while b < l.high and isWord(l[b + 1]): inc b
  (a, b)

# ---- drawing --------------------------------------------------------------------------------------

proc boxChar(r: Rune; x, y, w, h: int; c: Color): bool =
  ## The line-drawing and block characters drawn to fill their place, so
  ## lines meet from one to the next: true when `r` was one.
  let cp = int(r)
  if cp < 0x2500 or cp > 0x259F: return false
  let cx = x + w div 2
  let cy = y + h div 2
  let t = max(1, w div 8)
  let t2 = max(1, w div 5)
  proc hline(x0, x1, yy, th: int) = fill(x0, yy - th div 2, max(1, x1 - x0), th, c)
  proc vline(xx, y0, y1, th: int) = fill(xx - th div 2, y0, th, max(1, y1 - y0), c)
  # (which arms: left, right, up, down; light 1, heavy 2, double 3)
  var L, R, U, D = 0
  case cp
  of 0x2500: L = 1; R = 1
  of 0x2501: L = 2; R = 2
  of 0x2502: U = 1; D = 1
  of 0x2503: U = 2; D = 2
  of 0x250C: R = 1; D = 1
  of 0x250F: R = 2; D = 2
  of 0x2510: L = 1; D = 1
  of 0x2513: L = 2; D = 2
  of 0x2514: R = 1; U = 1
  of 0x2517: R = 2; U = 2
  of 0x2518: L = 1; U = 1
  of 0x251B: L = 2; U = 2
  of 0x251C: R = 1; U = 1; D = 1
  of 0x2523: R = 2; U = 2; D = 2
  of 0x2524: L = 1; U = 1; D = 1
  of 0x252B: L = 2; U = 2; D = 2
  of 0x252C: L = 1; R = 1; D = 1
  of 0x2533: L = 2; R = 2; D = 2
  of 0x2534: L = 1; R = 1; U = 1
  of 0x253B: L = 2; R = 2; U = 2
  of 0x253C: L = 1; R = 1; U = 1; D = 1
  of 0x254B: L = 2; R = 2; U = 2; D = 2
  of 0x2550: L = 3; R = 3
  of 0x2551: U = 3; D = 3
  of 0x2554: R = 3; D = 3
  of 0x2557: L = 3; D = 3
  of 0x255A: R = 3; U = 3
  of 0x255D: L = 3; U = 3
  of 0x2560: R = 3; U = 3; D = 3
  of 0x2563: L = 3; U = 3; D = 3
  of 0x2566: L = 3; R = 3; D = 3
  of 0x2569: L = 3; R = 3; U = 3
  of 0x256C: L = 3; R = 3; U = 3; D = 3
  of 0x256D: R = 1; D = 1
  of 0x256E: L = 1; D = 1
  of 0x256F: L = 1; U = 1
  of 0x2570: R = 1; U = 1
  of 0x2574: L = 1
  of 0x2575: U = 1
  of 0x2576: R = 1
  of 0x2577: D = 1
  of 0x2580: fill(x, y, w, h div 2, c); return true
  of 0x2584: fill(x, cy, w, h - h div 2, c); return true
  of 0x2588: fill(x, y, w, h, c); return true
  of 0x258C: fill(x, y, w div 2, h, c); return true
  of 0x2590: fill(cx, y, w - w div 2, h, c); return true
  of 0x2591, 0x2592, 0x2593:
    # (shades: dots in a checker, sparse to dense)
    let step = max(1, w div 4)
    let k = cp - 0x2590
    var yy = y
    var odd = false
    while yy < y + h:
      var xx = x + (if odd: step else: 0)
      while xx < x + w:
        fill(xx, yy, max(1, step * k div 3), max(1, step div 2 + k div 2), c)
        xx += 2 * step
      yy += step
      odd = not odd
    return true
  else:
    if cp >= 0x2581 and cp <= 0x2587:
      let part = (cp - 0x2580) * h div 8
      fill(x, y + h - part, w, part, c)
      return true
    if cp >= 0x2589 and cp <= 0x258F:
      let part = (0x2590 - cp) * w div 8
      fill(x, y, part, h, c)
      return true
    return false
  if L + R + U + D == 0: return false
  # horizontal arms
  for (n, x0, x1) in [(L, x, cx + 1), (R, cx, x + w)]:
    case n
    of 1: hline(x0, x1, cy, t)
    of 2: hline(x0, x1, cy, t2)
    of 3:
      hline(x0, x1, cy - max(2, h div 8), t)
      hline(x0, x1, cy + max(2, h div 8), t)
    else: discard
  for (n, y0, y1) in [(U, y, cy + 1), (D, cy, y + h)]:
    case n
    of 1: vline(cx, y0, y1, t)
    of 2: vline(cx, y0, y1, t2)
    of 3:
      vline(cx - max(2, w div 5), y0, y1, t)
      vline(cx + max(2, w div 5), y0, y1, t)
    else: discard
  true

var notInMono: Table[int32, bool]
  ## the letters FreeMono has not (drawn from another font, alone)

proc missing(ch: Rune): bool =
  let cp = int32(ch)
  if cp < 0x80: return false
  if not notInMono.hasKey(cp):
    notInMono[cp] = not hasGlyphs($ch, faceOf(style(mono = true)))
  notInMono[cp]

proc fallbackText(ch: Rune; x, y, w, h: int; fg: Color; st: TextStyle) =
  ## A letter FreeMono has not: from FreeSans or FreeSerif (GNU FreeFont has
  ## most of Unicode's alphabets and symbols between them), in the middle of
  ## its cell; else from the system's fonts.
  let s = $ch
  var st2 = st
  for serif in [false, true]:
    st2.mono = false
    st2.serif = serif
    if hasGlyphs(s, faceOf(st2)):
      let tw = textWidth(s, st2)
      pushClip(rect(x, y, w, h))
      text(x + (w - tw) div 2, y, s, fg, st2)
      popClip()
      return
  text(x, y, s, fg, st)

proc drawScreen(r: Rect; focused: bool) =
  fill(r, defaultBg())
  for row in 0 ..< scr.rows:
    let l = scr.lineAt(row, view)
    let abs = absRow(row)
    let y = area.y + row * chH
    var x = 0
    while x < min(l.len, scr.cols):
      # a run of characters that look the same
      let c0 = l[x]
      let rev0 = (aReverse in c0.attrs) xor selected(abs, x)
      var fg = inkColor(c0.fg, true, aBold in c0.attrs)
      var bg = inkColor(c0.bg, false, false)
      if rev0: swap(fg, bg)
      if aDim in c0.attrs: fg = color(uint8((int(fg.r) + int(bg.r)) div 2),
                                      uint8((int(fg.g) + int(bg.g)) div 2),
                                      uint8((int(fg.b) + int(bg.b)) div 2))
      var run = ""
      var x1 = x
      var special = false
      while x1 < min(l.len, scr.cols):
        let c = l[x1]
        if c.fg != c0.fg or c.bg != c0.bg or c.attrs != c0.attrs or
           ((aReverse in c.attrs) xor selected(abs, x1)) != rev0:
          break
        let cp = int(c.ch)
        if (cp >= 0x2500 and cp <= 0x259F) or charWidth(c.ch) == 2 or c.wide2 or missing(c.ch):
          if x1 == x: special = true; inc x1
          break
        run.add(if cp == 0: " " else: $c.ch)
        inc x1
      let px0 = area.x + int(round(float(x) * cw))
      let px1 = area.x + int(round(float(x1) * cw))
      if bg != defaultBg(): fill(px0, y, px1 - px0, chH, bg)
      if special:
        let c = l[x]
        let cp = int(c.ch)
        if c.wide2 or cp == 0: discard
        elif cp >= 0x2500 and cp <= 0x259F:
          if not boxChar(c.ch, px0, y, px1 - px0, chH, fg):
            text(px0, y, $c.ch, fg, st)
        elif charWidth(c.ch) == 2:
          # (a wide character: its two places)
          let pxw = area.x + int(round(float(x + 2) * cw))
          if bg != defaultBg(): fill(px1, y, pxw - px1, chH, bg)
          fallbackText(c.ch, px0, y, pxw - px0, chH, fg, st)
        elif aHidden notin c.attrs:
          var s2 = st
          s2.bold = boldLetters or aBold in c.attrs
          fallbackText(c.ch, px0, y, px1 - px0, chH, fg, s2)
      elif aHidden notin c0.attrs:
        let trimmed = run.strip(leading = false, chars = {' '})
        if trimmed.len > 0:
          var s2 = st
          s2.bold = boldLetters or aBold in c0.attrs
          s2.italic = aItalic in c0.attrs
          s2.underline = aUnderline in c0.attrs
          s2.strike = aStrike in c0.attrs
          text(px0, y, trimmed, fg, s2)
      x = x1
  # the cursor
  if view == 0 and scr.cursorShown:
    let cx = area.x + int(round(float(scr.cx) * cw))
    let cy = area.y + scr.cy * chH
    let w = max(2, int(round(cw)))
    let ink = if whiteScheme: color(0, 0, 0) else: palette(7)
    if focused:
      fill(cx, cy, w, chH, ink)
      let c = scr.lines[scr.cy][scr.cx]
      if int(c.ch) != 0 and not c.wide2:
        if not boxChar(c.ch, cx, cy, w, chH, defaultBg()):
          text(cx, cy, $c.ch, defaultBg(), st)
    else:
      box(rect(cx, cy, w, chH), ink)

# ---- the keyboard and the mouse ----------------------------------------------------------------

proc modNum(mods: set[Modifier]): int =
  1 + (if ShiftPressed in mods: 1 else: 0) + (if AltPressed in mods: 2 else: 0) +
    (if CtrlPressed in mods: 4 else: 0)

proc keyBytes(k: KeyCode; mods: set[Modifier]): string =
  ## What a key sends to the program (xterm's), "" for the keys that type text.
  let m = modNum(mods)
  let ctrl = CtrlPressed in mods
  let alt = AltPressed in mods
  let esc = if alt: "\e" else: ""
  proc cur(final: char): string =
    if m > 1: "\e[1;" & $m & $final
    elif scr.appCursor: "\eO" & $final
    else: "\e[" & $final
  proc tilde(n: int): string =
    if m > 1: "\e[" & $n & ";" & $m & "~" else: "\e[" & $n & "~"
  case k
  of KeyUp: cur('A')
  of KeyDown: cur('B')
  of KeyRight: cur('C')
  of KeyLeft: cur('D')
  of KeyHome: cur('H')
  of KeyEnd: cur('F')
  of KeyInsert: tilde(2)
  of KeyDelete: tilde(3)
  of KeyPageUp: tilde(5)
  of KeyPageDown: tilde(6)
  of KeyF1, KeyF2, KeyF3, KeyF4:
    let f = "PQRS"[ord(k) - ord(KeyF1)]
    if m > 1: "\e[1;" & $m & $f else: "\eO" & $f
  of KeyF5: tilde(15)
  of KeyF6: tilde(17)
  of KeyF7: tilde(18)
  of KeyF8: tilde(19)
  of KeyF9: tilde(20)
  of KeyF10: tilde(21)
  of KeyF11: tilde(23)
  of KeyF12: tilde(24)
  of KeyEnter: esc & "\r"
  of KeyTab: (if ShiftPressed in mods: "\e[Z" else: esc & "\t")
  of KeyBackspace: (if ctrl: esc & "\x08" else: esc & "\x7f")
  of KeyEsc: "\e"
  of KeyA .. KeyZ:
    if ctrl: esc & $chr(ord(k) - ord(KeyA) + 1)
    elif alt:
      let c = chr(ord('a') + ord(k) - ord(KeyA))
      "\e" & $(if ShiftPressed in mods: c.toUpperAscii else: c)
    else: ""
  of Key0 .. Key9:
    if alt and not ctrl: "\e" & $chr(ord('0') + ord(k) - ord(Key0))
    elif ctrl and k == Key2: "\0"
    elif ctrl and k == Key6: "\x1e"
    else: ""
  of KeySpace: (if ctrl: "\0" elif alt: "\e " else: "")
  of KeyLeftBracket: (if ctrl: "\e" else: "")
  of KeyBackslash: (if ctrl: "\x1c" else: "")
  of KeyRightBracket: (if ctrl: "\x1d" else: "")
  of KeyMinus: (if ctrl and ShiftPressed in mods: "\x1f" else: "")
  of KeySlash: (if ctrl: "\x1f" else: "")
  else: ""

proc paste() =
  var t = getClipboardText()
  if t.len == 0: return
  t = t.replace("\r\n", "\r").replace("\n", "\r")
  view = 0
  if scr.bracketedPaste: send("\e[200~" & t & "\e[201~")
  else: send(t)

proc copySelection() =
  let t = selectionText()
  if t.len > 0: putClipboardText(t)

proc keys() =
  ## The keys, before the menus see them: the program gets them all, but
  ## Ctrl+Shift+C and V (copy, paste) and Shift+PgUp, PgDn (the scrollback).
  if ui.dialogTop != 0 or ui.popup != 0: return
  let mods = ui.mods
  let k = ui.key
  if k != KeyNone:
    if CtrlPressed in mods and ShiftPressed in mods and k == KeyC:
      copySelection()
      ui.keyUsed = true
    elif CtrlPressed in mods and ShiftPressed in mods and k == KeyV:
      paste()
      ui.keyUsed = true
    elif ShiftPressed in mods and k in {KeyPageUp, KeyPageDown} and not scr.alt:
      view = clamp(view + (if k == KeyPageUp: scr.rows - 1 else: -(scr.rows - 1)),
                   0, scr.scrollback.len)
      ui.keyUsed = true
    else:
      let b = keyBytes(k, mods)
      if b.len > 0:
        view = 0
        sel.on = false
        send(b)
        ui.keyUsed = true
        ui.mnemonic = '\0'
        if CtrlPressed in mods or AltPressed in mods: ui.typed = ""
  if ui.typed.len > 0 and CtrlPressed notin mods and AltPressed notin mods:
    var t = ""
    for ch in ui.typed:
      if ord(ch) >= 0x20 and ord(ch) != 0x7F: t.add ch
    if t.len > 0:
      view = 0
      sel.on = false
      send(t)
    ui.typed = ""
    ui.mnemonic = '\0'

proc mouseReport(button, col, row: int; release: bool) =
  if scr.mouseSgr:
    send("\e[<" & $button & ";" & $(col + 1) & ";" & $(row + 1) & (if release: "m" else: "M"))
  else:
    let b = if release: 3 else: button
    if col < 223 and row < 223:
      send("\e[M" & $chr(32 + b) & $chr(33 + col) & $chr(33 + row))

var lastMouseCell = (-1, -1)

proc mouse(r: Rect) =
  # (the screen's own only when nothing is over it: a menu, a dialog -- their
  # clicks are theirs)
  let hit = interact(idOf("terminal-screen"), r, focusable = false)
  let over = hit.hover and ui.dialogTop == 0 and ui.popup == 0
  let col = clamp(int(float(ui.mx - area.x) / cw), 0, scr.cols - 1)
  let row = clamp((ui.my - area.y) div chH, 0, scr.rows - 1)
  let reports = scr.mouse != mmNone and ShiftPressed notin ui.mods and view == 0
  # the wheel: the program's (mouse reports; arrows on the alternate screen),
  # else the scrollback
  if over and ui.wheel != 0 and not ui.wheelUsed:
    ui.wheelUsed = true
    if reports:
      for _ in 0 ..< min(abs(ui.wheel), 5): mouseReport(if ui.wheel > 0: 64 else: 65, col, row, false)
    elif scr.alt:
      for _ in 0 ..< min(abs(ui.wheel) * 3, 15): send(keyBytes(if ui.wheel > 0: KeyUp else: KeyDown, {}))
    else:
      view = clamp(view + ui.wheel * 3, 0, scr.scrollback.len)
  if reports:
    if over and ui.pressed and not ui.pressUsed:
      mouseReport(0, col, row, false)
      lastMouseCell = (col, row)
      ui.pressUsed = true
    elif over and ui.rpressed and not ui.menuKey:
      mouseReport(2, col, row, false)
      mouseReport(2, col, row, true)
    elif ui.released and lastMouseCell[0] >= 0:
      mouseReport(0, col, row, true)
      lastMouseCell = (-1, -1)
    elif ui.mouseDown and scr.mouse in {mmDrags, mmMotion} and (col, row) != lastMouseCell and
         lastMouseCell[0] >= 0:
      mouseReport(32, col, row, false)
      lastMouseCell = (col, row)
    return
  # selecting
  if over and ui.pressed and not ui.pressUsed:
    ui.pressUsed = true
    let c = cellAt(ui.mx, ui.my)
    if ui.clicks >= 2:
      let (a, b) = wordAt(c.row, c.col)
      sel = (true, false, (c.row, a), (c.row, b))
      if ui.clicks >= 3:
        sel = (true, false, (c.row, 0), (c.row, scr.cols - 1))
    else:
      sel = (false, true, c, c)
  elif sel.active and ui.mouseDown:
    let c = cellAt(ui.mx, ui.my)
    if c != sel.b:
      sel.b = c
      sel.on = sel.a != sel.b
      ui.redraw = true
    # (past the top or the bottom: the view scrolls)
    if ui.my < area.y and view < scr.scrollback.len:
      inc view
      wakeIn(50)
    elif ui.my > area.y + area.h and view > 0:
      dec view
      wakeIn(50)
  elif sel.active and ui.released:
    sel.active = false
  if over and ui.rpressed and not ui.pressUsed:
    openPopupMenu("term", ui.mx, ui.my)

# ---- the window -------------------------------------------------------------------------------

proc keepSettings() =
  var s = loadSettings(TermSettings)
  s["colors"] = (if whiteScheme: "white" else: "dos")
  s["font"] = formatFloat(fontK, ffDecimal, 2)
  s["bold"] = (if boldLetters: "1" else: "0")
  discard saveSettings(TermSettings, s)

proc runTerminal*(args: seq[string]) =
  ## The terminal, until its shell ends (or its window is closed: the shell
  ## is told the terminal hung up).
  let s = loadSettings(TermSettings)
  whiteScheme = s.getOrDefault("colors", "white") == "white"
  boldLetters = s.getOrDefault("bold", "1") == "1"
  try: fontK = clamp(parseFloat(s.getOrDefault("font", "1.0")), 0.6, 3.0) except ValueError: discard
  try: scrollLines = clamp(parseInt(s.getOrDefault("scrollback", "3000")), 100, 100_000) except ValueError: discard
  applyDesktopLook()
  openApp("Terminal", scaled(680), scaled(460), frame = wfSystem, userFrame = false, id = "terminal")
  showArt("terminal")
  followLook()
  initLock(inLock)
  let d = Display(x11Display())
  if d != nil:
    wakeAtom = atom(d, "_RETRO_TERM_WAKE")
    termWin = x11Window()
    prevHook = x11EventHook
    x11EventHook = termHook
  measure()
  scr = newScreen(80, 25, scrollLines)
  var started = false
  var failed = false
  var thread: Thread[void]
  var lastTitle = ""
  while beginFrame():
    keys()
    menubar:
      menu "&Edit":
        if menuItem("&Copy", "Ctrl+Shift+C", enabled = sel.on): copySelection()
        if menuItem("&Paste", "Ctrl+Shift+V"): paste()
        if menuItem("Select &All"):
          sel = (true, false, (0, 0), (scr.scrollback.len + scr.rows - 1, scr.cols - 1))
        menuSeparator()
        if menuItem("Clear &Scrollback"):
          scr.scrollback.setLen(0)
          view = 0
          sel.on = false
      menu "&Settings":
        if menuItem("&MS-DOS Colors", checked = not whiteScheme):
          whiteScheme = false
          keepSettings()
        if menuItem("&Windows Colors", checked = whiteScheme):
          whiteScheme = true
          keepSettings()
        menuSeparator()
        if menuItem("&Bold Letters", checked = boldLetters):
          boldLetters = not boldLetters
          keepSettings()
          measure()
        if menuItem("&Larger Text"):
          fontK = min(3.0, fontK + 0.1)
          keepSettings()
          measure()
        if menuItem("&Smaller Text"):
          fontK = max(0.6, fontK - 0.1)
          keepSettings()
          measure()
      menu "&Help":
        if menuItem("&About Terminal..."): showAbout = true
    let r = canvas(-1, remainingH())
    # the grid fills the place: the shell is told when its size changes
    let inset = dp(3)
    let cols = max(2, int(float(r.w - 2 * inset) / cw))
    let rows = max(1, (r.h - 2 * inset) div chH)
    area = rect(r.x + inset, r.y + inset, int(float(cols) * cw), rows * chH)
    if cols != scr.cols or rows != scr.rows:
      scr.resize(cols, rows)
      setSize(cols, rows)
      view = clamp(view, 0, scr.scrollback.len)
    if not started and not failed:
      if spawn(shellCommand(args), cols, rows):
        started = true
        createThread(thread, reader)
      else:
        failed = true
        scr.feed("Retro Desktop could not start a shell here.\r\n")
    # what the shell wrote
    var got = ""
    var gone = false
    withLock inLock:
      if inbox.len > 262_144:
        got = inbox[0 ..< 262_144]
        inbox = inbox[262_144 .. ^1]
      else:
        swap(got, inbox)
      gone = ended and inbox.len == 0
    if got.len > 0:
      scr.feed(got)
      if inbox.len > 0: wakeIn(1)
    if scr.replies.len > 0:
      send(scr.replies)
      scr.replies.setLen(0)
    if outbox.len > 0:
      flushOut()
      if outbox.len > 0: wakeIn(10)
    if gone and started:
      var status: cint
      discard waitpid(child, status, WNOHANG)
      quitApp()
    mouse(r)
    drawScreen(r, ui.active31)
    if scr.title != lastTitle:
      lastTitle = scr.title
      setTitle(if scr.title.len > 0: scr.title else: "Terminal")
    popupMenu("term"):
      if menuItem("&Copy", "Ctrl+Shift+C", enabled = sel.on): copySelection()
      if menuItem("&Paste", "Ctrl+Shift+V"): paste()
      menuSeparator()
      if menuItem("Select &All"):
        sel = (true, false, (0, 0), (scr.scrollback.len + scr.rows - 1, scr.cols - 1))
    aboutBox(showAbout, "Terminal", DesktopVersion,
             ["A shell in a window, in a PC's 16 text colors.",
              "The terminal type it says it is: xterm-256color."])
    endFrame()
    appFrameDone()
  if started and child > 0:
    discard kill(child, SIGHUP)
  closeApp()
