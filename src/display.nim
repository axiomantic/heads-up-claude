import std/[strutils, osproc, json]
import types

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

proc getGitBranch*(dir: string): string =
  try:
    let (output, exitCode) = execCmdEx("git -C " & quoteShell(dir) & " rev-parse --abbrev-ref HEAD 2>/dev/null")
    if exitCode == 0:
      result = output.strip()
    else:
      result = ""
  except:
    result = ""

proc formatTokenCount*(count: int): string =
  if count >= 1000:
    result = formatFloat(count.float / 1000.0, ffDecimal, 1) & "K"
  else:
    result = $count

proc renderStatusLine*(
  displayProjectDir: string,
  branch: string,
  limits: PlanLimits,
  model: string,
  data: JsonNode,
  conversationTokens: int,
  conversationPercentUsed: int,
  cacheReadTokens: int,
  messages5hr: int,
  percent5hr: int,
  time5hr: string,
  hoursWeekly: float,
  percentWeekly: int,
  timeWeekly: string,
  tag: string = "",
  tagColor: string = ""
) =
  if tag.len > 0:
    stdout.write("[ ")
    if tagColor.len > 0:
      var colorCode = tagColor
      if not tagColor.startsWith("\x1b["):
        let converted = colorNameToAnsi(tagColor)
        if converted.len > 0:
          colorCode = converted
      stdout.write(colorCode, tag, "\x1b[0m")
    else:
      stdout.write(tag)
    stdout.write(" ] | ")

  stdout.write("\x1b[34m", displayProjectDir, "\x1b[0m")

  if branch.len > 0:
    stdout.write(" | ")
    stdout.write("\x1b[35m", branch, "\x1b[0m")

  stdout.write(" | ")

  stdout.write("\x1b[35m", limits.name, "\x1b[0m")

  var modelDisplay = model
  if data.hasKey("model") and data["model"].hasKey("thinking"):
    let thinkingEnabled = data["model"]["thinking"].getBool()
    if thinkingEnabled:
      modelDisplay = "\xf0\x9f\xa7\xa0 " & model

  stdout.write(" | ")
  stdout.write("\x1b[36m", modelDisplay, "\x1b[0m")

  stdout.write(" | ")
  if gUseEmoji:
    stdout.write("\xf0\x9f\x92\xac ")
  else:
    stdout.write("CTX ")
  let conversationTokenDisplay = formatTokenCount(conversationTokens)

  if conversationPercentUsed >= 100:
    stdout.write("\x1b[1;91m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ compact imminent\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN compact imminent\x1b[0m")
  elif conversationPercentUsed >= 90:
    stdout.write("\x1b[1;91m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ ", conversationPercentUsed, "%\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN ", conversationPercentUsed, "%\x1b[0m")
  elif conversationPercentUsed >= 80:
    stdout.write("\x1b[31m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[31m", conversationPercentUsed, "%\x1b[0m")
  else:
    stdout.write("\x1b[33m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[33m", conversationPercentUsed, "%\x1b[0m")

  if cacheReadTokens > 0:
    let cacheDisplay = formatTokenCount(cacheReadTokens)
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\xf0\x9f\x9f\xa2 ")
    else:
      stdout.write("CACHE ")
    stdout.write("\x1b[32m", cacheDisplay)
    if not gUseEmoji:
      stdout.write(" cached")
    stdout.write("\x1b[0m")

  stdout.write(" | ")
  if gUseEmoji:
    stdout.write("\xf0\x9f\x95\x90 ")
  else:
    stdout.write("5HR ")

  if percent5hr >= 100:
    stdout.write("\x1b[1;91m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ limit exceeded\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN limit exceeded\x1b[0m")
  elif percent5hr >= 90:
    stdout.write("\x1b[1;91m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ ", percent5hr, "%\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN ", percent5hr, "%\x1b[0m")
  elif percent5hr >= 80:
    stdout.write("\x1b[31m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[31m", percent5hr, "%\x1b[0m")
  else:
    stdout.write("\x1b[36m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[36m", percent5hr, "%\x1b[0m")

  if time5hr.len > 0:
    stdout.write(" (")
    stdout.write("\x1b[36m", time5hr, "\x1b[0m")
    stdout.write(")")

  stdout.write(" | ")
  if gUseEmoji:
    stdout.write("\xf0\x9f\x93\x85 ")
  else:
    stdout.write("WK ")

  let hoursDisplay = formatFloat(hoursWeekly, ffDecimal, 1)

  if percentWeekly >= 100:
    stdout.write("\x1b[1;91m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ limit exceeded\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN limit exceeded\x1b[0m")
  elif percentWeekly >= 90:
    stdout.write("\x1b[1;91m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ ", percentWeekly, "%\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN ", percentWeekly, "%\x1b[0m")
  elif percentWeekly >= 80:
    stdout.write("\x1b[31m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[31m", percentWeekly, "%\x1b[0m")
  else:
    stdout.write("\x1b[36m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[36m", percentWeekly, "%\x1b[0m")

  if timeWeekly.len > 0:
    stdout.write(" (")
    stdout.write("\x1b[36m", timeWeekly, "\x1b[0m")
    stdout.write(")")
