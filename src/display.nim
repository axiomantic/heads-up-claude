import std/[strutils, osproc, json]
import types

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
  timeWeekly: string
) =
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
