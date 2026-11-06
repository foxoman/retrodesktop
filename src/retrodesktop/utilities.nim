## Disk Space, News Reader and Share Desktop.
##
## - Disk Space: how full the storage is, and what fills a folder -- its
##   folders and files by size, measured on a thread of their own; into a
##   folder with a double click; the package caches let go.
## - News Reader: news feeds (RSS, Atom) -- a few to start, yours to add --
##   their items, the words of one, the page in the browser.
## - Share Desktop: this desktop on a computer's screen, through VNC
##   (x11vnc): its address, a password, on and off.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, algorithm, locks, typedthreads, posix, xmlparser, xmltree, net, osproc]
import retroui
import retroui/http
import common, link, help, tasks

proc human(bytes: int64): string =
  if bytes < 1024: $bytes & " B"
  elif bytes < 1024 * 1024: formatFloat(float(bytes) / 1024, ffDecimal, 1) & " KB"
  elif bytes < 1024 * 1024 * 1024: formatFloat(float(bytes) / 1024 / 1024, ffDecimal, 1) & " MB"
  else: formatFloat(float(bytes) / 1024 / 1024 / 1024, ffDecimal, 2) & " GB"

# ==== Disk Space =======================================================================================

var
  scanLock: Lock
  scanned {.guard: scanLock.}: seq[(string, int64, bool)]   ## name, size, a folder
  scanDone {.guard: scanLock.}: bool
  scanThread: Thread[string]

proc sizeOf(path: string): int64 {.gcsafe.} =
  ## A folder's size, all that is in it (links not followed).
  try:
    for kind, p in walkDir(path):
      case kind
      of pcFile: result += getFileSize(p)
      of pcDir: result += sizeOf(p)
      else: discard
  except CatchableError: discard

proc scan(folder: string) {.thread.} =
  try:
    for kind, p in walkDir(folder):
      var size: int64 = 0
      try:
        if kind == pcFile: size = getFileSize(p)
        elif kind == pcDir: size = sizeOf(p)
      except CatchableError: discard
      {.cast(gcsafe).}:
        withLock scanLock: scanned.add (p.extractFilename, size, kind == pcDir)
  except CatchableError: discard
  {.cast(gcsafe).}:
    withLock scanLock: scanDone = true

