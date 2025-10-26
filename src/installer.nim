import std/[os, strutils, times, json, options, strformat]
import types, usage, installer_tui

proc parseResetTime*(input: string): Option[(int, int)] =
  let normalized = input.toLowerAscii().strip()

  var weekday = -1
  if "mon" in normalized: weekday = 0
  elif "tue" in normalized: weekday = 1
  elif "wed" in normalized: weekday = 2
  elif "thu" in normalized: weekday = 3
  elif "fri" in normalized: weekday = 4
  elif "sat" in normalized: weekday = 5
  elif "sun" in normalized: weekday = 6

  if weekday == -1:
    return none((int, int))

  var hour = -1
  var minute = 0
  var isPM = false

  if " pm" in normalized or "pm" in normalized:
    isPM = true

  var timeStr = ""
  var foundColon = false
  for i, c in normalized:
    if c in {'0'..'9', ':'}:
      timeStr.add(c)
      if c == ':':
        foundColon = true
    elif foundColon and timeStr.len > 0:
      break

  if foundColon and timeStr.len > 0:
    let parts = timeStr.split(':')
    if parts.len == 2:
      try:
        hour = parseInt(parts[0])
        minute = parseInt(parts[1])

        if isPM and hour < 12:
          hour += 12
        elif not isPM and hour == 12:
          hour = 0
      except:
        return none((int, int))

  if hour < 0 or hour > 23 or minute < 0 or minute > 59:
    return none((int, int))

  var hourUTC = hour + 6
  if hourUTC >= 24:
    hourUTC -= 24

  return some((weekday, hourUTC))

proc formatResetTime*(weekday: int, hourUTC: int): string =
  let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
  let dayName = days[weekday]

  var hourCentral = hourUTC - 6
  if hourCentral < 0:
    hourCentral += 24

  let hour12 = if hourCentral == 0: 12
               elif hourCentral > 12: hourCentral - 12
               else: hourCentral
  let ampm = if hourCentral < 12: "AM" else: "PM"

  return dayName & " " & $hour12 & ":00 " & ampm & " Central (" & $hourUTC & ":00 UTC)"

proc installBinary*(): bool =
  echo ""
  echo "Installing binary..."

  let currentExe = getAppFilename()

  when defined(windows):
    let binDir = getEnv("LOCALAPPDATA") / "Programs"
    let binPath = binDir / "heads-up-claude.exe"
    createDir(binDir)
    copyFile(currentExe, binPath)
  else:
    let binDir = getEnv("HOME") / ".local" / "bin"
    let binPath = binDir / "heads-up-claude"
    createDir(binDir)
    copyFile(currentExe, binPath)
    setFilePermissions(binPath, {fpUserExec, fpUserWrite, fpUserRead, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})

  echo "✓ Installed to ", binPath
  return true

proc installStatusLine*(selectedPlan: PlanType, resetTime: DateTime, useEmoji: bool, claudeConfigDir: string, tag: string = "", tagColor: string = "") =
  if not dirExists(claudeConfigDir):
    createDir(claudeConfigDir)

  let settingsPath = claudeConfigDir / "settings.json"

  when defined(windows):
    let binPath = getEnv("LOCALAPPDATA") / "Programs" / "heads-up-claude.exe"
  else:
    let binPath = getEnv("HOME") / ".local" / "bin" / "heads-up-claude"

  var settings: JsonNode
  if fileExists(settingsPath):
    try:
      settings = parseJson(readFile(settingsPath))
    except:
      settings = newJObject()
  else:
    settings = newJObject()

  let planArg = case selectedPlan
    of Pro: "pro"
    of Max5: "max5"
    of Max20: "max20"

  let resetISO = format(resetTime, "yyyy-MM-dd'T'HH:mm:sszzz")

  var command = binPath & " --plan=" & planArg & " --reset-time=\"" & resetISO & "\""

  let home = getEnv("HOME")
  let defaultConfigDir = home / ".claude"
  if claudeConfigDir != defaultConfigDir:
    command.add(" --claude-config-dir=\"" & claudeConfigDir & "\"")

  if tag.len > 0:
    command.add(" --tag=\"" & tag & "\"")

  if tagColor.len > 0:
    command.add(" --tag-color=\"" & tagColor & "\"")

  if not useEmoji:
    command.add(" --no-emoji")

  settings["statusLine"] = %* {
    "type": "command",
    "command": command
  }

  writeFile(settingsPath, settings.pretty())

  echo ""
  echo "✓ Installed to ", settingsPath
  echo "✓ Plan configured: ", PLAN_INFO[ord(selectedPlan)].name
  echo "✓ Reset time: ", formatResetTime(resetTime.weekday.ord, resetTime.hour)
  echo "✓ Display style: ", if useEmoji: "emoji" else: "text"
  echo ""
  echo "Restart Claude Code to see the new statusline!"
  echo ""
  echo "To change your plan or reset time later, run:"
  when defined(windows):
    echo "  heads-up-claude --install"
  else:
    echo "  ~/.local/bin/heads-up-claude --install"

