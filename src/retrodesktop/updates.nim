## Updates: whether a newer Retro Desktop is out -- the latest release on
## GitHub (github.com/foxoman/retrodesktop), asked on a thread of its own --
## and its package for this phone (the .deb Termux installs).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, json, locks, typedthreads]
import retroui/http
import common

const ReleasesUrl* = "https://api.github.com/repos/foxoman/retrodesktop/releases/latest"
const ReleasesPage* = "https://github.com/foxoman/retrodesktop/releases"

type Update* = object
  version*: string              ## "0.1.9" ("" none newer, or not known)
  deb*: string                  ## its package's address, for this phone ("" none)
  notes*: string                ## what is new (the release's words)
  error*: string                ## why it is not known

var
  lock: Lock
  found {.guard: lock.}: Update
  done {.guard: lock.}: bool
  thread: Thread[void]
  started = false

proc newer*(a, b: string): bool =
  ## Whether version `a` ("0.1.10") is after `b` ("0.1.9").
  let x = a.strip(chars = {'v', 'V'}).split('.')
  let y = b.strip(chars = {'v', 'V'}).split('.')
  for i in 0 ..< max(x.len, y.len):
    var p, q = 0
    try:
      if i < x.len: p = parseInt(x[i])
      if i < y.len: q = parseInt(y[i])
    except ValueError: return false
    if p != q: return p > q
  false

proc ask() {.thread.} =
  var u: Update
  try:
    # (RETRO_RELEASES_URL: another answer, for trying it)
    let r = httpRequest("GET", getEnv("RETRO_RELEASES_URL", ReleasesUrl), headers = @[("Accept", "application/vnd.github+json"),
                        ("User-Agent", "Retro-Desktop/" & DesktopVersion)],
                        timeoutSec = 20)
    if r.status != 200:
      u.error = (if r.status == 0: r.error else: "GitHub answered " & $r.status)
    else:
      let j = parseJson(r.body)
      let v = j{"tag_name"}.getStr.strip(chars = {'v', 'V'})
      if newer(v, DesktopVersion):
        u.version = v
        u.notes = j{"body"}.getStr
        for a in j{"assets"}:
          let name = a{"name"}.getStr
          if name.endsWith("_aarch64.deb"): u.deb = a{"browser_download_url"}.getStr
  except CatchableError as e: u.error = e.msg
  {.cast(gcsafe).}:
    withLock lock:
      found = u
      done = true

proc checkForUpdate*() =
  ## Asks GitHub (once; the answer comes with `updateFound`).
  if started: return
  started = true
  initLock(lock)
  createThread(thread, ask)

proc updateFound*(): (bool, Update) =
  ## Whether the answer came, and what it says.
  if not started: return (false, Update())
  withLock lock:
    result = (done, found)
