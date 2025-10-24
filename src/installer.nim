import std/[os, strutils, times, json, options, strformat]
import types, usage

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

proc promptResetTime*(): DateTime =
  echo ""
  echo "Weekly Reset Time"
  echo "================="
  echo "Visit https://claude.ai/settings/usage to see your reset time."
  echo "Copy and paste the reset time (e.g., \"Resets Wed 5:59 PM\"),"
  echo "or enter it in a format like \"Wed 5:59 PM\" or \"Wednesday 17:59\"."
  echo ""

  while true:
    stdout.write("Reset time (default: Wed 6:00 PM Central): ")
    stdout.flushFile()

    let input = stdin.readLine().strip()

    var weekday, hourUTC: int

    if input.len == 0:
      weekday = 2
      hourUTC = 23
    else:
      let parsed = parseResetTime(input)
      if parsed.isNone:
        echo "Could not parse reset time. Please try again."
        echo "Examples: \"Wed 5:59 PM\", \"Wednesday 17:59\", \"Resets Thu 6:00 PM\""
        echo ""
        continue

      (weekday, hourUTC) = parsed.get()
      echo ""
      echo "Parsed as: ", formatResetTime(weekday, hourUTC)
      stdout.write("Is this correct? [Y/n]: ")
      stdout.flushFile()

      let confirm = stdin.readLine().strip().toLowerAscii()
      if confirm.len > 0 and confirm[0] != 'y':
        echo "Let's try again."
        echo ""
        continue

    let now = now().utc()
    var resetTime = now
    resetTime.hour = hourUTC
    resetTime.minute = 0
    resetTime.second = 0
    resetTime.nanosecond = 0

    let currentWeekday = now.weekday.ord
    let daysUntilReset = (weekday - currentWeekday + 7) mod 7

    if daysUntilReset == 0:
      if now.hour >= hourUTC:
        resetTime = resetTime + initDuration(days = 7)
    else:
      resetTime = resetTime + initDuration(days = daysUntilReset)

    return resetTime

proc promptPlanSelection*(detectedPlan: PlanType): PlanType =
  echo "Claude Code Plan"
  echo "================"
  echo ""
  echo "Select your Claude plan:"
  echo "  1. Pro (45 msgs/5hr, 40-80 hrs/week)"
  echo "  2. Max 5 (225 msgs/5hr, 140-280 hrs/week)"
  echo "  3. Max 20 (900 msgs/5hr, 240-480 hrs/week)"
  echo ""
  echo "Auto-detected: ", PLAN_INFO[ord(detectedPlan)].name, " (option ", ord(detectedPlan) + 1, ")"
  stdout.write("Enter choice [1-3, default=", ord(detectedPlan) + 1, "]: ")
  stdout.flushFile()

  let input = stdin.readLine().strip()
  if input.len == 0:
    return detectedPlan

  try:
    let choice = parseInt(input)
    case choice
    of 1: return Pro
    of 2: return Max5
    of 3: return Max20
    else:
      echo "Invalid choice, using detected plan"
      return detectedPlan
  except:
    echo "Invalid input, using detected plan"
    return detectedPlan

proc installStatusLine*(selectedPlan: PlanType, resetTime: DateTime, useEmoji: bool) =
  let settingsPath = getEnv("HOME") / ".claude" / "settings.json"
  let statuslinePath = getEnv("HOME") / ".claude" / "heads-up-claude"

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

  var command = statuslinePath & " --plan=" & planArg & " --reset-time=\"" & resetISO & "\""
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
  echo "  ~/.claude/heads-up-claude --install"

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
  echo "  --install               Run interactive installer to configure settings.json"
  echo "  --plan=PLAN             Set plan tier: pro, max5, or max20"
  echo "  --reset-time=DATETIME   Set weekly reset time (ISO format with timezone)"
  echo "                          Example: --reset-time=\"2025-10-30T18:00:00-05:00\""
  echo "  --no-emoji              Use descriptive text instead of emoji"
  echo "  --help                  Show this help message"
  echo ""
  echo "Examples:"
  echo "  # Run installer"
  echo "  ~/.claude/heads-up-claude --install"
  echo ""
  echo "  # Use in settings.json with custom options"
  echo "  ~/.claude/heads-up-claude --plan=max20 --reset-time=\"2025-10-30T23:00:00+00:00\" --no-emoji"
  echo ""
  echo "For more information, see https://github.com/axiomantic/heads-up-claude"

proc runInstall*(projectsDir: string) =
  echo "Heads Up Claude Installer"
  echo "========================="
  echo ""

  let detected = detectPlan(projectsDir)

  let selected = promptPlanSelection(detected)

  let resetTime = promptResetTime()

  echo ""
  echo "Display Style"
  echo "============="
  echo ""
  echo "Choose display style:"
  echo ""
  echo "1. With emoji (default):"
  echo "   💬 104.6K 65% 🟢 104.0K cached | 🕐 178/900 19% (3h22m) | 📅 19.3h/240h 8% (5d23h)"
  echo ""
  echo "2. No emoji (descriptive text):"
  echo "   CTX 104.6K 65% CACHE 104.0K | 5HR 178/900 19% (3h22m) | WK 19.3h/240h 8% (5d23h)"
  echo ""
  stdout.write("Use emoji? [Y/n]: ")
  stdout.flushFile()

  let emojiInput = stdin.readLine().strip().toLowerAscii()
  let useEmoji = emojiInput.len == 0 or emojiInput[0] == 'y'

  installStatusLine(selected, resetTime, useEmoji)
