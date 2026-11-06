## What every part of Retro Desktop shares: its settings, where its files
## are, starting programs, the installed programs (their desktop entries
## and icons).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, tables, algorithm, math, times, hashes]
import retroui
import retroui/[svgimport, imaging]
import retroui/uirelays/drivers/x11_driver

const
  DesktopVersion* = "0.1.5"
  DesktopName* = "Retro Desktop"
  SettingsName* = "retrodesktop"
  Teal* = "#008080"
    ## the desktop's color as Windows 3.1 had it

type
  AppEntry* = object
    ## A program the desktop can start: one of its own, or an installed
    ## one (a desktop entry).
    name*, command*, icon*, categories*, comment*: string
    terminal*: bool
    builtin*: bool
    id*: string            ## the desktop entry's file name, or the built-in's role

# ---- settings ---------------------------------------------------------------------------------------

proc desktopSettings*(): Settings = loadSettings(SettingsName)
  ## The desktop's settings (Control Panel writes them).

proc setting*(s: Settings; key, default: string): string =
  ## A setting, or `default` when it is not set.
  s.getOrDefault(key, default)

proc saveDesktopSettings*(s: Settings) = discard saveSettings(SettingsName, s)
  ## Keeps the desktop's settings.

proc hexColor*(s: string; default: Color): Color =
  ## "#rrggbb" as a color (`default` when it is not one).
  var t = s.strip
  if t.startsWith("#"): t = t[1 .. ^1]
  if t.len != 6: return default
  try:
    let v = parseHexInt(t)
    color(uint8((v shr 16) and 255), uint8((v shr 8) and 255), uint8(v and 255))
  except ValueError: default

proc schemeTheme*(name: string): Theme =
  ## The color scheme called `name` (Classic when there is none).
  for t in builtinThemes:
    if cmpIgnoreCase(t.name, name) == 0: return t.theme
  Classic

proc applyDesktopLook*() =
  ## The color scheme, font and text size Control Panel set, for one of the
  ## desktop's own programs.
  let s = desktopSettings()
  # (the cursors in the classic shapes, at the screen's size)
  x11DrawnCursors = 1
  ui.theme = schemeTheme(s.setting("scheme", "Classic"))
  case s.setting("font", "sans")
  of "serif": setUiFont(ufSerif)
  of "mono": setUiFont(ufMono)
  else: setUiFont(ufSans)
  # (the sizes only once Control Panel set them: until then the screen's own,
  # and what RETRO_SCALE or Ctrl + and - say)
  if s.hasKey("textScale"):
    try: setTextScale(parseInt(s["textScale"])) except ValueError: discard
  if s.hasKey("size"):
    try: setUiScale(parseInt(s["size"])) except ValueError: discard

proc devScale*(): float =
  ## The screen's own pixels per design pixel: the kit's scale times its
  ## pixel zoom (2 on a 2K tablet, where each logical pixel is drawn 2 x 2).
  ## X windows, icons made for the screen and the dpi other programs are
  ## told are in these.
  dpf(1.0) * float(max(1, pxScale))

proc devPx*(v: float): int =
  ## `v` design pixels in the screen's own pixels.
  max(1, int(round(v * devScale())))

proc onOff*(s: Settings; key: string; default: bool): bool =
  ## A setting that is "on", "off" or "auto" (`default`).
  case s.setting(key, "auto")
  of "on": true
  of "off": false
  else: default

# ---- starting programs ----------------------------------------------------------------------------

proc prefixDir*(): string =
  ## Where the system's programs and their data are: Termux's prefix, else /usr.
  let p = getEnv("PREFIX")
  if p.len > 0 and dirExists(p): p
  elif dirExists("/data/data/com.termux/files/usr"): "/data/data/com.termux/files/usr"
  else: "/usr"

proc launch*(command: string) =
  ## Starts `command` (a shell command line) on its own: it outlives the
  ## desktop's program that started it, and leaves no process behind to wait for.
  if command.strip.len == 0: return
  discard execShellCmd("(" & command & ") </dev/null >/dev/null 2>&1 &")

proc selfCommand*(role: string): string =
  ## The command that starts one of the desktop's own programs (`role`).
  quoteShell(getAppFilename()) & " " & role

proc companion*(name: string): string =
  ## One of the programs that come with the desktop (retro-files...): beside
  ## this one, or on the PATH; "" when it is not there.
  let beside = getAppDir() / name
  if fileExists(beside): return beside
  findExe(name)

proc terminalCommand*(): string =
  ## The desktop's Terminal, as a command line that runs what follows its
  ## "-e" in it.
  selfCommand("terminal")

proc runCommand*(e: AppEntry): string =
  ## The command line that starts `e` (in the Terminal when it asks for one).
  if e.terminal: terminalCommand() & " -e " & e.command
  else: e.command

