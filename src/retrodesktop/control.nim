## Control Panel: how the desktop and its programs look and behave -- the
## color scheme, the desktop (its color, pattern, wallpaper), the fonts and
## sizes, the windows (frames for fingers, opening maximized), the look
## other Linux programs are given, Android's settings for Termux. What is
## set here is kept, and every program of the desktop follows it at once.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, math, times, algorithm]
import retroui
import common, link, art, sounds, help, keyboard, syscheck, hijri

type Applet = enum
  apColor = "Color", apDesktop = "Desktop", apFonts = "Fonts", apWindows = "Windows",
  apDateTime = "Date/Time", apSound = "Sound", apSaver = "Screen Saver", apPrograms = "Linux Programs",
  apAndroid = "Android", apInternational = "International", apKeyboard = "Keyboard",
  apSystem = "System Check", apBackup = "Backup", apAbout = "About"

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
  reopenPrograms = true
  clock24 = true
  timeZone = ""
  saver = 0
  saverDelay = 5
  saverText = ""
  pauseIconic = false
  gpu = true
  soundsOn = true
  soundMap: seq[string]
  evSel = 0
  pickSound = false
  pickedSound = ""
  night = false
  nightFrom = 19
  nightTo = 7
  nightScheme = 0
  panelOn = true
  backKey = false
  fontFile = ""
  fontSel = 0
  pickFont = false
  newFont = ""
  language = 0
  saverLocked = false
  hijriOn = false
  hijriAdjust = 0
  saverPassword = ""
  showPassword = false
  pwOld, pwNew, pwAgain, pwSaid: string
  # the keyboard
  kbTab = 0
  layoutOn: seq[bool]            ## each of `Layouts`, chosen or not
  layoutSwitch = 0
  repeatDelay = 500
  repeatRate = 25
  tryTyping = ""
  shortcutKeys: seq[string]      ## each of `ShortcutNames`' keys ("" none)
  scSel = 0
  showShortcut = false
  scCtrl, scAlt, scShift, scWin: bool
  scKey = 0
  scCols: seq[Column]
  scOpen = false
  # System Check, Backup
  checksStarted = false
  backupSaid = ""
  pickBackup = false
  backupPath = ""
  askRestore = false

const
  Savers* = ["(None)", "Blank Screen", "Starfield", "Mystify", "Marquee"]
  Zones = ["", "UTC", "Asia/Muscat", "Asia/Dubai", "Asia/Riyadh", "Asia/Kolkata", "Asia/Tokyo",
           "Asia/Shanghai", "Europe/London", "Europe/Paris", "Europe/Berlin", "Europe/Moscow",
           "Africa/Cairo", "America/New_York", "America/Chicago", "America/Los_Angeles",
           "America/Sao_Paulo", "Australia/Sydney"]
  WallModes = ["fill", "center", "tile", "stretch"]
  AutoOnOff = ["auto", "on", "off"]
  Languages = ["en", "ar"]
  LanguageNames = ["English", "العربية (Arabic)"]

proc hourNames(): seq[string] =
  for h in 0 .. 23: result.add (if h < 10: "0" else: "") & $h & ":00"

proc myFonts(): seq[string] =
  ## The font files of yours (in the fonts folder), by name.
  let dir = fontsFolder()
  if dirExists(dir):
    for kind, p in walkDir(dir):
      if kind in {pcFile, pcLinkToFile} and p.splitFile.ext.toLowerAscii in [".ttf", ".otf"]: result.add p
  result.sort(proc (a, b: string): int = cmpIgnoreCase(a.extractFilename, b.extractFilename))

proc patternNames(): seq[string] =
  for (n, _) in Patterns: result.add n

