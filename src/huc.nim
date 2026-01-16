## huc - Heads Up Claude Statusline
## Lightweight binary that reads status.json and renders output

import std/[os, json, parseopt, strutils, options, paths, terminal, osproc]
import shared/types
import huc/[reader, render, daemon]
import installer

proc showHelp() =
  echo "huc - Heads Up Claude Statusline"
  echo ""
  echo "Usage:"
  echo "  huc [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --tag=TEXT               Prepend [ TEXT ] | to statusline"
  echo "  --tag-color=COLOR        Color for tag (blue, red, green, etc.)"
  echo "  --claude-config-dir=PATH Claude config directory (default: ~/.claude)"
  echo "  --no-emoji               Use text instead of emoji"
  echo "  --debug                  Enable debug output"
  echo "  --help                   Show this help"
  echo ""
  echo "Daemon Management:"
  echo "  --daemon-status          Show daemon status and config"
  echo "  --daemon-restart         Restart the daemon"
  echo "  --daemon-logs            Show recent daemon logs"
  echo ""
  echo "Setup:"
  echo "  --install                Run interactive setup (updates settings.json)"
  echo "  --setup-api              Configure API credentials"
  echo ""
  echo "Examples:"
  echo "  huc --tag=\"DEV\" --tag-color=green"
  echo "  huc --daemon-status"
  echo "  huc --daemon-logs"

