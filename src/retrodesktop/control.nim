## Control Panel: how the desktop and its programs look and behave -- the
## color scheme, the desktop (its color, pattern, wallpaper), the fonts and
## sizes, the windows (frames for fingers, opening maximized), the look
## other Linux programs are given, Android's settings for Termux. What is
## set here is kept, and every program of the desktop follows it at once.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, math]
import retroui
import common, link, art

type Applet = enum
  apColor = "Color", apDesktop = "Desktop", apFonts = "Fonts", apWindows = "Windows",
  apPrograms = "Linux Programs", apAndroid = "Android", apAbout = "About"

var
  conf: Settings
  applets: seq[Applet]
  sel = 0
  marked: seq[bool]
  opened = -1
  showDialog = false
  # what the dialogs edit
  scheme = 0
  deskColor: Color
  pattern = 0
  wallpaper = ""
  wallMode = 0
  pickWall = false
  fontKind = 0
  textPct = 100
  sizePct = 100
  touch = 0
  maxNew = 0
  linuxLook = true
  wakeLock = true
  startProgman = true

const
  WallModes = ["fill", "center", "tile", "stretch"]
  AutoOnOff = ["auto", "on", "off"]

proc schemeNames(): seq[string] =
  for t in builtinThemes: result.add t.name

proc patternNames(): seq[string] =
  for (n, _) in Patterns: result.add n

proc readAll() =
  conf = desktopSettings()
  scheme = max(0, schemeNames().find(conf.setting("scheme", "Classic")))
  deskColor = hexColor(conf.setting("desktopColor", Teal), color(0, 128, 128))
  pattern = max(0, patternNames().find(conf.setting("pattern", "(None)")))
  wallpaper = conf.setting("wallpaper", "")
  wallMode = max(0, WallModes.find(conf.setting("wallpaperMode", "fill")))
  fontKind = max(0, ["sans", "serif", "mono"].find(conf.setting("font", "sans")))
  try: textPct = parseInt(conf.setting("textScale", "100")) except ValueError: textPct = 100
  try: sizePct = parseInt(conf.setting("size", "100")) except ValueError: sizePct = 100
  touch = max(0, AutoOnOff.find(conf.setting("touch", "auto")))
  maxNew = max(0, AutoOnOff.find(conf.setting("maximizeNew", "auto")))
  linuxLook = conf.setting("linuxLook", "on") != "off"
  wakeLock = conf.setting("wakeLock", "on") != "off"
  startProgman = conf.setting("startProgman", "on") != "off"

proc saveAll() =
  ## Keeps what the dialogs set; the desktop and its programs take it now.
  conf = desktopSettings()
  conf["scheme"] = schemeNames()[clamp(scheme, 0, builtinThemes.high)]
  conf["desktopColor"] = hexOf(deskColor)
  conf["pattern"] = patternNames()[clamp(pattern, 0, Patterns.high)]
  conf["wallpaper"] = wallpaper
  conf["wallpaperMode"] = WallModes[clamp(wallMode, 0, WallModes.high)]
  conf["font"] = ["sans", "serif", "mono"][clamp(fontKind, 0, 2)]
  if textPct != 100 or conf.hasKey("textScale"): conf["textScale"] = $textPct
  if sizePct != 100 or conf.hasKey("size"): conf["size"] = $sizePct
  conf["touch"] = AutoOnOff[clamp(touch, 0, 2)]
  conf["maximizeNew"] = AutoOnOff[clamp(maxNew, 0, 2)]
  conf["linuxLook"] = (if linuxLook: "on" else: "off")
  conf["wakeLock"] = (if wakeLock: "on" else: "off")
  conf["startProgman"] = (if startProgman: "on" else: "off")
  saveDesktopSettings(conf)
  applyDesktopLook()
  retroCommand(RetroLookChanged)

proc artOf(a: Applet): string =
  case a
  of apColor: "paint"
  of apDesktop: "control"
  of apFonts: "readme"
  of apWindows: "window"
  of apPrograms: "app"
  of apAndroid: "terminal"
  of apAbout: "logo"

