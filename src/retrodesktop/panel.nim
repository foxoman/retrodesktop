## The panel: Windows 95's taskbar in 3.1's look -- gray, raised buttons,
## black outlines. At its start the Start button (the desktop's logo, no
## word on it), which opens the Start menu: Programs, Documents, Settings,
## Find, Help, Run, Shut Down, each opening its own menu beside it as 95's
## do. Then a button for each window (the one in front pressed in; a click
## brings it, or minimizes it when it is in front; a right click its
## control menu); at its end the tray: the keyboard's layout (EN, ع: a
## click goes to the next), the volume (PulseAudio: a click for its menu,
## the wheel up and down), Wi-Fi (Termux:API, or the computer's own), the
## notifications (a click lists them), the battery (Termux:API, or the
## computer's own) and the clock (resting on it: the date).
##
## As 95's, it goes on any edge of the screen -- dragged there by its empty
## part -- and is made taller (rows of buttons) or wider by its inner edge;
## it can hide itself until the pointer comes to its edge, and stay over the
## windows or not. A right click on its empty part: Cascade, Tile, Minimize
## All Windows, Task List, Properties (the taskbar's box).
##
## The panel is a window of the window manager's (on the desktop's X
## connection), kept over the programs' windows but a full-screen one.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils, json, times, math, streams, tables, algorithm]
from std/unicode import toRunes, `$`
import retroui
import retroui/canvas2d
import retroui/uirelays/drivers/x11_driver
from retroui/uirelays/screen import CursorKind
import xlib, common, wm, art, catalog, keyboard, tasks

type
  Edge* = enum eBottom = "bottom", eTop = "top", eLeft = "left", eRight = "right"
  TrayKind = enum tkLayout, tkVolume, tkWifi, tkNotes, tkBattery, tkClock
  Box = tuple[x, y, w, h: int]

var
  panelWin*: Window
  shown = false
  hasClock = true
  h24 = true
  edge = eBottom
  rows = 1                       ## rows of buttons (along the bottom or the top)
  sideW = 0                      ## its width on the left or right edge (the screen's pixels)
  autoHide = false
  alwaysOnTop = true
  smallIcons = false             ## the Start menu with small pictures, no band
  hiddenNow = false              ## (hiding itself: only its edge shows)
  leftAt = 0.0                   ## when the pointer left it (to hide a moment later)
  buttons: seq[tuple[c: Client; r: Box]]
  startBox, trayBox: Box
  battery = ""                   ## "87%" ("" not known)
  charging = false
  batteryAt = 0.0
  batteryJob: Process
  minuteShown = -1
  pressedOn = -2                 ## the button held (-1 Start)
  startDown = false              ## the Start menu is open: its button pressed in
  menuPics: Table[string, Bitmap]  ## the menus' pictures, at their size
  drag: tuple[on, resize, moved: bool; rx, ry: int; startThick: int]
  ignoreRelease = false
  tip: tuple[win: Window; text: string; since: float; x, y: int; want: string]
  cursors: Table[CursorKind, culong]   ## (made once each)
  cursorShown = curArrow

var
  tray: seq[tuple[kind: TrayKind; r: Box]]   ## what is where in the tray
  layouts: seq[string]           ## the keyboard's layouts ("us", "ara")
  volume = -1                    ## the speakers' volume, % (-1 not known)
  muted = false
  volumeJob: Task
  volumeAt = 0.0
  wifiName = ""                  ## the Wi-Fi network ("" none known)
  wifiLevel = -1                 ## its strength, 0 to 4 (-1 no Wi-Fi known)
  wifiJob: Task
  wifiAt = 0.0
  notesSeen = 0                  ## the notifications when the list was last opened
  notesCount = 0
  notesStamp: times.Time

proc drawPanel*()
proc panelPlace*()

proc notesFile*(): string = dataDir(SettingsName) / "notifications"

proc readNotes(): seq[tuple[at, title, body: string]] =
  ## The notifications kept (the newest last): when, what, its words.
  try:
    for line in readFile(notesFile()).splitLines:
      let f = line.split('\t')
      if f.len >= 2: result.add (f[0], f[1], (if f.len > 2: f[2] else: ""))
  except CatchableError: discard

proc readVolume() =
  ## PulseAudio's volume and mute (in the background).
  if volumeJob != nil:
    if not volumeJob.check(): return
    let o = volumeJob.output
    let k = o.find('%')
    if k > 0:
      var j = k - 1
      while j > 0 and o[j - 1] in Digits: dec j
      try: volume = parseInt(o[j ..< k]) except ValueError: discard
    muted = "Mute: yes" in o or "Mute: ja" in o
    volumeJob = nil
    drawPanel()
  elif findExe("pactl").len > 0 and epochTime() - volumeAt > 30:
    volumeAt = epochTime()
    volumeJob = run("pactl get-sink-volume @DEFAULT_SINK@; pactl get-sink-mute @DEFAULT_SINK@")

proc setVolume(cmd: string) =
  launch("pactl " & cmd)
  volumeAt = 0
  if volumeJob != nil: volumeJob.stop()
  volumeJob = nil
  readVolume()

proc readWifi() =
  ## The Wi-Fi network and its strength: the computer's own (/proc), else
  ## Termux:API's (every two minutes, in the background).
  if fileExists("/proc/net/wireless"):
    try:
      for line in readFile("/proc/net/wireless").splitLines[2 .. ^1]:
        let f = line.splitWhitespace
        if f.len > 2:
          let q = parseFloat(f[2].strip(chars = {'.'}))
          wifiLevel = clamp(int(q / 70.0 * 4.0 + 0.5), 0, 4)
          wifiName = f[0].strip(chars = {':'})
          return
    except CatchableError: discard
  if wifiJob != nil:
    if not wifiJob.check(): return
    try:
      let j = parseJson(wifiJob.output)
      if j{"supplicant_state"}.getStr == "COMPLETED":
        wifiName = j{"ssid"}.getStr.strip(chars = {'"'})
        let rssi = j{"rssi"}.getInt(-100)
        wifiLevel = clamp((rssi + 100) div 12, 0, 4)
      else:
        wifiName = ""
        wifiLevel = -1
    except CatchableError: discard
    wifiJob = nil
    drawPanel()
  elif inTermux() and findExe("termux-wifi-connectioninfo").len > 0 and epochTime() - wifiAt > 120:
    wifiAt = epochTime()
    wifiJob = run("termux-wifi-connectioninfo")