proc readAll() =
  conf = desktopSettings()
  scheme = max(0, schemeNames().find(conf.setting("scheme", "Classic")))
  deskColor = hexColor(conf.setting("desktopColor", Teal), color(0, 128, 128))
  pattern = max(0, patternNames().find(conf.setting("pattern", "(None)")))
  wallpaper = conf.setting("wallpaper", "")
  wallMode = max(0, WallModes.find(conf.setting("wallpaperMode", "fill")))
  fontKind = max(0, ["sans", "serif", "mono", "file"].find(conf.setting("font", "sans")))
  fontFile = conf.setting("fontFile", "")
  night = conf.setting("night", "off") == "on"
  try:
    nightFrom = clamp(parseInt(conf.setting("nightFrom", "19")), 0, 23)
    nightTo = clamp(parseInt(conf.setting("nightTo", "7")), 0, 23)
  except ValueError: discard
  nightScheme = max(0, schemeNames().find(conf.setting("nightScheme", "Dark")))
  panelOn = conf.setting("panel", "on") != "off"
  backKey = conf.setting("backKey", "off") == "on"
  language = max(0, Languages.find(conf.setting("language", "en")))
  saverPassword = conf.setting("saverPassword", "")
  saverLocked = saverPassword.len > 0
  hijriOn = conf.setting("hijri", "off") == "on"
  try: hijriAdjust = clamp(parseInt(conf.setting("hijriAdjust", "0")), -2, 2) except ValueError: hijriAdjust = 0
  let lays = layoutsOf(conf)
  layoutOn = @[]
  for (k, _, _) in Layouts: layoutOn.add k in lays
  layoutSwitch = 0
  for i, (k, _) in Switches:
    if k == conf.setting("layoutSwitch", "Alt+Shift"): layoutSwitch = i
  try:
    repeatDelay = clamp(parseInt(conf.setting("repeatDelay", "500")), 150, 1000)
    repeatRate = clamp(parseInt(conf.setting("repeatRate", "25")), 2, 60)
  except ValueError: discard
  shortcutKeys = @[]
  for (action, _) in ShortcutNames:
    var keys = ""
    for (a, k) in DefaultShortcuts:
      if a == action: keys = k
    shortcutKeys.add conf.setting("key." & action, keys)
  try: textPct = parseInt(conf.setting("textScale", "100")) except ValueError: textPct = 100
  try: sizePct = parseInt(conf.setting("size", "100")) except ValueError: sizePct = 100
  touch = max(0, AutoOnOff.find(conf.setting("touch", "auto")))
  maxNew = max(0, AutoOnOff.find(conf.setting("maximizeNew", "auto")))
  linuxLook = conf.setting("linuxLook", "on") != "off"
  wakeLock = conf.setting("wakeLock", "on") != "off"
  startProgman = conf.setting("startProgman", "on") != "off"
  reopenPrograms = conf.setting("reopen", "on") != "off"
  clock24 = conf.setting("clock24", "on") != "off"
  timeZone = conf.setting("timezone", "")
  saver = max(0, Savers.find(conf.setting("saver", "(None)")))
  try: saverDelay = clamp(parseInt(conf.setting("saverDelay", "5")), 1, 120) except ValueError: saverDelay = 5
  saverText = conf.setting("saverText", DesktopName)
  pauseIconic = conf.setting("pauseIconic", "off") == "on"
  gpu = conf.setting("gpu", "auto") != "off"
  soundsOn = conf.setting("sounds", "on") != "off"
  soundMap = @[]
  for (key, _, _) in SoundEvents: soundMap.add soundFor(conf, key)

