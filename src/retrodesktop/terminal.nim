## Terminal: a shell in a window, as the desktop's own MS-DOS Prompt -- in
## the 16 colors of a PC's text screen, black on white as Windows' windows
## (or MS-DOS's gray on black), bold letters in the bright colors as a PC
## showed them. Underneath it is Retro Nim UI's terminal (`retroui/terminal`):
## xterm's escape sequences for full-screen programs (vim, nano, htop, mc,
## less), kitty's keyboard protocol for the programs that ask for it
## (neovim, helix, kakoune), the pictures they send by kitty's graphics
## protocol (chafa, timg, yazi), the cursor's shapes, mouse reports for the
## programs that take the mouse, a scrollback to wheel through, selecting
## with the mouse, copy and paste, finding.
##
## The shell runs on a pseudo-terminal that the window's own wait for X
## events watches: the terminal takes no CPU while nothing happens.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retroui, retroui/terminal
import common, link, help

const TermSettings = "retrodesktop-terminal"

const Cga = [
  # (a PC's 16 text colors, as MS-DOS showed them)
  (0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0), (0, 0, 170), (170, 0, 170),
  (0, 170, 170), (170, 170, 170), (85, 85, 85), (255, 85, 85), (85, 255, 85),
  (255, 255, 85), (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255)]

var
  term: Terminal
  whiteScheme = true             ## black on white, as Windows' own windows (MS-DOS Colors: gray on black)
  showAbout = false
  findOpen = false
  findFocus = false              ## (the find box takes the keys, the bar just opened)
  findWhat = ""
  findCase = false
  found = true

proc cga(i: int): Color = color(uint8(Cga[i][0]), uint8(Cga[i][1]), uint8(Cga[i][2]))

proc pcColors(): TermColors =
  ## The terminal's colors: the PC's 16, on white (Windows) or on black
  ## (MS-DOS); the text chosen in 3.1's highlight, white on navy.
  for i in 0 .. 15: result.ansi[i] = cga(i)
  if whiteScheme:
    result.fg = cga(0)
    result.bg = cga(15)
  else:
    result.fg = cga(7)
    result.bg = cga(0)
  result.cursor = result.fg
  result.selection = color(0, 0, 128)

proc shellCommand(args: seq[string]): seq[string] =
  ## What runs in the terminal: the command after -e, else the user's shell
  ## (Termux's login, which sets Termux up; $SHELL; bash; sh).
  if args.len > 0:
    return @["/bin/sh", "-c", args.join(" ")]
  let pfx = prefixDir()
  if existsEnv("TERMUX_VERSION") and fileExists(pfx / "bin" / "login"):
    return @[pfx / "bin" / "login"]
  let sh = getEnv("SHELL")
  if sh.len > 0 and fileExists(sh): return @[sh, "-l"]
  for s in ["bash", "zsh", "sh"]:
    let p = findExe(s)
    if p.len > 0: return @[p, "-l"]
  @["/bin/sh"]

proc keepSettings() =
  var s = loadSettings(TermSettings)
  s["colors"] = (if whiteScheme: "white" else: "dos")
  s["font"] = formatFloat(term.fontSize, ffDecimal, 2)
  s["bold"] = (if term.boldText: "1" else: "0")
  s["pictures"] = (if term.picsOn: "1" else: "0")
  discard saveSettings(TermSettings, s)

proc openFind() =
  findOpen = true
  findFocus = true

proc findBar() =
  ## Edit > Find (Ctrl+Shift+F): a bar over the screen that finds in all it
  ## kept, from the bottom up, as it is typed.
  var close = false
  row([-1, 0, 0, 0, 0]):
    # (Enter in the box: the next one up; Esc: the bar closed, before the box
    # would take it to empty itself -- the terminal's own while it has the keys)
    if findFocus:
      ui.focus = peekId(findWhat, "search")
      findFocus = false
    let inBox = ui.focus == peekId(findWhat, "search")
    if inBox:
      ui.takesEnter = true
      if ui.key == KeyEsc and not ui.keyUsed:
        ui.keyUsed = true
        close = true
    if searchBox(findWhat, tr("Find in the terminal")):
      term.selectNone()
      found = findWhat.len == 0 or term.findText(findWhat, matchCase = findCase)
    checkbox("Match &case", findCase)
    let back = button("&Previous") or (inBox and keyHit(KeyEnter))
    let on = button("Ne&xt")
    if back or on: found = term.findText(findWhat, back = not on, matchCase = findCase)
    if button("Close"): close = true
  if close:
    findOpen = false
    found = true
    ui.focus = 0                   # (the terminal takes the keys again)
  elif not found: label(tr("No more of it."), color = badColor())

