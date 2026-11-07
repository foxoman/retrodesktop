## Media Player and Sound Recorder.
##
## - Media Player: music and videos in a playlist, played by mpv (Setup >
##   Multimedia > mpv) and told what to do through its IPC socket: play,
##   pause, stop, the next and the one before, the position, the volume.
##   A video opens in mpv's own window.
## - Sound Recorder: your voice from the phone's microphone (Termux:API's
##   termux-microphone-record), or the computer's (PulseAudio's parecord,
##   ALSA's arecord), kept in Recordings; played back, sent to Android.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils, json, net, times, math, algorithm]
from std/posix import poll, TPollfd, POLLIN
import retroui
import common, link, help, tasks

const MediaExts = [".mp3", ".ogg", ".oga", ".opus", ".flac", ".wav", ".m4a", ".aac", ".wma",
                   ".mp4", ".mkv", ".webm", ".avi", ".mov", ".m4v", ".3gp"]

proc clock(secs: float): string =
  if secs < 0 or secs.isNaN: return "--:--"
  let s = int(secs)
  if s >= 3600: $(s div 3600) & ":" & align($(s mod 3600 div 60), 2, '0') & ":" & align($(s mod 60), 2, '0')
  else: $(s div 60) & ":" & align($(s mod 60), 2, '0')

# ==== Media Player =====================================================================================

type Mpv = object
  p: Process
  sock: Socket
  buf: string
  path: string

proc endLeftOver() =
  ## An mpv a Media Player left when it was killed (its player gone): told
  ## to quit, its socket taken away.
  for kind, p in walkDir(getTempDir()):
    let name = p.extractFilename
    if not name.startsWith("retro-mpv-"): continue
    let pid = try: parseInt(name["retro-mpv-".len .. ^1]) except ValueError: -1
    if pid <= 0 or dirExists("/proc/" & $pid): continue
    var s: Socket
    try:
      s = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP, buffered = false)
      s.connectUnix(p)
      s.send($(%*{"command": ["quit"]}) & "\n")
    except CatchableError: discard
    if s != nil:
      try: s.close() except CatchableError: discard
    try: removeFile(p) except CatchableError: discard

proc start(m: var Mpv): bool =
  let exe = findExe("mpv")
  if exe.len == 0: return false
  endLeftOver()
  m.path = getTempDir() / "retro-mpv-" & $getCurrentProcessId()
  removeFile(m.path)
  var args = @["--idle=yes", "--no-terminal", "--force-window=no", "--input-ipc-server=" & m.path,
               "--title=${media-title} - Media Player",
               # (a song's cover is not shown in a window of its own: the
               # player shows the song)
               "--audio-display=no"]
  # (the picture through EGL on X11 when this mpv has it, else X11's own:
  # left to find one, mpv tried the others first, and one of them closed
  # file 0 again and again -- the X connection, once it was given that
  # number, and mpv ended on the next video)
  let known = try: execProcess(exe, args = ["--gpu-context=help"], options = {poStdErrToStdOut}) &
                   execProcess(exe, args = ["--vo=help"], options = {poStdErrToStdOut})
              except CatchableError: ""
  if "x11egl" in known: args.add "--gpu-context=x11egl"
  if "\n  x11 " in known: args.add "--vo=gpu,x11,"
  m.p = startProcess(exe, args = args, options = {poDaemon})
  # (mpv's socket is not a file: `fileExists` is false for it, so it is
  # only tried until it answers)
  for _ in 0 ..< 50:
    if not m.p.running: break
    var s: Socket
    try:
      s = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP, buffered = false)
      s.connectUnix(m.path)
      m.sock = s
      for (id, prop) in [(1, "time-pos"), (2, "duration"), (3, "pause"), (4, "media-title"),
                         (5, "idle-active"), (6, "volume")]:
        m.sock.send($(%*{"command": ["observe_property", id, prop]}) & "\n")
      return true
    except CatchableError:
      if s != nil:
        try: s.close() except CatchableError: discard
      m.sock = nil
    sleep(100)
  # (it never answered: it goes, and the player says so)
  if m.p != nil:
    m.p.terminate()
    discard m.p.waitForExit(1000)
    m.p.close()
    m.p = nil
  false

proc lose(m: var Mpv) =
  ## mpv went (it ended, or was ended): its socket closed; the player starts
  ## it again.
  if m.sock != nil:
    try: m.sock.close() except CatchableError: discard
    m.sock = nil