proc saveAll() =
  ## Keeps what the dialogs set; the desktop and its programs take it now.
  conf = desktopSettings()
  conf["scheme"] = schemeNames()[clamp(scheme, 0, schemeNames().high)]
  conf["desktopColor"] = hexOf(deskColor)
  conf["pattern"] = patternNames()[clamp(pattern, 0, Patterns.high)]
  conf["wallpaper"] = wallpaper
  conf["wallpaperMode"] = WallModes[clamp(wallMode, 0, WallModes.high)]
  if fontKind == 3 and fontFile.len == 0: fontKind = 0
  conf["font"] = ["sans", "serif", "mono", "file"][clamp(fontKind, 0, 3)]
  conf["fontFile"] = fontFile
  conf["night"] = (if night: "on" else: "off")
  conf["nightFrom"] = $nightFrom
  conf["nightTo"] = $nightTo
  conf["nightScheme"] = schemeNames()[clamp(nightScheme, 0, schemeNames().high)]
  conf["panel"] = (if panelOn: "on" else: "off")
  conf["backKey"] = (if backKey: "on" else: "off")
  conf["language"] = Languages[clamp(language, 0, Languages.high)]
  conf["saverPassword"] = (if saverLocked: saverPassword else: "")
  conf["hijri"] = (if hijriOn: "on" else: "off")
  conf["hijriAdjust"] = $hijriAdjust
  var lays: seq[string]
  for i, (k, _, _) in Layouts:
    if i < layoutOn.len and layoutOn[i]: lays.add k
  if lays.len == 0: lays = @["us"]
  conf["layouts"] = lays.join(",")
  conf["layoutSwitch"] = Switches[clamp(layoutSwitch, 0, Switches.high)][0]
  conf["repeatDelay"] = $repeatDelay
  conf["repeatRate"] = $repeatRate
  for i, (action, _) in ShortcutNames:
    if i < shortcutKeys.len: conf["key." & action] = shortcutKeys[i]
  if textPct != 100 or conf.hasKey("textScale"): conf["textScale"] = $textPct
  if sizePct != 100 or conf.hasKey("size"): conf["size"] = $sizePct
  conf["touch"] = AutoOnOff[clamp(touch, 0, 2)]
  conf["maximizeNew"] = AutoOnOff[clamp(maxNew, 0, 2)]
  conf["linuxLook"] = (if linuxLook: "on" else: "off")
  conf["wakeLock"] = (if wakeLock: "on" else: "off")
  conf["startProgman"] = (if startProgman: "on" else: "off")
  conf["reopen"] = (if reopenPrograms: "on" else: "off")
  conf["clock24"] = (if clock24: "on" else: "off")
  conf["timezone"] = timeZone.strip
  conf["saver"] = Savers[clamp(saver, 0, Savers.high)]
  conf["saverDelay"] = $saverDelay
  conf["saverText"] = saverText
  conf["pauseIconic"] = (if pauseIconic: "on" else: "off")
  conf["gpu"] = (if gpu: "auto" else: "off")
  conf["sounds"] = (if soundsOn: "on" else: "off")
  for i, (key, _, _) in SoundEvents:
    if i < soundMap.len: conf["sound." & key] = soundMap[i]
  saveDesktopSettings(conf)
  applyDesktopLook()
  retroCommand(RetroLookChanged)

proc artOf(a: Applet): string =
  case a
  of apColor: "paint"
  of apDesktop: "control"
  of apFonts: "fonts"
  of apWindows: "window"
  of apDateTime: "datetime"
  of apSound: "sound"
  of apSaver: "saver"
  of apPrograms: "app"
  of apAndroid: "android"
  of apInternational: "international"
  of apKeyboard: "keyboard"
  of apSystem: "syscheck"
  of apBackup: "backup"
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
  dialog(showDialog, "Color", 440):
    form 0:
      field "Color &Schemes:": combo(schemeNames(), scheme)
    schemePreview(schemeTheme(schemeNames()[clamp(scheme, 0, schemeNames().high)]))
    group "Night colors":
      checkbox("&Night colors (easier on the eyes in the dark)", night)
      form 0:
        field "Night &scheme:": combo(schemeNames(), nightScheme, enabled = night)
        field "&From:":
          row:
            combo(hourNames(), nightFrom, w = dp(90), enabled = night)
            label "To:"
            combo(hourNames(), nightTo, w = dp(90), enabled = night)
    if okCancel(): saveAll()

proc desktopDialog() =
  dialog(showDialog, "Desktop", 460):
    group "Pattern":
      form 0:
        field "&Desktop color:": colorWell(deskColor, "desk")
        field "&Name:": combo(patternNames(), pattern)
    group "Wallpaper":
      form 0:
        var wallIdx = if wallpaper.startsWith("@"): 1 + max(0, BuiltinWallpapers.find(wallpaper[1 .. ^1])) else: 0
        let choices = @["(a picture of yours)"] & @BuiltinWallpapers
        field "&Wallpaper:":
          if combo(choices, wallIdx):
            wallpaper = if wallIdx > 0: "@" & BuiltinWallpapers[wallIdx - 1] else: ""
        if not wallpaper.startsWith("@"):
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
    checkbox("&Reopen the programs that were open when the desktop ended", reopenPrograms)
    if okCancel(): saveAll()
  if pickWall:
    if filePicker(pickWall, wallpaper, fmOpen, ["*.png", "*.jpg", "*.jpeg", "*.bmp", "*.webp", "*.gif"],
                  "Wallpaper"):
      discard

