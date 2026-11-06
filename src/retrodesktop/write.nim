## Write: the word processor 3.1 came with, made again on Retro Nim UI's rich
## text editor -- bold, italic, underline, sizes, colors, lists, alignment,
## undo -- saving documents as HTML (any browser, LibreOffice or AbiWord opens
## them) or as plain text.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils]
import retroui
import retroui/[richedit, report]
import common, link, help

var
  doc: RichDoc
  path = ""
  saved = true
  showOpen, showSave, askSave, showAbout, showError: bool
  then = ""                      # what to do once the question is answered
  errorText = ""
  pickPath = ""
  showPdf = false
  pdfPath = ""

proc docName(): string = (if path.len > 0: path.extractFilename else: "(Untitled)")

proc load(p: string) =
  try:
    let text = readFile(p)
    let ext = p.splitFile.ext.toLowerAscii
    doc = if ext in [".html", ".htm", ".xhtml"]: richFromHtml(text) else: richDoc(text)
    path = p
    saved = true
  except CatchableError as e:
    errorText = "Cannot open " & p.extractFilename & ":\n" & e.msg
    showError = true

proc store(p: string): bool =
  try:
    let ext = p.splitFile.ext.toLowerAscii
    if ext in [".html", ".htm", ".xhtml"]:
      writeFile(p, "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>" &
                p.splitFile.name & "</title></head>\n<body>\n" & toHtml(doc) & "\n</body></html>\n")
    else:
      writeFile(p, toPlainText(doc))
    path = p
    saved = true
    true
  except CatchableError as e:
    errorText = "Cannot save " & p.extractFilename & ":\n" & e.msg
    showError = true
    false

proc save(): bool =
  if path.len == 0:
    pickPath = getHomeDir() / "Document.html"
    showSave = true
    false
  else: store(path)

proc carryOn() =
  case then
  of "new":
    doc = richDoc("")
    path = ""
    saved = true
  of "open":
    pickPath = (if path.len > 0: path.parentDir else: getHomeDir())
    showOpen = true
  of "exit": quitApp()
  else: discard
  then = ""

proc ask(what: string) =
  ## `what` ("new", "open", "exit") once the changes are saved, or not.
  then = what
  if saved: carryOn() else: askSave = true

proc runWrite*(args: seq[string]) =
  ## Write (with `args`: the document to open).
  doc = richDoc("")
  if args.len > 0 and fileExists(args[0]): load(absolutePath(args[0]))
  applyDesktopLook()
  openApp("Write", scaled(640), scaled(480), frame = wfSystem, userFrame = false, id = "write")
  showArt("write")
  followLook()
  doc.spell = false
  while beginFrame():
    helpKeys("write")
    let wanted = "Write - " & docName()
    if ui.title != wanted: setTitle(wanted)
    if closeRequested() and not saved:
      cancelClose()
      ask("exit")
    menubar:
      menu "&File":
        if menuItem("&New", "Ctrl+N"): ask("new")
        if menuItem("&Open...", "Ctrl+O"): ask("open")
        if menuItem("&Save", "Ctrl+S"): discard save()
        if menuItem("Save &As..."):
          pickPath = (if path.len > 0: path else: getHomeDir() / "Document.html")
          showSave = true
        menuSeparator()
        if menuItem("&Print to PDF...", "Ctrl+P"):
          pdfPath = (if path.len > 0: path.changeFileExt(".pdf") else: getHomeDir() / "Document.pdf")
          showPdf = true
        menuSeparator()
        if menuItem("E&xit"): ask("exit")
      menu "&Edit":
        if menuItem("&Undo", "Ctrl+Z", enabled = richCanUndo(doc)): richUndo(doc)
        if menuItem("&Redo", "Ctrl+Y", enabled = richCanRedo(doc)): richRedo(doc)
        menuSeparator()
        if menuItem("Select &All", "Ctrl+A"): richSelectAll(doc)
      menu "&Character":
        let st = richState(doc)
        if menuItem("&Bold", "Ctrl+B", checked = st.bold): richBold(doc)
        if menuItem("&Italic", "Ctrl+I", checked = st.italic): richItalic(doc)
        if menuItem("&Underline", "Ctrl+U", checked = st.underline): richUnderline(doc)
        menuSeparator()
        for (name, k) in richSizes:
          if menuItem(name, checked = abs((if st.size <= 0: 1.0 else: st.size) - k) < 0.01):
            richSize(doc, k)
      menu "&Paragraph":
        let a = richAlignment(doc)
        if menuItem("&Left", checked = a == alLeft): richAlign(doc, alLeft)
        if menuItem("&Centered", checked = a == alCenter): richAlign(doc, alCenter)
        if menuItem("&Right", checked = a == alRight): richAlign(doc, alRight)
        menuSeparator()
        if menuItem("&Bullets", checked = richParaKind(doc) == pkBullet): richList(doc, pkBullet)
        if menuItem("&Numbers", checked = richParaKind(doc) == pkNumber): richList(doc, pkNumber)
      menu "&Help":
        if menuItem("&Help Topics", "F1"): openHelp("write")
        menuSeparator()
        if menuItem("&About Write..."): showAbout = true
    if hotkeyPressed("Ctrl+N"): ask("new")
    if hotkeyPressed("Ctrl+O"): ask("open")
    if hotkeyPressed("Ctrl+S"): discard save()
    if hotkeyPressed("Ctrl+P"):
      pdfPath = (if path.len > 0: path.changeFileExt(".pdf") else: getHomeDir() / "Document.pdf")
      showPdf = true
    richToolbar(doc)
    if richEdit(doc, placeholder = "Write here"): saved = false
    # the dialogs
    if fileDialog(showOpen, pickPath, fmOpen, ["Write Documents (*.html;*.htm)", "Text Files (*.txt)",
                  "All Files (*.*)"]):
      load(pickPath)
    if fileDialog(showSave, pickPath, fmSave, ["Write Documents (*.html)", "Text Files (*.txt)"],
                  title = "Save As"):
      var p = pickPath
      if p.splitFile.ext.len == 0: p &= ".html"
      if store(p) and then.len > 0: carryOn()
    if fileDialog(showPdf, pdfPath, fmSave, ["PDF Documents (*.pdf)"], title = "Print to PDF"):
      # (the document as pages: its HTML laid out by Retro Nim UI's reports)
      var p = pdfPath
      if p.splitFile.ext.toLowerAscii != ".pdf": p &= ".pdf"
      try:
        let r = reportFromHtml("<html><body>" & toHtml(doc) & "</body></html>", title = docName())
        r.savePdf(p)
        launch(selfCommand("pdf") & " " & quoteShell(p))
      except CatchableError as e:
        errorText = "The PDF could not be made: " & e.msg
        showError = true
    if askSave:
      let r = msgBox(askSave, "Write", "Save the changes to " & docName() & "?",
                     ["&Yes", "&No", "Cancel"], miQuestion)
      if r == 1:
        if save(): carryOn()
      elif r == 2:
        saved = true
        carryOn()
      elif r == 3: then = ""
    if showError: discard msgBox(showError, "Write", errorText, ["OK"], miStop)
    aboutBox(showAbout, "Write", DesktopVersion,
             ["Documents with bold, italic, sizes, colors, lists and alignment, kept " &
              "as HTML (or as plain text).", "Part of " & DesktopName & "."])
    endFrame()
    appFrameDone()
  closeApp()
