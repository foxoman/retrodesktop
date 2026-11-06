## Picture Viewer, PDF Reader and Camera.
##
## - Picture Viewer: a folder's pictures as thumbnails (the phone's camera
##   photos first), one picture as large as the window, the next and the one
##   before (the arrows, or the buttons), turning it, a slide show, setting
##   it as the desktop's wallpaper, sending it to Android (termux-share).
## - PDF Reader: Retro Nim UI's PDF view -- the pages, the zoom, going to a
##   page -- with the files read lately.
## - Camera: a photo with the phone's camera (Termux:API), then to the
##   viewer, Paintbrush or Android.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, tables, algorithm, json, times]
import retroui
import retroui/[background, pdfview]
import common, link, help, tasks

const PictureExts = [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".tif", ".tiff"]

proc share(path: string) =
  ## A file sent to Android's share sheet (WhatsApp, mail, Drive...).
  if findExe("termux-share").len > 0: launch("termux-share -a send " & quoteShell(path))
  else: launch(selfCommand("open") & " " & quoteShell(path.parentDir))

proc firstPictureFolder(): string =
  for d in [getHomeDir() / "storage/dcim/Camera", getHomeDir() / "storage/shared/DCIM/Camera",
            getHomeDir() / "storage/pictures", getHomeDir() / "Pictures", getHomeDir()]:
    if dirExists(d): return d
  getHomeDir()

proc rotated(b: Bitmap): Bitmap =
  ## `b` turned a quarter to the right.
  result = newBitmap(b.h, b.w)
  for y in 0 ..< b.h:
    for x in 0 ..< b.w:
      result.px[x * b.h + (b.h - 1 - y)] = b.px[y * b.w + x]

# ==== Picture Viewer ======================================================================================

