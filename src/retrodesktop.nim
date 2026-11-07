## Retro Desktop: a Windows 3.1 style desktop for Linux and for Termux on
## Android (Termux:X11) -- a window manager that puts every X11 program in a
## 3.1 frame, Program Manager with your installed programs, and the small
## programs of a desktop: Clock, Calculator, Calendar, Cardfile, Control
## Panel, Task List. One program; what it is comes from its first argument.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retrodesktop/[common, link, session, progman, accessories, control, tasklist, terminal,
                     browser, setup, boxes, games, write, clipboard, opener, saver, sounds, help,
                     charmap, viewers, players, phone, utilities, crash]

proc usage() =
  echo DesktopName, " ", DesktopVersion, " -- a Windows 3.1 style desktop"
  echo ""
  echo "  retro-desktop             the desktop (start it on an X screen: Termux:X11, Xvfb, a display)"
  echo "  retro-desktop progman     Program Manager"
  echo "  retro-desktop control     Control Panel"
  echo "  retro-desktop tasklist    Task List"
  echo "  retro-desktop terminal    Terminal (-e command: runs it in the Terminal)"
  echo "  retro-desktop browser     Retro Browser (Firefox in the desktop's look)"
  echo "  retro-desktop setup       Setup: programs to install (setup firefox: one at once)"
  echo "  retro-desktop mines       Minesweeper (solitaire, reversi: the other games)"
  echo "  retro-desktop write       Write (a document to open after it)"
  echo "  retro-desktop clipboard   Clipboard Viewer"
  echo "  retro-desktop open FILE   a file or a link in the program for it"
  echo "  retro-desktop clock       Clock"
  echo "  retro-desktop calc        Calculator"
  echo "  retro-desktop calendar    Calendar"
  echo "  retro-desktop cardfile    Cardfile"
  echo "  retro-desktop charmap     Character Map"
  echo "  retro-desktop pictures    Picture Viewer (pictures or a folder after it)"
  echo "  retro-desktop pdf         PDF Reader (a PDF after it)"
  echo "  retro-desktop media       Media Player (songs or videos after it)"
  echo "  retro-desktop recorder    Sound Recorder"
  echo "  retro-desktop camera      Camera (Termux:API)"
  echo "  retro-desktop dialer      Phone Dialer (Termux:API)"
  echo "  retro-desktop news        News Reader"
  echo "  retro-desktop diskspace   Disk Space"
  echo "  retro-desktop share       Share Desktop (VNC)"

proc main(role: string) =
  case role
  of "", "session", "desktop": runSession()
  of "progman": runProgman()
  of "control": runControl()
  of "browser":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runBrowser(args)
  of "terminal":
    # (retro-desktop terminal -e command...: the command, not a shell)
    var args: seq[string]
    var i = 2
    if paramCount() >= 2 and paramStr(2) == "-e": i = 3
    if i == 3:
      for k in 3 .. paramCount(): args.add paramStr(k)
    runTerminal(args)
  of "setup":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runSetup(args)
  of "mines", "minesweeper": runMines()
  of "solitaire": runSolitaire()
  of "reversi": runReversi()
  of "write":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runWrite(args)
  of "clipboard": runClipboard()
  of "open":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runOpen(args)
  of "saver":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runSaver(args)
  of "storage": runStorage()
  of "notify":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runNotify(args)
  of "sound":
    # (retro-desktop sound beep: an event's sound, from a script)
    if paramCount() >= 2: playSound(paramStr(2))
  of "help": runHelp(if paramCount() >= 2: paramStr(2) else: "contents")
  of "tour": runTour()
  of "charmap": runCharmap()
  of "pictures":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runPictures(args)
  of "pdf":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runPdf(args)
  of "camera": runCamera()
  of "media":
    var args: seq[string]
    for k in 2 .. paramCount(): args.add paramStr(k)
    runMedia(args)
  of "recorder": runRecorder()
  of "dialer": runDialer()
  of "news": runNews()
  of "diskspace", "disk": runDiskSpace()
  of "share": runShare()
  of "run": runRunBox()
  of "about": runAboutBox()
  of "exit": runExitBox()
  of "welcome": runWelcomeBox()
  of "tasklist", "tasks": runTaskList()
  of "clock": runClock()
  of "calc", "calculator": runCalc()
  of "calendar": runCalendar()
  of "cardfile": runCardfile()
  of "crash": runCrashBox((if paramCount() >= 2: paramStr(2) else: "a program"),
                          paramCount() >= 3 and paramStr(3) == "noted")
  of "--version", "-v", "version": echo DesktopName, " ", DesktopVersion
  of "--retro-command":
    # (for scripts and the checks: asks the desktop to cascade (1), tile (2),
    # arrange icons (3), take the look again (4), exit (5))
    if paramCount() >= 2: sendRetroCommand(parseInt(paramStr(2)))
  else: usage()

when isMainModule:
  let role = if paramCount() >= 1: paramStr(1).toLowerAscii else: ""
  # (a fault, or an error no one caught: the General Protection Fault box)
  watchCrashes(role)
  try: main(role)
  except Exception as e:
    crashed(role, e)
    raise
