## The panel: a bar along the bottom of the screen, as Windows 95 had one,
## drawn in 3.1's look -- gray, raised buttons, black outlines. At its left
## the Programs button (every group of Program Manager, and Run, Help,
## Control Panel, Exit); then a button for each window (the one in front
## pressed in; a click brings it, or minimizes it when it is in front; a
## right click its control menu); at its right the battery (Termux:API, or
## the computer's own) and the clock. Maximized windows stop above it.
##
## The panel is a window of the window manager's (on the desktop's X
## connection), kept over the programs' windows but a full-screen one.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils, json, times, math, streams, tables]
import retroui
import retroui/canvas2d
import xlib, common, wm, art, catalog

var
  panelWin*: Window
  shown = false
  hasClock = true
  h24 = true
  buttons: seq[tuple[c: Client; x, w: int]]
  startW, trayX = 0
  battery = ""                   ## "87%" ("" not known)
  charging = false
  batteryAt = 0.0
  batteryJob: Process
  minuteShown = -1
  pressedOn = -2                 ## the button held (-1 Programs)
  menuPics: Table[string, Bitmap]  ## the menus' pictures, at their size

proc pic(art: string; icon = ""): Bitmap =
  ## A menu item's picture: the program's own icon (an icon theme's, or a
  ## file) when it has one, else the desktop's picture `art`.
  let size = menuIconSize()
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

proc panelHeight*(): int = tbh() + dpx(10)

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

proc drawPanel*() =
  if not shown or panelWin == None: return
  let (sw, _) = screenSize()
  let h = panelHeight()
  let t = ui.theme
  let cv = newCanvas2D(sw, h)
  cv.fillStyle = t.face
  cv.fillRect(0, 0, float(sw), float(h))
  cv.fillStyle = t.frame
  cv.fillRect(0, 0, float(sw), 1)
  cv.fillStyle = t.light
  cv.fillRect(0, 1, float(sw), 1)
  let px = max(10, int(round(float(tbh()) * 0.52)))
  let pad = dpx(3)
  let bh = h - 2 * pad - 1
  proc bevelBox(x, y, w, hh: int; down: bool) =
    cv.fillStyle = t.frame
    cv.fillRect(float(x), float(y), float(w), float(hh))
    cv.fillStyle = (if down: t.shadow else: t.light)
    cv.fillRect(float(x + 1), float(y + 1), float(w - 2), float(hh - 2))
    cv.fillStyle = (if down: t.light else: t.shadow)
    cv.fillRect(float(x + 2), float(y + 2), float(w - 3), float(hh - 3))
    cv.fillStyle = t.face
    cv.fillRect(float(x + 2), float(y + 2), float(w - 4), float(hh - 4))
  # the Programs button: the desktop's logo and its word
  cv.font = "bold " & $px & "px sans-serif"
  cv.textBaseline = "middle"
  cv.textAlign = "left"
  let isz = bh - dpx(6)
  let label = tr("Programs")
  startW = isz + dpx(14) + int(cv.measureText(label).width)
  bevelBox(pad, pad + 1, startW, bh, pressedOn == -1)
  let logo = appIcon("logo", isz)
  if logo != nil: cv.drawImage(logo, float(pad + dpx(4)), float(pad + 1 + (bh - isz) div 2))
  cv.fillStyle = t.text
  cv.fillText(label, float(pad + isz + dpx(9)), float(pad + 1 + bh div 2))
  # the tray: the battery and the clock, sunken
  cv.font = $px & "px sans-serif"
  let n = now()
  var tray = ""
  if battery.len > 0: tray = (if charging: "+" else: "") & battery & "   "
  if hasClock: tray &= n.format(if h24: "HH:mm" else: "h:mm tt")
  let trayW = int(cv.measureText(tray).width) + dpx(16)
  trayX = sw - pad - trayW
  if tray.len > 0:
    cv.fillStyle = t.shadow
    cv.fillRect(float(trayX), float(pad + 1), float(trayW), 1)
    cv.fillRect(float(trayX), float(pad + 1), 1, float(bh))
    cv.fillStyle = t.light
    cv.fillRect(float(trayX), float(pad + bh), float(trayW), 1)
    cv.fillRect(float(trayX + trayW - 1), float(pad + 1), 1, float(bh))
    cv.fillStyle = t.text
    cv.fillText(tray, float(trayX + dpx(8)), float(pad + 1 + bh div 2))
  # the windows: a button each, in the order they were opened
  buttons = @[]
  var list: seq[Client]
  for c in clients:
    if c.transient == None and not c.dialog: list.add c
  let x0 = pad + startW + dpx(8)
  let room = trayX - dpx(6) - x0
  if list.len > 0 and room > dpx(30):
    let w = min(dpx(170), room div list.len)
    var x = x0
    cv.font = $px & "px sans-serif"
    for c in list:
      let down = (c == active and not c.iconic) or pressedOn == buttons.len
      bevelBox(x, pad + 1, w - dpx(3), bh, down)
      let ic = c.readIcon(isz)
      var tx = x + dpx(6)
      if ic != nil and w > isz + dpx(20):
        cv.drawImage(ic, float(tx), float(pad + 1 + (bh - isz) div 2), float(isz), float(isz))
        tx += isz + dpx(5)
      var title = tr(c.title)
      let maxW = float(x + w - dpx(8) - tx)
      while title.len > 1 and cv.measureText(title).width > maxW:
        title = title[0 ..< title.len - 2] & "…"
        if title.len <= 2: break
      cv.font = (if c == active and not c.iconic: "bold " else: "") & $px & "px sans-serif"
      cv.fillStyle = t.text
      cv.fillText(title, float(tx), float(pad + 1 + bh div 2 + (if down: 1 else: 0)))
      cv.font = $px & "px sans-serif"
      buttons.add (c, x, w - dpx(3))
      x += w
  putBitmap(panelWin, cv.toBitmap, 0, 0)