proc cmd(m: var Mpv; args: JsonNode) =
  if m.sock != nil:
    # (no SafeDisconn: with it Nim's send took a socket mpv had closed for
    # one that only waits, and tried again forever -- the player hung)
    try: m.sock.send($(%*{"command": args}) & "\n", flags = {})
    except CatchableError: m.lose()

proc events(m: var Mpv): seq[JsonNode] =
  if m.sock == nil: return
  var fds = [TPollfd(fd: cint(m.sock.getFd), events: POLLIN)]
  while poll(addr fds[0], 1, 0) > 0:
    var data = newString(8192)
    let n = try: m.sock.recv(addr data[0], data.len) except CatchableError: -1
    if n <= 0:
      # (readable, and nothing: mpv closed its end)
      m.lose()
      break
    data.setLen(n)
    m.buf.add data
  while true:
    let k = m.buf.find('\n')
    if k < 0: break
    let line = m.buf[0 ..< k]
    m.buf = m.buf[k + 1 .. ^1]
    try: result.add parseJson(line)
    except CatchableError: discard

proc stop(m: var Mpv) =
  if m.sock != nil:
    m.cmd(%*["quit"])
    try: m.sock.close() except CatchableError: discard
    m.sock = nil
  if m.p != nil:
    if m.p.waitForExit(1500) == -1 or m.p.running:
      m.p.terminate()
      discard m.p.waitForExit(1000)
    m.p.close()
    m.p = nil
  removeFile(m.path)

