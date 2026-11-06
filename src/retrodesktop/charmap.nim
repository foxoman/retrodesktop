## Character Map, as 3.1's: the letters and symbols of a font in a grid,
## each larger under the finger; Select puts it in the characters to copy,
## Copy takes them to the clipboard. The blocks: Latin, Greek, Cyrillic,
## Arabic, Hebrew, punctuation, currency, arrows, mathematics, box drawing,
## shapes, symbols, dingbats.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, unicode]
import retroui
from retroui/typeset import hasGlyphs
import common, link, help

const
  Blocks = [("Latin", 0x21, 0x24F), ("Greek", 0x370, 0x3FF), ("Cyrillic", 0x400, 0x4FF),
            ("Arabic", 0x600, 0x6FF), ("Hebrew", 0x590, 0x5FF), ("Punctuation", 0x2010, 0x205E),
            ("Currency", 0x20A0, 0x20C0), ("Arrows", 0x2190, 0x21FF), ("Mathematics", 0x2200, 0x22FF),
            ("Box drawing", 0x2500, 0x259F), ("Shapes", 0x25A0, 0x25FF), ("Symbols", 0x2600, 0x26FF),
            ("Dingbats", 0x2700, 0x27BF)]
  Fonts = ["Sans", "Serif", "Mono"]

let blockNames = block:
  var n: seq[string]
  for (b, _, _) in Blocks: n.add b
  n

proc runCharmap*() =
  applyDesktopLook()
  openApp("Character Map", scaled(560), scaled(420), frame = wfSystem, userFrame = false, id = "charmap")
  showArt("charmap")
  followLook()
  var blockAt, fontAt = 0
  var toCopy = ""
  var sel = -1
  var chars: seq[int]
  var shownFor = (-1, -1)
  var showAbout = false
  while beginFrame():
    helpKeys("charmap")
    let st = TextStyle(serif: fontAt == 1, mono: fontAt == 2)
    if shownFor != (blockAt, fontAt):
      # (the block's characters the font has)
      shownFor = (blockAt, fontAt)
      chars = @[]
      let (_, a, b) = Blocks[blockAt]
      for cp in a .. b:
        if hasGlyphs($Rune(cp), faceOf(st)): chars.add cp
      sel = -1
    menubar:
      menu "&Edit":
        if menuItem("&Copy", "Ctrl+C", enabled = toCopy.len > 0): putClipboardText(toCopy)
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("charmap")
        menuSeparator()
        if menuItem("&About Character Map..."): showAbout = true
    row:
      label("&Font:")
      combo(Fonts, fontAt, w = dp(90))
      label("&Block:")
      combo(blockNames, blockAt, w = dp(140))
      spring()
    row([-1, 0, 0]):
      edit(toCopy)
      if button("&Select", enabled = sel >= 0): toCopy.add $Rune(chars[sel])
      if button("&Copy", isDefault = true, enabled = toCopy.len > 0):
        putClipboardText(toCopy)
        toast("Copied: " & toCopy, 2000)
    let area = canvas(-1, max(dp(80), remainingH() - lineHeight() - dp(8)))
    let cell = max(dp(26), min(dp(40), area.w div 16))
    let cols = max(1, area.w div cell)
    fill(area, ui.theme.window)
    let hit = interact(idOf("charmap-grid"), area, focusable = false)
    var hover = -1
    let big = TextStyle(serif: st.serif, mono: st.mono, size: float32(cell) / float32(lineHeight()) * 0.62)
    pushClip(area)
    for i, cp in chars:
      let r = rect(area.x + (i mod cols) * cell, area.y + (i div cols) * cell, cell, cell)
      if r.y > area.y + area.h: break
      if i == sel: fill(r, ui.theme.select)
      box(r, ui.theme.line)
      let s = $Rune(cp)
      text(r.x + (r.w - textWidth(s, big)) div 2, r.y + (r.h - lineHeight(big)) div 2, s,
           (if i == sel: ui.theme.selectText else: ui.theme.text), big)
      if hit.hover and ui.mx >= r.x and ui.mx < r.x + r.w and ui.my >= r.y and ui.my < r.y + r.h: hover = i
    popClip()
    if hover >= 0:
      if ui.pressed:
        if sel == hover and ui.clicks >= 2: toCopy.add $Rune(chars[hover])
        sel = hover
      # (the one under the pointer, larger, as 3.1 showed it)
      let z = cell * 2
      let hx = clamp(area.x + (hover mod cols) * cell - cell div 2, area.x, area.x + area.w - z)
      let hy = clamp(area.y + (hover div cols) * cell - cell div 2, area.y, area.y + area.h - z)
      let zr = rect(hx, hy, z, z)
      fill(zr, ui.theme.window)
      box(zr, ui.theme.frame, 2)
      let zs = TextStyle(serif: st.serif, mono: st.mono, size: big.size * 2)
      let s = $Rune(chars[hover])
      text(zr.x + (z - textWidth(s, zs)) div 2, zr.y + (z - lineHeight(zs)) div 2, s, ui.theme.text, zs)
    let shownCp = if hover >= 0: chars[hover] elif sel >= 0: chars[sel] else: -1
    label(if shownCp >= 0: "U+" & toHex(shownCp, 4) & "    " & $Rune(shownCp) else: "Click a character, then Select",
          enabled = shownCp >= 0)
    aboutBox(showAbout, "Character Map", DesktopVersion,
             ["Letters and symbols to copy into any program.", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
