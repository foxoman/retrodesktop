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
import xlib, common, theming, wm, link, art, boxes, opener, saver, sounds, panel, deskicons, catalog

var
  conf: Settings
  deskColor = Color(r: 0, g: 128, b: 128, a: 255)
  patternName = "(None)"
  tile: Bitmap                   # the pattern, ready to repeat
  wallPath, wallMode: string
  wall: Bitmap                   # the wallpaper, at the screen's size
  wallTile: Bitmap               # one of the desktop's own wallpapers, a tile
  wallFor: (int, int)            # ... made for this size
  touchMode: bool                # icons open with one tap
  iconSel = -1
  showNoWm: bool
  welcoming = false              # the Welcome is open: Program Manager waits for it
  exiting = false
  exitUntil = 0
  wakeLocked = false
  managing = false
  lowMemory = false
  lowSaid = 0
  raised = false                 # the desktop over the windows (its message is open)

# ---- the settings ------------------------------------------------------------------------------------

let firstTz = getEnv("TZ")       # (the time zone the desktop was started with)

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
  wallTile = nil
  wallFor = (0, 0)
  # (the time zone Control Panel set, for the programs started from now on)
  let tz = conf.setting("timezone", "").strip
  if tz.len > 0: putEnv("TZ", tz)
  elif firstTz.len > 0: putEnv("TZ", firstTz)
  else: delEnv("TZ")
  wm.pauseIconic = conf.setting("pauseIconic", "off") == "on"
  if not wm.pauseIconic: wm.resumeAll()
  touchMode = conf.onOff("touch", inTermux())
  wm.bigFrames = touchMode
  wm.maximizeNew = conf.onOff("maximizeNew", inTermux() and phoneScreen())
  wm.setBackCloses(conf.setting("backKey", "off") == "on")

proc useGpu()

var schemeNow = ""               # the color scheme in use (night colors change it)

proc relook() =
  ## The settings changed (Control Panel): the desktop, its frames and the
  ## other programs take them.
  readSettings()
  schemeNow = currentScheme(conf)
  useGpu()
  if managing:
    showPanel(conf.setting("panel", "on") != "off")
    panelSettings(true, conf.setting("clock24", "on") != "off")
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

# ---- the programs open, kept ------------------------------------------------------------------------

const
  SessionSettings = "retrodesktop-session"
  NotAgain = ["", "session", "desktop", "progman", "tasklist", "run", "about", "exit",
              "welcome", "setup", "open", "saver", "help", "tour", "notify", "storage", "sound",
              "camera", "dialer", "recorder", "share"]
    ## (the desktop's own parts that are not opened again: Program Manager
    ## starts by itself, the rest are dialogs, or ask Android for the
    ## camera, the phone, the microphone, or share the screen)

var
  commands: Table[int, string]   # a process's command line, to start it again ("" not)
  keptSession = ""
  sessionFrozen = false

proc commandOf(c: Client): string =
  ## The command line that starts `c`'s program again.
  if c.class == "RetroBrowser": return selfCommand("browser")
  if commands.hasKey(c.pid): return commands[c.pid]
  var args: seq[string]
  try: args = readFile("/proc/" & $c.pid & "/cmdline").split('\0')
  except CatchableError: args = @[]
  while args.len > 0 and args[^1].len == 0: args.setLen(args.len - 1)
  var quoted: seq[string]
  for a in args: quoted.add quoteShell(a)
  if args.len == 0: result = ""
  elif args[0].extractFilename == "retro-desktop" or args[0] == getAppFilename():
    result = if args.len < 2 or args[1] in NotAgain: "" else: selfCommand(quoted[1 .. ^1].join(" "))
  else: result = quoted.join(" ")
  commands[c.pid] = result

proc sessionNow(): string =
  ## The programs open and where their windows are, a line each.
  var seen: seq[int]
  for c in wm.sessionWindows():
    if c.pid in seen: continue
    seen.add c.pid
    let cmd = commandOf(c)
    if cmd.len == 0: continue
    let g = c.savedGeometry
    result.add [c.class, c.title.replace("\t", " "), cmd, $g.x & "," & $g.y & "," & $g.w & "," & $g.h,
                (if c.maximized: "m" else: "") & (if c.iconic: "i" else: "")].join("\t") & "\n"

