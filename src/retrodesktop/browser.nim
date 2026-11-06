## Retro Browser: Firefox dressed as a 3.1 program -- gray toolbars, square
## raised buttons, tabs like 3.1 buttons, a sunken address field, 3.1
## menus, the menu bar shown, FreeSans, the desktop's color scheme -- in
## the desktop's frame (Firefox draws no title bar of its own). It runs on a
## profile of its own (~/.local/share/retrodesktop/browser): the user's own
## Firefox, and its profile, stay as they are.
##
## The look is written each time it starts, from the color scheme Control
## Panel set; the rest of the profile is Firefox's.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, posix]
import retroui
import common

proc firefoxPath*(): string =
  ## Firefox, when it is installed ("" when not).
  for n in ["firefox", "firefox-esr"]:
    let p = findExe(n)
    if p.len > 0: return p
  ""

proc profileDir*(): string = dataDir(SettingsName) / "browser"

proc userChrome(t: Theme): string =
  let face = hexOf(t.face)
  let text = hexOf(t.text)
  let light = hexOf(t.light)
  let shadow = hexOf(t.shadow)
  let frame = hexOf(t.frame)
  let field = hexOf(t.field)
  let fieldText = hexOf(t.fieldText)
  let sel = hexOf(t.select)
  let selText = hexOf(t.selectText)
  result = "/* Retro Browser: Firefox in the colors and shapes of Windows 3.1.\n" &
    "   Retro Desktop writes this file each time it starts the browser. */\n\n" &
    ":root {\n" &
    "  --rb-face: " & face & "; --rb-text: " & text & "; --rb-light: " & light & ";\n" &
    "  --rb-shadow: " & shadow & "; --rb-frame: " & frame & "; --rb-field: " & field & ";\n" &
    "  --rb-field-text: " & fieldText & "; --rb-select: " & sel & "; --rb-select-text: " & selText & ";\n" &
    """
  --toolbar-bgcolor: var(--rb-face) !important;
  --toolbar-color: var(--rb-text) !important;
  --toolbar-field-background-color: var(--rb-field) !important;
  --toolbar-field-color: var(--rb-field-text) !important;
  --toolbar-field-focus-background-color: var(--rb-field) !important;
  --toolbar-field-focus-color: var(--rb-field-text) !important;
  --toolbar-field-border-color: var(--rb-shadow) !important;
  --lwt-accent-color: var(--rb-face) !important;
  --lwt-text-color: var(--rb-text) !important;
  --tab-selected-bgcolor: var(--rb-field) !important;
  --tab-selected-textcolor: var(--rb-text) !important;
  --tab-border-radius: 0 !important;
  --toolbarbutton-border-radius: 0 !important;
  --arrowpanel-border-radius: 0 !important;
  --arrowpanel-background: var(--rb-face) !important;
  --arrowpanel-color: var(--rb-text) !important;
  --arrowpanel-border-color: var(--rb-frame) !important;
  --panel-border-radius: 0 !important;
  --border-radius-small: 0 !important;
  --border-radius-medium: 0 !important;
  --border-radius-large: 0 !important;
  --urlbar-box-bgcolor: var(--rb-face) !important;
  --focus-outline-color: var(--rb-frame) !important;
  --chrome-content-separator-color: var(--rb-frame) !important;
  --button-bgcolor: var(--rb-face) !important;
  --button-color: var(--rb-text) !important;
}
* { border-radius: 0 !important; }
#main-window, #navigator-toolbox, #TabsToolbar, #nav-bar, #PersonalToolbar, #toolbar-menubar {
  background: var(--rb-face) !important;
  color: var(--rb-text) !important;
  font-family: "FreeSans", sans-serif !important;
}
#navigator-toolbox { border-bottom: 1px solid var(--rb-frame) !important; }
#nav-bar { border-top: 1px solid var(--rb-light) !important; box-shadow: none !important; }

/* tabs: 3.1 buttons, the one shown pressed in */
.tabbrowser-tab .tab-background {
  margin-block: 3px !important;
  background: var(--rb-face) !important;
  border: 1px solid var(--rb-frame) !important;
  box-shadow: inset 1px 1px var(--rb-light), inset -1px -1px var(--rb-shadow) !important;
}
.tabbrowser-tab[selected] .tab-background {
  background: var(--rb-field) !important;
  box-shadow: inset 1px 1px var(--rb-shadow) !important;
}
.tabbrowser-tab[selected] .tab-label { font-weight: bold !important; }
.tab-label { color: var(--rb-text) !important; }

/* toolbar buttons: raised; pressed in while held or open */
#nav-bar .toolbarbutton-1 > .toolbarbutton-icon,
#nav-bar .toolbarbutton-1 > .toolbarbutton-badge-stack {
  background: var(--rb-face) !important;
  border: 1px solid var(--rb-frame) !important;
  box-shadow: inset 1px 1px var(--rb-light), inset -1px -1px var(--rb-shadow) !important;
}
#nav-bar .toolbarbutton-1:not([disabled]):hover:active > .toolbarbutton-icon,
#nav-bar .toolbarbutton-1[open] > .toolbarbutton-icon,
#nav-bar .toolbarbutton-1[checked] > .toolbarbutton-icon {
  box-shadow: inset 1px 1px var(--rb-shadow) !important;
}
.toolbarbutton-1[disabled] { opacity: 0.5 !important; }

/* the address: a sunken field */
#urlbar-background, #searchbar {
  background: var(--rb-field) !important;
  border: 1px solid !important;
  border-color: var(--rb-shadow) var(--rb-light) var(--rb-light) var(--rb-shadow) !important;
  box-shadow: inset 1px 1px var(--rb-frame) !important;
  outline: none !important;
}
#urlbar-input, #urlbar { color: var(--rb-field-text) !important; }
.urlbarView-row[selected], .urlbarView-row:hover { background: var(--rb-select) !important;
  color: var(--rb-select-text) !important; }

/* menus: 3.1 menus */
menupopup, panel {
  --panel-background: var(--rb-face) !important;
  --panel-color: var(--rb-text) !important;
  --panel-border-color: var(--rb-frame) !important;
  --panel-shadow-margin: 0px !important;
}
menupopup menuitem[_moz-menuactive], menupopup menu[_moz-menuactive],
menubar > menu[_moz-menuactive], menubar > menu[open] {
  background: var(--rb-select) !important;
  color: var(--rb-select-text) !important;
}

/* the status line */
#statuspanel-label {
  background: var(--rb-face) !important;
  color: var(--rb-text) !important;
  border: 1px solid var(--rb-shadow) !important;
}
"""