proc runPictures*(args: seq[string]) =
  var folder = firstPictureFolder()
  var at = -1                    ## the picture shown (-1: the thumbnails)
  if args.len > 0:
    if dirExists(args[0]): folder = absolutePath(args[0])
    elif fileExists(args[0]): folder = absolutePath(args[0]).parentDir
  var files: seq[string]
  proc list() =
    files = @[]
    for kind, p in walkDir(folder):
      if kind in {pcFile, pcLinkToFile} and p.splitFile.ext.toLowerAscii in PictureExts: files.add p
    files.sort(proc (a, b: string): int = cmp(b, a))
  list()
  if args.len > 0 and fileExists(args[0]): at = files.find(absolutePath(args[0]))
  applyDesktopLook()
  openApp("Picture Viewer", scaled(720), scaled(520), frame = wfSystem, userFrame = false, id = "pictures")
  showArt("pictures")
  followLook()
  var thumbs: Table[string, Bitmap]
  var asked: Table[string, bool]
  var big: Bitmap
  var bigFor = ""
  var bigTicket = -1
  var turns = 0
  var sel = 0
  var marked: seq[bool]
  var slide = false
  var slideAt = 0
  var pickFolder = false
  var pickPath = folder
  var showAbout = false
  while beginFrame():
    helpKeys("pictures")
    for r in finished():
      if r.w > 0 and r.ticket == bigTicket:
        big = Bitmap(w: r.w, h: r.h, px: r.px)
        turns = 0
      elif r.w > 0:
        thumbs[r.path] = Bitmap(w: r.w, h: r.h, px: r.px)
    let showing = at >= 0 and at < files.len
    if showing and bigFor != files[at]:
      bigFor = files[at]
      big = nil
      bigTicket = pictureAsync(files[at], 2400, 2400, priority = 10)
    menubar:
      menu "&File":
        if menuItem("&Open Folder..."): pickFolder = true
        if menuItem("&Thumbnails", "Esc", enabled = showing): at = -1
        menuSeparator()
        if menuItem("Set as &Wallpaper", enabled = showing):
          var s = desktopSettings()
          s["wallpaper"] = files[at]
          saveDesktopSettings(s)
          retroCommand(RetroLookChanged)
          toast("The desktop's wallpaper now.", 2500)
        if menuItem("&Send to Android...", enabled = showing): share(files[at])
        if menuItem("Edit in &Paintbrush", enabled = showing and companion("retro-photo").len > 0):
          launch(quoteShell(companion("retro-photo")) & " " & quoteShell(files[at]))
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&View":
        if menuItem("&Next", "Right", enabled = showing): at = (at + 1) mod files.len
        if menuItem("&Previous", "Left", enabled = showing): at = (at - 1 + files.len) mod files.len
        if menuItem("&Turn Right", "R", enabled = showing and big != nil):
          big = rotated(big)
          inc turns
        if menuItem("&Slide Show", "F5", checked = slide, enabled = files.len > 0):
          slide = not slide
          if slide and at < 0: at = 0
          slideAt = ui.now
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("pictures")
        menuSeparator()
        if menuItem("&About Picture Viewer..."): showAbout = true
    if showing:
      if ui.key == KeyRight: at = (at + 1) mod files.len
      elif ui.key == KeyLeft: at = (at - 1 + files.len) mod files.len
      elif ui.key == KeyEsc:
        at = -1
        slide = false
      elif hotkeyPressed("R") and big != nil: big = rotated(big)
    if hotkeyPressed("F5") and files.len > 0:
      slide = not slide
      if slide and at < 0: at = 0
      slideAt = ui.now
    if slide and at >= 0:
      if ui.now - slideAt > 3500:
        slideAt = ui.now
        at = (at + 1) mod files.len
      wakeIn(3500)
    if showing:
      let area = canvas(-1, remainingH() - CtrlH - Gap)
      fill(area, color(0, 0, 0))
      if big != nil:
        let k = min(float(area.w) / float(big.w), float(area.h) / float(big.h))
        let w = int(float(big.w) * k)
        let h = int(float(big.h) * k)
        drawBitmap(rect(area.x + (area.w - w) div 2, area.y + (area.h - h) div 2, w, h), big)
      else:
        text(area.x + dp(10), area.y + dp(10), "Opening...", color(200, 200, 200))
      # (a tap on the left third: the one before; on the right third: the next)
      let hit = interact(idOf("picture"), area, focusable = false)
      if hit.clicked and files.len > 0:
        if ui.mx < area.x + area.w div 3: at = (at - 1 + files.len) mod files.len
        elif ui.mx > area.x + area.w * 2 div 3: at = (at + 1) mod files.len
      row:
        if button("< &Back"): at = (at - 1 + files.len) mod files.len
        if button("&Next >"): at = (at + 1) mod files.len
        if button("&Turn", enabled = big != nil): big = rotated(big)
        if button("&Thumbnails"):
          at = -1
          slide = false
        spring()
        label(files[at].extractFilename & "  (" & $(at + 1) & " of " & $files.len & ")")
    else:
      label(folder & "  --  " & $files.len & " pictures", enabled = false)
      if marked.len != files.len: marked = newSeq[bool](files.len)
      let px = devPx(96.0)
      let ev = iconView(files.len,
        proc (i: int): string = files[i].extractFilename,
        proc (i: int; r: Rect) =
          let f = files[i]
          let t = thumbs.getOrDefault(f)
          if t == nil:
            if not asked.hasKey(f):
              asked[f] = true
              discard pictureAsync(f, px, px)
            box(rect(r.x + 4, r.y + 4, r.w - 8, r.h - 8), ui.theme.line)
          else:
            let k = min(float(r.w) / float(t.w), float(r.h) / float(t.h))
            let w = int(float(t.w) * k)
            let h = int(float(t.h) * k)
            drawBitmap(rect(r.x + (r.w - w) div 2, r.y + (r.h - h) div 2, w, h), t),
        sel, marked, height = -1, tapActivates = fingers() or isMobile(), picSize = 96, tile = 116)
      if ev.activated and sel in 0 ..< files.len: at = sel
    if pickFolder:
      if filePicker(pickFolder, pickPath, fmFolder, title = "Pictures in"):
        folder = pickPath
        thumbs.clear()
        asked.clear()
        list()
        at = -1
    aboutBox(showAbout, "Picture Viewer", DesktopVersion,
             ["Your photos and pictures.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()

# ==== PDF Reader ==========================================================================================

proc runPdf*(args: seq[string]) =
  applyDesktopLook()
  openApp("PDF Reader", scaled(680), scaled(560), frame = wfSystem, userFrame = false, id = "pdf")
  showArt("pdf")
  followLook()
  var view: PdfView
  var path = ""
  var recent = desktopSettings().setting("pdfRecent", "").split('\n')
  var showOpen, showAbout, showGo: bool
  var pick = getHomeDir()
  var goTo = ""
  var problem = ""
  proc openIt(p: string) =
    try:
      if view != nil: closePdfView(view)
      view = openPdfView(p)
      path = p
      setTitle("PDF Reader - " & p.extractFilename)
      var r = @[p]
      for q in recent:
        if q != p and q.len > 0 and r.len < 8: r.add q
      recent = r
      var s = desktopSettings()
      s["pdfRecent"] = recent.join("\n")
      saveDesktopSettings(s)
    except CatchableError as e:
      problem = "Cannot open " & p.extractFilename & ": " & e.msg
  if args.len > 0 and fileExists(args[0]): openIt(absolutePath(args[0]))
  while beginFrame():
    helpKeys("pdf")
    menubar:
      menu "&File":
        if menuItem("&Open...", "Ctrl+O"): showOpen = true
        if recent.len > 0 and recent[0].len > 0:
          menuSeparator()
          for i, r in recent:
            if r.len > 0:
              withId(i):
                if menuItem("&" & $(i + 1) & " " & r.extractFilename.replace("&", "&&")): openIt(r)
        menuSeparator()
        if menuItem("&Send to Android...", enabled = path.len > 0): share(path)
        if menuItem("E&xit"): quitApp()
      menu "&View":
        if menuItem("Zoom &In", "+", enabled = view != nil): zoomIn(view)
        if menuItem("Zoom &Out", "-", enabled = view != nil): zoomOut(view)
        if menuItem("Page &Width", enabled = view != nil): fitWidth(view)
        menuSeparator()
        if menuItem("&Go to Page...", "Ctrl+G", enabled = view != nil): showGo = true
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("pdf")
        menuSeparator()
        if menuItem("&About PDF Reader..."): showAbout = true
    if hotkeyPressed("Ctrl+O"): showOpen = true
    if hotkeyPressed("Ctrl+G") and view != nil: showGo = true
    if view != nil:
      row:
        if button("<", enabled = view.page > 0): goToPage(view, view.page - 1)
        label("Page " & $(view.page + 1) & " of " & $view.count)
        if button(">", enabled = view.page + 1 < view.count): goToPage(view, view.page + 1)
        spring()
        if button("-"): zoomOut(view)
        label($zoomPercent(view) & " %")
        if button("+"): zoomIn(view)
      pdfView(view)
    else:
      label("File > Open (Ctrl+O) opens a PDF document.", enabled = false)
      if problem.len > 0: label(problem, color = color(170, 0, 0))
    if fileDialog(showOpen, pick, fmOpen, ["PDF Documents (*.pdf)", "All Files (*.*)"]): openIt(pick)
    if showGo:
      if inputBox(showGo, "Go to Page", "Page (1 to " & $view.count & "):", goTo) == 1:
        try: goToPage(view, clamp(parseInt(goTo.strip) - 1, 0, view.count - 1)) except ValueError: discard
    aboutBox(showAbout, "PDF Reader", DesktopVersion, ["PDF documents.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  if view != nil: closePdfView(view)
  closeApp()

# ==== Camera ==============================================================================================

proc runCamera*() =
  applyDesktopLook()
  openApp("Camera", scaled(520), scaled(480), frame = wfSystem, userFrame = false, id = "camera")
  showArt("camera")
  followLook()
  let folder = if dirExists(getHomeDir() / "storage/dcim"): getHomeDir() / "storage/dcim/Retro"
               else: getHomeDir() / "Pictures/Camera"
  var cams: seq[(string, string)]           ## id, facing
  var camAt = 0
  var info = if findExe("termux-camera-info").len > 0: run("termux-camera-info") else: nil
  var shot: Task
  var last = ""
  var pic: Bitmap
  var ticket = -1
  var said = if info == nil: "The camera needs Termux:API: Setup > System > Termux:API tools, " &
                             "and the Termux:API app." else: "Looking for the cameras..."
  var showAbout = false
  while beginFrame():
    helpKeys("camera")
    if info != nil and info.check():
      try:
        for c in parseJson(info.output):
          cams.add (c{"id"}.getStr, c{"facing"}.getStr)
        said = if cams.len > 0: "" else: "No camera was found."
      except CatchableError: said = "Android did not let Termux use the camera: allow it, and try again."
      info = nil
    if shot != nil and shot.check():
      if fileExists(last) and getFileSize(last) > 0:
        ticket = pictureAsync(last, 1600, 1600)
        said = "Saved: " & last
      else: said = "No photo came: allow the camera for Termux:API in Android's settings."
      shot = nil
    for r in finished():
      if r.ticket == ticket and r.w > 0: pic = Bitmap(w: r.w, h: r.h, px: r.px)
    if info != nil or shot != nil: wakeIn(200)
    menubar:
      menu "&Photo":
        if menuItem("&Open in Picture Viewer", enabled = last.len > 0):
          launch(selfCommand("pictures") & " " & quoteShell(last))
        if menuItem("Edit in &Paintbrush", enabled = last.len > 0 and companion("retro-photo").len > 0):
          launch(quoteShell(companion("retro-photo")) & " " & quoteShell(last))
        if menuItem("&Send to Android...", enabled = last.len > 0): share(last)
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("camera")
        menuSeparator()
        if menuItem("&About Camera..."): showAbout = true
    let area = canvas(-1, remainingH() - CtrlH - lineHeight() - 2 * Gap)
    fill(area, color(0, 0, 0))
    if pic != nil:
      let k = min(float(area.w) / float(pic.w), float(area.h) / float(pic.h))
      let w = int(float(pic.w) * k)
      let h = int(float(pic.h) * k)
      drawBitmap(rect(area.x + (area.w - w) div 2, area.y + (area.h - h) div 2, w, h), pic)
    label(if said.len > 0: said else: "Ready.", literal = true, enabled = said.len > 0)
    row:
      if cams.len > 1:
        var names: seq[string]
        for (id, facing) in cams: names.add (if facing == "front": "Front" elif facing == "back": "Back" else: "Camera " & id)
        combo(names, camAt, w = dp(110))
      spring()
      if button("&Take Photo", isDefault = true, enabled = cams.len > 0 and shot == nil):
        createDir(folder)
        last = folder / "IMG_" & now().format("yyyyMMdd'_'HHmmss") & ".jpg"
        said = "Taking the photo..."
        shot = run("termux-camera-photo -c " & cams[clamp(camAt, 0, cams.high)][0] & " " & quoteShell(last))
    aboutBox(showAbout, "Camera", DesktopVersion,
             ["Photos with the phone's camera (Termux:API).", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
