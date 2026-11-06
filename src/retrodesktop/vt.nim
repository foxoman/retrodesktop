## The terminal's screen: what a program writes to it (text, and the
## escape sequences of xterm and the VT100/VT220 it grew from) made into a
## grid of characters with their colors -- the cursor, scrolling regions,
## the alternate screen full-screen programs use, the line-drawing set,
## 16, 256 and 24-bit colors, the modes programs switch on (application
## cursor keys, bracketed paste, mouse reports), the lines scrolled off
## the top kept to scroll back to. And the replies a program asks for (where
## the cursor is, what terminal this is).
##
## No drawing here: `terminal.nim` draws the grid and runs the program.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, unicode]

type
  Attr* = enum
    aBold, aDim, aItalic, aUnderline, aBlink, aReverse, aHidden, aStrike

  Ink* = object
    ## A color: the default, one of the 256 of the palette, or exact.
    case kind*: range[0 .. 2]   ## 0 default, 1 palette, 2 RGB
    of 1: index*: uint8
    of 2: r*, g*, b*: uint8
    else: discard

  Cell* = object
    ## One place on the screen: its character (0: empty), and how it looks.
    ## A wide character takes two: the second has `wide2`.
    ch*: Rune
    fg*, bg*: Ink
    attrs*: set[Attr]
    wide2*: bool

  Line* = seq[Cell]

  MouseMode* = enum
    mmNone, mmClicks, mmDrags, mmMotion

  Screen* = ref object
    cols*, rows*: int
    lines*: seq[Line]            ## the screen shown (the main or the alternate)
    mainLines, altLines: seq[Line]
    alt*: bool                   ## the alternate screen is shown
    scrollback*: seq[Line]       ## lines scrolled off the top of the main screen
    maxScrollback*: int
    cx*, cy*: int                ## the cursor
    wrapNext: bool               ## the cursor is past the last column (the next character wraps)
    pen: Cell                    ## the colors and attributes characters are written with
    saved: tuple[cx, cy: int; pen: Cell; origin: bool; g0: bool]
    top, bottom: int             ## the scrolling region
    tabs: seq[bool]
    origin: bool                 ## DECOM: the cursor's rows count from the region's top
    autowrap*: bool
    insert: bool                 ## IRM
    lineDrawing: bool            ## G0 is DEC's line-drawing set
    appCursor*: bool             ## DECCKM: the arrows send ESC O A...
    appKeypad*: bool
    cursorShown*: bool           ## DECTCEM
    bracketedPaste*: bool
    mouse*: MouseMode
    mouseSgr*: bool              ## mouse reports as CSI < ... M
    focusReports*: bool
    title*: string               ## what the program called the window (OSC 0 and 2)
    replies*: string             ## what to write back to the program (reports)
    bell*: bool                  ## a BEL came
    changed*: bool               ## the screen changed since `changed` was cleared
    # (the parser)
    state: int
    params: seq[int]
    curParam: int
    hasParam: bool
    privMark, interm: char
    osc: string
    utf8Need, utf8Have: int
    utf8Cp: int32
    lastChar: Rune

const
  stGround = 0
  stEsc = 1
  stCsi = 2
  stOsc = 3
  stOscEsc = 4
  stCharset = 5
  stDcs = 6
  stDcsEsc = 7
  stEscInterm = 8

proc defaultInk*(): Ink = Ink(kind: 0)
proc paletteInk*(i: int): Ink = Ink(kind: 1, index: uint8(clamp(i, 0, 255)))
proc rgbInk*(r, g, b: int): Ink =
  Ink(kind: 2, r: uint8(clamp(r, 0, 255)), g: uint8(clamp(g, 0, 255)), b: uint8(clamp(b, 0, 255)))

proc `==`*(a, b: Ink): bool =
  if a.kind != b.kind: return false
  case a.kind
  of 1: a.index == b.index
  of 2: a.r == b.r and a.g == b.g and a.b == b.b
  else: true

proc blank(pen: Cell): Cell =
  ## An empty place in the pen's background (erasing paints with it).
  Cell(ch: Rune(0), fg: pen.fg, bg: pen.bg)

