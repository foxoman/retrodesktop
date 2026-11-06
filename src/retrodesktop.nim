## Retro Desktop: a Windows 3.1 style desktop for Linux and for Termux on
## Android (Termux:X11) -- a window manager that puts every X11 program in a
## 3.1 frame, Program Manager with your installed programs, and the small
## programs of a desktop: Clock, Calculator, Calendar, Cardfile, Control
## Panel, Task List. One program; what it is comes from its first argument.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retrodesktop/[common, link, session, progman, accessories, control, tasklist, terminal]

proc usage() =
  echo DesktopName, " ", DesktopVersion, " -- a Windows 3.1 style desktop"
  echo ""
  echo "  retro-desktop             the desktop (start it on an X screen: Termux:X11, Xvfb, a display)"
  echo "  retro-desktop progman     Program Manager"
  echo "  retro-desktop control     Control Panel"
  echo "  retro-desktop tasklist    Task List"
  echo "  retro-desktop terminal    Terminal (-e command: runs it in the Terminal)"
  echo "  retro-desktop clock       Clock"
  echo "  retro-desktop calc        Calculator"
  echo "  retro-desktop calendar    Calendar"
  echo "  retro-desktop cardfile    Cardfile"

when isMainModule:
  let role = if paramCount() >= 1: paramStr(1).toLowerAscii else: ""
  case role
  of "", "session", "desktop": runSession()
  of "progman": runProgman()
  of "control": runControl()
  of "terminal":
    # (retro-desktop terminal -e command...: the command, not a shell)
    var args: seq[string]
    var i = 2
    if paramCount() >= 2 and paramStr(2) == "-e": i = 3
    if i == 3:
      for k in 3 .. paramCount(): args.add paramStr(k)
    runTerminal(args)
  of "tasklist", "tasks": runTaskList()
  of "clock": runClock()
  of "calc", "calculator": runCalc()
  of "calendar": runCalendar()
  of "cardfile": runCardfile()
  of "--version", "-v", "version": echo DesktopName, " ", DesktopVersion
  of "--retro-command":
    # (for scripts and the checks: asks the desktop to cascade (1), tile (2),
    # arrange icons (3), take the look again (4), exit (5))
    if paramCount() >= 2: sendRetroCommand(parseInt(paramStr(2)))
  else: usage()
