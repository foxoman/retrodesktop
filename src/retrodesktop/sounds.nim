## The desktop's sounds: chimes of its own, made here from sine waves (no
## recordings) and kept as WAV files the first time they are needed, played
## through PulseAudio (paplay), else Android itself (termux-media-player,
## with Termux:API), else ALSA (aplay). Control Panel's Sound says which
## chime -- or which file of yours -- goes with which event.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, math, strutils, random]
from std/times import epochTime
import retroui
import common

const
  SoundEvents* = [("start", "Retro Desktop Start", "Chord"),
                  ("exit", "Retro Desktop Exit", "Fall"),
                  ("open", "Open Program", "(None)"),
                  ("close", "Close Program", "(None)"),
                  ("minimize", "Minimize", "(None)"),
                  ("maximize", "Maximize", "(None)"),
                  ("restore", "Restore", "(None)"),
                  ("beep", "Default Beep", "Ding"),
                  ("notify", "Notification", "Chimes")]
    ## (the setting, its name in Control Panel, its chime out of the box)
  Chimes* = ["(None)", "Chord", "Ding", "Chimes", "Rise", "Fall", "Fanfare", "Click", "Pop"]
  Rate = 22050
  Made = "1"                     # (the chimes' version: made again when it changes)

proc soundsDir*(): string = dataDir(SettingsName) / "sounds"

proc note(buf: var seq[float]; at, freq, dur, vol: float; bell = true) =
  ## A note from `at` seconds: a struck bell (its overtones fading faster),
  ## or a plain tone.
  let start = int(at * Rate)
  let n = int(dur * Rate)
  if buf.len < start + n: buf.setLen(start + n)
  for i in 0 ..< n:
    let t = float(i) / Rate
    let env = exp(-t * 4.5 / dur) * min(1.0, t * 300)
    var v = sin(2 * PI * freq * t)
    if bell:
      v = v * 0.6 + sin(2 * PI * freq * 2.0 * t) * 0.25 * exp(-t * 7 / dur) +
          sin(2 * PI * freq * 3.01 * t) * 0.12 * exp(-t * 11 / dur)
    buf[start + i] += v * env * vol

proc hz(midi: int): float = 440.0 * pow(2.0, float(midi - 69) / 12)

proc synth(name: string): seq[float] =
  case name
  of "Chord":
    for k, m in [72, 76, 79, 84]: note(result, float(k) * 0.07, hz(m), 1.8, 0.5)
  of "Ding":
    note(result, 0, hz(88), 0.9, 0.8)
  of "Chimes":
    for k, m in [88, 84, 79]: note(result, float(k) * 0.18, hz(m), 1.1, 0.6)
  of "Rise":
    for k, m in [72, 76, 79, 84]: note(result, float(k) * 0.09, hz(m), 0.55, 0.6)
  of "Fall":
    for k, m in [84, 79, 76, 72]: note(result, float(k) * 0.13, hz(m), 1.0, 0.6)
  of "Fanfare":
    for k, m in [67, 72, 76]: note(result, float(k) * 0.13, hz(m), 0.3, 0.6, bell = false)
    for m in [79, 72, 76]: note(result, 0.42, hz(m), 1.3, 0.45, bell = false)
  of "Click":
    result.setLen(int(0.012 * Rate))
    for i in 0 ..< result.len:
      result[i] = (rand(2.0) - 1.0) * exp(-float(i) / (0.002 * Rate))
  of "Pop":
    let n = int(0.08 * Rate)
    result.setLen(n)
    var ph = 0.0
    for i in 0 ..< n:
      let t = float(i) / float(n)
      ph += 2 * PI * (900 - 600 * t) / Rate
      result[i] = sin(ph) * (1 - t)
  else: discard
  var peak = 0.0
  for v in result: peak = max(peak, abs(v))
  if peak > 0:
    for v in result.mitems: v = v / peak * 0.8

proc wav(samples: seq[float]): string =
  ## 16-bit mono WAV.
  proc le32(s: var string; v: int) =
    for k in 0 .. 3: s.add char((v shr (8 * k)) and 255)
  proc le16(s: var string; v: int) =
    for k in 0 .. 1: s.add char((v shr (8 * k)) and 255)
  let data = samples.len * 2
  result = "RIFF"
  le32(result, 36 + data)
  result.add "WAVEfmt "
  le32(result, 16)
  le16(result, 1)
  le16(result, 1)
  le32(result, Rate)
  le32(result, Rate * 2)
  le16(result, 2)
  le16(result, 16)
  result.add "data"
  le32(result, data)
  for v in samples: le16(result, int(round(clamp(v, -1.0, 1.0) * 32767)) and 0xFFFF)

proc chimeFile*(name: string): string =
  ## The WAV file of the chime `name` (made the first time); "" for none.
  if name notin Chimes or name == "(None)": return ""
  let dir = soundsDir()
  result = dir / name.toLowerAscii & ".wav"
  try:
    let stamp = dir / "made"
    if not fileExists(result) or not fileExists(stamp) or readFile(stamp) != Made:
      createDir(dir)
      for c in Chimes[1 .. ^1]: writeFile(dir / c.toLowerAscii & ".wav", wav(synth(c)))
      writeFile(stamp, Made)
  except CatchableError: result = ""

var lastPlay = 0.0

proc playFile*(path: string) =
  ## `path` played in the background (by whatever plays sound here).
  if path.len == 0 or not fileExists(path): return
  let now = epochTime()
  if now - lastPlay < 0.12: return
  lastPlay = now
  let q = quoteShell(path)
  if findExe("paplay").len > 0: launch("paplay " & q)
  elif findExe("termux-media-player").len > 0: launch("termux-media-player play " & q)
  elif findExe("aplay").len > 0: launch("aplay -q " & q)

proc soundFor*(s: Settings; event: string): string =
  ## The chime's name or the file that goes with `event`.
  var default = "(None)"
  for (key, _, d) in SoundEvents:
    if key == event: default = d
  s.setting("sound." & event, default)

proc playSound*(event: string; s = desktopSettings()) =
  ## The sound of `event` (start, exit, open, close, minimize, maximize,
  ## restore, beep, notify), when sounds are on.
  if s.setting("sounds", "on") == "off": return
  let what = soundFor(s, event)
  if what == "(None)" or what.len == 0: return
  playFile(if what in Chimes: chimeFile(what) else: what)
