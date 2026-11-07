## When one of the desktop's own programs fails: a 3.1 "General Protection
## Fault" box, instead of a window that just goes. The program's role and
## what went wrong (the signal, or the error and where) are kept in
## ~/.local/share/retrodesktop/crashes.log; the box shows them, copies them
## for a report, or starts the program again.
##
## `watchCrashes(role)` at the start of a program sets it up: a crash (a
## signal: SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGABRT) forks, the child lets
## go of the X connection and becomes the box, the program ends; an error no
## one caught is written down and does the same.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, times, posix]
import retroui
import retroui/uirelays/drivers/x11_driver
import common, link, help, sounds

var
  boxArgs, notedArgs: cstringArray   # (made before a crash: nothing is made in a signal's handler)
  boxExe: cstring
  boxExeKept: string            # (what `boxExe` points into)
  armed = false

proc XConnectionNumber(d: pointer): cint {.importc, dynlib: "libX11.so(|.6)", cdecl.}

proc crashLog*(): string = dataDir(SettingsName) / "crashes.log"

proc toBox(noted = false) {.noconv.} =
  ## (in the signal's handler: only what is safe there)
  let args = if noted: notedArgs else: boxArgs
  let pid = fork()
  if pid == 0:
    let d = x11Display()
    if d != nil: discard close(XConnectionNumber(d))
    # (the box keeps nothing of the program's: not its terminal, not a pipe it wrote to)
    let null = posix.open("/dev/null", O_RDWR)
    if null >= 0:
      for fd in 0.cint .. 2.cint: discard dup2(null, fd)
    discard setsid()
    discard execv(boxExe, args)
    exitnow(1)

proc onSignal(sig: cint) {.noconv.} =
  if armed:
    armed = false
    toBox()
  exitnow(128 + sig)

proc note(role, what: string) =
  try:
    let f = open(crashLog(), fmAppend)
    f.writeLine(now().format("yyyy-MM-dd HH:mm:ss") & "  " & role & " (" & DesktopVersion & "): " & what)
    f.close()
  except CatchableError: discard

proc watchCrashes*(role: string) =
  ## The box for this program (`role`) when it fails.
  # (the desktop itself has no frame to show a box in once it is gone; the
  # commands without a window answer in the terminal)
  if role in ["crash", "session", "desktop", "", "--retro-command", "--version", "-v", "version",
              "sound", "notify", "open"]: return
  boxExeKept = selfPath()
  boxExe = cstring(boxExeKept)
  boxArgs = allocCStringArray([selfPath(), "crash", role])
  notedArgs = allocCStringArray([selfPath(), "crash", role, "noted"])
  armed = true
  for sig in [SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGABRT]:
    var sa: Sigaction
    sa.sa_handler = onSignal
    discard sigemptyset(sa.sa_mask)
    sa.sa_flags = SA_RESETHAND
    discard sigaction(sig, sa, nil)

proc crashed*(role: string; e: ref Exception) =
  ## An error no one caught: written down, and the box.
  note(role, $e.name & ": " & e.msg & "\n" & e.getStackTrace())
  if armed:
    armed = false
    toBox(noted = true)

proc signalNote*(role: string) =
  ## (the box, when no error was written: the program was ended by a signal)
  note(role, "it stopped on a signal (a fault in memory, or it was aborted)")

proc lastCrash(role: string): string =
  ## What the log says of `role`'s last failure.
  try:
    let lines = readFile(crashLog()).splitLines
    var start = -1
    for i in countdown(lines.high, 0):
      if ("  " & role & " (") in lines[i]:
        start = i
        break
    if start >= 0:
      var parts: seq[string]
      for i in start .. lines.high:
        if i > start and lines[i].len > 19 and lines[i][4] == '-' and lines[i][13] == ':': break
        parts.add lines[i]
      return parts.join("\n").strip
  except CatchableError: discard
  ""

const Names = [("progman", "Program Manager"), ("control", "Control Panel"), ("tasklist", "Task List"),
               ("terminal", "Terminal"), ("browser", "Retro Browser"), ("setup", "Setup"),
               ("mines", "Minesweeper"), ("solitaire", "Solitaire"), ("reversi", "Reversi"),
               ("write", "Write"), ("clipboard", "Clipboard Viewer"), ("clock", "Clock"),
               ("calc", "Calculator"), ("calendar", "Calendar"), ("cardfile", "Cardfile"),
               ("charmap", "Character Map"), ("pictures", "Picture Viewer"), ("pdf", "PDF Reader"),
               ("media", "Media Player"), ("recorder", "Sound Recorder"), ("camera", "Camera"),
               ("dialer", "Phone Dialer"), ("news", "News Reader"), ("diskspace", "Disk Space"),
               ("share", "Share Desktop"), ("help", "Help"), ("saver", "the screen saver")]

proc nameOf(role: string): string =
  for (r, n) in Names:
    if r == role: return n
  role

proc runCrashBox*(role: string; noted: bool) =
  ## The box: which program, Close, Restart, Details (`noted`: the error is
  ## written down already; else it was a signal, written now).
  if not noted: signalNote(role)
  let details = lastCrash(role)
  applyDesktopLook()
  openApp("General Protection Fault", scaled(480), scaled(300), frame = wfSystem, userFrame = false,
          id = "crash")
  followLook()
  asDialog()
  playSound("error")
  var showDetails = false
  while beginFrame():
    helpKeys("crash")
    row:
      msgIcon(miStop)
      col:
        label("General Protection Fault", bold = true)
        paragraph "An error has occurred in " & nameOf(role) & " (" & DesktopName & " " &
          DesktopVersion & "). It was closed; what you had not saved in it is lost."
        paragraph "Restart opens it again. Details are for a report: Copy Details takes them."
    let room = max(dp(20), remainingH() - CtrlH - 2 * Gap)
    if showDetails:
      beginPanel(room, key = "details")
      paragraph details
      endPanel()
    else: space(room)
    row:
      if button(if showDetails: "<< &Details" else: "&Details >>"): showDetails = not showDetails
      if button("&Copy Details"):
        putClipboardText(details)
        toast("Copied.", 1500)
      spring()
      if button("&Restart"):
        launch(selfCommand(role))
        quitApp()
      if button("Close", isDefault = true): quitApp()
    endFrame()
    appFrameDone()
  closeApp()