proc newLine(cols: int; pen: Cell): Line =
  result = newSeq[Cell](cols)
  let b = blank(pen)
  for i in 0 ..< cols: result[i] = b

proc charWidth*(r: Rune): int =
  ## How many places a character takes: 2 for the wide ones of East Asian
  ## scripts and most emoji, 0 for marks that combine with the one before.
  let c = int(r)
  if c == 0: return 1
  if c < 0x300: return 1
  if (c >= 0x300 and c <= 0x36F) or (c >= 0x1AB0 and c <= 0x1AFF) or
     (c >= 0x1DC0 and c <= 0x1DFF) or (c >= 0x20D0 and c <= 0x20FF) or
     (c >= 0xFE20 and c <= 0xFE2F) or c == 0x200B or c == 0x200C or c == 0x200D or
     (c >= 0xFE00 and c <= 0xFE0F):
    return 0
  if (c >= 0x1100 and c <= 0x115F) or (c >= 0x2E80 and c <= 0x303E) or
     (c >= 0x3041 and c <= 0x33FF) or (c >= 0x3400 and c <= 0x4DBF) or
     (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0xA000 and c <= 0xA4CF) or
     (c >= 0xAC00 and c <= 0xD7A3) or (c >= 0xF900 and c <= 0xFAFF) or
     (c >= 0xFE30 and c <= 0xFE4F) or (c >= 0xFF00 and c <= 0xFF60) or
     (c >= 0xFFE0 and c <= 0xFFE6) or (c >= 0x1F300 and c <= 0x1F64F) or
     (c >= 0x1F900 and c <= 0x1F9FF) or (c >= 0x1F680 and c <= 0x1F6FF) or
     (c >= 0x20000 and c <= 0x3FFFD):
    return 2
  1

proc resetTabs(s: Screen) =
  s.tabs = newSeq[bool](s.cols)
  for i in 0 ..< s.cols: s.tabs[i] = i mod 8 == 0 and i > 0

proc newScreen*(cols, rows: int; scrollback = 3000): Screen =
  ## A screen `cols` x `rows`, empty, the cursor at the top left.
  result = Screen(cols: max(2, cols), rows: max(1, rows), maxScrollback: scrollback,
                  autowrap: true, cursorShown: true)
  result.pen = Cell(fg: defaultInk(), bg: defaultInk())
  for i in 0 ..< result.rows: result.mainLines.add newLine(result.cols, result.pen)
  for i in 0 ..< result.rows: result.altLines.add newLine(result.cols, result.pen)
  result.lines = result.mainLines
  result.top = 0
  result.bottom = result.rows - 1
  result.resetTabs()
  result.changed = true

proc syncLines(s: Screen) =
  ## (`lines` is the shown screen's: kept in its slot)
  if s.alt: s.altLines = s.lines else: s.mainLines = s.lines

proc resize*(s: Screen; cols, rows: int) =
  ## The screen at a new size: lines cut or filled out, rows taken from the
  ## top into the scrollback (or given back from it) so the cursor's line
  ## stays in view.
  let cols = max(2, cols)
  let rows = max(1, rows)
  if cols == s.cols and rows == s.rows: return
  s.syncLines()
  proc fit(ls: var seq[Line]; pen: Cell) =
    for l in ls.mitems:
      if l.len > cols: l.setLen(cols)
      while l.len < cols: l.add blank(pen)
  var main = s.mainLines
  var altl = s.altLines
  fit(main, s.pen)
  fit(altl, s.pen)
  fit(s.scrollback, s.pen)
  # (the main screen: rows to the scrollback when it shrinks under the cursor,
  # back from it when it grows)
  var cy = s.cy
  if rows < s.rows:
    var extra = s.rows - rows
    # (empty lines under the cursor go first)
    while extra > 0 and main.len > rows and main.len - 1 > (if s.alt: main.len - 1 else: cy):
      main.setLen(main.len - 1)
      dec extra
    while main.len > rows:
      s.scrollback.add main[0]
      main.delete(0)
      if not s.alt: dec cy
  else:
    while main.len < rows:
      if s.scrollback.len > 0 and not s.alt:
        main.insert(s.scrollback.pop(), 0)
        inc cy
      else:
        main.add newLine(cols, s.pen)
  while altl.len > rows: altl.setLen(altl.len - 1)
  while altl.len < rows: altl.add newLine(cols, s.pen)
  s.mainLines = main
  s.altLines = altl
  s.lines = if s.alt: s.altLines else: s.mainLines
  s.cols = cols
  s.rows = rows
  if not s.alt: s.cy = cy
  s.cx = clamp(s.cx, 0, cols - 1)
  s.cy = clamp(s.cy, 0, rows - 1)
  s.top = 0
  s.bottom = rows - 1
  s.wrapNext = false
  s.resetTabs()
  while s.scrollback.len > s.maxScrollback: s.scrollback.delete(0)
  s.changed = true

