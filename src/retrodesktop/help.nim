## Help, as 3.1's: a window of topics with links between them, opened by F1
## (or Help > Help Topics) in every program of the desktop at that program's
## page -- and the tour the first start offers, a few pages with pictures.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retroui
import common, link, art

const Topics* = [
  ("contents", "Contents", """
# Retro Desktop Help

Choose a topic:

* [Using the desktop](topic:desktop) -- windows, the mouse and the finger
* [Keys](topic:keys)
* [Program Manager](topic:progman) and [Setup](topic:setup)
* [Terminal](topic:terminal) and [Retro Browser](topic:browser)
* [Write](topic:write), [Clipboard Viewer](topic:clipboard)
* [Clock](topic:clock), [Calculator](topic:calc), [Calendar](topic:calendar), [Cardfile](topic:cardfile)
* [Task List](topic:tasklist), [Control Panel](topic:control)
* [Minesweeper](topic:mines), [Solitaire](topic:solitaire), [Reversi](topic:reversi)
* [DOS games](topic:dos)
* [Android and Termux](topic:android)
"""),
  ("desktop", "Using the desktop", """
# Using the desktop

Every program opens in its own window.

* **Move** a window by its title bar; **size** it by its border or a corner.
  Near an edge of the screen or of another window it snaps against it.
* The **minimize** button (the arrow down) makes it an icon at the bottom of
  the desktop; double click the icon (tap it on a touch screen) to bring it back.
* The **maximize** button (the arrow up), or a double click on the title bar,
  makes it fill the screen.
* The **control-menu box** (the bar at the left of the title) has Restore,
  Minimize, Maximize, Close and Switch To. Double click it to close the
  window. On a touch screen, hold a finger on the title bar for the same menu.
* A **right click on the desktop** (a finger held on it) opens its menu:
  Program Manager, Task List, Control Panel, Terminal, Run, Cascade, Tile.

In a menu the underlined letter chooses an item; the arrows, Enter and Esc
work too. The programs open when the desktop ends open again the next time,
where they were. See also [Keys](topic:keys) and [Contents](topic:contents).
"""),
  ("keys", "Keys", """
# Keys

| Keys | What they do |
|---|---|
| Alt+Tab | holding Alt: a box with the next window; Tab again for the one behind; let go of Alt to go there |
| Alt+Shift+Tab | the other way |
| Alt+F4 | closes the window in front |
| Alt+Esc | minimizes it |
| Ctrl+Esc | the Task List |
| F1 | Help, at the page of the program in front |
| Android's Back | closes the window in front (when Termux:X11 sends it as Back) |
| Ctrl+Shift+C, V | copy and paste in the Terminal |

[Contents](topic:contents)
"""),
  ("progman", "Program Manager", """
# Program Manager

The programs, in groups: **Main** (File Manager, Control Panel, Task List,
Terminal, Web Browser, Setup, Read Me), **Accessories**, **Games**, **StartUp**,
and a group for each kind of program you install (Internet, Office,
Development, Graphics, Multimedia, System), and **DOS** once DOSBox-X is in.

* Double click a program (tap it) to start it.
* **File > New** puts a program of your own in a group, with its command line.
  Programs in StartUp start with the desktop.
* **Options > Refresh** (F5) looks again; programs you install appear by
  themselves after a few seconds anyway.

[Setup](topic:setup) installs more. [Contents](topic:contents)
"""),
  ("setup", "Setup", """
# Setup

Programs from Termux's packages, as 3.1's Setup put programs on a PC.

1. Check the programs you want; clear one that is installed to remove it.
2. **Continue**: Setup says how much space they need, and how much there is.
3. **Continue** again: the gauge shows the packages coming in (or going).

Underneath it is Termux's apt (what `pkg` runs): it adds x11-repo first
when a program needs it and reads the lists of programs when they are old.
When it cannot reach the Internet, `termux-change-repo` in the
[Terminal](topic:terminal) picks another mirror.

Programs with windows come into Program Manager by themselves; the
Terminal's programs (htop, NetHack...) get an item. [Contents](topic:contents)
"""),
  ("terminal", "Terminal", """
# Terminal

The shell, in a PC's 16 text colors (Settings: Windows' black on white or
MS-DOS's gray on black, bold letters, larger or smaller text).

* Ctrl+Shift+C copies what you selected, Ctrl+Shift+V pastes.
* Shift+PgUp and Shift+PgDn go through what scrolled away (the wheel too).
* Full-screen programs work: vim, nano, htop, mc, less.

`retro-desktop terminal -e command` runs a command in it. [Contents](topic:contents)
"""),
  ("browser", "Retro Browser", """
# Retro Browser

Firefox dressed as a 3.1 program, on a profile of its own: your own Firefox
stays as it is. When Firefox is not installed, Retro Browser offers to
install it with [Setup](topic:setup). [Contents](topic:contents)
"""),
  ("write", "Write", """
# Write

Documents with **bold**, *italic*, underline, sizes, colors, lists and
alignment: the Character and Paragraph menus, the tool bar, or Ctrl+B, I, U.
Documents are kept as HTML (a browser, LibreOffice or AbiWord opens them) or
as plain text (.txt). Ctrl+Z undoes. [Contents](topic:contents)
"""),
  ("clipboard", "Clipboard Viewer", """
# Clipboard Viewer

What was copied last, from any program. **Edit > Delete** empties it;
**File > Save As** keeps it in a file. In Termux with the Termux:API app
(Setup > System > Termux:API tools), Edit brings Android's clipboard in or
sends it out. [Contents](topic:contents)
"""),
  ("clock", "Clock", """
# Clock

The time, on a face or in numbers (Settings), with the seconds and the date.
Made small, it shows the time in its title. Control Panel's Date/Time
chooses 12 or 24 hours and the time zone. [Contents](topic:contents)
"""),
  ("calc", "Calculator", """
# Calculator

The keys of the keyboard work as its buttons: the numbers, + - * /, Enter for
=, Esc to clear, Backspace. Edit > Copy and Paste take the number in and
out. [Contents](topic:contents)
"""),
  ("calendar", "Calendar", """
# Calendar

The month, the days with appointments and notes. Click a day to see it and
write in it; Show goes to today or another date. [Contents](topic:contents)
"""),
  ("cardfile", "Cardfile", """
# Cardfile

Cards of names, numbers and notes, in the order of their titles. Card > Add
makes one; Search > Go To finds a word on the cards. [Contents](topic:contents)
"""),
  ("tasklist", "Task List", """
# Task List

Ctrl+Esc: every window, and the memory its program takes (its own share).
Switch To brings one to the front; End Task ends a program that does not
answer; Cascade and Tile arrange the windows. [Contents](topic:contents)
"""),
  ("control", "Control Panel", """
# Control Panel

* **Color**: the color scheme of every window (and of GTK programs).
* **Desktop**: its color, pattern and wallpaper (pictures of yours, or the
  desktop's own), Termux kept awake, the programs reopened.
* **Fonts**: the font, the text size, the size of everything.
* **Windows**: frames for fingers, windows that open maximized, programs
  paused while minimized (no CPU, no battery).
* **Date/Time**: 12 or 24 hours, the time zone.
* **Sound**: which chime goes with which event.
* **Screen Saver**: after a delay with nothing done.
* **Linux Programs**: the look given to other programs; 3D through
  Android's GPU (VirGL). [Contents](topic:contents)
"""),
  ("mines", "Minesweeper", """
# Minesweeper

Open the squares without the mines. A number says how many mines touch its
square. A right click (a finger held) puts a flag where a mine is; clicking
a number whose mines are all flagged opens the squares around it. The face
starts a new game; Game chooses Beginner, Intermediate or Expert, and keeps
the best times. [Contents](topic:contents)
"""),
  ("solitaire", "Solitaire", """
# Solitaire

Build the four suits up from the aces, at the top right. In the columns,
cards go down in turn red and black; a king goes on an empty column.

* Drag cards with the mouse or a finger; a tap (a double click) sends a card
  where it can go.
* Click the deck to turn cards over (Game: draw one or three).
* A right click sends every card it can up to the aces.
* Game > Undo (Ctrl+Z), Deck to choose the back of the cards. [Contents](topic:contents)
"""),
  ("reversi", "Reversi", """
# Reversi

You have black, the computer white. Put a piece so that a line of white
pieces lies between it and one of yours: they turn black. When you cannot
move, Game > Pass. The most pieces at the end wins. Skill chooses how well
the computer plays; Game > Hint shows a good move. [Contents](topic:contents)
"""),
  ("dos", "DOS games", """
# DOS games

Install DOSBox-X with [Setup](topic:setup) (Games). The folder **DOS** in your
home is its drive C: put your games and programs there, a folder each, and
Program Manager's **DOS** group shows them: a double click starts the game in
DOSBox-X. DOSBox-X alone opens at C:. [Contents](topic:contents)
"""),
  ("android", "Android and Termux", """
# Android and Termux

Android stops programs it thinks you do not use. For a desktop that stays:

* Keep Termux awake (Control Panel > Desktop).
* Settings > Apps > Termux (and Termux:X11) > Battery: **Unrestricted**.
* Android 12 and later: Developer options > **Disable child process
  restrictions** (or, from a computer: `adb shell "settings put global
  settings_enable_monitor_phantom_procs false"`).

Main > **Android Files** shows the phone's photos, downloads and documents.
When Android ends Termux anyway, the programs that were open open again
the next time. [Contents](topic:contents)
""")]