const UserJs = """// Retro Browser: Retro Desktop writes this file each time it starts the browser.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.tabs.inTitlebar", 0);
user_pref("browser.uidensity", 1);
user_pref("browser.compactmode.show", true);
user_pref("ui.prefersReducedMotion", 1);
user_pref("toolkit.cosmeticAnimations.enabled", false);
user_pref("ui.systemUsesDarkTheme", 0);
user_pref("browser.theme.toolbar-theme", 1);
user_pref("browser.theme.content-theme", 1);
user_pref("layout.css.prefers-color-scheme.content-override", 1);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
// (scroll bars always there, with their arrows, as 3.1 had them)
user_pref("widget.gtk.overlay-scrollbars.enabled", false);
user_pref("widget.non-native-theme.scrollbar.style", 4);
user_pref("widget.non-native-theme.win.scrollbar.use-system-size", false);
// (a phone's memory: fewer content processes, tabs let go when it runs short)
user_pref("dom.ipc.processCount", 2);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.sessionstore.interval", 60000);
"""

proc writeProfile*() =
  ## The browser's profile: its look (userChrome.css, from the desktop's
  ## color scheme) and its settings (user.js) written again; the menu bar
  ## shown the first time.
  let dir = profileDir()
  createDir(dir / "chrome")
  let t = schemeTheme(desktopSettings().setting("scheme", "Classic"))
  writeFile(dir / "chrome" / "userChrome.css", userChrome(t))
  # (the pages' scroll bars in the scheme's grays, where a page sets none)
  writeFile(dir / "chrome" / "userContent.css",
            "/* Retro Browser: Retro Desktop writes this file each time it starts the browser. */\n" &
            ":root { scrollbar-color: " & hexOf(t.face) & " " & hexOf(t.scroll) & "; }\n")
  writeFile(dir / "user.js", UserJs)
  let xul = dir / "xulstore.json"
  if not fileExists(xul):
    writeFile(xul, """{"chrome://browser/content/browser.xhtml":{"toolbar-menubar":{"autohide":"false"}}}""")

proc runBrowser*(args: seq[string]) =
  ## Firefox as Retro Browser (with `args`: the pages to open). Without
  ## Firefox: a word on how to install it.
  let ff = firefoxPath()
  if ff.len == 0:
    applyDesktopLook()
    openApp("Retro Browser", scaled(420), scaled(160), frame = wfSystem, userFrame = false,
            id = "browser")
    var show = true
    while beginFrame():
      if msgBox(show, "Retro Browser", "Retro Browser is Firefox in the desktop's look, and " &
                "Firefox is not installed. In Termux: pkg install firefox (from x11-repo); " &
                "on Linux, your system's Firefox.", ["OK"], miInfo) != 0 or not show:
        quitApp()
      endFrame()
    closeApp()
    return
  try: writeProfile()
  except CatchableError: discard
  var argv = @[ff, "--profile", profileDir(), "--no-remote", "--class", "RetroBrowser",
               "--name", "RetroBrowser"]
  for a in args: argv.add a
  let cargs = allocCStringArray(argv)
  discard execv(cstring(ff), cargs)
  # (only when it could not start)
  deallocCStringArray(cargs)
  quit(1)