proc fontsDialog() =
  dialog(showDialog, "Fonts", 480):
    let mine = myFonts()
    form 0:
      field "&Font:":
        row:
          radio("Sans", fontKind, 0)
          radio("Serif", fontKind, 1)
          radio("Mono", fontKind, 2)
          radio("A font of yours", fontKind, 3)
      if fontKind == 3 or mine.len > 0:
        field "&Your fonts:":
          var names: seq[string]
          for f in mine: names.add f.splitFile.name
          fontSel = max(0, mine.find(fontFile))
          if names.len == 0: label("(none yet: Add a Font...)", enabled = false)
          elif listbox(names, fontSel, rows = min(5, names.len)):
            fontFile = mine[fontSel]
            fontKind = 3
          if fontKind == 3 and fontFile.len == 0 and mine.len > 0: fontFile = mine[0]
        field "":
          row:
            if button("&Add a Font..."):
              newFont = ""
              pickFont = true
            if button("&Remove the Font", enabled = fontSel in 0 ..< mine.len):
              try: removeFile(mine[fontSel]) except CatchableError: discard
              if fontFile == mine[fontSel]:
                fontFile = ""
                if fontKind == 3: fontKind = 0
              launch("fc-cache -f " & quoteShell(fontsFolder()))
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
      "follow with Linux Programs on. Fonts you add (.ttf, .otf) go to " & fontsFolder() &
      ": every program can use them."
    if okCancel(): saveAll()
  if pickFont:
    if filePicker(pickFont, newFont, fmOpen, ["*.ttf", "*.otf", "*.TTF", "*.OTF"], "Add a Font"):
      try:
        createDir(fontsFolder())
        let dest = fontsFolder() / newFont.extractFilename
        copyFile(newFont, dest)
        fontFile = dest
        fontKind = 3
        launch("fc-cache -f " & quoteShell(fontsFolder()))
      except CatchableError: toast("The font could not be copied.", 3000)

proc windowsDialog() =
  dialog(showDialog, "Windows", 460):
    form 0:
      field "&Frames for fingers:": segmented(["Automatic", "On", "Off"], touch)
      field "Open &maximized:": segmented(["Automatic", "On", "Off"], maxNew)
    checkbox("&Pause programs while they are minimized", pauseIconic)
    checkbox("Show the &panel (the programs and the windows at the bottom)", panelOn)
    if inTermux():
      checkbox("Android's &Back key closes the window in front", backKey)
    paragraph "Frames for fingers: taller title bars and wider borders; an icon opens with one " &
      "tap. Automatic: on in Termux. Open maximized: new windows fill the screen. " &
      "Automatic: on a phone's screen in Termux. A paused program takes no CPU and no " &
      "battery until you bring it back -- music and downloads in it stop too. The panel: " &
      "a bar along the bottom with the Programs menu, a button for each window and the clock " &
      "(3.1 had none: it came with 95; here in 3.1's colors). Back: Termux:X11 uses it for its " &
      "keyboard unless its preferences give it to X."
    if okCancel(): saveAll()

proc dateTimeDialog() =
  dialog(showDialog, "Date & Time", 440):
    let t = now()
    form 0:
      field "Date:": label t.format("dddd, d MMMM yyyy")
      field "Time:": label t.format(if clock24: "HH:mm:ss" else: "h:mm:ss tt")
      field "&Clock:":
        row:
          var k = if clock24: 0 else: 1
          radio("&24 hours", k, 0)
          radio("&12 hours", k, 1)
          clock24 = k == 0
      field "Time &zone:": comboEdit(timeZone, Zones, w = dp(220))
      field "":
        checkbox("Show the &Hijri date too (Clock, Calendar)", hijriOn)
      field "&Adjust:":
        row([-1, 150]):
          slider(hijriAdjust, -2, 2, ticks = 5, enabled = hijriOn)
          label(if hijriOn: hijriText(t, hijriAdjust, language == 1) else: "", literal = true)
    paragraph "The date and the time are Android's (or the computer's): Settings > " &
      "System > Date & time sets them. The time zone here is for the desktop's programs " &
      "(TZ); empty: the system's own. The Hijri date is counted (the tabular calendar); " &
      "Adjust moves it a day or two where the month began otherwise by the moon's sighting."
    wakeIn(1000)
    if okCancel(): saveAll()