proc okCancel(): bool =
  ## OK and Cancel at the bottom of a dialog: true for OK.
  row:
    spring()
    if button("OK", isDefault = true):
      showDialog = false
      result = true
    if button("Cancel"):
      showDialog = false
      readAll()

proc schemePreview(t: Theme) =
  ## A little window in the scheme: its title bar, menu, text and a button.
  let r = canvas(-1, dp(120))
  fill(r, t.face)
  box(r, t.frame)
  let win = rect(r.x + dp(10), r.y + dp(10), r.w - dp(20), r.h - dp(20))
  fill(win, t.window)
  box(win, t.frame)
  let title = rect(win.x + 1, win.y + 1, win.w - 2, lineHeight() + dp(4))
  fill(title, t.select)
  text(title.x + dp(6), title.y + dp(2), "Active Window", t.selectText, true)
  text(win.x + dp(8), title.y + title.h + dp(6), "Window Text", t.text)
  text(win.x + dp(8), title.y + title.h + dp(6) + lineHeight() + dp(2), "Disabled", t.gray)
  let b = rect(win.x + win.w - dp(90), win.y + win.h - dp(30), dp(80), dp(22))
  fill(b, t.face)
  box(b, t.frame)
  text(b.x + (b.w - textWidth("OK")) div 2, b.y + (b.h - lineHeight()) div 2, "OK", t.text)

proc colorDialog() =
  dialog(showDialog, "Color", 420):
    form 0:
      field "Color &Schemes:": combo(schemeNames(), scheme)
    schemePreview(builtinThemes[clamp(scheme, 0, builtinThemes.high)].theme)
    if okCancel(): saveAll()

proc desktopDialog() =
  dialog(showDialog, "Desktop", 460):
    group "Pattern":
      form 0:
        field "&Desktop color:": colorWell(deskColor, "desk")
        field "&Name:": combo(patternNames(), pattern)
    group "Wallpaper":
      form 0:
        field "&File:":
          row([-1, 0, 0]):
            edit wallpaper
            if button("&Browse..."): pickWall = true
            if button("&None"): wallpaper = ""
        field "":
          row:
            for i, m in ["&Fill", "&Center", "&Tile", "&Stretch"]:
              radio(m, wallMode, i)
    if inTermux():
      group "Termux":
        checkbox("&Keep Termux awake while the desktop runs (termux-wake-lock)", wakeLock)
    checkbox("Start &Program Manager with the desktop", startProgman)
    if okCancel(): saveAll()
  if pickWall:
    if filePicker(pickWall, wallpaper, fmOpen, ["*.png", "*.jpg", "*.jpeg", "*.bmp", "*.webp", "*.gif"],
                  "Wallpaper"):
      discard

proc fontsDialog() =
  dialog(showDialog, "Fonts", 440):
    form 0:
      field "&Font:":
        row:
          radio("Sans", fontKind, 0)
          radio("Serif", fontKind, 1)
          radio("Mono", fontKind, 2)
      field "&Text size:":
        row([-1, 60]):
          slider(textPct, 75, 200, ticks = 5)
          label $textPct & " %"
      field "&Everything:":
        row([-1, 60]):
          slider(sizePct, 75, 250, ticks = 7)
          label $sizePct & " %"
    paragraph "\"Everything\" is the size of the windows' frames, buttons and text together: " &
      "100 % is the screen's own (from its density). Programs that are not the desktop's " &
      "follow with Linux Programs on."
    if okCancel(): saveAll()

proc windowsDialog() =
  dialog(showDialog, "Windows", 460):
    form 0:
      field "&Frames for fingers:": segmented(["Automatic", "On", "Off"], touch)
      field "Open &maximized:": segmented(["Automatic", "On", "Off"], maxNew)
    paragraph "Frames for fingers: taller title bars and wider borders; an icon opens with one " &
      "tap. Automatic: on in Termux. Open maximized: new windows fill the screen. " &
      "Automatic: on a phone's screen in Termux."
    if okCancel(): saveAll()

