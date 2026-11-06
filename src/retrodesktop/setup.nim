## Setup: programs put on the desktop the way Windows 3.1's Setup put them on
## -- the blue screen with "Retro Desktop Setup" at its top, the programs to
## choose, the space they need and the space there is, a gauge while they go
## in -- with Termux's own package manager doing the work underneath (apt,
## which `pkg` runs). Check a program to install it; clear one that is
## installed to remove it.
##
## Programs with windows come into Program Manager by their desktop entries;
## programs for the Terminal (htop, mc, NetHack...) get an item of their own.
##
## `retro-desktop setup firefox` asks for one program at once (Retro Browser
## does, when Firefox is not there); `--then browser` offers to start that
## after. On a Linux computer the system's package manager needs root: Setup
## shows the command to run instead.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils, strtabs, posix, times]
import retroui
import common, link

type
  Offer = object
    group, name, pkgs, repo, about, cli: string
      ## `pkgs` its packages (a space between), `repo` "" (Termux's main
      ## repository), "x11" or "tur", `cli` the command of a program for the
      ## Terminal ("" for a program with windows)
    big: bool                  ## a large one (hundreds of MB)

  Screen = enum scChoose, scChecking, scConfirm, scWorking, scDone, scFailed, scManual

  StepKind = enum stRepo, stUpdate, stInstall, stRemove

  Step = object
    kind: StepKind
    pkgs: seq[string]

  Job = object
    p: Process
    fd: cint
    part: string
    lines: seq[string]
    running: bool
    code: int

proc offer(group, name, pkgs, repo, about: string; cli = ""; big = false): Offer =
  Offer(group: group, name: name, pkgs: pkgs, repo: repo, about: about, cli: cli, big: big)

