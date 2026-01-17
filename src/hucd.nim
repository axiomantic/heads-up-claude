## hucd - Heads Up Claude Daemon
## Background process that monitors transcripts and fetches API data

import std/[os, parseopt, options, times, tables]
import shared/types
import hucd/[config, main, watcher, api, writer]

proc showHelp() =
  echo "hucd - Heads Up Claude Daemon"
  echo ""
  echo "Usage:"
  echo "  hucd [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --config=PATH    Path to config.json file"
  echo "                   (default: ~/.config/hucd/config.json)"
  echo "  --debug          Enable debug logging"
  echo "  --help           Show this help"
  echo ""
  echo "The daemon reads config from hucd.json which specifies:"
  echo "- Which Claude config directories to monitor"
  echo "- Scan/fetch intervals"
  echo "- Debug settings"
  echo ""
  echo "Config changes are hot-reloaded (no restart needed)."

proc main() =
  var configPath = getHomeDir() / ".config" / "hucd" / "config.json"
  var showHelpMode = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "config":
        configPath = p.val
      of "debug":
        debugMode = true
      of "help", "h":
        showHelpMode = true
      else:
        discard
    else:
      discard

  if showHelpMode:
    showHelp()
    return

  log(INFO, "Starting hucd daemon")
  log(INFO, "Config path: " & configPath)

  # Load config
  let config = loadConfig(configPath)

  if config.debug:
    debugMode = true

  log(INFO, "Monitoring " & $config.configDirs.len & " config directories")
  for dir in config.configDirs:
    log(INFO, "  - " & dir)

  # Initialize state
  var state = initDaemonState(config)
  state.configWatch = ConfigWatchState(configPath: configPath)
  initConfigWatch(state.configWatch)

  # Install signal handlers
  installSignalHandlers(state)

  # Load transcript cache from first config dir (if exists)
  # This avoids the 10+ minute initial scan on restart
  if config.configDirs.len > 0:
    let cacheDir = config.configDirs[0] / "heads-up-cache"
    state.transcriptCache = loadTranscriptCache(cacheDir)

  # Write initial status immediately (before slow scan)
  # This allows the install script to verify daemon is running
  log(INFO, "Writing initial status")
  for configDir in config.configDirs:
    let cacheDir = configDir / "heads-up-cache"
    let status = buildStatus(state, configDir)
    writeStatus(cacheDir, status)

  # Initial scan (updates cache incrementally - fast if cache was loaded)
  log(INFO, "Running initial scan")
  for configDir in config.configDirs:
    let projectsDir = configDir / "projects"
    scanTranscripts(projectsDir, state.transcriptCache)

    if hasCredentials(configDir):
      let creds = loadApiCredentials(configDir)
      if creds.isSome:
        let (sessionPct, sessionReset, weeklyPct, weeklyReset, apiResult) = fetchUsageFromApi(creds.get())
        if apiResult == ApiSuccess:
          state.apiStatus[configDir] = ApiStatus(
            configured: true,
            fetchedAt: some(now().utc()),
            sessionPercent: some(sessionPct),
            sessionReset: some(sessionReset),
            weeklyPercent: some(weeklyPct),
            weeklyReset: some(weeklyReset)
          )

    let cacheDir = configDir / "heads-up-cache"
    let status = buildStatus(state, configDir)
    writeStatus(cacheDir, status)

  # Run main loop
  runMainLoop(state)

  # Shutdown
  shutdown(state)

when isMainModule:
  main()