# ---- installed programs ---------------------------------------------------------------------------

proc dataDirs*(): seq[string] =
  ## Where desktop entries and icons are (XDG_DATA_HOME, XDG_DATA_DIRS,
  ## Termux's prefix).
  let home = getEnv("XDG_DATA_HOME")
  result.add(if home.len > 0: home else: getHomeDir() / ".local" / "share")
  let dirs = getEnv("XDG_DATA_DIRS")
  for d in dirs.split(':'):
    if d.len > 0 and d notin result: result.add d
  for d in [prefixDir() / "share", "/usr/local/share", "/usr/share"]:
    if d notin result and dirExists(d): result.add d

proc stripFieldCodes(exec: string): string =
  ## A desktop entry's Exec without its %f, %U... (the desktop starts
  ## programs without files).
  var parts: seq[string]
  for p in exec.splitWhitespace:
    if p.len == 2 and p[0] == '%': continue
    if p == "%%": parts.add "%"
    else: parts.add p
  parts.join(" ")

proc readDesktopEntry*(path: string): AppEntry =
  ## A desktop entry file; `name` "" when it is not a program to show.
  var inEntry = false
  var hidden = false
  var kind = ""
  for raw in lines(path):
    let line = raw.strip
    if line.startsWith("["):
      inEntry = line == "[Desktop Entry]"
      continue
    if not inEntry or '=' notin line: continue
    let k = line[0 ..< line.find('=')].strip
    let v = line[line.find('=') + 1 .. ^1].strip
    case k
    of "Name": result.name = v
    of "Exec": result.command = stripFieldCodes(v)
    of "Icon": result.icon = v
    of "Categories": result.categories = v
    of "Comment": result.comment = v
    of "Terminal": result.terminal = v.toLowerAscii == "true"
    of "Type": kind = v
    of "NoDisplay", "Hidden":
      if v.toLowerAscii == "true": hidden = true
    else: discard
  result.id = path.extractFilename
  if hidden or kind != "Application" or result.command.len == 0: result.name = ""

proc installedApps*(): seq[AppEntry] =
  ## The programs installed with a desktop entry (each id once: the first
  ## found, so the user's own entries win), by name.
  var seen: Table[string, bool]
  for d in dataDirs():
    let dir = d / "applications"
    if not dirExists(dir): continue
    for kind, path in walkDir(dir):
      if kind notin {pcFile, pcLinkToFile} or not path.endsWith(".desktop"): continue
      let id = path.extractFilename
      if seen.hasKey(id) or id.startsWith("retro-"): continue
      seen[id] = true
      try:
        let e = readDesktopEntry(path)
        if e.name.len > 0: result.add e
      except CatchableError: discard
  result.sort(proc (a, b: AppEntry): int = cmpIgnoreCase(a.name, b.name))

proc groupOf*(e: AppEntry): string =
  ## Which Program Manager group an installed program goes in, from its
  ## categories.
  let c = ";" & e.categories & ";"
  if ";Game;" in c: "Games"
  elif ";Development;" in c: "Development"
  elif ";Graphics;" in c: "Graphics"
  elif ";Network;" in c or ";WebBrowser;" in c: "Internet"
  elif ";Office;" in c: "Office"
  elif ";AudioVideo;" in c or ";Audio;" in c or ";Video;" in c: "Multimedia"
  elif ";System;" in c or ";Settings;" in c or ";TerminalEmulator;" in c: "System"
  elif ";Utility;" in c: "Accessories"
  else: "Applications"

# ---- icons ------------------------------------------------------------------------------------------

proc findIconFile*(name: string): string =
  ## The file of an icon theme's icon `name` (PNG first, then SVG), or the
  ## path itself when it is one; "" when there is none.
  if name.len == 0: return ""
  if name.isAbsolute: return (if fileExists(name): name else: "")
  for d in dataDirs():
    for size in ["48x48", "64x64", "32x32", "96x96", "128x128", "192x192", "256x256", "24x24", "512x512"]:
      for theme in ["hicolor", "Adwaita", "breeze"]:
        let p = d / "icons" / theme / size / "apps" / name & ".png"
        if fileExists(p): return p
    let pm = d / "pixmaps" / name & ".png"
    if fileExists(pm): return pm
  for d in dataDirs():
    for theme in ["hicolor", "Adwaita", "breeze"]:
      let p = d / "icons" / theme / "scalable" / "apps" / name & ".svg"
      if fileExists(p): return p
    let pm = d / "pixmaps" / name & ".svg"
    if fileExists(pm): return pm
    let xpm = d / "pixmaps" / name & ".xpm"
    if fileExists(xpm): return ""
  ""

