## The desktop's accessories, as 3.1 had them: Clock, Calculator, Calendar
## and Cardfile. Each is one window, sized by its frame, its keys as on a
## keyboard, what it keeps in the desktop's data folder.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, times, math, algorithm]
import retroui
import common, link

proc keep(name, key, value: string) =
  var s = loadSettings(name)
  s[key] = value
  discard saveSettings(name, s)

# ==== Clock ===============================================================================================

var
  analog = true
  showSeconds = true
  showDate = true

proc hand(cx, cy, angle, len, width: float; c: Color) =
  thickLine(cx, cy, cx + sin(angle) * len, cy - cos(angle) * len, width, c)

proc drawAnalog(r: Rect; t: DateTime) =
  let t2 = ui.theme
  let cx = float(r.x) + float(r.w) / 2
  let cy = float(r.y) + float(r.h) / 2
  let rad = max(10.0, min(float(r.w), float(r.h)) / 2 - float(dp(6)))
  for i in 0 ..< 60:
    let a = float(i) * PI / 30
    let x = cx + sin(a) * rad
    let y = cy - cos(a) * rad
    if i mod 5 == 0:
      let s = max(2.0, rad / 22)
      fill(int(x - s), int(y - s), int(2 * s), int(2 * s), t2.select)
      fill(int(x - s) + int(s), int(y - s) + int(s), int(s), int(s), t2.shadow)
    else:
      let s = max(1.0, rad / 60)
      fill(int(x - s / 2), int(y - s / 2), max(1, int(s)), max(1, int(s)), t2.text)
  let h = float(t.hour mod 12) + float(t.minute) / 60
  let m = float(t.minute) + float(t.second) / 60
  hand(cx, cy, h * PI / 6, rad * 0.55, max(2.0, rad / 14), t2.text)
  hand(cx, cy, m * PI / 30, rad * 0.82, max(2.0, rad / 20), t2.text)
  if showSeconds:
    hand(cx, cy, float(t.second) * PI / 30, rad * 0.88, max(1.0, rad / 70), t2.select)
  disc(cx, cy, max(2.0, rad / 18), t2.text)

proc drawDigital(r: Rect; t: DateTime) =
  let s = if showSeconds: t.format("HH:mm:ss") else: t.format("HH:mm")
  let probe = textWidth(s, style(bold = true))
  let k = max(1.0, min(float(r.w) * 0.85 / float(max(1, probe)),
                       float(r.h) * 0.5 / float(max(1, lineHeight()))))
  let st = style(bold = true, size = k)
  let w = textWidth(s, st)
  text(r.x + (r.w - w) div 2, r.y + (r.h - lineHeight(st)) div 2, s, ui.theme.text, st)

proc runClock*() =
  let s = loadSettings("retrodesktop-clock")
  analog = s.getOrDefault("mode", "analog") == "analog"
  showSeconds = s.getOrDefault("seconds", "1") == "1"
  showDate = s.getOrDefault("date", "1") == "1"
  applyDesktopLook()
  openApp("Clock", scaled(240), scaled(260), frame = wfSystem, userFrame = false, id = "clock")
  followLook()
  while beginFrame():
    let t = now()
    menubar:
      menu "&Settings":
        if menuItem("&Analog", checked = analog):
          analog = true
          keep("retrodesktop-clock", "mode", "analog")
        if menuItem("&Digital", checked = not analog):
          analog = false
          keep("retrodesktop-clock", "mode", "digital")
        menuSeparator()
        if menuItem("&Seconds", checked = showSeconds):
          showSeconds = not showSeconds
          keep("retrodesktop-clock", "seconds", if showSeconds: "1" else: "0")
        if menuItem("Da&te", checked = showDate):
          showDate = not showDate
          keep("retrodesktop-clock", "date", if showDate: "1" else: "0")
    let r = canvas(-1, remainingH())
    fill(r, ui.theme.face)
    var face = r
    if showDate:
      let d = t.format("dddd, d MMMM yyyy")
      let lh = lineHeight()
      text(r.x + (r.w - textWidth(d)) div 2, r.y + r.h - lh - dp(4), d, ui.theme.text)
      face.h -= lh + dp(6)
    if analog: drawAnalog(face, t) else: drawDigital(face, t)
    setTitle(if r.w < dp(150): t.format("HH:mm") else: "Clock")
    # (the next second, or the next minute without the seconds hand)
    let ms = if showSeconds: 1000 - (int(t.nanosecond div 1_000_000) mod 1000)
             else: (60 - t.second) * 1000
    wakeInShown(r, max(50, ms))
    endFrame()
    appFrameDone()
  closeApp()

# ==== Calculator ==========================================================================================

