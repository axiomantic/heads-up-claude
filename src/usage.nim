import std/[json, os, times, streams, options, tables]
import types, cache

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

proc roundToHour*(dt: DateTime): DateTime =
  result = dt
  result.minute = 0
  result.second = 0
  result.nanosecond = 0

proc calculateWindowEnd*(firstTimestamp: DateTime): DateTime =
  let startTime = roundToHour(firstTimestamp)
  result = startTime + initDuration(hours = 5)

proc getNextWeeklyReset*(): DateTime =
  let now = now().utc()

  var resetTime = now
  resetTime.hour = gWeeklyResetHourUTC
  resetTime.minute = 0
  resetTime.second = 0
  resetTime.nanosecond = 0

  let currentWeekday = now.weekday.ord
  let daysUntilReset = (gWeeklyResetDay - currentWeekday + 7) mod 7

  if daysUntilReset == 0:
    if now.hour >= gWeeklyResetHourUTC:
      resetTime = resetTime + initDuration(days = 7)
  else:
    resetTime = resetTime + initDuration(days = daysUntilReset)

  return resetTime

proc getFileTokensAndTimestamp*(filePath: string, cache: var Table[string, FileCache]): FileCache =
  try:
    var result = FileCache()
    if not fileExists(filePath):
      return result

    let modTime = getLastModificationTime(filePath)
    let cacheKey = getCacheKey(filePath, modTime)

    if cache.hasKey(cacheKey):
      return cache[cacheKey]

    let (firstTs, lastTs, contextTokens, cacheReadTokens, apiTokens, messageCount) = getFirstTimestampAndContextTokens(filePath)

    result.modTime = modTime
    result.contextTokens = contextTokens
    result.cacheReadTokens = cacheReadTokens
    result.apiTokens = apiTokens
    result.firstTimestamp = firstTs
    result.lastTimestamp = lastTs
    result.messageCount = messageCount
    cache[cacheKey] = result

    return result
  except:
    return FileCache()

proc calculate5HourAndWeeklyUsage*(projectsDir: string, cache: var Table[string, FileCache], currentPlan: PlanType): (int, int, string, float, int, string) =
  let now = now().utc()

  let nextReset = getNextWeeklyReset()
  let lastReset = nextReset - initDuration(days = 7)

  var messages5hr = 0
  var hoursWeekly = 0.0
  var latestWindowEnd = none(DateTime)
  var earliestThisWeek = none(DateTime)

  try:
    for file in walkFiles(projectsDir / "*.jsonl"):
      let sessionData = getFileTokensAndTimestamp(file, cache)

      if sessionData.firstTimestamp.isSome:
        let firstTs = sessionData.firstTimestamp.get()

        let windowEnd = calculateWindowEnd(firstTs)
        if windowEnd > now:
          messages5hr += sessionData.messageCount
          if latestWindowEnd.isNone or windowEnd > latestWindowEnd.get():
            latestWindowEnd = some(windowEnd)

        if sessionData.lastTimestamp.isSome:
          let lastTs = sessionData.lastTimestamp.get()
          if lastTs >= lastReset:
            let effectiveStart = if firstTs < lastReset: lastReset else: firstTs
            let duration = (lastTs - effectiveStart).inSeconds.float / 3600.0
            if duration > 0:
              hoursWeekly += duration

              if earliestThisWeek.isNone or effectiveStart < earliestThisWeek.get():
                earliestThisWeek = some(effectiveStart)
  except:
    discard

  let limits = PLAN_INFO[ord(currentPlan)]

  let percent5hr = if messages5hr > 0: (messages5hr * 100) div limits.fiveHourMessages else: 0

  let percentWeekly = if hoursWeekly > 0: int((hoursWeekly * 100.0) / limits.weeklyHoursMin.float) else: 0

  var time5hr = ""
  if latestWindowEnd.isSome:
    let remaining = latestWindowEnd.get() - now
    if remaining.inSeconds > 0:
      let hoursLeft = remaining.inHours
      let minsLeft = remaining.inMinutes mod 60
      if hoursLeft > 0:
        time5hr = $hoursLeft & "h" & $minsLeft & "m"
      else:
        time5hr = $minsLeft & "m"

  var timeWeekly = ""
  let remaining = nextReset - now
  if remaining.inSeconds > 0:
    let daysLeft = remaining.inDays
    let hoursLeft = remaining.inHours mod 24
    if daysLeft > 0:
      timeWeekly = $daysLeft & "d" & $hoursLeft & "h"
    else:
      timeWeekly = $hoursLeft & "h"

  return (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly)

proc detectPlan*(projectsDir: string): PlanType =
  var cache = loadCache()
  defer: saveCache(cache)

  let now = now().utc()
  var maxMessages5hr = 0

  try:
    for file in walkFiles(projectsDir / "*.jsonl"):
      let sessionData = getFileTokensAndTimestamp(file, cache)
      if sessionData.firstTimestamp.isSome:
        let windowEnd = calculateWindowEnd(sessionData.firstTimestamp.get())
        if windowEnd > now:
          if sessionData.messageCount > maxMessages5hr:
            maxMessages5hr = sessionData.messageCount
  except:
    discard

  if maxMessages5hr > 225:
    return Max20
  elif maxMessages5hr > 45:
    return Max5
  else:
    return Pro
