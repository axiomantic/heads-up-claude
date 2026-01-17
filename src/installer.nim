import std/[os, json, strutils, browsers]

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

proc installStatusLine*(useEmoji: bool, claudeConfigDir: string, tag: string = "", tagColor: string = "") =
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

  var command = binPath

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
  echo "✓ Display style: ", if useEmoji: "emoji" else: "text"
  echo ""
  echo "Configuration complete!"
  echo ""
  echo "Restart Claude Code to see the new statusline!"
  echo ""
  echo "Note: Usage estimates are based on local conversation activity."
  echo "      Reset times are estimated from conversation timestamps."

proc showHelp*() =
  echo "Heads Up Claude"
  echo "==============="
  echo ""
  echo "A custom statusline for Claude Code that shows token usage, rate limits, and weekly usage estimates."
  echo ""
  echo "Usage estimates are based on local conversation activity and reset times are calculated"
  echo "from conversation timestamps."
  echo ""
  echo "Usage:"
  echo "  heads-up-claude [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --install                    Run interactive installer to configure settings.json"
  echo "  --setup-api                  Setup API credentials for real-time usage data"
  echo "  --tag=TEXT                   Prepend TEXT | at the beginning of the status line"
  echo "  --tag-color=COLOR            Color for the tag. Available colors:"
  echo "                               black, red, green, yellow, blue, magenta, cyan, white,"
  echo "                               gray, bright-red, bright-green, bright-yellow,"
  echo "                               bright-blue, bright-magenta, bright-cyan, bright-white"
  echo "  --claude-config-dir=PATH     Claude config directory"
  echo "                               (default: $CLAUDE_CONFIG_DIR or ~/.claude)"
  echo "  --no-emoji                   Use descriptive text instead of emoji"
  echo "  --debug                      Enable debug logging to stderr"
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
    echo "  heads-up-claude --tag=\"DEV\" --tag-color=green --no-emoji"
  else:
    echo "  ~/.local/bin/heads-up-claude --tag=\"DEV\" --tag-color=green --no-emoji"
  echo ""
  echo "For more information, see https://github.com/axiomantic/heads-up-claude"

proc savePlanConfig(claudeConfigDir: string, plan: string, fiveHourLimit: int, weeklyHours: int) =
  let configPath = claudeConfigDir / "heads_up_config.json"
  let config = %* {
    "plan": plan,
    "five_hour_messages": fiveHourLimit,
    "weekly_hours_min": weeklyHours
  }
  writeFile(configPath, config.pretty())

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

  echo ""
  echo "Configure your Claude plan"
  echo "=========================="
  echo ""
  echo "Select your Claude plan:"
  echo "  1) Free"
  echo "  2) Pro ($20/month) - 45 messages per 5 hours"
  echo "  3) Max 5× ($100/month) - 225 messages per 5 hours"
  echo "  4) Max 20× ($200/month) - 900 messages per 5 hours"
  echo ""
  stdout.write("Enter choice [1-4] (default: 2): ")
  stdout.flushFile()

  let planResponse = stdin.readLine().strip()
  var planType: string
  var fiveHourLimit: int
  var weeklyHours: int

  case planResponse:
  of "1":
    planType = "free"
    fiveHourLimit = 10
    weeklyHours = 0
  of "3":
    planType = "max5"
    fiveHourLimit = 225
    weeklyHours = 140
  of "4":
    planType = "max20"
    fiveHourLimit = 900
    weeklyHours = 240
  else:
    planType = "pro"
    fiveHourLimit = 45
    weeklyHours = 40

  echo ""
  echo "Plan configured: ", planType
  if weeklyHours > 0:
    echo "  5-hour limit: ", fiveHourLimit, " messages"
    echo "  Weekly minimum: ", weeklyHours, " hours"
  else:
    echo "  5-hour limit: ", fiveHourLimit, " messages"

  savePlanConfig(claudeConfigDir, planType, fiveHourLimit, weeklyHours)

  echo ""
  echo "Configure tag prefix (optional)"
  echo "==============================="
  echo ""
  echo "You can add a custom tag prefix to your statusline (e.g., DEV, WORK, [personal])"
  echo ""
  stdout.write("Enter tag prefix (leave empty to skip): ")
  stdout.flushFile()

  var tagPrefix = stdin.readLine().strip()
  var tagColorChoice = ""

  if tagPrefix.len > 0:
    echo ""
    echo "Choose tag color:"
    echo "  1) green       2) yellow      3) blue        4) cyan"
    echo "  5) magenta     6) red         7) bright-green"
    echo "  8) bright-yellow  9) bright-blue  10) bright-cyan"
    echo ""
    stdout.write("Enter choice [1-10] (default: 4/cyan): ")
    stdout.flushFile()

    let colorResponse = stdin.readLine().strip()
    case colorResponse:
    of "1": tagColorChoice = "green"
    of "2": tagColorChoice = "yellow"
    of "3": tagColorChoice = "blue"
    of "5": tagColorChoice = "magenta"
    of "6": tagColorChoice = "red"
    of "7": tagColorChoice = "bright-green"
    of "8": tagColorChoice = "bright-yellow"
    of "9": tagColorChoice = "bright-blue"
    of "10": tagColorChoice = "bright-cyan"
    else: tagColorChoice = "cyan"

  echo ""
  echo "Configure display style"
  echo "======================="
  echo ""
  stdout.write("Use emoji icons? [Y/n]: ")
  stdout.flushFile()

  let emojiResponse = stdin.readLine().strip().toLowerAscii()
  let useEmoji = emojiResponse.len == 0 or emojiResponse[0] == 'y'

  if not installBinary():
    quit(1)

  installStatusLine(useEmoji, claudeConfigDir, tagPrefix, tagColorChoice)

