## Icons on the desktop: what is in your Desktop folder (~/Desktop, or its
## name in your language) -- programs (desktop entries: Program Manager's
## "Put on the Desktop" makes them), folders and files. A double click (a tap
## with frames for fingers) opens one; drag one where you want it, and it
## stays there; a right click: Open, Show in File Manager, Remove.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, tables, times, algorithm]
import retroui
import common, art, wm
from retroui/uirelays/services import standardFolder

type DeskIcon = object
  path, name, command, art, icon: string
  isDir, program: bool
  x, y: int                      ## where it is (logical pixels); -1: not placed yet

const IconsSettings = "retrodesktop-icons"

var
  icons: seq[DeskIcon]
  folderStamp: Time
  lookedAt = -10_000
  sel = -1
  drag = -1
  grabX, grabY, pressX, pressY: int
  moved = false
  pictures: Table[string, Bitmap]
  touch = false

proc deskFolder*(): string =
  ## The folder whose things the desktop shows.
  result = standardFolder("desktop")
  if result.len == 0: result = getHomeDir() / "Desktop"

proc cellW(): int = dp(if touch: 96 else: 80)
proc cellH(): int = dp(if touch: 82 else: 72)

proc keepPlaces() =
  var s: Settings
  for it in icons:
    if it.x >= 0: s[it.path.extractFilename] = $it.x & "," & $it.y
  saveSettings(IconsSettings, s)

proc place(top: int) =
  ## The icons not placed yet: in columns from the top left, where none is.
  let cw = cellW()
  let ch = cellH()
  let rows = max(1, (ui.h - top - dp(60)) div ch)
  var k = 0
  for it in icons.mitems:
    if it.x >= 0: continue
    while true:
      let x = dp(8) + (k div rows) * cw
      let y = top + dp(8) + (k mod rows) * ch
      inc k
      var taken = false
      for o in icons:
        if o.x >= 0 and abs(o.x - x) < cw div 2 and abs(o.y - y) < ch div 2: taken = true
      if not taken:
        it.x = x
        it.y = y
        break
      if k > 500: break

proc look(top: int) =
  ## The folder read again when it changed (every few seconds at most).
  if ui.now - lookedAt < 3000: return
  lookedAt = ui.now
  let dir = deskFolder()
  if not dirExists(dir):
    if icons.len > 0: icons = @[]
    return
  let stamp = try: getLastModificationTime(dir) except CatchableError: Time()
  if stamp == folderStamp and icons.len > 0: return
  folderStamp = stamp
  let kept = loadSettings(IconsSettings)
  var list: seq[DeskIcon]
  for kind, p in walkDir(dir):
    let name = p.extractFilename
    if name.startsWith("."): continue
    var it = DeskIcon(path: p, name: name, x: -1, y: -1)
    if kind in {pcDir, pcLinkToDir}:
      it.isDir = true
      it.art = "folder"
    elif name.toLowerAscii.endsWith(".desktop"):
      try:
        let e = readDesktopEntry(p)
        if e.name.len == 0: continue
        it.name = e.name
        it.command = (if e.terminal: selfCommand("terminal") & " -e " & e.command else: e.command)
        it.program = true
        if e.icon.startsWith("retro:"): it.art = e.icon[6 .. ^1]
        else: it.icon = e.icon
      except CatchableError: continue
    else:
      it.art = case p.splitFile.ext.toLowerAscii
               of ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp": "pictures"
               of ".pdf": "pdf"
               of ".mp3", ".ogg", ".m4a", ".flac", ".wav", ".mp4", ".mkv", ".webm": "media"
               of ".rtf", ".doc", ".docx", ".odt", ".wri": "write"
               of ".txt", ".md", ".log", ".ini", ".conf", ".nim", ".py", ".sh": "notepad"
               else: "file"
    let v = kept.getOrDefault(name, "").split(',')
    if v.len == 2:
      try:
        it.x = parseInt(v[0])
        it.y = parseInt(v[1])
      except ValueError: discard
    list.add it
  list.sort(proc (a, b: DeskIcon): int =
    if a.isDir != b.isDir: (if a.isDir: -1 else: 1) else: cmpIgnoreCase(a.name, b.name))
  icons = list
  sel = -1
  place(top)

proc wrapName(s: string; maxW: int): seq[string] =
  ## A name on lines no wider than `maxW` (a word too long: cut).
  var line = ""
  for word in s.splitWhitespace:
    let t = if line.len > 0: line & " " & word else: word
    if textWidth(t) <= maxW or line.len == 0: line = t
    else:
      result.add line
      line = word
  if line.len > 0: result.add line
  for l in result.mitems:
    if textWidth(l) > maxW: l = ellipsize(l, maxW)