proc keepSession() =
  ## The programs open, kept when they changed (Android may end Termux at
  ## any time: the next start opens them again).
  if sessionFrozen or not managing: return
  let now = sessionNow()
  if now == keptSession: return
  keptSession = now
  var s = loadSettings(SessionSettings)
  s["windows"] = now
  discard saveSettings(SessionSettings, s)
  if commands.len > 200: commands.clear()

proc reopen() =
  ## The programs that were open when the desktop ended, opened again, their
  ## windows where they were (not the ones StartUp starts anyway).
  if conf.setting("reopen", "on") == "off": return
  var startup: seq[string]
  for it in progItems():
    if it.group == "StartUp": startup.add it.command
  var started: seq[string]
  let until = epochTime() + 90
  for line in loadSettings(SessionSettings).getOrDefault("windows", "").split('\n'):
    let f = line.split('\t')
    if f.len < 5: continue
    let g = f[3].split(',')
    if g.len == 4:
      try:
        wm.pending.add (class: f[0], title: f[1], x: parseInt(g[0]), y: parseInt(g[1]),
                        w: parseInt(g[2]), h: parseInt(g[3]), maximized: 'm' in f[4],
                        iconic: 'i' in f[4], until: until)
      except ValueError: discard
    let cmd = f[2]
    if cmd.len > 0 and cmd notin started and cmd notin startup:
      started.add cmd
      launch(cmd)

# ---- starting and ending -----------------------------------------------------------------------------

proc running(name: string): bool =
  ## A process called `name` runs (from /proc).
  for kind, path in walkDir("/proc"):
    if not path.extractFilename.allCharsInSet(Digits): continue
    try:
      let args = readFile(path / "cmdline").split('\0')
      if args.len > 0 and args[0].extractFilename == name: return true
    except CatchableError: discard

proc useGpu() =
  ## 3D through Android's GPU (VirGL), when it is installed and not turned
  ## off: its server started, the programs started from now on told to use it.
  let on = conf.setting("gpu", "auto") != "off" and findExe("virgl_test_server_android").len > 0
  if on:
    if not running("virgl_test_server_android"): launch("virgl_test_server_android")
    putEnv("GALLIUM_DRIVER", "virpipe")
    putEnv("MESA_GL_VERSION_OVERRIDE", "4.0")
  elif getEnv("GALLIUM_DRIVER") == "virpipe":
    delEnv("GALLIUM_DRIVER")
    delEnv("MESA_GL_VERSION_OVERRIDE")

var
  tookOver = false
  restStarted = false
  startedAt = 0

proc startPrograms() =
  ## Program Manager first (when it is not open already), and what the
  ## programs need running (the sound, the GPU); the rest -- StartUp, the
  ## programs open last time -- once Program Manager is there (`startRest`):
  ## the desktop is usable sooner. Not when this desktop took the windows of
  ## one before it: they are running.
  tookOver = managing and wm.clients.len > 0
  startedAt = ui.now
  # (the sound, for every program: PulseAudio, when it is installed)
  if findExe("pulseaudio").len > 0 and execShellCmd("pulseaudio --check >/dev/null 2>&1") != 0:
    launch("pulseaudio --start --exit-idle-time=-1")
  useGpu()
  if conf.setting("startProgman", "on") != "off" and findWindow("Program Manager") == 0:
    launch(selfCommand("progman"))
  if not tookOver: playSound("start", conf)

proc startRest() =
  if restStarted: return
  if ui.now - startedAt < 4000 and conf.setting("startProgman", "on") != "off" and
     findWindow("Program Manager") == 0:
    wakeIn(250)
    return
  restStarted = true
  if not tookOver:
    for it in progItems():
      if it.group == "StartUp": launch(it.command)
    reopen()

proc beginExit*() =
  ## Ends the session: every program asked to close its windows, the
  ## desktop goes when they did (or after a few seconds).
  if exiting: return
  exiting = true
  # (what is open now is what opens next time: not the windows closing)
  keepSession()
  sessionFrozen = true
  playSound("exit", conf)
  wm.sound = nil
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
  of RetroAskExit: launch(selfCommand("exit"))
  of RetroWelcomed:
    welcoming = false
    conf = desktopSettings()
    wakeLock(conf.setting("wakeLock", "on") == "on")
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
  if wallPath.startsWith("@"):
    # (one of the desktop's own: a scene, or a tile repeated)
    let name = wallPath[1 .. ^1]
    let dot = max(1, devPx(2.0))
    if name == "Sunset":
      drawSunset(full, max(1, dot div max(1, pxScale)))
    else:
      if wallTile == nil: wallTile = wallpaperTile(name, dot)
      if wallTile != nil:
        let tw = max(1, wallTile.w div max(1, pxScale))
        let th = max(1, wallTile.h div max(1, pxScale))
        var y = 0
        while y < ui.h:
          var x = 0
          while x < ui.w:
            drawBitmap(rect(x, y, tw, th), wallTile)
            x += tw
          y += th
  elif wallPath.len > 0 and fileExists(wallPath) and not lowMemory:
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

