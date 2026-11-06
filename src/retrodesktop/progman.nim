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
import common, link, art

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
                "Graphics", "Multimedia", "System", "Games", "StartUp"]
  HelpText = """
# Retro Desktop

Every program opens in its own window on the desktop.

* **Move** a window by its title bar; **size** it by its border or a corner.
* The **minimize** button (the arrow down) makes it an icon at the bottom of
  the desktop; double click the icon (tap it on a touch screen) to bring it back.
* The **maximize** button (the arrow up), or a double click on the title bar,
  makes it fill the screen.
* The **control-menu box** (the bar at the left of the title) has Restore,
  Minimize, Maximize, Close and Switch To. Double click it to close the
  window. On a touch screen, hold a finger on the title bar for the same menu.

## Keys

| Keys | What they do |
|---|---|
| Alt+Tab | the next window (again and again: the ones behind it) |
| Alt+F4 | closes the window in front |
| Alt+Esc | minimizes the window in front |
| Ctrl+Esc | the Task List: every window, how much memory each takes |

## Program Manager

Double click a program (tap it) to start it. Programs you install with a
desktop entry (most programs with windows) come in the groups by their kind;
**File > New** adds one of your own, with its command line, to any group.
Programs in **StartUp** start with the desktop. **Options > Refresh** (F5)
looks for programs installed since.

## Termux on Android

Keep Termux awake (Control Panel > Desktop), set Termux and Termux:X11 to
"Unrestricted" battery use, and turn off the phantom process killer
(Developer options > Disable child process restrictions), or Android may
stop the programs you started while you are in another app.
"""

var
  groups: seq[Group]
  icons: Table[string, Bitmap]
  minimizeOnUse = false
  saveOnExit = true
  showNew, showProps, showRun, showAbout, showHelp, showDelete, showNoTerm: bool
  newName, newCommand, newIcon: string
  newGroup = 0
  propsGroup: Group
  propsIndex = -1
  runText = ""
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
  let term = terminalCommand()
  main.add builtin("Terminal", (if term.len > 0: quoteShell(term) else: "?terminal"), "terminal",
                   "A terminal: a shell's command line")
  main.add builtin("Read Me", "?help", "readme", "How the desktop works")
  companionItem("Notepad", "retro-notepad", "notepad", "Text files", acc)
  companionItem("Paintbrush", "retro-photo", "paint", "Retro Photo: pictures and painting", acc)
  companionItem("Board", "retro-board", "board", "Retro Board: a whiteboard for drawings and notes", acc)
  companionItem("Mail", "retro-mail", "mail", "Retro Mail", acc)
  companionItem("Gallery", "retro-gallery", "gallery", "Retro Gallery: every control of Retro Nim UI", acc)
  acc.add builtin("Calculator", selfCommand("calc"), "calc", "A calculator")
  acc.add builtin("Calendar", selfCommand("calendar"), "calendar", "Days, with notes and appointments")
  acc.add builtin("Cardfile", selfCommand("cardfile"), "cardfile", "Cards of names, numbers and notes")
  acc.add builtin("Clock", selfCommand("clock"), "clock", "The time, on a face or in numbers")
  groupNamed("Main").items = main
  groupNamed("Accessories").items = acc
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
  of "?help": showHelp = true
  of "?terminal": showNoTerm = true
  else:
    var cmd = it.command
    if it.terminal:
      let t = terminalCommand()
      if t.len > 0: cmd = quoteShell(t) & " -e " & cmd
    launch(cmd)
    if minimizeOnUse: minimizeSelf()

# ---- the frame ----------------------------------------------------------------------------------------

proc groupView(g: Group) =
  let px = int(round(dpf(32.0)))
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
      if menuItem("&Run..."):
        showRun = true
        focusFirstText(inDialog = true)
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
      if menuItem("&Read Me", "F1"): showHelp = true
      menuSeparator()
      if menuItem("&About Program Manager..."): showAbout = true
  if hotkeyPressed("Ctrl+N"):
    showNew = true
    focusFirstText(inDialog = true)
  if hotkeyPressed("F5"): loadGroups()
  if hotkeyPressed("Shift+F5"): mdiCascade()
  if hotkeyPressed("Shift+F4"): mdiTile()
  if hotkeyPressed("F1"): showHelp = true
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
        drawBitmap(rect(r.x, r.y, s, s), pictureOf(it, int(round(dpf(32.0)))))
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
  if showRun:
    if inputBox(showRun, "Run", "&Command Line:", runText, width = 420) == 1:
      if runText.strip.len > 0: launch(runText)
  if showNoTerm:
    discard msgBox(showNoTerm, "Terminal",
                   "No terminal is installed. In Termux: pkg install xfce4-terminal " &
                   "(or aterm); on Linux, any terminal your system has.", ["OK"], miInfo)
  if showHelp:
    dialog(showHelp, "Read Me", 560):
      markdownView(HelpText, height = dp(360))
      row:
        spring()
        if button("OK", isDefault = true): showHelp = false
  aboutBox(showAbout, "Program Manager", DesktopVersion,
           [DesktopName & " " & DesktopVersion, "Memory: " & memoryReport(false)])

proc runProgman*() =
  ## Program Manager, until it is closed.
  applyDesktopLook()
  openApp("Program Manager", scaled(720), scaled(480), frame = wfSystem, userFrame = false, id = "progman")
  followLook(proc () = icons.clear())
  loadGroups()
  onMemoryPressure(proc (level: MemoryPressure) =
    icons.clear()
    forgetIcons())
  while beginFrame():
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