proc programsDialog() =
  dialog(showDialog, "Linux Programs", 480):
    checkbox("&Give other programs the desktop's look", linuxLook)
    paragraph "GTK programs (and Chromium, Electron, Firefox) take the color scheme as the " &
      "\"Retro31\" theme, the desktop's fonts (FreeSans, FreeSerif, FreeMono) and its size; " &
      "Qt and older X programs take the size and the fonts. It is done through XSETTINGS, " &
      "the X resources, fontconfig and ~/.config/gtk-3.0/settings.ini (left alone when it " &
      "is your own). Programs already open follow when they can; others when started again."
    if okCancel(): saveAll()

proc androidDialog() =
  dialog(showDialog, "Android", 500):
    checkbox("&Keep Termux awake while the desktop runs (termux-wake-lock)", wakeLock)
    paragraph "So Android lets the desktop and its programs run while you use other apps:"
    paragraph "1. Settings > Apps > Termux > Battery: Unrestricted (the same for Termux:X11)."
    paragraph "2. Android 12 and later stop programs started from Termux beyond a few " &
      "(the phantom process killer): Developer options > \"Disable child process " &
      "restrictions\" (Android 14), or from a computer: adb shell \"settings put global " &
      "settings_enable_monitor_phantom_procs false\"."
    paragraph "3. In Termux:X11's preferences: Display resolution mode native; Touchscreen " &
      "input mode Direct touch (tap where you point) or Trackpad; the additional keyboard " &
      "for Esc, Ctrl, Alt and Tab; Fullscreen on."
    if okCancel(): saveAll()

proc aboutDialog() =
  dialog(showDialog, "About " & DesktopName, 440):
    row:
      let s = dp(48)
      let r = canvas(s + dp(8), s)
      drawBitmap(rect(r.x, r.y, s, s), appIcon("logo", devPx(48.0)))
      col:
        heading DesktopName & " " & DesktopVersion
        label "A Windows 3.1 style desktop for Linux and Termux"
    paragraph "Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net"
    paragraph "Made with Retro Nim UI " & RetroVersion & "."
    label "Memory: " & memoryReport(false)
    row:
      spring()
      if button("OK", isDefault = true): showDialog = false

proc runControl*() =
  readAll()
  applyDesktopLook()
  openApp("Control Panel", scaled(460), scaled(300), frame = wfSystem, userFrame = false, id = "control")
  followLook()
  applets = @[apColor, apDesktop, apFonts, apWindows, apPrograms]
  if inTermux(): applets.add apAndroid
  applets.add apAbout
  marked = newSeq[bool](applets.len)
  var showAboutCp = false
  while beginFrame():
    menubar:
      menu "&Settings":
        for i, a in applets:
          withId(i):
            if menuItem("&" & $a & "..."):
              opened = i
              readAll()
              showDialog = true
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&About Control Panel..."): showAboutCp = true
    let px = devPx(32.0)
    let ev = iconView(applets.len,
      proc (i: int): string = $applets[i],
      proc (i: int; r: Rect) =
        let s = dp(32)
        drawBitmap(rect(r.x + (r.w - s) div 2, r.y + (r.h - s) div 2, s, s),
                   appIcon(artOf(applets[i]), px)),
      sel, marked, height = -1, tapActivates = fingers() or isMobile())
    if ev.activated and sel in 0 ..< applets.len:
      opened = sel
      readAll()
      showDialog = true
    statusbar(if sel in 0 ..< applets.len:
                (case applets[sel]
                 of apColor: "The colors of the windows"
                 of apDesktop: "The desktop's color, pattern and wallpaper"
                 of apFonts: "The font, the text size, the size of everything"
                 of apWindows: "Frames for fingers; windows that open maximized"
                 of apPrograms: "The look GTK, Qt and other programs are given"
                 of apAndroid: "Keeping the desktop running on Android"
                 of apAbout: "About " & DesktopName)
              else: "")
    if showDialog and opened in 0 ..< applets.len:
      case applets[opened]
      of apColor: colorDialog()
      of apDesktop: desktopDialog()
      of apFonts: fontsDialog()
      of apWindows: windowsDialog()
      of apPrograms: programsDialog()
      of apAndroid: androidDialog()
      of apAbout: aboutDialog()
    aboutBox(showAboutCp, "Control Panel", DesktopVersion)
    endFrame()
    appFrameDone()
  closeApp()