proc topicIndex(name: string): int =
  for i, t in Topics:
    if t[0] == name: return i
  0

proc openHelp*(topic: string) =
  ## Help at `topic`, in a window of its own.
  launch(selfCommand("help") & " " & topic)

proc helpKeys*(topic: string) =
  ## F1: Help at `topic` (each program calls this every frame).
  if hotkeyPressed("F1"): openHelp(topic)

proc runHelp*(topic: string) =
  applyDesktopLook()
  openApp("Help", scaled(560), scaled(460), frame = wfSystem, userFrame = false, id = "help")
  showArt("help")
  followLook()
  var at = topicIndex(topic)
  var back: seq[int]
  while beginFrame():
    let wanted = "Help - " & Topics[at][1]
    if ui.title != wanted: setTitle(wanted)
    menubar:
      menu "&File":
        if menuItem("E&xit"): quitApp()
      menu "&Topics":
        for i, t in Topics:
          withId(i):
            if menuItem(t[1], checked = i == at):
              back.add at
              at = i
    row:
      if button("&Contents"):
        back.add at
        at = 0
      if button("&Back", enabled = back.len > 0): at = back.pop()
      spring()
    let ev = markdownView(Topics[at][2], key = Topics[at][0])
    if ev.link.startsWith("topic:"):
      back.add at
      at = topicIndex(ev.link[6 .. ^1])
    elif ev.link.len > 0: launch(selfCommand("open") & " " & quoteShell(ev.link))
    if ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()

