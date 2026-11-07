## Word documents (.docx) for Write: read into its paragraphs and runs, and
## written from them -- headings, bold, italic, underline, strike, colors,
## sizes, the typewriter font, links, bulleted and numbered lists, quotes,
## alignment, and Arabic paragraphs right to left. What Write has no place
## for (pictures, tables' borders, footnotes, comments) is left out when
## read: a table's rows become lines, its cells parted by " | ".
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, xmltree, xmlparser, parsexml, tables, unicode, times, math, strtabs]
import retroui
import retroui/[richedit, zip]

# ---- reading ------------------------------------------------------------------------------------------

proc attrOf(n: XmlNode; name: string): string =
  ## A "w:val"-like attribute ("" when absent).
  if n == nil or n.kind != xnElement or n.attrs == nil: return ""
  n.attrs.getOrDefault(name)

proc child(n: XmlNode; tag: string): XmlNode =
  if n == nil or n.kind != xnElement: return nil
  for c in n:
    if c.kind == xnElement and c.tag == tag: return c
  nil

proc isOn(n: XmlNode): bool =
  ## <w:b/>, <w:b w:val="true"/>: on; <w:b w:val="0"/>: off.
  n != nil and n.attrOf("w:val") notin ["0", "false", "none"]

proc hexColor(s: string): Color =
  if s.len != 6 or s == "auto": return Color()
  try: color(uint8(parseHexInt(s[0 .. 1])), uint8(parseHexInt(s[2 .. 3])), uint8(parseHexInt(s[4 .. 5])))
  except ValueError: Color()

proc styleOf(rPr: XmlNode): RichStyle =
  if rPr == nil: return
  result.bold = rPr.child("w:b").isOn
  result.italic = rPr.child("w:i").isOn
  let u = rPr.child("w:u")
  result.underline = u != nil and u.attrOf("w:val") notin ["none", "0", "false"]
  result.strike = rPr.child("w:strike").isOn or rPr.child("w:dstrike").isOn
  let c = rPr.child("w:color")
  if c != nil: result.color = hexColor(c.attrOf("w:val"))
  let sz = rPr.child("w:sz")
  if sz != nil:
    try:
      let pt = parseFloat(sz.attrOf("w:val")) / 2
      if abs(pt - 11) > 0.6: result.size = pt / 11
    except ValueError: discard
  let f = rPr.child("w:rFonts")
  if f != nil:
    let name = (f.attrOf("w:ascii") & f.attrOf("w:hAnsi")).toLowerAscii
    result.mono = "courier" in name or "mono" in name or "consolas" in name

proc readNumbering(xml: string): Table[string, string] =
  ## numId -> the format of its first level ("bullet", "decimal"...).
  if xml.len == 0: return
  var abstractFmt: Table[string, string]
  try:
    let x = parseXml(xml)
    for n in x:
      if n.kind != xnElement: continue
      if n.tag == "w:abstractNum":
        for lvl in n:
          if lvl.kind == xnElement and lvl.tag == "w:lvl" and lvl.attrOf("w:ilvl") == "0":
            abstractFmt[n.attrOf("w:abstractNumId")] = lvl.child("w:numFmt").attrOf("w:val")
    for n in x:
      if n.kind == xnElement and n.tag == "w:num":
        result[n.attrOf("w:numId")] = abstractFmt.getOrDefault(n.child("w:abstractNumId").attrOf("w:val"))
  except CatchableError: discard

proc readRels(xml: string): Table[string, string] =
  ## A relationship's id -> its target (the links' addresses).
  if xml.len == 0: return
  try:
    for n in parseXml(xml):
      if n.kind == xnElement and n.tag == "Relationship":
        result[n.attrOf("Id")] = n.attrOf("Target")
  except CatchableError: discard

proc entry(archive: string; name: string): string =
  for e in zipEntries(archive):
    if e.name == name: return readEntry(archive, e)
  ""

