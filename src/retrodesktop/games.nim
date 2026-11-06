## The games 3.1 came with, made again for the desktop: Minesweeper,
## Solitaire (Klondike) and Reversi. Each is one window, drawn at the size of
## its window (a phone's screen too), for a mouse and for a finger: a finger
## held is a right click (Minesweeper's flag), a tap moves a card where it can
## go, cards drag with a finger as with the mouse.
##
## The cards, the faces and the boards are drawn here, in the flat colors of
## 3.1; the best times and the choices are kept in "retrodesktop-games".
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[random, times, math, strutils, tables, algorithm]
import retroui
import common, link, help

const GamesSettings = "retrodesktop-games"

proc gameSetting(key, default: string): string = loadSettings(GamesSettings).getOrDefault(key, default)

proc keepGame(key, value: string) =
  var s = loadSettings(GamesSettings)
  s[key] = value
  discard saveSettings(GamesSettings, s)

let
  Gray = color(192, 192, 192)
  White = color(255, 255, 255)
  Dark = color(128, 128, 128)
  Black = color(0, 0, 0)

proc bevel(r: Rect; t: int; up: bool) =
  ## 3.1's raised (`up`) or sunken edge, `t` pixels thick, inside `r`.
  let a = if up: White else: Dark
  let b = if up: Dark else: White
  for i in 0 ..< t:
    fill(r.x + i, r.y + i, r.w - 2 * i, 1, a)
    fill(r.x + i, r.y + i, 1, r.h - 2 * i, a)
    fill(r.x + i + 1, r.y + r.h - 1 - i, r.w - 2 * i - 1, 1, b)
    fill(r.x + r.w - 1 - i, r.y + i + 1, 1, r.h - 2 * i - 1, b)

proc centerText(r: Rect; s: string; c: Color; st: TextStyle) =
  text(r.x + (r.w - textWidth(s, st)) div 2, r.y + (r.h - lineHeight(st)) div 2, s, c, st)

proc arc(cx, cy, rad, a0, a1, width: float; c: Color) =
  ## A curve of a circle (a smile), in short straight pieces.
  let n = 10
  for i in 0 ..< n:
    let p = a0 + (a1 - a0) * float(i) / float(n)
    let q = a0 + (a1 - a0) * float(i + 1) / float(n)
    thickLine(cx + cos(p) * rad, cy + sin(p) * rad, cx + cos(q) * rad, cy + sin(q) * rad, width, c)

# ==== Minesweeper ==========================================================================================

type
  MCell = object
    mine, open, flag: bool
    n: int

  Mood = enum moodSmile, moodWorry, moodDead, moodCool

const Levels = [("Beginner", 9, 9, 10), ("Intermediate", 16, 16, 40), ("Expert", 30, 16, 99)]

var
  mLevel = 0
  mCols, mRows, mMines: int
  mCells: seq[MCell]
  mPlaced, mOver, mWon: bool
  mStart = 0.0
  mTime = 0
  mFlags = 0
  mBoom = -1
  mAskName = false
  mName = ""
  mShowBest = false
  mShowAbout = false

proc newMines() =
  mCols = Levels[mLevel][1]
  mRows = Levels[mLevel][2]
  mMines = Levels[mLevel][3]
  mCells = newSeq[MCell](mCols * mRows)
  mPlaced = false
  mOver = false
  mWon = false
  mTime = 0
  mFlags = 0
  mBoom = -1

proc around(i: int): seq[int] =
  let x = i mod mCols
  let y = i div mCols
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      let nx = x + dx
      let ny = y + dy
      if nx >= 0 and ny >= 0 and nx < mCols and ny < mRows: result.add ny * mCols + nx

proc placeMines(safe: int) =
  ## The mines, laid after the first click: never under it or beside it.
  var keepOff = around(safe)
  keepOff.add safe
  var spots: seq[int]
  for i in 0 ..< mCells.len:
    if i notin keepOff: spots.add i
  shuffle(spots)
  for k in 0 ..< min(mMines, spots.len): mCells[spots[k]].mine = true
  for i in 0 ..< mCells.len:
    var n = 0
    for j in around(i):
      if mCells[j].mine: inc n
    mCells[i].n = n
  mPlaced = true
  mStart = epochTime()

proc checkWon() =
  var shut = 0
  for c in mCells:
    if not c.open: inc shut
  if shut == mMines and not mOver:
    mWon = true
    mOver = true
    for c in mCells.mitems:
      if c.mine: c.flag = true
    mFlags = mMines
    let best = gameSetting("mines." & $mLevel, "999\tAnonymous").split('\t')
    var bestT = 999
    try: bestT = parseInt(best[0]) except ValueError: discard
    if mTime < bestT:
      mAskName = true
      mName = gameSetting("player", "")

proc reveal(i: int) =
  if mOver or mCells[i].open or mCells[i].flag: return
  if not mPlaced: placeMines(i)
  if mCells[i].mine:
    mCells[i].open = true
    mBoom = i
    mOver = true
    for c in mCells.mitems:
      if c.mine: c.open = true
    return
  var todo = @[i]
  while todo.len > 0:
    let k = todo.pop()
    if mCells[k].open or mCells[k].flag: continue
    mCells[k].open = true
    if mCells[k].n == 0:
      for j in around(k):
        if not mCells[j].open and not mCells[j].mine: todo.add j
  checkWon()

proc chord(i: int) =
  ## A number with as many flags around it as it says: the rest opened.
  if not mCells[i].open or mCells[i].n == 0: return
  var flags = 0
  for j in around(i):
    if mCells[j].flag: inc flags
  if flags == mCells[i].n:
    for j in around(i): reveal(j)

