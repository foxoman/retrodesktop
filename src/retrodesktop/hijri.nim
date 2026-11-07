## The Hijri date beside the Gregorian one: the tabular Islamic calendar
## (30 years: 11 of them with 355 days), as Windows and phones show it,
## with the days to add or take away (-2 to 2) where the month began on
## another day by the moon's sighting -- Control Panel > Date/Time sets them.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/times

const
  MonthsEn* = ["Muharram", "Safar", "Rabi' al-Awwal", "Rabi' al-Thani", "Jumada al-Ula",
               "Jumada al-Akhirah", "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhu al-Qa'dah",
               "Dhu al-Hijjah"]
  MonthsAr* = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب",
               "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]

proc julianDay(y, m, d: int): int =
  ## The Julian day number of a Gregorian date.
  let a = (14 - m) div 12
  let yy = y + 4800 - a
  let mm = m + 12 * a - 3
  d + (153 * mm + 2) div 5 + 365 * yy + yy div 4 - yy div 100 + yy div 400 - 32045

proc hijriOf*(y, m, d: int; adjust = 0): tuple[year, month, day: int] =
  ## The Hijri date of the Gregorian `y`-`m`-`d` (`adjust`: days).
  let jd = julianDay(y, m, d) + adjust
  # (the tabular calendar's epoch: 16 July 622, Julian day 1948440)
  let days = jd - 1948440 + 10632
  let n = (days - 1) div 10631
  var z = days - 10631 * n + 354
  let j = ((10985 - z) div 5316) * ((50 * z) div 17719) + (z div 5670) * ((43 * z) div 15238)
  z = z - ((30 - j) div 15) * ((17719 * j) div 50) - (j div 16) * ((15238 * j) div 43) + 29
  let month = (24 * z) div 709
  let day = z - (709 * month) div 24
  let year = 30 * n + j - 30
  (year, month, day)

proc hijriText*(t: DateTime; adjust = 0; arabic = false): string =
  ## "26 Jumada al-Ula 1448 AH" (or in Arabic: "٢٦ جمادى الأولى ١٤٤٨ هـ").
  let (y, m, d) = hijriOf(t.year, ord(t.month), t.monthday, adjust)
  if m notin 1 .. 12: return ""
  if arabic:
    const digits = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
    proc ar(n: int): string =
      for ch in $n: result.add digits[ord(ch) - ord('0')]
    ar(d) & " " & MonthsAr[m - 1] & " " & ar(y) & " هـ"
  else:
    $d & " " & MonthsEn[m - 1] & " " & $y & " AH"