proc readDocx*(path: string): RichDoc =
  ## A Word document as Write's paragraphs (raises when it is not one).
  let body = entry(path, "word/document.xml")
  if body.len == 0: raise newException(ValueError, "this is not a Word document (.docx)")
  let numbering = readNumbering(entry(path, "word/numbering.xml"))
  let rels = readRels(entry(path, "word/_rels/document.xml.rels"))
  let x = parseXml(body, {reportWhitespace})
  var paras: seq[RichPara]
  proc runsOf(n: XmlNode; p: var RichPara; link = "") =
    for c in n:
      if c.kind != xnElement: continue
      case c.tag
      of "w:r":
        var st = styleOf(c.child("w:rPr"))
        st.link = link
        for t in c:
          if t.kind != xnElement: continue
          case t.tag
          of "w:t": p.runs.add RichRun(text: t.innerText, style: st)
          of "w:tab": p.runs.add RichRun(text: "    ", style: st)
          of "w:br", "w:cr":
            # (a line's break: a paragraph of its own here)
            paras.add p
            p = RichPara(kind: p.kind, level: p.level, align: p.align)
          else: discard
      of "w:hyperlink":
        let target = rels.getOrDefault(c.attrOf("r:id"))
        runsOf(c, p, (if target.len > 0: target else: "#" & c.attrOf("w:anchor")))
      of "w:smartTag", "w:ins", "w:fldSimple", "w:sdt", "w:sdtContent":
        runsOf(c, p, link)
      else: discard
  proc paragraph(n: XmlNode) =
    var p = RichPara(kind: pkNormal)
    let pPr = n.child("w:pPr")
    if pPr != nil:
      let style = pPr.child("w:pStyle").attrOf("w:val").toLowerAscii
      if style in ["title", "heading1"]: (p.kind, p.level) = (pkHeading, 0)
      elif style in ["subtitle", "heading2"]: (p.kind, p.level) = (pkHeading, 1)
      elif style.startsWith("heading"): (p.kind, p.level) = (pkHeading, 2)
      elif "quote" in style: p.kind = pkQuote
      elif style.startsWith("listbullet"): p.kind = pkBullet
      elif style.startsWith("listnumber"): p.kind = pkNumber
      let num = pPr.child("w:numPr")
      if num != nil:
        let fmt = numbering.getOrDefault(num.child("w:numId").attrOf("w:val"), "bullet")
        p.kind = (if fmt == "bullet": pkBullet else: pkNumber)
        try: p.level = parseInt(num.child("w:ilvl").attrOf("w:val")) except ValueError: p.level = 0
      case pPr.child("w:jc").attrOf("w:val")
      of "center": p.align = alCenter
      of "right", "end": p.align = alRight
      else: p.align = alLeft
    runsOf(n, p)
    paras.add p
  proc walk(n: XmlNode) =
    for c in n:
      if c.kind != xnElement: continue
      case c.tag
      of "w:p": paragraph(c)
      of "w:tbl":
        # (a row a line, its cells parted)
        for tr in c:
          if tr.kind != xnElement or tr.tag != "w:tr": continue
          var row = RichPara(kind: pkNormal)
          var first = true
          for tc in tr:
            if tc.kind != xnElement or tc.tag != "w:tc": continue
            if not first: row.runs.add RichRun(text: " | ")
            first = false
            for cp in tc:
              if cp.kind == xnElement and cp.tag == "w:p":
                var tmp = RichPara()
                runsOf(cp, tmp)
                for r in tmp.runs: row.runs.add r
          paras.add row
      of "w:body", "w:sdt", "w:sdtContent": walk(c)
      else: discard
  walk(x)
  result = richDoc("")
  if paras.len > 0:
    result.paras = paras

# ---- writing ------------------------------------------------------------------------------------------

