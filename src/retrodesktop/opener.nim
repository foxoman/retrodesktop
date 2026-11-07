## Open: a file or a link opened in the program for its kind -- the one you
## chose before ("Always use this program"), else the program that says it
## takes that kind of file (its desktop entry's MimeType), else you choose in
## the Open With box (in Termux, an Android app too: termux-open).
##
## The desktop's programs reach it through `xdg-open`: the desktop puts its
## own xdg-open first on their PATH (Retro Files opening a file, a program
## opening a link).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, tables]
import retroui
import common, link, browser

const OpenSettings = "retrodesktop-open"

type Handler = object
  name, exec: string             ## `exec`: the desktop entry's (with %f, %u...)
  mimes: seq[string]
  terminal: bool

var types = {".txt": "text/plain", ".md": "text/markdown", ".html": "text/html", ".htm": "text/html",
             ".pdf": "application/pdf", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
             ".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml", ".bmp": "image/bmp",
             ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".flac": "audio/flac", ".wav": "audio/x-wav",
             ".m4a": "audio/mp4", ".mp4": "video/mp4", ".mkv": "video/x-matroska", ".webm": "video/webm",
             ".avi": "video/x-msvideo", ".mov": "video/quicktime", ".zip": "application/zip",
             ".tar": "application/x-tar", ".gz": "application/gzip", ".7z": "application/x-7z-compressed",
             ".odt": "application/vnd.oasis.opendocument.text",
             ".ods": "application/vnd.oasis.opendocument.spreadsheet",
             ".odp": "application/vnd.oasis.opendocument.presentation",
             ".doc": "application/msword",
             ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
             ".xls": "application/vnd.ms-excel",
             ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
             ".ppt": "application/vnd.ms-powerpoint",
             ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
             ".csv": "text/csv", ".json": "application/json", ".xml": "application/xml",
             ".py": "text/x-python", ".nim": "text/x-nim", ".c": "text/x-csrc", ".h": "text/x-chdr",
             ".js": "text/javascript", ".sh": "application/x-shellscript", ".epub": "application/epub+zip",
             ".log": "text/plain", ".ini": "text/plain", ".conf": "text/plain"}.toTable

proc readMimeTypes() =
  ## The system's list of kinds (mime.types), for the extensions not above.
  for f in [prefixDir() / "etc/mime.types", "/etc/mime.types"]:
    if not fileExists(f): continue
    try:
      for line in lines(f):
        if line.len == 0 or line[0] == '#': continue
        let w = line.splitWhitespace
        for e in w[1 .. ^1]:
          if not types.hasKey("." & e): types["." & e] = w[0]
    except CatchableError: discard

proc kindOf(target: string): string =
  if target.startsWith("http://") or target.startsWith("https://"): return "x-scheme-handler/http"
  if target.startsWith("mailto:"): return "x-scheme-handler/mailto"
  if dirExists(target): return "inode/directory"
  types.getOrDefault(target.splitFile.ext.toLowerAscii, "application/octet-stream")

proc handlers(): seq[Handler] =
  ## Every program with a desktop entry, and the kinds of files it takes.
  var seen: Table[string, bool]
  for d in dataDirs():
    let dir = d / "applications"
    if not dirExists(dir): continue
    for kind, path in walkDir(dir):
      if not path.endsWith(".desktop") or seen.hasKey(path.extractFilename): continue
      seen[path.extractFilename] = true
      var h = Handler()
      var inEntry, hidden = false
      try:
        for raw in lines(path):
          let line = raw.strip
          if line.startsWith("["):
            inEntry = line == "[Desktop Entry]"
            continue
          if not inEntry or '=' notin line: continue
          let k = line[0 ..< line.find('=')].strip
          let v = line[line.find('=') + 1 .. ^1].strip
          case k
          of "Name": (if h.name.len == 0: h.name = v)
          of "Exec": h.exec = v
          of "MimeType":
            for m in v.split(';'):
              if m.len > 0: h.mimes.add m
          of "Terminal": h.terminal = v.toLowerAscii == "true"
          of "NoDisplay", "Hidden": (if v.toLowerAscii == "true": hidden = true)
          else: discard
      except CatchableError: continue
      if h.name.len > 0 and h.exec.len > 0 and not hidden: result.add h

proc commandFor(h: Handler; target: string): string =
  ## The desktop entry's Exec with the file (or the link) in it.
  var parts: seq[string]
  var placed = false
  for p in h.exec.splitWhitespace:
    if p in ["%f", "%F", "%u", "%U"]:
      parts.add quoteShell(target)
      placed = true
    elif p.len == 2 and p[0] == '%': continue
    else: parts.add p
  if not placed: parts.add quoteShell(target)
  result = parts.join(" ")
  if h.terminal: result = terminalCommand() & " -e " & result