let Offers = @[
  # (every name checked against Termux's packages: termux-packages' packages
  # and x11-packages)
  offer("Internet", "Firefox", "firefox", "x11", "The web browser (Retro Browser dresses it as a 3.1 program)", big = true),
  offer("Internet", "Chromium", "chromium", "x11", "The open-source browser Chrome is made from", big = true),
  offer("Internet", "NetSurf", "netsurf", "x11", "A small, quick browser for phones with little memory"),
  offer("Internet", "Thunderbird", "thunderbird", "x11", "Mail, news feeds and calendars", big = true),
  offer("Internet", "Transmission", "transmission-gtk", "x11", "Downloads torrents"),
  offer("Internet", "Pidgin", "pidgin", "x11", "Chat on IRC, XMPP and more"),
  offer("Internet", "Telegram", "telegram-desktop", "x11", "Telegram's desktop app", big = true),
  offer("Office", "LibreOffice", "libreoffice", "x11", "Writer, Calc, Impress, Draw: the whole office", big = true),
  offer("Office", "AbiWord", "abiword", "x11", "A light word processor (.doc, .docx, .odt)"),
  offer("Office", "Gnumeric", "gnumeric", "x11", "A light spreadsheet (.xls, .xlsx, .ods)"),
  offer("Office", "Atril", "atril", "x11", "Reads PDF, EPUB and DjVu documents"),
  offer("Development", "VS Code", "code-oss", "x11", "Visual Studio Code (the open-source build)", big = true),
  offer("Development", "Geany", "geany", "x11", "A light IDE for many languages"),
  offer("Development", "Lite XL", "lite-xl", "x11", "A fast, small code editor"),
  offer("Development", "Git", "git", "", "Version control for your code", cli = "git --help"),
  offer("Development", "Python", "python", "", "Python 3 and pip", cli = "python"),
  offer("Development", "Node.js", "nodejs-lts", "", "JavaScript outside the browser, with npm", cli = "node"),
  offer("Development", "Nim", "nim", "", "The language this desktop is written in", cli = "nim --help"),
  offer("Development", "Go", "golang", "", "Google's Go language", cli = "go help"),
  offer("Development", "Rust", "rust", "", "Rust and Cargo", big = true, cli = "cargo --help"),
  offer("Development", "Clang", "clang", "", "C and C++", cli = "clang --help"),
  offer("Development", "Neovim", "neovim", "", "The editor, in the Terminal", cli = "nvim"),
  offer("Graphics", "GIMP", "gimp", "x11", "Photos and pictures", big = true),
  offer("Graphics", "Inkscape", "inkscape", "x11", "Drawings in SVG", big = true),
  offer("Graphics", "Krita", "krita", "x11", "Painting, for artists", big = true),
  offer("Graphics", "mtPaint", "mtpaint", "x11", "A light painting program, for pixel art too"),
  offer("Graphics", "Ristretto", "ristretto", "x11", "A quick picture viewer"),
  offer("Multimedia", "VLC", "vlc-qt", "x11", "Plays every video and music file", big = true),
  offer("Multimedia", "Audacious", "audacious", "x11", "Music, with playlists and Winamp skins"),
  offer("Multimedia", "Audacity", "audacity", "x11", "Records and edits sound"),
  offer("Multimedia", "mpv", "mpv", "", "A video player that opens its own window", cli = "mpv --help"),
  offer("Multimedia", "Sound", "pulseaudio", "", "The sound for every program (the desktop starts it)"),
  offer("Games", "SuperTux", "supertux", "x11", "Tux runs and jumps through levels"),
  offer("Games", "OpenTTD", "openttd", "x11", "Build a transport company"),
  offer("Games", "DOSBox-X", "dosbox-x", "x11", "A DOS PC, for the old games and programs you have"),
  offer("Games", "mGBA", "mgba", "x11", "A Game Boy Advance, for the games you own"),
  offer("Games", "Chess", "xboard gnuchess", "x11", "XBoard with GNU Chess to play against"),
  offer("Games", "NetHack", "nethack", "", "The dungeon, in the Terminal", cli = "nethack"),
  offer("System", "Midnight Commander", "mc", "", "Files in two panels, in the Terminal", cli = "mc"),
  offer("System", "htop", "htop", "", "What runs, and what it takes, in the Terminal", cli = "htop"),
  offer("System", "Xarchiver", "xarchiver", "x11", "Zip, 7z and tar archives"),
  offer("System", "Fastfetch", "fastfetch", "", "Your system at a glance, in the Terminal", cli = "fastfetch; read -n 1 -p 'Press a key'"),
  offer("System", "Termux:API tools", "termux-api", "", "The phone's clipboard and notifications (needs the Termux:API app)"),
  offer("System", "QEMU", "qemu-system-x86-64", "x11", "A whole PC in a window, for other systems", big = true),
  offer("Fonts", "DejaVu", "ttf-dejavu", "", "Fonts with more letters and symbols"),
  offer("Fonts", "Noto CJK", "otf-noto-sans-cjk", "", "Chinese, Japanese and Korean letters", big = true),
  offer("Fonts", "Nerd Font symbols", "ttf-nerd-fonts-symbols", "", "The icons of shell prompts and tools")]

var
  installed, want: seq[bool]
  screen = scChoose
  showMain = true
  job: Job
  steps: seq[Step]
  stepAt = 0
  stepGauge = 0.0
  status, doing: string
  pmSeen = false
  updateLines = 0
  needUpdate = false
  forceUpdate = false              # (trying again after a failure: the lists read first)
  spaceNeed, spaceGet: int64       # bytes, -1 not known
  newCount = 0
  toAdd, toRemove: seq[int]        # offers
  failText = ""
  thenRole = ""
  firstRun = ""                    # a program just installed, to start ("" none)
  firstName = ""

# ---- what is installed ------------------------------------------------------------------------------

proc packages(o: Offer): seq[string] = o.pkgs.splitWhitespace

proc canInstall(): bool =
  ## Setup can run the package manager itself: Termux, or root with apt.
  inTermux() or (getuid() == 0 and findExe("apt-get").len > 0)

