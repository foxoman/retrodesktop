# Changelog

## 0.1.6

- **Sounds**: chimes of the desktop's own (made from sine waves the first
  time, no recordings) for its start and exit, programs opening and closing,
  minimize, maximize, restore, notifications; Control Panel > Sound chooses
  them (or a file of yours). Played through PulseAudio, else Termux:API.
- **Wallpapers and colors**: nine pixel-art wallpapers drawn by the desktop
  (Control Panel > Desktop > Wallpaper), and nine more color schemes,
  Sunlight among them for a phone outdoors.
- **DOS games**: with DOSBox-X installed, Program Manager's DOS group shows
  what is in ~/DOS (a game a folder), started in DOSBox-X with ~/DOS as C:.
- **Freedoom** in Setup: Chocolate Doom and Freedoom's two games, their
  levels downloaded from Freedoom's GitHub releases; in the Games group.
- **Android's Back** (XF86Back) closes the window in front.
- **Android Files** in Main: the phone's shared storage in File Manager;
  the first time, termux-setup-storage asks Android.
- **Notifications**: the desktop's own `notify-send` (first on its programs'
  PATH) gives Android notifications with Termux:API, else a box at the
  bottom right of the screen.
- **Help**: F1 and Help > Help Topics in every program open its page (Help,
  with links between pages, Contents and Back); the Welcome offers a tour
  of six pages with pictures.
- **Programs paused while minimized** (Control Panel > Windows, off at
  first): SIGSTOP for the program and its children when all its windows are
  icons, SIGCONT when one comes back, when it is closed, when the desktop
  ends; a desktop that crashed leaves them written down and the next start
  lets them go on.
- **3D through Android's GPU**: Setup > System > 3D graphics installs
  VirGL; the desktop starts its server and tells programs to use it
  (Control Panel > Linux Programs to turn it off).
- **A quicker start**: Program Manager first, StartUp and the programs to
  reopen once it is there.
- Control Panel opens larger; Setup's list knows Freedoom and 3D graphics.
- Needs Retro Nim UI 0.20.8 (Retro Files opens the folder it is given).
## 0.1.5

- **Setup**, as Windows 3.1's: the blue screen, the programs to choose in
  groups (Internet, Office, Development, Graphics, Multimedia, Games,
  System, Fonts -- every name checked against Termux's repositories), the
  space required and available, a gauge while they install, and Termux's
  apt underneath (its status read as it works; x11-repo added first when a
  program needs it, the lists read when they are old). Clear a program to
  remove it. Programs for the Terminal get a Program Manager item.
  `retro-desktop setup gimp` asks for one at once. On Linux it shows the
  command to run with the administrator.
- **Retro Browser installs Firefox** through Setup when Firefox is not
  there, then starts. Web Browser is always in Main; Setup is there too.
- **The desktop's Run, About, Exit and Welcome are windows of their own**,
  over the other windows (the desktop no longer comes over every window
  while one is open). Run remembers its command lines and can run one in
  the Terminal.
- **Alt+Tab as 3.1 had it**: holding Alt, a box with the next window's icon
  and title; Tab again goes on; letting go of Alt goes there.
- **Windows snap** to the screen's edges and to the other windows as you
  move them.
- **The programs open when the desktop ended open again**, where their
  windows were (Control Panel > Desktop to stop it): after Exit, or when
  Android stopped Termux.
- **Games**: Minesweeper (best times), Solitaire (Klondike, draw one or
  three, undo, three card backs, the bouncing cards) and Reversi (four
  levels, hints), for a mouse and a finger.
- **Write**, a word processor on Retro Nim UI's rich text editor (HTML or
  plain text); **Clipboard Viewer** (Android's clipboard with Termux:API).
- **Open**: files and links from the desktop's programs (its own
  `xdg-open`) go to the program for their kind, or the Open With box.