proc soundDialog() =
  dialog(showDialog, "Sound", 540):
    row:
      col(240):
        label "&Events:"
        var names: seq[string]
        for e in SoundEvents: names.add e[1]
        listbox(names, evSel, rows = 9)
      col:
        label "&Files:"
        evSel = clamp(evSel, 0, soundMap.high)
        let cur = soundMap[evSel]
        var shown = @Chimes
        var fsel = Chimes.find(cur)
        if fsel < 0:
          shown.add cur.extractFilename
          fsel = shown.high
        if listbox(shown, fsel, rows = 9) and fsel < Chimes.len: soundMap[evSel] = Chimes[fsel]
    row:
      if button("&Test"):
        let what = soundMap[evSel]
        playFile(if what in Chimes: chimeFile(what) else: what)
      if button("&Browse..."): pickSound = true
      spring()
      checkbox("&Enable system sounds", soundsOn)
    paragraph "The chimes are the desktop's own. Sound needs PulseAudio (Setup > " &
      "Multimedia > Sound: the desktop starts it) or Termux:API."
    if okCancel(): saveAll()
  if pickSound:
    if filePicker(pickSound, pickedSound, fmOpen, ["*.wav", "*.ogg", "*.mp3", "*.flac"], "Sound"):
      soundMap[evSel] = pickedSound

proc saverDialog() =
  dialog(showDialog, "Screen Saver", 440):
    form 0:
      field "&Name:":
        row:
          combo(Savers, saver)
          if button("&Test", enabled = saver > 0):
            saveAll()
            launch(selfCommand("saver") & " now")
      field "&Delay:":
        row([-1, 80]):
          slider(saverDelay, 1, 60, ticks = 6)
          label $saverDelay & " minutes"
      if Savers[clamp(saver, 0, Savers.high)] == "Marquee":
        field "Te&xt:": edit saverText
      field "":
        row:
          checkbox("&Password protected", saverLocked)
          if button("&Set Password...", enabled = saverLocked):
            pwOld = ""
            pwNew = ""
            pwAgain = ""
            pwSaid = ""
            showPassword = true
    paragraph "It starts when nothing was typed or touched for the delay; a key, a click " &
      "or a touch ends it (with a password, once it is typed). Win+L starts it now. On a " &
      "phone it takes the battery while it runs: Blank Screen takes least. The password " &
      "locks this desktop, not Android."
    if okCancel():
      if saverLocked and saverPassword.len == 0: saverLocked = false
      saveAll()
  if showPassword:
    dialog(showPassword, "Change Password", 380):
      form 0:
        if saverPassword.len > 0:
          field "&Old Password:": edit(pwOld, password = true)
        field "&New Password:": edit(pwNew, password = true)
        field "&Retype New Password:": edit(pwAgain, password = true)
      if pwSaid.len > 0: label(pwSaid, color = color(170, 0, 0))
      if okCancel():
        if saverPassword.len > 0 and not passwordIs(saverPassword, pwOld):
          pwSaid = "The old password is not right."
          showPassword = true
        elif pwNew != pwAgain:
          pwSaid = "The new password and its retyping differ."
          showPassword = true
        elif pwNew.len == 0:
          saverPassword = ""
          saverLocked = false
        else:
          saverPassword = newPasswordHash(pwNew)
          saverLocked = true

proc programsDialog() =
  dialog(showDialog, "Linux Programs", 480):
    checkbox("&Give other programs the desktop's look", linuxLook)
    checkbox("Use Android's &GPU for 3D (VirGL, once Setup > System > 3D graphics is installed)", gpu)
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

proc internationalDialog() =
  dialog(showDialog, "International", 440):
    form 0:
      field "&Language:": combo(LanguageNames, language)
    paragraph "The desktop's own programs, menus and dialogs in the language chosen (Arabic: " &
      "right to left). Other programs keep their own language."
    if okCancel(): saveAll()

const KeyChoices = ["(none)", "the Windows key alone", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
                    "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
                    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "F1", "F2", "F3", "F4", "F5",
                    "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Left", "Right", "Up", "Down",
                    "Esc", "Tab", "Space", "Enter", "Home", "End", "Delete", "Insert", "Print"]