proc readInstalled() =
  installed = newSeq[bool](Offers.len)
  if findExe("dpkg-query").len == 0: return
  var all: seq[string]
  for o in Offers: all.add o.packages
  let (outp, _) = execCmdEx("dpkg-query -W -f='${Package} ${db:Status-Abbrev}\\n' " &
                            all.join(" ") & " 2>/dev/null")
  var have: seq[string]
  for line in outp.splitLines:
    let f = line.splitWhitespace
    if f.len >= 2 and f[1].startsWith("ii"): have.add f[0]
  for i, o in Offers:
    var all = true
    for p in o.packages:
      if p notin have: all = false
    installed[i] = all

proc repoReady(repo: string): bool =
  case repo
  of "x11": fileExists(prefixDir() / "etc/apt/sources.list.d/x11.list")
  of "tur": fileExists(prefixDir() / "etc/apt/sources.list.d/tur.list")
  else: true

proc listsAge(): float =
  ## Hours since the lists of packages were read (`pkg update`); a lot when never.
  result = 1e9
  let dir = prefixDir() / "var/lib/apt/lists"
  if not dirExists(dir): return
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith("Packages"):
      try: result = min(result, (getTime() - getLastModificationTime(path)).inSeconds.float / 3600)
      except CatchableError: discard

proc freeSpace(): int64 =
  var st: Statvfs
  if statvfs(cstring(prefixDir()), st) == 0: int64(st.f_bavail) * int64(st.f_frsize) else: -1

proc mb(bytes: int64): string =
  if bytes < 0: "not known yet"
  elif bytes < 1_000_000: $max(1, bytes div 1000) & " KB"
  elif bytes < 1_000_000_000: $(bytes div 1_000_000) & " MB"
  else: formatFloat(float(bytes) / 1e9, ffDecimal, 1) & " GB"

proc names(list: seq[int]): string =
  var n: seq[string]
  for i in list: n.add Offers[i].name
  if n.len <= 1: return n.join("")
  n[0 .. ^2].join(", ") & " and " & n[^1]

# ---- running the package manager --------------------------------------------------------------------

proc aptEnv(): StringTableRef =
  result = newStringTable(modeCaseSensitive)
  for k, v in envPairs(): result[k] = v
  result["DEBIAN_FRONTEND"] = "noninteractive"
  result["LC_ALL"] = "C"                      # (apt's words, to read them)

proc start(j: var Job; args: seq[string]) =
  j = Job()
  try:
    j.p = startProcess(args[0], args = args[1 .. ^1], env = aptEnv(),
                       options = {poStdErrToStdOut, poUsePath})
  except OSError as e:
    j.lines = @[e.msg]
    j.code = 127
    return
  j.fd = cint(j.p.outputHandle)
  discard fcntl(j.fd, F_SETFL, fcntl(j.fd, F_GETFL) or O_NONBLOCK)
  j.running = true

proc pump(j: var Job): seq[string] =
  ## What the job wrote since, line by line (and whether it ended).
  if not j.running: return
  var buf: array[8192, char]
  var ended = false
  while true:
    let n = posix.read(j.fd, addr buf[0], buf.len)
    if n > 0:
      for i in 0 ..< n: j.part.add buf[i]
    else:
      if n == 0: ended = true
      break
  var a = 0
  for i in 0 ..< j.part.len:
    if j.part[i] in {'\n', '\r'}:
      if i > a: result.add j.part[a ..< i]
      a = i + 1
  j.part = j.part[a .. ^1]
  if ended:
    if j.part.len > 0: result.add j.part
    j.part = ""
    j.code = j.p.waitForExit()
    j.p.close()
    j.running = false
  for l in result: j.lines.add l
  if j.lines.len > 400: j.lines = j.lines[^300 .. ^1]

proc stop(j: var Job) =
  if j.running:
    j.p.terminate()
    discard j.p.waitForExit()
    j.p.close()
    j.running = false

proc aptArgs(s: Step): seq[string] =
  case s.kind
  of stRepo, stInstall:
    @["apt-get", "install", "-y", "-o", "APT::Status-Fd=1",
      "-o", "Dpkg::Options::=--force-confdef", "-o", "Dpkg::Options::=--force-confold"] & s.pkgs
  of stUpdate: @["apt-get", "update"]
  of stRemove: @["apt-get", "remove", "-y", "--autoremove", "-o", "APT::Status-Fd=1"] & s.pkgs