proc programsMenu*()

proc startItem(cmd: string; helpCall: bool): proc () =
  ## (a closure of its own for each item: one made in the loop would see
  ## the loop's last values)
  result = proc () =
    if helpCall: launch(selfCommand("help") & " desktop") else: launch(cmd)

proc groupMenu(name: string; items: seq[CatItem])

proc openGroup(name: string; items: seq[CatItem]): proc () =
  result = proc () = groupMenu(name, items)

proc groupMenu(name: string; items: seq[CatItem]) =
  let (_, sh) = screenSize()
  var list = @[menuItem((if ui.rtl: tr("Programs") & " >" else: "< " & tr("Programs")), "", true,
                        proc () = programsMenu(), pic("progman")), menuLine()]
  for it in items:
    let cmd = if it.terminal: terminalCommand() & " -e " & it.command else: it.command
    let helpCall = it.command == "?help"
    list.add menuItem(it.name.replace("&", "&&"), "", true, startItem(cmd, helpCall),
                      pic(it.art, it.icon))
  showMenu(list, dpx(3), sh - panelHeight(), above = true)

proc programsMenu*() =
  ## The Programs button's menu: the groups (each its programs), and the
  ## desktop's commands.
  let (_, sh) = screenSize()
  var list: seq[MenuItem]
  for (name, items) in catalog():
    if items.len == 0: continue
    # (the arrow of a menu that opens another, at the far side, as 95's)
    list.add menuItem((if ui.rtl: tr(name) else: "&" & tr(name)), (if ui.rtl: "<" else: ">"), true,
                      openGroup(name, items), pic(groupArt(name)))
  list.add menuLine()
  list.add menuItem("&Run...", "", true, proc () = launch(selfCommand("run")), pic("run"))
  list.add menuItem("&Help", "F1", true, proc () = launch(selfCommand("help") & " contents"), pic("help"))
  list.add menuItem("&Control Panel", "", true, proc () = launch(selfCommand("control")), pic("control"))
  list.add menuItem("&Task List...", "Ctrl+Esc", true, (proc () =
    if taskList != nil: taskList()), pic("tasklist"))
  list.add menuLine()
  list.add menuItem("E&xit Retro Desktop...", "", true, proc () = launch(selfCommand("exit")), pic("exit"))
  showMenu(list, dpx(3), sh - panelHeight(), above = true)