proc main() =
  var tag = ""
  var tagColor = ""
  var claudeConfigDir = ""
  var showHelpMode = false
  var daemonStatusMode = false
  var daemonRestartMode = false
  var daemonLogsMode = false
  var installMode = false
  var setupApiMode = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "tag": tag = p.val
      of "tag-color": tagColor = p.val
      of "claude-config-dir": claudeConfigDir = p.val
      of "no-emoji": gUseEmoji = false
      of "debug": debugMode = true
      of "help", "h": showHelpMode = true
      of "daemon-status": daemonStatusMode = true
      of "daemon-restart": daemonRestartMode = true
      of "daemon-logs": daemonLogsMode = true
      of "install": installMode = true
      of "setup-api": setupApiMode = true
      else: discard
    else: discard

  if showHelpMode:
    showHelp()
    return

  # Resolve config dir
  if claudeConfigDir.len == 0:
    let envConfigDir = getEnv("CLAUDE_CONFIG_DIR")
    if envConfigDir.len > 0:
      claudeConfigDir = string(expandTilde(Path(envConfigDir)))
    else:
      claudeConfigDir = getHomeDir() / ".claude"
  else:
    claudeConfigDir = string(expandTilde(Path(claudeConfigDir)))

  # Daemon management commands
  if daemonStatusMode:
    echo getDaemonStatus()
    return

  if daemonRestartMode:
    if restartDaemon():
      echo "Daemon restarted successfully"
    else:
      echo "Failed to restart daemon"
    return

  if daemonLogsMode:
    echo getDaemonLogs()
    return

  # Install mode - run interactive installer
  if installMode:
    let projectsDir = claudeConfigDir / "projects"
    runInstall(projectsDir, claudeConfigDir, tag, tagColor)
    return

  # Setup API credentials
  if setupApiMode:
    echo "API credential setup not yet implemented"
    echo "Please configure manually in: " & claudeConfigDir / "heads_up_config.json"
    return

  # Main statusline mode - read stdin for context, read status.json for usage
  let cacheDir = claudeConfigDir / "heads-up-cache"
  let statusPath = cacheDir / "status.json"

  # Read status
  let statusOpt = readStatus(statusPath)

  # Check if stdin is available (Claude Code provides context)
  var inputJson: JsonNode = nil
  if not stdin.isatty():
    try:
      let input = stdin.readAll()
      if input.strip().len > 0:
        inputJson = parseJson(input)
    except:
      discard

  # Build output
  var output = ""

  # Tag prefix
  if tag.len > 0:
    var tc = tagColor
    if tc.len > 0:
      let converted = colorNameToAnsi(tc)
      if converted.len > 0:
        tc = converted
    output.add(renderTag(tag, tc))

  # Project/branch from stdin
  # CRITICAL: Validate JSON structure before accessing nested fields
  if inputJson != nil:
    let workspace = inputJson.getOrDefault("workspace")
    if workspace.kind == JObject:
      let projectDirNode = workspace.getOrDefault("project_dir")
      if projectDirNode.kind == JString:
        let home = getEnv("HOME")
        let projectDir = projectDirNode.getStr()
        let displayProjectDir = if projectDir.startsWith(home):
          "~" & projectDir[home.len..^1]
        else:
          projectDir

        output.add("\x1b[34m" & displayProjectDir & "\x1b[0m")

        # Get git branch
        try:
          let (branchOutput, exitCode) = execCmdEx("git --no-optional-locks -C " & quoteShell(projectDir) & " rev-parse --abbrev-ref HEAD 2>/dev/null")
          if exitCode == 0:
            let branch = branchOutput.strip()
            if branch.len > 0:
              output.add(" | \x1b[35m" & branch & "\x1b[0m")
        except:
          discard

  if statusOpt.isNone:
    # No status file - daemon not running or first start
    output.add(" | " & renderWaiting("waiting for data"))
    stdout.write(output)
    return

  let status = statusOpt.get()

  # Plan name
  output.add(" | \x1b[35m" & status.plan.name & "\x1b[0m")

  # Model from stdin
  if inputJson != nil and inputJson.hasKey("model"):
    var modelDisplay = inputJson["model"]["display_name"].getStr()
    if inputJson["model"].hasKey("thinking") and inputJson["model"]["thinking"].getBool():
      modelDisplay = "\xf0\x9f\xa7\xa0 " & modelDisplay
    output.add(" | \x1b[36m" & modelDisplay & "\x1b[0m")

  # Context section
  output.add(" | " & renderContextSection(
    status.context.tokens,
    status.context.cacheReadTokens,
    status.context.percentUsed
  ))

  # Determine which usage data to show
  var useApiData = false
  if status.api.configured and status.api.error.isNone and not isApiStale(status):
    useApiData = true

  var sessionPercent, weeklyPercent: int
  var sessionReset, weeklyReset: string
  var hoursWeekly: float

  if useApiData and status.api.sessionPercent.isSome:
    sessionPercent = status.api.sessionPercent.get()
    sessionReset = status.api.sessionReset.get("")
    weeklyPercent = status.api.weeklyPercent.get(0)
    weeklyReset = status.api.weeklyReset.get("")
    hoursWeekly = if status.plan.weeklyHoursMin > 0:
      (weeklyPercent.float / 100.0) * status.plan.weeklyHoursMin.float
    else:
      0.0
  else:
    sessionPercent = status.estimates.sessionPercent
    sessionReset = status.estimates.sessionReset
    weeklyPercent = status.estimates.weeklyPercent
    weeklyReset = status.estimates.weeklyReset
    hoursWeekly = status.estimates.hoursWeekly

  output.add(" | " & renderUsageSection(
    status.plan.fiveHourMessages,
    status.plan.name,
    sessionPercent,
    sessionReset,
    hoursWeekly,
    status.plan.weeklyHoursMin,
    weeklyPercent,
    weeklyReset,
    useApiData
  ))

  # Warnings
  if isStatusStale(status):
    output.add(" | " & renderWarning("daemon stale"))

  if status.api.configured and status.api.error.isSome:
    if status.api.error.get() == "credentials expired":
      output.add(" | " & renderWarning("credentials expired: huc --setup-api"))

  if status.errors.daemon.isSome:
    output.add(" | " & renderError(status.errors.daemon.get()))

  stdout.write(output)

when isMainModule:
  main()
