## The desktop's own pictures, drawn at the size they are shown at (sharp on
## any screen): the icons of its programs, in the flat, outlined colors of
## 3.1's icons, and the desktop's patterns.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[math, tables, strutils]
import retroui
import retroui/canvas2d

const
  Black = "#000000"
  White = "#ffffff"
  Gray = "#c0c0c0"
  Dark = "#808080"
  Navy = "#000080"
  TealC = "#008080"
  Yellow = "#ffff00"
  Red = "#c00000"
  Green = "#008000"
  Cyan = "#00ffff"
  Blue = "#0000ff"

var cache: Table[string, Bitmap]

proc box(c: Canvas2D; x, y, w, h: float; fillC: string; line = Black) =
  c.fillStyle = fillC
  c.fillRect(x, y, w, h)
  c.strokeStyle = line
  c.lineWidth = 1
  c.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1)

proc windowShape(c: Canvas2D; x, y, w, h: float; title = Navy) =
  ## A little window: its frame, title bar and white inside.
  box(c, x, y, w, h, White)
  c.fillStyle = title
  c.fillRect(x + 1, y + 1, w - 2, 5)
  c.fillStyle = Black
  c.fillRect(x + 1, y + 6, w - 2, 1)

proc drawIcon(c: Canvas2D; kind: string) =
  ## `kind` drawn on a 32 x 32 grid (the canvas is scaled to the size).
  case kind
  of "progman":
    windowShape(c, 2, 4, 28, 24)
    for i in 0 .. 2:
      box(c, 5 + float(i) * 8, 13, 6, 6, [Yellow, Cyan, "#ff80ff"][i])
    c.fillStyle = Dark
    for i in 0 .. 2: c.fillRect(5 + float(i) * 8, 21, 6, 2)
  of "clock":
    c.fillStyle = Black
    c.beginPath(); c.arc(16, 16, 14, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.beginPath(); c.arc(16, 16, 12.5, 0, 2 * PI); c.fill()
    c.fillStyle = Navy
    for i in 0 ..< 12:
      let a = float(i) * PI / 6
      c.fillRect(16 + sin(a) * 10.5 - 0.75, 16 - cos(a) * 10.5 - 0.75, 1.5, 1.5)
    c.strokeStyle = Black
    c.lineWidth = 2
    c.beginPath(); c.moveTo(16, 16); c.lineTo(16, 8); c.stroke()
    c.beginPath(); c.moveTo(16, 16); c.lineTo(22, 18); c.stroke()
    c.strokeStyle = Red
    c.lineWidth = 1
    c.beginPath(); c.moveTo(16, 16); c.lineTo(11, 25); c.stroke()
  of "calc":
    box(c, 6, 2, 20, 28, Gray)
    box(c, 9, 5, 14, 6, "#c0ffc0")
    c.fillStyle = Black
    c.font = "bold 5px monospace"
    c.textAlign = "right"
    c.textBaseline = "middle"
    c.fillText("42", 22, 8.3)
    for r in 0 .. 3:
      for k in 0 .. 2:
        box(c, 9 + float(k) * 5, 13 + float(r) * 4, 4, 3,
            (if k == 2 and r == 3: Red else: White))
  of "calendar":
    box(c, 3, 4, 26, 25, White)
    c.fillStyle = Red
    c.fillRect(4, 5, 24, 6)
    c.fillStyle = Black
    for k in 0 .. 1: c.fillRect(9 + float(k) * 12, 2, 2, 5)
    c.fillStyle = Dark
    for r in 0 .. 3:
      for k in 0 .. 5:
        c.fillRect(6 + float(k) * 3.8, 13.5 + float(r) * 3.8, 2.4, 2.4)
    c.fillStyle = Blue
    c.fillRect(6 + 3 * 3.8, 13.5 + 2 * 3.8, 2.4, 2.4)
  of "cardfile":
    for i in 0 .. 2:
      let o = float(i) * 3
      box(c, 2 + o, 13 - o, 24, 16, (if i == 2: White else: "#ffffc0"))
      c.fillStyle = Red
      c.fillRect(3 + o, 14 - o + 2, 22, 1)
    c.fillStyle = Dark
    for k in 0 .. 2: c.fillRect(11, 15 + float(k) * 3, 12, 1)
  of "control":
    box(c, 3, 5, 26, 18, Gray)
    box(c, 6, 8, 20, 12, TealC)
    box(c, 11, 23, 10, 3, Gray)
    box(c, 7, 26, 18, 3, Gray)
    c.fillStyle = Yellow
    c.beginPath(); c.arc(12, 13, 2.5, 0, 2 * PI); c.fill()
    c.fillStyle = "#00c000"
    c.beginPath(); c.moveTo(7, 19); c.lineTo(15, 12); c.lineTo(20, 16); c.lineTo(25, 13)
    c.lineTo(25, 19); c.closePath(); c.fill()
  of "tasklist":
    windowShape(c, 3, 3, 26, 26)
    for r in 0 .. 3:
      c.fillStyle = (if r == 1: Navy else: Dark)
      c.fillRect(6, 11 + float(r) * 4, 20, 2.5)
  of "notepad":
    box(c, 6, 3, 20, 27, White)
    c.fillStyle = Blue
    for r in 0 .. 5: c.fillRect(8, 9 + float(r) * 3.5, 16, 1)
    c.fillStyle = Dark
    for k in 0 .. 4: c.fillRect(8 + float(k) * 4, 2, 2, 4)
  of "files":
    box(c, 6, 3, 20, 27, Gray)
    for r in 0 .. 2:
      box(c, 8, 5 + float(r) * 8.3, 16, 7, "#d8d8d8")
      c.fillStyle = Black
      c.fillRect(14, 8 + float(r) * 8.3, 4, 1.5)
  of "paint", "photo":
    c.fillStyle = "#e0c090"
    c.beginPath(); c.arc(15, 17, 13, 0, 2 * PI); c.fill()
    c.strokeStyle = Black
    c.lineWidth = 1
    c.beginPath(); c.arc(15, 17, 13, 0, 2 * PI); c.stroke()
    for i, col in [Red, Blue, Green, Yellow, "#ff00ff"]:
      let a = float(i) * 0.9 + 2.2
      c.fillStyle = col
      c.beginPath(); c.arc(15 + cos(a) * 8, 17 + sin(a) * 8, 2.6, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.beginPath(); c.arc(21, 21, 2.5, 0, 2 * PI); c.fill()
    c.strokeStyle = "#804000"
    c.lineWidth = 2.5
    c.beginPath(); c.moveTo(29, 2); c.lineTo(17, 15); c.stroke()
  of "board":
    box(c, 2, 4, 28, 20, White)
    box(c, 2, 24, 28, 2, Dark)
    c.fillStyle = Dark
    c.fillRect(8, 26, 2, 5); c.fillRect(22, 26, 2, 5)
    c.strokeStyle = Red
    c.lineWidth = 1.5
    c.strokeRect(6, 8, 9, 6)
    c.strokeStyle = Blue
    c.beginPath(); c.moveTo(15, 11); c.lineTo(20, 16); c.stroke()
    c.beginPath(); c.arc(23, 17, 3, 0, 2 * PI); c.stroke()
  of "terminal":
    windowShape(c, 2, 4, 28, 24)
    c.fillStyle = Black
    c.fillRect(3, 11, 26, 16)
    c.fillStyle = Gray
    c.font = "bold 7px monospace"
    c.textAlign = "left"
    c.textBaseline = "middle"
    c.fillText("$_", 5, 16)
  of "browser":
    # (a globe: the sea, the lands, the lines of a map)
    c.fillStyle = Navy
    c.beginPath(); c.arc(16, 16, 13, 0, 2 * PI); c.fill()
    c.fillStyle = "#0080ff"
    c.beginPath(); c.arc(16, 16, 12, 0, 2 * PI); c.fill()
    c.fillStyle = "#00a000"
    c.beginPath(); c.moveTo(8, 9); c.lineTo(14, 7); c.lineTo(16, 12); c.lineTo(12, 17)
    c.lineTo(9, 15); c.closePath(); c.fill()
    c.beginPath(); c.moveTo(18, 15); c.lineTo(24, 13); c.lineTo(26, 19); c.lineTo(21, 26)
    c.lineTo(18, 22); c.closePath(); c.fill()
    c.strokeStyle = White
    c.lineWidth = 0.8
    c.beginPath(); c.moveTo(4, 16); c.lineTo(28, 16); c.stroke()
    c.beginPath(); c.arc(16, 16, 12, -PI / 2, PI / 2); c.stroke()
  of "mail":
    box(c, 3, 8, 26, 17, White)
    c.strokeStyle = Black
    c.lineWidth = 1
    c.beginPath(); c.moveTo(3.5, 8.5); c.lineTo(16, 18); c.lineTo(28.5, 8.5); c.stroke()
  of "gallery":
    box(c, 3, 5, 26, 22, White)
    c.fillStyle = Cyan
    c.fillRect(5, 7, 22, 12)
    c.fillStyle = Green
    c.beginPath(); c.moveTo(5, 19); c.lineTo(13, 11); c.lineTo(20, 19); c.closePath(); c.fill()
    c.fillStyle = Yellow
    c.beginPath(); c.arc(22, 11, 2.5, 0, 2 * PI); c.fill()
  of "run":
    windowShape(c, 3, 6, 26, 18)
    box(c, 6, 15, 20, 5, White)
    c.fillStyle = Black
    c.fillRect(8, 17, 6, 1)
  of "readme":
    box(c, 6, 3, 20, 27, White)
    c.fillStyle = Navy
    c.font = "bold 12px serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("i", 16, 13)
    c.fillStyle = Dark
    for r in 0 .. 2: c.fillRect(9, 20 + float(r) * 3, 14, 1)
  of "group":
    # (a Program Manager group, minimized)
    box(c, 3, 6, 26, 20, White)
    c.fillStyle = Navy
    c.fillRect(4, 7, 24, 4)
    for i in 0 .. 2:
      c.fillStyle = [Yellow, Cyan, Red][i]
      c.fillRect(6 + float(i) * 8, 15, 4, 4)
  of "window":
    windowShape(c, 3, 5, 26, 22)
  of "setup":
    # (a box of programs, and a disk going in)
    box(c, 4, 13, 20, 16, "#c08040")
    c.fillStyle = "#804000"
    c.fillRect(5, 17, 18, 1)
    box(c, 15, 3, 14, 14, Navy)
    box(c, 18, 4, 8, 5, Gray)
    box(c, 18, 11, 8, 5, White)
    c.fillStyle = Black
    c.fillRect(23, 5, 2, 3)
  of "mines":
    # (a mine: the ball, its spikes, the shine)
    c.strokeStyle = Black
    c.lineWidth = 2
    for k in 0 ..< 4:
      let a = float(k) * PI / 4
      c.beginPath()
      c.moveTo(16 - cos(a) * 13, 16 - sin(a) * 13)
      c.lineTo(16 + cos(a) * 13, 16 + sin(a) * 13)
      c.stroke()
    c.fillStyle = Black
    c.beginPath(); c.arc(16, 16, 8.5, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.fillRect(12, 12, 3, 3)
  of "cards":
    box(c, 3, 6, 16, 22, White)
    c.fillStyle = Red
    c.font = "bold 9px serif"
    c.textAlign = "left"
    c.textBaseline = "top"
    c.fillText("A", 5, 7)
    c.beginPath(); c.moveTo(11, 14); c.lineTo(14, 18); c.lineTo(11, 22); c.lineTo(8, 18); c.closePath(); c.fill()
    box(c, 13, 3, 16, 22, Navy)
    c.strokeStyle = "#4040ff"
    c.lineWidth = 1
    for k in 0 ..< 5:
      c.beginPath(); c.moveTo(15, 6 + float(k) * 4); c.lineTo(27, 6 + float(k) * 4); c.stroke()
  of "reversi":
    box(c, 2, 2, 28, 28, Green)
    c.strokeStyle = "#004000"
    c.lineWidth = 1
    for k in 1 .. 3:
      c.beginPath(); c.moveTo(2 + float(k) * 7, 2); c.lineTo(2 + float(k) * 7, 30); c.stroke()
      c.beginPath(); c.moveTo(2, 2 + float(k) * 7); c.lineTo(30, 2 + float(k) * 7); c.stroke()
    for (x, y, ink) in [(12.5, 12.5, Black), (19.5, 19.5, Black), (19.5, 12.5, White), (12.5, 19.5, White)]:
      c.fillStyle = ink
      c.beginPath(); c.arc(x, y, 3, 0, 2 * PI); c.fill()
  of "write":
    box(c, 6, 3, 20, 26, White)
    c.fillStyle = Navy
    c.font = "bold 13px serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("A", 13, 11)
    c.fillStyle = Dark
    for r in 0 .. 3: c.fillRect(9, 17 + float(r) * 3, 14 - float(r mod 2) * 4, 1)
    # (a pen across the page)
    c.strokeStyle = Black
    c.lineWidth = 2.5
    c.beginPath(); c.moveTo(29, 6); c.lineTo(19, 22); c.stroke()
    c.strokeStyle = Yellow
    c.lineWidth = 1.2
    c.beginPath(); c.moveTo(29, 6); c.lineTo(19.5, 21); c.stroke()
  of "clipboard":
    box(c, 5, 5, 22, 25, "#c08040")
    box(c, 8, 9, 16, 18, White)
    box(c, 11, 2, 10, 6, Gray)
    c.fillStyle = Dark
    for r in 0 .. 3: c.fillRect(10, 12 + float(r) * 3.5, 12, 1)
  of "datetime":
    box(c, 2, 5, 20, 22, White)
    c.fillStyle = Red
    c.fillRect(3, 6, 18, 5)
    c.fillStyle = Black
    c.font = "bold 10px sans-serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("31", 12, 19)
    c.fillStyle = Black
    c.beginPath(); c.arc(23, 21, 8, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.beginPath(); c.arc(23, 21, 6.8, 0, 2 * PI); c.fill()
    c.strokeStyle = Black
    c.lineWidth = 1.3
    c.beginPath(); c.moveTo(23, 21); c.lineTo(23, 16); c.moveTo(23, 21); c.lineTo(26, 22); c.stroke()
  of "saver":
    box(c, 2, 3, 28, 21, Gray)
    c.fillStyle = Black
    c.fillRect(4, 5, 24, 17)
    c.fillStyle = White
    for (x, y) in [(7.0, 8.0), (13.0, 14.0), (20.0, 9.0), (24.0, 17.0), (10.0, 19.0), (17.0, 18.0)]:
      c.fillRect(x, y, 1.5, 1.5)
    c.fillStyle = Yellow
    c.fillRect(15, 11, 2, 2)
    box(c, 11, 24, 10, 3, Gray)
    box(c, 6, 27, 20, 3, Gray)
  of "logo":
    # (Retro Desktop's: a screen with a setting sun over the sea)
    box(c, 2, 3, 28, 21, Gray)
    c.fillStyle = Navy
    c.fillRect(4, 5, 24, 17)
    c.fillStyle = "#ff8000"
    c.beginPath(); c.arc(16, 15, 6, PI, 2 * PI); c.fill()
    c.fillStyle = TealC
    c.fillRect(4, 15, 24, 7)
    c.fillStyle = Yellow
    for k in 0 .. 2: c.fillRect(10 + float(k) * 4, 17 + float(k), 4 - float(k), 1)
    box(c, 11, 24, 10, 3, Gray)
    box(c, 6, 27, 20, 3, Gray)
  else:
    # (a program: a window with a gear)
    windowShape(c, 2, 4, 28, 24, TealC)
    c.fillStyle = Dark
    c.beginPath(); c.arc(16, 18, 6, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.beginPath(); c.arc(16, 18, 2.5, 0, 2 * PI); c.fill()
    c.fillStyle = Dark
    for i in 0 ..< 6:
      let a = float(i) * PI / 3
      c.fillRect(16 + cos(a) * 7 - 1.3, 18 + sin(a) * 7 - 1.3, 2.6, 2.6)

proc appIcon*(kind: string; size: int): Bitmap =
  ## The desktop's icon `kind` (progman, clock, calc, calendar, cardfile,
  ## control, tasklist, notepad, files, paint, photo, board, terminal, mail,
  ## gallery, run, readme, group, window, logo, setup, mines, cards, reversi,
  ## write, clipboard, datetime, saver; anything else: a program's)
  ## at `size` pixels, kept for the next time.
  let key = kind & "@" & $size
  if cache.hasKey(key): return cache[key]
  let c = newCanvas2D(size, size)
  c.scale(float(size) / 32, float(size) / 32)
  drawIcon(c, kind)
  result = c.toBitmap
  if cache.len > 200: cache.clear()
  cache[key] = result

proc forgetIcons*() =
  ## Lets the icons go (memory runs short; the screen's size changed).
  cache.clear()

# ---- the desktop's patterns --------------------------------------------------------------------------

const Patterns* = [
  ## 3.1's desktop patterns: eight rows of eight dots each (a bit set: a dot
  ## in the text color over the desktop's color).
  ("(None)", ""),
  ("50% Gray", "170 85 170 85 170 85 170 85"),
  ("Boxes", "127 65 65 65 65 65 127 0"),
  ("Critters", "0 80 114 32 0 5 39 2"),
  ("Diamonds", "32 80 136 80 32 0 0 0"),
  ("Paisley", "2 7 7 2 32 80 80 32"),
  ("Quilt", "130 68 40 17 40 68 130 1"),
  ("Scottie", "64 192 200 120 120 72 0 0"),
  ("Spinner", "20 12 200 121 158 19 48 40"),
  ("Thatches", "248 116 34 71 143 23 34 113"),
  ("Tulip", "0 0 84 124 124 56 146 124"),
  ("Waffle", "0 0 0 0 128 128 128 240"),
  ("Weave", "136 84 34 69 136 21 34 81")]

proc patternTile*(name: string; dot: int; bg, fg: Color; tiles = 16): Bitmap =
  ## The pattern `name` as a picture `tiles` x `tiles` of its 8 x 8 cells,
  ## each dot `dot` pixels (nil for "(None)").
  var rows = ""
  for (n, r) in Patterns:
    if n == name: rows = r
  if rows.len == 0: return nil
  var bits: seq[int]
  for p in rows.splitWhitespace:
    try: bits.add parseInt(p) except ValueError: bits.add 0
  if bits.len != 8: return nil
  let d = max(1, dot)
  let side = 8 * d * tiles
  result = newBitmap(side, side)
  let b = 0xFF000000'u32 or (uint32(bg.r) shl 16) or (uint32(bg.g) shl 8) or uint32(bg.b)
  let f = 0xFF000000'u32 or (uint32(fg.r) shl 16) or (uint32(fg.g) shl 8) or uint32(fg.b)
  for y in 0 ..< side:
    let row = bits[(y div d) mod 8]
    for x in 0 ..< side:
      let bit = (row shr (7 - (x div d) mod 8)) and 1
      result.px[y * side + x] = (if bit == 1: f else: b)
  result.opaque = true
