# Changelog

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
