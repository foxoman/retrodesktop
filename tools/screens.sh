#!/bin/sh
# Screenshots of the desktop, for every push (GitHub keeps them with the
# run): the panel's Programs menu, the accessories, Control Panel, Help --
# on a screen of its own (Xvfb), in build/screens/.
#
#   sh tools/screens.sh [the retro-desktop program]
#
# Needs Xvfb, xdotool, xprop and ImageMagick's import.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

set -e
cd "$(dirname "$0")/.."
BIN=${1:-bin/retro-desktop}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
export DISPLAY=:94
export HOME=$PWD/build/screens-home
OUT=$PWD/build/screens
rm -rf "$HOME" "$OUT"; mkdir -p "$HOME/.local/share/retrodesktop" "$OUT"
VERSION=$(sed -n 's/^ *DesktopVersion\* = "\(.*\)".*/\1/p' src/retrodesktop/common.nim)
printf 'welcomed=%s\nreopen=off\nstartProgman=off\n' "$VERSION" > "$HOME/.local/share/retrodesktop/settings.ini"
Xvfb $DISPLAY -screen 0 1280x800x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $DESK $XVFB 2>/dev/null || true' EXIT
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  xprop -root >/dev/null 2>&1 && break
  sleep 0.5
done
"$BIN" &
DESK=$!
sleep 4
shot() { import -window root "$OUT/$1.png"; echo "  $1.png"; }
echo "screenshots:"
# the panel's Programs menu (the Windows key), then a group of it
xdotool key super
sleep 1
shot 1-programs
xdotool key Escape
sleep 0.5
# the accessories, tiled
"$BIN" charmap & "$BIN" calc & "$BIN" calendar & "$BIN" clock &
sleep 4
"$BIN" --retro-command 2
sleep 1
shot 2-accessories
# Control Panel, over them
"$BIN" control &
sleep 3
shot 3-control-panel
# Help
"$BIN" help contents &
sleep 3
shot 4-help
kill -0 $DESK