proc runDiskSpace*() =
  applyDesktopLook()
  openApp("Disk Space", scaled(520), scaled(460), frame = wfSystem, userFrame = false, id = "diskspace")
  showArt("diskspace")
  followLook()
  initLock(scanLock)
  var places = @[("Home", getHomeDir())]
  if dirExists(getHomeDir() / "storage/shared"): places.add ("Phone storage", getHomeDir() / "storage/shared")
  places.add ("Programs", prefixDir())
  var placeAt = 0
  var folder = places[0][1]
  var items: seq[(string, int64, bool)]
  var running = false
  var sel = 0
  var cleanJob: Task
  var said = ""
  var showAbout = false
  proc start(f: string) =
    if running: return
    folder = f
    items = @[]
    withLock scanLock:
      scanned = @[]
      scanDone = false
    running = true
    createThread(scanThread, scan, f)
  start(folder)
  while beginFrame():
    helpKeys("diskspace")
    if running:
      var done = false
      withLock scanLock:
        items = scanned
        done = scanDone
      items.sort(proc (a, b: (string, int64, bool)): int = cmp(b[1], a[1]))
      if done:
        running = false
        joinThread(scanThread)
      else: wakeIn(300)
    if cleanJob != nil and cleanJob.check():
      said = "The package caches are let go."
      cleanJob = nil
      start(folder)
    menubar:
      menu "&Disk":
        if menuItem("&Refresh", "F5", enabled = not running): start(folder)
        if menuItem("&Clean the Package Cache", enabled = findExe("apt-get").len > 0 and cleanJob == nil):
          cleanJob = run("apt-get clean")
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("diskspace")
        menuSeparator()
        if menuItem("&About Disk Space..."): showAbout = true
    var st: Statvfs
    if statvfs(cstring(folder), st) == 0:
      let total = int64(st.f_blocks) * int64(st.f_frsize)
      let free = int64(st.f_bavail) * int64(st.f_frsize)
      label("Used " & human(total - free) & " of " & human(total) & "  --  " & human(free) & " free")
      progress(if total > 0: float(total - free) / float(total) else: 0)
    row:
      var names: seq[string]
      for (n, _) in places: names.add n
      if combo(names, placeAt, w = dp(150)): start(places[placeAt][1])
      if button("&Up", enabled = not running and folder.parentDir != folder and folder.len > 1):
        start(folder.parentDir)
      spring()
      if running: label("Measuring...", enabled = false)
    label(folder, literal = true, enabled = false)
    var total: int64 = 0
    for it in items: total += it[1]
    let area = canvas(-1, remainingH() - lineHeight() - Gap)
    fill(area, ui.theme.window)
    sunken(area)
    let rowH = lineHeight() + dp(6)
    let hit = interact(idOf("disk-list"), area, focusable = false)
    pushClip(area)
    for i, (name, size, isDir) in items:
      let y = area.y + 2 + i * rowH
      if y > area.y + area.h: break
      let r = rect(area.x + 2, y, area.w - 4, rowH)
      if i == sel: fill(r, ui.theme.select)
      let ink = if i == sel: ui.theme.selectText else: ui.theme.text
      let barW = int(float(r.w div 3) * (if items[0][1] > 0: float(size) / float(items[0][1]) else: 0))
      fill(rect(r.x + dp(4), r.y + dp(3), barW, rowH - dp(6)), (if isDir: color(0, 128, 128) else: color(128, 128, 0)))
      text(r.x + r.w div 3 + dp(12), r.y + dp(3), (if isDir: name & "/" else: name), ink)
      let s = human(size)
      text(r.x + r.w - textWidth(s) - dp(6), r.y + dp(3), s, ink)
      if hit.hover and ui.my >= r.y and ui.my < r.y + r.h:
        if ui.pressed:
          if sel == i and (ui.clicks >= 2 or fingers()) and isDir and not running: start(folder / name)
          sel = i
    popClip()
    label(if said.len > 0: said else: $items.len & " items, " & human(total), enabled = said.len == 0)
    aboutBox(showAbout, "Disk Space", DesktopVersion, ["What fills the storage.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()

# ==== News Reader ======================================================================================

type
  Item = object
    title, link, text, date: string
  Feed = object
    title, url: string
    items: seq[Item]
    error: string

const StartFeeds = [("BBC News: World", "https://feeds.bbci.co.uk/news/world/rss.xml"),
                    ("Hacker News", "https://hnrss.org/frontpage"),
                    ("NASA: Breaking News", "https://www.nasa.gov/news-release/feed/"),
                    ("Nim's news", "https://nim-lang.org/feed.xml")]

var
  newsLock: Lock
  fetched {.guard: newsLock.}: seq[(string, string, int, string)]   ## url, body, status, error
  newsThreads: seq[ref Thread[string]]

proc fetchFeed(url: string) {.thread.} =
  var body, err = ""
  var status = 0
  try:
    let r = httpRequest("GET", url, timeoutSec = 30)
    body = r.body
    status = r.status
    if r.status notin 200 .. 299: err = (if r.status == 0: r.error else: "the site answered " & $r.status)
  except CatchableError as e: err = e.msg
  {.cast(gcsafe).}:
    withLock newsLock: fetched.add (url, body, status, err)

proc plain(html: string): string =
  ## Words without the HTML around them.
  var inTag = false
  var tag = ""
  for ch in html:
    if ch == '<':
      inTag = true
      tag = ""
    elif ch == '>':
      inTag = false
      # (a paragraph, a line, a list item: a space between them; bold or a link: none)
      let name = tag.strip(chars = {'/', ' '}).split(' ')[0].toLowerAscii
      if name in ["p", "br", "div", "li", "ul", "ol", "tr", "td", "h1", "h2", "h3", "h4", "img", "hr",
                  "blockquote", "figure", "figcaption"]: result.add ' '
    elif inTag: tag.add ch
    else: result.add ch
  result = result.multiReplace(("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                               ("&#39;", "'"), ("&nbsp;", " "), ("&#8217;", "'"), ("&#8220;", "\""),
                               ("&#8221;", "\""))
  result = result.splitWhitespace.join(" ")

proc parseFeed(body: string): (string, seq[Item]) =
  let x = parseXml(body)
  let ch = x.child("channel")
  if ch != nil:
    let t = ch.child("title")
    if t != nil: result[0] = t.innerText
    for it in ch.findAll("item"):
      var i: Item
      for (k, dst) in [("title", addr i.title), ("link", addr i.link), ("description", addr i.text),
                       ("pubDate", addr i.date)]:
        let c = it.child(k)
        if c != nil: dst[] = c.innerText
      i.text = plain(i.text)
      result[1].add i
  else:
    # Atom
    let t = x.child("title")
    if t != nil: result[0] = t.innerText
    for e in x.findAll("entry"):
      var i: Item
      if e.child("title") != nil: i.title = e.child("title").innerText
      for l in e.findAll("link"):
        if l.attr("rel") in ["", "alternate"]: i.link = l.attr("href")
      for k in ["summary", "content"]:
        if i.text.len == 0 and e.child(k) != nil: i.text = plain(e.child(k).innerText)
      for k in ["updated", "published"]:
        if i.date.len == 0 and e.child(k) != nil: i.date = e.child(k).innerText
      result[1].add i

proc runNews*() =
  applyDesktopLook()
  openApp("News Reader", scaled(700), scaled(500), frame = wfSystem, userFrame = false, id = "news")
  showArt("news")
  followLook()
  initLock(newsLock)
  var feeds: seq[Feed]
  let kept = desktopSettings().setting("feeds", "")
  if kept.len > 0:
    for line in kept.split('\n'):
      let f = line.split('\t')
      if f.len == 2: feeds.add Feed(title: f[0], url: f[1])
  else:
    for (t, u) in StartFeeds: feeds.add Feed(title: t, url: u)
  proc keepFeeds() =
    var lines: seq[string]
    for f in feeds: lines.add f.title & "\t" & f.url
    var s = desktopSettings()
    s["feeds"] = lines.join("\n")
    saveDesktopSettings(s)
  var waiting = 0
  proc refreshAll() =
    for f in feeds:
      var th = new Thread[string]
      createThread(th[], fetchFeed, f.url)
      newsThreads.add th
      inc waiting
  refreshAll()
  var fsel, isel = 0
  var showAdd, showAbout, askRemove: bool
  var newUrl = ""
  while beginFrame():
    helpKeys("news")
    var got: seq[(string, string, int, string)]
    withLock newsLock:
      got = move fetched
      fetched = @[]
    for (url, body, status, err) in got:
      dec waiting
      for f in feeds.mitems:
        if f.url == url:
          if err.len > 0: f.error = err
          else:
            try:
              let (t, its) = parseFeed(body)
              f.items = its
              f.error = ""
              if f.title.len == 0 or f.title == f.url: f.title = (if t.len > 0: t else: url)
            except CatchableError: f.error = "this is not a news feed"
      keepFeeds()
    if waiting > 0: wakeIn(300)
    menubar:
      menu "&Feeds":
        if menuItem("&Add a Feed..."):
          newUrl = ""
          showAdd = true
        if menuItem("&Remove the Feed", enabled = fsel in 0 ..< feeds.len): askRemove = true
        if menuItem("&Refresh", "F5"): refreshAll()
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("news")
        menuSeparator()
        if menuItem("&About News Reader..."): showAbout = true
    if hotkeyPressed("F5"): refreshAll()
    row([180, -1]):
      col:
        var names: seq[string]
        for f in feeds: names.add f.title & (if f.items.len > 0: " (" & $f.items.len & ")" else: "")
        if listbox(names, fsel, rows = -1): isel = 0
      col:
        if fsel in 0 ..< feeds.len:
          let f = feeds[fsel]
          if f.error.len > 0: label("Could not read it: " & f.error, color = color(170, 0, 0))
          elif f.items.len == 0: label(if waiting > 0: "Reading..." else: "Nothing in it yet.", enabled = false)
          var titles: seq[string]
          for it in f.items: titles.add it.title
          listbox(titles, isel, rows = max(4, (remainingH() div 2) div ItemH))
          if isel in 0 ..< f.items.len:
            let it = f.items[isel]
            label(it.title, bold = true, literal = true)
            if it.date.len > 0: label(it.date, enabled = false, literal = true)
            beginPanel(max(dp(60), remainingH() - CtrlH - 2 * Gap), key = "item")
            paragraph it.text
            endPanel()
            row:
              spring()
              if button("&Read on the Site", isDefault = true, enabled = it.link.len > 0):
                launch(selfCommand("open") & " " & quoteShell(it.link))
    if showAdd:
      if inputBox(showAdd, "Add a Feed", "The feed's address (RSS or Atom):", newUrl) == 1:
        let u = newUrl.strip
        if u.startsWith("http"):
          feeds.add Feed(title: u, url: u)
          fsel = feeds.high
          var th = new Thread[string]
          createThread(th[], fetchFeed, u)
          newsThreads.add th
          inc waiting
          keepFeeds()
    if askRemove and fsel in 0 ..< feeds.len:
      if msgBox(askRemove, "Remove", "Remove " & feeds[fsel].title & "?", ["&Remove", "Cancel"], miQuestion) == 1:
        feeds.delete(fsel)
        fsel = max(0, fsel - 1)
        keepFeeds()
    aboutBox(showAbout, "News Reader", DesktopVersion, ["News feeds: RSS and Atom.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()

# ==== Share Desktop ====================================================================================

proc vncRunning(): bool =
  for kind, path in walkDir("/proc"):
    if not path.extractFilename.allCharsInSet(Digits): continue
    try:
      let args = readFile(path / "cmdline").split('\0')
      if args.len > 0 and args[0].extractFilename == "x11vnc": return true
    except CatchableError: discard

proc myAddress(): string =
  try: $getPrimaryIPAddr()
  except CatchableError: "this device's address"

proc runShare*() =
  applyDesktopLook()
  openApp("Share Desktop", scaled(460), scaled(330), frame = wfSystem, userFrame = false, id = "share")
  showArt("share")
  followLook()
  var pass = desktopSettings().setting("vncPassword", "")
  var on = vncRunning()
  var job: Task
  let have = findExe("x11vnc").len > 0
  var showAbout = false
  while beginFrame():
    helpKeys("share")
    if job != nil and job.check(): job = nil
    menubar:
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("share")
        menuSeparator()
        if menuItem("&About Share Desktop..."): showAbout = true
    paragraph "Use this desktop from a computer on the same network: open a VNC viewer there " &
      "(TigerVNC, RealVNC, Remmina...) and connect to the address below."
    if not have:
      label("It needs x11vnc: Setup > System > Share Desktop.", color = color(170, 0, 0))
    form 0:
      field "Address:": label(myAddress() & ":5900", bold = true)
      field "&Password:": edit(pass, password = true)
      field "Now:": label(if on: "shared" else: "not shared", color = (if on: color(0, 128, 0) else: color(128, 128, 128)))
    label("Anyone with the password can see and use it while it is shared.", enabled = false)
    row:
      spring()
      if not on:
        if button("&Share", isDefault = true, enabled = have and pass.len >= 6):
          var s = desktopSettings()
          s["vncPassword"] = pass
          saveDesktopSettings(s)
          let pw = dataDir(SettingsName) / "vncpass"
          discard execShellCmd("x11vnc -storepasswd " & quoteShell(pass) & " " & quoteShell(pw) & " >/dev/null 2>&1")
          launch("x11vnc -display " & quoteShell(getEnv("DISPLAY", ":0")) & " -rfbauth " & quoteShell(pw) &
                 " -forever -shared -rfbport 5900 -noxdamage -quiet")
          on = true
      elif button("&Stop Sharing", isDefault = true):
        discard execShellCmd("pkill -x x11vnc")
        on = false
      if button("Close"): quitApp()
    if pass.len in 1 .. 5: label("A password of 6 letters or more.", enabled = false)
    aboutBox(showAbout, "Share Desktop", DesktopVersion,
             ["This desktop on a computer's screen (VNC).", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
