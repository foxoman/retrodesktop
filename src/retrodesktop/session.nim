## The desktop itself: the screen behind every window -- its color, its
## pattern or wallpaper, the windows minimized to icons along its bottom,
## its menu (a right click, or a finger held on it) -- and the session:
## the window manager, the look other programs are given, Program Manager
## and the StartUp group started, Termux kept awake, the memory watched.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, tables, math, times, posix]
import retroui
import retroui/uirelays/drivers/x11_driver
import xlib, common, theming, wm, link, art

var
  conf: Settings
  deskColor = Color(r: 0, g: 128, b: 128, a: 255)
  patternName = "(None)"
  tile: Bitmap                   # the pattern, ready to repeat
  wallPath, wallMode: string
  wall: Bitmap                   # the wallpaper, at the screen's size
  wallFor: (int, int)            # ... made for this size
  touchMode: bool                # icons open with one tap
  iconSel = -1
  iconMenuFor: Client
  showWelcome, showExit, showRun, showAbout, showNoWm: bool
  welcomeAwake = true
  runText = ""
  exiting = false
  exitUntil = 0
  wakeLocked = false
  managing = false
  lowMemory = false
  lowSaid = 0
  raised = false                 # the desktop over the windows (a dialog of its own is open)

# ---- the settings ------------------------------------------------------------------------------------

proc phoneScreen(): bool =
  ## The screen is a phone's (its shorter side under 600 logical pixels).
  min(ui.w, ui.h) < 600

proc readSettings() =
  conf = desktopSettings()
  applyDesktopLook()
  deskColor = hexColor(conf.setting("desktopColor", Teal), color(0, 128, 128))
  patternName = conf.setting("pattern", "(None)")
  wallPath = conf.setting("wallpaper", "")
  wallMode = conf.setting("wallpaperMode", "fill")
  tile = nil
  wall = nil
  wallFor = (0, 0)
  touchMode = conf.onOff("touch", inTermux())
  wm.bigFrames = touchMode
  wm.maximizeNew = conf.onOff("maximizeNew", inTermux() and phoneScreen())

proc relook() =
  ## The settings changed (Control Panel): the desktop, its frames and the
  ## other programs take them.
  readSettings()
  let d = Display(x11Display())
  if d != nil: applyLook(d)
  announceLook()
  if managing: wm.relook()
  ui.redraw = true

# ---- Termux ------------------------------------------------------------------------------------------

proc wakeLock(on: bool) =
  ## Termux kept running while the screen is off (its wake lock): Android
  ## stops a program in the background that holds none.
  if not inTermux() or on == wakeLocked: return
  let cmd = if on: "termux-wake-lock" else: "termux-wake-unlock"
  if findExe(cmd).len > 0:
    launch(cmd)
    wakeLocked = on

# ---- starting and ending -----------------------------------------------------------------------------

proc startPrograms() =
  ## Program Manager (when it is not open already) and StartUp -- not when
  ## this desktop took the windows of one before it: they are running.
  let tookOver = managing and wm.clients.len > 0
  if conf.setting("startProgman", "on") != "off" and findWindow("Program Manager") == 0:
    launch(selfCommand("progman"))
  if not tookOver:
    for it in progItems():
      if it.group == "StartUp": launch(it.command)

proc beginExit*() =
  ## Ends the session: every program asked to close its windows, the
  ## desktop goes when they did (or after a few seconds).
  if exiting: return
  exiting = true
  exitUntil = ui.now + 4000
  if managing: wm.closeAll()

proc finishExit() =
  if managing: wm.stop()
  wakeLock(false)
  quitApp()

proc onCommand(n, arg: int) {.nimcall.} =
  case n
  of RetroPing:
    let d = Display(x11Display())
    if d != nil:
      let r = XRootWindow(d, XDefaultScreen(d))
      setLongs(d, r, atom(d, "_RETRO_DESKTOP_PONG"), XA_CARDINAL, [clong(arg)])
      discard XFlush(d)
    return
  of RetroArrange:
    iconSel = -1
    ui.redraw = true
  of RetroLookChanged: relook()
  of RetroExit: beginExit()
  of RetroAskExit: showExit = true
  else: discard
  x11Wake()

