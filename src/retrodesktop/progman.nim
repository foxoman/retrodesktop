## Program Manager: the programs, in groups -- Main and Accessories with the
## desktop's own, StartUp with what starts with the desktop, and a group for
## each kind of program installed (every program with a desktop entry:
## Applications, Internet, Office, Development, Graphics, Multimedia, System,
## Games). A double click (a tap) starts one; File > New puts a program of
## your own in a group.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, tables, math]
import retroui
import common, link, art, help, catalog, deskicons

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
  for (name, items) in catalog():
    let g = groupNamed(name)
    for it in items:
      g.items.add Item(name: it.name, command: it.command, comment: it.comment, art: it.art,
                       icon: it.icon, terminal: it.terminal, custom: it.custom)
  discard groupNamed("StartUp")
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
    proc (i: int): string = tr(g.items[i].name),
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

proc toDesktop(it: Item) =
  ## The program on the desktop, as an icon (a desktop entry in ~/Desktop).
  var cmd = it.command
  if cmd == "?help": cmd = selfCommand("help") & " desktop"
  if putOnDesktop(it.name, cmd, it.art, it.icon, it.terminal):
    toast(it.name & " is on the desktop.", 2500)

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
      if menuItem("Put on the Des&ktop", enabled = hasItem): toDesktop(g.items[g.sel])
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
      if menuItem("Put on the Des&ktop"): toDesktop(g2.items[g2.sel])
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
