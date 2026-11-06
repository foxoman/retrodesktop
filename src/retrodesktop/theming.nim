## The look the desktop gives other programs: the same fonts (GNU FreeFont),
## the same size (the screen's density), the same colors (a "Retro31" GTK
## theme made from the color scheme) -- through what their toolkits read:
## XSETTINGS (GTK, Chromium, Electron), X resources (Xft.dpi for Qt and the
## rest, old X programs' colors), fontconfig, GTK's settings file.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, math]
import retroui
import retroui/[typeset, ttf]
import xlib, common

const
  ThemeName* = "Retro31"
  Marker = "# made by Retro Desktop (it rewrites this file; remove this line to keep your own)"

proc density(): float =
  ## The screen's own scale (2.0 on a 320 dpi tablet), without the size the
  ## user chose in Control Panel: the screen's pixels per design pixel over
  ## that size.
  max(0.25, devScale() * 100 / float(max(1, uiScale())))

proc fontPoints*(): int =
  ## The UI's text size in points at 96 dpi -- the text size and the size of
  ## everything the user chose in it (the screen's density comes on top,
  ## from the dpi). (`textSize` is in logical pixels: `pxScale` of the
  ## screen's each.)
  max(7, int(round(textSize() * float(max(1, pxScale)) / density() * 72 / 96)))

proc dpiNow*(): int =
  ## The dots per inch programs are told: the screen's density (96 at 100 %).
  ## The user's size is not in it: the desktop's own programs read it as
  ## the screen's and add that size themselves; other programs get it in
  ## the font size.
  max(96, int(round(96 * density())))

# ---- fonts ------------------------------------------------------------------------------------------

proc installFonts*() =
  ## GNU FreeFont for every program (in the user's fonts folder) and
  ## fontconfig told that sans-serif, serif and monospace are FreeSans,
  ## FreeSerif and FreeMono.
  let dir = getHomeDir() / ".local" / "share" / "fonts" / "retro-desktop"
  try:
    createDir(dir)
    const files = ["FreeSans", "FreeSansBold", "FreeSansOblique", "FreeSansBoldOblique",
                   "FreeSerif", "FreeSerifBold", "FreeSerifItalic", "FreeSerifBoldItalic",
                   "FreeMono", "FreeMonoBold", "FreeMonoOblique", "FreeMonoBoldOblique"]
    for id in fSans .. fMonoBoldItalic:
      let p = dir / files[ord(id) - ord(fSans)] & ".ttf"
      if not fileExists(p):
        let data = face(id).fontData
        if data.len > 0: writeFile(p, data)
    let conf = getHomeDir() / ".config" / "fontconfig" / "conf.d"
    createDir(conf)
    var x = "<?xml version=\"1.0\"?>\n<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">\n" &
            "<!-- made by Retro Desktop -->\n<fontconfig>\n" &
            "  <dir>" & dir & "</dir>\n"
    for (generic, family) in [("sans-serif", "FreeSans"), ("serif", "FreeSerif"),
                              ("monospace", "FreeMono"), ("sans", "FreeSans")]:
      x.add "  <alias binding=\"strong\"><family>" & generic & "</family><prefer><family>" &
            family & "</family></prefer></alias>\n"
    x.add "  <match target=\"font\"><edit name=\"antialias\" mode=\"assign\"><bool>true</bool></edit>" &
          "<edit name=\"hintstyle\" mode=\"assign\"><const>hintslight</const></edit>" &
          "<edit name=\"rgba\" mode=\"assign\"><const>none</const></edit></match>\n</fontconfig>\n"
    writeFile(conf / "60-retro-desktop.conf", x)
  except CatchableError: discard

# ---- the GTK theme ----------------------------------------------------------------------------------

