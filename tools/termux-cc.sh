#!/bin/sh
# The C compiler and linker for Termux programs on 64-bit ARM (aarch64),
# for Nim's --clang.exe / --clang.linkerexe: the Android NDK's clang when
# there is one ($ANDROID_NDK_HOME, $ANDROID_NDK_LATEST_HOME, $ANDROID_NDK),
# else this computer's clang with lld and an Android sysroot
# ($ANDROID_SYSROOT: a folder with usr/include and usr/lib, as the NDK's
# sysroot; Retro Nim UI's retroapk keeps one in ~/.retro/android-sysroot).
#
# A Termux program is an Android program (bionic, the Android linker) that
# finds Termux's libraries: its RUNPATH is Termux's lib folder.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

API=24
TARGET=aarch64-linux-android$API
TERMUX_LIB=/data/data/com.termux/files/usr/lib

linking=1
for a in "$@"; do
  case "$a" in
    -c|-S|-E) linking=0 ;;
  esac
done

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-$ANDROID_NDK}}"
if [ -n "$NDK" ] && [ -d "$NDK/toolchains/llvm/prebuilt" ]; then
  BIN=$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin | head -n 1)
  CC="$BIN/$TARGET-clang"
  if [ $linking = 0 ]; then exec "$CC" "$@"; fi
  exec "$CC" -pie "$@" -lm -ldl \
    -Wl,-rpath=$TERMUX_LIB -Wl,--enable-new-dtags -Wl,--gc-sections
fi

SR="$ANDROID_SYSROOT"
if [ -z "$SR" ]; then
  SR=$(ls -d "$HOME"/.retro/android-sysroot/api$API-* 2>/dev/null | head -n 1)
fi
if [ -z "$SR" ] || [ ! -d "$SR/usr/include" ]; then
  echo "termux-cc: no Android NDK and no sysroot (set ANDROID_NDK_HOME or ANDROID_SYSROOT)" >&2
  exit 1
fi
LIB="$SR/usr/lib/aarch64-linux-android"
if [ $linking = 0 ]; then
  exec clang --target=$TARGET --sysroot="$SR" "$@"
fi
exec clang --target=$TARGET --sysroot="$SR" -fuse-ld=lld -nostdlib -pie \
  "$LIB/$API/crtbegin_dynamic.o" "$@" \
  -L"$LIB/$API" -lc -lm -ldl "$LIB/libclang_rt.builtins-aarch64-android.a" \
  "$LIB/$API/crtend_android.o" \
  -Wl,-dynamic-linker,/system/bin/linker64 \
  -Wl,-rpath=$TERMUX_LIB -Wl,--enable-new-dtags -Wl,--gc-sections
