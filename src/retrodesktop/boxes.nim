## The desktop's own dialogs -- Run, About, Exit, the Welcome -- each a window
## of its own, framed by the window manager and over the other windows (drawn
## on the desktop they were under every window, and the desktop had to come
## over all of them while one was open).
##
## Run remembers the command lines it ran (Up, or the list of its field).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, sequtils, times]
import retroui
import common, link, art, sounds

const
  RetroWelcomed* = 8
    ## (the Welcome tells the desktop it was closed: Program Manager and
    ## StartUp start then)
  HistoryMax = 15

proc bringBack(title: string): bool =
  ## A dialog of the desktop's open already: to the front (true), not opened twice.
  let w = findWindow(title)
  if w != 0:
    activate(w)
    return true

proc openBox(title: string; w, h: int; id: string) =
  applyDesktopLook()
  openApp(title, scaled(w), scaled(h), frame = wfSystem, userFrame = false, id = id)
  followLook()
  asDialog()

# ---- Run --------------------------------------------------------------------------------------------

proc runHistory*(): seq[string] =
  for line in desktopSettings().setting("runHistory", "").split('\n'):
    if line.strip.len > 0: result.add line

proc remember(cmd: string) =
  var list = @[cmd]
  for c in runHistory():
    if c != cmd and list.len < HistoryMax: list.add c
  var s = desktopSettings()
  s["runHistory"] = list.join("\n")
  saveDesktopSettings(s)

proc runRunBox*() =
  ## Run: a command line, started on its own (in the Terminal when asked).
  if bringBack("Run"): return
  openBox("Run", 440, 150, "run")
  let history = runHistory()
  var cmd = ""
  var inTerminal = false
  var first = true
  while beginFrame():
    label("&Command Line:")
    comboEdit(cmd, history, w = ui.w - 2 * Pad)
    if first:
      focusFirstText()
      first = false
    checkbox("Run in the &Terminal", inTerminal)
    row:
      spring()
      if button("OK", isDefault = true, enabled = cmd.strip.len > 0):
        let c = cmd.strip
        remember(c)
        launch(if inTerminal: terminalCommand() & " -e " & c else: c)
        quitApp()
      if button("Cancel") or ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()

# ---- About ------------------------------------------------------------------------------------------

proc runAboutBox*() =
  if bringBack("About " & DesktopName): return
  openBox("About " & DesktopName, 460, 250, "about")
  while beginFrame():
    row:
      let s = dp(48)
      let r = canvas(s + dp(12), s)
      drawBitmap(rect(r.x, r.y, s, s), appIcon("logo", devPx(48.0)))
      col:
        label(DesktopName, bold = true)
        label("Version " & DesktopVersion)
        label("A Windows 3.1 style desktop for Linux and Termux on Android.")
    separator()
    label("Developed by Sultan Al Isaiee @foxoman")
    label("www.foxoman.net -- sultan@foxoman.net")
    label("Made with Retro Nim UI. MIT License.", enabled = false)
    label("Memory: " & memoryReport(false), enabled = false)
    row:
      spring()
      if button("OK", isDefault = true) or ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()

# ---- Exit -------------------------------------------------------------------------------------------

proc runExitBox*() =
  if bringBack("Exit " & DesktopName): return
  openBox("Exit " & DesktopName, 400, 130, "exit")
  while beginFrame():
    row:
      msgIcon(miWarning)
      col:
        label("This will end your " & DesktopName & " session.")
        label("Programs still open are asked to close.")
    row:
      spring()
      if button("OK", isDefault = true):
        retroCommand(RetroExit)
        quitApp()
      if button("Cancel") or ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()

# ---- Welcome ----------------------------------------------------------------------------------------

proc runWelcomeBox*() =
  ## The first start's welcome; the desktop starts Program Manager when it closes.
  if bringBack("Welcome to " & DesktopName): return
  openBox("Welcome to " & DesktopName, 560, (if inTermux(): 520 else: 300), "welcome")
  var awake = true
  while beginFrame():
    beginScroll(max(dp(80), ui.h - CtrlH - 3 * Pad), framed = false)
    block:
      row:
        let s = dp(32)
        let r = canvas(s + dp(8), s)
        drawBitmap(rect(r.x, r.y, s, s), appIcon("logo", devPx(32.0)))
        label(DesktopName & " " & DesktopVersion, bold = true)
      paragraph "This is your desktop: every program opens here in its own window, " &
        "with a title bar to move it by, borders to size it by, and the buttons to " &
        "minimize and maximize it. Program Manager holds your programs; Setup (in its " &
        "Main group) installs more -- browsers, office, games."
      paragraph "A right click on the desktop (or a finger held on it) opens its menu. " &
        "Alt+Tab goes to the next window, Alt+F4 closes one, Ctrl+Esc opens the Task List. " &
        "Control Panel changes the colors, the fonts, the sizes and the desktop."
      if inTermux():
        label("Keep it running on Android", bold = true)
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
        checkbox("&Keep Termux awake while the desktop runs (termux-wake-lock)", awake)
    endScroll()
    row:
      if button("Take the &Tour"):
        launch(selfCommand("tour"))
        quitApp()
      spring()
      if button("OK", isDefault = true): quitApp()
    endFrame()
    appFrameDone()
  var s = desktopSettings()
  s["welcomed"] = DesktopVersion
  if inTermux(): s["wakeLock"] = (if awake: "on" else: "off")
  saveDesktopSettings(s)
  retroCommand(RetroWelcomed)
  closeApp()