proc iconCacheDir(): string =
  let x = getEnv("XDG_CACHE_HOME")
  (if x.len > 0: x else: getHomeDir() / ".cache") / SettingsName / "icons"

proc cachedIcon(path: string; size: int): Bitmap =
  ## The icon at `path` as drawn before at `size` (its pixels kept in the
  ## cache folder: no PNG to decode, no SVG to draw again); nil when there
  ## is none, or the icon changed since.
  try:
    let stamp = $getLastModificationTime(path).toUnix
    let f = iconCacheDir() / $hash(path & "@" & $size) & ".px"
    if not fileExists(f): return nil
    let data = readFile(f)
    let head = stamp & "\n" & path & "\n"
    let n = size * size
    if not data.startsWith(head) or data.len != head.len + n * 4: return nil
    result = Bitmap(w: size, h: size, px: newSeq[uint32](n))
    copyMem(addr result.px[0], unsafeAddr data[head.len], n * 4)
  except CatchableError: result = nil

proc keepIcon(path: string; size: int; b: Bitmap) =
  if b == nil or b.w != size or b.h != size or b.px.len != size * size: return
  try:
    createDir(iconCacheDir())
    let head = $getLastModificationTime(path).toUnix & "\n" & path & "\n"
    var data = newString(head.len + b.px.len * 4)
    copyMem(addr data[0], unsafeAddr head[0], head.len)
    copyMem(addr data[head.len], unsafeAddr b.px[0], b.px.len * 4)
    writeFile(iconCacheDir() / $hash(path & "@" & $size) & ".px", data)
  except CatchableError: discard

proc loadIcon*(name: string; size: int): Bitmap =
  ## The icon `name` (a theme's or a file) at `size` pixels, nil when there is
  ## none that can be read. SVG icons are drawn at that size. What was drawn
  ## once is kept (~/.cache/retrodesktop/icons): Program Manager opens quicker
  ## the next time.
  let f = findIconFile(name)
  if f.len == 0: return nil
  result = cachedIcon(f, size)
  if result != nil: return
  try:
    if f.toLowerAscii.endsWith(".svg"):
      result = rasterizeSvg(readFile(f), size, size)
    else:
      result = loadPicture(f, size, size)
  except CatchableError, Defect: result = nil
  if result != nil and (result.w != size or result.h != size):
    # (a picture not square: in the middle of a square, so it can be kept)
    let sq = Bitmap(w: size, h: size, px: newSeq[uint32](size * size))
    let ox = (size - result.w) div 2
    let oy = (size - result.h) div 2
    for y in 0 ..< min(result.h, size):
      for x in 0 ..< min(result.w, size):
        if ox + x >= 0 and oy + y >= 0 and ox + x < size and oy + y < size:
          sq.px[(oy + y) * size + ox + x] = result.px[y * result.w + x]
    result = sq
  keepIcon(f, size, result)

# ---- Program Manager's own items --------------------------------------------------------------------

type
  ProgItem* = object
    ## A program the user put in a Program Manager group (File > New), or
    ## in StartUp (started with the desktop).
    group*, name*, command*, icon*: string

const ProgmanSettings* = "retrodesktop-progman"

proc progItems*(): seq[ProgItem] =
  ## The items the user made, in the order made.
  for line in loadSettings(ProgmanSettings).getOrDefault("items", "").split('\n'):
    let f = line.split('\t')
    if f.len >= 3 and f[1].len > 0:
      result.add ProgItem(group: f[0], name: f[1], command: f[2], icon: (if f.len > 3: f[3] else: ""))

proc saveProgItems*(items: openArray[ProgItem]) =
  ## Keeps the items the user made.
  var s = loadSettings(ProgmanSettings)
  var lines: seq[string]
  for it in items:
    lines.add [it.group, it.name, it.command, it.icon].join("\t").replace("\n", " ")
  s["items"] = lines.join("\n")
  discard saveSettings(ProgmanSettings, s)

proc scaled*(v: int): int =
  ## A window's size in design pixels, grown by the size of everything the
  ## user chose (Control Panel's Fonts, or RETRO_SCALE): the window opens
  ## large enough for what it shows. (The screen's density is the kit's.)
  var pct = 100
  try:
    let env = getEnv("RETRO_SCALE")
    pct = if env.len > 0: parseInt(env) else: parseInt(desktopSettings().setting("size", "100"))
  except ValueError: discard
  v * clamp(pct, 50, 300) div 100

proc appsStamp*(): string =
  ## What changes when a program is installed or removed: the times the
  ## folders of desktop entries changed, and Program Manager's own items.
  for d in dataDirs():
    let dir = d / "applications"
    try:
      if dirExists(dir): result.add $getLastModificationTime(dir).toUnix & ";"
    except CatchableError: discard
  result.add loadSettings(ProgmanSettings).getOrDefault("items", "").len.`$`
