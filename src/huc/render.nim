## Statusline rendering utilities

import std/strutils

var gUseEmoji* = true

proc renderTag*(tag: string, tagColor: string): string =
  ## Render optional tag prefix (user provides their own brackets if desired)
  if tag.len == 0:
    return ""

  if tagColor.len > 0:
    result = tagColor & tag & "\x1b[0m" & " | "
  else:
    result = tag & " | "

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
