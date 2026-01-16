import std/[json, os, times, streams, options, osproc, strutils]
import types

const
  MAX_DIRECT_READ_BYTES = 10 * 1024 * 1024  # 10MB - files larger than this use tail

proc getFirstTimestampAndContextTokens*(transcriptPath: string): (Option[DateTime], Option[DateTime], int, int, int, int) =
  try:
    if not fileExists(transcriptPath):
      return (none(DateTime), none(DateTime), 0, 0, 0, 0)

    let fileSize = getFileSize(transcriptPath)
    debugLog("Transcript size: " & $(fileSize div 1024) & "KB")

    # For large files, use tail to only read the last portion
    # This is much faster than reading 400MB line by line
    var lines: seq[string]
    if fileSize > MAX_DIRECT_READ_BYTES:
      debugLog("Large file detected, using tail for last 2000 lines")
      let (output, exitCode) = execCmdEx("tail -n 2000 " & quoteShell(transcriptPath))
      if exitCode == 0:
        lines = output.splitLines()
      else:
        return (none(DateTime), none(DateTime), 0, 0, 0, 0)
    else:
      let stream = newFileStream(transcriptPath, fmRead)
      if stream.isNil:
        return (none(DateTime), none(DateTime), 0, 0, 0, 0)
      defer: stream.close()
      var line: string
      while stream.readLine(line):
        lines.add(line)

    var firstTimestamp = none(DateTime)
    var lastTimestamp = none(DateTime)
    var tokensAfterLastSummary = 0
    var lastCacheReadTokens = 0
    var lastNewTokens = 0
    var messageCount = 0

    for line in lines:
      if line.len == 0:
        continue
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
  except Exception as e:
    debugLog("getFirstTimestampAndContextTokens error: " & e.msg)
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

proc countMessagesInWindow(transcriptPath: string, windowStart: DateTime): int =
  ## Count messages (user/assistant) with timestamps >= windowStart
  try:
    if not fileExists(transcriptPath):
      return 0

    let stream = newFileStream(transcriptPath, fmRead)
    if stream.isNil:
      return 0

    defer: stream.close()

    var count = 0
    var line: string

    while stream.readLine(line):
      try:
        let entry = parseJson(line)

        # Only count user/assistant messages with timestamps in the window
        if entry.hasKey("type") and entry.hasKey("timestamp"):
          let msgType = entry["type"].getStr()
          if msgType == "user" or msgType == "assistant":
            let ts = entry["timestamp"].getStr()
            let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
            if parsedTs >= windowStart:
              count += 1
      except:
        continue

    return count
  except:
    return 0

proc getSessionDurationInWindow(transcriptPath: string, windowStart: DateTime): int =
  ## Get session duration in minutes for activity within the time window
  try:
    if not fileExists(transcriptPath):
      return 0

    let stream = newFileStream(transcriptPath, fmRead)
    if stream.isNil:
      return 0

    defer: stream.close()

    var firstInWindow = none(DateTime)
    var lastInWindow = none(DateTime)
    var line: string

    while stream.readLine(line):
      try:
        let entry = parseJson(line)

        if entry.hasKey("timestamp"):
          let ts = entry["timestamp"].getStr()
          let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
          if parsedTs >= windowStart:
            if firstInWindow.isNone:
              firstInWindow = some(parsedTs)
            lastInWindow = some(parsedTs)
      except:
        continue

    if firstInWindow.isSome and lastInWindow.isSome:
      let duration = lastInWindow.get() - firstInWindow.get()
      return int(duration.inMinutes)
    return 0
  except:
    return 0

type
  ApiCredentials* = object
    sessionKey*: string
    orgId*: string

proc loadApiCredentials*(claudeConfigDir: string): Option[ApiCredentials] =
  ## Load API credentials from heads_up_config.json
  let configPath = claudeConfigDir / "heads_up_config.json"

  if not fileExists(configPath):
    return none(ApiCredentials)

  try:
    let config = parseFile(configPath)
    let sessionKey = config.getOrDefault("session_key").getStr("")
    let orgId = config.getOrDefault("org_id").getStr("")

    if sessionKey.len > 0 and orgId.len > 0:
      return some(ApiCredentials(sessionKey: sessionKey, orgId: orgId))
    return none(ApiCredentials)
  except:
    return none(ApiCredentials)