proc weight(s: Step): float =
  case s.kind
  of stRepo: 1.0
  of stUpdate: 2.0
  of stInstall: 8.0
  of stRemove: 3.0

proc gauge(): float =
  var total, done = 0.0
  for i, s in steps:
    total += s.weight
    if i < stepAt: done += s.weight
    elif i == stepAt: done += s.weight * clamp(stepGauge, 0.0, 1.0)
  if total <= 0: 0.0 else: done / total

proc sizeOf(s: string): int64 =
  ## "52.3 MB" (apt's way) in bytes.
  let f = s.strip.splitWhitespace
  if f.len < 2: return -1
  var v = 0.0
  try: v = parseFloat(f[0].replace(",", ""))
  except ValueError: return -1
  let k = case f[1].toUpperAscii
          of "B": 1.0
          of "KB": 1e3
          of "MB": 1e6
          of "GB": 1e9
          else: 1.0
  int64(v * k)

proc readDryRun(lines: seq[string]) =
  ## What `apt-get install --assume-no` said: the space, the packages.
  spaceNeed = -1
  spaceGet = -1
  newCount = 0
  var inNew = false
  for l in lines:
    if l.startsWith("Need to get "):
      let s = l["Need to get ".len .. ^1]
      let cut = s.find(" of archives")
      let part = if cut > 0: s[0 ..< cut] else: s
      spaceGet = sizeOf(part.split('/')[^1])
    elif l.startsWith("After this operation, "):
      let s = l["After this operation, ".len .. ^1]
      let cut = s.find(" of additional")
      if cut > 0: spaceNeed = sizeOf(s[0 ..< cut])
    if l.startsWith("The following NEW packages"):
      inNew = true
    elif inNew and l.startsWith("  "):
      newCount += l.splitWhitespace.len
    else:
      inNew = false
    if "Unable to locate package" in l or "has no installation candidate" in l:
      needUpdate = true

proc plan() =
  ## The steps: the repositories first, the lists read, then in, then out.
  steps = @[]
  var repos: seq[string]
  var pk: seq[string]
  for i in toAdd:
    let o = Offers[i]
    if o.repo.len > 0 and not repoReady(o.repo) and o.repo notin repos: repos.add o.repo
    for p in o.packages:
      if p notin pk: pk.add p
  for r in repos: steps.add Step(kind: stRepo, pkgs: @[r & "-repo"])
  if pk.len > 0 and (needUpdate or forceUpdate or repos.len > 0 or listsAge() > 24):
    steps.add Step(kind: stUpdate)
  if pk.len > 0: steps.add Step(kind: stInstall, pkgs: pk)
  var rm: seq[string]
  for i in toRemove:
    for p in Offers[i].packages:
      if p notin rm: rm.add p
  if rm.len > 0: steps.add Step(kind: stRemove, pkgs: rm)

proc startStep() =
  stepGauge = 0
  pmSeen = false
  updateLines = 0
  let s = steps[stepAt]
  doing = case s.kind
          of stRepo: "Adding the " & s.pkgs.join(" ") & " repository"
          of stUpdate: "Reading the lists of programs"
          of stInstall: "Installing " & names(toAdd)
          of stRemove: "Removing " & names(toRemove)
  status = ""
  job.start(aptArgs(s))

