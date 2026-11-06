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
  of "sound":
    # (a loudspeaker and its waves)
    c.fillStyle = Black
    c.fillRect(4, 12, 7, 8)
    c.beginPath(); c.moveTo(11, 12); c.lineTo(18, 6); c.lineTo(18, 26); c.lineTo(11, 20); c.closePath(); c.fill()
    c.strokeStyle = Navy
    c.lineWidth = 1.6
    for k in 1 .. 3:
      c.beginPath(); c.arc(18, 16, 3.5 * float(k), -PI / 4, PI / 4); c.stroke()
  of "dos":
    windowShape(c, 2, 4, 28, 24)
    c.fillStyle = Black
    c.fillRect(3, 11, 26, 16)
    c.fillStyle = Gray
    c.font = "bold 6px monospace"
    c.textAlign = "left"
    c.textBaseline = "middle"
    c.fillText("C:\\>", 4, 16)
  of "doom":
    box(c, 3, 3, 26, 26, "#400000")
    c.fillStyle = "#ff4000"
    c.font = "bold 9px sans-serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("FREE", 16, 12)
    c.fillStyle = Yellow
    c.fillText("DOOM", 16, 21)
  of "storage":
    # (a phone with a folder)
    box(c, 9, 2, 14, 28, Black)
    c.fillStyle = "#4080ff"
    c.fillRect(11, 5, 10, 20)
    c.fillStyle = Yellow
    c.fillRect(12, 12, 8, 7)
    c.fillRect(12, 11, 4, 2)
  of "help":
    box(c, 4, 4, 24, 24, Yellow)
    c.fillStyle = Navy
    c.font = "bold 18px serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("?", 16, 17)
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
  of "charmap":
    # (a grid of letters, one of them larger)
    box(c, 2, 4, 28, 24, White)
    c.strokeStyle = Gray
    c.lineWidth = 1
    for k in 1 .. 3:
      c.beginPath(); c.moveTo(2 + float(k) * 7, 4); c.lineTo(2 + float(k) * 7, 28); c.stroke()
      c.beginPath(); c.moveTo(2, 4 + float(k) * 6); c.lineTo(30, 4 + float(k) * 6); c.stroke()
    c.fillStyle = Black
    c.font = "4.5px serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    for (x, y, s) in [(5.5, 7.0, "A"), (12.5, 7.0, "&"), (26.5, 7.0, "$"), (5.5, 13.0, "€"),
                      (5.5, 19.0, "Ω"), (26.5, 25.0, "#"), (12.5, 25.0, "@")]:
      c.fillText(s, x, y)
    box(c, 13, 9, 15, 15, White, Navy)
    c.fillStyle = Navy
    c.font = "bold 12px serif"
    c.fillText("ß", 20.5, 17)
  of "pictures":
    # (a framed picture: the hills, the sun)
    box(c, 2, 5, 28, 23, "#c08040")
    box(c, 5, 8, 22, 17, Cyan)
    c.fillStyle = Green
    c.beginPath(); c.moveTo(5.5, 24.5); c.lineTo(12, 15); c.lineTo(17, 21); c.lineTo(21, 17)
    c.lineTo(26.5, 24.5); c.closePath(); c.fill()
    c.fillStyle = Yellow
    c.beginPath(); c.arc(21, 12, 2.5, 0, 2 * PI); c.fill()
  of "pdf":
    box(c, 6, 3, 20, 27, White)
    c.fillStyle = Dark
    for r in 0 .. 3: c.fillRect(9, 6 + float(r) * 3, 14, 1)
    box(c, 3, 18, 22, 9, Red)
    c.fillStyle = White
    c.font = "bold 7px sans-serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("PDF", 14, 22.8)
  of "media":
    # (a film strip and the play sign)
    box(c, 2, 6, 28, 20, Black)
    c.fillStyle = White
    for k in 0 ..< 7:
      c.fillRect(4 + float(k) * 3.8, 7.5, 2, 2)
      c.fillRect(4 + float(k) * 3.8, 22.5, 2, 2)
    c.fillStyle = Navy
    c.fillRect(3, 11, 26, 10)
    c.fillStyle = Yellow
    c.beginPath(); c.moveTo(13, 12); c.lineTo(21, 16); c.lineTo(13, 20); c.closePath(); c.fill()
  of "recorder":
    # (a microphone on its stand)
    c.fillStyle = Dark
    box(c, 11, 2, 10, 15, Dark)
    c.fillStyle = Gray
    for r in 0 .. 3: c.fillRect(12, 4 + float(r) * 3, 8, 1)
    c.strokeStyle = Black
    c.lineWidth = 1.6
    c.beginPath(); c.arc(16, 13, 8, 0, PI); c.stroke()
    c.beginPath(); c.moveTo(16, 21); c.lineTo(16, 27); c.stroke()
    box(c, 9, 27, 14, 3, Black)
    c.fillStyle = Red
    c.beginPath(); c.arc(26, 5, 3, 0, 2 * PI); c.fill()
  of "camera":
    box(c, 2, 9, 28, 19, Dark)
    box(c, 10, 5, 12, 5, Dark)
    c.fillStyle = Black
    c.beginPath(); c.arc(16, 18, 7, 0, 2 * PI); c.fill()
    c.fillStyle = "#4060c0"
    c.beginPath(); c.arc(16, 18, 5, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.beginPath(); c.arc(14, 16, 1.5, 0, 2 * PI); c.fill()
    c.fillStyle = Yellow
    c.fillRect(24, 11, 4, 2)
  of "dialer":
    # (a telephone of the time: the handset over the dial)
    box(c, 4, 14, 24, 15, "#c00000")
    c.fillStyle = White
    c.beginPath(); c.arc(16, 22, 5.5, 0, 2 * PI); c.fill()
    c.fillStyle = Black
    for k in 0 ..< 8:
      let a = float(k) * PI / 4
      c.beginPath(); c.arc(16 + cos(a) * 3.6, 22 + sin(a) * 3.6, 0.9, 0, 2 * PI); c.fill()
    c.fillStyle = "#800000"
    c.beginPath(); c.moveTo(3, 12); c.lineTo(8, 7); c.lineTo(24, 7); c.lineTo(29, 12); c.lineTo(25, 13)
    c.lineTo(22, 10); c.lineTo(10, 10); c.lineTo(7, 13); c.closePath(); c.fill()
    c.strokeStyle = Black
    c.lineWidth = 1
    c.stroke()
  of "news":
    # (a newspaper, folded)
    box(c, 3, 5, 26, 22, White)
    c.fillStyle = Black
    c.font = "bold 6px serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("NEWS", 16, 9)
    c.fillRect(5, 12, 22, 1)
    box(c, 5, 14, 9, 7, Gray)
    c.fillStyle = Dark
    for r in 0 .. 3: c.fillRect(16, 14 + float(r) * 2.5, 11, 1)
    for r in 0 .. 1: c.fillRect(5, 23 + float(r) * 2, 22, 1)
    c.fillStyle = "#ff8000"
    c.beginPath(); c.arc(27, 6, 3.5, 0, 2 * PI); c.fill()
    c.fillStyle = White
    c.beginPath(); c.arc(26, 7, 0.9, 0, 2 * PI); c.fill()
  of "diskspace":
    # (a pie: how full)
    c.fillStyle = "#00c0c0"
    c.beginPath(); c.arc(16, 16, 13, 0, 2 * PI); c.fill()
    c.fillStyle = Navy
    c.beginPath(); c.moveTo(16, 16); c.arc(16, 16, 13, -PI / 2, PI * 0.9); c.closePath(); c.fill()
    c.fillStyle = "#ff00ff"
    c.beginPath(); c.moveTo(16, 16); c.arc(16, 16, 13, PI * 0.9, PI * 1.25); c.closePath(); c.fill()
    c.strokeStyle = Black
    c.lineWidth = 1
    c.beginPath(); c.arc(16, 16, 13, 0, 2 * PI); c.stroke()
  of "share":
    # (two screens and the line between them)
    box(c, 1, 4, 16, 12, Gray)
    c.fillStyle = TealC
    c.fillRect(3, 6, 12, 8)
    box(c, 15, 16, 16, 12, Gray)
    c.fillStyle = TealC
    c.fillRect(17, 18, 12, 8)
    c.strokeStyle = Red
    c.lineWidth = 1.6
    c.beginPath(); c.moveTo(9, 17); c.lineTo(9, 22); c.lineTo(14, 22); c.stroke()
    c.beginPath(); c.moveTo(12, 20); c.lineTo(14.5, 22); c.lineTo(12, 24); c.stroke()
  of "communicator":
    # (two who talk: their heads, a word between them)
    for (x, col) in [(9.0, "#00a000"), (23.0, "#ffa000")]:
      c.fillStyle = col
      c.beginPath(); c.arc(x, 19, 4.5, 0, 2 * PI); c.fill()
      c.beginPath(); c.arc(x, 31, 8, PI, 2 * PI); c.fill()
      c.strokeStyle = Black
      c.lineWidth = 1
      c.beginPath(); c.arc(x, 19, 4.5, 0, 2 * PI); c.stroke()
    box(c, 6, 2, 20, 10, White)
    c.fillStyle = White
    c.beginPath(); c.moveTo(13, 11); c.lineTo(15, 14.5); c.lineTo(17, 11); c.closePath(); c.fill()
    c.fillStyle = Navy
    for k in 0 .. 2: c.fillRect(10 + float(k) * 4.5, 6, 3, 2)
  of "android":
    # (a phone, its screen of apps)
    box(c, 8, 2, 16, 28, Black)
    c.fillStyle = "#3ddc84"
    c.fillRect(10, 5, 12, 21)
    c.fillStyle = White
    for r in 0 .. 2:
      for k in 0 .. 1: c.fillRect(11.5 + float(k) * 5, 7 + float(r) * 6, 4, 4)
    c.fillStyle = Gray
    c.fillRect(14, 27, 4, 1.5)
  of "folder":
    c.fillStyle = Black
    box(c, 3, 7, 12, 5, Yellow)
    box(c, 3, 10, 26, 18, Yellow)
    c.fillStyle = "#ffffa0"
    c.fillRect(4, 11, 24, 2)
  of "file":
    c.fillStyle = White
    c.beginPath(); c.moveTo(7, 3); c.lineTo(20, 3); c.lineTo(26, 9); c.lineTo(26, 29); c.lineTo(7, 29)
    c.closePath(); c.fill()
    c.strokeStyle = Black
    c.lineWidth = 1
    c.stroke()
    c.beginPath(); c.moveTo(20, 3); c.lineTo(20, 9); c.lineTo(26, 9); c.stroke()
    c.fillStyle = Dark
    for r in 0 .. 4: c.fillRect(10, 13 + float(r) * 3, 13, 1)
  of "panel":
    # (a screen with the panel along its bottom)
    box(c, 2, 4, 28, 22, TealC)
    box(c, 2, 21, 28, 5, Gray)
    box(c, 3, 22, 6, 3, Gray)
    c.fillStyle = Navy
    c.fillRect(10, 22.5, 7, 2)
    c.fillStyle = Black
    c.fillRect(25, 23, 4, 1)
    box(c, 11, 26, 10, 2, Gray)
    box(c, 7, 28, 18, 2, Gray)
  of "night":
    box(c, 2, 2, 28, 28, Navy)
    c.fillStyle = Yellow
    c.beginPath(); c.arc(14, 14, 8, 0, 2 * PI); c.fill()
    c.fillStyle = Navy
    c.beginPath(); c.arc(18, 11, 7, 0, 2 * PI); c.fill()
    c.fillStyle = White
    for (x, y) in [(24.0, 20.0), (8.0, 25.0), (25.0, 6.0)]: c.fillRect(x, y, 1.5, 1.5)
  of "fonts":
    box(c, 3, 3, 26, 26, White)
    c.fillStyle = Navy
    c.font = "bold 16px serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("A", 12, 15)
    c.fillStyle = Red
    c.font = "italic 13px sans-serif"
    c.fillText("a", 22, 21)
  of "international":
    # (a globe and an Arabic letter beside an A)
    c.fillStyle = "#0080ff"
    c.beginPath(); c.arc(16, 16, 13, 0, 2 * PI); c.fill()
    c.strokeStyle = White
    c.lineWidth = 0.8
    c.beginPath(); c.moveTo(3, 16); c.lineTo(29, 16); c.stroke()
    c.beginPath(); c.arc(16, 16, 6, 0, 2 * PI); c.stroke()
    box(c, 4, 8, 11, 11, White)
    box(c, 17, 13, 11, 11, White)
    c.fillStyle = Black
    c.font = "bold 8px sans-serif"
    c.textAlign = "center"
    c.textBaseline = "middle"
    c.fillText("A", 9.5, 13.8)
    c.fillText("ع", 22.5, 18.5)
  of "exit":
    # (a door, open, and the way out)
    box(c, 5, 3, 16, 26, "#804000")
    c.fillStyle = Black
    c.fillRect(7, 5, 12, 22)
    c.fillStyle = "#c08040"
    c.beginPath(); c.moveTo(7, 5); c.lineTo(15, 8); c.lineTo(15, 30); c.lineTo(7, 27); c.closePath(); c.fill()
    c.strokeStyle = Black
    c.lineWidth = 1
    c.stroke()
    c.fillStyle = Yellow
    c.fillRect(13, 17, 1.5, 2)
    c.strokeStyle = Red
    c.lineWidth = 2.5
    c.beginPath(); c.moveTo(18, 16); c.lineTo(29, 16); c.stroke()
    c.fillStyle = Red
    c.beginPath(); c.moveTo(31, 16); c.lineTo(25, 11); c.lineTo(25, 21); c.closePath(); c.fill()
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

# ---- the desktop's own wallpapers ---------------------------------------------------------------------

const BuiltinWallpapers* = ["Bricks", "Tartan", "Argyle", "Circuit", "Starry Night", "Waves",
                            "Checkers", "Marble", "Sunset"]
  ## Pixel art of the desktop's own, chosen in Control Panel > Desktop
  ## (the setting "wallpaper" is "@" and the name). Sunset is a scene, the
  ## others tiles.

proc rgb(r, g, b: int): uint32 =
  0xFF000000'u32 or (uint32(clamp(r, 0, 255)) shl 16) or (uint32(clamp(g, 0, 255)) shl 8) or
    uint32(clamp(b, 0, 255))

proc wallpaperPixel(name: string; x, y: int; w, h: var int): uint32 =
  ## One pixel of a tile (its size in `w`, `h`), on the tile's own grid.
  case name
  of "Bricks":
    w = 32
    h = 16
    let row = y div 8
    let bx = (x + (if row mod 2 == 1: 8 else: 0)) mod 32
    if y mod 8 == 7 or bx mod 16 == 15: return rgb(196, 192, 180)
    let which = ((bx div 16) + row * 3) mod 3
    let base = [rgb(164, 52, 36), rgb(180, 68, 44), rgb(148, 44, 30)][which]
    if y mod 8 == 0 or bx mod 16 == 0: return rgb(200, 96, 72)
    base
  of "Tartan":
    w = 32
    h = 32
    proc band(v: int): (int, int, int) =
      if v in 4 .. 11: (0, 32, 96)
      elif v in 18 .. 19: (176, 0, 0)
      elif v == 26: (220, 200, 40)
      else: (0, 88, 40)
    let a = band(y)
    let b = band(x)
    let (r, g, bl) = if (x + y) mod 2 == 0: a else: b
    rgb((r * 3 + b[0]) div 4, (g * 3 + b[1]) div 4, (bl * 3 + b[2]) div 4)
  of "Argyle":
    w = 32
    h = 32
    let dx = abs((x mod 32) - 16)
    let dy = abs((y mod 32) - 16)
    let inside = dx + dy < 16
    if (x + y) mod 32 == 0 or (x - y + 64) mod 32 == 0: return rgb(240, 232, 200)
    if inside: rgb(120, 24, 56) else: rgb(40, 56, 104)
  of "Circuit":
    w = 32
    h = 32
    let board = rgb(0, 84, 44)
    let copper = rgb(212, 168, 48)
    if (y == 8 and x <= 20) or (x == 20 and y >= 8) or (y == 24 and x <= 12) or
       (x == 28 and y <= 16) or (y == 16 and x >= 28): return copper
    if x in 3 .. 10 and y in 13 .. 19: return (if (x == 3 or x == 10) and y mod 2 == 1: rgb(200, 200, 200)
                                               else: rgb(24, 24, 24))
    for (px, py) in [(20, 30), (12, 24), (28, 2), (0, 8)]:
      if abs(x - px) <= 1 and abs(y - py) <= 1: return copper
    if (x * 7 + y * 13) mod 31 == 0: rgb(0, 100, 52) else: board
  of "Starry Night":
    w = 64
    h = 64
    let star = (x * 73 + y * 151 + x * y * 7) mod 397
    if star == 0: return rgb(255, 255, 255)
    if star == 1 or star == 2: return rgb(150, 150, 200)
    if (abs(x - 20) + abs(y - 40) == 0) or ((x == 20 and abs(y - 40) == 1) or (y == 40 and abs(x - 20) == 1)):
      return rgb(255, 255, 200)
    rgb(10, 10, 48 + (y mod 64) div 8)
  of "Waves":
    w = 32
    h = 16
    let a = 4 + int(round(3 * sin(2 * PI * float(x) / 32)))
    let b = 12 + int(round(3 * sin(2 * PI * float(x + 16) / 32)))
    if y == a or y == a + 1: return rgb(96, 192, 216)
    if y == b: return rgb(0, 72, 104)
    rgb(0, 112, 144)
  of "Checkers":
    w = 16
    h = 16
    if ((x div 8) + (y div 8)) mod 2 == 0: rgb(255, 255, 255) else: rgb(192, 192, 192)
  of "Marble":
    w = 64
    h = 64
    let t = 2 * PI / 64
    let v = sin(float(x) * t * 2 + 3.2 * sin(float(y) * t) + 1.3 * sin(float(x + y) * t))
    let g = 216 + int(v * 22)
    if abs(v) < 0.08: rgb(g - 70, g - 74, g - 60) else: rgb(g, g - 2, g - 6)
  else:
    w = 1
    h = 1
    rgb(0, 128, 128)

proc wallpaperTile*(name: string; dot: int): Bitmap =
  ## The built-in wallpaper `name` as a tile, each of its pixels `dot` x `dot`
  ## pixels of the screen (repeated to some 256 of them, to draw quickly);
  ## nil for Sunset (a scene: `drawSunset`) or a name not known.
  if name notin BuiltinWallpapers or name == "Sunset": return nil
  var w, h = 0
  discard wallpaperPixel(name, 0, 0, w, h)
  let d = max(1, dot)
  let reps = max(1, 256 div (w * d))
  let bw = w * d * reps
  let bh = h * d * reps
  result = newBitmap(bw, bh)
  for y in 0 ..< bh:
    for x in 0 ..< bw:
      var tw, th = 0
      result.px[y * bw + x] = wallpaperPixel(name, (x div d) mod w, (y div d) mod h, tw, th)
  result.opaque = true

proc drawSunset*(r: Rect; dot: int) =
  ## Sunset: the sky going from night to orange, a striped sun on the
  ## horizon, the sea with the sun's light on it -- in bands of `dot` pixels.
  let horizon = r.y + r.h * 62 div 100
  let band = max(2, dot * 3)
  var y = r.y
  while y < horizon:
    let k = (y - r.y) / max(1, horizon - r.y)
    fill(rect(r.x, y, r.w, min(band, horizon - y)),
         color(uint8(40 + 215 * k), uint8(10 + 110 * k * k), uint8(90 - 50 * k)))
    y += band
  let cx = float(r.x + r.w div 2)
  let rad = float(min(r.w, r.h)) * 0.18
  disc(cx, float(horizon), rad, color(255, 200, 40))
  # (the sun's stripes, wider toward the horizon)
  var s = 0
  var sy = horizon - int(rad * 0.45)
  while sy < horizon:
    fill(rect(int(cx - rad), sy, int(rad * 2), max(1, dot + s)), color(230, 110, 40))
    sy += band * 2
    inc s
  y = horizon
  while y < r.y + r.h:
    let k = (y - horizon) / max(1, r.y + r.h - horizon)
    fill(rect(r.x, y, r.w, min(band, r.y + r.h - y)),
         color(uint8(0), uint8(96 - 60 * k), uint8(128 - 70 * k)))
    y += band
  # (the light on the sea)
  var ly = horizon + band
  var lw = rad * 1.6
  while ly < r.y + r.h:
    fill(rect(int(cx - lw / 2), ly, int(lw), max(1, dot)), color(255, 220, 90))
    ly += band * 2
    lw *= 0.86
