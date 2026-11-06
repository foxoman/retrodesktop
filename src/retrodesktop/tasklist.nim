## Task List (Ctrl+Esc): every window on the desktop, with how much memory
## its program holds -- switch to one, end one (a program that does not
## answer is ended for good), cascade, tile, arrange the icons. The memory
## the device has free is at the bottom.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[posix, strutils]
import retroui
import common, link, help

var
  list: seq[WinInfo]
  mem: seq[int64]
  sel = 0
  ending: tuple[win: uint; pid: int; at: int]
  askKill = false

proc mb(n: int64): string =
  if n <= 0: "" else: formatFloat(float(n) / (1024 * 1024), ffDecimal, 1) & " MB"

proc refresh() =
  let keep = if sel in 0 ..< list.len: list[sel].win else: 0
  list = windows()
  # (the one in front first, as 3.1 listed them)
  var r: seq[WinInfo]
  for i in countdown(list.high, 0): r.add list[i]
  list = r
  mem.setLen(list.len)
  for i, w in list: mem[i] = processMemory(w.pid)
  sel = 0
  for i, w in list:
    if w.win == keep: sel = i

proc runTaskList*() =
  applyDesktopLook()
  openApp("Task List", scaled(420), scaled(300), frame = wfSystem, userFrame = false, id = "tasklist")
  showArt("tasklist")
  followLook()
  var cols = @[column("Program", 260), column("Memory", 90, alRight)]
  var lastRefresh = -10_000
  while beginFrame():
    helpKeys("tasklist")
    if ui.now - lastRefresh > 2000:
      refresh()
      lastRefresh = ui.now
    wakeIn(2000)
    let ev = grid(cols, list.len,
      proc (row, col: int): string =
        if col == 0: (if list[row].iconic: tr(list[row].title) & "  (icon)" else: tr(list[row].title))
        else: mb(mem[row]),
      sel, height = max(3, (remainingH() - 2 * CtrlH - lineHeight() - 6 * Gap) div ItemH - 2),
      tapActivates = fingers() or isMobile(),
      footer = proc (col: int): string =
        if col == 0: $list.len & " windows" else: "")
    let has = sel in 0 ..< list.len
    if (ev.activated or ui.key == KeyEnter) and has:
      activate(list[sel].win)
      quitApp()
    row:
      if button("&Switch To", isDefault = true, enabled = has):
        activate(list[sel].win)
        quitApp()
      if button("&End Task", enabled = has):
        closeWindow(list[sel].win)
        ending = (uint(list[sel].win), list[sel].pid, ui.now)
      if button("Cancel"): quitApp()
    row:
      if button("&Cascade"):
        retroCommand(RetroCascade)
        quitApp()
      if button("&Tile"):
        retroCommand(RetroTile)
        quitApp()
      if button("&Arrange Icons"):
        retroCommand(RetroArrange)
        quitApp()
    label "Free memory: " & memoryReport(false)
    if ui.key == KeyEsc and ui.dialogTop == 0: quitApp()
    # (a program that did not close its window when asked: ended for good, if the user says)
    if ending.win != 0 and ui.now - ending.at > 4000:
      var still = false
      for w in windows():
        if uint(w.win) == ending.win: still = true
      if still and ending.pid > 0: askKill = true
      else: ending.win = 0
    if askKill:
      let r = msgBox(askKill, "End Task", "This program is not answering. " &
                     "End it now? What it has not saved is lost.", ["&End Now", "Cancel"], miWarning)
      if r == 1 and ending.pid > 0: discard posix.kill(Pid(ending.pid), SIGKILL)
      if r != 0: ending.win = 0
    endFrame()
    appFrameDone()
  closeApp()
