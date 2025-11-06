import std/[json, os, times, streams, options, osproc, strutils, re]
import types

proc getFirstTimestampAndContextTokens*(transcriptPath: string): (Option[DateTime], Option[DateTime], int, int, int, int) =
  try:
    if not fileExists(transcriptPath):
      return (none(DateTime), none(DateTime), 0, 0, 0, 0)

    let stream = newFileStream(transcriptPath, fmRead)
    if stream.isNil:
      return (none(DateTime), none(DateTime), 0, 0, 0, 0)

    defer: stream.close()

    var firstTimestamp = none(DateTime)
    var lastTimestamp = none(DateTime)
    var tokensAfterLastSummary = 0
    var lastCacheReadTokens = 0
    var lastNewTokens = 0
    var messageCount = 0
    var line: string

    while stream.readLine(line):
      try:
        let entry = parseJson(line)

        if entry.hasKey("timestamp"):
          let ts = entry["timestamp"].getStr()
          let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
          if firstTimestamp.isNone:
            firstTimestamp = some(parsedTs)
          lastTimestamp = some(parsedTs)

        if entry.hasKey("type") and entry["type"].getStr() == "summary":
          tokensAfterLastSummary = 0
          messageCount = 0
          continue

        if entry.hasKey("type") and (entry["type"].getStr() == "user" or entry["type"].getStr() == "assistant"):
          messageCount += 1

        if entry.hasKey("message") and entry["message"].hasKey("usage"):
          let usage = entry["message"]["usage"]

          if usage.hasKey("cache_read_input_tokens"):
            lastCacheReadTokens = usage["cache_read_input_tokens"].getInt()

          lastNewTokens = 0
          if usage.hasKey("input_tokens"):
            lastNewTokens += usage["input_tokens"].getInt()
          if usage.hasKey("cache_creation_input_tokens"):
            lastNewTokens += usage["cache_creation_input_tokens"].getInt()
          if usage.hasKey("output_tokens"):
            lastNewTokens += usage["output_tokens"].getInt()

          tokensAfterLastSummary += lastNewTokens
      except:
        continue

    let contextTokens = lastCacheReadTokens + lastNewTokens

    return (firstTimestamp, lastTimestamp, contextTokens, lastCacheReadTokens, tokensAfterLastSummary, messageCount)
  except:
    return (none(DateTime), none(DateTime), 0, 0, 0, 0)

proc loadPlanConfig*(claudeConfigDir: string): PlanLimits =
  let configPath = claudeConfigDir / "heads_up_config.json"

  if not fileExists(configPath):
    return PlanLimits(name: "Free", fiveHourMessages: 10, weeklyHoursMin: 0, weeklyHoursMax: 0)

  try:
    let config = parseFile(configPath)
    result.fiveHourMessages = config.getOrDefault("five_hour_messages").getInt(10)
    result.weeklyHoursMin = config.getOrDefault("weekly_hours_min").getInt(0)

    # Set the plan name based on the plan type
    let planType = config.getOrDefault("plan").getStr("free")
    case planType
    of "free":
      result.name = "Free"
      result.weeklyHoursMax = 0
    of "pro":
      result.name = "Pro"
      result.weeklyHoursMax = 80
    of "max5":
      result.name = "Max 5"
      result.weeklyHoursMax = 280
    of "max20":
      result.name = "Max 20"
      result.weeklyHoursMax = 480
    else:
      result.name = "Pro"
      result.weeklyHoursMax = 80
  except:
    result.name = "Free"
    result.fiveHourMessages = 10
    result.weeklyHoursMin = 0
    result.weeklyHoursMax = 0

proc estimateUsageFromTranscripts*(projectsDir: string, limits: PlanLimits): (int, int, string, float, int, string) =
  var messages5hr = 0
  var percent5hr = 0
  var time5hr = ""
  var hoursWeekly = 0.0
  var percentWeekly = 0
  var timeWeekly = ""

  if not dirExists(projectsDir):
    return (0, 0, "", 0.0, 0, "")

  let now = now().utc()
  let fiveHoursAgo = now - initDuration(hours = 5)
  let sevenDaysAgo = now - initDuration(days = 7)

  var recentMessages = 0
  var weeklyTokens = 0
  var oldestRecentTime = none(DateTime)
  var oldestWeeklyTime = none(DateTime)

  try:
    for kind, path in walkDir(projectsDir):
      if kind == pcDir:
        for transcript in walkFiles(path / "*.jsonl"):
          let (firstTs, lastTs, _, _, _, msgCount) = getFirstTimestampAndContextTokens(transcript)

          if lastTs.isSome:
            let lastTime = lastTs.get()

            if lastTime >= fiveHoursAgo:
              recentMessages += msgCount
              if oldestRecentTime.isNone or firstTs.get() < oldestRecentTime.get():
                oldestRecentTime = firstTs

            if lastTime >= sevenDaysAgo:
              if firstTs.isSome and firstTs.get() >= sevenDaysAgo:
                let duration = lastTime - firstTs.get()
                weeklyTokens += int(duration.inMinutes)
                if oldestWeeklyTime.isNone or firstTs.get() < oldestWeeklyTime.get():
                  oldestWeeklyTime = firstTs
  except:
    discard

  percent5hr = min(100, int((recentMessages.float / limits.fiveHourMessages.float) * 100.0))
  messages5hr = recentMessages

  if oldestRecentTime.isSome:
    let resetTime = oldestRecentTime.get() + initDuration(hours = 5)
    if resetTime > now:
      let remaining = resetTime - now
      let hoursLeft = remaining.inHours
      let minsLeft = remaining.inMinutes mod 60
      if hoursLeft > 0:
        time5hr = $hoursLeft & "h" & $minsLeft & "m"
      else:
        time5hr = $minsLeft & "m"

  if limits.weeklyHoursMin > 0:
    hoursWeekly = weeklyTokens.float / 60.0
    percentWeekly = min(100, int((hoursWeekly / limits.weeklyHoursMin.float) * 100.0))

    if oldestWeeklyTime.isSome:
      let resetTime = oldestWeeklyTime.get() + initDuration(days = 7)
      if resetTime > now:
        let remaining = resetTime - now
        let daysLeft = remaining.inDays
        let hoursLeft = remaining.inHours mod 24
        if daysLeft > 0:
          timeWeekly = $daysLeft & "d" & $hoursLeft & "h"
        else:
          timeWeekly = $hoursLeft & "h"

  return (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly)