proc readStatus(l: string) =
  ## apt's status lines (APT::Status-Fd): "dlstatus:3:42.5:Retrieving file 3
  ## of 25", "pmstatus:firefox:80:Installing firefox".
  let s = steps[stepAt]
  let f = l.split(':', 3)
  if f.len == 4 and f[0] in ["dlstatus", "pmstatus", "pmerror"]:
    var pct = 0.0
    try: pct = parseFloat(f[2]) / 100 except ValueError: discard
    if f[0] == "dlstatus":
      if not pmSeen: stepGauge = (if s.kind == stRemove: pct else: pct * 0.5)
      status = "Copying files: " & f[3].replace("Retrieving file", "file")
    elif f[0] == "pmstatus":
      pmSeen = true
      stepGauge = if s.kind == stRemove: pct else: 0.5 + pct * 0.5
      status = f[3]
    else:
      status = "Problem: " & f[3]
  elif s.kind == stUpdate and (l.startsWith("Get:") or l.startsWith("Hit:") or l.startsWith("Ign:")):
    inc updateLines
    stepGauge = min(0.95, float(updateLines) / 12)
    let w = l.splitWhitespace
    status = "Reading " & (if w.len > 1: w[1] else: "")

proc addTerminalItems() =
  ## The Terminal's programs just installed get an item in Program Manager;
  ## the ones removed lose theirs.
  var items = progItems()
  var changed = false
  for i, o in Offers:
    if o.cli.len == 0: continue
    let cmd = terminalCommand() & " -e " & o.cli
    var at = -1
    for k, it in items:
      if it.name == o.name and it.command == cmd: at = k
    if installed[i] and at < 0:
      items.add ProgItem(group: o.group, name: o.name, command: cmd, icon: "")
      changed = true
    elif not installed[i] and at >= 0:
      items.delete(at)
      changed = true
  if changed: saveProgItems(items)

proc entryOf(pkg: string): string =
  ## The command of the program `pkg` puts in Program Manager ("" none).
  let (outp, code) = execCmdEx("dpkg -L " & quoteShell(pkg) & " 2>/dev/null")
  if code != 0: return ""
  for line in outp.splitLines:
    if line.endsWith(".desktop") and "/applications/" in line:
      try:
        let e = readDesktopEntry(line)
        if e.name.len > 0: return runCommand(e)
      except CatchableError: discard

proc finish() =
  readInstalled()
  addTerminalItems()
  firstRun = ""
  firstName = ""
  if thenRole.len > 0:
    firstRun = selfCommand(thenRole)
    firstName = (if thenRole == "browser": "Retro Browser" else: thenRole)
  elif toAdd.len == 1:
    let o = Offers[toAdd[0]]
    if installed[toAdd[0]]:
      firstRun = if o.cli.len > 0: terminalCommand() & " -e " & o.cli else: entryOf(o.packages[0])
      firstName = o.name
  for i in 0 ..< want.len: want[i] = installed[i]
  screen = scDone

proc pumpWork() =
  for l in job.pump():
    readStatus(l)
  if job.running: return
  if job.code != 0:
    # (the lists: read again once, when a package was not found)
    var tail: seq[string]
    for l in job.lines:
      if l.startsWith("E:") or l.startsWith("pmerror") or "rror" in l: tail.add l
    if tail.len == 0: tail = job.lines[max(0, job.lines.len - 6) .. ^1]
    failText = tail[max(0, tail.len - 8) .. ^1].join("\n")
    screen = scFailed
    readInstalled()
    return
  inc stepAt
  if stepAt >= steps.len: finish()
  else: startStep()

proc check() =
  ## The space the programs to install need, from apt (it stops before
  ## doing anything).
  needUpdate = listsAge() > 24 * 30
  spaceNeed = -1
  spaceGet = -1
  newCount = 0
  var pk: seq[string]
  for i in toAdd:
    for p in Offers[i].packages:
      if p notin pk: pk.add p
  if pk.len == 0:
    screen = scConfirm
    return
  # (a repository not added yet: its packages are not known until it is)
  for i in toAdd:
    if not repoReady(Offers[i].repo):
      screen = scConfirm
      return
  job.start(@["apt-get", "install", "--assume-no"] & pk)
  screen = scChecking

proc pumpCheck() =
  discard job.pump()
  if job.running: return
  readDryRun(job.lines)
  screen = scConfirm

proc choose() =
  toAdd = @[]
  toRemove = @[]
  for i in 0 ..< Offers.len:
    if want[i] and not installed[i]: toAdd.add i
    elif not want[i] and installed[i]: toRemove.add i
  if not canInstall():
    screen = scManual
    return
  check()