proc readNotesCount() =
  try:
    let t = getLastModificationTime(notesFile())
    if t != notesStamp:
      notesStamp = t
      notesCount = readNotes().len
      drawPanel()
  except CatchableError: discard

proc pic(art: string; icon = ""; size = 0): Bitmap =
  ## A menu item's picture: the program's own icon (an icon theme's, or a
  ## file) when it has one, else the desktop's picture `art`.
  let size = if size > 0: size else: menuIconSize()
  let key = art & "|" & icon & "@" & $size
  if menuPics.hasKey(key): return menuPics[key]
  var b: Bitmap = nil
  if icon.len > 0: b = loadIcon(icon, size)
  if b == nil: b = appIcon((if art.len > 0: art else: "app"), size)
  if menuPics.len > 300: menuPics.clear()
  menuPics[key] = b
  b

proc forgetMenuPictures*() =
  ## (memory runs low: drawn again when a menu opens)
  menuPics.clear()

proc groupArt(name: string): string =
  case name
  of "DOS": "dos"
  of "Android": "android"
  else: "group"

proc rowHeight(): int = tbh() + dpx(10)
  ## A row of the panel's buttons, with the room round them.

proc horizontal(): bool = edge in {eBottom, eTop}

proc thickness*(): int =
  ## How far the panel reaches into the screen from its edge.
  if horizontal(): rows * rowHeight()
  else: max(dpx(60), sideW)

proc panelHeight*(): int = thickness()
  ## (the panel's depth from its edge)

proc fullBox(): Box =
  ## Where the panel is when it shows.
  let (sw, sh) = screenSize()
  let t = min(thickness(), (if horizontal(): sh else: sw) div 2)
  case edge
  of eBottom: (0, sh - t, sw, t)
  of eTop: (0, 0, sw, t)
  of eLeft: (0, 0, t, sh)
  of eRight: (sw - t, 0, t, sh)

proc shownBox(): Box =
  ## Where it is now: hiding itself, only a sliver along its edge.
  let b = fullBox()
  if not (autoHide and hiddenNow): return b
  let s = max(2, dpx(2))
  case edge
  of eBottom: (b.x, b.y + b.h - s, b.w, s)
  of eTop: (b.x, b.y, b.w, s)
  of eLeft: (b.x, b.y, s, b.h)
  of eRight: (b.x + b.w - s, b.y, s, b.h)

proc keepRoom() =
  ## The work area: the panel's room kept on its edge while it stays over
  ## the windows and does not hide; else the windows have the whole screen.
  let t = if shown and alwaysOnTop and not autoHide: thickness() else: 0
  workInset = (0, 0, 0, 0)
  case edge
  of eBottom: workInset.bottom = t
  of eTop: workInset.top = t
  of eLeft: workInset.left = t
  of eRight: workInset.right = t
  if shown and (alwaysOnTop or autoHide): onTop = @[panelWin] else: onTop = @[]

proc mirrored(): bool = ui.rtl and horizontal()
  ## (right to left -- Arabic: Start at the right, the tray at the left)

proc readBattery() =
  ## The battery's charge: the computer's own (/sys), else Termux:API's
  ## (in the background: it takes a moment).
  for d in ["/sys/class/power_supply/BAT0", "/sys/class/power_supply/BAT1", "/sys/class/power_supply/battery"]:
    if fileExists(d / "capacity"):
      try:
        battery = readFile(d / "capacity").strip & "%"
        charging = fileExists(d / "status") and readFile(d / "status").strip == "Charging"
        return
      except CatchableError: discard
  if batteryJob != nil:
    if batteryJob.peekExitCode() == -1: return
    try:
      let j = parseJson(batteryJob.outputStream.readAll())
      battery = $j{"percentage"}.getInt & "%"
      charging = j{"status"}.getStr in ["CHARGING", "FULL"]
    except CatchableError: discard
    batteryJob.close()
    batteryJob = nil
  elif inTermux() and findExe("termux-battery-status").len > 0 and epochTime() - batteryAt > 120:
    batteryAt = epochTime()
    try: batteryJob = startProcess("termux-battery-status", options = {poUsePath})
    except OSError: batteryJob = nil

proc clockText(): string = now().format(if h24: "HH:mm" else: "h:mm tt")

proc inBox(b: Box; x, y: int): bool = x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h