# ---- the tour ---------------------------------------------------------------------------------------

proc miniWindow(r: Rect; title: string; active = true) =
  fill(r, color(255, 255, 255))
  box(r, color(0, 0, 0))
  let bar = rect(r.x + 1, r.y + 1, r.w - 2, lineHeight() + dp(4))
  fill(bar, if active: color(0, 0, 128) else: color(255, 255, 255))
  text(bar.x + (bar.w - textWidth(title, true)) div 2, bar.y + dp(2), title,
       (if active: color(255, 255, 255) else: color(0, 0, 0)), true)
  let s = bar.h
  fill(rect(bar.x, bar.y, s, s), color(192, 192, 192))
  fill(rect(bar.x + bar.w - 2 * s, bar.y, s, s), color(192, 192, 192))
  fill(rect(bar.x + bar.w - s, bar.y, s, s), color(192, 192, 192))
  box(rect(bar.x, bar.y, s, s), color(0, 0, 0))
  box(rect(bar.x + bar.w - 2 * s, bar.y, s, s), color(0, 0, 0))
  box(rect(bar.x + bar.w - s, bar.y, s, s), color(0, 0, 0))

proc callout(x, y: int; s: string) =
  let w = textWidth(s) + dp(10)
  let r = rect(x, y, w, lineHeight() + dp(6))
  fill(r, color(255, 255, 225))
  box(r, color(0, 0, 0))
  text(r.x + dp(5), r.y + dp(3), s, color(0, 0, 0))