proc esc(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

proc hexOf(c: Color): string = toHex(int(c.r), 2) & toHex(int(c.g), 2) & toHex(int(c.b), 2)

proc rightToLeft(p: RichPara): bool =
  ## Whether its first letter that has a direction is Arabic or Hebrew.
  for r in p.runs:
    for ch in r.text.runes:
      let c = int(ch)
      if (c >= 0x0590 and c <= 0x08FF) or (c >= 0xFB1D and c <= 0xFEFC): return true
      if ch.isAlpha: return false
  false

const
  ContentTypes = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>"""
  PackageRels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>"""
  Styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="200"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="160"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/><w:color w:val="404040"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="40"/></w:pPr></w:style>
<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0000FF"/><w:u w:val="single"/></w:rPr></w:style>
</w:styles>"""

proc numberingXml(): string =
  ## Two lists: bullets (1) and numbers (2), nine levels each.
  result = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">"""
  for (id, fmt) in [(0, "bullet"), (1, "decimal")]:
    result.add "<w:abstractNum w:abstractNumId=\"" & $id & "\">"
    for lvl in 0 .. 8:
      let text = if fmt == "bullet": ["•", "◦", "▪"][lvl mod 3] else: "%" & $(lvl + 1) & "."
      result.add "<w:lvl w:ilvl=\"" & $lvl & "\"><w:start w:val=\"1\"/><w:numFmt w:val=\"" & fmt &
                 "\"/><w:lvlText w:val=\"" & text & "\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"" &
                 $(720 * (lvl + 1)) & "\" w:hanging=\"360\"/></w:pPr></w:lvl>"
    result.add "</w:abstractNum>"
  result.add "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>"
  result.add "<w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"

proc docxOf*(d: RichDoc; title = ""): string =
  ## The document as a Word file's bytes.
  var links: seq[string]
  var body = ""
  for p in d.paras:
    let rtl = rightToLeft(p)
    var pPr = ""
    case p.kind
    of pkHeading: pPr.add "<w:pStyle w:val=\"Heading" & $(clamp(p.level, 0, 2) + 1) & "\"/>"
    of pkQuote: pPr.add "<w:pStyle w:val=\"Quote\"/>"
    of pkBullet, pkNumber:
      pPr.add "<w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"" & $clamp(p.level, 0, 8) &
              "\"/><w:numId w:val=\"" & (if p.kind == pkBullet: "1" else: "2") & "\"/></w:numPr>"
    of pkNormal:
      if p.level > 0: pPr.add "<w:ind w:left=\"" & $(p.level * 720) & "\"/>"
    if rtl: pPr.add "<w:bidi/>"
    case p.align
    of alCenter: pPr.add "<w:jc w:val=\"center\"/>"
    of alRight: pPr.add "<w:jc w:val=\"" & (if rtl: "left" else: "right") & "\"/>"
    else: discard
    body.add "<w:p>"
    if pPr.len > 0: body.add "<w:pPr>" & pPr & "</w:pPr>"
    for r in p.runs:
      if r.text.len == 0: continue
      let s = r.style
      var rPr = ""
      if s.mono: rPr.add "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\"/>"
      if s.bold: rPr.add "<w:b/><w:bCs/>"
      if s.italic: rPr.add "<w:i/><w:iCs/>"
      if s.strike: rPr.add "<w:strike/>"
      if s.color.a > 0: rPr.add "<w:color w:val=\"" & hexOf(s.color) & "\"/>"
      if s.size > 0 and abs(s.size - 1.0) > 0.01:
        let half = $int(round(s.size * 22))
        rPr.add "<w:sz w:val=\"" & half & "\"/><w:szCs w:val=\"" & half & "\"/>"
      if s.underline: rPr.add "<w:u w:val=\"single\"/>"
      if rtl: rPr.add "<w:rtl/>"
      if s.link.len > 0: rPr = "<w:rStyle w:val=\"Hyperlink\"/>" & rPr
      let run = "<w:r>" & (if rPr.len > 0: "<w:rPr>" & rPr & "</w:rPr>" else: "") &
                "<w:t xml:space=\"preserve\">" & esc(r.text) & "</w:t></w:r>"
      if s.link.len > 0 and not s.link.startsWith("#"):
        links.add s.link
        body.add "<w:hyperlink r:id=\"rIdL" & $links.len & "\">" & run & "</w:hyperlink>"
      else: body.add run
    body.add "</w:p>"
  let document = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>""" &
    body & """<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>"""
  var rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>"""
  for i, l in links:
    rels.add "\n<Relationship Id=\"rIdL" & $(i + 1) &
             "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"" &
             esc(l) & "\" TargetMode=\"External\"/>"
  rels.add "\n</Relationships>"
  let stamp = now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  let core = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>""" &
    esc(title) & """</dc:title><dcterms:created xsi:type="dcterms:W3CDTF">""" & stamp &
    """</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">""" & stamp & """</dcterms:modified></cp:coreProperties>"""
  var z = newZipWriter()
  z.addFile("[Content_Types].xml", ContentTypes)
  z.addFile("_rels/.rels", PackageRels)
  z.addFile("docProps/core.xml", core)
  z.addFile("word/document.xml", document)
  z.addFile("word/styles.xml", Styles)
  z.addFile("word/numbering.xml", numberingXml())
  z.addFile("word/_rels/document.xml.rels", rels)
  z.finish()