proc drawPanel*() =
  if not shown or panelWin == None: return
  let box = shownBox()
  if autoHide and hiddenNow:
    # (hidden: the sliver along the edge, in the panel's gray)
    let cv = newCanvas2D(max(1, box.w), max(1, box.h))
    cv.fillStyle = ui.theme.face
    cv.fillRect(0, 0, float(box.w), float(box.h))
    putBitmap(panelWin, cv.toBitmap, 0, 0)
    return
  let (w, h) = (box.w, box.h)
  let t = ui.theme
  let cv = newCanvas2D(w, h)
  cv.fillStyle = t.face
  cv.fillRect(0, 0, float(w), float(h))
  # (its outline on the side that faces the screen: black, then a light line)
  cv.fillStyle = t.frame
  case edge
  of eBottom: cv.fillRect(0, 0, float(w), 1)
  of eTop: cv.fillRect(0, float(h - 1), float(w), 1)
  of eLeft: cv.fillRect(float(w - 1), 0, 1, float(h))
  of eRight: cv.fillRect(0, 0, 1, float(h))
  cv.fillStyle = t.light
  case edge
  of eBottom: cv.fillRect(0, 1, float(w), 1)
  of eTop: cv.fillRect(0, float(h - 2), float(w), 1)
  of eLeft: cv.fillRect(float(w - 2), 0, 1, float(h))
  of eRight: cv.fillRect(1, 0, 1, float(h))
  let pad = dpx(3)
  let rh = rowHeight()
  let bh = rh - 2 * pad - 1               # (a button's height)
  let px = max(10, int(round(float(tbh()) * 0.52)))
  let isz = bh - dpx(6)
  proc bevelBox(b: Box; down: bool; checked = false) =
    cv.fillStyle = t.frame
    cv.fillRect(float(b.x), float(b.y), float(b.w), float(b.h))
    cv.fillStyle = (if down: t.shadow else: t.light)
    cv.fillRect(float(b.x + 1), float(b.y + 1), float(b.w - 2), float(b.h - 2))
    cv.fillStyle = (if down: t.light else: t.shadow)
    cv.fillRect(float(b.x + 2), float(b.y + 2), float(b.w - 3), float(b.h - 3))
    cv.fillStyle = t.face
    cv.fillRect(float(b.x + 2), float(b.y + 2), float(b.w - 4), float(b.h - 4))
    if checked:
      # (the window in front: its button held in, dotted light, as 95's)
      cv.fillStyle = t.light
      var yy = b.y + 2
      while yy < b.y + b.h - 2:
        var xx = b.x + 2 + ((yy - b.y) mod 2)
        while xx < b.x + b.w - 2:
          cv.fillRect(float(xx), float(yy), 1, 1)
          xx += 2
        inc yy
  # -- the Start button: the desktop's logo --
  let sbw = isz + dpx(18)
  let inner = (x: (if edge == eRight: 2 else: 0), y: (if edge == eBottom: 2 else: 0),
               w: w - (if edge in {eLeft, eRight}: 2 else: 0), h: h - (if edge in {eTop, eBottom}: 2 else: 0))
  if horizontal():
    let sx = if mirrored(): inner.x + inner.w - pad - sbw else: inner.x + pad
    startBox = (sx, inner.y + pad, sbw, bh)
  else:
    startBox = (inner.x + pad, inner.y + pad, inner.w - 2 * pad, bh)
  bevelBox(startBox, startDown or pressedOn == -1)
  let logo = appIcon("logo", isz)
  let o = if startDown or pressedOn == -1: 1 else: 0
  if logo != nil:
    cv.drawImage(logo, float(startBox.x + (startBox.w - isz) div 2 + o),
                 float(startBox.y + (startBox.h - isz) div 2 + o))
  # -- the tray, sunken: the layout, the volume, Wi-Fi, the notifications,
  # the battery, the clock (what is not known is left out) --
  cv.font = $px & "px sans-serif"
  cv.textBaseline = "middle"
  cv.textAlign = "left"
  let g = isz
  var items: seq[tuple[kind: TrayKind; w: int]]
  if layouts.len > 1:
    items.add (tkLayout, int(cv.measureText(markOf(layouts[clamp(currentGroup(dpy), 0, layouts.high)])).width) + dpx(10))
  if volume >= 0: items.add (tkVolume, g + dpx(4))
  if wifiLevel >= 0: items.add (tkWifi, g + dpx(2))
  if notesCount > 0: items.add (tkNotes, g + dpx(2))
  if battery.len > 0: items.add (tkBattery, int(cv.measureText((if charging: "+" else: "") & battery).width))
  if hasClock: items.add (tkClock, int(cv.measureText(clockText()).width))
  tray = @[]
  trayBox = (0, 0, 0, 0)
  if items.len > 0:
    # (along the bottom or the top: a row at the far end; on a side: rows
    # at its foot, as many as its width needs)
    var lines: seq[seq[int]]
    if horizontal():
      var all: seq[int]
      for i in 0 ..< items.len: all.add i
      lines = @[all]
    else:
      let room = inner.w - 2 * pad - dpx(8)
      var cur: seq[int]
      var used = 0
      for i, it in items:
        let need = it.w + dpx(8)
        if cur.len > 0 and used + need > room:
          lines.add cur
          cur = @[]
          used = 0
        cur.add i
        used += need
      if cur.len > 0: lines.add cur
    var lineW: seq[int]
    for l in lines:
      var lw = dpx(8)
      for i in l: lw += items[i].w + dpx(8)
      lineW.add lw
    if horizontal():
      let tw = lineW[0]
      let tx = if mirrored(): inner.x + pad else: inner.x + inner.w - pad - tw
      trayBox = (tx, inner.y + pad, tw, bh)
    else:
      let th = lines.len * bh
      trayBox = (inner.x + pad, inner.y + inner.h - pad - th, inner.w - 2 * pad, th)
    cv.fillStyle = t.shadow
    cv.fillRect(float(trayBox.x), float(trayBox.y), float(trayBox.w), 1)
    cv.fillRect(float(trayBox.x), float(trayBox.y), 1, float(trayBox.h))
    cv.fillStyle = t.light
    cv.fillRect(float(trayBox.x), float(trayBox.y + trayBox.h - 1), float(trayBox.w), 1)
    cv.fillRect(float(trayBox.x + trayBox.w - 1), float(trayBox.y), 1, float(trayBox.h))
    for li, l in lines:
      var lx = trayBox.x + dpx(8) + (if horizontal(): 0 else: (trayBox.w - lineW[li]) div 2)
      let ly = trayBox.y + li * bh
      let gy = float(ly + (bh - g) div 2)
      let mid = float(ly + bh div 2)
      for i in l:
        let it = items[i]
        let x = lx
        cv.fillStyle = t.text
        cv.strokeStyle = t.text
        case it.kind
        of tkLayout:
          let mark = markOf(layouts[clamp(currentGroup(dpy), 0, layouts.high)])
          cv.font = "bold " & $px & "px sans-serif"
          cv.fillStyle = t.select
          cv.fillRect(float(x), gy, float(it.w), float(g))
          cv.fillStyle = t.selectText
          cv.textAlign = "center"
          cv.fillText(mark, float(x + it.w div 2), mid)
          cv.textAlign = "left"
          cv.font = $px & "px sans-serif"
        of tkVolume:
          # (a speaker; its waves, or a cross when muted)
          let u = float(g) / 16
          cv.beginPath()
          cv.moveTo(float(x) + 1 * u, gy + 6 * u); cv.lineTo(float(x) + 4 * u, gy + 6 * u)
          cv.lineTo(float(x) + 8 * u, gy + 2 * u); cv.lineTo(float(x) + 8 * u, gy + 14 * u)
          cv.lineTo(float(x) + 4 * u, gy + 10 * u); cv.lineTo(float(x) + 1 * u, gy + 10 * u)
          cv.closePath(); cv.fill()
          cv.lineWidth = max(1.0, u * 1.3)
          if muted or volume == 0:
            cv.strokeStyle = "#c00000"
            cv.beginPath(); cv.moveTo(float(x) + 10 * u, gy + 5 * u); cv.lineTo(float(x) + 15 * u, gy + 11 * u); cv.stroke()
            cv.beginPath(); cv.moveTo(float(x) + 15 * u, gy + 5 * u); cv.lineTo(float(x) + 10 * u, gy + 11 * u); cv.stroke()
          else:
            for k in 1 .. (if volume > 66: 3 elif volume > 33: 2 else: 1):
              cv.beginPath()
              cv.arc(float(x) + 8 * u, gy + 8 * u, float(k) * 2.6 * u, -0.9, 0.9)
              cv.stroke()
        of tkWifi:
          for k in 0 .. 3:
            let bhk = float(g) * float(k + 1) / 4
            cv.fillStyle = (if k < wifiLevel: t.text else: t.shadow)
            cv.fillRect(float(x) + float(k) * float(g) / 4, gy + float(g) - bhk, float(g) / 4 - 1, bhk)
        of tkNotes:
          # (a bell; how many came since the list was opened)
          let u = float(g) / 16
          cv.fillStyle = t.text
          cv.beginPath()
          cv.moveTo(float(x) + 3 * u, gy + 12 * u)
          cv.bezierCurveTo(float(x) + 4 * u, gy + 9 * u, float(x) + 3 * u, gy + 2 * u, float(x) + 8 * u, gy + 2 * u)
          cv.bezierCurveTo(float(x) + 13 * u, gy + 2 * u, float(x) + 12 * u, gy + 9 * u, float(x) + 13 * u, gy + 12 * u)
          cv.closePath(); cv.fill()
          cv.fillRect(float(x) + 2 * u, gy + 12 * u, 12 * u, 1.5 * u)
          cv.beginPath(); cv.arc(float(x) + 8 * u, gy + 14.5 * u, 1.6 * u, 0, 2 * PI); cv.fill()
          let fresh = notesCount - notesSeen
          if fresh > 0:
            cv.fillStyle = "#c00000"
            cv.beginPath(); cv.arc(float(x) + 13 * u, gy + 4 * u, 4 * u, 0, 2 * PI); cv.fill()
            cv.fillStyle = "#ffffff"
            cv.font = "bold " & $max(7, int(6 * u)) & "px sans-serif"
            cv.textAlign = "center"
            cv.fillText((if fresh > 9: "9+" else: $fresh), float(x) + 13 * u, gy + 4.3 * u)
            cv.textAlign = "left"
            cv.font = $px & "px sans-serif"
        of tkBattery:
          cv.fillText((if charging: "+" else: "") & battery, float(x), mid)
        of tkClock:
          cv.fillText(clockText(), float(x), mid)
        tray.add (it.kind, (x - dpx(4), ly, it.w + dpx(8), bh))
        lx += it.w + dpx(8)
  # -- the windows: a button each, in the order they were opened --
  buttons = @[]
  var list: seq[Client]
  for c in clients:
    if c.transient == None and not c.dialog: list.add c
  if list.len > 0:
    cv.font = $px & "px sans-serif"
    var boxes: seq[Box]
    if horizontal():
      # (between Start and the tray, in as many rows as the panel has)
      let x0 = if mirrored(): (if trayBox.w > 0: trayBox.x + trayBox.w + dpx(6) else: inner.x + pad)
               else: startBox.x + startBox.w + dpx(6)
      let x1 = if mirrored(): startBox.x - dpx(6)
               else: (if trayBox.w > 0: trayBox.x - dpx(6) else: inner.x + inner.w - pad)
      let room = x1 - x0
      if room > dpx(30):
        # (as 95's: the first row fills before the next is used)
        let perRow = max(max(1, (list.len + rows - 1) div rows), min(list.len, room div dpx(160)))
        let bw = min(dpx(160), room div perRow)
        for i in 0 ..< list.len:
          let r = i div perRow
          let k = i mod perRow
          let x = if mirrored(): x1 - (k + 1) * bw else: x0 + k * bw
          boxes.add (x + (if mirrored(): dpx(3) else: 0), inner.y + pad + r * rh, bw - dpx(3), bh)
    else:
      # (one under another, between Start and the tray)
      let y0 = startBox.y + startBox.h + dpx(6)
      let y1 = (if trayBox.h > 0: trayBox.y else: inner.y + inner.h) - dpx(6)
      let step = bh + dpx(2)
      for i in 0 ..< list.len:
        let y = y0 + i * step
        if y + bh > y1: break
        boxes.add (inner.x + pad, y, inner.w - 2 * pad, bh)
    for i, b in boxes:
      let c = list[i]
      let front = c == active and not c.iconic
      let down = front or pressedOn == i
      bevelBox(b, down, front and pressedOn != i)
      let ic = c.readIcon(isz)
      let withIcon = ic != nil and b.w > isz + dpx(20)
      let rtl = ui.rtl
      let iconX = if rtl: b.x + b.w - dpx(6) - isz else: b.x + dpx(6)
      let dy = if down: 1 else: 0
      if withIcon:
        cv.drawImage(ic, float(iconX + dy), float(b.y + (bh - isz) div 2 + dy), float(isz), float(isz))
      let room = b.w - dpx(11) - (if withIcon: isz + dpx(5) else: 0)
      var title = tr(c.title)
      cv.font = (if front: "bold " else: "") & $px & "px sans-serif"
      if cv.measureText(title).width > float(room):
        # (cut by letters, never inside one: Arabic's are two bytes)
        var r = title.toRunes
        while r.len > 1 and cv.measureText($r & "…").width > float(room): r.setLen(r.len - 1)
        title = $r & "…"
      cv.fillStyle = t.text
      let ty = float(b.y + bh div 2 + dy)
      if rtl:
        cv.textAlign = "right"
        cv.fillText(title, float(b.x + b.w - dpx(6) - (if withIcon: isz + dpx(5) else: 0) + dy), ty)
        cv.textAlign = "left"
      else:
        cv.fillText(title, float(b.x + dpx(6) + (if withIcon: isz + dpx(5) else: 0) + dy), ty)
      cv.font = $px & "px sans-serif"
      buttons.add (c, b)
  putBitmap(panelWin, cv.toBitmap, 0, 0)

