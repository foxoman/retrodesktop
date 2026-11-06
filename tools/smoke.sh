#!/bin/sh
# A quick check of the desktop on a screen of its own (Xvfb): it starts,
# manages an X program's window (xclock), opens Program Manager and the
# accessories, and the screen is saved as build/smoke.png.
#
#   sh tools/smoke.sh [the retro-desktop program]
#
# Needs Xvfb, xclock (x11-apps), xprop and ImageMagick's import.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

set -e
cd "$(dirname "$0")/.."
BIN=${1:-bin/retro-desktop}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
export DISPLAY=:93
export HOME=$PWD/build/smoke-home
rm -rf "$HOME"; mkdir -p "$HOME/.local/share/retrodesktop"
# (welcomed already: Program Manager starts with the desktop)
VERSION=$(sed -n 's/^ *DesktopVersion\* = "\(.*\)".*/\1/p' src/retrodesktop/common.nim)
echo "welcomed=$VERSION" > "$HOME/.local/share/retrodesktop/settings.ini"
Xvfb $DISPLAY -screen 0 1280x800x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $DESK $XVFB 2>/dev/null || true' EXIT
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  xprop -root >/dev/null 2>&1 && break
  sleep 0.5
done
"$BIN" &
DESK=$!
sleep 3
xclock &
sleep 1
"$BIN" clock & "$BIN" calc & "$BIN" calendar & "$BIN" control &
sleep 4
WM=$(xprop -root _NET_SUPPORTING_WM_CHECK | sed 's/.*# //')
NAME=$(xprop -id "$WM" _NET_WM_NAME | sed 's/.*= //')
LIST=$(xprop -root _NET_CLIENT_LIST)
echo "window manager: $NAME"
echo "$LIST"
mkdir -p build
import -window root build/smoke.png
COUNT=$(echo "$LIST" | tr ',' '\n' | grep -c 0x || true)
if [ "$NAME" != '"Retro Desktop"' ] || [ "$COUNT" -lt 6 ]; then
  echo "smoke test failed: $COUNT windows managed"
  exit 1
fi
echo "smoke test passed: $COUNT windows managed"
