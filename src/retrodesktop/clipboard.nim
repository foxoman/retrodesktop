## Clipboard Viewer: what was copied last, as 3.1's Clipboard Viewer showed
## it -- and, in Termux, Android's clipboard brought in or sent out (with the
## Termux:API app and `pkg install termux-api`; Termux:X11 can also share the
## clipboard by itself, in its preferences).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils, streams]
import retroui
import common, link

proc androidClipboard(): bool = findExe("termux-clipboard-get").len > 0

proc runClipboard*() =
  applyDesktopLook()
  openApp("Clipboard Viewer", scaled(480), scaled(340), frame = wfSystem, userFrame = false,
          id = "clipboard")
  showArt("clipboard")
  followLook()
  var text = getClipboardText()
  var lookedAt = 0
  var showSave, showAbout, showSaid: bool
  var savePath = getHomeDir() / "Clipboard.txt"
  var said = ""
  while beginFrame():
    # (looked at again every two seconds: a program copied something)
    if ui.now - lookedAt >= 2000:
      lookedAt = ui.now
      let t = getClipboardText()
      if t != text: text = t
    wakeIn(2000)
    menubar:
      menu "&File":
        if menuItem("Save &As...", enabled = text.len > 0): showSave = true
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Edit":
        if menuItem("&Delete", "Del", enabled = text.len > 0):
          putClipboardText("")
          text = ""
        if androidClipboard():
          menuSeparator()
          if menuItem("&Get Android's Clipboard"):
            let (o, code) = execCmdEx("termux-clipboard-get")
            if code == 0:
              putClipboardText(o)
              text = o
            else:
              said = "Android's clipboard could not be read: the Termux:API app is needed " &
                     "(from where Termux came), with pkg install termux-api."
              showSaid = true
          if menuItem("&Send to Android's Clipboard", enabled = text.len > 0):
            let p = startProcess("termux-clipboard-set", options = {poUsePath})
            p.inputStream.write(text)
            p.inputStream.close()
            discard p.waitForExit()
            p.close()
      menu "&Help":
        if menuItem("&About Clipboard Viewer..."): showAbout = true
    if hotkeyPressed("Delete") and text.len > 0:
      putClipboardText("")
      text = ""
    if text.len == 0:
      label("The clipboard is empty. What you copy (Ctrl+C, Edit > Copy) shows here.",
            enabled = false)
    else:
      var shown = if text.len > 200_000: text[0 ..< 200_000] else: text
      editArea(shown, lines = -1, readOnly = true)
    if fileDialog(showSave, savePath, fmSave, ["Text Files (*.txt)"], title = "Save As"):
      try: writeFile(savePath, text)
      except CatchableError as e:
        said = "Cannot save: " & e.msg
        showSaid = true
    if showSaid: discard msgBox(showSaid, "Clipboard Viewer", said, ["OK"], miInfo)
    aboutBox(showAbout, "Clipboard Viewer", DesktopVersion,
             ["What was copied last, from any program.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
