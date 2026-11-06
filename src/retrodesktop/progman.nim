## Program Manager: the programs, in groups -- Main and Accessories with the
## desktop's own, StartUp with what starts with the desktop, and a group for
## each kind of program installed (every program with a desktop entry:
## Applications, Internet, Office, Development, Graphics, Multimedia, System,
## Games). A double click (a tap) starts one; File > New puts a program of
## your own in a group.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, tables, math]
import retroui
import common, link, art, help

type
  Item = object
    name, command, comment: string
    art: string              ## the desktop's own picture ("" none)
    icon: string             ## an icon theme's name or a file ("" none)
    terminal: bool
    custom: int              ## its place in `progItems` (-1: not the user's)

  Group = ref object
    name: string
    items: seq[Item]
    win: MdiWindow
    sel: int
    marked: seq[bool]

const
  GroupOrder = ["Main", "Accessories", "Applications", "Internet", "Office", "Development",
                "Graphics", "Multimedia", "System", "Games", "DOS", "StartUp"]


var
  groups: seq[Group]
  icons: Table[string, Bitmap]
  minimizeOnUse = false
  saveOnExit = true
  showNew, showProps, showAbout, showDelete: bool
  newName, newCommand, newIcon: string
  newGroup = 0
  propsGroup: Group
  propsIndex = -1
  lastGroup: Group

# ---- the items ----------------------------------------------------------------------------------------

proc builtin(name, command, art, comment: string): Item =
  Item(name: name, command: command, art: art, comment: comment, custom: -1)

proc companionItem(name, exe, art, comment: string; list: var seq[Item]) =
  ## A program that comes with the desktop, when it is installed.
  let p = companion(exe)
  if p.len > 0:
    var it = builtin(name, quoteShell(p), art, comment)
    it.icon = exe
    list.add it

proc pickExe(folder: string): string =
  ## The program a DOS game's folder starts with: one named like the folder,
  ## else its .BAT, else its largest .EXE (not SETUP or INSTALL).
  var best = ""
  var bestScore = -1
  let stem = folder.extractFilename.toLowerAscii
  for kind, path in walkDir(folder):
    if kind notin {pcFile, pcLinkToFile}: continue
    let (_, name, ext) = path.splitFile
    let e = ext.toLowerAscii
    if e notin [".exe", ".com", ".bat"]: continue
    let n = name.toLowerAscii
    if n in ["setup", "install", "uninst", "uninstal", "config", "setsound", "readme"]: continue
    var score = int(min(getFileSize(path), 9_000_000) div 1000)
    if n.len >= 3 and stem.startsWith(n[0 ..< min(n.len, 4)]): score += 50_000
    if e == ".bat": score += 20_000
    if score > bestScore:
      bestScore = score
      best = path
  best

proc dosItems(): seq[Item] =
  ## DOSBox-X with ~/DOS as its drive C:, and a program for each game there
  ## (a folder each, or a program at its top) -- when DOSBox-X is installed.
  let box = findExe("dosbox-x")
  if box.len == 0: return
  let dir = dosDir()
  try:
    if not dirExists(dir):
      createDir(dir)
      writeFile(dir / "README.TXT", "Put your DOS games and programs here, a folder each. Program " &
                "Manager's DOS group shows them, and DOSBox-X runs them with this folder as drive C:.\r\n")
  except CatchableError: discard
  proc run(rel: string): string =
    result = quoteShell(box) & " -fastlaunch -c " & quoteShell("mount c \"" & dir & "\"") & " -c c:"
    if rel.len > 0:
      let folder = rel.parentDir
      if folder.len > 0 and folder != ".": result &= " -c " & quoteShell("cd \\" & folder.replace("/", "\\"))
      result &= " -c " & quoteShell(rel.extractFilename)
  result.add builtin("DOSBox-X", run(""), "dos", "A DOS PC; the folder DOS in your home is its drive C:")
  for kind, path in walkDir(dir):
    if kind in {pcDir, pcLinkToDir}:
      let exe = pickExe(path)
      if exe.len > 0:
        result.add builtin(path.extractFilename, run(exe.relativePath(dir)), "dos",
                           "In DOSBox-X: " & exe.relativePath(dir))
    elif path.splitFile.ext.toLowerAscii in [".exe", ".com", ".bat"]:
      result.add builtin(path.splitFile.name, run(path.extractFilename), "dos", "In DOSBox-X")

proc groupNamed(name: string): Group =
  for g in groups:
    if g.name == name: return g
  result = Group(name: name, win: MdiWindow(title: name, open: true, glyph: pxWindow, noPin: true))
  groups.add result