proc segDigit(r: Rect; ch: char) =
  ## A red seven-segment digit, as 3.1's counters had.
  const segs = {'0': "abcdef", '1': "bc", '2': "abged", '3': "abgcd", '4': "fgbc",
                '5': "afgcd", '6': "afgedc", '7': "abc", '8': "abcdefg", '9': "abcdfg",
                '-': "g"}.toTable
  let on = segs.getOrDefault(ch, "")
  let t = max(2, r.w div 5)
  let w = r.w
  let h2 = r.h div 2
  proc seg(name: char; x, y, sw, sh: int) =
    fill(x, y, sw, sh, if name in on: color(255, 0, 0) else: color(80, 0, 0))
  seg('a', r.x + t, r.y, w - 2 * t, t)
  seg('g', r.x + t, r.y + h2 - t div 2, w - 2 * t, t)
  seg('d', r.x + t, r.y + r.h - t, w - 2 * t, t)
  seg('f', r.x, r.y + t, t, h2 - t)
  seg('b', r.x + w - t, r.y + t, t, h2 - t)
  seg('e', r.x, r.y + h2 + t div 2, t, h2 - t)
  seg('c', r.x + w - t, r.y + h2 + t div 2, t, h2 - t)

proc led(r: Rect; v: int) =
  fill(r, Black)
  let n = clamp(v, -99, 999)
  let s = if n < 0: "-" & align($(-n), 2, '0') else: align($n, 3, '0')
  let dw = r.w div 3
  let pad = max(1, r.h div 10)
  for i, ch in s: segDigit(rect(r.x + i * dw + pad, r.y + pad, dw - 2 * pad, r.h - 2 * pad), ch)

proc face(r: Rect; mood: Mood; pressed: bool) =
  fill(r, Gray)
  bevel(r, max(2, r.w div 12), not pressed)
  let off = if pressed: 1.0 else: 0.0
  let cx = float(r.x) + float(r.w) / 2 + off
  let cy = float(r.y) + float(r.h) / 2 + off
  let rad = float(r.w) * 0.34
  disc(cx, cy, rad, color(255, 255, 0))
  ring(cx, cy, rad, max(1.0, rad / 9), Black)
  let ex = rad * 0.36
  let ey = cy - rad * 0.28
  let lw = max(1.0, rad / 9)
  case mood
  of moodDead:
    for sx in [-1.0, 1.0]:
      let x = cx + sx * ex
      let s = rad * 0.13
      thickLine(x - s, ey - s, x + s, ey + s, lw, Black)
      thickLine(x - s, ey + s, x + s, ey - s, lw, Black)
    arc(cx, cy + rad * 0.62, rad * 0.32, PI * 1.15, PI * 1.85, lw, Black)
  of moodCool:
    fill(int(cx - rad * 0.7), int(ey - rad * 0.12), int(rad * 1.4), int(max(2.0, rad * 0.1)), Black)
    for sx in [-1.0, 1.0]: disc(cx + sx * ex, ey + rad * 0.05, rad * 0.2, Black)
    arc(cx, cy + rad * 0.05, rad * 0.5, PI * 0.2, PI * 0.8, lw, Black)
  of moodWorry:
    for sx in [-1.0, 1.0]: disc(cx + sx * ex, ey, rad * 0.1, Black)
    ring(cx, cy + rad * 0.4, rad * 0.18, lw, Black)
  of moodSmile:
    for sx in [-1.0, 1.0]: disc(cx + sx * ex, ey, rad * 0.1, Black)
    arc(cx, cy + rad * 0.05, rad * 0.5, PI * 0.2, PI * 0.8, lw, Black)

proc mine(r: Rect; ink: Color) =
  let cx = float(r.x) + float(r.w) / 2
  let cy = float(r.y) + float(r.h) / 2
  let rad = float(min(r.w, r.h)) * 0.28
  for k in 0 ..< 4:
    let a = float(k) * PI / 4
    thickLine(cx - cos(a) * rad * 1.45, cy - sin(a) * rad * 1.45,
              cx + cos(a) * rad * 1.45, cy + sin(a) * rad * 1.45, max(1.0, rad / 4), ink)
  disc(cx, cy, rad, ink)
  fill(int(cx - rad * 0.45), int(cy - rad * 0.45), max(1, int(rad * 0.35)), max(1, int(rad * 0.35)), White)

proc flag(r: Rect) =
  let x = float(r.x)
  let y = float(r.y)
  let w = float(r.w)
  let h = float(r.h)
  polygon([(x + w * 0.58, y + h * 0.18), (x + w * 0.58, y + h * 0.52), (x + w * 0.24, y + h * 0.36)],
          color(255, 0, 0))
  fill(int(x + w * 0.54), int(y + h * 0.18), max(1, int(w * 0.08)), int(h * 0.55), Black)
  fill(int(x + w * 0.3), int(y + h * 0.68), int(w * 0.44), max(1, int(h * 0.08)), Black)
  fill(int(x + w * 0.22), int(y + h * 0.74), int(w * 0.6), max(1, int(h * 0.1)), Black)

const NumberInk = [color(0, 0, 255), color(0, 128, 0), color(255, 0, 0), color(0, 0, 128),
                   color(128, 0, 0), color(0, 128, 128), color(0, 0, 0), color(128, 128, 128)]

proc minesWindow(): (int, int) =
  (scaled(Levels[mLevel][1] * 20 + 28), scaled(Levels[mLevel][2] * 20 + 96))

