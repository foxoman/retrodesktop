## System Check and Backup, two of Control Panel's pages.
##
## - System Check: what the desktop's programs need, and whether it is
##   there -- Termux:API (its tools and its app), the sound, mpv, x11vnc, the
##   keyboard's layouts, Android's GPU, the phone's storage, Android's limits
##   on programs started from Termux, memory and storage -- each with what to
##   do: Setup for what is missing, a few words for Android's settings.
## - Backup: the desktop's settings, Program Manager's groups, the desktop's
##   icons, the programs' settings (Communicator, Mail, the others of Retro
##   Nim UI -- never their passwords) and your fonts in one .zip in your
##   downloads; Restore puts one back. For a new phone, or Termux installed
##   again.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils, json, times]
import retroui
import retroui/zip
from retroui/uirelays/services import standardFolder
import common, tasks

type
  CheckState* = enum csOk, csWarn, csMissing, csChecking
  Check* = object
    name*, detail*: string
    state*: CheckState
    install*: string            ## Setup's name for what is missing ("" none)

var
  apiJob, soundJob, sdkJob: Task
  apiState = csChecking
  soundState = csChecking
  sdk = 0

proc startChecks*() =
  ## The checks that take a moment (Termux:API answers through its app, or
  ## not at all when the app is missing: 8 seconds, then no).
  apiState = csChecking
  soundState = csChecking
  if inTermux() and findExe("termux-battery-status").len > 0:
    apiJob = run("timeout 8 termux-battery-status")
  else:
    apiJob = nil
    apiState = csMissing
  if findExe("pactl").len > 0: soundJob = run("pactl info")
  else:
    soundJob = nil
    soundState = csMissing
  sdkJob = (if inTermux(): run("getprop ro.build.version.sdk") else: nil)

proc stillChecking*(): bool =
  ## Whether a check is still waiting for its answer (the page draws again
  ## when it comes).
  if apiJob != nil and apiJob.check():
    apiState = (if apiJob.code == 0 and apiJob.output.strip.startsWith("{"): csOk else: csWarn)
    apiJob = nil
  if soundJob != nil and soundJob.check():
    soundState = (if soundJob.code == 0: csOk else: csWarn)
    soundJob = nil
  if sdkJob != nil and sdkJob.check():
    try: sdk = parseInt(sdkJob.output.strip) except ValueError: sdk = 0
    sdkJob = nil
  apiJob != nil or soundJob != nil or sdkJob != nil

proc freeOf(path: string): (int64, int64) =
  ## The storage's free and whole bytes where `path` is.
  try:
    let o = execProcess("df -Pk " & quoteShell(path))
    let f = o.splitLines[1].splitWhitespace
    (parseBiggestInt(f[3]) * 1024, parseBiggestInt(f[1]) * 1024)
  except CatchableError: (0'i64, 0'i64)

proc memAvailable(): (int64, int64) =
  try:
    var total, avail = 0'i64
    for line in readFile("/proc/meminfo").splitLines:
      let f = line.splitWhitespace
      if f.len >= 2:
        if f[0] == "MemTotal:": total = parseBiggestInt(f[1]) * 1024
        if f[0] == "MemAvailable:": avail = parseBiggestInt(f[1]) * 1024
    (avail, total)
  except CatchableError: (0'i64, 0'i64)

proc gb(b: int64): string = formatFloat(float(b) / 1024 / 1024 / 1024, ffDecimal, 1) & " GB"

