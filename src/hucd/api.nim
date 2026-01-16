## API polling for Claude.ai usage data

import std/[os, json, options, osproc, strutils, times]
import ../shared/types

const
  CURL_TIMEOUT_SECONDS = 10
  API_BASE_URL = "https://claude.ai/api/organizations/"

type
  ApiResult* = enum
    ApiSuccess,
    ApiAuthFailed,
    ApiNetworkError,
    ApiParseError

proc loadApiCredentials*(configDir: string): Option[ApiCredentials] =
  ## Load API credentials from heads_up_config.json
  let configPath = configDir / "heads_up_config.json"

  if not fileExists(configPath):
    return none(ApiCredentials)

  try:
    let config = parseFile(configPath)
    let sessionKey = config.getOrDefault("session_key").getStr("")
    let orgId = config.getOrDefault("org_id").getStr("")

    if sessionKey.len > 0 and orgId.len > 0:
      return some(ApiCredentials(sessionKey: sessionKey, organizationId: orgId))
    return none(ApiCredentials)
  except:
    return none(ApiCredentials)

proc hasCredentials*(configDir: string): bool =
  ## Check if valid API credentials are configured
  loadApiCredentials(configDir).isSome

proc parseApiResponse*(body: string): (int, string, int, string) =
  ## Parse API response JSON and extract usage data
  ## Returns: (sessionPercent, sessionReset, weeklyPercent, weeklyReset)
  var sessionPercent = 0
  var sessionReset = ""
  var weeklyPercent = 0
  var weeklyReset = ""

  try:
    let data = parseJson(body)

    # Parse 5-hour utilization
    if data.hasKey("five_hour"):
      let fiveHour = data["five_hour"]
      if fiveHour.hasKey("utilization"):
        let util = fiveHour["utilization"]
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
  except:
    discard

  return (sessionPercent, sessionReset, weeklyPercent, weeklyReset)

proc fetchUsageFromApi*(creds: ApiCredentials): (int, string, int, string, ApiResult) =
  ## Fetch usage data from Claude.ai API
  ## Returns: (sessionPercent, sessionReset, weeklyPercent, weeklyReset, result)
  log(DEBUG, "Fetching usage from API")

  let url = API_BASE_URL & creds.organizationId & "/usage"
  let curlCmd = "curl -s --max-time " & $CURL_TIMEOUT_SECONDS &
                " -w '\\n%{http_code}' -H 'Cookie: sessionKey=" & creds.sessionKey &
                "' -H 'Accept: application/json' '" & url & "'"

  try:
    let (output, exitCode) = execCmdEx(curlCmd, options = {poUsePath})

    if exitCode != 0:
      log(DEBUG, "curl failed with exit code " & $exitCode)
      return (0, "", 0, "", ApiNetworkError)

    let lines = output.strip().split('\n')
    if lines.len < 2:
      return (0, "", 0, "", ApiParseError)

    let httpCode = try: parseInt(lines[^1]) except: 0
    let body = lines[0..^2].join("\n")

    if httpCode == 401 or httpCode == 403:
      log(DEBUG, "API auth failed (expired credentials)")
      return (0, "", 0, "", ApiAuthFailed)

    if httpCode < 200 or httpCode >= 300:
      log(DEBUG, "API HTTP error: " & $httpCode)
      return (0, "", 0, "", ApiNetworkError)

    let (sessionPct, sessionReset, weeklyPct, weeklyReset) = parseApiResponse(body)
    log(DEBUG, "API success: session=" & $sessionPct & "% weekly=" & $weeklyPct & "%")
    return (sessionPct, sessionReset, weeklyPct, weeklyReset, ApiSuccess)

  except Exception as e:
    log(DEBUG, "API exception: " & e.msg)
    return (0, "", 0, "", ApiParseError)
