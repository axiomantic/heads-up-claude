## Daemon main loop and state management

import std/[os, times, tables, monotimes, options, posix, json, strutils]
import ../shared/types
import config, watcher, api, writer, pruner

type
  DaemonState* = object
    running*: bool
    config*: DaemonConfig
    transcriptCache*: TranscriptCache
    configWatch*: ConfigWatchState

    # Timer state per config_dir
    lastScan*: Table[string, MonoTime]
    lastApi*: Table[string, MonoTime]
    lastPrune*: MonoTime

    # API status per config_dir
    apiStatus*: Table[string, ApiStatus]

var globalState: ptr DaemonState

proc handleSignal(sig: cint) {.noconv.} =
  if globalState != nil:
    globalState.running = false
    log(INFO, "Received signal " & $sig & ", shutting down")

proc installSignalHandlers*(state: var DaemonState) =
  globalState = addr state

  var action: Sigaction
  action.sa_handler = handleSignal
  discard sigemptyset(action.sa_mask)
  action.sa_flags = 0

  discard sigaction(SIGTERM, action, nil)
  discard sigaction(SIGINT, action, nil)

proc initDaemonState*(config: DaemonConfig): DaemonState =
  ## Initialize daemon state with config
  result.running = true
  result.config = config
  result.transcriptCache = TranscriptCache(
    version: 1,
    lastPruned: now().utc(),
    transcripts: initTable[string, TranscriptEntry]()
  )
  result.lastScan = initTable[string, MonoTime]()
  result.lastApi = initTable[string, MonoTime]()
  result.apiStatus = initTable[string, ApiStatus]()
  result.lastPrune = getMonoTime()

  # Initialize per-config-dir state
  for configDir in config.configDirs:
    result.lastScan[configDir] = MonoTime()
    result.lastApi[configDir] = MonoTime()
    result.apiStatus[configDir] = ApiStatus(configured: false)

    # Ensure cache directory exists
    let cacheDir = configDir / "heads-up-cache"
    try:
      createDir(cacheDir)
    except:
      discard

proc elapsed(last: MonoTime, now: MonoTime): Duration =
  ## Calculate duration since last time
  if last == MonoTime():
    return initDuration(hours = 1)  # Force first run
  return now - last

proc shouldScan*(state: DaemonState, configDir: string): bool =
  ## Check if transcript scan is due for configDir
  let now = getMonoTime()
  let interval = initDuration(minutes = state.config.scanIntervalMinutes)
  if not state.lastScan.hasKey(configDir):
    return true
  return elapsed(state.lastScan[configDir], now) >= interval

proc shouldFetchApi*(state: DaemonState, configDir: string): bool =
  ## Check if API fetch is due for configDir (only if credentials configured)
  if not hasCredentials(configDir):
    return false
  let now = getMonoTime()
  let interval = initDuration(minutes = state.config.apiIntervalMinutes)
  if not state.lastApi.hasKey(configDir):
    return true
  return elapsed(state.lastApi[configDir], now) >= interval

proc shouldPrune*(state: DaemonState): bool =
  ## Check if cache prune is due
  let now = getMonoTime()
  let interval = initDuration(minutes = state.config.pruneIntervalMinutes)
  return elapsed(state.lastPrune, now) >= interval

proc loadPlanLimits(configDir: string): PlanStatus =
  ## Load plan limits from heads_up_config.json
  let configPath = configDir / "heads_up_config.json"
  result = PlanStatus(name: "Free", fiveHourMessages: 10, weeklyHoursMin: 0)

  if not fileExists(configPath):
    return

  try:
    let config = parseFile(configPath)
    result.fiveHourMessages = config.getOrDefault("five_hour_messages").getInt(10)
    result.weeklyHoursMin = config.getOrDefault("weekly_hours_min").getInt(0)

    let planType = config.getOrDefault("plan").getStr("free")
    case planType
    of "free": result.name = "Free"
    of "pro": result.name = "Pro"
    of "max5": result.name = "Max 5"
    of "max20": result.name = "Max 20"
    else: result.name = "Pro"
  except:
    discard