- **Control Panel**: Date/Time (12 or 24 hours, the time zone for the
  desktop's programs) and Screen Saver (Blank Screen, Starfield, Mystify,
  Marquee, after a delay; it needs libxss, now in the package's Depends).
- **The Terminal draws letters FreeMono lacks** from FreeSans and FreeSerif
  (arrows, check marks, stars, music, Greek, Cyrillic...) in their cells.
- **Faster, truer**: Program Manager keeps the icons it drew; Task List
  shows each program's own share of memory (Pss), not memory it shares.
- The desktop's own windows have their icons (minimized, in Alt+Tab).
- PulseAudio, when installed, is started with the desktop.
## 0.1.4

- **Fixed: the desktop's menu opened under the windows.** The desktop is
  under every window, and its menu was drawn on it; the menu (and the menu
  of a minimized window's icon) is now a window of its own, over all of
  them, as the control menu is.
- **Menus as 3.1 had them**: the underlined letter chooses an item, Up and
  Down move, Enter chooses, Esc closes; a right click let go where it was
  pressed leaves the menu open, pressed, moved to an item and let go picks
  it.
- **Fixed: the Terminal's About box and its menus did not close or
  answer.** The Terminal's screen took the clicks meant for them.
- **The Terminal opens in Windows' colors** (black on white); MS-DOS
  Prompt's gray on black is in Settings.
- Run's and Cardfile's Go To prompts showed a stray "&".
## 0.1.3

- **Retro Browser** (Program Manager > Main > Web Browser, `retro-desktop
  browser`): Firefox dressed as a 3.1 program -- gray toolbars, square
  raised buttons, tabs like 3.1 buttons, a sunken address field, 3.1 menus,
  the menu bar shown, FreeSans, the desktop's color scheme, no title bar of
  its own (the desktop's frame). It runs on a profile of its own
  (`~/.local/share/retrodesktop/browser`): the user's Firefox and its
  profile stay as they are. Fewer content processes and tabs let go when
  memory runs short, for phones. Without Firefox it says how to install it.
- **Cursors in the 3.1 shapes, at the screen's size**: the arrow, the
  I-beam, the hourglass, the hand, the cross, the sizing arrows -- crisp, a
  pixel of the drawing a square of the screen's scale. The desktop and its
  programs draw them (Retro Nim UI 0.20.7); other programs (GTK, Qt,
  Firefox) get them as the cursor theme "Retro31" (`~/.icons`), at the same
  size.
- **Scroll bars always there, with their arrow buttons**, as in 3.1: in GTK
  programs (the Retro31 theme, no overlay scroll bars) and in Retro
  Browser.
- **Program Manager sees programs installed or removed while it runs**
  (Firefox appears in Internet a few seconds after `pkg install firefox`).
- Needs Retro Nim UI 0.20.7.

## 0.1.2

- **A desktop that hangs is replaced.** `retro-desktop` asks the desktop
  that runs whether it answers (`_RETRO_DESKTOP` 7, a ping); when it does
  not within two seconds -- hung after a crash -- it is ended and the new
  desktop takes its programs' windows, framed again, with no second
  Program Manager and StartUp not run again.
- **A crash ends the desktop at once** (no stack trace that could hang on a
  broken heap, as 0.1.0's Cascade crash hung on Android): the X server gives
  the windows back to the screen, and the next start takes them.
- **Fixed: windows a desktop takes over were let go at once.** X tells of
  the unmapping when a shown window is put into its frame twice (to the
  window, and to the root); only a program's own unmapping counts now.
- What goes wrong is kept in `~/.local/share/retrodesktop/desktop.log`.

## 0.1.1

- **Terminal**, the desktop's own: a shell in a window in a PC's 16 text
  colors (MS-DOS Prompt's gray on black, or black on white), chunky bold
  letters, the line-drawing characters drawn whole. xterm's escape
  sequences for full-screen programs (vim, nano, htop, mc, less, top), 256
  and 24-bit colors, mouse reports, bracketed paste; a scrollback (the
  wheel, Shift+PgUp); selecting with the mouse (a double click: a word),
  Ctrl+Shift+C and Ctrl+Shift+V. It takes no CPU while nothing happens. In
  Program Manager's Main group and the desktop's menu, and programs whose
  desktop entry asks for a terminal open in it (`retro-desktop terminal -e
  command`).
- **Fixed: Cascade ended the desktop** (the windows were reordered while
  they were walked; a window's record was freed under it). Tile, closing all
  the windows and the rest walk a copy now.
- **Fixed: everything small on a 2K tablet.** The window frames and the dpi
  other programs are told now count the toolkit's pixel zoom: frames, title
  bars and every program at the screen's own size. The X resources an
  earlier desktop left on the server (its dpi) are cleared when the desktop
  starts, so they are not taken for the screen's.
- **Fixed: starting again after a desktop that ended** stopped with
  BadWindow (its check window was gone); Task List no longer stops when a
  window closes while it reads the list.
- Termux is kept awake from the moment the desktop starts (before, only
  after the welcome): without it Android pauses Termux behind Termux:X11
  and Termux:X11 says "X server stalled".
- Windows of the desktop's programs open as large as the size chosen in
  Control Panel; `retro-desktop --retro-command n` for scripts.

## 0.1.0

The first release: a Windows 3.1 style desktop for Termux on Android
(Termux:X11) and any Linux X screen.

- **The window manager**, on the desktop's own X connection: every
  program's window in a 3.1 frame -- title bar (drawn in Retro Nim UI's
  fonts and colors), control-menu box with its menu (Restore, Minimize,
  Maximize, Close, Switch To; a double click closes), minimize and
  maximize buttons, the sizing border and its corners. Click to focus (the
  click goes on to the program), Alt+Tab and Alt+Shift+Tab through the
  windows, Alt+F4, Alt+Esc, Ctrl+Esc. Dialogs over their windows, windows
  placed where their programs ask, a cascade for the rest; full screen
  programs; maximized windows and the screen turning; EWMH and ICCCM for
  the programs and panels that ask (_NET_ACTIVE_WINDOW, _NET_CLOSE_WINDOW,
  _NET_WM_STATE, _NET_CLIENT_LIST, _NET_FRAME_EXTENTS, WM_DELETE_WINDOW,
  WM_TAKE_FOCUS, WM_CHANGE_STATE). Windows minimized are icons on the
  desktop (the program's own icon when it has one).
- **The desktop:** its color, the 3.1 patterns, a wallpaper (fill, center,
  tile, stretch), its menu (a right click, a finger held), Run..., Cascade,
  Tile, Arrange Icons, Exit (programs asked to close first). A welcome the
  first time, with what Android needs to keep it running.
- **Program Manager:** Main, Accessories, StartUp and a group for each kind
  of installed program (desktop entries, their icons from the icon
  themes); File > New, Delete, Properties, Run; Minimize on Use; the
  groups' windows kept where they were; Read Me.
- **Clock** (analog, digital, seconds, date), **Calculator** (memory,
  percent, square root, the keyboard, copy and paste), **Calendar** (a
  day's appointments by the hour, notes, what comes next), **Cardfile**,
  **Task List** (the memory each program holds; End Task, ending a program
  that hangs), **Control Panel** (Color, Desktop, Fonts, Windows, Linux
  Programs, Android, About).
- **The look for other programs:** the XSETTINGS manager (GTK, Chromium,
  Electron), the X resources (Xft.dpi, fonts, colors), fontconfig aliases
  to GNU FreeFont, a "Retro31" GTK 3 theme from the color scheme, GTK 3's
  settings file (left alone when it is the user's own). A change in Control
  Panel reaches every program of the desktop at once.
- **Android:** the size from the screen's density, frames for fingers
  (taller title bars, wider borders, icons that open with one tap, a finger
  held on a title bar for its menu), windows that open maximized on a
  phone's screen, termux-wake-lock while it runs, the memory watched (the
  caches let go, a warning when the phone runs short).
- **The Termux package** (`tools/build-deb.sh`, GitHub's
  `.github/workflows/deb.yml`): retro-desktop with File Manager (Retro
  Files), Paintbrush (Retro Photo), Board (Retro Board) and Notepad from
  Retro Nim UI's examples, for 64-bit ARM.