proc pictureOf(it: DeskIcon; size: int): Bitmap =
  let key = it.path & "@" & $size
  if pictures.hasKey(key): return pictures[key]
  result = nil
  if it.icon.len > 0: result = loadIcon(it.icon, size)
  if result == nil: result = appIcon((if it.art.len > 0: it.art else: "app"), size)
  if pictures.len > 100: pictures.clear()
  pictures[key] = result

proc openIcon(it: DeskIcon) =
  if it.program: launch(it.command)
  else: launch(selfCommand("open") & " " & quoteShell(it.path))

proc arrangeDeskIcons*() =
  ## The icons in columns again, from the top left.
  for it in icons.mitems:
    it.x = -1
    it.y = -1
  place(0)
  keepPlaces()

proc iconMenu(i: int; sx, sy: int) =
  let it = icons[i]
  var items = @[wm.menuItem("&Open", "", true, proc () = openIcon(it)),
                wm.menuItem("Show in &File Manager", "", true, proc () =
                  launch(selfCommand("open") & " " & quoteShell(deskFolder())))]
  if it.program:
    items.add wm.menuLine()
    items.add wm.menuItem("&Remove from the Desktop", "", true, proc () =
      try: removeFile(it.path) except CatchableError: discard
      lookedAt = -10_000
      folderStamp = Time())
  items.add wm.menuLine()
  items.add wm.menuItem("&Arrange Icons", "", true, proc () = arrangeDeskIcons())
  wm.showMenu(items, sx, sy)

proc drawDeskIcons*(touchMode: bool; top = 0) =
  ## The desktop's icons, over the wallpaper and under every window.
  touch = touchMode
  look(top)
  if icons.len == 0: return
  let cw = cellW()
  let ch = cellH()
  let isz = dp(32)
  let lh = lineHeight()
  for i in 0 ..< icons.len:
    let it = icons[i]
    let r = rect(it.x, it.y, cw, ch)
    let id = idOf("desk:" & it.path)
    let hit = interact(id, r, focusable = false)
    let picR = rect(r.x + (r.w - isz) div 2, r.y + dp(4), isz, isz)
    drawBitmap(picR, pictureOf(it, isz * max(1, pxScale)))
    # (the name, on two lines at most, as 3.1's icons wrapped them)
    var lines = wrapName(it.name, r.w - dp(4))
    if lines.len > 2:
      lines = lines[0 .. 1]
      lines[1] = ellipsize(lines[1] & "...", r.w - dp(4))
    let chosen = i == sel
    for k, line in lines:
      let tw = textWidth(line)
      let tr = rect(r.x + (r.w - tw) div 2 - dp(2), picR.y + isz + dp(3) + k * lh, tw + dp(4), lh)
      if chosen: fill(tr, ui.theme.select)
      if not chosen: text(tr.x + dp(3), tr.y + 1, line, color(0, 0, 0))
      text(tr.x + dp(2), tr.y, line, (if chosen: ui.theme.selectText else: color(255, 255, 255)))
    if ui.pressed and ui.active == id:
      # (the press is this icon's: `interact` took it)
      if sel == i and ui.clicks >= 2:
        openIcon(it)
        drag = -1
      else:
        sel = i
        drag = i
        moved = false
        grabX = ui.mx - it.x
        grabY = ui.my - it.y
        pressX = ui.mx
        pressY = ui.my
    elif hit.hover and ui.rpressed:
      ui.pressUsed = true
      sel = i
      iconMenu(i, ui.mx * max(1, pxScale), ui.my * max(1, pxScale))
  if drag in 0 ..< icons.len:
    if ui.mouseDown:
      if abs(ui.mx - pressX) + abs(ui.my - pressY) > dp(6): moved = true
      if moved:
        icons[drag].x = clamp(ui.mx - grabX, 0, ui.w - cw)
        icons[drag].y = clamp(ui.my - grabY, top, ui.h - ch)
        ui.redraw = true
    else:
      if moved: keepPlaces()
      elif touch and ui.released: openIcon(icons[drag])
      drag = -1
  elif ui.pressed and not ui.pressUsed: sel = -1

proc putOnDesktop*(name, command, art, icon: string; terminal = false): bool =
  ## A program on the desktop: a desktop entry in the Desktop folder.
  let dir = deskFolder()
  try:
    createDir(dir)
    var file = ""
    for ch in name:
      file.add(if ch.isAlphaNumeric or ch in {'-', '_', ' '}: ch else: '_')
    let path = dir / file.strip & ".desktop"
    writeFile(path, "[Desktop Entry]\nType=Application\nName=" & name & "\nExec=" & command &
              "\nIcon=" & (if art.len > 0: "retro:" & art else: icon) &
              "\nTerminal=" & (if terminal: "true" else: "false") & "\n")
    setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpOthersRead})
    lookedAt = -10_000
    folderStamp = Time()
    result = true
  except CatchableError: result = false

proc forgetDeskIcons*() =
  ## (memory runs low: the pictures are drawn again when needed)
  pictures.clear()