proc openTaskList() {.nimcall.} =
  let w = findWindow("Task List")
  if w != 0: activate(w)
  else: launch(selfCommand("tasklist"))

# ---- drawing the desktop ----------------------------------------------------------------------------

proc drawBackground() =
  let full = rect(0, 0, ui.w, ui.h)
  fill(full, deskColor)
  if patternName != "(None)" and patternName.len > 0:
    let dot = devPx(1.0)
    if tile == nil:
      let ink = if deskColor.r.int + deskColor.g.int + deskColor.b.int > 380: color(0, 0, 0)
                else: color(0, 0, 0)
      tile = patternTile(patternName, dot, deskColor, ink)
    if tile != nil:
      # (the tile at the screen's own pixels: its logical size is its pixels
      # over the density)
      let side = max(1, tile.w div max(1, pxScale))
      var y = 0
      while y < ui.h:
        var x = 0
        while x < ui.w:
          drawBitmap(rect(x, y, side, side), tile)
          x += side
        y += side
  if wallPath.len > 0 and fileExists(wallPath) and not lowMemory:
    let dw = ui.w * max(1, pxScale)
    let dh = ui.h * max(1, pxScale)
    if wall == nil or wallFor != (dw, dh):
      wallFor = (dw, dh)
      try: wall = loadPicture(wallPath, max(64, dw), max(64, dh))
      except CatchableError: wall = nil
      if wall == nil: wallPath = ""
    if wall != nil and wall.w > 0 and wall.h > 0:
      let iw = float(wall.w) / float(max(1, pxScale))
      let ih = float(wall.h) / float(max(1, pxScale))
      case wallMode
      of "center":
        drawBitmap(rect(int((float(ui.w) - iw) / 2), int((float(ui.h) - ih) / 2), int(iw), int(ih)), wall)
      of "tile":
        var y = 0
        while y < ui.h:
          var x = 0
          while x < ui.w:
            drawBitmap(rect(x, y, int(iw), int(ih)), wall)
            x += max(1, int(iw))
          y += max(1, int(ih))
      of "stretch":
        drawBitmap(full, wall)
      else:
        # fill: the whole screen covered, the picture's shape kept
        let k = max(float(ui.w) / iw, float(ui.h) / ih)
        let w = int(iw * k)
        let h = int(ih * k)
        pushClip(full)
        drawBitmap(rect((ui.w - w) div 2, (ui.h - h) div 2, w, h), wall)
        popClip()

proc iconOf(c: Client; size: int): Bitmap =
  let px = size * max(1, pxScale)
  let b = c.readIcon(px)
  if b != nil: b else: appIcon("window", px)

proc drawIcons() =
  ## The windows minimized, as icons along the bottom, left to right, rows
  ## going up as they fill.
  let list = iconicClients()
  if list.len == 0:
    iconSel = -1
    return
  let cw = dp(if touchMode: 96 else: 80)
  let ch = dp(if touchMode: 82 else: 68)
  let isz = dp(32)
  let perRow = max(1, (ui.w - dp(8)) div cw)
  let lh = lineHeight()
  for i, c in list:
    let col = i mod perRow
    let row = i div perRow
    let r = rect(dp(4) + col * cw, ui.h - (row + 1) * ch, cw, ch)
    let hit = interact(idOf("icon:" & $c.win), r, focusable = false)
    let picR = rect(r.x + (r.w - isz) div 2, r.y + dp(6), isz, isz)
    drawBitmap(picR, iconOf(c, isz))
    let label = ellipsize(c.title, r.w - dp(6))
    let tw = textWidth(label)
    let tr = rect(r.x + (r.w - tw) div 2 - dp(2), picR.y + isz + dp(4), tw + dp(4), lh + dp(2))
    let chosen = i == iconSel
    if chosen: fill(tr, ui.theme.select)
    text(tr.x + dp(2), tr.y + dp(1), label,
         (if chosen: ui.theme.selectText else: color(255, 255, 255)))
    if hit.hover and ui.pressed and ui.clicks >= 2:
      iconSel = -1
      wm.restore(c)
    elif hit.clicked:
      if touchMode:
        iconSel = -1
        wm.restore(c)
      elif iconSel == i:
        iconMenuFor = c
        openPopupMenu("icon", r.x, max(0, r.y - dp(80)))
      else:
        iconSel = i
    elif hit.hover and ui.rpressed:
      iconSel = i
      iconMenuFor = c
      openPopupMenu("icon", ui.mx, ui.my)
  popupMenu("icon"):
    let c = iconMenuFor
    if c != nil and c in wm.clients:
      if menuItem("&Restore"): wm.restore(c)
      if menuItem("Ma&ximize"): wm.maximize(c)
      menuSeparator()
      if menuItem("&Close", "Alt+F4"): wm.close(c)
      menuSeparator()
      if menuItem("S&witch To...", "Ctrl+Esc"): openTaskList()

