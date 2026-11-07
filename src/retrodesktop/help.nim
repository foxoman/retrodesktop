## Help, as 3.1's: a window of topics with links between them, opened by F1
## (or Help > Help Topics) in every program of the desktop at that program's
## page -- and the tour the first start offers, a few pages with pictures.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retroui
import common, link, art, helpar

const Topics* = [
  ("contents", "Contents", """
# Retro Desktop Help

Choose a topic:

* [Using the desktop](topic:desktop) -- windows, the mouse and the finger
* [Keys](topic:keys) and [the keyboard](topic:keyboard) -- shortcuts, English and Arabic
* [Program Manager](topic:progman) and [Setup](topic:setup)
* [Terminal](topic:terminal) and [Retro Browser](topic:browser)
* [The panel](topic:panel) and [icons on the desktop](topic:icons)
* [Write](topic:write), [Clipboard Viewer](topic:clipboard), [Character Map](topic:charmap)
* [Picture Viewer](topic:pictures), [PDF Reader](topic:pdf), [Media Player](topic:media),
  [Sound Recorder](topic:recorder)
* [Communicator](topic:communicator), [News Reader](topic:news), [Share Desktop](topic:share)
* [Camera](topic:camera), [Phone Dialer](topic:dialer), [Disk Space](topic:diskspace)
* [Clock](topic:clock), [Calculator](topic:calc), [Calendar](topic:calendar), [Cardfile](topic:cardfile)
* [Task List](topic:tasklist), [Control Panel](topic:control)
* [Minesweeper](topic:mines), [Solitaire](topic:solitaire), [Reversi](topic:reversi)
* [DOS games](topic:dos)
* [Android and Termux](topic:android), [Android apps](topic:androidapps)
* [When a program fails](topic:crash)
"""),
  ("desktop", "Using the desktop", """
# Using the desktop

Every program opens in its own window.

* **Move** a window by its title bar; **size** it by its border or a corner.
  Near an edge of the screen or of another window it snaps against it.
* The **minimize** button (the arrow down) puts it away: a button on the
  [panel](topic:panel) (or, with the panel off, an icon at the bottom of the
  desktop: double click it -- tap it -- to bring it back).
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
| Win | the panel's Programs menu (Program Manager with the panel off) |
| Win+R, Win+E, Win+I | Run, File Manager, Control Panel |
| Win+Left, Win+Right | the window on the left or right half of the screen (again: back) |
| Win+Up, Win+Down | maximize; restore or minimize |
| Win+D | every window minimized (again: back) |
| Win+L | locks the screen (the screen saver; its password when it has one) |
| Ctrl+Alt+T | Terminal |
| Ctrl+Shift+Esc | Task List |
| Alt+Shift | the next keyboard layout (English, Arabic...) |
| F1 | Help, at the page of the program in front |
| Android's Back | closes the window in front -- when Control Panel > Windows says so, and Termux:X11 sends it as Back |
| Ctrl+Shift+C, V | copy and paste in the Terminal |

Control Panel > Keyboard changes the shortcuts: [the keyboard](topic:keyboard).
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
* **File > Put on the Desktop** (or a right click on a program) makes an icon
  for it on the desktop: [icons on the desktop](topic:icons).

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

**Updates:** Setup asks GitHub whether a newer Retro Desktop is out; when one
is, it says so at the top, and **Update Now** downloads it and installs it
(start the desktop again after). The desktop asks once a week by itself and
sends a notification.

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
Documents are kept as **Word documents** (.docx: Word, LibreOffice and Google
Docs open them), as HTML (a browser opens them) or as plain text (.txt); Write
opens all three, and a .docx from anywhere: its headings, lists, links and
tables come in (a table as lines, its cells between bars). Arabic paragraphs
stay right to left in Word. Ctrl+Z undoes. [Contents](topic:contents)
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
chooses 12 or 24 hours and the time zone, and shows the **Hijri date** under
the other. [Contents](topic:contents)
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
write in it; Show goes to today or another date. With the Hijri date on
(Control Panel > Date/Time), the day shows it too. [Contents](topic:contents)
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

* **Color**: the color scheme of every window (and of GTK programs); night
  colors: another scheme between two hours (Dark, OLED Black...), the day's after.
* **Desktop**: its color, pattern and wallpaper (pictures of yours, or the
  desktop's own), Termux kept awake, the programs reopened.
* **Fonts**: the font -- one of yours too: Add a Font takes a .ttf or .otf
  into your fonts folder, where every program finds it -- the text size, the
  size of everything.
* **Windows**: frames for fingers, the [panel](topic:panel), windows that
  open maximized, programs paused while minimized (no CPU, no battery), and
  in Termux whether Android's Back key closes the window in front (off at
  first: Termux:X11 uses Back for its keyboard).
* **Date/Time**: 12 or 24 hours, the time zone, and the **Hijri date** beside
  the other (Clock, Calendar); Adjust moves it a day or two, where the month
  began otherwise by the moon's sighting.
* **Sound**: which chime goes with which event.
* **Screen Saver**: after a delay with nothing done; **Password protected**
  asks for a password before it ends (Win+L starts it now).
* **Linux Programs**: the look given to other programs; 3D through
  Android's GPU (VirGL).
* **International**: the desktop's programs in English or in Arabic (right
  to left: the panel, the menus and Help too).
* **Keyboard**: the layouts and the key that switches them, the shortcuts,
  how fast a held key repeats: [the keyboard](topic:keyboard).
* **System Check**: what the desktop's programs need -- Termux:API, the
  sound, mpv, x11vnc, the layouts, VirGL, the phone's storage -- and whether it
  is there, with **Install** for what is missing.
* **Backup**: the settings, Program Manager's groups, the desktop's icons and
  your fonts in one .zip in your downloads; **Restore** puts one back.
  [Contents](topic:contents)
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
"""),
  ("androidapps", "Android apps", """
# Android apps

Program Manager's **Android** group has the apps you installed on the phone
(the desktop asks Android for them when it starts; they appear the time
after). A double click opens the app on Android, over Termux:X11: come back
to the desktop with Android's recent apps. The phone's own apps (Phone,
Settings...) are not listed. [Contents](topic:contents)
"""),
  ("panel", "The panel", """
# The panel

A bar along the bottom of the screen -- 3.1 had none: it came with Windows
95, and here it wears 3.1's colors.

* **Programs**, at the left: every group of Program Manager in a menu, and
  Run, Help, Control Panel, Task List, Exit.
* A **button for each window**: a click brings it to the front, a click on the
  one in front minimizes it; a right click opens its control menu.
* At the right, the tray: the **keyboard's layout** (EN, ع: a click goes
  to the next), the **volume** (a click for its menu, the wheel up and down),
  **Wi-Fi**, the **notifications** (a bell; a click lists the last ones), the
  battery and the clock (a click opens Clock).

In Arabic it turns right to left: Programs at the right, the tray at the
left. Control Panel > Windows turns it off: the windows minimized are icons at
the bottom of the desktop again, as in 3.1. [Contents](topic:contents)
"""),
  ("icons", "Icons on the desktop", """
# Icons on the desktop

What is in your **Desktop** folder shows on the desktop: folders, files and
programs. Program Manager's **File > Put on the Desktop** puts a program there.

* A double click (a tap with frames for fingers) opens it -- a file in its
  program, a folder in File Manager.
* Drag an icon where you want it: it stays there.
* A right click: Open, Show in File Manager, Remove from the Desktop (a
  program's icon), Arrange Icons. [Contents](topic:contents)
"""),
  ("charmap", "Character Map", """
# Character Map

Letters and symbols you cannot type, to copy into any program: choose the
font and the block (Latin, Greek, Arabic, arrows, mathematics, shapes...).
The character under the pointer shows larger. Click one and **Select** (or a
double click) adds it to the characters to copy; **Copy** takes them to the
clipboard. [Contents](topic:contents)
"""),
  ("pictures", "Picture Viewer", """
# Picture Viewer

Your pictures, as small pictures of a folder (the phone's photos at first, in
Termux). A double click (a tap) shows one large: the arrows (or a tap at the
left or right third) go to the one before or after; Turn rotates it; F5 starts
a slide show. **Set as Wallpaper**, **Edit in Paintbrush**, and in Termux
**Send to Android** (share it with any app). [Contents](topic:contents)
"""),
  ("pdf", "PDF Reader", """
# PDF Reader

Opens PDF documents: the pages one under another; zoom in and out, page
width, Go to Page (Ctrl+G). The documents opened last are in the File menu.
Write and Notepad make PDFs with **File > Print to PDF**. [Contents](topic:contents)
"""),
  ("media", "Media Player", """
# Media Player

Music and videos, played by mpv (Setup > Multimedia > mpv): open files or a
whole folder as the play list; play, pause, the one before and after, the
place in it, the volume. Videos open in a window of their own. The play
list is kept for the next time. [Contents](topic:contents)
"""),
  ("recorder", "Sound Recorder", """
# Sound Recorder

**Record**, **Stop**, play it back. In Termux it records with the phone's
microphone (Termux:API) into Recordings in the phone's storage; on Linux with
PulseAudio or ALSA. The recordings are listed: play one, delete it, or send it
to Android. [Contents](topic:contents)
"""),
  ("camera", "Camera", """
# Camera

Photos with the phone's cameras (Termux:API): choose the camera, **Take
Photo**, and it is shown and kept in the phone's DCIM/Retro folder (the
gallery finds it there). Android asks once to let Termux:API use the camera.
[Contents](topic:contents)
"""),
  ("dialer", "Phone Dialer", """
# Phone Dialer

The phone the desktop runs on, through Termux:API: **Dial** a number (the keys
or the keyboard), your **Contacts**, the **Messages** as conversations (read
one, write an answer), the **Calls** made, received and missed. Android asks
once for each. [Contents](topic:contents)
"""),
  ("news", "News Reader", """
# News Reader

News feeds (RSS and Atom): a few to start with, **Feeds > Add a Feed** for any
site's. Choose a feed, then a story: its words show below; **Read on the
Site** opens it in the browser. F5 reads them again. [Contents](topic:contents)
"""),
  ("diskspace", "Disk Space", """
# Disk Space

How full the storage is, and what fills it: the folders and files of your
home (or the phone's storage, or the programs') by size, measured while you
look. A double click goes into a folder, Up comes back. **Disk > Clean the
Package Cache** lets go of the packages apt kept after installing.
[Contents](topic:contents)
"""),
  ("share", "Share Desktop", """
# Share Desktop

Use this desktop from a computer: install x11vnc (Setup > System), choose a
password and **Share**. On the computer, a VNC viewer (TigerVNC, RealVNC,
Remmina...) connects to the address shown. **Stop Sharing** ends it. Anyone
on the network with the password can see and use the desktop while it is
shared. [Contents](topic:contents)
"""),
  ("keyboard", "The keyboard", """
# The keyboard

**Shortcuts.** The Windows key alone opens the Programs menu; with a key it
does more -- the list is in [Keys](topic:keys). Control Panel > Keyboard >
Shortcuts changes them: choose one, **Change**, then the keys.

**English and Arabic.** Control Panel > Keyboard > Layouts: check the layouts
to type in (English, Arabic, French...) and the keys that switch them
(Alt+Shift at first). The panel shows the one typing now; a click on it goes
to the next. More than one needs Setup > System > Keyboard layouts.

**Repeat.** How long a held key waits, and how fast it repeats then.

**In Termux:X11's preferences** (with a keyboard of its own):

* Keyboard > **Enable Accessibility service for intercepting system
  shortcuts manually**: it opens Android's Accessibility settings; turn on
  Termux:X11's service there. Then Alt+Tab, the Windows key and Ctrl+Esc come
  to the desktop instead of Android. (On Samsung DeX: **Intercept system
  shortcuts**.) Leave **Filter out intercepted Win key** off.
* Keyboard > **Prefer scancodes when possible**: the layouts type right
  (Arabic too).
* Other > **Clipboard sharing** (on at first): what you copy here can be
  pasted in Android's apps, and the other way. (Clipboard Viewer can also get
  or send it, through Termux:API.)

[Contents](topic:contents)
"""),
  ("crash", "When a program fails", """
# When a program fails

When one of the desktop's own programs fails, its window goes and a
**General Protection Fault** box comes, as in 3.1: **Restart** opens it again,
**Details** shows what went wrong, **Copy Details** takes it for a report. All
of it is kept in ~/.local/share/retrodesktop/crashes.log. [Contents](topic:contents)
"""),
  ("communicator", "Communicator", """
# Communicator

Talk to your friends, on XMPP (Jabber): any server, your own account or a new
one made here.

* The **Friends** list: who is there, away or busy, and their notes. A double
  click starts a talk; a right click: Info, Rename, Remove.
* **Add** a friend by their address (name@server); they are asked to accept.
* **Rooms**: talk with many at once.
* Send a picture or a file; set your picture, your name, your away message.

[Contents](topic:contents)
""")]