proc tourPicture(page: int; r: Rect) =
  fill(r, color(0, 128, 128))
  let px = devPx(32.0)
  let s = dp(32)
  case page
  of 0:
    let k = min(r.w, r.h) * 6 div 10
    drawBitmap(rect(r.x + (r.w - k) div 2, r.y + (r.h - k) div 2, k, k), appIcon("logo", devPx(float(k))))
  of 1:
    let w = rect(r.x + r.w div 6, r.y + r.h div 5, r.w * 2 div 3, r.h * 3 div 5)
    miniWindow(w, "A window")
    callout(w.x - dp(4), w.y - lineHeight() - dp(10), "Drag the title bar to move it")
    callout(w.x + w.w - dp(150), w.y + w.h + dp(4), "Its border or a corner sizes it")
    callout(w.x + w.w - dp(120), w.y + lineHeight() + dp(12), "Minimize, maximize")
  of 2:
    let w = rect(r.x + dp(16), r.y + dp(16), r.w - dp(32), r.h - dp(32))
    miniWindow(w, "Program Manager")
    var x = w.x + dp(16)
    for kind in ["files", "control", "terminal", "browser", "setup", "write"]:
      drawBitmap(rect(x, w.y + dp(40), s, s), appIcon(kind, px))
      x += s + dp(18)
    callout(w.x + dp(16), w.y + dp(40) + s + dp(12), "Double click (tap) a program to start it")
    callout(w.x + dp(16), w.y + dp(40) + s + dp(40), "Setup installs more programs")
  of 3:
    let m = rect(r.x + r.w div 3, r.y + dp(20), r.w div 3, r.h - dp(40))
    fill(m, color(255, 255, 255))
    box(m, color(0, 0, 0))
    var y = m.y + dp(4)
    for it in ["Program Manager", "Task List...", "Control Panel", "Terminal", "Run...", "Cascade", "Tile"]:
      text(m.x + dp(10), y, it, color(0, 0, 0))
      y += lineHeight() + dp(4)
    callout(r.x + dp(8), r.y + r.h - lineHeight() - dp(14), "Right click (hold a finger) on the desktop")
  of 4:
    let b = rect(r.x + r.w div 6, r.y + r.h * 2 div 5, r.w * 2 div 3, dp(56))
    fill(b, color(192, 192, 192))
    box(b, color(0, 0, 0), 2)
    drawBitmap(rect(b.x + dp(12), b.y + (b.h - s) div 2, s, s), appIcon("terminal", px))
    text(b.x + dp(56), b.y + (b.h - lineHeight()) div 2, "Terminal", color(0, 0, 0), true)
    callout(b.x, b.y - lineHeight() - dp(16), "Hold Alt, press Tab: the next window")
  else:
    var x = r.x + dp(20)
    for kind in ["help", "control", "storage", "sound"]:
      drawBitmap(rect(x, r.y + r.h div 3, s * 2, s * 2), appIcon(kind, devPx(64.0)))
      x += s * 2 + dp(24)
    callout(r.x + dp(20), r.y + r.h div 3 + s * 2 + dp(12), "F1 in any program: its Help")

const TourPages = [
  ("Welcome", "This is Retro Desktop: Windows 3.1's look for your phone, tablet or " &
   "computer, with every Linux program in a window of its own. This tour takes a minute."),
  ("Windows", "Each program has a window: move it by its title bar, size it by its " &
   "border, minimize it to an icon or maximize it with the buttons. On a touch screen, " &
   "hold a finger on a title bar for its menu."),
  ("Program Manager", "Your programs are in Program Manager's groups. Setup, in Main, " &
   "installs more -- browsers, office, development, games -- from Termux's packages."),
  ("The desktop's menu", "A right click on the desktop -- or a finger held on it -- " &
   "opens its menu: the Task List, Control Panel, the Terminal, Run, Cascade, Tile."),
  ("Switching", "Alt+Tab shows the next window while Alt is held; Ctrl+Esc lists them " &
   "all with the memory each takes. The keyboard bar of Termux:X11 has Alt, Ctrl and Esc."),
  ("Help is near", "F1 in any program opens its Help. Control Panel changes the colors, " &
   "the wallpaper, the sizes and the sounds. Android Files, in Main, shows your phone's files.")]

proc runTour*() =
  applyDesktopLook()
  openApp("Retro Desktop Tour", scaled(560), scaled(420), frame = wfSystem, userFrame = false,
          id = "tour")
  showArt("logo")
  followLook()
  asDialog()
  var page = 0
  while beginFrame():
    let pic = canvas(-1, max(dp(120), ui.h - dp(170)))
    tourPicture(page, pic)
    label(TourPages[page][0], bold = true)
    paragraph TourPages[page][1]
    row:
      label($(page + 1) & " of " & $TourPages.len, enabled = false)
      spring()
      if button("< &Back", enabled = page > 0): dec page
      if page < TourPages.high:
        if button("&Next >", isDefault = true): inc page
      elif button("&Done", isDefault = true): quitApp()
      if button("Cancel") or ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()