proc desktopMenu() =
  if ui.rpressed and not ui.pressUsed and ui.popup == 0 and ui.dialogTop == 0:
    openPopupMenu("desktop", ui.mx, ui.my)
  popupMenu("desktop"):
    if menuItem("&Program Manager"):
      let w = findWindow("Program Manager")
      if w != 0: activate(w) else: launch(selfCommand("progman"))
    if menuItem("&Task List...", "Ctrl+Esc"): openTaskList()
    if menuItem("&Control Panel"): launch(selfCommand("control"))
    if menuItem("T&erminal"): launch(selfCommand("terminal"))
    if menuItem("&Run..."):
      showRun = true
      focusFirstText(inDialog = true)
    menuSeparator()
    if menuItem("&Cascade"): wm.cascade()
    if menuItem("&Tile"): wm.tile()
    if menuItem("&Arrange Icons"): iconSel = -1
    menuSeparator()
    if menuItem("&About Retro Desktop..."): showAbout = true
    if menuItem("E&xit Retro Desktop..."): showExit = true

# ---- the dialogs --------------------------------------------------------------------------------------

proc welcome() =
  dialog(showWelcome, "Welcome to " & DesktopName, 560):
    row:
      image(glyphIcon(pxInfo, ui.theme.text, 32))
      heading DesktopName & " " & DesktopVersion
    paragraph "This is your desktop: every program opens here in its own window, " &
      "with a title bar to move it by, borders to size it by, and the buttons to " &
      "minimize and maximize it. Program Manager holds your programs, the ones that come " &
      "with the desktop and every program you install with a desktop entry."
    paragraph "A right click on the desktop (or a finger held on it) opens its menu. " &
      "Alt+Tab goes to the next window, Alt+F4 closes one, Ctrl+Esc opens the Task List. " &
      "Control Panel changes the colors, the fonts, the sizes and the desktop."
    if inTermux():
      group "Keep it running on Android":
        paragraph "Android stops programs it thinks you do not use. For a desktop " &
          "that stays: let Termux keep the phone awake, set Termux (and Termux:X11) to " &
          "\"Unrestricted\" in Settings > Apps > Battery, and on Android 12 and later " &
          "turn off the phantom process killer (Developer options > \"Disable child " &
          "process restrictions\"; on Android 12L or older, from a computer: adb shell " &
          "\"settings put global settings_enable_monitor_phantom_procs false\")."
        paragraph "In Termux:X11's preferences: Display resolution mode \"native\" for " &
          "sharp text, Touchscreen input mode \"Direct touch\" to tap where you point (or " &
          "\"Trackpad\" for a pointer), and the additional keyboard bar for Esc, Ctrl, Alt " &
          "and Tab."
        checkbox("&Keep Termux awake while the desktop runs (termux-wake-lock)", welcomeAwake)
    row:
      spring()
      if button("OK", isDefault = true):
        showWelcome = false
  if not showWelcome and conf.setting("welcomed", "") == "":
    conf["welcomed"] = DesktopVersion
    if inTermux():
      conf["wakeLock"] = (if welcomeAwake: "on" else: "off")
      wakeLock(welcomeAwake)
    saveDesktopSettings(conf)

