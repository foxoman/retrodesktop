## The screen savers: Blank Screen, Starfield, Mystify, Marquee -- the whole
## screen, until a key, a click or a touch. The desktop starts one when
## nothing was done for the delay Control Panel set (it asks the X server how
## long the screen has been idle: the MIT-SCREEN-SAVER extension, libXss).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[random, math, dynlib]
import retroui
import retroui/uirelays/drivers/x11_driver
import xlib, common, link

# ---- how long the screen has been idle ---------------------------------------------------------------

type
  XssInfo = object
    window: culong
    state, kind: cint
    tilOrSince, idle, eventMask: culong

  XssQuery = proc (d: pointer; drawable: culong; info: ptr XssInfo): cint {.cdecl.}

var
  xssTried = false
  xssQuery: XssQuery

proc idleMs*(d: Display): int =
  ## Milliseconds since the last key, click or touch on the screen; -1 when
  ## the X server cannot say (no libXss, no extension).
  if not xssTried:
    xssTried = true
    var lib = loadLib("libXss.so.1")
    if lib == nil: lib = loadLib("libXss.so")
    if lib != nil: xssQuery = cast[XssQuery](lib.symAddr("XScreenSaverQueryInfo"))
  if xssQuery == nil or d == nil: return -1
  var info: XssInfo
  if xssQuery(cast[pointer](d), culong(XRootWindow(d, XDefaultScreen(d))), addr info) == 0: return -1
  int(info.idle)

# ---- the savers -------------------------------------------------------------------------------------

type
  Star = object
    x, y, z: float

proc runSaver*(args: seq[string]) =
  let s = desktopSettings()
  let kind = s.setting("saver", "(None)")
  let words = s.setting("saverText", DesktopName)
  if kind == "(None)" and (args.len == 0 or args[0] != "now"): return
  randomize()
  openApp("Screen Saver", 640, 480, frame = wfSystem, userFrame = false, id = "saver")
  fullscreenSelf()
  var stars: seq[Star]
  for i in 0 ..< 220: stars.add Star(x: rand(2.0) - 1.0, y: rand(2.0) - 1.0, z: rand(1.0) + 0.05)
  var pts: array[2, array[4, tuple[x, y, vx, vy: float]]]
  for p in 0 .. 1:
    for k in 0 .. 3:
      pts[p][k] = (x: rand(640.0), y: rand(480.0), vx: rand(6.0) - 3.0, vy: rand(6.0) - 3.0)
  var trails: array[2, seq[array[4, (float, float)]]]
  var hue = 0.0
  var mx = -1
  var my = -1
  var started = 0
  var marqueeX = 1e9
  var marqueeY = 0
  while beginFrame():
    if started == 0: started = ui.now
    # (a key, a click, a touch, the pointer moved: the saver ends)
    if ui.now - started > 800:
      if ui.pressed or ui.rpressed or ui.key != KeyNone or
         (mx >= 0 and (abs(ui.mx - mx) > 8 or abs(ui.my - my) > 8)):
        quitApp()
    if mx < 0 or ui.now - started <= 800:
      mx = ui.mx
      my = ui.my
    let r = rect(0, 0, ui.w, ui.h)
    fill(r, color(0, 0, 0))
    case kind
    of "Starfield":
      let cx = float(r.w) / 2
      let cy = float(r.h) / 2
      for st in stars.mitems:
        st.z -= 0.012
        if st.z <= 0.02:
          st = Star(x: rand(2.0) - 1.0, y: rand(2.0) - 1.0, z: 1.0)
        let sx = cx + st.x / st.z * cx
        let sy = cy + st.y / st.z * cy
        if sx < 0 or sy < 0 or sx >= float(r.w) or sy >= float(r.h):
          st = Star(x: rand(2.0) - 1.0, y: rand(2.0) - 1.0, z: 1.0)
          continue
        let size = max(1, int((1.0 - st.z) * 3.5))
        let v = uint8(clamp(int((1.0 - st.z) * 255) + 60, 0, 255))
        fill(int(sx), int(sy), size, size, color(v, v, v))
      wakeIn(33)
    of "Mystify":
      hue += 0.01
      for p in 0 .. 1:
        for k in 0 .. 3:
          var q = pts[p][k]
          q.x += q.vx * float(dp(1))
          q.y += q.vy * float(dp(1))
          if q.x < 0 or q.x > float(r.w): q.vx = -q.vx
          if q.y < 0 or q.y > float(r.h): q.vy = -q.vy
          q.x = clamp(q.x, 0, float(r.w))
          q.y = clamp(q.y, 0, float(r.h))
          pts[p][k] = q
        var shape: array[4, (float, float)]
        for k in 0 .. 3: shape[k] = (pts[p][k].x, pts[p][k].y)
        trails[p].add shape
        if trails[p].len > 7: trails[p].delete(0)
        let h = hue + float(p) * 0.5
        let ink = color(uint8(128 + 127 * sin(h)), uint8(128 + 127 * sin(h + 2.1)),
                        uint8(128 + 127 * sin(h + 4.2)))
        for sh in trails[p]:
          for k in 0 .. 3:
            let a = sh[k]
            let b = sh[(k + 1) mod 4]
            thickLine(a[0], a[1], b[0], b[1], max(1.0, float(dp(1))), ink)
      wakeIn(33)
    of "Marquee":
      let st = TextStyle(bold: true, size: 2.5)
      let tw = textWidth(words, st)
      if marqueeX < -float(tw):
        marqueeX = float(r.w)
        marqueeY = rand(max(1, r.h - lineHeight(st)))
      elif marqueeX > float(r.w) + 1e8:
        marqueeX = float(r.w)
        marqueeY = r.h div 2
      marqueeX -= 3.0 * float(dp(1))
      text(int(marqueeX), marqueeY, words, color(255, 255, 0), st)
      wakeIn(33)
    else:
      # Blank Screen: nothing to draw again
      wakeIn(1000)
    endFrame()
  closeApp()