# ---- scrolling ------------------------------------------------------------------------------------

proc scrollUp(s: Screen; n = 1) =
  ## The region's lines up `n` (new empty lines at its bottom); off the top of
  ## the whole main screen they go to the scrollback.
  for _ in 0 ..< n:
    let gone = s.lines[s.top]
    s.lines.delete(s.top)
    s.lines.insert(newLine(s.cols, s.pen), s.bottom)
    if s.top == 0 and not s.alt:
      s.scrollback.add gone
      if s.scrollback.len > s.maxScrollback: s.scrollback.delete(0)
  s.changed = true

proc scrollDown(s: Screen; n = 1) =
  for _ in 0 ..< n:
    s.lines.delete(s.bottom)
    s.lines.insert(newLine(s.cols, s.pen), s.top)
  s.changed = true

proc lineFeed(s: Screen) =
  s.wrapNext = false
  if s.cy == s.bottom: s.scrollUp()
  elif s.cy < s.rows - 1: inc s.cy

proc reverseIndex(s: Screen) =
  s.wrapNext = false
  if s.cy == s.top: s.scrollDown()
  elif s.cy > 0: dec s.cy

# ---- writing characters ---------------------------------------------------------------------------

const lineDrawing = [
  # (DEC's special graphics, for `_` to `~`)
  0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0, 0x00B1, 0x2424,
  0x240B, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C, 0x23BA, 0x23BB, 0x2500, 0x23BC,
  0x23BD, 0x251C, 0x2524, 0x2534, 0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260,
  0x00A3, 0x00B7]

proc put(s: Screen; r: Rune) =
  var r = r
  if s.lineDrawing and int(r) >= 0x5F and int(r) <= 0x7E:
    r = Rune(lineDrawing[int(r) - 0x5F])
  let w = charWidth(r)
  if w == 0:
    return                                  # (marks that combine: not kept)
  if s.wrapNext and s.autowrap:
    s.lineFeed()
    s.cx = 0
  s.wrapNext = false
  if w == 2 and s.cx == s.cols - 1:
    # (a wide character does not fit at the end: on the next line)
    if s.autowrap:
      s.lines[s.cy][s.cx] = blank(s.pen)
      s.lineFeed()
      s.cx = 0
    else: return
  if s.insert:
    var l = s.lines[s.cy]
    for _ in 0 ..< w:
      l.insert(blank(s.pen), s.cx)
      l.setLen(s.cols)
    s.lines[s.cy] = l
  var c = s.pen
  c.ch = r
  c.wide2 = false
  s.lines[s.cy][s.cx] = c
  if w == 2:
    var c2 = s.pen
    c2.ch = Rune(0)
    c2.wide2 = true
    s.lines[s.cy][s.cx + 1] = c2
  s.lastChar = r
  if s.cx + w >= s.cols:
    s.cx = s.cols - 1
    s.wrapNext = true
  else:
    s.cx += w
  s.changed = true

# ---- erasing --------------------------------------------------------------------------------------

proc eraseCells(s: Screen; y, x0, x1: int) =
  let b = blank(s.pen)
  for x in max(0, x0) .. min(s.cols - 1, x1):
    s.lines[y][x] = b
  s.changed = true