proc keepDialogsInFront() =
  ## The desktop's own dialogs (Welcome, Run, Exit, About) are drawn on the
  ## desktop, under every window: while one is open the desktop comes over
  ## the windows, and goes back under them when it closes.
  let modal = showWelcome or showRun or showExit or showAbout or showNoWm
  if modal == raised or not managing: return
  raised = modal
  let d = Display(x11Display())
  let me = Window(x11Window())
  if modal:
    discard XRaiseWindow(d, me)
    discard XSetInputFocus(d, me, RevertToPointerRoot, CurrentTime)
  else:
    discard XLowerWindow(d, me)
    if wm.active != nil: wm.focus(wm.active)
  discard XFlush(d)

proc dialogs() =
  if showWelcome: welcome()
  if showRun:
    if inputBox(showRun, "Run", "&Command line:", runText, width = 420) == 1:
      if runText.strip.len > 0: launch(runText)
  if showExit:
    if msgBox(showExit, "Exit " & DesktopName, "This will end your " & DesktopName &
              " session.\nPrograms still open are asked to close.", ["OK", "Cancel"],
              miWarning) == 1:
      beginExit()
  if showNoWm:
    discard msgBox(showNoWm, DesktopName, "Another window manager is running on this screen, " &
                   "so the desktop does not frame the windows. Close it and start " &
                   DesktopName & " again for the full desktop.", ["OK"], miInfo)
  aboutBox(showAbout, DesktopName, DesktopVersion,
           ["A Windows 3.1 style desktop for Linux and Termux on Android.",
            "Memory: " & memoryReport(false)])

# ---- memory --------------------------------------------------------------------------------------------

proc watchMemory() =
  onMemoryPressure(proc (level: MemoryPressure) =
    forgetIcons()
    tile = nil
    if level == mpCritical:
      wall = nil
      lowMemory = true
      if ui.now - lowSaid > 60_000:
        lowSaid = ui.now
        toast("Close programs you are not using: Ctrl+Esc lists them, with how much each holds.",
              8000, title = "Memory is running low")
    trimHeap()
    ui.redraw = true)

# ---- the session --------------------------------------------------------------------------------------

proc oldSessions(): seq[int] =
  ## Other desktops of this user running (`retro-desktop` with no argument),
  ## from /proc.
  let me = getCurrentProcessId()
  for kind, path in walkDir("/proc"):
    let pid = try: parseInt(path.extractFilename) except ValueError: -1
    if pid <= 0 or pid == me: continue
    try:
      let args = readFile(path / "cmdline").split('\0')
      var n = 0
      for a in args:
        if a.len > 0: inc n
      if n == 1 and args[0].extractFilename == "retro-desktop": result.add pid
    except CatchableError: discard

proc answers(d: Display; r: Window): bool =
  ## The desktop on the screen answers a ping (within two seconds).
  let token = clong(getCurrentProcessId() * 1000 + (epochTime().int mod 1000))
  let pong = atom(d, "_RETRO_DESKTOP_PONG")
  var e: XEvent
  e.xclient.theType = ClientMessage
  e.xclient.window = r
  e.xclient.messageType = atom(d, "_RETRO_DESKTOP")
  e.xclient.format = 32
  e.xclient.data[0] = clong(RetroPing)
  e.xclient.data[1] = token
  discard XSendEvent(d, r, 0, SubstructureRedirectMask or SubstructureNotifyMask, addr e)
  for _ in 0 ..< 20:
    discard XSync(d, 0)
    let v = propLongs(d, r, pong, XA_CARDINAL)
    if v.len > 0 and v[0] == token: return true
    sleep(100)
  false

