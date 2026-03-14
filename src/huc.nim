## huc - Heads Up Claude Statusline
## Lightweight binary that renders a minimal statusline

import std/[os, json, parseopt, strutils, paths, terminal, osproc]
import shared/types
import huc/render
import installer

proc showHelp() =
  echo "huc - Heads Up Claude Statusline"
  echo ""
  echo "Usage:"
  echo "  huc [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --tag=TEXT               Prepend TEXT | to statusline"
  echo "  --tag-color=COLOR        Color for tag (blue, red, green, etc.)"
  echo "  --claude-config-dir=PATH Claude config directory (default: ~/.claude)"
  echo "  --no-emoji               Use text instead of emoji"
  echo "  --debug                  Enable debug output"
  echo "  --help                   Show this help"
  echo ""
  echo "Setup:"
  echo "  --install                Run interactive setup (updates settings.json)"
  echo ""
  echo "Examples:"
  echo "  huc --tag=\"DEV\" --tag-color=green"

proc main() =
  var tag = ""
  var tagColor = ""
  var claudeConfigDir = ""
  var showHelpMode = false
  var installMode = false

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
      of "install": installMode = true
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

  # Install mode - run interactive installer
  if installMode:
    let projectsDir = claudeConfigDir / "projects"
    runInstall(projectsDir, claudeConfigDir, tag, tagColor)
    return

  # Main statusline mode - read stdin for context
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

  # Project dir and branch from stdin
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
              var branchDisplay = "\x1b[35m" & branch & "\x1b[0m"

              # Detect worktree: if --git-dir and --git-common-dir differ, we're in a worktree
              try:
                let (gitDirOut, gdExit) = execCmdEx("git --no-optional-locks -C " & quoteShell(projectDir) & " rev-parse --git-dir 2>/dev/null")
                let (commonDirOut, cdExit) = execCmdEx("git --no-optional-locks -C " & quoteShell(projectDir) & " rev-parse --git-common-dir 2>/dev/null")
                if gdExit == 0 and cdExit == 0:
                  let gitDir = gitDirOut.strip()
                  let commonDir = commonDirOut.strip()
                  # Normalize paths for comparison
                  let normalGitDir = expandFilename(if gitDir.isAbsolute: gitDir else: projectDir / gitDir)
                  let normalCommonDir = expandFilename(if commonDir.isAbsolute: commonDir else: projectDir / commonDir)
                  if normalGitDir != normalCommonDir:
                    # We're in a worktree; show worktree name (basename of project dir)
                    let worktreeName = projectDir.splitPath().tail
                    branchDisplay = "\x1b[35m" & branch & "\x1b[0m \x1b[90m(wt: " & worktreeName & ")\x1b[0m"
              except:
                discard

              output.add(" | " & branchDisplay)
        except:
          discard

  # Plan name from config
  let planName = loadPlanName(claudeConfigDir)
  if planName.len > 0:
    output.add(" | \x1b[35m" & planName & "\x1b[0m")

  # Model from stdin
  if inputJson != nil and inputJson.hasKey("model"):
    let modelNode = inputJson["model"]
    var modelDisplay = modelNode.getOrDefault("display_name").getStr("")
    if modelDisplay.len > 0:
      if modelNode.hasKey("thinking") and modelNode["thinking"].getBool():
        modelDisplay = "\xf0\x9f\xa7\xa0 " & modelDisplay
      output.add(" | \x1b[36m" & modelDisplay & "\x1b[0m")

  stdout.write(output)

when isMainModule:
  main()