proc eraseDisplay(s: Screen; mode: int) =
  case mode
  of 0:
    s.eraseCells(s.cy, s.cx, s.cols - 1)
    for y in s.cy + 1 ..< s.rows: s.eraseCells(y, 0, s.cols - 1)
  of 1:
    for y in 0 ..< s.cy: s.eraseCells(y, 0, s.cols - 1)
    s.eraseCells(s.cy, 0, s.cx)
  of 2:
    for y in 0 ..< s.rows: s.eraseCells(y, 0, s.cols - 1)
  of 3:
    s.scrollback.setLen(0)
    s.changed = true
  else: discard

proc eraseLine(s: Screen; mode: int) =
  case mode
  of 0: s.eraseCells(s.cy, s.cx, s.cols - 1)
  of 1: s.eraseCells(s.cy, 0, s.cx)
  of 2: s.eraseCells(s.cy, 0, s.cols - 1)
  else: discard

# ---- modes --------------------------------------------------------------------------------------

proc setAlt(s: Screen; on, clear, saveCursor: bool) =
  if on == s.alt: return
  if on and saveCursor: s.saved = (s.cx, s.cy, s.pen, s.origin, s.lineDrawing)
  s.syncLines()
  s.alt = on
  s.lines = if on: s.altLines else: s.mainLines
  if on and clear:
    for y in 0 ..< s.rows: s.lines[y] = newLine(s.cols, s.pen)
  if not on and saveCursor:
    (s.cx, s.cy, s.pen, s.origin, s.lineDrawing) = s.saved
  s.top = 0
  s.bottom = s.rows - 1
  s.wrapNext = false
  s.changed = true

proc setMode(s: Screen; private: bool; n: int; on: bool) =
  if private:
    case n
    of 1: s.appCursor = on
    of 6:
      s.origin = on
      s.cx = 0
      s.cy = if on: s.top else: 0
    of 7: s.autowrap = on
    of 25: s.cursorShown = on
    of 47, 1047: s.setAlt(on, n == 1047, false)
    of 1048:
      if on: s.saved = (s.cx, s.cy, s.pen, s.origin, s.lineDrawing)
      else: (s.cx, s.cy, s.pen, s.origin, s.lineDrawing) = s.saved
    of 1049: s.setAlt(on, true, true)
    of 1000: s.mouse = (if on: mmClicks else: mmNone)
    of 1002: s.mouse = (if on: mmDrags else: mmNone)
    of 1003: s.mouse = (if on: mmMotion else: mmNone)
    of 1004: s.focusReports = on
    of 1006: s.mouseSgr = on
    of 2004: s.bracketedPaste = on
    else: discard
  else:
    case n
    of 4: s.insert = on
    of 20: discard                     # (LNM: no)
    else: discard
  s.changed = true

proc reset*(s: Screen) =
  ## Everything as when the terminal opened (RIS), the scrollback kept.
  s.setAlt(false, false, false)
  s.pen = Cell(fg: defaultInk(), bg: defaultInk())
  for y in 0 ..< s.rows: s.lines[y] = newLine(s.cols, s.pen)
  s.cx = 0
  s.cy = 0
  s.top = 0
  s.bottom = s.rows - 1
  s.origin = false
  s.autowrap = true
  s.insert = false
  s.lineDrawing = false
  s.appCursor = false
  s.appKeypad = false
  s.cursorShown = true
  s.bracketedPaste = false
  s.mouse = mmNone
  s.mouseSgr = false
  s.wrapNext = false
  s.resetTabs()
  s.changed = true

# ---- SGR: colors and attributes --------------------------------------------------------------------