proc screenAt(x, y: int): (int, int) =
  ## The screen's pixels of a point of the desktop's (the kit's pixels).
  (x * max(1, pxScale), y * max(1, pxScale))

proc iconMenu(c: Client; x, y: int; above = false) =
  ## The menu of a minimized window's icon, over every window (`above`: its
  ## bottom at `y`, over the icon, as 3.1 opened it).
  let (sx, sy) = screenAt(x, y)
  ui.pressUsed = true                   # (the desktop's own menu not opened too)
  template its(body: untyped): proc () =
    proc () =
      if c in wm.clients: body
  wm.showMenu(@[
    wm.menuItem("&Restore", "", true, its(wm.restore(c))),
    wm.menuItem("Ma&ximize", "", true, its(wm.maximize(c))),
    wm.menuLine(),
    wm.menuItem("&Close", "Alt+F4", true, its(wm.close(c))),
    wm.menuLine(),
    wm.menuItem("S&witch To...", "Ctrl+Esc", true, proc () = openTaskList())], sx, sy, above)

proc drawIcons() =
  ## The windows minimized, as icons along the bottom, left to right, rows
  ## going up as they fill (with the panel shown: on the panel instead).
  if conf.setting("panel", "on") != "off" and managing: return
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
        iconMenu(c, r.x, r.y, above = true)
      else:
        iconSel = i
    elif hit.hover and ui.rpressed:
      iconSel = i
      iconMenu(c, ui.mx, ui.my)

proc desktopMenuItems(): seq[wm.MenuItem] =
  @[wm.menuItem("&Program Manager", "", true, proc () =
      let w = findWindow("Program Manager")
      if w != 0: activate(w) else: launch(selfCommand("progman"))),
    wm.menuItem("&Task List...", "Ctrl+Esc", true, proc () = openTaskList()),
    wm.menuItem("&Control Panel", "", true, proc () = launch(selfCommand("control"))),
    wm.menuItem("T&erminal", "", true, proc () = launch(selfCommand("terminal"))),
    wm.menuItem("&Run...", "", true, proc () = launch(selfCommand("run"))),
    wm.menuLine(),
    wm.menuItem("&Cascade", "", true, proc () = wm.cascade()),
    wm.menuItem("&Tile", "", true, proc () = wm.tile()),
    wm.menuItem("&Arrange Icons", "", true, proc () =
      iconSel = -1
      arrangeDeskIcons()
      x11Wake()),
    wm.menuLine(),
    wm.menuItem("&About Retro Desktop...", "", true, proc () = launch(selfCommand("about"))),
    wm.menuItem("E&xit Retro Desktop...", "", true, proc () = launch(selfCommand("exit")))]

proc desktopMenu() =
  if ui.rpressed and not ui.pressUsed and ui.popup == 0 and ui.dialogTop == 0:
    if managing:
      # (its own window, over every program's -- the desktop is under them)
      let (x, y) = screenAt(ui.mx, ui.my)
      wm.showMenu(desktopMenuItems(), x, y)
    else:
      openPopupMenu("desktop", ui.mx, ui.my)
  popupMenu("desktop"):
    # (with no window manager there are no windows over the desktop: the
    # kit's own menu)
    if menuItem("&Program Manager"):
      let w = findWindow("Program Manager")
      if w != 0: activate(w) else: launch(selfCommand("progman"))
    if menuItem("&Task List...", "Ctrl+Esc"): openTaskList()
    if menuItem("&Control Panel"): launch(selfCommand("control"))
    if menuItem("T&erminal"): launch(selfCommand("terminal"))
    if menuItem("&Run..."): launch(selfCommand("run"))
    menuSeparator()
    if menuItem("&About Retro Desktop..."): launch(selfCommand("about"))
    if menuItem("E&xit Retro Desktop..."): launch(selfCommand("exit"))