proc runMines*() =
  randomize()
  try: mLevel = clamp(parseInt(gameSetting("mines.level", "0")), 0, 2) except ValueError: discard
  newMines()
  applyDesktopLook()
  let (w, h) = minesWindow()
  openApp("Minesweeper", w, h, frame = wfSystem, userFrame = false, id = "mines")
  showArt("mines")
  followLook()
  while beginFrame():
    helpKeys("mines")
    var levelTo = -1
    menubar:
      menu "&Game":
        if menuItem("&New", "F2"): newMines()
        menuSeparator()
        for i, lv in Levels:
          if menuItem("&" & lv[0], checked = mLevel == i): levelTo = i
        menuSeparator()
        if menuItem("Best &Times..."): mShowBest = true
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("mines")
        menuSeparator()
        if menuItem("&About Minesweeper..."): mShowAbout = true
    if hotkeyPressed("F2"): newMines()
    if levelTo >= 0:
      mLevel = levelTo
      keepGame("mines.level", $mLevel)
      newMines()
      let (nw, nh) = minesWindow()
      resizeSelf(nw, nh)
    if mPlaced and not mOver:
      mTime = min(999, int(epochTime() - mStart))
      wakeIn(1000 - int((epochTime() - mStart) * 1000) mod 1000 + 5)
    let area = canvas(-1, remainingH())
    fill(area, Gray)
    bevel(area, 3, true)
    let m = max(dp(6), area.w div 40)
    let headH = max(dp(30), min(dp(48), area.h div 8))
    let head = rect(area.x + m, area.y + m, area.w - 2 * m, headH)
    bevel(head, 2, false)
    let ledH = headH - dp(10)
    let ledW = ledH * 13 div 10 * 3 div 2 + dp(6)
    led(rect(head.x + dp(6), head.y + (headH - ledH) div 2, ledW, ledH), mMines - mFlags)
    led(rect(head.x + head.w - dp(6) - ledW, head.y + (headH - ledH) div 2, ledW, ledH), mTime)
    let fs = headH - dp(6)
    let faceR = rect(head.x + (head.w - fs) div 2, head.y + dp(3), fs, fs)
    let fhit = interact(idOf("mines-face"), faceR, focusable = false)
    if fhit.clicked: newMines()
    let boardOut = rect(area.x + m, head.y + headH + m, area.w - 2 * m, area.h - headH - 3 * m)
    let cell = max(dp(10), min((boardOut.w - 6) div mCols, (boardOut.h - 6) div mRows))
    let bw = cell * mCols
    let bh = cell * mRows
    let board = rect(boardOut.x + (boardOut.w - bw) div 2, boardOut.y + (boardOut.h - bh) div 2, bw, bh)
    bevel(rect(board.x - 3, board.y - 3, bw + 6, bh + 6), 3, false)
    let hit = interact(idOf("mines-board"), board, focusable = false)
    var under = -1
    if hit.hover:
      let cx = (ui.mx - board.x) div cell
      let cy = (ui.my - board.y) div cell
      if cx >= 0 and cy >= 0 and cx < mCols and cy < mRows: under = cy * mCols + cx
    let holding = hit.down and under >= 0 and not mOver
    let mood = if mWon: moodCool elif mOver: moodDead elif holding: moodWorry else: moodSmile
    face(faceR, mood, fhit.down)
    let numSt = TextStyle(bold: true, size: float32(cell) / float32(max(1, lineHeight())) * 0.8)
    for i, c in mCells:
      let r = rect(board.x + (i mod mCols) * cell, board.y + (i div mCols) * cell, cell, cell)
      if c.open:
        fill(r, if i == mBoom: color(255, 0, 0) else: Gray)
        hline(r.x, r.y, r.w, Dark)
        vline(r.x, r.y, r.h, Dark)
        if c.mine:
          mine(r, Black)
          if c.flag: discard
        elif c.n > 0:
          centerText(r, $c.n, NumberInk[c.n - 1], numSt)
      else:
        let pressedHere = holding and i == under and not c.flag
        if pressedHere:
          fill(r, Gray)
          hline(r.x, r.y, r.w, Dark)
          vline(r.x, r.y, r.h, Dark)
        else:
          fill(r, Gray)
          bevel(r, max(1, cell div 8), true)
        if c.flag:
          flag(r)
          if mOver and not c.mine:
            # (a flag where there was no mine)
            fill(r, Gray)
            mine(r, Black)
            thickLine(float(r.x + 3), float(r.y + 3), float(r.x + r.w - 3), float(r.y + r.h - 3), 2, color(255, 0, 0))
            thickLine(float(r.x + r.w - 3), float(r.y + 3), float(r.x + 3), float(r.y + r.h - 3), 2, color(255, 0, 0))
    if not mOver and under >= 0:
      if hit.clicked:
        if mCells[under].open: chord(under)
        else: reveal(under)
      elif ui.rpressed and not mCells[under].open:
        mCells[under].flag = not mCells[under].flag
        mFlags += (if mCells[under].flag: 1 else: -1)
    # the dialogs
    if mAskName:
      if inputBox(mAskName, "Minesweeper", "You have the fastest time for " &
                  Levels[mLevel][0].toLowerAscii & " level. Please enter your name.", mName) == 1:
        keepGame("mines." & $mLevel, $mTime & "\t" & (if mName.strip.len > 0: mName.strip else: "Anonymous"))
        keepGame("player", mName.strip)
        mShowBest = true
    if mShowBest:
      dialog(mShowBest, "Fastest Mine Sweepers", 360):
        form 0:
          for i, lv in Levels:
            let b = gameSetting("mines." & $i, "999\tAnonymous").split('\t')
            field lv[0] & ":": label(b[0] & " seconds    " & (if b.len > 1: b[1] else: ""))
        row:
          if button("&Reset Scores"):
            for i in 0 .. 2: keepGame("mines." & $i, "999\tAnonymous")
          spring()
          if button("OK", isDefault = true): mShowBest = false
    aboutBox(mShowAbout, "Minesweeper", DesktopVersion,
             ["Find the mines without stepping on one. A number says how many mines " &
              "touch its square. Right click (hold a finger) to put a flag.",
              "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()

# ==== Solitaire ============================================================================================

type
  Card = object
    rank: int                  # 1 (ace) .. 13 (king)
    suit: int                  # 0 clubs, 1 diamonds, 2 hearts, 3 spades
    up: bool

  PileKind = enum pkStock, pkWaste, pkFound, pkTab

  Deal = object
    stock, waste: seq[Card]
    found: array[4, seq[Card]]
    tab: array[7, seq[Card]]
    score: int

  Spot = object
    kind: PileKind
    pile, index: int
    r: Rect

var
  game: Deal
  undoList: seq[Deal]
  drawThree = false
  backDesign = 0
  sStart = 0.0
  sMoves = 0
  dragging = false
  dragFrom: Spot
  dragDX, dragDY: int
  pressAt: (int, int)
  bounce: seq[tuple[card: Card; x, y, vx, vy: float]]
  trail: seq[tuple[card: Card; x, y: int]]
  sWon = false
  sEnd = 0
  sShowAbout = false
  sShowDeck = false

proc red(c: Card): bool = c.suit in [1, 2]

proc newDeal() =
  var deck: seq[Card]
  for s in 0 .. 3:
    for r in 1 .. 13: deck.add Card(rank: r, suit: s)
  shuffle(deck)
  game = Deal()
  for i in 0 .. 6:
    for k in 0 .. i:
      var c = deck.pop()
      c.up = k == i
      game.tab[i].add c
  game.stock = deck
  undoList = @[]
  sStart = epochTime()
  sMoves = 0
  sWon = false
  bounce = @[]
  trail = @[]

proc remember() =
  undoList.add game
  if undoList.len > 100: undoList.delete(0)

proc canFound(c: Card; f: seq[Card]): bool =
  if f.len == 0: c.rank == 1
  else: f[^1].suit == c.suit and f[^1].rank + 1 == c.rank

proc canTab(c: Card; t: seq[Card]): bool =
  if t.len == 0: c.rank == 13
  else: t[^1].up and t[^1].red != c.red and t[^1].rank == c.rank + 1

proc turnTops() =
  for i in 0 .. 6:
    if game.tab[i].len > 0 and not game.tab[i][^1].up:
      game.tab[i][^1].up = true
      game.score += 5

proc cardsAt(s: Spot): seq[Card] =
  case s.kind
  of pkWaste: (if game.waste.len > 0: @[game.waste[^1]] else: @[])
  of pkFound: (if game.found[s.pile].len > 0: @[game.found[s.pile][^1]] else: @[])
  of pkTab: game.tab[s.pile][s.index .. ^1]
  of pkStock: @[]

proc takeFrom(s: Spot) =
  case s.kind
  of pkWaste: discard game.waste.pop()
  of pkFound: discard game.found[s.pile].pop()
  of pkTab: game.tab[s.pile].setLen(s.index)
  of pkStock: discard

proc moveTo(s: Spot; kind: PileKind; pile: int): bool =
  ## The cards at `s` onto pile `pile` (a foundation or a column), when the
  ## rules let them: true when they went.
  let cards = cardsAt(s)
  if cards.len == 0: return false
  if kind == s.kind and pile == s.pile: return false
  case kind
  of pkFound:
    if cards.len != 1 or not canFound(cards[0], game.found[pile]): return false
    remember()
    takeFrom(s)
    game.found[pile].add cards[0]
    game.score += (if s.kind in [pkWaste, pkTab]: 10 else: 0)
  of pkTab:
    if not canTab(cards[0], game.tab[pile]): return false
    remember()
    takeFrom(s)
    for c in cards: game.tab[pile].add c
    if s.kind == pkWaste: game.score += 5
    elif s.kind == pkFound: game.score = max(0, game.score - 15)
  else: return false
  turnTops()
  inc sMoves
  var all = 0
  for f in game.found: all += f.len
  if all == 52 and not sWon:
    sWon = true
    sEnd = int(epochTime() - sStart)
  true

proc autoMove(s: Spot): bool =
  ## A tap (a double click): the card to a foundation if it can go, else
  ## the cards to the first column that takes them.
  let cards = cardsAt(s)
  if cards.len == 0: return false
  if cards.len == 1:
    for f in 0 .. 3:
      if moveTo(s, pkFound, f): return true
  for t in 0 .. 6:
    if t != s.pile or s.kind != pkTab:
      if game.tab[t].len == 0 and cards[0].rank == 13 and s.kind == pkTab and s.index == 0: continue
      if moveTo(s, pkTab, t): return true
  false

proc drawStock() =
  remember()
  if game.stock.len == 0:
    if game.waste.len == 0:
      discard undoList.pop()
      return
    while game.waste.len > 0:
      var c = game.waste.pop()
      c.up = false
      game.stock.add c
    game.score = max(0, game.score - (if drawThree: 20 else: 100))
  else:
    for _ in 0 ..< (if drawThree: 3 else: 1):
      if game.stock.len == 0: break
      var c = game.stock.pop()
      c.up = true
      game.waste.add c

proc suitShape(cx, cy, s: float; suit: int; ink: Color) =
  ## A suit's sign, `s` its size, centered at `cx`, `cy`.
  case suit
  of 1:  # diamond
    polygon([(cx, cy - s * 0.55), (cx + s * 0.4, cy), (cx, cy + s * 0.55), (cx - s * 0.4, cy)], ink)
  of 2:  # heart
    disc(cx - s * 0.22, cy - s * 0.12, s * 0.26, ink)
    disc(cx + s * 0.22, cy - s * 0.12, s * 0.26, ink)
    polygon([(cx - s * 0.47, cy - s * 0.04), (cx + s * 0.47, cy - s * 0.04), (cx, cy + s * 0.5)], ink)
  of 3:  # spade
    disc(cx - s * 0.22, cy + s * 0.08, s * 0.25, ink)
    disc(cx + s * 0.22, cy + s * 0.08, s * 0.25, ink)
    polygon([(cx - s * 0.46, cy + s * 0.02), (cx + s * 0.46, cy + s * 0.02), (cx, cy - s * 0.52)], ink)
    polygon([(cx, cy + s * 0.12), (cx + s * 0.16, cy + s * 0.52), (cx - s * 0.16, cy + s * 0.52)], ink)
  else:  # club
    disc(cx, cy - s * 0.24, s * 0.22, ink)
    disc(cx - s * 0.24, cy + s * 0.08, s * 0.22, ink)
    disc(cx + s * 0.24, cy + s * 0.08, s * 0.22, ink)
    polygon([(cx, cy), (cx + s * 0.16, cy + s * 0.52), (cx - s * 0.16, cy + s * 0.52)], ink)

const RankName = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

proc drawBack(r: Rect) =
  ## The back of a card: one of three designs of the desktop's own.
  fill(r, White)
  box(r, Black)
  let inner = rect(r.x + 3, r.y + 3, r.w - 6, r.h - 6)
  case backDesign
  of 1:
    # (teal waves)
    fill(inner, color(0, 128, 128))
    var y = inner.y + 2
    while y < inner.y + inner.h - 2:
      var x = inner.x + 1
      while x < inner.x + inner.w - 3:
        fill(x, y + (if ((x - inner.x) div 3) mod 2 == 0: 0 else: 1), 3, 1, color(0, 255, 255))
        x += 3
      y += 5
  of 2:
    # (a sunset over the sea, the desktop's logo)
    fill(inner, color(0, 0, 128))
    disc(float(inner.x + inner.w div 2), float(inner.y + inner.h * 3 div 5), float(inner.w) * 0.28,
         color(255, 128, 0))
    fill(inner.x, inner.y + inner.h * 3 div 5, inner.w, inner.h - inner.h * 3 div 5, color(0, 128, 128))
    for k in 0 .. 3:
      fill(inner.x + inner.w div 2 - inner.w div 6 + k * 2, inner.y + inner.h * 3 div 5 + 4 + k * 4,
           inner.w div 3 - k * 4, 2, color(255, 255, 0))
  else:
    # (a navy lattice)
    fill(inner, color(0, 0, 160))
    let step = max(4, r.w div 8)
    pushClip(inner)
    var k = -inner.h
    while k < inner.w:
      line(inner.x + k, inner.y, inner.x + k + inner.h, inner.y + inner.h, color(96, 96, 255))
      line(inner.x + k + inner.h, inner.y, inner.x + k, inner.y + inner.h, color(96, 96, 255))
      k += step
    popClip()
    box(inner, White)

proc drawCard(r: Rect; c: Card) =
  if not c.up:
    drawBack(r)
    return
  fill(r, White)
  box(r, Black)
  let ink = if c.red: color(255, 0, 0) else: Black
  let corner = TextStyle(bold: true, size: max(0.7'f32, float32(r.w) / float32(dp(60))))
  let lh = lineHeight(corner)
  text(r.x + 3, r.y + 2, RankName[c.rank], ink, corner)
  let small = float(lh) * 0.8
  suitShape(float(r.x + 3) + small / 2, float(r.y + 2 + lh) + small / 2, small, c.suit, ink)
  let big = float(min(r.w, r.h)) * 0.42
  let cx = float(r.x) + float(r.w) / 2
  let cy = float(r.y) + float(r.h) * 0.6
  if c.rank > 10:
    # (a court card: a framed panel with its letter and its suit)
    let p = rect(r.x + r.w div 5, r.y + r.h div 4, r.w * 3 div 5, r.h * 2 div 3)
    fill(p, color(255, 255, 192))
    box(p, ink)
    centerText(rect(p.x, p.y, p.w, p.h div 2), RankName[c.rank],
               ink, TextStyle(bold: true, serif: true, size: corner.size * 1.6))
    suitShape(float(p.x) + float(p.w) / 2, float(p.y) + float(p.h) * 0.72, big * 0.55, c.suit, ink)
  else:
    suitShape(cx, cy, big, c.suit, ink)

proc emptySpot(r: Rect; mark: string) =
  box(r, color(0, 96, 0), 1)
  if mark.len > 0:
    centerText(r, mark, color(0, 96, 0), TextStyle(bold: true, size: max(1.0'f32, float32(r.w) / float32(dp(40)))))

proc runSolitaire*() =
  randomize()
  drawThree = gameSetting("solitaire.draw", "1") == "3"
  try: backDesign = clamp(parseInt(gameSetting("solitaire.back", "0")), 0, 2) except ValueError: discard
  newDeal()
  applyDesktopLook()
  openApp("Solitaire", scaled(620), scaled(470), frame = wfSystem, userFrame = false, id = "solitaire")
  showArt("cards")
  followLook()
  while beginFrame():
    helpKeys("solitaire")
    menubar:
      menu "&Game":
        if menuItem("&Deal", "F2"): newDeal()
        menuSeparator()
        if menuItem("&Undo", "Ctrl+Z", enabled = undoList.len > 0):
          game = undoList.pop()
        if menuItem("De&ck..."): sShowDeck = true
        if menuItem("Draw &One", checked = not drawThree):
          drawThree = false
          keepGame("solitaire.draw", "1")
        if menuItem("Draw &Three", checked = drawThree):
          drawThree = true
          keepGame("solitaire.draw", "3")
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("solitaire")
        menuSeparator()
        if menuItem("&About Solitaire..."): sShowAbout = true
    if hotkeyPressed("F2"): newDeal()
    if hotkeyPressed("Ctrl+Z") and undoList.len > 0: game = undoList.pop()
    let status = rect(0, ui.h - lineHeight() - dp(6), ui.w, lineHeight() + dp(6))
    let area = canvas(-1, remainingH() - status.h)
    fill(area, color(0, 128, 0))
    let gap = max(dp(4), area.w div 70)
    let cw = max(dp(24), (area.w - gap * 8) div 7)
    let ch = cw * 7 div 5
    let colX = proc (i: int): int = area.x + gap + i * (cw + gap)
    let top = area.y + gap
    var spots: seq[Spot]
    # the stock and the waste
    let stockR = rect(colX(0), top, cw, ch)
    if game.stock.len > 0: drawBack(stockR)
    else: emptySpot(stockR, "O")
    let fan = cw div 4
    let shownN = if drawThree: min(3, game.waste.len) else: min(1, game.waste.len)
    for k in 0 ..< shownN:
      let idx = game.waste.len - shownN + k
      let r = rect(colX(1) + k * fan, top, cw, ch)
      let isTop = idx == game.waste.len - 1
      if dragging and dragFrom.kind == pkWaste and isTop: continue
      drawCard(r, game.waste[idx])
      if isTop: spots.add Spot(kind: pkWaste, pile: 0, index: idx, r: r)
    if game.waste.len == 0: emptySpot(rect(colX(1), top, cw, ch), "")
    # the foundations
    for f in 0 .. 3:
      let r = rect(colX(3 + f), top, cw, ch)
      let pile = game.found[f]
      var shown = pile.len
      if dragging and dragFrom.kind == pkFound and dragFrom.pile == f: dec shown
      if shown > 0: drawCard(r, pile[shown - 1])
      else: emptySpot(r, "A")
      spots.add Spot(kind: pkFound, pile: f, index: max(0, pile.len - 1), r: r)
    # the columns
    let tabTop = top + ch + gap * 2
    let room = area.y + area.h - tabTop - gap
    for t in 0 .. 6:
      let pile = game.tab[t]
      let x = colX(t)
      var downs, ups = 0
      for c in pile:
        if c.up: inc ups else: inc downs
      let downStep = max(dp(3), ch div 9)
      var upStep = max(dp(10), ch div 4)
      if ups > 1:
        upStep = max(dp(6), min(upStep, (room - ch - downs * downStep) div (ups - 1)))
      var y = tabTop
      if pile.len == 0:
        emptySpot(rect(x, y, cw, ch), "K")
        spots.add Spot(kind: pkTab, pile: t, index: 0, r: rect(x, y, cw, ch))
      for i, c in pile:
        let r = rect(x, y, cw, ch)
        let lifted = dragging and dragFrom.kind == pkTab and dragFrom.pile == t and i >= dragFrom.index
        if not lifted: drawCard(r, c)
        if c.up: spots.add Spot(kind: pkTab, pile: t, index: i, r: r)
        y += (if c.up: upStep else: downStep)
    # the hand: pressing, dragging, letting go
    let hit = interact(idOf("solitaire"), area, focusable = false)
    proc spotAt(x, y: int): int =
      result = -1
      for i in countdown(spots.high, 0):
        let r = spots[i].r
        if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h: return i
    if not sWon:
      if hit.hover and ui.pressed:
        let sx = ui.mx
        let sy = ui.my
        pressAt = (sx, sy)
        if sx >= stockR.x and sy >= stockR.y and sx < stockR.x + stockR.w and sy < stockR.y + stockR.h:
          drawStock()
        else:
          let i = spotAt(sx, sy)
          if i >= 0 and cardsAt(spots[i]).len > 0 and spots[i].kind != pkStock:
            if ui.clicks >= 2:
              discard autoMove(spots[i])
            else:
              dragging = true
              dragFrom = spots[i]
              dragDX = sx - spots[i].r.x
              dragDY = sy - spots[i].r.y
              ui.dragsActive = true
      if dragging:
        let cards = cardsAt(dragFrom)
        let moved = abs(ui.mx - pressAt[0]) + abs(ui.my - pressAt[1]) > dp(6)
        if ui.mouseDown:
          if moved:
            var y = ui.my - dragDY
            for c in cards:
              drawCard(rect(ui.mx - dragDX, y, cw, ch), c)
              y += max(dp(10), ch div 4)
          else:
            # (still where it was pressed: drawn in its place)
            var y = dragFrom.r.y
            for c in cards:
              drawCard(rect(dragFrom.r.x, y, cw, ch), c)
              y += max(dp(10), ch div 4)
        else:
          dragging = false
          if not moved:
            # (a tap or a click: the card where it can go)
            if fingers() or isMobile(): discard autoMove(dragFrom)
          else:
            # (let go over a pile: there, if the rules let it)
            let cx = ui.mx - dragDX + cw div 2
            let cy = ui.my - dragDY + ch div 4
            var done = false
            for f in 0 .. 3:
              let r = rect(colX(3 + f), top, cw, ch)
              if not done and cx >= r.x - gap and cx < r.x + r.w + gap and cy < r.y + r.h + gap:
                done = moveTo(dragFrom, pkFound, f)
            for t in 0 .. 6:
              let x = colX(t)
              if not done and cx >= x - gap div 2 and cx < x + cw + gap div 2 and cy >= tabTop - gap:
                done = moveTo(dragFrom, pkTab, t)
          wakeIn(16)
      if ui.rpressed and hit.hover:
        # (a right click: every card that can go up, goes up)
        var again = true
        while again:
          again = false
          if game.waste.len > 0:
            for f in 0 .. 3:
              if not again and moveTo(Spot(kind: pkWaste, index: game.waste.high), pkFound, f): again = true
          for t in 0 .. 6:
            if game.tab[t].len > 0:
              for f in 0 .. 3:
                if not again and moveTo(Spot(kind: pkTab, pile: t, index: game.tab[t].high), pkFound, f):
                  again = true
    else:
      # won: the cards leave the foundations bouncing, as 3.1's did
      if bounce.len == 0 and trail.len == 0:
        for f in 0 .. 3:
          for c in game.found[f]:
            bounce.add (card: c, x: float(colX(3 + f)), y: float(top), vx: 0.0, vy: 0.0)
        bounce.reverse()
        for i in 0 ..< bounce.len:
          bounce[i].vx = -(2.0 + rand(5.0)) * float(dp(1)) * (if rand(3) == 0: -1.0 else: 1.0)
          bounce[i].vy = -rand(6.0) * float(dp(1))
      if bounce.len > 0:
        var b = bounce[0]
        for _ in 0 .. 1:
          b.x += b.vx
          b.y += b.vy
          b.vy += 0.6 * float(dp(1))
          if b.y + float(ch) > float(area.y + area.h):
            b.y = float(area.y + area.h - ch)
            b.vy = -b.vy * 0.75
          trail.add (card: b.card, x: int(b.x), y: int(b.y))
        bounce[0] = b
        if b.x + float(cw) < float(area.x) or b.x > float(area.x + area.w):
          bounce.delete(0)
        if trail.len > 400: trail = trail[100 .. ^1]
        wakeIn(16)
      for t in trail: drawCard(rect(t.x, t.y, cw, ch), t.card)
      if bounce.len == 0:
        centerText(rect(area.x, area.y + area.h div 3, area.w, dp(40)), "You won! F2 deals again.",
                   White, TextStyle(bold: true, size: 1.6))
    # the status line
    fill(status, ui.theme.face)
    hline(status.x, status.y, status.w, ui.theme.shadow)
    let secs = if sWon: sEnd else: int(epochTime() - sStart)
    text(status.x + dp(6), status.y + dp(3), "Score: " & $game.score & "      Time: " & $secs &
         "      Cards left: " & $game.stock.len, ui.theme.text)
    if not sWon: wakeIn(1000)
    # the dialogs
    if sShowDeck:
      dialog(sShowDeck, "Select Card Back", 380):
        row:
          for d in 0 .. 2:
            let r = canvas(dp(60), dp(84))
            let save = backDesign
            backDesign = d
            drawBack(rect(r.x + dp(4), r.y + dp(2), dp(52), dp(78)))
            backDesign = save
            if d == backDesign: box(r, ui.theme.select, 3)
            if interact(idOf("back" & $d), r, focusable = false).clicked:
              backDesign = d
              keepGame("solitaire.back", $d)
        row:
          spring()
          if button("OK", isDefault = true): sShowDeck = false
    aboutBox(sShowAbout, "Solitaire", DesktopVersion,
             ["Klondike: build the four suits up from the aces. Drag cards (or tap one: it " &
              "goes where it can); a right click sends every card it can to the aces.",
              "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()

# ==== Reversi ==============================================================================================

const
  Weights = [120, -20, 20, 5, 5, 20, -20, 120,
             -20, -40, -5, -5, -5, -5, -40, -20,
             20, -5, 15, 3, 3, 15, -5, 20,
             5, -5, 3, 3, 3, 3, -5, 5,
             5, -5, 3, 3, 3, 3, -5, 5,
             20, -5, 15, 3, 3, 15, -5, 20,
             -20, -40, -5, -5, -5, -5, -40, -20,
             120, -20, 20, 5, 5, 20, -20, 120]
  Dirs = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
  Skills = ["&Beginner", "&Novice", "&Expert", "&Master"]

type Board = array[64, int8]     # 0 empty, 1 you (black), 2 the computer (white)

var
  rb: Board
  rTurn: int8 = 1
  rSkill = 1
  rHint = -1
  rLast = -1
  rSaid = ""
  rThinkAt = 0
  rShowAbout = false
  rHistory: seq[Board]

proc flips(b: Board; at: int; who: int8): seq[int] =
  if b[at] != 0: return
  let x0 = at mod 8
  let y0 = at div 8
  let other = 3'i8 - who
  for (dx, dy) in Dirs:
    var line: seq[int]
    var x = x0 + dx
    var y = y0 + dy
    while x >= 0 and y >= 0 and x < 8 and y < 8 and b[y * 8 + x] == other:
      line.add y * 8 + x
      x += dx
      y += dy
    if line.len > 0 and x >= 0 and y >= 0 and x < 8 and y < 8 and b[y * 8 + x] == who:
      result.add line

proc moves(b: Board; who: int8): seq[int] =
  for i in 0 ..< 64:
    if b[i] == 0 and flips(b, i, who).len > 0: result.add i

proc play(b: var Board; at: int; who: int8) =
  for k in flips(b, at, who): b[k] = who
  b[at] = who

proc count(b: Board; who: int8): int =
  for v in b:
    if v == who: inc result

proc judge(b: Board; who: int8): int =
  ## How good `b` is for `who`: the places held (corners most), the moves it has.
  let other = 3'i8 - who
  for i in 0 ..< 64:
    if b[i] == who: result += Weights[i]
    elif b[i] == other: result -= Weights[i]
  result += 4 * (moves(b, who).len - moves(b, other).len)

proc search(b: Board; who: int8; depth: int; alpha, beta: int): int =
  let mine = moves(b, who)
  if depth == 0:
    return judge(b, who)
  if mine.len == 0:
    if moves(b, 3'i8 - who).len == 0:
      let d = count(b, who) - count(b, 3'i8 - who)
      return (if d > 0: 10000 elif d < 0: -10000 else: 0) + d
    return -search(b, 3'i8 - who, depth - 1, -beta, -alpha)
  var a = alpha
  result = -1_000_000
  for m in mine:
    var nb = b
    play(nb, m, who)
    let v = -search(nb, 3'i8 - who, depth - 1, -beta, -a)
    if v > result: result = v
    if v > a: a = v
    if a >= beta: break

proc bestMove(b: Board; who: int8; skill: int): int =
  let list = moves(b, who)
  if list.len == 0: return -1
  if skill == 0:
    # (a beginner: any move, corners when it sees them)
    for m in list:
      if Weights[m] == 120: return m
    return list[rand(list.high)]
  let depth = [1, 2, 3, 4][clamp(skill, 0, 3)]
  var best = -1_000_001
  result = list[0]
  for m in list:
    var nb = b
    play(nb, m, who)
    let v = -search(nb, 3'i8 - who, depth - 1, -1_000_000, 1_000_000)
    if v > best:
      best = v
      result = m

proc newReversi() =
  for i in 0 ..< 64: rb[i] = 0
  rb[27] = 2
  rb[36] = 2
  rb[28] = 1
  rb[35] = 1
  rTurn = 1
  rHint = -1
  rLast = -1
  rSaid = "Your move: black."
  rHistory = @[]

proc afterMove() =
  rHint = -1
  let you = moves(rb, 1)
  let me = moves(rb, 2)
  if you.len == 0 and me.len == 0:
    let a = count(rb, 1)
    let b = count(rb, 2)
    rSaid = if a > b: "You won, " & $a & " to " & $b & "!"
            elif a < b: "The computer won, " & $b & " to " & $a & "."
            else: "A tie, " & $a & " to " & $b & "."
    rTurn = 0
  elif rTurn == 1:
    if me.len > 0:
      rTurn = 2
      rSaid = "Thinking..."
      rThinkAt = ui.now + 350
    else: rSaid = "The computer has to pass: your move again."
  else:
    if you.len > 0:
      rTurn = 1
      rSaid = "Your move: black."
    else:
      rSaid = "You have to pass (Game > Pass)."
      rTurn = 1

proc runReversi*() =
  randomize()
  try: rSkill = clamp(parseInt(gameSetting("reversi.skill", "1")), 0, 3) except ValueError: discard
  newReversi()
  applyDesktopLook()
  openApp("Reversi", scaled(420), scaled(470), frame = wfSystem, userFrame = false, id = "reversi")
  showArt("reversi")
  followLook()
  while beginFrame():
    helpKeys("reversi")
    let youCan = rTurn == 1 and moves(rb, 1).len > 0
    menubar:
      menu "&Game":
        if menuItem("&New", "F2"): newReversi()
        if menuItem("&Hint", "H", enabled = youCan): rHint = bestMove(rb, 1, 2)
        if menuItem("&Pass", enabled = rTurn == 1 and not youCan and moves(rb, 2).len > 0):
          rTurn = 2
          rThinkAt = ui.now + 300
          rSaid = "Thinking..."
        if menuItem("&Undo", "Ctrl+Z", enabled = rHistory.len > 0 and rTurn == 1):
          rb = rHistory.pop()
          rTurn = 1
          rSaid = "Your move: black."
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Skill":
        for i, s in Skills:
          if menuItem(s, checked = rSkill == i):
            rSkill = i
            keepGame("reversi.skill", $i)
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("reversi")
        menuSeparator()
        if menuItem("&About Reversi..."): rShowAbout = true
    if hotkeyPressed("F2"): newReversi()
    if hotkeyPressed("H") and youCan: rHint = bestMove(rb, 1, 2)
    # (the computer's move, after a moment)
    if rTurn == 2:
      if ui.now >= rThinkAt:
        let m = bestMove(rb, 2, rSkill)
        if m >= 0:
          play(rb, m, 2)
          rLast = m
        rTurn = 2
        afterMove()
        if rTurn == 2:
          rThinkAt = ui.now + 350
      else: wakeIn(max(10, rThinkAt - ui.now))
    let status = rect(0, ui.h - lineHeight() - dp(6), ui.w, lineHeight() + dp(6))
    let area = canvas(-1, remainingH() - status.h)
    fill(area, Gray)
    let side = max(dp(80), min(area.w, area.h) - dp(16))
    let cell = side div 8
    let board = rect(area.x + (area.w - cell * 8) div 2, area.y + (area.h - cell * 8) div 2, cell * 8, cell * 8)
    bevel(rect(board.x - 3, board.y - 3, board.w + 6, board.h + 6), 3, false)
    fill(board, color(0, 128, 0))
    for k in 0 .. 8:
      fill(board.x + k * cell - (if k == 8: 1 else: 0), board.y, 1, board.h, Black)
      fill(board.x, board.y + k * cell - (if k == 8: 1 else: 0), board.w, 1, Black)
    let hit = interact(idOf("reversi"), board, focusable = false)
    var under = -1
    if hit.hover:
      let cx = (ui.mx - board.x) div cell
      let cy = (ui.my - board.y) div cell
      if cx >= 0 and cy >= 0 and cx < 8 and cy < 8: under = cy * 8 + cx
    let legal = if rTurn == 1: moves(rb, 1) else: @[]
    for i in 0 ..< 64:
      let r = rect(board.x + (i mod 8) * cell, board.y + (i div 8) * cell, cell, cell)
      let cx = float(r.x) + float(cell) / 2
      let cy = float(r.y) + float(cell) / 2
      let rad = float(cell) * 0.4
      if rb[i] != 0:
        let ink = if rb[i] == 1: Black else: White
        disc(cx + 1.5, cy + 1.5, rad, color(0, 64, 0))
        disc(cx, cy, rad, ink)
        ring(cx, cy, rad, 1, if rb[i] == 1: color(64, 64, 64) else: Dark)
        if i == rLast: disc(cx, cy, max(2.0, rad * 0.15), color(255, 0, 0))
      elif i == rHint:
        fill(int(cx - rad * 0.3), int(cy - rad * 0.3), int(rad * 0.6), int(rad * 0.6), color(255, 255, 0))
      elif i == under and i in legal:
        ring(cx, cy, rad, 1.5, color(0, 0, 0))
    if hit.clicked and under >= 0 and rTurn == 1:
      if under in legal:
        rHistory.add rb
        play(rb, under, 1)
        rLast = under
        afterMove()
      else:
        rSaid = "You cannot move there: a move must turn over the computer's pieces."
    fill(status, ui.theme.face)
    hline(status.x, status.y, status.w, ui.theme.shadow)
    text(status.x + dp(6), status.y + dp(3), "Black (you): " & $count(rb, 1) & "    White: " &
         $count(rb, 2) & "    " & rSaid, ui.theme.text)
    aboutBox(rShowAbout, "Reversi", DesktopVersion,
             ["Turn the computer's pieces over: put yours so that a line of its pieces " &
              "lies between it and one of yours. The most pieces at the end wins.",
              "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