proc buttonAt(x: int): int =
  ## -1 the Programs button, a window's button, -2 none.
  if x < dpx(3) + startW: return -1
  for i, b in buttons:
    if x >= b.x and x < b.x + b.w: return i
  -2

proc panelEvents(p: pointer): bool {.nimcall.} =
  let e = cast[ptr XEvent](p)
  case e.theType
  of Expose:
    if e.xexpose.window != panelWin: return false
    if e.xexpose.count == 0: drawPanel()
    true
  of ButtonPress:
    if e.xbutton.window != panelWin: return false
    closeMenu()
    pressedOn = buttonAt(int(e.xbutton.x))
    drawPanel()
    true
  of ButtonRelease:
    if e.xbutton.window != panelWin: return false
    let at = buttonAt(int(e.xbutton.x))
    let was = pressedOn
    pressedOn = -2
    if at == was:
      if at == -1: programsMenu()
      elif at >= 0 and at < buttons.len:
        let c = buttons[at].c
        if c in clients:
          if e.xbutton.button == 3: openMenu(c, int(e.xbutton.xRoot), int(e.xbutton.yRoot) - dpx(4))
          elif c == active and not c.iconic: minimize(c)
          else: restore(c)
      elif int(e.xbutton.x) >= trayX:
        launch(selfCommand("clock"))
    drawPanel()
    true
  else: false

proc panelPlace*()

proc showPanel*(on: bool) =
  ## The panel shown (the room for it kept), or not.
  let d = dpy
  if d == nil: return
  if on == shown:
    if on: drawPanel()
    return
  shown = on
  if on:
    let (sw, sh) = screenSize()
    let h = panelHeight()
    panelWin = XCreateSimpleWindow(d, root, 0, cint(sh - h), cuint(sw), cuint(h), 0, 0, xcolor(ui.theme.face))
    var attrs: XSetWindowAttributes
    attrs.overrideRedirect = 1
    discard XChangeWindowAttributes(d, panelWin, CWOverrideRedirect, addr attrs)
    discard XSelectInput(d, panelWin, ExposureMask or ButtonPressMask or ButtonReleaseMask)
    onTop = @[panelWin]
    otherEvents = panelEvents
    refresh = proc () {.nimcall.} = panelPlace()
    workBottom = h
    discard XMapWindow(d, panelWin)
    discard XRaiseWindow(d, panelWin)
    readBattery()
    drawPanel()
  else:
    onTop = @[]
    otherEvents = nil
    refresh = nil
    workBottom = 0
    if panelWin != None: discard XDestroyWindow(d, panelWin)
    panelWin = None
  discard XFlush(d)

proc panelSettings*(clock, hours24: bool) =
  hasClock = clock
  h24 = hours24
  drawPanel()

proc panelPlace*() =
  ## The screen changed size (the tablet turned): the panel along its bottom.
  if not shown or panelWin == None: return
  let (sw, sh) = screenSize()
  let h = panelHeight()
  var a: XWindowAttributes
  if XGetWindowAttributes(dpy, panelWin, addr a) != 0 and
     (int(a.width) != sw or int(a.height) != h or int(a.y) != sh - h):
    discard XMoveResizeWindow(dpy, panelWin, 0, cint(sh - h), cuint(sw), cuint(h))
  workBottom = h
  drawPanel()

proc panelTick*() =
  ## Every few seconds (the desktop's own beat): the clock's minute, the battery.
  if not shown: return
  readBattery()
  let m = now().minute
  if m != minuteShown:
    minuteShown = m
    drawPanel()
  if batteryJob != nil: wakeIn(1000)