# ---- the Start menu ----------------------------------------------------------------------------------

proc startItem(cmd: string; helpCall: bool): proc () =
  ## (a closure of its own for each item: one made in the loop would see
  ## the loop's last values)
  result = proc () =
    if helpCall: launch(selfCommand("help") & " desktop") else: launch(cmd)

proc groupItems(items: seq[CatItem]): proc (): seq[MenuItem] =
  result = proc (): seq[MenuItem] =
    for it in items:
      let cmd = if it.terminal: terminalCommand() & " -e " & it.command else: it.command
      let helpCall = it.command == "?help"
      result.add menuItem(it.name.replace("&", "&&"), "", true, startItem(cmd, helpCall),
                          pic(it.art, it.icon))

proc programsItems(): seq[MenuItem] =
  ## Programs: every group of Program Manager, each its programs.
  for (name, items) in catalog():
    if items.len == 0: continue
    result.add menuItem(tr(name).replace("&", "&&"), "", true, nil, pic(groupArt(name)),
                        groupItems(items))

proc openDoc(path: string): proc () =
  result = proc () = launch(selfCommand("open") & " " & quoteShell(path))

proc documentsItems(): seq[MenuItem] =
  ## Documents: the files opened last (the newest first).
  for p in recentDocuments():
    result.add menuItem(p.extractFilename.replace("&", "&&"), "", true, openDoc(p), pic("file"))
  if result.len == 0: result.add menuItem("(Empty)", "", false, nil)