proc sgr(s: Screen; ps: seq[int]) =
  var ps = ps
  if ps.len == 0: ps = @[0]
  var i = 0
  while i < ps.len:
    let p = ps[i]
    case p
    of 0:
      s.pen.attrs = {}
      s.pen.fg = defaultInk()
      s.pen.bg = defaultInk()
    of 1: s.pen.attrs.incl aBold
    of 2: s.pen.attrs.incl aDim
    of 3: s.pen.attrs.incl aItalic
    of 4: s.pen.attrs.incl aUnderline
    of 5, 6: s.pen.attrs.incl aBlink
    of 7: s.pen.attrs.incl aReverse
    of 8: s.pen.attrs.incl aHidden
    of 9: s.pen.attrs.incl aStrike
    of 21, 22: s.pen.attrs.excl aBold; s.pen.attrs.excl aDim
    of 23: s.pen.attrs.excl aItalic
    of 24: s.pen.attrs.excl aUnderline
    of 25: s.pen.attrs.excl aBlink
    of 27: s.pen.attrs.excl aReverse
    of 28: s.pen.attrs.excl aHidden
    of 29: s.pen.attrs.excl aStrike
    of 30 .. 37: s.pen.fg = paletteInk(p - 30)
    of 39: s.pen.fg = defaultInk()
    of 40 .. 47: s.pen.bg = paletteInk(p - 40)
    of 49: s.pen.bg = defaultInk()
    of 90 .. 97: s.pen.fg = paletteInk(p - 90 + 8)
    of 100 .. 107: s.pen.bg = paletteInk(p - 100 + 8)
    of 38, 48:
      var ink = defaultInk()
      if i + 1 < ps.len and ps[i + 1] == 5 and i + 2 < ps.len:
        ink = paletteInk(ps[i + 2])
        i += 2
      elif i + 1 < ps.len and ps[i + 1] == 2 and i + 4 < ps.len:
        ink = rgbInk(ps[i + 2], ps[i + 3], ps[i + 4])
        i += 4
      if p == 38: s.pen.fg = ink else: s.pen.bg = ink
    else: discard
    inc i

# ---- the parser ---------------------------------------------------------------------------------

proc param(s: Screen; i: int; default: int): int =
  if i < s.params.len and s.params[i] > 0: s.params[i] else: default

proc rowBase(s: Screen): int = (if s.origin: s.top else: 0)

proc csi(s: Screen; final: char) =
  let p1 = s.param(0, 1)
  case final
  of '@':
    if s.privMark == '\0':
      var l = s.lines[s.cy]
      for _ in 0 ..< min(p1, s.cols - s.cx):
        l.insert(blank(s.pen), s.cx)
        l.setLen(s.cols)
      s.lines[s.cy] = l
  of 'A': s.cy = max(if s.cy >= s.top: s.top else: 0, s.cy - p1)
  of 'B', 'e': s.cy = min(if s.cy <= s.bottom: s.bottom else: s.rows - 1, s.cy + p1)
  of 'C', 'a': s.cx = min(s.cols - 1, s.cx + p1)
  of 'D': s.cx = max(0, s.cx - p1)
  of 'E':
    s.cy = min(s.bottom, s.cy + p1)
    s.cx = 0
  of 'F':
    s.cy = max(s.top, s.cy - p1)
    s.cx = 0
  of 'G', '`': s.cx = clamp(p1 - 1, 0, s.cols - 1)
  of 'H', 'f':
    s.cy = clamp(s.rowBase + s.param(0, 1) - 1, 0, s.rows - 1)
    s.cx = clamp(s.param(1, 1) - 1, 0, s.cols - 1)
  of 'I':
    for _ in 0 ..< p1:
      var x = s.cx + 1
      while x < s.cols - 1 and not s.tabs[x]: inc x
      s.cx = min(x, s.cols - 1)
  of 'J': s.eraseDisplay(if s.params.len > 0: s.params[0] else: 0)
  of 'K': s.eraseLine(if s.params.len > 0: s.params[0] else: 0)
  of 'L':
    if s.cy >= s.top and s.cy <= s.bottom:
      for _ in 0 ..< min(p1, s.bottom - s.cy + 1):
        s.lines.delete(s.bottom)
        s.lines.insert(newLine(s.cols, s.pen), s.cy)
      s.cx = 0
  of 'M':
    if s.cy >= s.top and s.cy <= s.bottom:
      for _ in 0 ..< min(p1, s.bottom - s.cy + 1):
        s.lines.delete(s.cy)
        s.lines.insert(newLine(s.cols, s.pen), s.bottom)
      s.cx = 0
  of 'P':
    var l = s.lines[s.cy]
    for _ in 0 ..< min(p1, s.cols - s.cx):
      l.delete(s.cx)
      l.add blank(s.pen)
    s.lines[s.cy] = l
  of 'S': s.scrollUp(p1)
  of 'T':
    if s.params.len <= 1: s.scrollDown(p1)
  of 'X': s.eraseCells(s.cy, s.cx, s.cx + p1 - 1)
  of 'Z':
    for _ in 0 ..< p1:
      var x = s.cx - 1
      while x > 0 and not s.tabs[x]: dec x
      s.cx = max(0, x)
  of 'b':
    if int(s.lastChar) != 0:
      for _ in 0 ..< min(p1, 2000): s.put(s.lastChar)
  of 'c':
    if s.privMark == '>': s.replies.add "\e[>1;95;0c"
    elif s.privMark == '\0': s.replies.add "\e[?62;22c"
  of 'd': s.cy = clamp(s.rowBase + p1 - 1, 0, s.rows - 1)
  of 'g':
    let m = if s.params.len > 0: s.params[0] else: 0
    if m == 0: s.tabs[s.cx] = false
    elif m == 3:
      for i in 0 ..< s.cols: s.tabs[i] = false
  of 'h', 'l':
    for n in s.params: s.setMode(s.privMark == '?', n, final == 'h')
  of 'm':
    if s.privMark == '\0': s.sgr(s.params)
  of 'n':
    if s.privMark == '\0':
      case (if s.params.len > 0: s.params[0] else: 0)
      of 5: s.replies.add "\e[0n"
      of 6: s.replies.add "\e[" & $(s.cy - s.rowBase + 1) & ";" & $(s.cx + 1) & "R"
      else: discard
  of 'p':
    if s.interm == '!': s.reset()             # DECSTR
  of 'r':
    if s.privMark == '\0':
      let t = s.param(0, 1) - 1
      let b = s.param(1, s.rows) - 1
      if t < b and b < s.rows:
        s.top = t
        s.bottom = b
        s.cx = 0
        s.cy = s.rowBase
  of 's':
    if s.privMark == '\0': s.saved = (s.cx, s.cy, s.pen, s.origin, s.lineDrawing)
  of 'u':
    if s.privMark == '\0': (s.cx, s.cy, s.pen, s.origin, s.lineDrawing) = s.saved
  else: discard
  s.wrapNext = false
  s.changed = true