proc runTerminal*(args: seq[string]) =
  ## The terminal, until its shell ends (or its window is closed: the shell
  ## is told the terminal hung up).
  let s = loadSettings(TermSettings)
  whiteScheme = s.getOrDefault("colors", "white") == "white"
  var lines = 3000
  try: lines = clamp(parseInt(s.getOrDefault("scrollback", "3000")), 100, 100_000) except ValueError: discard
  applyDesktopLook()
  openApp("Terminal", scaled(680), scaled(460), frame = wfSystem, userFrame = false, id = "terminal")
  showArt("terminal")
  followLook()
  term = newTerminal(80, 25, lines)
  term.themed = false
  term.colors = pcColors()
  term.boldBright = true
  term.boldText = s.getOrDefault("bold", "1") == "1"
  term.picsOn = s.getOrDefault("pictures", "1") == "1"
  try: term.fontSize = clamp(parseFloat(s.getOrDefault("font", "1.0")), 0.5, 3.0) except ValueError: discard
  var started = false
  var failed = false
  var lastTitle = ""
  var lastSize = term.fontSize
  while beginFrame():
    helpKeys("terminal")
    # (the program gets Alt and a letter -- bash's words -- and F10, before
    # the menu bar would take them: its menus have the mouse, and Alt alone)
    terminalKeysFirst(term)
    menubar:
      menu "&Edit":
        term.terminalEditItems()
        menuSeparator()
        if menuItem("&Find...", "Ctrl+Shift+F"): openFind()
        menuSeparator()
        term.terminalItems()
      menu "&Settings":
        if menuItem("&MS-DOS Colors", checked = not whiteScheme):
          whiteScheme = false
          term.colors = pcColors()
          keepSettings()
        if menuItem("&Windows Colors", checked = whiteScheme):
          whiteScheme = true
          term.colors = pcColors()
          keepSettings()
        menuSeparator()
        if menuItem("Bold &Letters", checked = term.boldText):
          term.boldText = not term.boldText
          keepSettings()
        if menuItem("&Pictures from Programs", checked = term.picsOn):
          term.picsOn = not term.picsOn
          keepSettings()
        menuSeparator()
        term.terminalViewItems()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("terminal")
        menuSeparator()
        if menuItem("&About Terminal..."): showAbout = true
    if ui.key == KeyF and ui.mods * {CtrlPressed, ShiftPressed} == {CtrlPressed, ShiftPressed} and
       not ui.keyUsed and canInput():
      # (Ctrl+Shift+F: the find bar -- taken before the terminal sends it on)
      ui.keyUsed = true
      openFind()
    if findOpen: findBar()
    terminalView(term, lines = -1, focusFirst = true, menu = proc () =
      if menuItem("&Find...", "Ctrl+Shift+F"): openFind())
    # (the shell started once the view gave the terminal its size)
    if not started and not failed:
      if term.spawn(shellCommand(args), cwd = getHomeDir()):
        started = true
      else:
        failed = true
        term.feed("Retro Desktop could not start a shell here: " & term.error & "\r\n")
    if started and not term.running: quitApp()
    if term.fontSize != lastSize:
      lastSize = term.fontSize
      keepSettings()
    if term.title != lastTitle:
      lastTitle = term.title
      setTitle(if term.title.len > 0: term.title else: "Terminal")
    aboutBox(showAbout, "Terminal", DesktopVersion,
             ["A shell in a window, in a PC's 16 text colors.",
              "The terminal type it says it is: xterm-256color."])
    endFrame()
    appFrameDone()
  if started and term.running: term.stop()
  closeApp()