proc settingsItems(): seq[MenuItem] =
  @[menuItem("&Control Panel", "", true, proc () = launch(selfCommand("control")), pic("control")),
    menuItem("&Taskbar...", "", true, proc () = launch(selfCommand("taskbar")), pic("panel"))]

proc findItems(): seq[MenuItem] =
  @[menuItem("&Files or Folders...", "", true,
             proc () = launch(selfCommand("open") & " " & quoteShell(getHomeDir())), pic("files"))]

proc startMenuItems(): seq[MenuItem] =
  let s = if smallIcons: menuIconSize() else: menuBigIconSize()
  @[menuItem("&Programs", "", true, nil, pic("progman", size = s), proc (): seq[MenuItem] = programsItems()),
    menuItem("&Documents", "", true, nil, pic("folder", size = s), proc (): seq[MenuItem] = documentsItems()),
    menuItem("&Settings", "", true, nil, pic("control", size = s), proc (): seq[MenuItem] = settingsItems()),
    menuItem("&Find", "", true, nil, pic("files", size = s), proc (): seq[MenuItem] = findItems()),
    menuItem("&Help", "", true, proc () = launch(selfCommand("help") & " contents"), pic("help", size = s)),
    menuItem("&Run...", "", true, proc () = launch(selfCommand("run")), pic("run", size = s)),
    menuLine(),
    menuItem("Sh&ut Down...", "", true, proc () = launch(selfCommand("exit")), pic("exit", size = s))]

proc toScreen(b: Box): Box =
  let p = shownBox()
  (p.x + b.x, p.y + b.y, b.w, b.h)

proc menuAt(b: Box; items: seq[MenuItem]; big = false) =
  ## A menu from the panel at the thing `b` (a box of the panel): above it
  ## on the bottom, under it on the top, beside it on a side.
  let s = toScreen(b)
  let p = fullBox()
  case edge
  of eBottom: showMenu(items, (if ui.rtl: s.x + s.w else: s.x), p.y, above = true, big = big, toLeft = ui.rtl)
  of eTop: showMenu(items, (if ui.rtl: s.x + s.w else: s.x), p.y + p.h, big = big, toLeft = ui.rtl)
  of eLeft: showMenu(items, p.x + p.w, s.y, big = big)
  of eRight: showMenu(items, p.x, s.y, big = big, toLeft = true)

proc letStartUp() {.nimcall.} =
  startDown = false
  drawPanel()

proc programsMenu*() =
  ## The Start menu (the Start button, the Windows key, Ctrl+Esc); shown
  ## already: closed.
  if not shown:
    return
  if menuOpen() and startDown:
    closeMenu()
    return
  if autoHide and hiddenNow:
    hiddenNow = false
    panelPlace()
  # (under the windows -- not always on top: brought over them, as 95's)
  if not alwaysOnTop: discard XRaiseWindow(dpy, panelWin)
  startDown = true
  drawPanel()
  menuAt(startBox, startMenuItems(), big = not smallIcons)
  let s = toScreen(startBox)
  wm.menuButton = (s.x, s.y, s.w, s.h)
  menuClosed = letStartUp