type CalcState = object
  display: string        # what is shown (the number being typed, or the result)
  acc: float             # the number before the operation
  op: char               # the operation waiting ('\0': none)
  fresh: bool            # the next digit starts a new number
  memory: float
  error: bool

var calc = CalcState(display: "0", fresh: true)

proc fmtNum(v: float): string =
  if v.classify in {fcNan, fcInf, fcNegInf}: return "Error"
  if v == 0: return "0"
  if abs(v) >= 1e15 or abs(v) < 1e-9:
    return formatFloat(v, ffScientific, 9).replace("e+", "e")
  result = formatFloat(v, ffDecimal, 12)
  if '.' in result:
    result = result.strip(leading = false, chars = {'0'})
    if result.endsWith("."): result.setLen(result.len - 1)
  if result == "-0": result = "0"

proc value(): float =
  try: parseFloat(calc.display) except ValueError: 0.0

proc setValue(v: float) =
  calc.display = fmtNum(v)
  calc.error = calc.display == "Error"
  calc.fresh = true

proc applyOp() =
  let b = value()
  case calc.op
  of '+': setValue(calc.acc + b)
  of '-': setValue(calc.acc - b)
  of '*': setValue(calc.acc * b)
  of '/':
    if b == 0:
      calc.display = "Error"
      calc.error = true
      calc.fresh = true
    else: setValue(calc.acc / b)
  else: discard
  calc.op = '\0'

proc press(k: string) =
  ## A key of the calculator (its label).
  if calc.error and k notin ["C", "CE"]: return
  case k
  of "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
    if calc.fresh or calc.display == "0":
      calc.display = k
      calc.fresh = false
    elif calc.display.len < 16: calc.display.add k
  of ".":
    if calc.fresh:
      calc.display = "0."
      calc.fresh = false
    elif '.' notin calc.display: calc.display.add '.'
  of "Back":
    if not calc.fresh:
      calc.display.setLen(max(0, calc.display.len - 1))
      if calc.display.len == 0 or calc.display == "-": calc.display = "0"
  of "CE":
    calc.display = "0"
    calc.fresh = true
    calc.error = false
  of "C":
    calc = CalcState(display: "0", fresh: true, memory: calc.memory)
  of "+/-":
    if calc.display != "0":
      calc.display = if calc.display.startsWith("-"): calc.display[1 .. ^1] else: "-" & calc.display
  of "+", "-", "*", "/":
    if calc.op != '\0' and not calc.fresh: applyOp()
    calc.acc = value()
    calc.op = k[0]
    calc.fresh = true
  of "=":
    if calc.op != '\0': applyOp()
  of "sqrt":
    if value() < 0:
      calc.display = "Error"
      calc.error = true
    else: setValue(sqrt(value()))
  of "%":
    setValue(calc.acc * value() / 100)
  of "1/x":
    if value() == 0:
      calc.display = "Error"
      calc.error = true
    else: setValue(1 / value())
  of "MC": calc.memory = 0
  of "MR": setValue(calc.memory)
  of "MS": calc.memory = value(); calc.fresh = true
  of "M+": calc.memory += value(); calc.fresh = true
  else: discard

const CalcKeys = [
  ["MC", "Back", "CE", "C", "sqrt"],
  ["MR", "7", "8", "9", "/"],
  ["MS", "4", "5", "6", "*"],
  ["M+", "1", "2", "3", "-"],
  ["%", "0", "+/-", ".", "+"],
  ["1/x", "", "", "", "="]]

proc calcKeys() =
  ## The keyboard: digits, + - * /, Enter or =, Esc (C), Del (CE), Backspace.
  if ui.typed.len > 0 and ui.dialogTop == 0:
    for ch in ui.typed:
      case ch
      of '0' .. '9', '.', '+', '-', '*', '/', '%': press($ch)
      of ',': press(".")
      of '=': press("=")
      else: discard
  case ui.key
  of KeyEnter: press("=")
  of KeyEsc: press("C")
  of KeyDelete: press("CE")
  of KeyBackspace: press("Back")
  else: discard
  if hotkeyPressed("Ctrl+C"): putClipboardText(calc.display)
  if hotkeyPressed("Ctrl+V"):
    let t = getClipboardText().strip
    try:
      setValue(parseFloat(t))
    except ValueError: discard

