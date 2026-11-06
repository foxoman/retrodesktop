## The programs, in their groups, as Program Manager and the panel's
## Programs menu show them: the desktop's own (Main, Accessories, Games),
## the programs that come with it, Freedoom, the DOS games in ~/DOS, every
## program installed with a desktop entry (in a group by its kind), and
## the user's own items.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retroui
import common

type
  CatItem* = object
    ## A program to start.
    name*, command*, comment*: string
    art*: string               ## the desktop's own picture ("" none)
    icon*: string              ## an icon theme's name or a file ("" none)
    terminal*: bool
    custom*: int               ## its place in `progItems` (-1: not the user's)

const GroupOrder* = ["Main", "Accessories", "Applications", "Internet", "Office", "Development",
                     "Graphics", "Multimedia", "System", "Games", "DOS", "Android", "StartUp"]

proc own(name, command, art, comment: string): CatItem =
  CatItem(name: name, command: command, art: art, comment: comment, custom: -1)

proc companionItem(name, exe, art, comment: string; list: var seq[CatItem]) =
  ## A program that comes with the desktop, when it is installed.
  let p = companion(exe)
  if p.len > 0:
    var it = own(name, quoteShell(p), art, comment)
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

proc dosItems(): seq[CatItem] =
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
  result.add own("DOSBox-X", run(""), "dos", "A DOS PC; the folder DOS in your home is its drive C:")
  for kind, path in walkDir(dir):
    if kind in {pcDir, pcLinkToDir}:
      let exe = pickExe(path)
      if exe.len > 0:
        result.add own(path.extractFilename, run(exe.relativePath(dir)), "dos",
                           "In DOSBox-X: " & exe.relativePath(dir))
    elif path.splitFile.ext.toLowerAscii in [".exe", ".com", ".bat"]:
      result.add own(path.splitFile.name, run(path.extractFilename), "dos", "In DOSBox-X")

proc androidApps*(): seq[CatItem] =
  ## The Android apps Program Manager found (Termux: pm), kept from the last
  ## time it looked (`lookForAndroidApps`).
  let f = dataDir(SettingsName) / "android-apps"
  if not fileExists(f): return
  for line in readFile(f).splitLines:
    let pkg = line.strip
    if pkg.len == 0: continue
    var name = pkg.split('.')[^1]
    if name.len > 0: name[0] = name[0].toUpperAscii
    result.add own(name, "am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p " &
                   quoteShell(pkg) & " >/dev/null 2>&1", "android", "The Android app " & pkg)

proc lookForAndroidApps*() =
  ## Asks Android, in the background, which apps are installed (the list
  ## comes next time: `androidApps`).
  if not inTermux() or findExe("pm").len == 0: return
  let f = dataDir(SettingsName) / "android-apps"
  launch("pm list packages -3 2>/dev/null | sed 's/^package://' | sort > " & quoteShell(f & ".new") &
         " && [ -s " & quoteShell(f & ".new") & " ] && mv " & quoteShell(f & ".new") & " " & quoteShell(f))