proc desktopShown(): bool =
  ## Retro Desktop runs on this screen already (another session, which
  ## answers). A desktop that stopped answering -- hung after a crash -- is
  ## ended, and its programs' windows come to this one. When no desktop
  ## runs, the X resources a desktop before left on the server go: the kit
  ## would take their dpi for the screen's (and this desktop puts its own
  ## back once it knows the screen).
  var name = getEnv("DISPLAY")
  if name.len == 0 and inTermux(): name = ":0"
  if name.len == 0: return false
  let d = XOpenDisplay(name.cstring)
  if d == nil: return false
  let r = XRootWindow(d, XDefaultScreen(d))
  let c = propLongs(d, r, atom(d, "_NET_SUPPORTING_WM_CHECK"), XA_WINDOW)
  if c.len > 0:
    # (the check window of a desktop that ended is gone: an error, no desktop)
    var name = ""
    var pids: seq[clong]
    trapErrors(d):
      name = propText(d, Window(c[0]), atom(d, "_NET_WM_NAME"))
      pids = propLongs(d, Window(c[0]), atom(d, "_NET_WM_PID"), XA_CARDINAL)
    result = not xTrapped and name == DesktopName
    if result and not answers(d, r):
      # (it hangs: ended, and its windows' frames go with it -- the X server
      # gives the programs' windows back to the screen, for this desktop)
      var victims: seq[int]
      if pids.len > 0: victims.add int(pids[0])
      else: victims = oldSessions()
      for pid in victims: discard posix.kill(Pid(pid), SIGKILL)
      for _ in 0 ..< 30:
        var gone = false
        trapErrors(d):
          discard propText(d, Window(c[0]), atom(d, "_NET_WM_NAME"))
        gone = xTrapped
        if gone: break
        sleep(100)
      result = false
  if not result and ownResources(d):
    discard XDeleteProperty(d, r, atom(d, "RESOURCE_MANAGER"))
    discard XSync(d, 0)
  discard XCloseDisplay(d)

proc c_exit(code: cint) {.importc: "_exit", header: "<unistd.h>", noreturn.}

proc onFatal(sig: cint) {.noconv.} =
  ## A crash ends the desktop at once -- no stack trace, which could hang on a
  ## broken heap: the X server gives the programs' windows back to the
  ## screen, and `retro-desktop` starts a new desktop that takes them.
  const msg = "Retro Desktop stopped: a fatal error (the windows went back to the screen)\n"
  discard posix.write(2, msg.cstring, msg.len)
  c_exit(70)

proc runSession*() =
  ## The desktop, until Exit.
  # (what goes wrong is kept: ~/.local/share/retrodesktop/desktop.log)
  try:
    let log = dataDir(SettingsName) / "desktop.log"
    createDir(log.parentDir)
    discard reopen(stderr, log, fmWrite)
    stderr.writeLine(DesktopName & " " & DesktopVersion & ", started " & $now())
    stderr.flushFile()
  except CatchableError: discard
  for s in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE]: discard posix.signal(s, onFatal)
  if desktopShown():
    # (a second start: Program Manager on the desktop that runs)
    if getEnv("DISPLAY").len == 0: putEnv("DISPLAY", ":0")
    launch(selfCommand("progman"))
    return
  applyDesktopLook()
  openApp(DesktopName, 1024, 768, frame = wfSystem, userFrame = false, id = "retrodesktop")
  setTitle(DesktopName)
  readSettings()
  watchMemory()
  wm.changed = nil
  wm.taskList = openTaskList
  wm.command = onCommand
  managing = wm.start()
  if not managing: showNoWm = true
  let d = Display(x11Display())
  if d != nil: applyLook(d)
  announceLook()
  # (Termux awake from the start: Android stops a Termux without it as soon
  # as Termux:X11 is in front -- "X server stalled")
  if conf.setting("wakeLock", "on") == "on": wakeLock(true)
  # (the welcome the first time only, not again after an update)
  if conf.setting("welcomed", "") == "": showWelcome = true
  var started = false
  while beginFrame():
    # (the first time, the welcome first: Program Manager comes after it)
    if not started and not showWelcome:
      started = true
      startPrograms()
    drawBackground()
    drawIcons()
    desktopMenu()
    dialogs()
    keepDialogsInFront()
    if exiting:
      if not managing or wm.clients.len == 0 or ui.now > exitUntil: finishExit()
      else: wakeIn(100)
    else:
      discard memoryPressure()
      wakeIn(5000)
    endFrame()
  if managing: wm.stop()
  wakeLock(false)
  stopApp()