const ORG_SNIPPET* = """
// Paste this in browser console to get org_id
fetch('/api/organizations').then(r=>r.json()).then(o=>console.log(o[0].uuid))
"""

proc runApiSetup*(claudeConfigDir: string) =
  ## Interactive setup for Claude.ai API credentials
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║            Setup Real-Time Usage Data (API)                  ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "This will configure your Claude.ai API credentials for"
  echo "accurate, real-time usage data in your statusline."
  echo ""
  echo "Step 1: Opening claude.ai in your browser..."
  echo ""

  # Open browser
  openDefaultBrowser("https://claude.ai")

  echo "Step 2: Open Developer Tools (F12 or Cmd+Option+I)"
  echo ""
  echo "Step 3: Go to Application tab > Cookies > claude.ai"
  echo "        Find 'sessionKey' and copy its value"
  echo "        (starts with 'sk-ant-sid01-...')"
  echo ""
  stdout.write("Step 4: Paste your sessionKey here: ")
  stdout.flushFile()

  let sessionKey = stdin.readLine().strip()
  if sessionKey.len == 0 or not sessionKey.startsWith("sk-ant-"):
    echo ""
    echo "✗ Invalid session key. Should start with 'sk-ant-sid01-...'"
    quit(1)

  echo ""
  echo "Step 5: Go to Console tab and paste this script:"
  echo ""
  echo "─────────────────────────────────────────────────────────────────"
  echo ORG_SNIPPET
  echo "─────────────────────────────────────────────────────────────────"
  echo ""
  stdout.write("Step 6: Paste the org_id here: ")
  stdout.flushFile()

  let orgId = stdin.readLine().strip()
  if orgId.len == 0 or orgId.len < 30:
    echo ""
    echo "✗ Invalid org_id. Should be a UUID like 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
    quit(1)

  # Load existing config or create new
  let configPath = claudeConfigDir / "heads_up_config.json"
  var config: JsonNode

  if fileExists(configPath):
    try:
      config = parseFile(configPath)
    except:
      config = newJObject()
  else:
    config = newJObject()
    # Set defaults if new config
    config["plan"] = %"pro"
    config["five_hour_messages"] = %45
    config["weekly_hours_min"] = %40

  # Update with API credentials
  config["session_key"] = %sessionKey
  config["org_id"] = %orgId

  # Ensure config directory exists
  createDir(claudeConfigDir)

  # Save atomically
  let tmpPath = configPath & ".tmp"
  writeFile(tmpPath, config.pretty())
  moveFile(tmpPath, configPath)

  echo ""
  echo "✓ API credentials saved to ", configPath
  echo ""
  echo "Your statusline will now show real-time usage data from Claude!"
  echo ""
  echo "Note: Session keys expire periodically. If you see 'credentials expired'"
  echo "      in your statusline, run this command again to refresh."