proc ownHandlers(kind, target: string): seq[Handler] =
  ## The desktop's own programs for this kind of file.
  let q = quoteShell(target)
  if kind == "x-scheme-handler/http" or kind == "text/html":
    if firefoxPath().len > 0:
      result.add Handler(name: "Retro Browser", exec: selfCommand("browser") & " " & q)
  if kind == "text/html" or kind == "text/plain":
    result.add Handler(name: "Write", exec: selfCommand("write") & " " & q)
  if kind.startsWith("text/") or kind in ["application/json", "application/xml", "application/x-shellscript"]:
    let n = companion("retro-notepad")
    if n.len > 0: result.add Handler(name: "Notepad", exec: quoteShell(n) & " " & q)
  if kind.startsWith("image/"):
    let p = companion("retro-photo")
    if p.len > 0: result.add Handler(name: "Paintbrush", exec: quoteShell(p) & " " & q)
  if kind == "inode/directory":
    let f = companion("retro-files")
    if f.len > 0: result.add Handler(name: "File Manager", exec: quoteShell(f) & " " & q)

proc runOpen*(args: seq[string]) =
  ## Opens `args[0]` (a file, a folder or a link) in its program.
  if args.len == 0: return
  var target = args[0]
  if target.startsWith("file://"): target = target[7 .. ^1].replace("%20", " ")
  if not target.contains("://") and not target.startsWith("mailto:") and
     (fileExists(target) or dirExists(target)):
    target = absolutePath(target)
  readMimeTypes()
  let kind = kindOf(target)
  let ext = if kind.startsWith("x-scheme-handler/"): kind else: target.splitFile.ext.toLowerAscii
  # (what was chosen before for this kind)
  let chosen = loadSettings(OpenSettings).getOrDefault(ext, "")
  if chosen.len > 0:
    launch(chosen.replace("%f", quoteShell(target)))
    return
  var list = ownHandlers(kind, target)
  for h in handlers():
    if kind in h.mimes:
      list.add Handler(name: h.name, exec: commandFor(h, target))
  if list.len == 1:
    launch(list[0].exec)
    return
  # (more than one, or none: the Open With box)
  var others: seq[Handler]
  for h in handlers():
    var known = false
    for l in list:
      if l.name == h.name: known = true
    if not known: others.add Handler(name: h.name, exec: commandFor(h, target))
  let android = inTermux() and findExe("termux-open").len > 0
  var names: seq[string]
  for h in list: names.add h.name
  for h in others: names.add h.name
  if android: names.add "An Android app (termux-open)"
  if names.len == 0:
    names.add "(no program is installed for it: Setup installs more)"
  applyDesktopLook()
  openApp("Open With", scaled(420), scaled(300), frame = wfSystem, userFrame = false, id = "open")
  asDialog()
  var sel = 0
  var always = false
  while beginFrame():
    label("Open \"" & (if target.contains("://"): target else: target.extractFilename) & "\" with:",
          literal = true)
    discard listbox(names, sel, rows = 9)
    if ext.len > 0 and ext != "inode/directory":
      checkbox("&Always use this program for " & (if ext.startsWith("."): ext & " files" else: "these links"),
               always)
    row:
      spring()
      let ok = sel in 0 ..< list.len + others.len or (android and sel == names.high)
      if button("OK", isDefault = true, enabled = ok):
        var cmd = ""
        if sel < list.len: cmd = list[sel].exec
        elif sel < list.len + others.len: cmd = others[sel - list.len].exec
        else: cmd = "termux-open " & quoteShell(target)
        if always and ext.len > 0:
          var s = loadSettings(OpenSettings)
          s[ext] = cmd.replace(quoteShell(target), "%f")
          discard saveSettings(OpenSettings, s)
        launch(cmd)
        quitApp()
      if button("Cancel") or ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()

proc installOpener*() =
  ## The desktop's own `xdg-open`, first on its programs' PATH: what they
  ## open goes to `retro-desktop open`.
  let dir = dataDir(SettingsName) / "bin"
  try:
    createDir(dir)
    let sh = if fileExists(prefixDir() / "bin/sh"): prefixDir() / "bin/sh" else: "/bin/sh"
    let f = dir / "xdg-open"
    let body = "#!" & sh & "\n# Retro Desktop's: what its programs open goes to its Open.\n" &
               "exec " & quoteShell(selfPath()) & " open \"$@\"\n"
    if not fileExists(f) or readFile(f) != body:
      writeFile(f, body)
      setFilePermissions(f, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec,
                             fpOthersRead, fpOthersExec})
    # (notify-send: the programs' notifications to Android's, or to a box)
    let n = dir / "notify-send"
    let nbody = "#!" & sh & "\n# Retro Desktop's: notifications to Android (Termux:API) or the desktop.\n" &
                "exec " & quoteShell(selfPath()) & " notify \"$@\"\n"
    if not fileExists(n) or readFile(n) != nbody:
      writeFile(n, nbody)
      setFilePermissions(n, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec,
                             fpOthersRead, fpOthersExec})
    let path = getEnv("PATH")
    if not path.startsWith(dir & ":"): putEnv("PATH", dir & ":" & path)
  except CatchableError: discard