proc placeWindows() =
  ## Where each group's window is: as kept, else a cascade (the first two
  ## open, the rest icons, as 3.1 had them).
  let s = loadSettings(ProgmanSettings)
  minimizeOnUse = s.getOrDefault("minimizeOnUse", "0") == "1"
  saveOnExit = s.getOrDefault("saveOnExit", "1") == "1"
  for i, g in groups:
    let v = s.getOrDefault("win." & g.name, "").split(',')
    if v.len >= 6:
      try:
        g.win.r = rect(parseInt(v[0]), parseInt(v[1]), parseInt(v[2]), parseInt(v[3]))
        g.win.minimized = v[4] == "1"
        g.win.maximized = v[5] == "1"
        continue
      except ValueError: discard
    # (Main above Accessories, the rest as icons, as 3.1 came)
    case g.name
    of "Main": g.win.r = rect(dp(8), dp(8), dp(440), dp(170))
    of "Accessories": g.win.r = rect(dp(28), dp(190), dp(440), dp(190))
    else: g.win.r = rect(dp(8 + i * 20), dp(8 + i * 20), dp(400), dp(200))
    g.win.minimized = g.name notin ["Main", "Accessories"]

proc saveWindows() =
  var s = loadSettings(ProgmanSettings)
  s["minimizeOnUse"] = (if minimizeOnUse: "1" else: "0")
  s["saveOnExit"] = (if saveOnExit: "1" else: "0")
  for g in groups:
    let r = g.win.r
    s["win." & g.name] = [$r.x, $r.y, $r.w, $r.h, (if g.win.minimized: "1" else: "0"),
                          (if g.win.maximized: "1" else: "0")].join(",")
  discard saveSettings(ProgmanSettings, s)

proc loadGroups() =
  ## Every group, from the desktop's programs, the installed ones and the
  ## user's own (the windows where they were).
  let before = groups
  groups = @[]
  var main, acc: seq[Item]
  companionItem("File Manager", "retro-files", "files", "Retro Files: folders and files", main)
  main.add builtin("Control Panel", selfCommand("control"), "control",
                   "Colors, fonts, sizes, the desktop")
  main.add builtin("Task List", selfCommand("tasklist"), "tasklist",
                   "The windows open, and the memory each takes")
  main.add builtin("Terminal", selfCommand("terminal"), "terminal",
                   "The shell's command line, in a PC's 16 text colors")
  # (Retro Browser asks to install Firefox when it is not there)
  main.add builtin("Web Browser", selfCommand("browser"), "browser",
                   "Retro Browser: Firefox in the desktop's look, on a profile of its own")
  main.add builtin("Setup", selfCommand("setup"), "setup",
                   "Programs to install, from Termux's packages: browsers, office, games...")
  if inTermux():
    main.add builtin("Android Files", selfCommand("storage"), "storage",
                     "Your phone's photos, downloads and documents, in File Manager")
  main.add builtin("Read Me", "?help", "readme", "How the desktop works")
  companionItem("Notepad", "retro-notepad", "notepad", "Text files", acc)
  companionItem("Paintbrush", "retro-photo", "paint", "Retro Photo: pictures and painting", acc)
  companionItem("Board", "retro-board", "board", "Retro Board: a whiteboard for drawings and notes", acc)
  companionItem("Mail", "retro-mail", "mail", "Retro Mail", acc)
  companionItem("Gallery", "retro-gallery", "gallery", "Retro Gallery: every control of Retro Nim UI", acc)
  acc.add builtin("Write", selfCommand("write"), "write", "Documents with bold, italic, sizes and lists")
  acc.add builtin("Clipboard Viewer", selfCommand("clipboard"), "clipboard", "What was copied last")
  acc.add builtin("Calculator", selfCommand("calc"), "calc", "A calculator")
  acc.add builtin("Calendar", selfCommand("calendar"), "calendar", "Days, with notes and appointments")
  acc.add builtin("Cardfile", selfCommand("cardfile"), "cardfile", "Cards of names, numbers and notes")
  acc.add builtin("Clock", selfCommand("clock"), "clock", "The time, on a face or in numbers")
  groupNamed("Main").items = main
  groupNamed("Accessories").items = acc
  var games = @[
    builtin("Minesweeper", selfCommand("mines"), "mines", "Find the mines without stepping on one"),
    builtin("Solitaire", selfCommand("solitaire"), "cards", "Klondike, as 3.1 had it"),
    builtin("Reversi", selfCommand("reversi"), "reversi", "Turn the computer's pieces over")]
  # (Freedoom, once Setup put it here)
  let doom = findExe("chocolate-doom")
  let wads = gameDataDir("freedoom")
  if doom.len > 0:
    for (name, wad) in [("Freedoom", "freedoom1.wad"), ("Freedoom: Phase 2", "freedoom2.wad")]:
      if fileExists(wads / wad):
        games.add builtin(name, quoteShell(doom) & " -iwad " & quoteShell(wads / wad), "doom",
                          "A free Doom, in Chocolate Doom")
  groupNamed("Games").items = games
  let dos = dosItems()
  if dos.len > 0: groupNamed("DOS").items = dos
  for e in installedApps():
    groupNamed(groupOf(e)).items.add Item(name: e.name, command: e.command, comment: e.comment,
                                          icon: e.icon, terminal: e.terminal, custom: -1)
  discard groupNamed("StartUp")
  for i, it in progItems():
    groupNamed(if it.group.len > 0: it.group else: "Applications").items.add Item(
      name: it.name, command: it.command, icon: it.icon, custom: i, art: (if it.icon.len == 0: "app" else: ""))
  # (in 3.1's order; the user's own groups after)
  var ordered: seq[Group]
  for n in GroupOrder:
    for g in groups:
      if g.name == n and (g.items.len > 0 or n in ["Main", "Accessories", "StartUp"]): ordered.add g
  for g in groups:
    if g.name notin GroupOrder: ordered.add g
  groups = ordered
  if before.len == 0:
    placeWindows()
  else:
    # (a refresh: the windows stay where they are)
    for g in groups:
      for b in before:
        if b.name == g.name:
          g.win = b.win
          g.sel = b.sel
  for g in groups:
    g.sel = clamp(g.sel, 0, max(0, g.items.len - 1))

