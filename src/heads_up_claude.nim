import std/[json, os, strutils, parseopt, times, paths]
import types, cache, usage, display, installer

proc main() =
  var planArg = ""
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
      of "plan":
        planArg = p.val
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
      of "reset-time":
        var parsed = false
        try:
          let resetTime = parse(p.val, "yyyy-MM-dd'T'HH:mm:sszzz")
          let resetUTC = resetTime.utc()
          gWeeklyResetDay = resetUTC.weekday.ord
          gWeeklyResetHourUTC = resetUTC.hour
          parsed = true
        except CatchableError:
          discard

        if not parsed:
          try:
            let resetTimeLocal = parse(p.val, "yyyy-MM-dd'T'HH:mm:ss")
            let resetUTC = resetTimeLocal.utc()
            gWeeklyResetDay = resetUTC.weekday.ord
            gWeeklyResetHourUTC = resetUTC.hour
            parsed = true
          except CatchableError:
            discard

        if not parsed:
          echo "Error: Could not parse --reset-time value: ", p.val
          echo "Expected ISO format like: 2025-10-30T18:00:00-05:00 or 2025-10-30T18:00:00"
          quit(1)
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

  var currentPlan = Max20
  if planArg.len > 0:
    case planArg.toLowerAscii()
    of "pro":
      currentPlan = Pro
    of "max5", "max5x", "max-5":
      currentPlan = Max5
    of "max20", "max20x", "max-20":
      currentPlan = Max20
    else:
      discard

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

  let projectsDir = parentDir(transcriptPath)
  var cacheObj = loadCache()
  defer: saveCache(cacheObj)
  let (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly) = calculate5HourAndWeeklyUsage(projectsDir, cacheObj, currentPlan)

  let limits = PLAN_INFO[ord(currentPlan)]

  var tagColorForDisplay = tagColor
  if tagColor.len > 0:
    let converted = colorNameToAnsi(tagColor)
    if converted.len > 0:
      tagColorForDisplay = converted

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

when isMainModule:
  main()