type
  ApiResult* = enum
    ApiSuccess,
    ApiAuthFailed,  # 401/403 - credentials expired
    ApiNetworkError,
    ApiParseError

const
  CURL_TIMEOUT_SECONDS = 10

proc fetchUsageFromApi*(creds: ApiCredentials): (int, string, int, string, ApiResult) =
  ## Fetch usage data from Claude.ai API using curl
  ## Returns: (session%, sessionReset, weekly%, weeklyReset, result)
  debugLog("fetchUsageFromApi: starting")
  try:
    let url = "https://claude.ai/api/organizations/" & creds.orgId & "/usage"
    let curlCmd = "curl -s --max-time " & $CURL_TIMEOUT_SECONDS & " -w '\\n%{http_code}' -H 'Cookie: sessionKey=" & creds.sessionKey & "' -H 'Accept: application/json' '" & url & "'"
    debugLog("fetchUsageFromApi: executing curl (timeout=" & $CURL_TIMEOUT_SECONDS & "s)")

    let (output, exitCode) = execCmdEx(curlCmd, options = {poUsePath})
    debugLog("fetchUsageFromApi: curl exitCode=" & $exitCode)

    if exitCode != 0:
      debugLog("fetchUsageFromApi: curl failed with exit code " & $exitCode)
      return (0, "", 0, "", ApiNetworkError)

    # Parse output - last line is HTTP status code
    let lines = output.strip().split('\n')
    if lines.len < 2:
      debugLog("fetchUsageFromApi: unexpected output format, lines=" & $lines.len)
      return (0, "", 0, "", ApiParseError)

    let httpCode = try: parseInt(lines[^1]) except: 0
    let body = lines[0..^2].join("\n")
    debugLog("fetchUsageFromApi: httpCode=" & $httpCode)

    # Check for auth failures
    if httpCode == 401 or httpCode == 403:
      debugLog("fetchUsageFromApi: auth failed (expired credentials)")
      return (0, "", 0, "", ApiAuthFailed)

    if httpCode < 200 or httpCode >= 300:
      debugLog("fetchUsageFromApi: HTTP error " & $httpCode)
      return (0, "", 0, "", ApiNetworkError)

    let data = parseJson(body)

    var sessionPercent = 0
    var sessionReset = ""
    var weeklyPercent = 0
    var weeklyReset = ""

    # Parse 5-hour utilization
    if data.hasKey("five_hour"):
      let fiveHour = data["five_hour"]
      if fiveHour.hasKey("utilization"):
        let util = fiveHour["utilization"]
        # Handle both int and float
        if util.kind == JInt:
          sessionPercent = util.getInt()
        elif util.kind == JFloat:
          sessionPercent = int(util.getFloat())

      if fiveHour.hasKey("resets_at"):
        let resetTime = fiveHour["resets_at"].getStr()
        if resetTime.len > 0:
          try:
            let parsed = parse(resetTime, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
            let remaining = parsed - now().utc()
            if remaining.inSeconds > 0:
              let hours = remaining.inHours
              let mins = remaining.inMinutes mod 60
              if hours > 0:
                sessionReset = $hours & "h" & $mins & "m"
              else:
                sessionReset = $mins & "m"
          except:
            discard

    # Parse weekly utilization
    if data.hasKey("seven_day"):
      let sevenDay = data["seven_day"]
      if sevenDay.hasKey("utilization"):
        let util = sevenDay["utilization"]
        if util.kind == JInt:
          weeklyPercent = util.getInt()
        elif util.kind == JFloat:
          weeklyPercent = int(util.getFloat())

      if sevenDay.hasKey("resets_at"):
        let resetTime = sevenDay["resets_at"].getStr()
        if resetTime.len > 0:
          try:
            let parsed = parse(resetTime, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
            let remaining = parsed - now().utc()
            if remaining.inSeconds > 0:
              let days = remaining.inDays
              let hours = remaining.inHours mod 24
              if days > 0:
                weeklyReset = $days & "d" & $hours & "h"
              else:
                weeklyReset = $hours & "h"
          except:
            discard

    debugLog("fetchUsageFromApi: success session=" & $sessionPercent & "% weekly=" & $weeklyPercent & "%")
    return (sessionPercent, sessionReset, weeklyPercent, weeklyReset, ApiSuccess)
  except Exception as e:
    debugLog("fetchUsageFromApi: exception " & e.msg)
    return (0, "", 0, "", ApiParseError)

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
  var weeklyMinutes = 0
  var oldestRecentTime = none(DateTime)
  var oldestWeeklyTime = none(DateTime)

  try:
    for kind, path in walkDir(projectsDir):
      if kind == pcDir:
        for transcript in walkFiles(path / "*.jsonl"):
          # Count messages actually sent in the last 5 hours
          let msgCount = countMessagesInWindow(transcript, fiveHoursAgo)
          if msgCount > 0:
            recentMessages += msgCount
            # Track oldest message time for reset calculation
            let (firstTs, _, _, _, _, _) = getFirstTimestampAndContextTokens(transcript)
            if firstTs.isSome:
              let clampedFirst = if firstTs.get() < fiveHoursAgo: fiveHoursAgo else: firstTs.get()
              if oldestRecentTime.isNone or clampedFirst < oldestRecentTime.get():
                oldestRecentTime = some(clampedFirst)

          # Get session duration within the last 7 days
          let sessionMinutes = getSessionDurationInWindow(transcript, sevenDaysAgo)
          if sessionMinutes > 0:
            weeklyMinutes += sessionMinutes
            let (firstTs, _, _, _, _, _) = getFirstTimestampAndContextTokens(transcript)
            if firstTs.isSome:
              let clampedFirst = if firstTs.get() < sevenDaysAgo: sevenDaysAgo else: firstTs.get()
              if oldestWeeklyTime.isNone or clampedFirst < oldestWeeklyTime.get():
                oldestWeeklyTime = some(clampedFirst)
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
    hoursWeekly = weeklyMinutes.float / 60.0
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

const
  CACHE_SOFT_TTL_SECONDS = 60   # Trigger background refresh after 60s
  CACHE_MAX_AGE_SECONDS = 300   # After 5 minutes, cache is too stale

proc readCache(cachePath: string): (int, string, int, string, bool, bool, bool, int64, string) =
  ## Read cached usage data.
  ## Returns (session%, sessionReset, weekly%, weeklyReset, isFresh, isUsable, authFailed, ageSeconds, sessionKeyHash)
  ## - isFresh: cache is within soft TTL, no refresh needed
  ## - isUsable: cache can be returned while refreshing in background
  ## - authFailed: cached auth failure (don't retry API)
  ## - sessionKeyHash: hash of session key when cache was written (to detect key changes)
  debugLog("readCache: checking " & cachePath)
  if not fileExists(cachePath):
    debugLog("readCache: file not found")
    return (0, "", 0, "", false, false, false, -1, "")

  try:
    let cacheInfo = getFileInfo(cachePath)
    let age = now().utc() - cacheInfo.lastWriteTime.utc()
    let ageSeconds = age.inSeconds
    let isFresh = ageSeconds < CACHE_SOFT_TTL_SECONDS
    let isUsable = ageSeconds < CACHE_MAX_AGE_SECONDS

    let cache = parseFile(cachePath)
    let authFailed = cache.getOrDefault("authFailed").getBool(false)
    let cachedKeyHash = cache.getOrDefault("sessionKeyHash").getStr("")

    debugLog("readCache: age=" & $ageSeconds & "s fresh=" & $isFresh & " usable=" & $isUsable & " authFailed=" & $authFailed)

    return (
      cache["sessionPercent"].getInt(),
      cache["sessionResetTime"].getStr(),
      cache["weeklyPercent"].getInt(),
      cache["weeklyResetTime"].getStr(),
      isFresh,
      isUsable,
      authFailed,
      ageSeconds,
      cachedKeyHash
    )
  except Exception as e:
    debugLog("readCache: exception " & e.msg)
    return (0, "", 0, "", false, false, false, -1, "")

proc hashSessionKey(key: string): string =
  ## Simple hash of session key (just use last 8 chars to detect changes)
  if key.len > 8:
    result = key[^8..^1]
  else:
    result = key

proc spawnBackgroundRefresh(cacheDir, cachePath: string, creds: ApiCredentials) =
  ## Spawn a background process to refresh the cache without blocking.
  let lockPath = cacheDir / "refresh.lock"

  # Check if refresh already in progress (lock file exists and is recent)
  if fileExists(lockPath):
    try:
      let lockInfo = getFileInfo(lockPath)
      let lockAge = now().utc() - lockInfo.lastWriteTime.utc()
      if lockAge.inSeconds < 30:  # Lock is fresh, refresh in progress
        debugLog("spawnBackgroundRefresh: refresh already in progress")
        return
      # Lock is stale, remove it
      removeFile(lockPath)
    except:
      discard

  debugLog("spawnBackgroundRefresh: spawning background refresh")

  # Create a shell command that:
  # 1. Creates lock file
  # 2. Calls curl
  # 3. Parses response and updates cache
  # 4. Removes lock file
  let url = "https://claude.ai/api/organizations/" & creds.orgId & "/usage"
  let script = """
    set -e
    LOCK_FILE="$1"
    CACHE_FILE="$2"
    URL="$3"
    SESSION_KEY="$4"

    # Create lock
    echo $$ > "$LOCK_FILE"
    trap "rm -f '$LOCK_FILE'" EXIT

    # Fetch data
    RESPONSE=$(curl -s --max-time 10 -w '\n%{http_code}' \
      -H "Cookie: sessionKey=$SESSION_KEY" \
      -H "Accept: application/json" \
      "$URL" 2>/dev/null) || exit 1

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    # Only update cache on success
    if [ "$HTTP_CODE" = "200" ]; then
      # Parse JSON and extract values (simple grep-based parsing)
      FIVE_HOUR=$(echo "$BODY" | grep -o '"five_hour"[^}]*}' | head -1)
      SEVEN_DAY=$(echo "$BODY" | grep -o '"seven_day"[^}]*}' | head -1)

      SESSION_PCT=$(echo "$FIVE_HOUR" | grep -o '"utilization"[^,}]*' | grep -o '[0-9]*' | head -1)
      WEEKLY_PCT=$(echo "$SEVEN_DAY" | grep -o '"utilization"[^,}]*' | grep -o '[0-9]*' | head -1)

      SESSION_PCT=${SESSION_PCT:-0}
      WEEKLY_PCT=${WEEKLY_PCT:-0}

      # Write cache atomically
      TMP_CACHE="${CACHE_FILE}.tmp.$$"
      cat > "$TMP_CACHE" << EOF
{"sessionPercent":$SESSION_PCT,"sessionResetTime":"","weeklyPercent":$WEEKLY_PCT,"weeklyResetTime":""}
EOF
      mv "$TMP_CACHE" "$CACHE_FILE"
    fi
  """

  try:
    # Write script to temp file and execute in background
    let scriptPath = cacheDir / "refresh.sh"
    writeFile(scriptPath, script)

    # Use shell to run in background with nohup
    let cmd = "nohup /bin/bash " & quoteShell(scriptPath) & " " &
              quoteShell(lockPath) & " " &
              quoteShell(cachePath) & " " &
              quoteShell(url) & " " &
              quoteShell(creds.sessionKey) & " >/dev/null 2>&1 &"
    discard execShellCmd(cmd)
  except Exception as e:
    debugLog("spawnBackgroundRefresh: exception " & e.msg)

type
  UsageStatus* = enum
    UsageOk,           # Fresh data from API
    UsageStale,        # Using stale cache
    UsageAuthExpired,  # API credentials expired - need refresh
    UsageNoCredentials,# No API credentials configured
    UsageEstimates     # Falling back to transcript estimates

proc getRealUsageData*(claudeConfigDir: string): (int, string, int, string, UsageStatus) =
  ## Get real usage data from Claude.ai API with smart caching.
  ## - Fresh cache (< 60s): return immediately
  ## - Stale cache (60s-300s): return immediately + background refresh
  ## - Very stale/missing (> 300s): blocking API call
  ##
  ## Returns: (session%, sessionReset, weekly%, weeklyReset, status)
  debugLog("getRealUsageData: starting")

  # Use claude config dir for cache (persists across reboots, not cleaned up)
  let cacheDir = claudeConfigDir / "heads-up-cache"
  let cachePath = cacheDir / "usage_cache.json"
  debugLog("getRealUsageData: cacheDir=" & cacheDir)

  # Ensure cache directory exists
  try:
    createDir(cacheDir)
  except:
    discard

  # Load API credentials
  debugLog("getRealUsageData: loading API credentials")
  let credsOpt = loadApiCredentials(claudeConfigDir)
  if credsOpt.isNone:
    debugLog("getRealUsageData: no API credentials configured")
    return (0, "", 0, "", UsageNoCredentials)

  let creds = credsOpt.get()
  debugLog("getRealUsageData: credentials found")

  # Check cache state
  let (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, isFresh, isUsable, authFailed, _, cachedKeyHash) = readCache(cachePath)

  # Check if credentials changed since cache was written
  let currentKeyHash = hashSessionKey(creds.sessionKey)
  let credentialsChanged = cachedKeyHash.len > 0 and cachedKeyHash != currentKeyHash

  # Case 0: Cached auth failure - don't hammer API with bad credentials
  # BUT if credentials changed, try the new ones
  if authFailed and not credentialsChanged:
    debugLog("getRealUsageData: cached auth failure (same credentials), not retrying API")
    return (0, "", 0, "", UsageAuthExpired)

  if credentialsChanged:
    debugLog("getRealUsageData: credentials changed, will retry API")

  # Case 1: Fresh cache - return immediately, no refresh needed
  if isFresh:
    debugLog("getRealUsageData: cache is fresh, returning")
    return (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, UsageOk)

  # Case 2: Usable but stale cache - return immediately + background refresh
  if isUsable and (cachedSession > 0 or cachedWeekly > 0):
    debugLog("getRealUsageData: cache usable but stale, spawning background refresh")
    spawnBackgroundRefresh(cacheDir, cachePath, creds)
    return (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, UsageOk)

  # Case 3: No usable cache - must block on API call
  debugLog("getRealUsageData: no usable cache, blocking on API call")
  let (sessionPct, sessionReset, weeklyPct, weeklyReset, apiResult) = fetchUsageFromApi(creds)

  case apiResult
  of ApiSuccess:
    debugLog("getRealUsageData: API success, updating cache")
    try:
      let tmpCache = cachePath & ".tmp." & $getCurrentProcessId()
      let cacheJson = %*{
        "sessionPercent": sessionPct,
        "sessionResetTime": sessionReset,
        "weeklyPercent": weeklyPct,
        "weeklyResetTime": weeklyReset,
        "authFailed": false,
        "sessionKeyHash": currentKeyHash
      }
      writeFile(tmpCache, $cacheJson)
      moveFile(tmpCache, cachePath)
    except:
      discard
    return (sessionPct, sessionReset, weeklyPct, weeklyReset, UsageOk)

  of ApiAuthFailed:
    debugLog("getRealUsageData: API auth failed, caching failure")
    # Cache the auth failure so we don't keep hammering
    try:
      let tmpCache = cachePath & ".tmp." & $getCurrentProcessId()
      let cacheJson = %*{
        "sessionPercent": 0,
        "sessionResetTime": "",
        "weeklyPercent": 0,
        "weeklyResetTime": "",
        "authFailed": true,
        "sessionKeyHash": currentKeyHash
      }
      writeFile(tmpCache, $cacheJson)
      moveFile(tmpCache, cachePath)
    except:
      discard
    return (0, "", 0, "", UsageAuthExpired)

  of ApiNetworkError, ApiParseError:
    debugLog("getRealUsageData: API error")
    # Return stale cache if available
    if cachedSession > 0 or cachedWeekly > 0:
      return (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, UsageStale)
    return (0, "", 0, "", UsageEstimates)
