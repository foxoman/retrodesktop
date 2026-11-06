# Retro Desktop

A Windows 3.1 style desktop for Linux -- made first for **Termux on
Android** (Termux:X11), so a phone or a tablet has a whole desktop: every
X11 program in a 3.1 window, Program Manager with the programs you
install, and the small programs a desktop comes with.

![Retro Desktop](docs/desktop.png)

I made it with my own toolkit, [Retro Nim UI](https://github.com/foxoman/retroui):
one program of about 5 MB, nothing to set up.

## What is in it

- **The window manager.** Every program's window gets the 3.1 frame: the
  title bar to move it by, the border and the corners to size it by, the
  control-menu box (Restore, Minimize, Maximize, Close, Switch To), the
  minimize and maximize buttons. Minimized windows are icons along the
  bottom of the desktop. Click to bring a window to the front, Alt+Tab to
  go through them, Alt+F4 to close one. Dialogs open over their windows,
  programs that go full screen (videos, games) get the whole screen, and
  the windows follow when the tablet turns.
- **Program Manager**, with the groups 3.1 had -- Main, Accessories,
  StartUp -- and a group for each kind of program you install: Internet,
  Office, Development, Graphics, Multimedia, System, Games. Every program
  installed with a desktop entry is there by itself (Firefox, VS Code,
  GIMP, LibreOffice...). File > New puts in programs of your own; StartUp
  starts them with the desktop.
- **The accessories:** Clock, Calculator, Calendar (with appointments and
  notes), Cardfile, Task List (Ctrl+Esc: every window and the memory its
  program takes; End Task ends one that hangs), Control Panel.
- **From Retro Nim UI's examples:** File Manager (Retro Files), Paintbrush
  (Retro Photo), Board (Retro Board), Notepad.
- **The same look for the other programs.** GTK programs (and Chromium,
  Electron, Firefox) get the color scheme as a "Retro31" GTK theme, the
  desktop's fonts (GNU FreeFont) and its size; Qt and older X programs get
  the size and the fonts. Control Panel changes the scheme, the fonts, the
  text size and the size of everything, and every program of the desktop
  follows at once.
- **Made for phones and tablets.** The size follows the screen's density
  (a 2K tablet is not tiny); frames for fingers (taller title bars, wider
  borders, icons that open with one tap); hold a finger on a title bar for
  its menu; windows that open maximized on a phone's screen; Termux kept
  awake (termux-wake-lock); the memory watched -- when the phone runs
  short the desktop lets its caches go and says so, and Task List shows
  which program holds what. At rest the desktop takes no CPU and about
  20 MB; Clock, Calculator and the others about 13 MB each.

![Frames for fingers, at 150 %](docs/tablet.png)

## Install it in Termux

1. Install **Termux** and **Termux:X11** (the app: from
   [its releases](https://github.com/termux/termux-x11/releases)).
2. In Termux:

   ```sh
   pkg install x11-repo
   pkg install termux-x11-nightly libx11
   apt install ./retro-desktop_0.1.0_aarch64.deb     # the .deb from the releases
   retro-desktop
   ```

`retro-desktop` starts the X server when none runs, brings Termux:X11 to
the front, and the desktop fills its screen. Install programs as you
always do (`pkg install firefox xfce4-terminal`...): Program Manager shows
them (Options > Refresh, F5).

### So Android lets it run

Android stops programs it thinks you do not use. For a desktop that stays:

- **Termux awake:** the desktop holds Termux's wake lock while it runs
  (Control Panel > Desktop to turn it off).
- **Battery:** Settings > Apps > Termux > Battery > *Unrestricted* (and the
  same for Termux:X11).
- **The phantom process killer** (Android 12 and later stops programs
  started from Termux beyond a few): Developer options > *Disable child
  process restrictions* (Android 14), or from a computer with adb:
  `adb shell "settings put global settings_enable_monitor_phantom_procs false"`.

### Termux:X11's preferences

- *Display resolution mode:* native -- sharp text at the screen's own pixels.
- *Touchscreen input mode:* Direct touch (tap where you point) or Trackpad
  (a pointer you move).
- *Show additional keyboard:* Esc, Ctrl, Alt, Tab -- for Alt+Tab and the rest.
- *Fullscreen on device display* and *Hide display cutout*, for all of the screen.

## Using it

| Keys | What they do |
|---|---|
| Alt+Tab | the window behind to the front (again, quickly: the ones behind it) |
| Alt+Shift+Tab | the other way |
| Alt+F4 | closes the window in front |
| Alt+Esc | minimizes it |
| Ctrl+Esc | Task List |

A right click on the desktop (a finger held on it) opens its menu: Program
Manager, Task List, Control Panel, Run..., Cascade, Tile, Arrange Icons,
Exit. Double click a title bar to maximize a window; double click its
control-menu box to close it.

Every part is also a command: `retro-desktop progman`, `control`,
`tasklist`, `clock`, `calc`, `calendar`, `cardfile`.

## On a Linux computer

It runs on any X screen with no window manager: from a text console
(`startx $(which retro-desktop)`, or `exec retro-desktop` in `~/.xinitrc`),
or in a window of your own desktop with Xephyr:

```sh
Xephyr :2 -screen 1280x800 & DISPLAY=:2 retro-desktop
```

## Building it

You need [Nim](https://nim-lang.org) 2.2 or later and
[Retro Nim UI](https://github.com/foxoman/retroui) 0.20.6 or later.

```sh
nimble install retroui
nimble build -d:release                 # bin/retro-desktop for this computer
```

The Termux package (`build/retro-desktop_<version>_aarch64.deb`) with the
programs from Retro Nim UI's examples:

```sh
sh tools/build-deb.sh
```

In Termux it builds on the phone (`pkg install nim clang git`); on Linux
it cross-builds for 64-bit ARM with the Android NDK (`ANDROID_NDK_HOME`) or
clang with lld and an Android sysroot (`tools/termux-cc.sh`). It uses the
Retro Nim UI checkout next to this one (`../retro`), `RETROUI_SRC`, or
clones it.

GitHub builds the package on every push and pull request
(`.github/workflows/deb.yml`), and puts it on the release when a version
tag is pushed (`git tag v0.1.0 && git push origin v0.1.0`).

## How it works

Retro Desktop is one Nim program. Started with no argument it is the
desktop: a Retro Nim UI window that fills the screen, under every other
window, and the window manager on the same X connection (Retro Nim UI's
X11 driver hands it the events of the windows it manages). Each frame is
an X window: its border drawn with plain X, its title bar drawn with the
toolkit's canvas in the toolkit's fonts and colors. The other parts --
Program Manager, the accessories, Control Panel -- are the same program
started again with an argument, each its own window in its own frame.

The look reaches other programs through what their toolkits read:
XSETTINGS (the desktop is the screen's XSETTINGS manager), the X
resources on the root window (Xft.dpi, fonts), fontconfig, and GTK 3's
settings file and a GTK theme written from the color scheme.

## Credits

Developed by Sultan Al Isaiee @foxoman -- [www.foxoman.net](https://www.foxoman.net) --
sultan@foxoman.net

MIT License (see `LICENSE`).