proc gtkCss*(t: Theme): string =
  ## A GTK 3 theme in the scheme's colors: Adwaita's, with the 3.1 look over
  ## it (square raised buttons, sunken fields, navy selection).
  let bg = hexOf(t.face)
  let fg = hexOf(t.text)
  let light = hexOf(t.light)
  let shadow = hexOf(t.shadow)
  let frame = hexOf(t.frame)
  let field = hexOf(t.field)
  let fieldText = hexOf(t.fieldText)
  let sel = hexOf(t.select)
  let selText = hexOf(t.selectText)
  let scroll = hexOf(t.scroll)
  result = "/* " & ThemeName & ": made by Retro Desktop from its color scheme */\n" &
    "@import url(\"resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained.css\");\n" &
    "@define-color theme_bg_color " & bg & ";\n@define-color theme_fg_color " & fg & ";\n" &
    "@define-color theme_base_color " & field & ";\n@define-color theme_text_color " & fieldText & ";\n" &
    "@define-color theme_selected_bg_color " & sel & ";\n@define-color theme_selected_fg_color " & selText & ";\n" &
    "* { border-radius: 0; -gtk-outline-radius: 0; }\n" &
    "button, entry, spinbutton, check, radio:not(:checked), combobox button, menu, menuitem, popover, " &
      "tooltip, notebook > header tab, scrollbar slider, frame > border, list, treeview, textview, " &
      "progressbar trough, progressbar progress, scale trough, scale slider, switch, switch slider " &
      "{ border-radius: 0; }\n" &
    "entry:focus, spinbutton:focus { border-color: " & shadow & " " & light & " " & light & " " &
      shadow & "; box-shadow: inset 1px 1px " & frame & "; outline: none; }\n" &
    "dialog .dialog-action-area button, messagedialog .dialog-action-area button, " &
      "messagedialog.csd .dialog-action-area button, .dialog-action-box button { border-radius: 0; }\n" &
    "button:focus { outline: 1px dotted " & frame & "; outline-offset: -4px; }\n" &
    "window, .background, dialog, messagedialog, popover, box, grid { background-color: " & bg &
      "; color: " & fg & "; }\n" &
    "label { color: inherit; }\n" &
    "button, .button { background-image: none; background-color: " & bg & "; color: " & fg &
      "; border: 1px solid " & frame & "; box-shadow: inset 1px 1px " & light & ", inset -1px -1px " &
      shadow & "; text-shadow: none; padding: 3px 10px; min-height: 18px; }\n" &
    "button:hover { background-image: none; background-color: " & bg & "; }\n" &
    "button:active, button:checked { background-image: none; background-color: " & bg &
      "; box-shadow: inset 1px 1px " & shadow & "; }\n" &
    "button:disabled { color: " & hexOf(t.gray) & "; }\n" &
    "button.flat { border-color: transparent; box-shadow: none; }\n" &
    "button.flat:hover { border-color: " & frame & "; box-shadow: inset 1px 1px " & light &
      ", inset -1px -1px " & shadow & "; }\n" &
    "entry, spinbutton, textview, textview text, treeview.view, list, listview, .view, iconview {" &
      " background-color: " & field & "; color: " & fieldText & "; }\n" &
    "entry, spinbutton { background-image: none; border: 2px solid; border-color: " & shadow & " " &
      light & " " & light & " " & shadow & "; box-shadow: inset 1px 1px " & frame & "; }\n" &
    "*:selected, selection, .view:selected, treeview.view:selected, row:selected, " &
      "entry selection, textview text selection { background-color: " & sel & "; color: " & selText & "; }\n" &
    "menubar, menu, .menu, .context-menu, popover.menu contents { background-color: " & bg &
      "; color: " & fg & "; box-shadow: none; }\n" &
    "menu, .menu, popover.menu contents { border: 1px solid " & frame & "; }\n" &
    "menubar > menuitem:hover, menu menuitem:hover, modelbutton:hover, popover.menu modelbutton:hover {" &
      " background-color: " & sel & "; color: " & selText & "; }\n" &
    "headerbar, .titlebar { background-image: none; background-color: " & sel & "; color: " & selText &
      "; border: none; box-shadow: none; min-height: 24px; padding: 0 4px; }\n" &
    "headerbar .title, .titlebar .title { color: " & selText & "; font-weight: bold; }\n" &
    "scrollbar { background-color: " & scroll & "; border: none; }\n" &
    "scrollbar slider { background-color: " & bg & "; border: 1px solid " & frame &
      "; box-shadow: inset 1px 1px " & light & "; min-width: 14px; min-height: 14px; margin: 0; }\n" &
    "notebook > header { background-color: " & bg & "; }\n" &
    "notebook > header tab { background-color: " & bg & "; color: " & fg & "; border: 1px solid " &
      frame & "; border-bottom: none; padding: 3px 10px; }\n" &
    "notebook > header tab:checked { box-shadow: inset 1px 1px " & light & "; }\n" &
    "check, radio { background-image: none; background-color: " & field & "; color: " & fieldText &
      "; border: 1px solid " & frame & "; }\n" &
    "radio { border-radius: 50%; }\n" &
    "tooltip, tooltip.background { background-color: " & hexOf(t.tip) & "; color: " & hexOf(t.tipText) &
      "; border: 1px solid " & frame & "; }\n" &
    "tooltip * { color: " & hexOf(t.tipText) & "; }\n" &
    "progressbar progress { background-color: " & sel & "; border-radius: 0; }\n" &
    "frame > border, .frame { border: 1px solid " & shadow & "; }\n"