proc shownTopics(): seq[(string, string, string)] =
  ## The topics in the interface's language (Arabic: each one there is, the
  ## others in English).
  let arabic = desktopSettings().setting("language", "en") == "ar"
  for t in Topics:
    var shown = t
    if arabic:
      for a in TopicsAr:
        if a[0] == t[0]: shown = a
    result.add shown

proc topicIndex(topics: seq[(string, string, string)]; name: string): int =
  for i, t in topics:
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
  let topics = shownTopics()
  var at = topicIndex(topics, topic)
  var back: seq[int]
  while beginFrame():
    let wanted = tr("Help") & " - " & topics[at][1]
    if ui.title != wanted: setTitle(wanted)
    menubar:
      menu "&File":
        if menuItem("E&xit"): quitApp()
      menu "&Topics":
        for i, t in topics:
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
    let ev = markdownView(topics[at][2], key = topics[at][0])
    if ev.link.startsWith("topic:"):
      back.add at
      at = topicIndex(topics, ev.link[6 .. ^1])
    elif ev.link.len > 0: launch(selfCommand("open") & " " & quoteShell(ev.link))
    if ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()

# ---- the tour ---------------------------------------------------------------------------------------

proc miniWindow(r: Rect; named: string; active = true) =
  let title = tr(named)
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

proc callout(x, y: int; said: string) =
  let s = tr(said)
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
      text(m.x + dp(10), y, tr(it), color(0, 0, 0))
      y += lineHeight() + dp(4)
    callout(r.x + dp(8), r.y + r.h - lineHeight() - dp(14), "Right click (hold a finger) on the desktop")
  of 4:
    let b = rect(r.x + r.w div 6, r.y + r.h * 2 div 5, r.w * 2 div 3, dp(56))
    fill(b, color(192, 192, 192))
    box(b, color(0, 0, 0), 2)
    drawBitmap(rect(b.x + dp(12), b.y + (b.h - s) div 2, s, s), appIcon("terminal", px))
    text(b.x + dp(56), b.y + (b.h - lineHeight()) div 2, tr("Terminal"), color(0, 0, 0), true)
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
      label($(page + 1) & " " & tr("of") & " " & $TourPages.len, enabled = false, literal = true)
      spring()
      if button("< &Back", enabled = page > 0): dec page
      if page < TourPages.high:
        if button("&Next >", isDefault = true): inc page
      elif button("&Done", isDefault = true): quitApp()
      if button("Cancel") or ui.key == KeyEsc: quitApp()
    endFrame()
    appFrameDone()
  closeApp()