proc buildStatus*(state: DaemonState, configDir: string): Status =
  ## Build status object for a config directory
  let plan = loadPlanLimits(configDir)
  let apiStatus = state.apiStatus.getOrDefault(configDir, ApiStatus(configured: false))

  # Find most recent transcript in this config's projects
  var mostRecentPath = none(string)
  var mostRecentTokens = 0
  var mostRecentCache = 0
  var mostRecentMessages = 0
  let projectsDir = configDir / "projects"

  for path, entry in state.transcriptCache.transcripts:
    if path.startsWith(projectsDir):
      if mostRecentPath.isNone or entry.lastChecked > state.transcriptCache.transcripts[mostRecentPath.get()].lastChecked:
        mostRecentPath = some(path)
        mostRecentTokens = entry.tokensAfterSummary + entry.lastCacheReadTokens
        mostRecentCache = entry.lastCacheReadTokens
        mostRecentMessages = entry.messagesAfterSummary

  # Calculate context percentage
  let compactThreshold = 160000
  let contextPercent = if mostRecentTokens > 0: (mostRecentTokens * 100) div compactThreshold else: 0

  # Build estimates from transcripts (simplified - real impl would scan all recent)
  let estimates = EstimateStatus(
    calculatedAt: now().utc(),
    messages5hr: mostRecentMessages,
    sessionPercent: if plan.fiveHourMessages > 0: min(100, (mostRecentMessages * 100) div plan.fiveHourMessages) else: 0,
    sessionReset: "",
    hoursWeekly: 0.0,
    weeklyPercent: 0,
    weeklyReset: ""
  )

  result = Status(
    version: 1,
    updatedAt: now().utc(),
    configDir: configDir,
    api: apiStatus,
    estimates: estimates,
    context: ContextStatus(
      transcriptPath: mostRecentPath,
      tokens: mostRecentTokens,
      cacheReadTokens: mostRecentCache,
      percentUsed: contextPercent
    ),
    plan: plan,
    errors: ErrorStatus()
  )

proc runMainLoop*(state: var DaemonState) =
  ## Main daemon loop
  log(INFO, "Starting main loop")

  while state.running:
    let now = getMonoTime()

    # Check config changes (hot-reload)
    if configFileChanged(state.configWatch):
      log(INFO, "Config file changed, reloading")
      state.config = loadConfig(state.configWatch.configPath)

    for configDir in state.config.configDirs:
      let cacheDir = configDir / "heads-up-cache"
      let projectsDir = configDir / "projects"

      # Transcript scan
      if shouldScan(state, configDir):
        log(DEBUG, "Scanning transcripts for " & configDir)
        scanTranscripts(projectsDir, state.transcriptCache)
        state.lastScan[configDir] = now

      # API fetch
      if shouldFetchApi(state, configDir):
        log(DEBUG, "Fetching API data for " & configDir)
        let creds = loadApiCredentials(configDir)
        if creds.isSome:
          let (sessionPct, sessionReset, weeklyPct, weeklyReset, apiResult) = fetchUsageFromApi(creds.get())

          var apiStatus = ApiStatus(configured: true)
          case apiResult
          of ApiSuccess:
            apiStatus.fetchedAt = some(now().utc())
            apiStatus.sessionPercent = some(sessionPct)
            apiStatus.sessionReset = some(sessionReset)
            apiStatus.weeklyPercent = some(weeklyPct)
            apiStatus.weeklyReset = some(weeklyReset)
          of ApiAuthFailed:
            apiStatus.error = some("credentials expired")
          of ApiNetworkError:
            apiStatus.error = some("network error")
          of ApiParseError:
            apiStatus.error = some("parse error")

          state.apiStatus[configDir] = apiStatus
        state.lastApi[configDir] = now

      # Write status
      let status = buildStatus(state, configDir)
      writeStatus(cacheDir, status)

    # Prune cache
    if shouldPrune(state):
      log(DEBUG, "Pruning transcript cache")
      pruneTranscriptCache(state.transcriptCache)
      state.lastPrune = now

      # Write transcript cache to first config dir
      if state.config.configDirs.len > 0:
        let cacheDir = state.config.configDirs[0] / "heads-up-cache"
        writeTranscriptCache(cacheDir, state.transcriptCache)

    # Sleep
    sleep(5000)

  log(INFO, "Main loop exited")

proc shutdown*(state: var DaemonState) =
  ## Graceful shutdown
  log(INFO, "Shutting down daemon")

  # Save transcript cache
  if state.config.configDirs.len > 0:
    let cacheDir = state.config.configDirs[0] / "heads-up-cache"
    writeTranscriptCache(cacheDir, state.transcriptCache)

  # Write final status for each config dir
  for configDir in state.config.configDirs:
    let cacheDir = configDir / "heads-up-cache"
    let status = buildStatus(state, configDir)
    writeStatus(cacheDir, status)

  log(INFO, "Shutdown complete")