proc catalog*(): seq[(string, seq[CatItem])] =
  ## Every group and its programs, in 3.1's order (the user's own groups after).
  var main, acc: seq[CatItem]
  companionItem("File Manager", "retro-files", "files", "Retro Files: folders and files", main)
  main.add own("Control Panel", selfCommand("control"), "control", "Colors, fonts, sizes, the desktop")
  main.add own("Task List", selfCommand("tasklist"), "tasklist", "The windows open, and the memory each takes")
  main.add own("Terminal", selfCommand("terminal"), "terminal", "The shell's command line, in a PC's 16 text colors")
  main.add own("Web Browser", selfCommand("browser"), "browser",
               "Retro Browser: Firefox in the desktop's look, on a profile of its own")
  main.add own("Setup", selfCommand("setup"), "setup",
               "Programs to install, from Termux's packages: browsers, office, games...")
  if inTermux():
    main.add own("Android Files", selfCommand("storage"), "storage",
                 "Your phone's photos, downloads and documents, in File Manager")
  main.add own("Share Desktop", selfCommand("share"), "share", "Use this desktop from a computer (VNC)")
  main.add own("Read Me", "?help", "readme", "How the desktop works")
  companionItem("Notepad", "retro-notepad", "notepad", "Text files", acc)
  companionItem("Paintbrush", "retro-photo", "paint", "Retro Photo: pictures and painting", acc)
  companionItem("Board", "retro-board", "board", "Retro Board: a whiteboard for drawings and notes", acc)
  companionItem("Mail", "retro-mail", "mail", "Retro Mail", acc)
  companionItem("Communicator", "retro-communicator", "communicator",
                "Retro Communicator: talk to your friends (XMPP)", acc)
  companionItem("Gallery", "retro-gallery", "gallery", "Retro Gallery: every control of Retro Nim UI", acc)
  acc.add own("Write", selfCommand("write"), "write", "Documents with bold, italic, sizes and lists")
  acc.add own("Character Map", selfCommand("charmap"), "charmap", "Letters and symbols to copy")
  acc.add own("Picture Viewer", selfCommand("pictures"), "pictures", "Your photos and pictures")
  acc.add own("PDF Reader", selfCommand("pdf"), "pdf", "PDF documents")
  acc.add own("Media Player", selfCommand("media"), "media", "Music and videos (with mpv)")
  acc.add own("Sound Recorder", selfCommand("recorder"), "recorder", "Record your voice")
  if inTermux():
    acc.add own("Camera", selfCommand("camera"), "camera", "Photos with the phone's camera")
    acc.add own("Phone Dialer", selfCommand("dialer"), "dialer", "Calls, messages and contacts of the phone")
  acc.add own("News Reader", selfCommand("news"), "news", "News feeds (RSS, Atom)")
  acc.add own("Clipboard Viewer", selfCommand("clipboard"), "clipboard", "What was copied last")
  acc.add own("Disk Space", selfCommand("diskspace"), "diskspace", "What fills the storage")
  acc.add own("Calculator", selfCommand("calc"), "calc", "A calculator")
  acc.add own("Calendar", selfCommand("calendar"), "calendar", "Days, with notes and appointments")
  acc.add own("Cardfile", selfCommand("cardfile"), "cardfile", "Cards of names, numbers and notes")
  acc.add own("Clock", selfCommand("clock"), "clock", "The time, on a face or in numbers")
  var groups: seq[(string, seq[CatItem])]
  proc addTo(name: string; it: CatItem) =
    for g in groups.mitems:
      if g[0] == name:
        g[1].add it
        return
    groups.add (name, @[it])
  for it in main: addTo("Main", it)
  for it in acc: addTo("Accessories", it)
  addTo("Games", own("Minesweeper", selfCommand("mines"), "mines", "Find the mines without stepping on one"))
  addTo("Games", own("Solitaire", selfCommand("solitaire"), "cards", "Klondike, as 3.1 had it"))
  addTo("Games", own("Reversi", selfCommand("reversi"), "reversi", "Turn the computer's pieces over"))
  # (Freedoom, once Setup put it here)
  let doom = findExe("chocolate-doom")
  let wads = gameDataDir("freedoom")
  if doom.len > 0:
    for (name, wad) in [("Freedoom", "freedoom1.wad"), ("Freedoom: Phase 2", "freedoom2.wad")]:
      if fileExists(wads / wad):
        addTo("Games", own(name, quoteShell(doom) & " -iwad " & quoteShell(wads / wad), "doom",
                           "A free Doom, in Chocolate Doom"))
  for it in dosItems(): addTo("DOS", it)
  for it in androidApps(): addTo("Android", it)
  for e in installedApps():
    addTo(groupOf(e), CatItem(name: e.name, command: e.command, comment: e.comment, icon: e.icon,
                              terminal: e.terminal, custom: -1))
  for i, it in progItems():
    addTo((if it.group.len > 0: it.group else: "Applications"),
          CatItem(name: it.name, command: it.command, icon: it.icon, custom: i,
                  art: (if it.icon.len == 0: "app" else: "")))
  for n in GroupOrder:
    for g in groups:
      if g[0] == n: result.add g
  for g in groups:
    if g[0] notin GroupOrder: result.add g