proc runMedia*(args: seq[string]) =
  applyDesktopLook()
  openApp("Media Player", scaled(460), scaled(400), frame = wfSystem, userFrame = false, id = "media")
  showArt("media")
  followLook()
  var list: seq[string]
  for l in desktopSettings().setting("playlist", "").split('\n'):
    if l.len > 0 and fileExists(l): list.add l
  for a in args:
    if fileExists(a): list.add absolutePath(a)
    elif dirExists(a):
      for kind, p in walkDir(a):
        if p.splitFile.ext.toLowerAscii in MediaExts: list.add p
  var m: Mpv
  let have = m.start()
  var at = -1
  var pos, length = 0.0
  var paused = false
  var title = ""
  var volume = 100
  var sel = 0
  var showOpen, showFolder, showAbout: bool
  var pick = getHomeDir()
  proc keepList() =
    var s = desktopSettings()
    s["playlist"] = list.join("\n")
    saveDesktopSettings(s)
  proc play(i: int) =
    if i < 0 or i >= list.len: return
    at = i
    m.cmd(%*["loadfile", list[i], "replace"])
    m.cmd(%*["set_property", "pause", false])
  if args.len > 0 and list.len > 0: play(list.len - 1)
  var restarts: seq[float]
  while beginFrame():
    helpKeys("media")
    if have and m.sock == nil and m.p != nil:
      # (mpv ended by itself: started again -- three times a minute at most)
      let t = epochTime()
      while restarts.len > 0 and t - restarts[0] > 60: restarts.delete(0)
      m.stop()
      if restarts.len < 3:
        restarts.add t
        discard m.start()
      at = -1
      pos = 0
      paused = false
    for e in m.events():
      if e{"event"}.getStr == "property-change":
        case e{"name"}.getStr
        of "time-pos": pos = e{"data"}.getFloat(0)
        of "duration": length = e{"data"}.getFloat(0)
        of "pause": paused = e{"data"}.getBool
        of "media-title": title = e{"data"}.getStr
        of "volume": volume = int(e{"data"}.getFloat(100))
        else: discard
      elif e{"event"}.getStr == "end-file" and e{"reason"}.getStr == "eof":
        if at + 1 < list.len: play(at + 1) else: at = -1
    if at >= 0 and not paused: wakeIn(500)
    menubar:
      menu "&File":
        if menuItem("&Open...", "Ctrl+O"): showOpen = true
        if menuItem("Open &Folder..."): showFolder = true
        if menuItem("&Clear the List", enabled = list.len > 0):
          list = @[]
          keepList()
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("media")
        menuSeparator()
        if menuItem("&About Media Player..."): showAbout = true
    if not have:
      paragraph "Media Player plays with mpv, which is not installed: Setup > Multimedia > mpv."
    let disp = canvas(-1, dp(54))
    fill(disp, color(0, 0, 0))
    let st = TextStyle(mono: true, size: 1.6)
    text(disp.x + dp(10), disp.y + dp(6), clock(pos) & " / " & clock(length), color(0, 255, 0), st)
    text(disp.x + dp(10), disp.y + dp(6) + lineHeight(st),
         (if at >= 0: (if title.len > 0: title else: list[at].extractFilename) else: "Stopped"), color(0, 200, 0))
    var p = int(if length > 0: pos / length * 1000 else: 0)
    if slider(p, 0, 1000) and length > 0: m.cmd(%*["seek", float(p) / 1000 * length, "absolute"])
    row:
      # (narrow buttons: the row fits the window, no scroll bar under it)
      let bw = dp(46)
      if button("|<", enabled = at > 0, w = bw): play(at - 1)
      if button(if at >= 0 and not paused: "Pause" else: "Play", isDefault = true, enabled = have and list.len > 0,
                w = dp(60)):
        if at < 0: play(max(0, sel))
        else: m.cmd(%*["cycle", "pause"])
      if button("Stop", enabled = at >= 0, w = dp(60)):
        m.cmd(%*["stop"])
        at = -1
        pos = 0
      if button(">|", enabled = at >= 0 and at + 1 < list.len, w = bw): play(at + 1)
      spring()
      label("Volume")
      if slider(volume, 0, 130, w = dp(90)): m.cmd(%*["set_property", "volume", volume])
    var names: seq[string]
    for i, f in list: names.add (if i == at: "> " else: "   ") & f.extractFilename
    if listbox(names, sel, rows = max(3, remainingH() div ItemH - 1)) and ui.clicks >= 2: play(sel)
    if ui.key == KeyEnter and sel in 0 ..< list.len: play(sel)
    if fileDialog(showOpen, pick, fmOpen, ["Music and Video", "All Files (*.*)"]):
      list.add pick
      keepList()
      play(list.high)
    if showFolder:
      if filePicker(showFolder, pick, fmFolder, title = "Play the folder"):
        var fs: seq[string]
        for kind, f in walkDir(pick):
          if f.splitFile.ext.toLowerAscii in MediaExts: fs.add f
        fs.sort()
        list.add fs
        keepList()
    aboutBox(showAbout, "Media Player", DesktopVersion, ["Music and videos, with mpv.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  m.stop()
  closeApp()

# ==== Sound Recorder ===================================================================================

proc recordingsDir(): string =
  result = if dirExists(getHomeDir() / "storage/shared"): getHomeDir() / "storage/shared/Recordings"
           else: getHomeDir() / "Recordings"
  createDir(result)

proc runRecorder*() =
  applyDesktopLook()
  openApp("Sound Recorder", scaled(440), scaled(380), frame = wfSystem, userFrame = false, id = "recorder")
  showArt("recorder")
  followLook()
  let termuxMic = findExe("termux-microphone-record").len > 0
  let pulse = findExe("parecord").len > 0
  let alsa = findExe("arecord").len > 0
  var recording = false
  var rec: Process
  var file = ""
  var started = 0.0
  var player: Task
  var files: seq[string]
  var sel = 0
  var showAbout = false
  var said = if termuxMic or pulse or alsa: "" else:
               "Recording needs Termux:API (Setup > System > Termux:API tools) or PulseAudio."
  # (Termux:API answers through its Android app, which can take a while --
  # asking for the microphone -- or never, when the app is missing: asked in
  # the background, so the window always answers)
  var micJob: Task
  var micAsked = 0.0
  var micStopping = false
  proc list() =
    files = @[]
    for kind, p in walkDir(recordingsDir()):
      if p.splitFile.ext.toLowerAscii in [".m4a", ".wav", ".amr", ".ogg", ".opus", ".aac"]: files.add p
    files.sort(proc (a, b: string): int = cmp(b, a))
  list()
  proc stopRecording() =
    if not recording: return
    recording = false
    if termuxMic:
      if micJob != nil: micJob.stop()
      micJob = run("termux-microphone-record -q")
      micAsked = epochTime()
      micStopping = true
    elif rec != nil:
      rec.terminate()
      discard rec.waitForExit(2000)
      rec.close()
      rec = nil
      list()
      sel = 0
  proc micAnswered() =
    ## Termux:API's answer to a start or a stop.
    if micJob == nil: return
    if micJob.check():
      let o = micJob.output.strip
      let failed = micJob.code != 0 or "error" in o.toLowerAscii or "denied" in o.toLowerAscii
      if failed and not micStopping:
        recording = false
        said = if o.len > 0: o.splitLines[0] else: "The microphone could not be started."
      micJob = nil
      if micStopping:
        micStopping = false
        list()
        sel = 0
    elif epochTime() - micAsked > 10:
      micJob.stop()
      micJob = nil
      if not micStopping: recording = false
      micStopping = false
      said = "Termux:API does not answer: install the Termux:API app and allow it the microphone."
  proc playIt(f: string) =
    if player != nil: player.stop()
    if findExe("mpv").len > 0: player = run("mpv --no-video --really-quiet " & quoteShell(f))
    elif findExe("termux-media-player").len > 0: player = run("termux-media-player play " & quoteShell(f))
    else: player = run("paplay " & quoteShell(f))
  while beginFrame():
    helpKeys("recorder")
    if player != nil and player.check(): player = nil
    micAnswered()
    if micJob != nil: wakeIn(200)
    if recording and rec != nil and not rec.running:
      # (parecord or arecord ended by itself: no sound server, no device)
      recording = false
      said = "The recording stopped: " & (if pulse: "PulseAudio" else: "ALSA") & " has no microphone here."
      rec.close()
      rec = nil
      list()
    menubar:
      menu "&File":
        if menuItem("&Send to Android...", enabled = sel in 0 ..< files.len and findExe("termux-share").len > 0):
          launch("termux-share -a send " & quoteShell(files[sel]))
        if menuItem("&Delete", enabled = sel in 0 ..< files.len and not recording):
          removeFile(files[sel])
          list()
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("recorder")
        menuSeparator()
        if menuItem("&About Sound Recorder..."): showAbout = true
    # the wave: a green line on black, moving while it records
    let w = canvas(-1, dp(80))
    fill(w, color(0, 0, 0))
    let mid = float(w.y + w.h div 2)
    var last = (float(w.x), mid)
    let t = epochTime()
    for x in countup(w.x, w.x + w.w, max(2, dp(3))):
      let amp = if recording: (sin(float(x) * 0.13 + t * 9) * 0.5 + sin(float(x) * 0.031 - t * 5) * 0.5) *
                              float(w.h) * 0.38 * (0.6 + 0.4 * sin(t * 3)) else: 0.0
      let pnt = (float(x), mid + amp)
      thickLine(last[0], last[1], pnt[0], pnt[1], 1.5, color(0, 255, 0))
      last = pnt
    label(if recording: "Recording   " & clock(epochTime() - started) elif said.len > 0: said
          else: "Ready", bold = recording)
    if recording: wakeIn(60)
    row:
      if button(if recording: "Stop" else: "Record", isDefault = true,
                enabled = (termuxMic or pulse or alsa) and micJob == nil):
        if recording: stopRecording()
        else:
          let stamp = now().format("yyyy-MM-dd' 'HH.mm.ss")
          said = ""
          if termuxMic:
            file = recordingsDir() / "Recording " & stamp & ".m4a"
            micJob = run("termux-microphone-record -f " & quoteShell(file) & " -e aac -l 0")
            micAsked = epochTime()
            micStopping = false
          else:
            file = recordingsDir() / "Recording " & stamp & ".wav"
            rec = if pulse: startProcess("parecord", args = ["--file-format=wav", file], options = {poUsePath})
                  else: startProcess("arecord", args = ["-q", "-f", "cd", file], options = {poUsePath})
          recording = true
          started = epochTime()
      if button("Play", enabled = not recording and sel in 0 ..< files.len): playIt(files[sel])
      if button("Stop Playing", enabled = player != nil): player.stop()
      spring()
    var names: seq[string]
    for f in files: names.add f.splitFile.name
    if listbox(names, sel, rows = max(3, (remainingH() - lineHeight() - Gap) div ItemH)) and ui.clicks >= 2 and
       sel in 0 ..< files.len: playIt(files[sel])
    # (one line: the home folder as ~, a long path cut)
    var dir = recordingsDir()
    let home = getHomeDir().strip(leading = false, chars = {'/'})
    if dir.startsWith(home & "/"): dir = "~" & dir[home.len .. ^1]
    label(ellipsize("In " & dir, ui.w - 3 * Pad), enabled = false)
    aboutBox(showAbout, "Sound Recorder", DesktopVersion, ["Your voice, recorded.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  stopRecording()
  if micJob != nil:
    # (the stop asked: waited for a moment, so the recording is kept)
    for _ in 0 ..< 30:
      if micJob.check(): break
      sleep(100)
    micJob.stop()
  if player != nil: player.stop()
  closeApp()
