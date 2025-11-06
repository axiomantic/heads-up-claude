import std/[json, os, strutils, parseopt, paths, times]
import types, usage, display, installer

proc main() =
  var installMode = false
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
      case p.key
      of "install":
        installMode = true
      of "help", "h":
        showHelpMode = true
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
    showHelp()
    return

  let home = getEnv("HOME")
  if claudeConfigDir.len == 0:
    let envConfigDir = getEnv("CLAUDE_CONFIG_DIR")
    if envConfigDir.len > 0:
      claudeConfigDir = string(expandTilde(Path(envConfigDir)))
    else:
      claudeConfigDir = home / ".claude"
  else:
    claudeConfigDir = string(expandTilde(Path(claudeConfigDir)))

  if installMode:
    let claudeProjects = claudeConfigDir / "projects"

    var projectsDir = ""
    if dirExists(claudeProjects):
      for kind, path in walkDir(claudeProjects):
        if kind == pcDir:
          projectsDir = path
          break

    runInstall(projectsDir, claudeConfigDir, tag, tagColor)
    return

  let limits = loadPlanConfig(claudeConfigDir)

  let input = stdin.readAll()

  # Debug the std input JSON
  # writeFile("/tmp/statusline-input.json", input)

  let data = parseJson(input)

  let transcriptPath = data["transcript_path"].getStr()
  let cwd = data["workspace"]["current_dir"].getStr()
  let projectDir = data["workspace"]["project_dir"].getStr()
  let model = data["model"]["display_name"].getStr()

  let displayProjectDir =
    if projectDir.startsWith(home):
      "~" & projectDir[home.len..^1]
    else:
      projectDir

  let branch = getGitBranch(projectDir)

  let (_, _, conversationTokens, cacheReadTokens, _, _) = getFirstTimestampAndContextTokens(transcriptPath)

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

  # Get real usage from Claude's /config or fall back to estimates
  let (sessionPercent, sessionResetTime, weeklyPercent, weeklyResetTime) = getRealUsageData()

  var messages5hr = 0
  var percent5hr = sessionPercent
  var time5hr = sessionResetTime
  var hoursWeekly = 0.0
  var percentWeekly = weeklyPercent
  var timeWeekly = weeklyResetTime
  var usingEstimates = false

  # Fall back to estimates if real data isn't available
  if sessionPercent == 0 and weeklyPercent == 0:
    usingEstimates = true
    let projectsDir = claudeConfigDir / "projects"
    let (m5hr, p5hr, t5hr, hWeekly, pWeekly, tWeekly) =
      estimateUsageFromTranscripts(projectsDir, limits)
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

  if usingEstimates:
    stdout.write(" | ")
    stdout.write("\x1b[90m~estimates\x1b[0m")

when isMainModule:
  main()