proc showHelp*() =
  echo "Heads Up Claude"
  echo "==============="
  echo ""
  echo "A custom statusline for Claude Code that shows token usage, rate limits, and weekly usage."
  echo ""
  echo "Usage:"
  echo "  heads-up-claude [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --install                    Run interactive installer to configure settings.json"
  echo "  --plan=PLAN                  Set plan tier: pro, max5, or max20"
  echo "  --reset-time=DATETIME        Set weekly reset time (ISO format with timezone)"
  echo "                               Example: --reset-time=\"2025-10-30T18:00:00-05:00\""
  echo "  --tag=TEXT                   Prepend [ TEXT ] | at the beginning of the status line"
  echo "  --tag-color=COLOR            Color for the tag. Available colors:"
  echo "                               black, red, green, yellow, blue, magenta, cyan, white,"
  echo "                               gray, bright-red, bright-green, bright-yellow,"
  echo "                               bright-blue, bright-magenta, bright-cyan, bright-white"
  echo "  --claude-config-dir=PATH     Claude config directory"
  echo "                               (default: $CLAUDE_CONFIG_DIR or ~/.claude)"
  echo "  --no-emoji                   Use descriptive text instead of emoji"
  echo "  --help                       Show this help message"
  echo ""
  echo "Environment Variables:"
  echo "  CLAUDE_CONFIG_DIR            Default Claude config directory if --claude-config-dir"
  echo "                               is not specified (default: ~/.claude)"
  echo ""
  echo "Examples:"
  echo "  # Run installer"
  when defined(windows):
    echo "  heads-up-claude --install"
  else:
    echo "  ~/.local/bin/heads-up-claude --install"
  echo ""
  echo "  # Use in settings.json with custom options"
  when defined(windows):
    echo "  heads-up-claude --plan=max20 --reset-time=\"2025-10-30T23:00:00+00:00\" --tag=\"DEV\" --tag-color=green --no-emoji"
  else:
    echo "  ~/.local/bin/heads-up-claude --plan=max20 --reset-time=\"2025-10-30T23:00:00+00:00\" --tag=\"DEV\" --tag-color=green --no-emoji"
  echo ""
  echo "For more information, see https://github.com/axiomantic/heads-up-claude"

proc runInstall*(projectsDir: string, claudeConfigDir: string, tag: string = "", tagColor: string = "") =
  let settingsPath = claudeConfigDir / "settings.json"

  if fileExists(settingsPath):
    try:
      let settings = parseJson(readFile(settingsPath))
      if settings.hasKey("statusLine") and settings["statusLine"].hasKey("command"):
        let currentCommand = settings["statusLine"]["command"].getStr()
        if "heads-up-claude" in currentCommand:
          echo "Existing configuration found:"
          echo "  ", currentCommand
          echo ""
          stdout.write("Reconfigure? This will update your settings. [y/N]: ")
          stdout.flushFile()

          let response = stdin.readLine().strip().toLowerAscii()
          if response.len == 0 or response[0] != 'y':
            echo "Reconfiguration skipped - keeping existing settings."
            echo ""
            stdout.write("Update binary? [Y/n]: ")
            stdout.flushFile()

            let installResponse = stdin.readLine().strip().toLowerAscii()
            if installResponse.len > 0 and installResponse[0] != 'y':
              echo "Installation cancelled."
              quit(1)

            if not installBinary():
              quit(1)

            echo ""
            echo "Your existing Claude Code statusline configuration is unchanged."
            return
          echo ""
    except:
      discard

  let detected = detectPlan(projectsDir)
  let tuiResult = runInstallerTUI(detected)

  if tuiResult.completed:
    if not installBinary():
      quit(1)
    installStatusLine(tuiResult.selectedPlan, tuiResult.resetTime, tuiResult.useEmoji, claudeConfigDir, tag, tagColor)
