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
import retroui/uirelays/drivers/x11_driver
import retroui/uirelays/screen
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

proc cursorSize*(): int =
  ## The cursors' size: 16 pixels at the screen's scale, in whole steps (the
  ## classic drawings stay crisp).
  16 * max(1, int(round(devScale())))

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
    # (scroll bars as 3.1 had them: always there, an arrow button at each end)
    "* { -GtkScrollbar-has-backward-stepper: true; -GtkScrollbar-has-forward-stepper: true; }\n" &
    "scrollbar { background-color: " & scroll & "; border: 1px solid " & frame & "; }\n" &
    "scrollbar slider { background-color: " & bg & "; border: 1px solid " & frame &
      "; box-shadow: inset 1px 1px " & light & ", inset -1px -1px " & shadow &
      "; min-width: 15px; min-height: 15px; margin: 0; }\n" &
    "scrollbar button { background-color: " & bg & "; color: " & fg & "; border: 1px solid " &
      frame & "; box-shadow: inset 1px 1px " & light & ", inset -1px -1px " & shadow &
      "; min-width: 15px; min-height: 15px; padding: 0; }\n" &
    "scrollbar button:active { box-shadow: inset 1px 1px " & shadow & "; }\n" &
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
        "gtk-decoration-layout=menu:minimize,maximize\ngtk-enable-animations=false\n" &
        "gtk-overlay-scrolling=false\ngtk-primary-button-warps-slider=false\n")
  except CatchableError: discard

# ---- what other programs are told -------------------------------------------------------------------

# ---- the cursors -----------------------------------------------------------------------------------

const
  CursorTheme* = "Retro31"
  CursorNames: array[CursorKind, seq[string]] = [
    curDefault: @["left_ptr", "default", "arrow", "top_left_arrow", "left_arrow", "X_cursor",
                  "help", "question_arrow", "whats_this", "context-menu", "copy", "alias",
                  "dnd-copy", "dnd-move", "dnd-link", "dnd-none", "no-drop", "not-allowed",
                  "crossed_circle", "forbidden", "pirate"],
    curArrow: @["right_ptr", "draft_large", "draft_small", "center_ptr"],
    curIbeam: @["xterm", "text", "ibeam", "vertical-text"],
    curWait: @["watch", "wait", "progress", "left_ptr_watch", "half-busy"],
    curCrosshair: @["crosshair", "cross", "tcross", "cross_reverse", "diamond_cross", "cell",
                    "plus", "target"],
    curHand: @["hand2", "hand1", "hand", "pointer", "pointing_hand", "grab", "grabbing",
               "openhand", "closedhand", "dnd-ask"],
    curSizeNS: @["sb_v_double_arrow", "v_double_arrow", "ns-resize", "row-resize", "n-resize",
                 "s-resize", "top_side", "bottom_side", "size_ver", "split_v", "double_arrow",
                 "up-arrow", "down-arrow"],
    curSizeWE: @["sb_h_double_arrow", "h_double_arrow", "ew-resize", "col-resize", "e-resize",
                 "w-resize", "left_side", "right_side", "size_hor", "split_h"],
    curSizeNWSE: @["bottom_right_corner", "top_left_corner", "nwse-resize", "nw-resize",
                   "se-resize", "size_fdiag", "bd_double_arrow", "ul_angle", "lr_angle"],
    curSizeNESW: @["bottom_left_corner", "top_right_corner", "nesw-resize", "ne-resize",
                   "sw-resize", "size_bdiag", "fd_double_arrow", "ur_angle", "ll_angle"],
    curMove: @["fleur", "move", "all-scroll", "size_all"]]