# ---- Android Files ----------------------------------------------------------------------------------

proc runStorage*() =
  ## The phone's shared storage (photos, downloads, documents) in File
  ## Manager; the first time, Termux asks Android to let it see them.
  let shared = getHomeDir() / "storage" / "shared"
  proc show() =
    let files = companion("retro-files")
    if files.len > 0: launch(quoteShell(files) & " " & quoteShell(shared))
    else: launch(terminalCommand() & " -e sh -c " & quoteShell("cd " & quoteShell(shared) & "; exec sh"))
  if dirExists(shared):
    show()
    return
  if bringBack("Android Files"): return
  openBox("Android Files", 460, 170, "storage")
  var asked = false
  var until = 0
  while beginFrame():
    row:
      msgIcon(miQuestion)
      col:
        if not asked:
          label("Android keeps your photos, downloads and documents apart from Termux.")
          label("Let Termux see them? Android asks you (termux-setup-storage).")
        elif ui.now < until:
          label("Waiting for Android: answer its question (Allow) and come back.")
          label("(It may ask in the Terminal first: answer y.)")
        else:
          label("Termux cannot see the phone's files yet.")
          label("Android > Settings > Apps > Termux > Permissions > Files allows it.")
    row:
      spring()
      if not asked:
        if button("&Allow...", isDefault = true):
          asked = true
          until = ui.now + 120_000
          launch(terminalCommand() & " -e termux-setup-storage")
        if button("Cancel") or ui.key == KeyEsc: quitApp()
      elif button(if ui.now < until: "Cancel" else: "OK", isDefault = ui.now >= until):
        quitApp()
    if asked:
      if dirExists(shared):
        show()
        quitApp()
      wakeIn(500)
    endFrame()
    appFrameDone()
  closeApp()

# ---- notifications ----------------------------------------------------------------------------------

proc runNotify*(args: seq[string]) =
  ## `notify-send`'s words: SUMMARY [BODY], with its options (-u critical,
  ## -t ms, -i, -a...). In Termux with Termux:API an Android notification;
  ## else a box at the bottom right of the screen for a few seconds.
  var words: seq[string]
  var ms = 6000
  var urgent = false
  var i = 0
  while i < args.len:
    let a = args[i]
    if a in ["-u", "--urgency", "-t", "--expire-time", "-i", "--icon", "-a", "--app-name",
             "-c", "--category", "-h", "--hint", "-r", "--replace-id", "-A", "--action"]:
      if i + 1 < args.len:
        if a in ["-u", "--urgency"]: urgent = args[i + 1] == "critical"
        if a in ["-t", "--expire-time"]:
          try: ms = max(1000, parseInt(args[i + 1])) except ValueError: discard
      i += 2
      continue
    if a.startsWith("--urgency="): urgent = a.endsWith("critical")
    elif a.startsWith("-"): discard
    else: words.add a
    inc i
  if words.len == 0: return
  let title = words[0]
  let body = if words.len > 1: words[1 .. ^1].join(" ") else: ""
  # (kept for the panel's list: the last 50)
  try:
    let file = dataDir(SettingsName) / "notifications"
    var lines = (if fileExists(file): readFile(file).splitLines else: @[])
    lines.keepItIf(it.len > 0)
    lines.add now().format("HH:mm") & "\t" & title.replace("\t", " ").replace("\n", " ") & "\t" &
              body.replace("\t", " ").replace("\n", " ")
    if lines.len > 50: lines = lines[^50 .. ^1]
    writeFile(file, lines.join("\n") & "\n")
  except CatchableError: discard
  playSound("notify")
  if inTermux() and findExe("termux-notification").len > 0:
    launch("termux-notification --title " & quoteShell(title) & " --content " & quoteShell(body) &
           (if urgent: " --priority high" else: ""))
    return
  applyDesktopLook()
  openApp(title, scaled(340), scaled(96), frame = wfSystem, userFrame = false, id = "notify")
  followLook()
  asDialog(-12, -12)
  var until = 0
  while beginFrame():
    if until == 0: until = ui.now + ms
    row:
      msgIcon(if urgent: miWarning else: miInfo)
      col:
        label(title, bold = true, literal = true)
        if body.len > 0: paragraph body
    if ui.pressed or ui.key == KeyEsc or ui.now >= until: quitApp()
    wakeIn(max(10, until - ui.now))
    endFrame()
    appFrameDone()
  closeApp()

# ---- Taskbar Properties -----------------------------------------------------------------------------

const PanelEdges = ["bottom", "top", "left", "right"]