# ---- the other menus ---------------------------------------------------------------------------------

proc trayMenu(list: seq[MenuItem]; b: Box) = menuAt(b, list)

proc volumeItem(label: string; cmd: string): MenuItem =
  menuItem(label, "", true, proc () = setVolume(cmd))

proc trayClick(x, y, button: int) =
  ## A click (or the wheel) on the tray.
  var kind = tkClock
  var at: Box = (-1, 0, 0, 0)
  for it in tray:
    if inBox(it.r, x, y):
      kind = it.kind
      at = it.r
  if at.x < 0: return
  case kind
  of tkLayout: nextLayout(dpy, layouts.len)
  of tkVolume:
    if button == 4: setVolume("set-sink-volume @DEFAULT_SINK@ +5%")
    elif button == 5: setVolume("set-sink-volume @DEFAULT_SINK@ -5%")
    else:
      var list = @[menuItem((if muted: "&Sound On" else: "&Mute"), "", true, (proc () =
        setVolume("set-sink-mute @DEFAULT_SINK@ toggle"))), menuLine()]
      for v in [100, 75, 50, 25, 10]:
        list.add volumeItem("&" & $v & " %" & (if volume == v: "  *" else: ""),
                            "set-sink-volume @DEFAULT_SINK@ " & $v & "%")
      if findExe("pavucontrol").len > 0:
        list.add menuLine()
        list.add menuItem("&Volume Control...", "", true, proc () = launch("pavucontrol"))
      trayMenu(list, at)
  of tkWifi:
    var list = @[menuItem((if wifiName.len > 0: wifiName else: "Wi-Fi") & "  (" & $wifiLevel & "/4)", "", false, nil),
                 menuLine()]
    if inTermux():
      list.add menuItem("&Wi-Fi Settings...", "", true, proc () =
        launch("am start -a android.settings.WIFI_SETTINGS >/dev/null 2>&1"))
    trayMenu(list, at)
  of tkNotes:
    let notes = readNotes()
    var list: seq[MenuItem]
    for k in countdown(notes.high, max(0, notes.len - 10)):
      let it = notes[k]
      var line = it.title & (if it.body.len > 0: " -- " & it.body else: "")
      if line.len > 70: line = line[0 ..< 67] & "..."
      list.add menuItem(line.replace("&", "&&"), it.at, true, nil)
    list.add menuLine()
    list.add menuItem("&Clear All", "", true, proc () =
      try: removeFile(notesFile()) except CatchableError: discard
      notesCount = 0
      notesSeen = 0
      drawPanel())
    notesSeen = notesCount
    trayMenu(list, at)
  of tkBattery:
    if inTermux(): launch("am start -a android.intent.action.POWER_USAGE_SUMMARY >/dev/null 2>&1")
  of tkClock: launch(selfCommand("clock"))

proc minimizeAll() =
  for c in clients:
    if not c.iconic and c.transient == None and not c.dialog: minimize(c)

proc panelMenu(x, y: int) =
  ## A right click on the panel's empty part: as 95's.
  showMenu(@[
    menuItem("&Cascade", "", true, proc () = cascade()),
    menuItem("Tile &Horizontally", "", true, proc () = tile(across = true)),
    menuItem("Tile &Vertically", "", true, proc () = tile(down = true)),
    menuLine(),
    menuItem("&Minimize All Windows", "", true, proc () = minimizeAll()),
    menuLine(),
    menuItem("&Task List...", "Ctrl+Shift+Esc", true, (proc () = (if taskList != nil: taskList()))),
    menuItem("P&roperties", "", true, proc () = launch(selfCommand("taskbar")))],
    x, y, above = edge == eBottom, toLeft = edge == eRight)

# ---- the pointer on the panel ------------------------------------------------------------------------

proc buttonAt(x, y: int): int =
  ## -1 the Start button, a window's button, -2 none.
  if inBox(startBox, x, y): return -1
  for i, b in buttons:
    if inBox(b.r, x, y): return i
  -2

proc nearInnerEdge(x, y: int): bool =
  ## On the panel's edge that faces the screen: it sizes the panel.
  let b = shownBox()
  let e = dpx(4)
  case edge
  of eBottom: y < e
  of eTop: y >= b.h - e
  of eLeft: x >= b.w - e
  of eRight: x < e

proc keepPanel() =
  ## Where the panel is and how it is, written down for the next start.
  var s = desktopSettings()
  s["panelEdge"] = $edge
  s["panelRows"] = $rows
  s["panelWidth"] = $int(round(float(sideW) / max(0.25, devScale())))
  saveDesktopSettings(s)

proc edgeFor(rx, ry: int): Edge =
  ## The edge of the screen a point is nearest to (as 95's taskbar went
  ## where it was dragged).
  let (sw, sh) = screenSize()
  let fx = float(rx) / float(max(1, sw))
  let fy = float(ry) / float(max(1, sh))
  let dl = fx
  let dr = 1 - fx
  let dt = fy
  let db = 1 - fy
  let m = min(min(dl, dr), min(dt, db))
  if m == db: eBottom elif m == dt: eTop elif m == dl: eLeft else: eRight

