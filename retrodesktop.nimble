# Retro Desktop -- a Windows 3.1 style desktop for Linux and Termux (Android)
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

version       = "0.1.4"
author        = "Sultan Al Isaiee (@foxoman)"
description   = "A Windows 3.1 style desktop and window manager for Linux and Termux:X11"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["retrodesktop"]
namedBin["retrodesktop"] = "retro-desktop"

requires "nim >= 2.0.0"
requires "retroui >= 0.20.7"

task deb, "The Termux package for 64-bit ARM: build/retro-desktop_<version>_aarch64.deb":
  exec "sh tools/build-deb.sh"

task desktop, "Build and run the desktop on this computer's X screen":
  exec "nim c -r -d:release -o:bin/retro-desktop src/retrodesktop.nim"