proc drawPanelPreview(edge: int; onTop, autoHide, clock: bool) =
  ## A little screen with the panel as chosen: on its edge, over a window
  ## or under it, hidden to a line.
  let t = ui.theme
  let r = canvas(ui.w - 2 * Pad, dp(110))
  let sw = min(r.w, dp(220))
  let scr = rect(r.x + (r.w - sw) div 2, r.y, sw, r.h)
  fill(scr, t.frame)
  let s = rect(scr.x + dp(4), scr.y + dp(4), scr.w - dp(8), scr.h - dp(8))
  fill(s, hexColor(Teal, color(0, 128, 128)))
  let th = if autoHide: max(2, dp(2)) else: dp(13)
  let sideW = if autoHide: max(2, dp(2)) else: dp(34)
  let bar = case edge
            of 1: rect(s.x, s.y, s.w, th)
            of 2: rect(s.x, s.y, sideW, s.h)
            of 3: rect(s.x + s.w - sideW, s.y, sideW, s.h)
            else: rect(s.x, s.y + s.h - th, s.w, th)
  let win = rect(s.x + s.w div 5, s.y + s.h div 6, s.w * 3 div 5, s.h * 2 div 3 + dp(6))
  proc drawWin() =
    fill(win, t.window)
    box(win, t.frame)
    fill(rect(win.x + 1, win.y + 1, win.w - 2, dp(9)), t.select)
  proc drawBar() =
    fill(bar, t.face)
    if autoHide: return
    let horizontal = edge in [0, 1]
    let b = if horizontal: rect(bar.x + dp(2), bar.y + dp(2), dp(16), bar.h - dp(4))
            else: rect(bar.x + dp(2), bar.y + dp(2), bar.w - dp(4), dp(9))
    raised(b, 1)
    if clock:
      let c = if horizontal: rect(bar.x + bar.w - dp(24), bar.y + dp(2), dp(22), bar.h - dp(4))
              else: rect(bar.x + dp(2), bar.y + bar.h - dp(11), bar.w - dp(4), dp(9))
      sunken(c)
  if onTop:
    drawWin()
    drawBar()
  else:
    drawBar()
    drawWin()

proc runTaskbarBox*() =
  ## Taskbar Properties, as 95's: where the panel is, whether it stays over
  ## the windows or hides itself, the Start menu's pictures, the clock; and
  ## the Start menu's Documents emptied.
  const Title = "Taskbar Properties"
  if bringBack(Title): return
  openBox(Title, 440, 370, "taskbar")
  let conf = desktopSettings()
  var edge = max(0, PanelEdges.find(conf.setting("panelEdge", "bottom")))
  var onTop = conf.setting("panelOnTop", "on") != "off"
  var autoHide = conf.setting("panelAutoHide", "off") == "on"
  var small = conf.setting("startSmallIcons", "off") == "on"
  var clock = conf.setting("panelClock", "on") != "off"
  var h24 = conf.setting("clock24", "on") != "off"
  var tab = 0
  var docs = recentDocuments().len
  template now(): untyped = (edge, onTop, autoHide, small, clock, h24)
  var saved = now()
  proc keep(v: tuple[edge: int; onTop, autoHide, small, clock, h24: bool]) =
    var s = desktopSettings()
    s["panelEdge"] = PanelEdges[v.edge]
    s["panelOnTop"] = (if v.onTop: "on" else: "off")
    s["panelAutoHide"] = (if v.autoHide: "on" else: "off")
    s["startSmallIcons"] = (if v.small: "on" else: "off")
    s["panelClock"] = (if v.clock: "on" else: "off")
    s["clock24"] = (if v.h24: "on" else: "off")
    saveDesktopSettings(s)
    retroCommand(RetroLookChanged)
  while beginFrame():
    tabs(tab, ["Taskbar &Options", "&Start Menu Programs"]):
      if tab == 0:
        drawPanelPreview(edge, onTop, autoHide, clock)
        row:
          label("&Position:")
          radio("&Bottom", edge, 0)
          radio("To&p", edge, 1)
          radio("&Left", edge, 2)
          radio("&Right", edge, 3)
        checkbox("&Always on top", onTop)
        checkbox("A&uto hide", autoHide)
        checkbox("Show s&mall icons in Start menu", small)
        checkbox("Show &Clock", clock)
        checkbox("24-&hour clock", h24, enabled = clock)
        paragraph("The taskbar can also be dragged by its empty part to any edge of the " &
                  "screen, and made larger by its inner edge.")
      else:
        group("Documents Menu"):
          paragraph("The files you open are kept in the Start menu's Documents. To empty it, press Clear.")
          row:
            spring()
            if button("C&lear", enabled = docs > 0):
              clearRecent()
              docs = 0
        group("Programs"):
          paragraph("The Start menu's Programs are Program Manager's groups: add, remove or " &
                    "arrange your programs there.")
          row:
            spring()
            if button("Program &Manager..."): launch(selfCommand("progman"))
    row:
      spring()
      if button("OK", isDefault = true):
        if now() != saved: keep(now())
        quitApp()
      if button("Cancel") or ui.key == KeyEsc: quitApp()
      if button("&Apply", enabled = now() != saved):
        keep(now())
        saved = now()
    endFrame()
    appFrameDone()
  closeApp()