proc showTip(text: string; x, y: int) =
  ## A little yellow box with `text` near `x`, `y` on the screen.
  if tip.win != None:
    discard XDestroyWindow(dpy, tip.win)
    tip.win = None
  if text.len == 0: return
  let px = max(9, dpx(12))
  let probe = newCanvas2D(4, 4)
  probe.font = $px & "px sans-serif"
  let w = int(probe.measureText(text).width) + dpx(10)
  let h = px + dpx(8)
  let (sw, sh) = screenSize()
  let tx = clamp(x - w div 2, 0, max(0, sw - w))
  let p = fullBox()
  let ty = case edge
           of eBottom: p.y - h - dpx(4)
           of eTop: p.y + p.h + dpx(4)
           else: clamp(y + dpx(16), 0, max(0, sh - h))
  let tx2 = case edge
            of eLeft: p.x + p.w + dpx(4)
            of eRight: p.x - w - dpx(4)
            else: tx
  tip.win = XCreateSimpleWindow(dpy, root, cint(tx2), cint(ty), cuint(w), cuint(h), 0, 0,
                                xcolor(color(255, 255, 225)))
  var attrs: XSetWindowAttributes
  attrs.overrideRedirect = 1
  discard XChangeWindowAttributes(dpy, tip.win, CWOverrideRedirect, addr attrs)
  discard XMapWindow(dpy, tip.win)
  discard XRaiseWindow(dpy, tip.win)
  let cv = newCanvas2D(w, h)
  cv.fillStyle = ui.theme.frame
  cv.fillRect(0, 0, float(w), float(h))
  cv.fillStyle = color(255, 255, 225)
  cv.fillRect(1, 1, float(w - 2), float(h - 2))
  cv.font = $px & "px sans-serif"
  cv.textBaseline = "middle"
  cv.fillStyle = color(0, 0, 0)
  cv.fillText(text, float(dpx(5)), float(h) / 2)
  putBitmap(tip.win, cv.toBitmap, 0, 0)
  tip.text = text

proc hideTip() =
  tip.want = ""
  if tip.win != None:
    discard XDestroyWindow(dpy, tip.win)
    tip.win = None
    tip.text = ""

proc tipFor(x, y: int): string =
  ## What the pointer resting here is told: the date on the clock, a
  ## window's whole title on its button.
  for it in tray:
    if it.kind == tkClock and inBox(it.r, x, y):
      return now().format("dddd, d MMMM yyyy")
  for b in buttons:
    if inBox(b.r, x, y): return tr(b.c.title)
  if inBox(startBox, x, y): return tr("Click here to begin.")
  ""

proc panelEvents(p: pointer): bool {.nimcall.} =
  let e = cast[ptr XEvent](p)
  case e.theType
  of Expose:
    if e.xexpose.window != panelWin: return false
    if e.xexpose.count == 0: drawPanel()
    true
  of EnterNotify:
    if e.xcrossing.window != panelWin: return false
    leftAt = 0
    if autoHide and hiddenNow:
      hiddenNow = false
      panelPlace()
    true
  of LeaveNotify:
    if e.xcrossing.window != panelWin: return false
    hideTip()
    if autoHide and not drag.on:
      leftAt = epochTime()
      wakeIn(750)
    true
  of ButtonPress:
    if e.xbutton.window != panelWin: return false
    hideTip()
    let (x, y) = (int(e.xbutton.x), int(e.xbutton.y))
    let at = buttonAt(x, y)
    if not alwaysOnTop and not autoHide: discard XRaiseWindow(dpy, panelWin)
    if at == -1 and e.xbutton.button == 1:
      # (95's Start opens on the press; pressed again while open: closed)
      if menuOpen() and startDown:
        closeMenu()
        ignoreRelease = true
      elif epochTime() - menuClosedAt < 0.3:
        ignoreRelease = true
      else:
        closeMenu()
        programsMenu()
        ignoreRelease = true
      return true
    closeMenu()
    if at == -2 and e.xbutton.button == 1 and not inBox(trayBox, x, y):
      # (its empty part: dragged, it goes to another edge; its inner edge:
      # dragged, it grows)
      drag = (true, nearInnerEdge(x, y), false, int(e.xbutton.xRoot), int(e.xbutton.yRoot), thickness())
      discard XGrabPointer(dpy, panelWin, 0, cuint(ButtonReleaseMask or PointerMotionMask),
                           GrabModeAsync, GrabModeAsync, None, 0, CurrentTime)
      return true
    pressedOn = at
    drawPanel()
    true
  of MotionNotify:
    if e.xmotion.window != panelWin: return false
    let (rx, ry) = (int(e.xmotion.xRoot), int(e.xmotion.yRoot))
    if drag.on:
      if not drag.moved and abs(rx - drag.rx) + abs(ry - drag.ry) > dpx(6): drag.moved = true
      if not drag.moved: return true
      if drag.resize:
        # (rows of buttons along the bottom or the top; a width on a side)
        let (sw, sh) = screenSize()
        let d = case edge
                of eBottom: drag.ry - ry
                of eTop: ry - drag.ry
                of eLeft: rx - drag.rx
                of eRight: drag.rx - rx
        if horizontal():
          let n = clamp(int(round(float(drag.startThick + d) / float(rowHeight()))), 1,
                        max(1, (sh div 2) div rowHeight()))
          if n != rows:
            rows = n
            panelPlace()
        else:
          let nw = clamp(drag.startThick + d, dpx(60), sw div 2)
          if nw != sideW:
            sideW = nw
            panelPlace()
      else:
        let ne = edgeFor(rx, ry)
        if ne != edge:
          edge = ne
          panelPlace()
      return true
    # (the cursor on the inner edge: the sizing arrows; resting: a tip)
    let (x, y) = (int(e.xmotion.x), int(e.xmotion.y))
    let kind = if nearInnerEdge(x, y): (if horizontal(): curSizeNS else: curSizeWE) else: curArrow
    if kind != cursorShown:
      cursorShown = kind
      if kind notin cursors: cursors[kind] = culong(x11ClassicCursor(kind, cursorScale()))
      discard XDefineCursor(dpy, panelWin, cursors[kind])
    let want = tipFor(x, y)
    if want != tip.want:
      hideTip()
      tip.want = want
      tip.since = epochTime()
      tip.x = rx
      tip.y = ry
      if want.len > 0: wakeIn(650)
    true
  of ButtonRelease:
    if e.xbutton.window != panelWin: return false
    if drag.on:
      drag.on = false
      discard XUngrabPointer(dpy, CurrentTime)
      if drag.moved:
        keepPanel()
        workChanged()
      elif e.xbutton.button == 1: discard
      drawPanel()
      return true
    if ignoreRelease:
      ignoreRelease = false
      return true
    let (x, y) = (int(e.xbutton.x), int(e.xbutton.y))
    let at = buttonAt(x, y)
    let was = pressedOn
    pressedOn = -2
    if at == was and at >= 0 and at < buttons.len:
      let c = buttons[at].c
      if c in clients:
        if e.xbutton.button == 3: openMenu(c, int(e.xbutton.xRoot), int(e.xbutton.yRoot) - dpx(4))
        elif c == active and not c.iconic: minimize(c)
        elif c.iconic: restore(c)
        else: focus(c)
    elif inBox(trayBox, x, y):
      trayClick(x, y, int(e.xbutton.button))
    elif at == -2 and e.xbutton.button == 3:
      panelMenu(int(e.xbutton.xRoot), int(e.xbutton.yRoot))
    drawPanel()
    true
  else: false