# ---- starting -----------------------------------------------------------------------------------------

proc pictureOf(it: Item; px: int): Bitmap =
  let key = it.icon & "|" & it.art & "@" & $px
  if icons.hasKey(key): return icons[key]
  var b: Bitmap = nil
  if it.icon.len > 0: b = loadIcon(it.icon, px)
  if b == nil: b = appIcon(if it.art.len > 0: it.art else: "app", px)
  if icons.len > 400: icons.clear()
  icons[key] = b
  b

proc start(it: Item) =
  case it.command
  of "?help": openHelp("desktop")
  else:
    var cmd = it.command
    if it.terminal: cmd = terminalCommand() & " -e " & cmd
    launch(cmd)
    if minimizeOnUse: minimizeSelf()

# ---- the frame ----------------------------------------------------------------------------------------

proc groupView(g: Group) =
  let px = devPx(32.0)
  if g.marked.len != g.items.len: g.marked = newSeq[bool](g.items.len)
  let ev = iconView(g.items.len,
    proc (i: int): string = g.items[i].name,
    proc (i: int; r: Rect) =
      let s = dp(32)
      drawBitmap(rect(r.x + (r.w - s) div 2, r.y + (r.h - s) div 2, s, s), pictureOf(g.items[i], px)),
    g.sel, g.marked, height = -1, tapActivates = fingers() or isMobile())
  if ev.activated and g.sel in 0 ..< g.items.len: start(g.items[g.sel])
  if ev.selChanged: lastGroup = g
  if ev.rightClicked:
    lastGroup = g
    g.sel = clamp(ev.row, 0, max(0, g.items.len - 1))
    openPopupMenu("item", ui.mx, ui.my)
  if g.items.len == 0:
    label(if g.name == "StartUp": "Programs here start with the desktop: File > New..."
          else: "(empty)", enabled = false)

proc activeGroup(): Group =
  for g in groups:
    if mdiIsActive(g.win): return g
  if lastGroup != nil: lastGroup
  elif groups.len > 0: groups[0]
  else: nil