# ---- the screen -------------------------------------------------------------------------------------

proc backdrop() =
  ## 3.1's Setup screen: blue going to black, the title in white italics.
  let r = rect(0, 0, ui.w, ui.h)
  let bands = 48
  for i in 0 ..< bands:
    let y0 = r.h * i div bands
    let y1 = r.h * (i + 1) div bands
    let k = 1.0 - float(i) / float(bands)
    fill(rect(0, y0, r.w, y1 - y0), color(0, 0, uint8(40 + 200 * k)))
  let st = TextStyle(bold: true, italic: true, serif: true, size: 2.2)
  let t = DesktopName & " Setup"
  text(dp(22), dp(18), t, color(0, 0, 0), st)
  text(dp(20), dp(16), t, color(255, 255, 255), st)

proc chooseDialog() =
  dialog(showMain, DesktopName & " Setup", 640):
    paragraph "Check the programs you want on your desktop; clear one that is installed " &
      "to remove it. Setup gets them from Termux's packages and puts them in Program Manager."
    let h = max(dp(120), min(dp(340), ui.h - dp(250)))
    scrollPanel(h):
      var last = ""
      for i, o in Offers:
        if o.group != last:
          last = o.group
          label(o.group, bold = true)
        row([170, -1]):
          checkbox(o.name, want[i])
          var about = o.about
          if installed[i]: about = "(installed) " & about
          elif o.big: about &= " -- large"
          label(about, enabled = installed[i] or want[i])
    var adds, rms = 0
    for i in 0 ..< Offers.len:
      if want[i] and not installed[i]: inc adds
      elif not want[i] and installed[i]: inc rms
    row:
      label("To install: " & $adds & "    To remove: " & $rms, enabled = adds + rms > 0)
      spring()
      if button("&Continue", isDefault = true, enabled = adds + rms > 0): choose()
      if button("E&xit"): quitApp()
  if not showMain: quitApp()

proc checkingDialog() =
  var open = true
  dialog(open, DesktopName & " Setup", 460):
    paragraph "Setup is checking what " & names(toAdd) & " need" &
      (if toAdd.len == 1: "s" else: "") & "..."
    progress(float((ui.now div 120) mod 20) / 20, showText = false)
    row:
      spring()
      if button("Cancel"):
        job.stop()
        screen = scChoose
  wakeIn(120)

proc confirmDialog() =
  var open = true
  dialog(open, DesktopName & " Setup", 520):
    if toAdd.len > 0:
      label("Setup will install:", bold = true)
      paragraph names(toAdd)
    if toRemove.len > 0:
      label("Setup will remove:", bold = true)
      paragraph names(toRemove)
    let free = freeSpace()
    form 0:
      if toAdd.len > 0:
        field "Space required:":
          label(if spaceNeed >= 0: mb(spaceNeed) & (if newCount > 0: " (" & $newCount & " packages)" else: "")
                else: "found once the lists are read")
        if spaceGet >= 0:
          field "From the Internet:": label mb(spaceGet)
      field "Space available:": label mb(free)
    if spaceNeed > 0 and free >= 0 and spaceNeed > free:
      label("There is not enough space: remove programs or files first.", color = color(192, 0, 0))
    row:
      spring()
      if button("&Continue", isDefault = true, enabled = not (spaceNeed > 0 and free >= 0 and spaceNeed > free)):
        plan()
        stepAt = 0
        if steps.len == 0: finish()
        else:
          screen = scWorking
          startStep()
      if button("&Back"): screen = scChoose
  if not open: screen = scChoose

proc workingDialog() =
  var open = true
  dialog(open, DesktopName & " Setup", 520):
    label(doing & "...", bold = true)
    label(if status.len > 0: status else: "Please wait.", literal = true)
    progress(gauge())
    row:
      label("Step " & $(stepAt + 1) & " of " & $steps.len, enabled = false)
      spring()
      # (stopping while the packages go in would leave them half there)
      let canStop = not pmSeen and steps[stepAt].kind != stRemove
      if button("Cancel", enabled = canStop):
        job.stop()
        readInstalled()
        screen = scChoose
  wakeIn(100)