proc showPanel*(on: bool) =
  ## The panel shown (the room for it kept), or not.
  let d = dpy
  if d == nil: return
  if on == shown:
    if on: panelPlace()
    return
  shown = on
  if on:
    let b = shownBox()
    panelWin = XCreateSimpleWindow(d, root, cint(b.x), cint(b.y), cuint(max(1, b.w)), cuint(max(1, b.h)),
                                   0, 0, xcolor(ui.theme.face))
    var attrs: XSetWindowAttributes
    attrs.overrideRedirect = 1
    discard XChangeWindowAttributes(d, panelWin, CWOverrideRedirect, addr attrs)
    discard XSelectInput(d, panelWin, ExposureMask or ButtonPressMask or ButtonReleaseMask or
                         PointerMotionMask or EnterWindowMask or LeaveWindowMask)
    otherEvents = panelEvents
    refresh = proc () {.nimcall.} = panelPlace()
    keepRoom()
    discard XMapWindow(d, panelWin)
    discard XRaiseWindow(d, panelWin)
    readBattery()
    workChanged()
    drawPanel()
  else:
    closeMenu()
    hideTip()
    onTop = @[]
    otherEvents = nil
    refresh = nil
    if panelWin != None: discard XDestroyWindow(d, panelWin)
    panelWin = None
    keepRoom()
    workChanged()
  discard XFlush(d)

proc panelSettings*(s: Settings; keyboards: seq[string] = @["us"]) =
  ## The panel as the settings say: its edge, its rows or width, hiding
  ## itself, over the windows or not, the clock, the Start menu's pictures.
  hasClock = s.setting("panelClock", "on") != "off"
  h24 = s.setting("clock24", "on") != "off"
  layouts = keyboards
  edge = try: parseEnum[Edge](s.setting("panelEdge", "bottom")) except ValueError: eBottom
  rows = try: clamp(parseInt(s.setting("panelRows", "1")), 1, 6) except ValueError: 1
  sideW = try: devPx(float(clamp(parseInt(s.setting("panelWidth", "160")), 40, 2000)))
          except ValueError: devPx(160)
  autoHide = s.setting("panelAutoHide", "off") == "on"
  alwaysOnTop = s.setting("panelOnTop", "on") != "off"
  smallIcons = s.setting("startSmallIcons", "off") == "on"
  if not autoHide: hiddenNow = false
  elif not hiddenNow and leftAt == 0:
    # (hiding itself from now: a moment after, unless the pointer is on it)
    leftAt = epochTime()
    wakeIn(750)
  panelPlace()

proc panelPlace*() =
  ## The screen changed size (the tablet turned), or the panel moved, grew,
  ## hid: the panel along its edge, the windows' room kept for it.
  if not shown or panelWin == None: return
  let b = shownBox()
  var a: XWindowAttributes
  if XGetWindowAttributes(dpy, panelWin, addr a) != 0 and
     (int(a.x) != b.x or int(a.y) != b.y or int(a.width) != b.w or int(a.height) != b.h):
    discard XMoveResizeWindow(dpy, panelWin, cint(b.x), cint(b.y), cuint(max(1, b.w)), cuint(max(1, b.h)))
  let before = workInset
  keepRoom()
  if alwaysOnTop or autoHide: discard XRaiseWindow(dpy, panelWin)
  if workInset != before: workChanged()
  drawPanel()

proc pointerOnPanel(): bool =
  var r, child: Window
  var rx, ry, wx, wy: cint
  var mask: cuint
  if XQueryPointer(dpy, root, addr r, addr child, addr rx, addr ry, addr wx, addr wy, addr mask) == 0:
    return false
  inBox(fullBox(), int(rx), int(ry))

proc panelTick*() =
  ## Every few seconds (the desktop's own beat): the clock's minute, the
  ## battery; hiding itself a moment after the pointer left; the tips.
  if not shown: return
  readBattery()
  readVolume()
  readWifi()
  readNotesCount()
  if volumeJob != nil or wifiJob != nil: wakeIn(500)
  let m = now().minute
  if m != minuteShown:
    minuteShown = m
    drawPanel()
  if batteryJob != nil: wakeIn(1000)
  let t = epochTime()
  if autoHide and not hiddenNow and leftAt > 0 and not menuOpen() and not drag.on:
    if t - leftAt >= 0.7 and pointerOnPanel():
      leftAt = 0
    elif t - leftAt >= 0.7:
      leftAt = 0
      hiddenNow = true
      hideTip()
      panelPlace()
    else: wakeIn(int((0.7 - (t - leftAt)) * 1000) + 10)
  if tip.want.len > 0 and tip.win == None and not menuOpen():
    if t - tip.since >= 0.6: showTip(tip.want, tip.x, tip.y)
    else: wakeIn(int((0.6 - (t - tip.since)) * 1000) + 10)
