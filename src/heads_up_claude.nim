import std/[json, os, strutils, parseopt, times]
import types, cache, usage, display, installer

proc main() =
  var planArg = ""
  var installMode = false
  var showHelpMode = false

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

  if installMode:
    let home = getEnv("HOME")
    let claudeProjects = home / ".claude" / "projects"

    var projectsDir = ""
    if dirExists(claudeProjects):
      for kind, path in walkDir(claudeProjects):
        if kind == pcDir:
          projectsDir = path
          break

    if projectsDir.len > 0:
      runInstall(projectsDir)
    else:
      echo "Error: Could not find Claude projects directory"
      echo "Expected at: ", claudeProjects
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
  writeFile("/tmp/statusline-input.json", input)
  let data = parseJson(input)

  let transcriptPath = data["transcript_path"].getStr()
  let cwd = data["workspace"]["current_dir"].getStr()
  let projectDir = data["workspace"]["project_dir"].getStr()
  let model = data["model"]["display_name"].getStr()

  let home = getEnv("HOME")
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
    timeWeekly
  )

when isMainModule:
  main()
