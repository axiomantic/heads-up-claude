## Statusline rendering utilities

import std/strutils

var gUseEmoji* = true

proc formatTokenCount*(count: int): string =
  if count >= 1000:
    result = formatFloat(count.float / 1000.0, ffDecimal, 1) & "K"
  else:
    result = $count

proc formatDuration*(minutes: int): string =
  ## Format duration in human readable form
  if minutes >= 60:
    let hours = minutes div 60
    let mins = minutes mod 60
    return $hours & "h" & $mins & "m"
  else:
    return $minutes & "m"

proc renderWaiting*(msg: string): string =
  ## Render waiting message
  if gUseEmoji:
    result = "\x1b[90m(" & msg & ")\x1b[0m"
  else:
    result = "\x1b[90m[" & msg & "]\x1b[0m"

proc renderWarning*(msg: string): string =
  ## Render warning message in yellow
  result = "\x1b[33m[" & msg & "]\x1b[0m"

proc renderError*(msg: string): string =
  ## Render error message in red
  result = "\x1b[31m[error: " & msg & "]\x1b[0m"

proc getColorForPercent(pct: int): string =
  ## Get ANSI color based on percentage
  if pct >= 100:
    return "\x1b[1;91m"  # bright red bold
  elif pct >= 90:
    return "\x1b[1;91m"  # bright red bold
  elif pct >= 80:
    return "\x1b[31m"    # red
  else:
    return "\x1b[36m"    # cyan

proc renderContextSection*(tokens: int, cacheReadTokens: int, percentUsed: int): string =
  ## Render context/token section
  let tokenDisplay = formatTokenCount(tokens)
  let color = if percentUsed >= 90: "\x1b[1;91m"
              elif percentUsed >= 80: "\x1b[31m"
              else: "\x1b[33m"

  result = ""
  if gUseEmoji:
    result.add("\xf0\x9f\x92\xac ")  # speech bubble
  else:
    result.add("CTX ")

  result.add(color & tokenDisplay & "\x1b[0m")
  result.add(" " & color & $percentUsed & "%\x1b[0m")

  if cacheReadTokens > 0:
    let cacheDisplay = formatTokenCount(cacheReadTokens)
    if gUseEmoji:
      result.add(" \xf0\x9f\x9f\xa2 ")  # green circle
    else:
      result.add(" CACHE ")
    result.add("\x1b[32m" & cacheDisplay & "\x1b[0m")

proc renderUsageSection*(fiveHourMessages: int, planName: string,
                          sessionPercent: int, sessionReset: string,
                          hoursWeekly: float, weeklyHoursMin: int,
                          weeklyPercent: int, weeklyReset: string,
                          useApi: bool): string =
  ## Render usage section (session + weekly)
  result = ""

  # Session (5-hour)
  let sessionColor = getColorForPercent(sessionPercent)
  if gUseEmoji:
    result.add("\xf0\x9f\x95\x90 ")  # clock
  else:
    result.add("5HR ")

  # Show messages/limit for session
  let messagesUsed = int((sessionPercent.float / 100.0) * fiveHourMessages.float)
  result.add(sessionColor & $messagesUsed & "/" & $fiveHourMessages & "\x1b[0m")
  result.add(" " & sessionColor & $sessionPercent & "%\x1b[0m")

  if sessionReset.len > 0:
    result.add(" (" & "\x1b[36m" & sessionReset & "\x1b[0m" & ")")

  result.add(" | ")

  # Weekly
  let weeklyColor = getColorForPercent(weeklyPercent)
  if gUseEmoji:
    result.add("\xf0\x9f\x93\x85 ")  # calendar
  else:
    result.add("WK ")

  let hoursDisplay = formatFloat(hoursWeekly, ffDecimal, 1)
  result.add(weeklyColor & hoursDisplay & "h/" & $weeklyHoursMin & "h\x1b[0m")
  result.add(" " & weeklyColor & $weeklyPercent & "%\x1b[0m")

  if weeklyReset.len > 0:
    result.add(" (" & "\x1b[36m" & weeklyReset & "\x1b[0m" & ")")

proc renderTag*(tag: string, tagColor: string): string =
  ## Render optional tag prefix
  if tag.len == 0:
    return ""

  result = "[ "
  if tagColor.len > 0:
    result.add(tagColor & tag & "\x1b[0m")
  else:
    result.add(tag)
  result.add(" ] | ")

proc colorNameToAnsi*(colorName: string): string =
  let normalized = colorName.toLowerAscii().strip()
  case normalized
  of "black": result = "\x1b[30m"
  of "red": result = "\x1b[31m"
  of "green": result = "\x1b[32m"
  of "yellow": result = "\x1b[33m"
  of "blue": result = "\x1b[34m"
  of "magenta", "purple": result = "\x1b[35m"
  of "cyan": result = "\x1b[36m"
  of "white": result = "\x1b[37m"
  of "gray", "grey": result = "\x1b[90m"
  of "bright-red", "brightred": result = "\x1b[91m"
  of "bright-green", "brightgreen": result = "\x1b[92m"
  of "bright-yellow", "brightyellow": result = "\x1b[93m"
  of "bright-blue", "brightblue": result = "\x1b[94m"
  of "bright-magenta", "brightmagenta", "bright-purple", "brightpurple": result = "\x1b[95m"
  of "bright-cyan", "brightcyan": result = "\x1b[96m"
  of "bright-white", "brightwhite": result = "\x1b[97m"
  else: result = ""