proc stripAnsi(s: string): string =
  ## Remove ANSI escape codes from string
  result = s.replace(re"\x1b\[[0-9;]*[a-zA-Z]", "")
  result = result.replace(re"\x1b\[?[0-9;]*[a-zA-Z]", "")
  result = result.replace("\x1b", "")

proc parseResetTime(resetStr: string): string =
  ## Parse reset time like "8:59pm (America/Chicago)" and convert to relative time with day
  ## Returns format like "5h30m" for session or "2d5h" for weekly
  try:
    # Extract the time part (e.g., "8:59pm")
    let timeMatch = resetStr.find(re"(\d+):(\d+)(am|pm)")
    if timeMatch < 0:
      return ""

    let timePart = resetStr[0..<resetStr.find(" (")]
    var hour = 0
    var minute = 0

    # Parse hour and minute
    let colonPos = timePart.find(":")
    if colonPos > 0:
      hour = parseInt(timePart[0..<colonPos])
      let minuteEnd = if timePart.contains("am"): timePart.find("am") else: timePart.find("pm")
      minute = parseInt(timePart[colonPos+1..<minuteEnd])

      # Convert to 24-hour format
      if timePart.contains("pm") and hour != 12:
        hour += 12
      elif timePart.contains("am") and hour == 12:
        hour = 0

    # Get current time (in UTC, we'll assume the timezone matches system for simplicity)
    let nowLocal = now()
    var resetTime = initDateTime(nowLocal.monthday, nowLocal.month, nowLocal.year, hour, minute, 0, nowLocal.timezone)

    # If reset time is in the past, it's tomorrow/next week
    if resetTime <= nowLocal:
      resetTime = resetTime + initDuration(days = 1)

    let remaining = resetTime - nowLocal
    let daysLeft = remaining.inDays
    let hoursLeft = remaining.inHours mod 24
    let minsLeft = remaining.inMinutes mod 60

    if daysLeft > 0:
      return $daysLeft & "d" & $hoursLeft & "h"
    elif hoursLeft > 0:
      return $hoursLeft & "h" & $minsLeft & "m"
    else:
      return $minsLeft & "m"
  except:
    return ""

proc getRealUsageData*(): (int, string, int, string) =
  ## Get real usage data from claude /config
  ## Returns (sessionPercent, sessionResetTime, weeklyPercent, weeklyResetTime)

  # Find the get_usage.exp script - it's installed in the same directory as the binary
  let scriptPath = getAppDir() / "get_usage.exp"

  if not fileExists(scriptPath):
    return (0, "", 0, "")

  try:
    let (output, exitCode) = execCmdEx(scriptPath)

    if exitCode != 0:
      return (0, "", 0, "")

    # Parse the output
    var sessionPercent = 0
    var sessionResetTime = ""
    var weeklyPercent = 0
    var weeklyResetTime = ""

    let lines = output.splitLines()
    var i = 0

    while i < lines.len:
      let cleanLine = lines[i].stripAnsi().strip()

      # Look for "Current session"
      if "Current session" in cleanLine:
        # Next line should have the percentage
        if i + 1 < lines.len:
          let percentLine = lines[i + 1].stripAnsi()
          let matches = percentLine.findAll(re"\d+")
          if matches.len > 0:
            sessionPercent = parseInt(matches[0])

        # Line after that should have reset time
        if i + 2 < lines.len:
          let resetLine = lines[i + 2].stripAnsi().strip()
          if "Resets" in resetLine:
            let parts = resetLine.split("Resets ")
            if parts.len > 1:
              sessionResetTime = parseResetTime(parts[1].strip())

      # Look for "Current week (all models)"
      elif "Current week (all models)" in cleanLine:
        # Next line should have the percentage
        if i + 1 < lines.len:
          let percentLine = lines[i + 1].stripAnsi()
          let matches = percentLine.findAll(re"\d+")
          if matches.len > 0:
            weeklyPercent = parseInt(matches[0])

        # Line after that should have reset time
        if i + 2 < lines.len:
          let resetLine = lines[i + 2].stripAnsi().strip()
          if "Resets" in resetLine:
            let parts = resetLine.split("Resets ")
            if parts.len > 1:
              weeklyResetTime = parseResetTime(parts[1].strip())

      inc i

    return (sessionPercent, sessionResetTime, weeklyPercent, weeklyResetTime)
  except:
    return (0, "", 0, "")