proc keyboardDialog() =
  dialog(showDialog, "Keyboard", 520):
    tabs(kbTab, ["&Layouts", "&Shortcuts", "&Repeat"]):
      case kbTab
      of 0:
        label("Type in these (the first at the start):")
        beginPanel(dp(150), key = "layouts")
        for i, (_, name, mark) in Layouts:
          withId(i):
            checkbox(name & "   (" & mark & ")", layoutOn[i])
        endPanel()
        form 0:
          field "S&witch with:":
            var names: seq[string]
            for (k, _) in Switches: names.add k
            combo(names, layoutSwitch)
        paragraph "The panel shows the one typing now (a click on it goes to the next). " &
          (if findExe("setxkbmap").len == 0: "More than one needs setxkbmap: Setup > System > Keyboard layouts. "
           else: "") &
          "In Termux:X11's Keyboard preferences turn on \"Prefer scancodes when possible\"."
      of 1:
        var rows: seq[seq[string]]
        for i, (_, what) in ShortcutNames:
          rows.add @[(if shortcutKeys[i].len > 0: shortcutKeys[i] else: "(none)"), what]
        if scCols.len == 0: scCols = @[column("Keys", 130), column("Does", 330)]
        let ev = grid(scCols, rows, scSel, height = 8)
        if ev.activated: scOpen = true
        row:
          if (button("&Change...", enabled = scSel in 0 ..< shortcutKeys.len) or scOpen) and
             scSel in 0 ..< shortcutKeys.len:
            scOpen = false
            let parts = shortcutKeys[scSel].split('+')
            scCtrl = "Ctrl" in parts
            scAlt = "Alt" in parts
            scShift = "Shift" in parts
            scWin = "Win" in parts
            scKey = 0
            if shortcutKeys[scSel] == "Win": scKey = 1
            elif parts.len > 0: scKey = max(0, KeyChoices.find(parts[^1]))
            showShortcut = true
          if button("Reset &All"):
            for i, (action, _) in ShortcutNames:
              for (a, k) in DefaultShortcuts:
                if a == action: shortcutKeys[i] = k
        paragraph "Alt+Tab, Alt+F4, Ctrl+Esc and Alt+Esc are always the desktop's. So that the " &
          "Windows key and Alt+Tab reach it and not Android: Termux:X11's Keyboard preferences > " &
          "\"Enable Accessibility service for intercepting system shortcuts manually\"."
      else:
        form 0:
          field "&Delay:":
            row([-1, 90]):
              slider(repeatDelay, 150, 1000, ticks = 6)
              label $repeatDelay & " ms"
          field "&Rate:":
            row([-1, 90]):
              slider(repeatRate, 2, 60, ticks = 6)
              label $repeatRate & " a second"
          field "&Try it:": edit(tryTyping)
        paragraph "How long a key held waits before it repeats, and how fast it repeats then " &
          "(the try takes them after OK)."
    if okCancel(): saveAll()
  if showShortcut:
    dialog(showShortcut, "Change the Keys", 380):
      label(ShortcutNames[clamp(scSel, 0, ShortcutNames.high)][1], bold = true)
      row:
        checkbox("&Ctrl", scCtrl)
        checkbox("&Alt", scAlt)
        checkbox("&Shift", scShift)
        checkbox("&Win", scWin)
      form 0:
        field "&Key:": combo(KeyChoices, scKey)
      if okCancel():
        var keys = ""
        if scKey == 1: keys = "Win"
        elif scKey > 1:
          var parts: seq[string]
          if scCtrl: parts.add "Ctrl"
          if scAlt: parts.add "Alt"
          if scShift: parts.add "Shift"
          if scWin: parts.add "Win"
          parts.add KeyChoices[scKey]
          keys = parts.join("+")
        if scSel in 0 ..< shortcutKeys.len: shortcutKeys[scSel] = keys

proc systemDialog() =
  if not checksStarted:
    checksStarted = true
    startChecks()
  if stillChecking(): wakeIn(300)
  dialog(showDialog, "System Check", 560):
    beginPanel(max(dp(120), min(dp(330), ui.h - dp(140))), key = "checks")
    for i, c in checks():
      withId(i):
        row([24, -1, 0]):
          let (mark, ink) = case c.state
            of csOk: ("✔", color(0, 128, 0))
            of csWarn: ("!", color(176, 112, 0))
            of csMissing: ("✖", color(176, 0, 0))
            of csChecking: ("…", color(128, 128, 128))
          label(mark, bold = true, color = ink)
          col:
            label(c.name, bold = true)
            paragraph c.detail
          if c.install.len > 0:
            if button("&Install..."): launch(selfCommand("setup") & " " & quoteShell(c.install))
    endPanel()
    row:
      if button("&Check Again"): startChecks()
      spring()
      if button("OK", isDefault = true):
        showDialog = false
        checksStarted = false
  if not showDialog: checksStarted = false

