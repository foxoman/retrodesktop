## Commands run in the background (Termux:API's take a second or more): a
## program asks, keeps drawing, and takes the output when the command ended.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[osproc, posix, strutils]

type Task* = ref object
  p: Process
  fd: cint
  output*: string
  done*: bool
  code*: int

proc run*(command: string): Task =
  ## `command` (a shell command line) started.
  result = Task()
  try:
    result.p = startProcess("sh", args = ["-c", command], options = {poUsePath, poStdErrToStdOut})
    result.fd = cint(result.p.outputHandle)
    discard fcntl(result.fd, F_SETFL, fcntl(result.fd, F_GETFL) or O_NONBLOCK)
  except OSError as e:
    result.output = e.msg
    result.done = true
    result.code = 127

proc check*(t: Task): bool =
  ## True once the command ended (its `output`, its `code`).
  if t == nil: return false
  if t.done: return true
  var buf: array[8192, char]
  while true:
    let n = posix.read(t.fd, addr buf[0], buf.len)
    if n > 0:
      for i in 0 ..< n: t.output.add buf[i]
    elif n == 0:
      t.code = t.p.waitForExit()
      t.p.close()
      t.done = true
      return true
    else: return false

proc stop*(t: Task) =
  if t != nil and not t.done:
    t.p.terminate()
    discard t.p.waitForExit()
    t.p.close()
    t.done = true

proc lines*(t: Task): seq[string] =
  for l in t.output.splitLines:
    if l.strip.len > 0: result.add l