proc installGtkTheme*(t: Theme) =
  ## The "Retro31" GTK theme in the user's themes folder, and GTK's settings
  ## file pointing at it (when the file is the desktop's own, or missing).
  try:
    let dir = getHomeDir() / ".themes" / ThemeName / "gtk-3.0"
    createDir(dir)
    writeFile(dir / "gtk.css", gtkCss(t))
    let ini = getHomeDir() / ".config" / "gtk-3.0" / "settings.ini"
    if not fileExists(ini) or Marker in readFile(ini):
      createDir(ini.parentDir)
      writeFile(ini, Marker & "\n[Settings]\ngtk-theme-name=" & ThemeName & "\n" &
        "gtk-font-name=FreeSans " & $fontPoints() & "\ngtk-dialogs-use-header=false\n" &
        "gtk-xft-antialias=1\ngtk-xft-hinting=1\ngtk-xft-hintstyle=hintslight\ngtk-xft-rgba=none\n" &
        "gtk-decoration-layout=menu:minimize,maximize\ngtk-enable-animations=false\n")
  except CatchableError: discard

# ---- what other programs are told -------------------------------------------------------------------

proc childEnvironment*() =
  ## What programs started from the desktop inherit: GTK 3 without its own
  ## title bars (the desktop's frames), Qt following GTK where it can, no
  ## accessibility bus to wait for.
  putEnv("GTK_CSD", "0")
  putEnv("NO_AT_BRIDGE", "1")
  if not existsEnv("QT_QPA_PLATFORMTHEME"): putEnv("QT_QPA_PLATFORMTHEME", "gtk3")
  putEnv("XCURSOR_SIZE", $max(16, devPx(16)))
  putEnv("RETRO_THEME", desktopSettings().setting("scheme", "Classic"))

proc ownResources*(d: Display): bool =
  ## The X resources on the screen are the ones the desktop put there (a
  ## desktop before this one, on the same X server).
  let root = XRootWindow(d, XDefaultScreen(d))
  let r = propText(d, root, atom(d, "RESOURCE_MANAGER"))
  "Retro Desktop's" in r or "*faceName:\tFreeSans" in r

proc setResources*(d: Display; t: Theme) =
  ## The X resources on the root window (RESOURCE_MANAGER): the density for
  ## Qt, Xft and the rest; fonts and colors for old X programs.
  let root = XRootWindow(d, XDefaultScreen(d))
  let res = "! Retro Desktop's (it puts them back each time it starts)\n" &
    "Xft.dpi:\t" & $dpiNow() & "\nXft.antialias:\t1\nXft.hinting:\t1\nXft.hintstyle:\thintslight\n" &
    "Xft.rgba:\tnone\nXcursor.size:\t" & $max(16, devPx(16)) & "\n" &
    "*background:\t" & hexOf(t.face) & "\n*foreground:\t" & hexOf(t.text) & "\n" &
    "*faceName:\tFreeSans\n*faceSize:\t" & $fontPoints() & "\n" &
    "XTerm*faceName:\tFreeMono\nXTerm*faceSize:\t" & $(fontPoints() + 1) & "\n" &
    "XTerm*background:\t" & hexOf(t.field) & "\nXTerm*foreground:\t" & hexOf(t.fieldText) & "\n" &
    "XTerm*scrollBar:\ttrue\n"
  setText(d, root, atom(d, "RESOURCE_MANAGER"), XA_STRING, res)