proc checks*(): seq[Check] =
  ## Every check, as it stands now.
  let termux = inTermux()
  let has = proc (exe: string): bool = findExe(exe).len > 0
  if termux:
    result.add Check(name: "Termux:API",
      state: (if not has("termux-battery-status"): csMissing else: apiState),
      detail: (if not has("termux-battery-status"): "Its tools are not installed: the Camera, the Phone Dialer, the Sound Recorder, the battery and Wi-Fi in the panel need them."
               elif apiState == csChecking: "Asking it..."
               elif apiState == csOk: "It answers: the phone's camera, calls, messages, microphone, battery and Wi-Fi can be used."
               else: "Its tools are here but the Termux:API app does not answer: install the app from where Termux came (F-Droid or GitHub), and open it once."),
      install: (if has("termux-battery-status"): "" else: "Termux:API tools"))
  result.add Check(name: "Sound",
    state: (if not has("pactl"): csMissing else: soundState),
    detail: (if not has("pactl"): "PulseAudio is not installed: no sound, no volume in the panel."
             elif soundState == csChecking: "Asking PulseAudio..."
             elif soundState == csOk: "PulseAudio runs: the programs' sound, the volume in the panel."
             else: "PulseAudio is installed but not running: the desktop starts it when it starts; start the desktop again."),
    install: (if has("pactl"): "" else: "Sound"))
  result.add Check(name: "Media Player",
    state: (if has("mpv"): csOk else: csMissing),
    detail: (if has("mpv"): "mpv is here: music and videos play." else: "mpv is not installed: the Media Player and the Sound Recorder's playing need it."),
    install: (if has("mpv"): "" else: "mpv"))
  result.add Check(name: "Keyboard layouts",
    state: (if has("setxkbmap"): csOk else: csWarn),
    detail: (if has("setxkbmap"): "setxkbmap is here: Control Panel > Keyboard's layouts (English, Arabic...) work."
             else: "setxkbmap is not installed: one layout only (Control Panel > Keyboard needs it for more)."),
    install: (if has("setxkbmap"): "" else: "Keyboard layouts"))
  result.add Check(name: "Share Desktop",
    state: (if has("x11vnc"): csOk else: csWarn),
    detail: (if has("x11vnc"): "x11vnc is here: Share Desktop works." else: "x11vnc is not installed: Share Desktop needs it."),
    install: (if has("x11vnc"): "" else: "Share Desktop"))
  if termux:
    let gpu = has("virgl_test_server_android")
    result.add Check(name: "3D graphics",
      state: (if gpu: csOk else: csWarn),
      detail: (if gpu: "VirGL is here: 3D programs use Android's GPU." else: "Without VirGL, 3D programs draw with the CPU (slowly)."),
      install: (if gpu: "" else: "3D graphics"))
    let storage = dirExists(getHomeDir() / "storage" / "shared")
    result.add Check(name: "The phone's storage",
      state: (if storage: csOk else: csWarn),
      detail: (if storage: "~/storage reaches the phone's photos, downloads and documents."
               else: "Not reached yet: run termux-setup-storage in the Terminal, and allow it."))
    if sdk >= 31:
      result.add Check(name: "Android's limit on programs", state: csWarn,
        detail: "Android " & (if sdk >= 34: "14" elif sdk >= 33: "13" else: "12") &
          " may stop programs started from Termux beyond a few: Developer options > \"Disable child process restrictions\" " &
          "(Android 14), or from a computer: adb shell settings put global settings_enable_monitor_phantom_procs false.")
    result.add Check(name: "Termux:X11's keyboard", state: csWarn,
      detail: "With a keyboard, in Termux:X11's preferences: Keyboard > \"Enable Accessibility service for intercepting system shortcuts manually\" (then Termux:X11's service on: Alt+Tab and the Windows key reach the desktop), \"Prefer scancodes when possible\" (the layouts type right); Other > \"Clipboard sharing\" on.")
  let (avail, total) = memAvailable()
  if total > 0:
    result.add Check(name: "Memory",
      state: (if avail * 8 < total: csWarn else: csOk),
      detail: gb(avail) & " free of " & gb(total) & (if avail * 8 < total: ": close programs you do not use." else: "."))
  let (free, whole) = freeOf(getHomeDir())
  if whole > 0:
    result.add Check(name: "Storage",
      state: (if free < 1024'i64 * 1024 * 1024: csWarn else: csOk),
      detail: gb(free) & " free of " & gb(whole) & (if free < 1024'i64 * 1024 * 1024: ": Disk Space shows what fills it." else: "."))

# ---- Backup and Restore -------------------------------------------------------------------------

const BackupApps = ["retrodesktop", "retrodesktop-progman", "retrodesktop-icons", "retro-communicator",
                    "retro-mail", "retro-files", "retro-board", "retro-photo", "retro-notepad"]
  ## The settings kept: the desktop's, and the programs' (their settings
  ## files only: never a password, a token, a message).

proc backupFolder*(): string =
  ## Where a backup goes: the phone's downloads, else ~/Downloads, else home.
  for d in [getHomeDir() / "storage" / "downloads", standardFolder("downloads"), getHomeDir()]:
    if d.len > 0 and dirExists(d): return d
  getHomeDir()

proc deskFolder(): string =
  result = standardFolder("desktop")
  if result.len == 0: result = getHomeDir() / "Desktop"

proc settingsFiles(): seq[(string, string)] =
  ## Each file to keep: its place in the backup, its place here.
  for app in BackupApps:
    let dir = dataDir(app)
    for name in ["settings.ini", "settings"]:
      if fileExists(dir / name): result.add ("settings/" & app & "/" & name, dir / name)
  let desk = deskFolder()
  if dirExists(desk):
    for kind, p in walkDir(desk):
      if kind == pcFile and p.endsWith(".desktop"): result.add ("desktop/" & p.extractFilename, p)
  let fonts = fontsFolder()
  if dirExists(fonts):
    for kind, p in walkDir(fonts):
      if kind == pcFile and p.splitFile.ext.toLowerAscii in [".ttf", ".otf"]:
        result.add ("fonts/" & p.extractFilename, p)

proc makeBackup*(): string =
  ## A backup made; its file (raises on failure).
  var z = newZipWriter()
  var list: seq[string]
  for (inZip, here) in settingsFiles():
    z.addFile(inZip, readFile(here))
    list.add inZip
  z.addFile("retro-desktop-backup.json", $(%*{"version": DesktopVersion, "made": $now(), "files": list}))
  result = backupFolder() / "retro-desktop-backup-" & now().format("yyyyMMdd'-'HHmm") & ".zip"
  writeFile(result, z.finish())

proc restoreBackup*(file: string): int =
  ## A backup put back; how many files (raises when it is not one).
  let entries = zipEntries(file)
  var isOne = false
  for e in entries:
    if e.name == "retro-desktop-backup.json": isOne = true
  if not isOne: raise newException(ValueError, "this is not a backup of Retro Desktop")
  for e in entries:
    let parts = e.name.split('/')
    var dest = ""
    if parts.len == 3 and parts[0] == "settings" and parts[1] in BackupApps and parts[2] in ["settings.ini", "settings"]:
      dest = dataDir(parts[1]) / parts[2]
    elif parts.len == 2 and parts[0] == "desktop" and parts[1].endsWith(".desktop") and "/" notin parts[1]:
      dest = deskFolder() / parts[1]
    elif parts.len == 2 and parts[0] == "fonts" and parts[1].splitFile.ext.toLowerAscii in [".ttf", ".otf"]:
      dest = fontsFolder() / parts[1]
    if dest.len == 0: continue
    createDir(dest.parentDir)
    writeFile(dest, readEntry(file, e))
    inc result