proc oscDone(s: Screen) =
  let semi = s.osc.find(';')
  if semi > 0:
    let what = s.osc[0 ..< semi]
    if what == "0" or what == "2": s.title = s.osc[semi + 1 .. ^1]
  s.osc.setLen(0)

proc escFinal(s: Screen; c: char) =
  case c
  of '7': s.saved = (s.cx, s.cy, s.pen, s.origin, s.lineDrawing)
  of '8': (s.cx, s.cy, s.pen, s.origin, s.lineDrawing) = s.saved
  of 'D': s.lineFeed()
  of 'E':
    s.lineFeed()
    s.cx = 0
  of 'H': s.tabs[s.cx] = true
  of 'M': s.reverseIndex()
  of 'c': s.reset()
  of '=': s.appKeypad = true
  of '>': s.appKeypad = false
  else: discard
  s.changed = true

proc control(s: Screen; c: char) =
  case c
  of '\a': s.bell = true
  of '\b':
    if s.cx > 0: dec s.cx
    s.wrapNext = false
  of '\t':
    var x = s.cx + 1
    while x < s.cols - 1 and not s.tabs[x]: inc x
    s.cx = min(x, s.cols - 1)
  of '\n', '\v', '\f': s.lineFeed()
  of '\r':
    s.cx = 0
    s.wrapNext = false
  of '\x0E': s.lineDrawing = true             # (SO: G1, line drawing here)
  of '\x0F': s.lineDrawing = false
  else: discard
  s.changed = true