proc runCalc*() =
  applyDesktopLook()
  openApp("Calculator", scaled(300), scaled(330), frame = wfSystem, userFrame = false, id = "calc")
  followLook()
  var showAbout = false
  while beginFrame():
    menubar:
      menu "&Edit":
        if menuItem("&Copy", "Ctrl+C"): putClipboardText(calc.display)
        if menuItem("&Paste", "Ctrl+V"):
          try: setValue(parseFloat(getClipboardText().strip)) except ValueError: discard
      menu "&Help":
        if menuItem("&About Calculator..."): showAbout = true
    calcKeys()
    let r = canvas(-1, remainingH())
    fill(r, ui.theme.face)
    let gap = dp(5)
    let dispH = max(dp(30), r.h div 7)
    let disp = rect(r.x + gap, r.y + gap, r.w - 2 * gap, dispH)
    fill(disp, ui.theme.field)
    box(disp, ui.theme.frame)
    let k = max(1.0, min(float(disp.h) * 0.6 / float(lineHeight()), 2.4))
    let st = style(bold = true, size = k)
    var shown = calc.display
    while shown.len > 1 and textWidth(shown, st) > disp.w - dp(12): shown = shown[1 .. ^1]
    text(disp.x + disp.w - textWidth(shown, st) - dp(6), disp.y + (disp.h - lineHeight(st)) div 2,
         shown, ui.theme.fieldText, st)
    if calc.memory != 0:
      text(disp.x + dp(6), disp.y + (disp.h - lineHeight()) div 2, "M", ui.theme.fieldText)
    let top = disp.y + disp.h + gap * 2
    let rows = CalcKeys.len
    let bw = (r.w - gap * 6) div 5
    let bh = max(dp(20), (r.y + r.h - top - gap * rows) div rows)
    for ri, line in CalcKeys:
      for ci, key in line:
        if key.len == 0: continue
        var w = bw
        if ri == 5 and ci == 0: discard
        let br = rect(r.x + gap + ci * (bw + gap), top + ri * (bh + gap), w, bh)
        let red = key in ["Back", "CE", "C", "MC", "MR", "MS", "M+"]
        let lbl = if key == "sqrt": "sqrt" else: key
        if buttonAt("calc" & $ri & ":" & $ci, br, lbl,
                    style(bold = not red, size = (if fingers(): 1.15 else: 1.0))):
          press(key)
    aboutBox(showAbout, "Calculator", DesktopVersion)
    endFrame()
    appFrameDone()
  closeApp()

# ==== Calendar ============================================================================================

const CalSettings = "retrodesktop-calendar"

var
  calDay: Date
  calData: Settings
  notes: string
  slots: array[24, string]
  loadedFor: Date

proc dayKey(d: Date): string =
  $d.year & "-" & align($d.month, 2, '0') & "-" & align($d.day, 2, '0')

proc loadDay(d: Date) =
  let k = dayKey(d)
  notes = calData.getOrDefault(k & " notes", "")
  for h in 0 ..< 24: slots[h] = calData.getOrDefault(k & " " & align($h, 2, '0'), "")
  loadedFor = d

proc saveDay() =
  let k = dayKey(loadedFor)
  for h in 0 ..< 24:
    let key = k & " " & align($h, 2, '0')
    if slots[h].strip.len > 0: calData[key] = slots[h]
    elif calData.hasKey(key): calData.del(key)
  if notes.strip.len > 0: calData[k & " notes"] = notes
  elif calData.hasKey(k & " notes"): calData.del(k & " notes")
  discard saveSettings(CalSettings, calData)

proc upcoming(): seq[string] =
  ## The next appointments, from today on.
  let t = dayKey(today())
  var keys: seq[string]
  for k, v in calData:
    if k.len == 13 and k[0 .. 9] >= t and v.strip.len > 0: keys.add k
  keys.sort()
  for k in keys:
    if result.len >= 6: break
    result.add k[0 .. 9] & " " & k[11 .. 12] & ":00  " & calData[k]

const DayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

proc dayView() =
  label(DayNames[weekday(calDay)] & ", " & $calDay, bold = true)
  scrollPanel(-1):
    form(50):
      for h in 6 .. 22:
        withId(h):
          field(align($h, 2, '0') & ":00"):
            if edit(slots[h]): saveDay()
    label "Notes:"
    if editArea(notes, 4): saveDay()

proc runCalendar*() =
  applyDesktopLook()
  calData = loadSettings(CalSettings)
  calDay = today()
  loadDay(calDay)
  openApp("Calendar", scaled(640), scaled(460), frame = wfSystem, userFrame = false, id = "calendar")
  followLook()
  while beginFrame():
    menubar:
      menu "&Show":
        if menuItem("&Today", "Ctrl+T"): calDay = today()
        if menuItem("&Previous Day", "Ctrl+PgUp"): calDay = calDay.addDays(-1)
        if menuItem("&Next Day", "Ctrl+PgDn"): calDay = calDay.addDays(1)
    if hotkeyPressed("Ctrl+T"): calDay = today()
    if hotkeyPressed("Ctrl+PgUp"): calDay = calDay.addDays(-1)
    if hotkeyPressed("Ctrl+PgDn"): calDay = calDay.addDays(1)
    if calDay != loadedFor:
      saveDay()
      loadDay(calDay)
    if ui.w >= dp(540):
      row([250, -1]):
        col:
          calendar(calDay)
          if button("&Today"): calDay = today()
          group "Coming up":
            let u = upcoming()
            if u.len == 0: label("Nothing yet.", enabled = false)
            for i, line in u:
              withId(i): label(line, literal = true)
        col:
          dayView()
    else:
      calendar(calDay)
      dayView()
    endFrame()
    appFrameDone()
  saveDay()
  closeApp()

