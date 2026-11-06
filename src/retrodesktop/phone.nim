## Phone Dialer -- 3.1 had one, for the modem -- for the phone the desktop
## runs on, through Termux:API: dial a number, the contacts, the messages
## (read them as conversations, write one), the calls made and missed.
## Android asks once to let Termux:API at each of them.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, json, tables, algorithm]
import retroui
import common, link, help, tasks

type
  Contact = tuple[name, number: string]
  Sms = tuple[number, name, body, date, kind: string]
  Call = tuple[name, number, kind, date, duration: string]

proc api(): bool = findExe("termux-telephony-call").len > 0

proc runDialer*() =
  applyDesktopLook()
  openApp("Phone Dialer", scaled(480), scaled(520), frame = wfSystem, userFrame = false, id = "dialer")
  showArt("dialer")
  followLook()
  var tab = 0
  var number = ""
  var contacts: seq[Contact]
  var sms: seq[Sms]
  var calls: seq[Call]
  var contactsJob, smsJob, callsJob, sendJob: Task
  var find = ""
  var csel, tsel, lsel = 0
  var thread = ""                ## the number whose messages are shown
  var draft = ""
  var said = if api(): "" else: "The Phone Dialer needs Termux:API: Setup > System > Termux:API tools, " &
                                 "and the Termux:API app from where Termux came."
  var showAbout = false
  proc nameFor(num: string): string =
    for c in contacts:
      if c.number.replace(" ", "") == num.replace(" ", ""): return c.name
    num
  proc call(num: string) =
    if num.strip.len > 0 and api(): launch("termux-telephony-call " & quoteShell(num.strip))
  if api():
    contactsJob = run("termux-contact-list")
  while beginFrame():
    helpKeys("dialer")
    if contactsJob != nil and contactsJob.check():
      try:
        contacts = @[]
        for c in parseJson(contactsJob.output):
          contacts.add (c{"name"}.getStr, c{"number"}.getStr)
        contacts.sort(proc (a, b: Contact): int = cmpIgnoreCase(a.name, b.name))
      except CatchableError: said = "Android did not let Termux:API read the contacts."
      contactsJob = nil
    if smsJob != nil and smsJob.check():
      try:
        sms = @[]
        for m in parseJson(smsJob.output):
          sms.add (m{"number"}.getStr, m{"sender"}.getStr, m{"body"}.getStr, m{"received"}.getStr, m{"type"}.getStr)
      except CatchableError: said = "Android did not let Termux:API read the messages."
      smsJob = nil
    if callsJob != nil and callsJob.check():
      try:
        calls = @[]
        for c in parseJson(callsJob.output):
          calls.add (c{"name"}.getStr, c{"phone_number"}.getStr, c{"type"}.getStr, c{"date"}.getStr,
                     c{"duration"}.getStr)
      except CatchableError: said = "Android did not let Termux:API read the calls."
      callsJob = nil
    if sendJob != nil and sendJob.check():
      said = if sendJob.code == 0: "Sent." else: "The message did not go: " & sendJob.output.strip
      sendJob = nil
      smsJob = run("termux-sms-list -l 200 -n")
    if contactsJob != nil or smsJob != nil or callsJob != nil or sendJob != nil: wakeIn(200)
    menubar:
      menu "&Phone":
        if menuItem("&Refresh", "F5", enabled = api()):
          contactsJob = run("termux-contact-list")
          if tab == 2: smsJob = run("termux-sms-list -l 200 -n")
          if tab == 3: callsJob = run("termux-call-log -l 100")
        menuSeparator()
        if menuItem("E&xit"): quitApp()
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("dialer")
        menuSeparator()
        if menuItem("&About Phone Dialer..."): showAbout = true
    if said.len > 0: label(said, literal = true, color = color(150, 60, 0))
    let before = tab
    tabs(tab, ["&Dial", "&Contacts", "&Messages", "C&alls"]):
      case tab
      of 0:
        let big = TextStyle(size: 1.8, mono: true)
        let r = canvas(-1, lineHeight(big) + dp(12))
        sunken(r)
        fill(rect(r.x + 1, r.y + 1, r.w - 2, r.h - 2), ui.theme.field)
        text(r.x + dp(8), r.y + dp(6), (if number.len > 0: number else: " "), ui.theme.fieldText, big)
        if number.len > 0: label(nameFor(number), enabled = false)
        for keys in [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]:
          row([-1, -1, -1]):
            for k in keys:
              if button(k): number.add k
        row:
          if button("&Delete", enabled = number.len > 0): number.setLen(number.len - 1)
          if button("C&lear"): number = ""
          spring()
          if button("&Message", enabled = number.len > 0):
            thread = number
            tab = 2
          if button("&Dial", isDefault = true, enabled = number.len > 0 and api()): call(number)
        for ch in ui.typed:
          if ch in {'0' .. '9', '*', '#', '+'}: number.add ch
      of 1:
        searchBox(find, "Find a name or a number")
        var shown: seq[Contact]
        var names: seq[string]
        for c in contacts:
          if find.len == 0 or find.toLowerAscii in c.name.toLowerAscii or find in c.number:
            shown.add c
            names.add c.name & "    " & c.number
        listbox(names, csel, rows = max(3, (remainingH() - CtrlH - 2 * Gap) div ItemH))
        row:
          spring()
          if button("&Message", enabled = csel in 0 ..< shown.len):
            thread = shown[csel].number
            tab = 2
          if button("&Call", isDefault = true, enabled = csel in 0 ..< shown.len and api()): call(shown[csel].number)
      of 2:
        if thread.len == 0:
          # the conversations: the newest message of each number
          var latest: OrderedTable[string, Sms]
          for m in sms:
            if not latest.hasKey(m.number) or m.date > latest[m.number].date: latest[m.number] = m
          var list: seq[Sms]
          for v in latest.values: list.add v
          list.sort(proc (a, b: Sms): int = cmp(b.date, a.date))
          var names: seq[string]
          for m in list:
            names.add (if m.name.len > 0: m.name else: nameFor(m.number)) & "  --  " &
                      m.body.replace("\n", " ")[0 ..< min(60, m.body.len)]
          if listbox(names, tsel, rows = max(3, (remainingH() - CtrlH - 2 * Gap) div ItemH)) and ui.clicks >= 2 and tsel in 0 ..< list.len: thread = list[tsel].number
          row:
            spring()
            if button("&Open", isDefault = true, enabled = tsel in 0 ..< list.len): thread = list[tsel].number
        else:
          row:
            if button("< &Back"): thread = ""
            label(nameFor(thread), bold = true)
            label(thread, enabled = false)
          var mine: seq[Sms]
          for m in sms:
            if m.number == thread: mine.add m
          mine.sort(proc (a, b: Sms): int = cmp(a.date, b.date))
          beginPanel(max(dp(80), remainingH() - EditH - 2 * Gap), key = "sms" & thread)
          for i, m in mine:
            withId(i):
              let sentByMe = m.kind == "sent" or m.kind == "outbox"
              label((if sentByMe: "Me" else: nameFor(m.number)) & "  " & m.date, bold = true,
                    color = (if sentByMe: color(192, 0, 0) else: color(0, 0, 192)))
              paragraph m.body
          revealInPanel(place(0, 1, fill = true), glide = false)
          endPanel()
          row([-1, 70]):
            edit(draft)
            if button("&Send", isDefault = true, enabled = draft.strip.len > 0 and api() and sendJob == nil):
              sendJob = run("termux-sms-send -n " & quoteShell(thread) & " " & quoteShell(draft))
              said = "Sending..."
              draft = ""
      else:
        var names: seq[string]
        for c in calls:
          let who = if c.name.len > 0 and c.name != "UNKNOWN_CALLER": c.name else: c.number
          let mark = case c.kind
                     of "INCOMING": "In   "
                     of "OUTGOING": "Out  "
                     of "MISSED": "Missed"
                     else: c.kind
          names.add mark & "  " & who & "  " & c.date & "  " & c.duration
        listbox(names, lsel, rows = max(3, (remainingH() - CtrlH - 2 * Gap) div ItemH))
        row:
          spring()
          if button("&Call Back", isDefault = true, enabled = lsel in 0 ..< calls.len and api()):
            call(calls[lsel].number)
    if tab != before and api():
      if tab == 2 and sms.len == 0 and smsJob == nil: smsJob = run("termux-sms-list -l 200 -n")
      if tab == 3 and calls.len == 0 and callsJob == nil: callsJob = run("termux-call-log -l 100")
    aboutBox(showAbout, "Phone Dialer", DesktopVersion,
             ["Calls, messages and contacts of the phone, through Termux:API.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