proc feedByte(s: Screen; b: char) =
  case s.state
  of stGround:
    discard
  of stEsc:
    case b
    of '[':
      s.state = stCsi
      s.params.setLen(0)
      s.curParam = 0
      s.hasParam = false
      s.privMark = '\0'
      s.interm = '\0'
    of ']':
      s.state = stOsc
      s.osc.setLen(0)
    of '(', ')', '*', '+': s.state = stCharset; s.interm = b
    of 'P', 'X', '^', '_': s.state = stDcs
    of ' ', '#', '%': s.state = stEscInterm
    else:
      s.state = stGround
      s.escFinal(b)
    return
  of stEscInterm:
    s.state = stGround
    return
  of stCharset:
    if s.interm == '(': s.lineDrawing = b == '0'
    s.state = stGround
    return
  of stCsi:
    case b
    of '0' .. '9':
      s.curParam = min(s.curParam * 10 + (ord(b) - ord('0')), 100000)
      s.hasParam = true
    of ';', ':':
      s.params.add s.curParam
      s.curParam = 0
      s.hasParam = false
    of '?', '>', '<', '=':
      s.privMark = b
    of ' ', '!', '"', '$', '\'':
      s.interm = b
    of '@' .. '~':
      if s.hasParam or s.params.len > 0: s.params.add s.curParam
      s.state = stGround
      s.csi(b)
    of '\x18', '\x1A': s.state = stGround
    else: discard
    return
  of stOsc:
    case b
    of '\a':
      s.oscDone()
      s.state = stGround
    of '\e': s.state = stOscEsc
    else:
      if s.osc.len < 4096: s.osc.add b
    return
  of stOscEsc:
    s.oscDone()
    s.state = stGround
    if b != '\\':
      s.state = stEsc
      s.feedByte(b)
    return
  of stDcs:
    if b == '\e': s.state = stDcsEsc
    elif b == '\a': s.state = stGround
    return
  of stDcsEsc:
    s.state = if b == '\\': stGround else: stDcs
    return
  else:
    s.state = stGround

proc feed*(s: Screen; data: string) =
  ## What the program wrote: text (UTF-8) and escape sequences.
  for b in data:
    let c = ord(b)
    if s.state != stGround and s.state != stOsc and s.state != stDcs and c < 0x20 and
       b != '\e':
      # (controls act in the middle of a sequence too)
      s.control(b)
      continue
    if s.state != stGround:
      if b == '\e' and s.state notin {stOsc, stDcs, stDcsEsc, stOscEsc}:
        s.state = stEsc
        continue
      s.feedByte(b)
      continue
    if s.utf8Need > 0:
      if (c and 0xC0) == 0x80:
        s.utf8Cp = (s.utf8Cp shl 6) or int32(c and 0x3F)
        inc s.utf8Have
        if s.utf8Have == s.utf8Need:
          s.utf8Need = 0
          s.put(Rune(s.utf8Cp))
        continue
      else:
        s.utf8Need = 0
        s.put(Rune(0xFFFD))
    if c < 0x20:
      if b == '\e': s.state = stEsc
      else: s.control(b)
    elif c == 0x7F: discard
    elif c < 0x80: s.put(Rune(c))
    elif (c and 0xE0) == 0xC0:
      s.utf8Need = 1; s.utf8Have = 0; s.utf8Cp = int32(c and 0x1F)
    elif (c and 0xF0) == 0xE0:
      s.utf8Need = 2; s.utf8Have = 0; s.utf8Cp = int32(c and 0x0F)
    elif (c and 0xF8) == 0xF0:
      s.utf8Need = 3; s.utf8Have = 0; s.utf8Cp = int32(c and 0x07)
    else: s.put(Rune(0xFFFD))

# ---- reading it back ------------------------------------------------------------------------------

proc lineAt*(s: Screen; row, view: int): Line =
  ## The line shown at `row` when the view is `view` lines back in the
  ## scrollback (0: the screen itself).
  let i = row - view
  if i >= 0: s.lines[i]
  else:
    let k = s.scrollback.len + i
    if k >= 0: s.scrollback[k] else: newLine(s.cols, Cell(fg: defaultInk(), bg: defaultInk()))

proc lineText*(l: Line; x0 = 0; x1 = -1): string =
  ## The text of a line (from `x0` to `x1`, the end when -1), the spaces at
  ## its end left off.
  let last = if x1 < 0: l.high else: min(x1, l.high)
  for x in max(0, x0) .. last:
    if l[x].wide2: continue
    if int(l[x].ch) == 0: result.add ' ' else: result.add $l[x].ch
  result = result.strip(leading = false, trailing = true, chars = {' '})
