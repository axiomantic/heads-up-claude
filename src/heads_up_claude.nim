import std/[json, os, strutils, parseopt, paths, terminal]
import types, usage, display, installer

proc main() =
  debugLog("Starting heads-up-claude")
  debugLog("Args: " & commandLineParams().join(" "))

  var installMode = false
  var setupApiMode = false
  var showHelpMode = false
  var tag = ""
  var tagColor = ""
  var claudeConfigDir = ""

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      debugLog("Parsing option: " & p.key & "=" & p.val)
      case p.key
      of "install":
        installMode = true
      of "setup-api":
        setupApiMode = true
      of "help", "h":
        showHelpMode = true
      of "debug":
        gDebug = true
        debugLog("Debug mode enabled")
      of "no-emoji":
        gUseEmoji = false
      of "tag":
        tag = p.val
      of "tag-color":
        tagColor = p.val
      of "claude-config-dir":
        claudeConfigDir = p.val
      else:
        discard
    else:
      discard

  if showHelpMode:
    debugLog("Showing help and exiting")
    showHelp()
    return

  let home = getEnv("HOME")
  debugLog("HOME=" & home)

  # Resolve claudeConfigDir early for setup-api
  if claudeConfigDir.len == 0:
    let envConfigDir = getEnv("CLAUDE_CONFIG_DIR")
    if envConfigDir.len > 0:
      claudeConfigDir = string(expandTilde(Path(envConfigDir)))
      debugLog("Using CLAUDE_CONFIG_DIR env: " & claudeConfigDir)
    else:
      claudeConfigDir = home / ".claude"
      debugLog("Using default config dir: " & claudeConfigDir)
  else:
    claudeConfigDir = string(expandTilde(Path(claudeConfigDir)))
    debugLog("Using provided config dir: " & claudeConfigDir)

  if setupApiMode:
    debugLog("Running API setup mode")
    runApiSetup(claudeConfigDir)
    return

  if installMode:
    debugLog("Running install mode")
    let claudeProjects = claudeConfigDir / "projects"

    var projectsDir = ""
    if dirExists(claudeProjects):
      for kind, path in walkDir(claudeProjects):
        if kind == pcDir:
          projectsDir = path
          break

    runInstall(projectsDir, claudeConfigDir, tag, tagColor)
    return

  # Only read stdin when running as a statusline (not in install or help mode)
  debugLog("Running statusline mode")
  debugLog("Loading plan config")
  let limits = loadPlanConfig(claudeConfigDir)
  debugLog("Plan: " & limits.name)

  # Check if stdin is a TTY (would block forever waiting for input)
  if stdin.isatty():
    stderr.writeLine("Error: No input provided. This command expects JSON input from Claude Code.")
    stderr.writeLine("Use --help for usage information, or --install to configure.")
    quit(1)

  debugLog("Reading stdin...")
  let input = stdin.readAll()
  debugLog("Read " & $input.len & " bytes from stdin")

  if input.strip().len == 0:
    stderr.writeLine("Error: Empty input. This command expects JSON input from Claude Code.")
    stderr.writeLine("Use --help for usage information, or --install to configure.")
    quit(1)

  # Debug the std input JSON
  # writeFile("/tmp/statusline-input.json", input)

  let data = parseJson(input)

  let transcriptPath = data["transcript_path"].getStr()
  let projectDir = data["workspace"]["project_dir"].getStr()
  let model = data["model"]["display_name"].getStr()

  let displayProjectDir =
    if projectDir.startsWith(home):
      "~" & projectDir[home.len..^1]
    else:
      projectDir

  debugLog("Getting git branch...")
  let branch = getGitBranch(projectDir)
  debugLog("Got branch: " & branch)

  debugLog("Reading transcript...")
  let (_, _, conversationTokens, cacheReadTokens, _, _) = getFirstTimestampAndContextTokens(transcriptPath)
  debugLog("Got transcript tokens: " & $conversationTokens)

  let compactThreshold = try:
    parseInt(getEnv("CLAUDE_AUTO_COMPACT_THRESHOLD", "160000"))
  except:
    160000
  let conversationPercentUsed = if conversationTokens > 0: (conversationTokens * 100) div compactThreshold else: 0

  var tagColorForDisplay = tagColor
  if tagColor.len > 0:
    let converted = colorNameToAnsi(tagColor)
    if converted.len > 0:
      tagColorForDisplay = converted

  # Get real usage from Claude.ai API or fall back to estimates
  debugLog("Getting real usage data...")
  let (sessionPercent, sessionResetTime, weeklyPercent, weeklyResetTime, usageStatus) = getRealUsageData(claudeConfigDir)
  debugLog("Got usage data: session=" & $sessionPercent & "% status=" & $usageStatus)

  var messages5hr = 0
  var percent5hr = sessionPercent
  var time5hr = sessionResetTime
  var hoursWeekly = 0.0
  var percentWeekly = weeklyPercent
  var timeWeekly = weeklyResetTime
  var usingEstimates = false

  # Fall back to estimates if real data isn't available
  # BUT: Don't fall back for auth failures - just show expired message, don't scan 10k files
  if sessionPercent == 0 and weeklyPercent == 0 and usageStatus notin {UsageOk, UsageAuthExpired}:
    debugLog("Falling back to estimates from transcripts...")
    usingEstimates = true
    let projectsDir = claudeConfigDir / "projects"
    debugLog("Reading transcripts from: " & projectsDir)
    let (m5hr, p5hr, t5hr, hWeekly, pWeekly, tWeekly) =
      estimateUsageFromTranscripts(projectsDir, limits)
    debugLog("Estimates done: messages=" & $m5hr & " percent=" & $p5hr)
    messages5hr = m5hr
    percent5hr = p5hr
    time5hr = t5hr
    hoursWeekly = hWeekly
    percentWeekly = pWeekly
    timeWeekly = tWeekly
  else:
    # Calculate message count from percentage when using real data
    messages5hr = int((sessionPercent.float / 100.0) * limits.fiveHourMessages.float)
    # Calculate hours from percentage when using real data
    if limits.weeklyHoursMin > 0:
      hoursWeekly = (weeklyPercent.float / 100.0) * limits.weeklyHoursMin.float

  debugLog("Rendering status line...")
  renderStatusLine(
    displayProjectDir,
    branch,
    limits,
    model,
    data,
    conversationTokens,
    conversationPercentUsed,
    cacheReadTokens,
    messages5hr,
    percent5hr,
    time5hr,
    hoursWeekly,
    percentWeekly,
    timeWeekly,
    tag,
    tagColorForDisplay
  )
  debugLog("Render complete")

  # Show status indicators based on usage data source
  case usageStatus
  of UsageAuthExpired:
    stdout.write(" | ")
    stdout.write("\x1b[33m[credentials expired: heads-up-claude --setup-api]\x1b[0m")
  of UsageNoCredentials:
    if usingEstimates:
      stdout.write(" | ")
      stdout.write("\x1b[90m~estimates\x1b[0m")
  of UsageStale:
    stdout.write(" | ")
    stdout.write("\x1b[90m[stale]\x1b[0m")
  of UsageEstimates:
    stdout.write(" | ")
    stdout.write("\x1b[90m~estimates\x1b[0m")
  of UsageOk:
    discard  # Fresh data, no indicator needed

when isMainModule:
  main()