proc doneDialog() =
  var open = true
  dialog(open, DesktopName & " Setup", 480):
    var said = ""
    if toAdd.len > 0: said = "Setup has installed " & names(toAdd) & ". "
    if toRemove.len > 0: said &= "It has removed " & names(toRemove) & ". "
    if toAdd.len > 0: said &= "You will find " & (if toAdd.len == 1: "it" else: "them") & " in Program Manager."
    paragraph said
    row:
      spring()
      if firstRun.len > 0 and button("&Start " & firstName, isDefault = true):
        launch(firstRun)
        quitApp()
      if button("OK", isDefault = firstRun.len == 0):
        if thenRole.len > 0: quitApp()
        screen = scChoose
  if not open: screen = scChoose

proc failedDialog() =
  var open = true
  dialog(open, DesktopName & " Setup", 560):
    let what = if doing.len > 0: $doing[0].toLowerAscii & doing[1 .. ^1] else: "its work"
    label("Setup could not finish " & what & ".", bold = true)
    paragraph "What the package manager said:"
    scrollPanel(dp(120)):
      for l in failText.splitLines: label(l, literal = true)
    paragraph "When it could not reach the Internet or a mirror: in the Terminal, " &
      "termux-change-repo picks another mirror, then pkg update. When another " &
      "program is installing (pkg in a Terminal): wait for it, and try again."
    row:
      if button("&Copy"): putClipboardText(failText)
      spring()
      if button("&Try Again", isDefault = true):
        forceUpdate = true
        choose()
      if button("&Back"): screen = scChoose
  if not open: screen = scChoose

proc manualDialog() =
  var open = true
  var pk, rm: seq[string]
  for i in toAdd: pk.add Offers[i].packages
  for i in toRemove: rm.add Offers[i].packages
  var cmd = ""
  if pk.len > 0: cmd = "sudo apt install " & pk.join(" ")
  if rm.len > 0: cmd &= (if cmd.len > 0: " && " else: "") & "sudo apt remove " & rm.join(" ")
  dialog(open, DesktopName & " Setup", 520):
    paragraph "Here the system's package manager needs the administrator. In a " &
      "Terminal (the names can differ on your system):"
    label(cmd, literal = true, bold = true)
    row:
      if button("&Copy"): putClipboardText(cmd)
      spring()
      if button("OK", isDefault = true): screen = scChoose
  if not open: screen = scChoose

proc runSetup*(args: seq[string]) =
  ## Setup (with `args`: the programs -- Offers' names or packages -- to
  ## install at once; `--then role` offers to start that after).
  var asked: seq[string]
  var k = 0
  while k < args.len:
    if args[k] == "--then" and k + 1 < args.len:
      thenRole = args[k + 1]
      k += 2
      continue
    asked.add args[k].toLowerAscii
    inc k
  readInstalled()
  want = installed
  for i, o in Offers:
    if o.name.toLowerAscii in asked or o.pkgs in asked: want[i] = true
  applyDesktopLook()
  openApp(DesktopName & " Setup", scaled(780), scaled(560), frame = wfSystem, userFrame = false,
          id = "setup")
  followLook()
  showArt("setup")
  maximizeSelf()
  if asked.len > 0: choose()
  while beginFrame():
    backdrop()
    case screen
    of scChoose: chooseDialog()
    of scChecking:
      pumpCheck()
      checkingDialog()
    of scConfirm: confirmDialog()
    of scWorking:
      pumpWork()
      if screen == scWorking: workingDialog()
    of scDone: doneDialog()
    of scFailed: failedDialog()
    of scManual: manualDialog()
    endFrame()
    appFrameDone()
  job.stop()
  closeApp()

proc offerFirefox*(): bool =
  ## Firefox is in Setup's list (and so can be installed from it).
  for o in Offers:
    if o.pkgs == "firefox": return true
  false