proc backupDialog() =
  dialog(showDialog, "Backup", 480):
    paragraph "A backup keeps the desktop's settings, Program Manager's groups, the desktop's " &
      "icons, the programs' settings (never their passwords) and your fonts in one .zip, " &
      "in " & backupFolder() & ". Restore puts one back: on a new phone, or after Termux " &
      "was installed again."
    if backupSaid.len > 0: label(backupSaid, literal = true)
    row:
      if button("&Make a Backup", isDefault = true):
        try: backupSaid = "Made: " & makeBackup()
        except CatchableError as e: backupSaid = "Not made: " & e.msg
      if button("&Restore..."):
        backupPath = backupFolder()
        pickBackup = true
      spring()
      if button("Close"):
        showDialog = false
        backupSaid = ""
  if pickBackup:
    if filePicker(pickBackup, backupPath, fmOpen, ["*.zip"], "Restore a Backup"): askRestore = true
  if askRestore:
    if msgBox(askRestore, "Restore", "Put back the settings in " & backupPath.extractFilename &
              "? The ones here now are replaced.", ["&Restore", "Cancel"], miQuestion) == 1:
      try:
        let n = restoreBackup(backupPath)
        backupSaid = $n & " files put back. Programs open now take them when they start again."
        readAll()
        saveAll()
      except CatchableError as e: backupSaid = "Not restored: " & e.msg

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
  openApp("Control Panel", scaled(520), scaled(400), frame = wfSystem, userFrame = false, id = "control")
  showArt("control")
  followLook()
  applets = @[apColor, apDesktop, apFonts, apWindows, apDateTime, apSound, apSaver, apPrograms]
  if inTermux(): applets.add apAndroid
  applets.add apInternational
  applets.add apKeyboard
  applets.add apSystem
  applets.add apBackup
  applets.add apAbout
  marked = newSeq[bool](applets.len)
  var showAboutCp = false
  while beginFrame():
    helpKeys("control")
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
        if menuItem("&Help Topics", "F1"): openHelp("control")
        menuSeparator()
        if menuItem("&About Control Panel..."): showAboutCp = true
    let px = devPx(32.0)
    let ev = iconView(applets.len,
      proc (i: int): string = tr($applets[i]),
      proc (i: int; r: Rect) =
        let s = dp(32)
        drawBitmap(rect(r.x + (r.w - s) div 2, r.y + (r.h - s) div 2, s, s),
                   appIcon(artOf(applets[i]), px)),
      sel, marked, height = -1, tapActivates = fingers() or isMobile())
    if ev.activated and sel in 0 ..< applets.len:
      opened = sel
      readAll()
      showDialog = true
    statusbar(tr(if sel in 0 ..< applets.len:
                (case applets[sel]
                 of apColor: "The colors of the windows, by day and by night"
                 of apDesktop: "The desktop's color, pattern and wallpaper"
                 of apFonts: "The font (one of yours too), the text size, the size of everything"
                 of apWindows: "Frames for fingers, the panel, windows that open maximized"
                 of apDateTime: "The clock's hours, the time zone, the Hijri date"
                 of apSound: "The sounds of the desktop's events"
                 of apSaver: "A screen saver, after a while with nothing done"
                 of apPrograms: "The look GTK, Qt and other programs are given"
                 of apAndroid: "Keeping the desktop running on Android"
                 of apInternational: "The language of the desktop's programs"
                 of apKeyboard: "The layouts (English, Arabic...), the shortcuts, how keys repeat"
                 of apSystem: "What the desktop's programs need, and whether it is here"
                 of apBackup: "The settings in one file, and back"
                 of apAbout: "About " & DesktopName)
              else: ""))
    if showDialog and opened in 0 ..< applets.len:
      case applets[opened]
      of apColor: colorDialog()
      of apDesktop: desktopDialog()
      of apFonts: fontsDialog()
      of apWindows: windowsDialog()
      of apDateTime: dateTimeDialog()
      of apSound: soundDialog()
      of apSaver: saverDialog()
      of apPrograms: programsDialog()
      of apAndroid: androidDialog()
      of apInternational: internationalDialog()
      of apKeyboard: keyboardDialog()
      of apSystem: systemDialog()
      of apBackup: backupDialog()
      of apAbout: aboutDialog()
    aboutBox(showAboutCp, "Control Panel", DesktopVersion)
    endFrame()
    appFrameDone()
  closeApp()