proc menus() =
  let g = activeGroup()
  let hasItem = g != nil and g.sel in 0 ..< g.items.len
  menubar:
    menu "&File":
      if menuItem("&New...", "Ctrl+N"):
        showNew = true
        newName = ""
        newCommand = ""
        newIcon = ""
        newGroup = max(0, groups.find(g))
        focusFirstText(inDialog = true)
      if menuItem("&Open", "Enter", enabled = hasItem): start(g.items[g.sel])
      if menuItem("&Delete", "Del", enabled = hasItem and g.items[g.sel].custom >= 0):
        showDelete = true
      if menuItem("&Properties...", "Alt+Enter", enabled = hasItem):
        propsGroup = g
        propsIndex = g.sel
        showProps = true
      menuSeparator()
      if menuItem("&Run..."): launch(selfCommand("run"))
      menuSeparator()
      if menuItem("E&xit Retro Desktop..."): retroCommand(RetroAskExit)
    menu "&Options":
      if menuItem("&Minimize on Use", checked = minimizeOnUse): minimizeOnUse = not minimizeOnUse
      if menuItem("&Save Settings on Exit", checked = saveOnExit): saveOnExit = not saveOnExit
      menuSeparator()
      if menuItem("&Refresh", "F5"): loadGroups()
    menu "&Window":
      mdiWindowMenu()
    menu "&Help":
      if menuItem("&Help Topics", "F1"): openHelp("progman")
      if menuItem("&Read Me"): openHelp("desktop")
      if menuItem("&Tour..."): launch(selfCommand("tour"))
      menuSeparator()
      if menuItem("&About Program Manager..."): showAbout = true
  if hotkeyPressed("Ctrl+N"):
    showNew = true
    focusFirstText(inDialog = true)
  if hotkeyPressed("F5"): loadGroups()
  if hotkeyPressed("Shift+F5"): mdiCascade()
  if hotkeyPressed("Shift+F4"): mdiTile()
  if hotkeyPressed("F1"): openHelp("progman")
  if hotkeyPressed("Alt+Enter") and hasItem:
    propsGroup = g
    propsIndex = g.sel
    showProps = true
  if hotkeyPressed("Delete") and hasItem and g.items[g.sel].custom >= 0: showDelete = true
  popupMenu("item"):
    let g2 = lastGroup
    if g2 != nil and g2.sel in 0 ..< g2.items.len:
      if menuItem("&Open"): start(g2.items[g2.sel])
      if menuItem("&Properties..."):
        propsGroup = g2
        propsIndex = g2.sel
        showProps = true
      if g2.items[g2.sel].custom >= 0:
        if menuItem("&Delete"): showDelete = true

proc groupNames(): seq[string] =
  for g in groups: result.add g.name

proc dialogs() =
  if showNew:
    dialog(showNew, "New Program Item", 460):
      form 0:
        field "&Description:": edit newName
        field "&Command Line:": edit newCommand
        field "&Group:": combo(groupNames(), newGroup)
        field "&Icon:": edit newIcon
      label "The icon: an icon theme's name (firefox) or a picture file; empty for the desktop's.",
            enabled = false
      row:
        spring()
        if button("OK", isDefault = true, enabled = newName.strip.len > 0 and newCommand.strip.len > 0):
          var items = progItems()
          items.add ProgItem(group: groups[clamp(newGroup, 0, groups.high)].name,
                             name: newName.strip, command: newCommand.strip, icon: newIcon.strip)
          saveProgItems(items)
          showNew = false
          loadGroups()
        if button("Cancel"): showNew = false
  if showProps and propsGroup != nil and propsIndex in 0 ..< propsGroup.items.len:
    let it = propsGroup.items[propsIndex]
    dialog(showProps, "Program Item Properties", 460):
      row:
        let s = dp(32)
        let r = canvas(s + dp(8), s)
        drawBitmap(rect(r.x, r.y, s, s), pictureOf(it, devPx(32.0)))
        heading it.name
      form 0:
        field "Command Line:": label(it.command, literal = true)
        if it.comment.len > 0:
          field "Comment:": label(it.comment, literal = true)
        field "Group:": label propsGroup.name
      row:
        spring()
        if button("&Run"):
          start(it)
          showProps = false
        if button("OK", isDefault = true): showProps = false
  if showDelete:
    let g = activeGroup()
    if g != nil and g.sel in 0 ..< g.items.len and g.items[g.sel].custom >= 0:
      let r = msgBox(showDelete, "Delete", "Delete \"" & g.items[g.sel].name & "\"?",
                     ["&Yes", "&No"], miQuestion)
      if r == 1:
        var items = progItems()
        let k = g.items[g.sel].custom
        if k in 0 ..< items.len: items.delete(k)
        saveProgItems(items)
        loadGroups()
    else: showDelete = false
  aboutBox(showAbout, "Program Manager", DesktopVersion,
           [DesktopName & " " & DesktopVersion, "Memory: " & memoryReport(false)])

proc runProgman*() =
  ## Program Manager, until it is closed.
  applyDesktopLook()
  openApp("Program Manager", scaled(720), scaled(480), frame = wfSystem, userFrame = false, id = "progman")
  showArt("progman")
  followLook(proc () = icons.clear())
  loadGroups()
  onMemoryPressure(proc (level: MemoryPressure) =
    icons.clear()
    forgetIcons())
  # (programs installed or removed while it runs: the folders of desktop
  # entries looked at every few seconds, the groups made again when one
  # changed)
  var seen = appsStamp()
  var lookedAt = 0
  while beginFrame():
    if ui.now - lookedAt >= 3000:
      lookedAt = ui.now
      let s = appsStamp()
      if s != seen:
        seen = s
        loadGroups()
    wakeIn(3000)
    menus()
    mdiArea(-1):
      for g in groups:
        mdiWindow(g.win):
          groupView(g)
    dialogs()
    endFrame()
    appFrameDone()
  if saveOnExit: saveWindows()
  closeApp()
