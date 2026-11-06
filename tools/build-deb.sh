#!/bin/sh
# The Termux package of Retro Desktop: build/retro-desktop_<version>_aarch64.deb
#
#   sh tools/build-deb.sh
#
# In Termux it builds on the phone itself (pkg install nim clang git); on a
# Linux computer it cross-builds for 64-bit ARM with tools/termux-cc.sh (the
# Android NDK, or clang with an Android sysroot). The package has:
#
#   bin/retro-desktop     the desktop, Program Manager and the accessories
#   bin/retro-files       File Manager (Retro Files)        \
#   bin/retro-board       Board (Retro Board)                | from Retro Nim
#   bin/retro-photo       Paintbrush (Retro Photo)           | UI's examples
#   bin/retro-notepad     Notepad                            |
#   bin/retro-mail        Mail (Retro Mail)                  |
#   bin/retro-communicator Communicator (XMPP)              /
#
# RETROUI_SRC: a Retro Nim UI checkout (default ../retro, else it is cloned
# into build/retroui). RETRO_APPS: which of the programs from the examples
# (default "files board photo notepad mail communicator"; "" for none).
#
# Retro Mail signs in with Microsoft and Google through the app IDs it is
# built with: RETRO_MAIL_MICROSOFT_ID, RETRO_MAIL_GOOGLE_ID and
# RETRO_MAIL_GOOGLE_SECRET in the environment while it builds (CI: from its
# secrets). Without them it asks each user for their own registration. They
# are never written in this repository.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

set -e
cd "$(dirname "$0")/.."
TOP=$PWD
VERSION=$(sed -n 's/^ *DesktopVersion\* = "\(.*\)".*/\1/p' src/retrodesktop/common.nim)
ARCH=aarch64
TERMUX=/data/data/com.termux/files/usr
APPS=${RETRO_APPS-"files board photo notepad mail communicator"}

KIT=${RETROUI_SRC:-}
if [ -z "$KIT" ]; then
  if [ -f ../retro/src/retroui.nim ]; then KIT=$TOP/../retro
  else
    KIT=$TOP/build/retroui
    if [ ! -f "$KIT/src/retroui.nim" ]; then
      git clone --depth 1 https://github.com/foxoman/retroui "$KIT"
    fi
  fi
fi
KIT=$(cd "$KIT" && pwd)

if [ -n "$TERMUX_VERSION" ]; then
  # (on the phone: Termux's own clang)
  CROSS="--cc:clang"
else
  CROSS="--os:android --cpu:arm64 --cc:clang --clang.exe:$TOP/tools/termux-cc.sh --clang.linkerexe:$TOP/tools/termux-cc.sh"
fi
NIMFLAGS="-d:release -d:useMalloc -d:useFork --app:console --passL:-s --hints:off $CROSS"

ROOT=$TOP/build/deb/root
rm -rf "$ROOT"
mkdir -p "$ROOT$TERMUX/bin" "$ROOT$TERMUX/share/doc/retro-desktop" "$ROOT/DEBIAN"

echo "== retro-desktop $VERSION"
nim c $NIMFLAGS --path:"$KIT/src" --nimcache:"$TOP/build/cache-deb/desktop" \
  -o:"$ROOT$TERMUX/bin/retro-desktop" src/retrodesktop.nim

for app in $APPS; do
  case $app in
    files)   src=filemanager.nim; exe=retro-files;   icon=filemanager-icon.png ;;
    board)   src=retroboard.nim;  exe=retro-board;   icon=board-icon.png ;;
    photo)   src=photo.nim;       exe=retro-photo;   icon=photo-icon.png ;;
    notepad) src=notepad.nim;     exe=retro-notepad; icon="" ;;
    mail)    src=mail.nim;        exe=retro-mail;    icon=mail-icon.png
             [ -n "$RETRO_MAIL_GOOGLE_ID$RETRO_MAIL_MICROSOFT_ID" ] ||
               echo "   (no RETRO_MAIL_* app IDs in the environment: Mail will ask for the user's own)" ;;
    communicator) src=communicator.nim; exe=retro-communicator; icon="" ;;
    gallery) src=gallery.nim;     exe=retro-gallery; icon=gallery-icon.png ;;
    *) echo "unknown program: $app"; exit 1 ;;
  esac
  echo "== $exe"
  nim c $NIMFLAGS --nimcache:"$TOP/build/cache-deb/$app" -o:"$ROOT$TERMUX/bin/$exe" "$KIT/examples/$src"
  if [ -n "$icon" ]; then
    mkdir -p "$ROOT$TERMUX/share/icons/hicolor/192x192/apps"
    cp "$KIT/examples/assets/$icon" "$ROOT$TERMUX/share/icons/hicolor/192x192/apps/$exe.png"
  fi
done

cp README.md LICENSE CHANGELOG.md "$ROOT$TERMUX/share/doc/retro-desktop/"
SIZE=$(du -sk "$ROOT$TERMUX" | cut -f1)
cat > "$ROOT/DEBIAN/control" <<CTL
Package: retro-desktop
Version: $VERSION
Architecture: $ARCH
Maintainer: Sultan Al Isaiee <sultan@foxoman.net>
Installed-Size: $SIZE
Depends: libx11, libxss, termux-x11-nightly, libcurl, openssl
Homepage: https://github.com/foxoman/retrodesktop
Description: A Windows 3.1 style desktop for Termux:X11
 Retro Desktop is a desktop and window manager in the style of Windows 3.1
 for Termux on Android (Termux:X11): every X11 program in a 3.1 frame,
 Program Manager with the programs you install, a panel with the Programs
 menu and the windows, icons on the desktop, Setup to install more (pkg
 underneath), Terminal, Write, Character Map, Picture Viewer, PDF Reader,
 Media Player, Sound Recorder, Camera, Phone Dialer, News Reader, Disk
 Space, Share Desktop (VNC), Clock, Calculator, Calendar, Cardfile,
 Clipboard Viewer, Minesweeper, Solitaire, Reversi, a DOS group for
 DOSBox-X, the Android apps, Help on F1, sounds, wallpapers and night
 colors, English or Arabic, Control Panel, Task List, File Manager,
 Paintbrush, Board, Notepad, Mail and Communicator. Start it with:
 retro-desktop
CTL
mkdir -p build
OUT=build/retro-desktop_${VERSION}_$ARCH.deb
dpkg-deb -Zxz --root-owner-group --build "$ROOT" "$OUT"
echo "== $OUT"
dpkg-deb --info "$OUT" | sed -n '1,12p'