proc xcursorFile(c: CursorKind): string =
  ## Cursor `c` as an Xcursor file (what libXcursor reads for GTK, Qt,
  ## Firefox and the rest): the classic drawing at 16, 24, 32, 48 and 64
  ## pixels, as crisp squares of its pixels.
  let art = classicCursorArt(c)
  var aw = 0
  for r in art.rows: aw = max(aw, r.len)
  let sizes = [16, 24, 32, 48, 64]
  proc put32(s: var string; v: uint32) =
    for i in 0 .. 3: s.add char((v shr (8 * i)) and 255)
  var images: seq[string]
  for n in sizes:
    let k = float(n) / 16
    let w = int(ceil(float(aw) * k))
    let h = int(ceil(float(art.rows.len) * k))
    var img = ""
    img.put32 36
    img.put32 0xFFFD0002'u32
    img.put32 uint32(n)
    img.put32 1
    img.put32 uint32(w)
    img.put32 uint32(h)
    img.put32 uint32(int(float(art.hx) * k + (if art.hx > 0: k / 2 else: 0)))
    img.put32 uint32(int(float(art.hy) * k + (if art.hy > 0: k / 2 else: 0)))
    img.put32 0
    for y in 0 ..< h:
      let row = art.rows[min(art.rows.high, int(float(y) / k))]
      for x in 0 ..< w:
        let col = int(float(x) / k)
        let ch = if col < row.len: row[col] else: ' '
        img.put32(case ch
                  of 'X': 0xFF000000'u32
                  of '.': 0xFFFFFFFF'u32
                  else: 0'u32)
    images.add img
  result = "Xcur"
  result.put32 16
  result.put32 0x10000
  result.put32 uint32(images.len)
  var at = 16 + 12 * images.len
  for i, n in sizes:
    result.put32 0xFFFD0002'u32
    result.put32 uint32(n)
    result.put32 uint32(at)
    at += images[i].len
  for img in images: result.add img

proc installCursors*() =
  ## The classic cursors as the cursor theme "Retro31" (~/.icons/Retro31),
  ## and the default theme when the user has none of their own: programs
  ## that are not the desktop's show them too, at the screen's size.
  let dir = getHomeDir() / ".icons" / CursorTheme
  let index = dir / "index.theme"
  let stamp = "Comment=The cursors of Retro Desktop " & DesktopVersion
  try:
    if fileExists(index) and stamp in readFile(index): return
    createDir(dir / "cursors")
    for c in CursorKind:
      let names = CursorNames[c]
      if names.len == 0: continue
      # (one file a shape; its other names link to it)
      let first = dir / "cursors" / names[0]
      writeFile(first, xcursorFile(c))
      for n in names[1 .. ^1]:
        let p = dir / "cursors" / n
        try:
          if symlinkExists(p) or fileExists(p): removeFile(p)
          createSymlink(names[0], p)
        except OSError: copyFile(first, p)
    writeFile(index, "[Icon Theme]\nName=" & CursorTheme & "\n" & stamp & "\n")
    let def = getHomeDir() / ".icons" / "default" / "index.theme"
    if not fileExists(def) or "Retro Desktop" in readFile(def):
      createDir(def.parentDir)
      writeFile(def, "[Icon Theme]\nName=Default\nComment=Retro Desktop's choice\nInherits=" &
                     CursorTheme & "\n")
  except CatchableError: discard

proc childEnvironment*() =
  ## What programs started from the desktop inherit: GTK 3 without its own
  ## title bars (the desktop's frames), Qt following GTK where it can, no
  ## accessibility bus to wait for.
  putEnv("GTK_CSD", "0")
  putEnv("GTK_OVERLAY_SCROLLING", "0")        # (scroll bars always there, as 3.1's)
  putEnv("NO_AT_BRIDGE", "1")
  if not existsEnv("QT_QPA_PLATFORMTHEME"): putEnv("QT_QPA_PLATFORMTHEME", "gtk3")
  putEnv("XCURSOR_SIZE", $cursorSize())
  putEnv("XCURSOR_THEME", CursorTheme)
  putEnv("RETRO_THEME", currentScheme(desktopSettings()))

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
    "Xft.rgba:\tnone\nXcursor.size:\t" & $cursorSize() & "\nXcursor.theme:\t" & CursorTheme & "\n" &
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
     ("Gtk/CursorThemeSize", cursorSize()), ("Net/EnableEventSounds", 0),
     ("Gtk/OverlayScrolling", 0)],
    [("Net/ThemeName", ThemeName), ("Gtk/CursorThemeName", CursorTheme), ("Gtk/FontName", "FreeSans " & $fontPoints()),
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
  let t = schemeTheme(currentScheme(desktopSettings()))
  installCursors()
  if desktopSettings().setting("linuxLook", "on") == "on":
    installFonts()
    installGtkTheme(t)
    startXSettings(d)
  setResources(d, t)
  childEnvironment()