# ==== Cardfile ============================================================================================

type Card = object
  title, body: string

var
  cards: seq[Card]
  cardSel = 0
  cardFind = ""
  showCardFind = false
  showDeleteCard = false

proc cardsFile(): string = dataDir(SettingsName) / "cardfile.txt"

proc loadCards() =
  ## One card a block: its index line, then its text, a line with a form feed
  ## between cards.
  cards = @[]
  try:
    for blk in readFile(cardsFile()).split("\n\f\n"):
      if blk.strip.len == 0: continue
      let nl = blk.find('\n')
      if nl < 0: cards.add Card(title: blk)
      else: cards.add Card(title: blk[0 ..< nl], body: blk[nl + 1 .. ^1])
  except CatchableError: discard
  if cards.len == 0:
    cards.add Card(title: "Retro Desktop", body: "The index line is the card's name; " &
                   "the cards are kept in order of it.\n\nCard > Add (F7) makes a new one.")

proc saveCards() =
  var parts: seq[string]
  for c in cards: parts.add c.title.replace("\n", " ") & "\n" & c.body.replace("\n\f\n", "\n\n")
  try:
    createDir(cardsFile().parentDir)
    writeFile(cardsFile() & ".tmp", parts.join("\n\f\n"))
    moveFile(cardsFile() & ".tmp", cardsFile())
  except CatchableError: discard

proc sortCards() =
  let current = if cardSel in 0 ..< cards.len: cards[cardSel].title else: ""
  cards.sort(proc (a, b: Card): int = cmpIgnoreCase(a.title, b.title))
  for i, c in cards:
    if c.title == current:
      cardSel = i
      break

proc runCardfile*() =
  applyDesktopLook()
  loadCards()
  sortCards()
  openApp("Cardfile", scaled(600), scaled(420), frame = wfSystem, userFrame = false, id = "cardfile")
  followLook()
  var titles: seq[string]
  while beginFrame():
    menubar:
      menu "&Card":
        if menuItem("&Add...", "F7"):
          cards.add Card(title: "New card")
          cardSel = cards.high
          saveCards()
          focusFirstText()
        if menuItem("&Delete", enabled = cards.len > 0): showDeleteCard = true
        if menuItem("D&uplicate", enabled = cards.len > 0):
          cards.add cards[cardSel]
          cardSel = cards.high
          saveCards()
      menu "&Search":
        if menuItem("&Go To...", "F4"):
          showCardFind = true
          focusFirstText(inDialog = true)
    if hotkeyPressed("F7"):
      cards.add Card(title: "New card")
      cardSel = cards.high
      saveCards()
      focusFirstText()
    if hotkeyPressed("F4"):
      showCardFind = true
      focusFirstText(inDialog = true)
    titles.setLen(0)
    for c in cards: titles.add c.title
    cardSel = clamp(cardSel, 0, max(0, cards.high))
    if ui.w >= dp(460):
      row([180, -1]):
        col:
          if listbox(titles, cardSel, rows = -1): discard
        col:
          if cards.len > 0:
            form 0:
              field "&Index:":
                if edit(cards[cardSel].title): saveCards()
            if editArea(cards[cardSel].body, -1): saveCards()
    else:
      if combo(titles, cardSel): discard
      if cards.len > 0:
        if edit(cards[cardSel].title): saveCards()
        if editArea(cards[cardSel].body, -1): saveCards()
    statusbar($cards.len & " cards")
    if showCardFind:
      if inputBox(showCardFind, "Go To", "Go to (a word on a card):", cardFind) == 1:
        let w = cardFind.toLowerAscii
        for i in 0 ..< cards.len:
          let k = (cardSel + 1 + i) mod cards.len
          if w in cards[k].title.toLowerAscii or w in cards[k].body.toLowerAscii:
            cardSel = k
            break
    if showDeleteCard and cards.len > 0:
      if msgBox(showDeleteCard, "Cardfile", "Delete \"" & cards[cardSel].title & "\"?",
                ["&Yes", "&No"], miQuestion) == 1:
        cards.delete(cardSel)
        saveCards()
    # (kept in order of their index lines, once the one being typed is left)
    if ui.focus == 0 or ui.key == KeyEnter:
      let before = cards
      sortCards()
      if before != cards: saveCards()
    endFrame()
    appFrameDone()
  sortCards()
  saveCards()
  closeApp()