# ---- the dialogs --------------------------------------------------------------------------------------

proc keepDialogsInFront() =
  ## The desktop's one message of its own (another window manager runs) is
  ## drawn on the desktop: the desktop over the windows while it is open.
  let modal = showNoWm
  if modal == raised: return
  raised = modal
  let d = Display(x11Display())
  let me = Window(x11Window())
  if modal:
    discard XRaiseWindow(d, me)
    discard XSetInputFocus(d, me, RevertToPointerRoot, CurrentTime)
  else:
    discard XLowerWindow(d, me)
    if managing and wm.active != nil: wm.focus(wm.active)
  discard XFlush(d)

proc dialogs() =
  if showNoWm:
    discard msgBox(showNoWm, DesktopName, "Another window manager is running on this screen, " &
                   "so the desktop does not frame the windows. Close it and start " &
                   DesktopName & " again for the full desktop.", ["OK"], miInfo)

# ---- the screen saver ----------------------------------------------------------------------------------

var saverOn = false

proc watchIdle() =
  ## The screen saver Control Panel chose, once nothing was done for its delay.
  if conf.setting("saver", "(None)") == "(None)" or exiting: return
  var delay = 5
  try: delay = clamp(parseInt(conf.setting("saverDelay", "5")), 1, 120) except ValueError: discard
  let idle = idleMs(Display(x11Display()))
  if idle < 0: return
  if idle >= delay * 60_000:
    if not saverOn:
      saverOn = true
      launch(selfCommand("saver"))
  else:
    saverOn = false
    wakeIn(min(5000, delay * 60_000 - idle + 50))

# ---- memory --------------------------------------------------------------------------------------------

proc watchMemory() =
  onMemoryPressure(proc (level: MemoryPressure) =
    forgetIcons()
    forgetDeskIcons()
    tile = nil
    wallTile = nil
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
  wm.sound = proc (event: string) {.nimcall.} = playSound(event, conf)
  wm.pausedFile = dataDir(SettingsName) / "paused"
  # (programs a desktop before this one paused, and left paused: going on)
  try:
    for line in readFile(wm.pausedFile).splitLines:
      if line.strip.len > 0: discard posix.kill(Pid(parseInt(line.strip)), SIGCONT)
    removeFile(wm.pausedFile)
  except CatchableError: discard
  schemeNow = currentScheme(conf)
  # (the Android apps, for Program Manager's Android group: asked in the background)
  lookForAndroidApps()
  managing = wm.start()
  if not managing: showNoWm = true
  else:
    showPanel(conf.setting("panel", "on") != "off")
    panelSettings(true, conf.setting("clock24", "on") != "off")
  let d = Display(x11Display())
  if d != nil: applyLook(d)
  announceLook()
  installOpener()
  # (Freedoom's levels, where Doom programs look for them)
  putEnv("DOOMWADDIR", gameDataDir("freedoom"))
  # (Termux awake from the start: Android stops a Termux without it as soon
  # as Termux:X11 is in front -- "X server stalled")
  if conf.setting("wakeLock", "on") == "on": wakeLock(true)
  # (the welcome the first time only, not again after an update)
  var welcomeAt = 0
  if conf.setting("welcomed", "") == "":
    welcoming = true
    welcomeAt = ui.now
    launch(selfCommand("welcome"))
  var started = false
  while beginFrame():
    # (a Welcome that never came -- it could not start: the programs anyway)
    if welcoming and ui.now - welcomeAt > 15_000 and findWindow("Welcome to " & DesktopName) == 0:
      welcoming = false
    # (the first time, the welcome first: Program Manager comes after it)
    if not started and not welcoming:
      started = true
      startPrograms()
    if started and not restStarted: startRest()
    drawBackground()
    drawDeskIcons(touchMode)
    drawIcons()
    desktopMenu()
    dialogs()
    keepDialogsInFront()
    if exiting:
      if not managing or wm.clients.len == 0 or ui.now > exitUntil: finishExit()
      else: wakeIn(100)
    else:
      discard memoryPressure()
      if started: keepSession()
      watchIdle()
      panelTick()
      # (night colors: the night's scheme from its hour, the day's after)
      if currentScheme(conf) != schemeNow: relook()
      wakeIn(5000)
    endFrame()
  if managing: wm.stop()
  wakeLock(false)
  stopApp()
