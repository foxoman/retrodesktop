# Working on Retro Desktop

Rules for anyone changing this repository -- people and AI coding agents
alike.

## The project

- Retro Desktop, a Windows 3.1 style desktop and window manager for Linux
  and Termux on Android (Termux:X11), by Sultan Al Isaiee (@foxoman) --
  www.foxoman.net -- sultan@foxoman.net. Repository:
  https://github.com/foxoman/retrodesktop
- Made with Retro Nim UI (`retroui`, https://github.com/foxoman/retroui):
  read its `skills/retroui/SKILL.md` before writing UI code.
- `src/retrodesktop.nim` -- the program; its first argument says which
  part it is (none: the desktop; `progman`, `control`, `tasklist`,
  `terminal`, `browser`, `setup`, `write`, `clipboard`, `open`, `mines`,
  `solitaire`, `reversi`, `run`, `about`, `exit`, `welcome`, `saver`,
  `help`, `tour`, `storage`, `notify`, `sound`, `clock`, `calc`, `calendar`,
  `cardfile`, `charmap`, `pictures`, `pdf`, `media`, `recorder`, `camera`,
  `dialer`, `news`, `diskspace`, `share`).
- `src/retrodesktop/`:
  - `wm.nim` -- the window manager (frames, focus, keys, EWMH/ICCCM), on the
    desktop's X connection through Retro Nim UI's `x11EventHook`; its menus
    (cascading: `MenuItem.sub`, 3.1's look, the Start menu's band with
    `big`), the work area (`workInset`, `workRect`, `workChanged`), and
    snapping as Windows 11's (zones of the work area, `layouts()`, the
    preview, Snap Assist, the layouts on the maximize button, `winArrow`;
    the title bars' buttons, Windows 95's or 3.1's, `titleButtons`);
    `tick()` is its timers (a menu opening on a rest, the layouts), called
    from the desktop's frame
  - `session.nim` -- the desktop: background, icons, menu, welcome, exit,
    memory, night colors; a session bus for screen readers where AT-SPI is
    installed and none was started (`startScreenReaders`)
  - `panel.nim` -- the panel, Windows 95's taskbar in 3.1's colors: Start
    and its menu, the windows' buttons, the tray, on any edge (`Edge`),
    rows or a width, auto hide, always on top or not (an override-redirect
    window the manager keeps on top, `wm.onTop`, and leaves room for,
    `wm.workInset`); its settings panelEdge, panelRows, panelWidth,
    panelAutoHide, panelOnTop, startSmallIcons, panelClock
  - `deskicons.nim` -- the icons of the Desktop folder on the desktop (each a
    node for screen readers, as the minimized windows' icons and the
    Terminal's screen are: what is drawn by hand says what it is with
    `accessNode`)
  - `catalog.nim` -- every program in its group, for Program Manager and
    the panel (the desktop's own, DOS, Android, installed, the user's)
  - `charmap.nim`, `viewers.nim` (Picture Viewer, PDF Reader, Camera),
    `players.nim` (Media Player, Sound Recorder), `phone.nim` (Phone
    Dialer), `utilities.nim` (Disk Space, News Reader, Share Desktop) --
    the new accessories
  - `tasks.nim` -- a command run in the background, its output read
    without blocking a frame (Termux:API, apt-get clean...)
  - `ar.nim` -- the desktop's words in Arabic (with retroui's
    `toolkitArabic`; `tr` finds them)
  - `keyboard.nim` -- the layouts (setxkbmap), the repeat (XKB), the
    shortcuts' names and keys at first
  - `syscheck.nim` -- Control Panel's System Check and Backup
  - `updates.nim` -- a newer release on GitHub (a thread of its own)
  - `crash.nim` -- the General Protection Fault box: a signal or an
    uncaught error forks the box, which lets go of the X connection
  - `docx.nim` -- Word documents (.docx) for Write: read into a RichDoc
    (paragraphs, headings, lists, links, tables as lines) and written from
    one (with `w:bidi` for Arabic paragraphs), through retroui/zip
  - `hijri.nim` -- the Hijri date (the tabular calendar, with Control
    Panel's adjust of -2 to 2 days), for Clock, Calendar and Date/Time
  - `helpar.nim` -- Help's topics in Arabic, by the same names as
    `help.nim`'s (a topic missing there shows in English)
  - `progman.nim`, `accessories.nim` (Clock, Calculator, Calendar,
    Cardfile), `control.nim`, `tasklist.nim`, `terminal.nim` -- the programs
  - `vt.nim` -- the Terminal's screen: xterm's escape sequences, no drawing
  - `browser.nim` -- Retro Browser: Firefox's profile with the 3.1
    userChrome.css, user.js
  - `setup.nim` -- Setup: the catalogue of Termux programs (each name
    checked against termux-packages and x11-packages before it goes in),
    apt-get with `APT::Status-Fd` underneath
  - `boxes.nim` -- the desktop's Run, About, Exit, Welcome and Taskbar
    Properties, each a window
  - `games.nim` -- Minesweeper, Solitaire, Reversi
  - `write.nim`, `clipboard.nim` -- Write, Clipboard Viewer
  - `opener.nim` -- `open`: files and links to their program; the desktop's
    own `xdg-open`
  - `saver.nim` -- the screen savers, and the idle time (libXss)
  - `sounds.nim` -- the chimes (synthesized into WAV files) and playing them
  - `help.nim` -- Help's topics (F1 in every program) and the tour
  - `theming.nim` -- the look given to other programs (XSETTINGS, X
    resources, fontconfig, the GTK theme)
  - `link.nim` -- how the programs talk to the desktop (EWMH messages,
    _RETRO_DESKTOP, following the look)
  - `common.nim` -- settings, starting programs, desktop entries, icons,
    the look of now (`currentScheme`: night colors), the language, a
    font file
  - `art.nim` -- the desktop's own icons and patterns, drawn at their size
  - `xlib.nim` -- the Xlib it uses, loaded at run time
- `tools/build-deb.sh` (the Termux package), `tools/termux-cc.sh` (the
  aarch64 compiler for it), `tools/smoke.sh` (a check on Xvfb).

## Rules

1. **Voice.** Docs, comments and messages speak as Sultan to users and
   developers ("I made...", "you can..."), plainly, without marketing.
2. **Credits** stay Sultan's: "Developed by Sultan Al Isaiee @foxoman --
   www.foxoman.net -- sultan@foxoman.net" at the top of each source file and
   in the About boxes.
3. **Keep the docs with the code:** `README.md`, `CHANGELOG.md` (a section
   per version, the newest on top), this file, `llms.txt` change with every
   change that touches what they say.
4. **Check what you change:** build it (`nim c -d:release -o:bin/retro-desktop
   src/retrodesktop.nim`), run `sh tools/smoke.sh`, look at the screen
   (build/smoke.png). For the window manager, try real X programs (xclock,
   xeyes, xcalc, a GTK program) and xdotool clicks.
5. **The X connection is shared** with Retro Nim UI's driver: the hook
   returns false for every event of the desktop's own window and for events
   without a window (the keyboard's, extensions'); the rest are the
   manager's.
6. **Pixels:** the window manager's X windows are in the screen's own pixels
   (`devPx`, `devScale`: the kit's scale times its pixel zoom `pxScale`);
   the kit's drawing is in logical pixels (`dp`). Never walk `clients` while
   something can reorder it (`snapshot()`), and read the properties of
   windows that may be gone inside `trapErrors`. Only a program's own
   unmapping (in its frame, or ICCCM's synthetic one to the root) lets
   go of its window.
   The screen's size is `wm.screenSize()` (the root window's, from its
   ConfigureNotify), never Xlib's `XDisplayWidth` in the desktop's own
   connection: that one keeps the size the connection began with, and
   Termux:X11 changes it after the start.
   The program's own file is `selfPath()` (never `getAppFilename()`: after
   an update it says "... (deleted)"). The manager's key grabs take no
   owner events, so the keys come to the root even when the desktop's own
   window has the focus.
   A closure made in a loop (a menu item's action) sees the loop's last
   values: make each one in a proc of its own (`startItem`, `groupItems` in
   panel.nim).
   Every window can be sized: `Client.fixed` only says it asked for one
   size; a splash window (`splash`) keeps its size and has no buttons.
   Nim's `Socket.send` with its default `SafeDisconn` never ends on a socket
   closed at the other end: send to another program's socket with
   `flags = {}` and treat the error as the program gone (players.nim).
   The desktop is under every window, so whatever has to show over them --
   its menu, the icons' menu, the control menu -- is the manager's
   `showMenu` (a window of its own, the pointer and the keyboard grabbed),
   never the kit's `popupMenu`. A widget drawn over a program's own screen
   (the Terminal's) takes the mouse only when no menu or dialog is open
   (`ui.popup == 0 and ui.dialogTop == 0`).
   The desktop's own dialogs are programs of their own (`boxes.nim`, made
   dialogs with `asDialog`), not dialogs drawn on the desktop.
   Programs Setup offers are checked against Termux's repositories
   (termux-packages: packages/, x11-packages/) before they go in the list.
   Every program of the desktop calls `helpKeys(topic)` each frame and has
   Help > Help Topics; a new program gets a topic in `help.nim`. The art
   (icons, wallpapers, card backs, chimes) is the desktop's own, drawn or
   synthesized in code: nothing copied from Windows.
7. **Android first:** sizes in `dp`, a finger as well as a mouse, nothing
   that keeps the CPU awake when nothing changes (`wakeIn` only as needed),
   memory let go when the phone runs short (`onMemoryPressure`).
8. Retro Desktop's own versions: `DesktopVersion` in
   `src/retrodesktop/common.nim` and `version` in `retrodesktop.nimble`, the
   same.
9. Never commit build output (`build/`, `bin/`, `.deb`).