# ---- XSETTINGS --------------------------------------------------------------------------------------

var
  settingsWin: Window
  settingsSerial: uint32

proc put32(s: var string; v: uint32) =
  for i in 0 .. 3: s.add char((v shr (8 * i)) and 255)

proc put16(s: var string; v: uint16) =
  s.add char(v and 255)
  s.add char(v shr 8)

proc pad4(s: var string) =
  while s.len mod 4 != 0: s.add '\0'

proc xsettingsBlob(ints: openArray[(string, int)]; strs: openArray[(string, string)]): string =
  ## (the _XSETTINGS_SETTINGS property: little-endian, as the spec says)
  inc settingsSerial
  result.add char(0)                       # LSBFirst
  result.add "\0\0\0"
  result.put32 settingsSerial
  result.put32 uint32(ints.len + strs.len)
  for (name, v) in ints:
    result.add char(0)                     # an integer
    result.add char(0)
    result.put16 uint16(name.len)
    result.add name
    result.pad4
    result.put32 0                         # (last-change serial)
    result.put32 cast[uint32](int32(v))
  for (name, v) in strs:
    result.add char(1)                     # a string
    result.add char(0)
    result.put16 uint16(name.len)
    result.add name
    result.pad4
    result.put32 0
    result.put32 uint32(v.len)
    result.add v
    result.pad4

proc startXSettings*(d: Display) =
  ## The desktop becomes the XSETTINGS manager of the screen: GTK, Chromium
  ## and Electron programs take the theme, the font and the density from it
  ## -- and follow when they change.
  let root = XRootWindow(d, XDefaultScreen(d))
  if settingsWin == 0:
    settingsWin = XCreateSimpleWindow(d, root, -10, -10, 1, 1, 0, 0, 0)
  let sel = atom(d, "_XSETTINGS_S" & $XDefaultScreen(d))
  let blob = xsettingsBlob(
    [("Xft/DPI", dpiNow() * 1024), ("Xft/Antialias", 1), ("Xft/Hinting", 1),
     ("Net/DoubleClickTime", 500), ("Gtk/DialogsUseHeader", 0), ("Gtk/EnableAnimations", 0),
     ("Gtk/CursorThemeSize", max(16, devPx(16))), ("Net/EnableEventSounds", 0)],
    [("Net/ThemeName", ThemeName), ("Gtk/FontName", "FreeSans " & $fontPoints()),
     ("Gtk/MonospaceFontName", "FreeMono " & $(fontPoints() + 1)), ("Xft/HintStyle", "hintslight"),
     ("Xft/RGBA", "none"), ("Gtk/DecorationLayout", "menu:minimize,maximize")])
  let prop = atom(d, "_XSETTINGS_SETTINGS")
  var b = blob
  discard XChangeProperty(d, settingsWin, prop, prop, 8, PropModeReplace, addr b[0], cint(b.len))
  if XGetSelectionOwner(d, sel) != settingsWin:
    discard XSetSelectionOwner(d, sel, settingsWin, CurrentTime)
    # (tell the screen's clients there is a manager now: MANAGER, as ICCCM asks)
    var e: XEvent
    e.xclient.theType = ClientMessage
    e.xclient.window = root
    e.xclient.messageType = atom(d, "MANAGER")
    e.xclient.format = 32
    e.xclient.data[0] = clong(CurrentTime)
    e.xclient.data[1] = clong(sel)
    e.xclient.data[2] = clong(settingsWin)
    discard XSendEvent(d, root, 0, StructureNotifyMask, addr e)
  discard XFlush(d)

proc applyLook*(d: Display) =
  ## Everything above, for the color scheme, fonts and size the settings say.
  let t = schemeTheme(desktopSettings().setting("scheme", "Classic"))
  if desktopSettings().setting("linuxLook", "on") == "on":
    installFonts()
    installGtkTheme(t)
    startXSettings(d)
  setResources(d, t)
  childEnvironment()
