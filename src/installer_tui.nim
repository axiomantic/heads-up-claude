import std/[strutils, times, options, os]
import illwill
import types

proc parseResetTime(input: string): Option[(int, int)] =
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

proc formatResetTime(weekday: int, hourUTC: int): string =
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

type
  InstallState = enum
    StatePlanSelection
    StateResetTime
    StateEmojiPreference
    StateComplete

  InstallerTUI = object
    state: InstallState
    selectedPlanIndex: int
    detectedPlan: PlanType
    resetTimeInput: string
    parsedResetTime: Option[(int, int)]
    emojiIndex: int
    finalResetTime: DateTime
    shouldReconfigure: bool
    shouldUpdateBinary: bool

  InstallerResult* = object
    completed*: bool
    selectedPlan*: PlanType
    resetTime*: DateTime
    useEmoji*: bool

proc newInstallerTUI(detectedPlan: PlanType): InstallerTUI =
  result.state = StatePlanSelection
  result.selectedPlanIndex = ord(detectedPlan)
  result.detectedPlan = detectedPlan
  result.resetTimeInput = ""
  result.parsedResetTime = none((int, int))
  result.emojiIndex = 0

proc drawBox(tb: var TerminalBuffer, x1, y1, x2, y2: int, title: string = "") =
  tb.drawRect(x1, y1, x2, y2)
  if title.len > 0:
    let titleText = " " & title & " "
    tb.write(x1 + 2, y1, titleText)

proc drawPlanSelection(tb: var TerminalBuffer, tui: var InstallerTUI) =
  let width = terminalWidth()
  let height = terminalHeight()

  tb.setForegroundColor(fgWhite, true)
  tb.write(2, 2, "Heads Up Claude Installer")
  tb.setForegroundColor(fgWhite, false)

  drawBox(tb, 2, 4, 72, 12, "Select Your Claude Plan")

  let plans = [
    "Pro",
    "Max 5",
    "Max 20"
  ]

  var y = 6
  for i, name in plans:
    if i == tui.selectedPlanIndex:
      tb.setBackgroundColor(bgBlue)
      tb.setForegroundColor(fgWhite, true)
      tb.write(4, y, "▶ ")
    else:
      tb.setBackgroundColor(bgNone)
      tb.setForegroundColor(fgWhite, false)
      tb.write(4, y, "  ")

    tb.write(6, y, name)

    if i == ord(tui.detectedPlan):
      tb.write(17, y, "(auto-detected)")

    tb.setBackgroundColor(bgNone)

    y += 2

  tb.setForegroundColor(fgYellow, false)
  tb.write(2, height - 3, "↑/↓: Navigate  Enter: Select  q: Quit")
  tb.setForegroundColor(fgWhite, false)

proc drawResetTime(tb: var TerminalBuffer, tui: var InstallerTUI) =
  let width = terminalWidth()
  let height = terminalHeight()

  tb.setForegroundColor(fgWhite, true)
  tb.write(2, 2, "Heads Up Claude Installer")
  tb.setForegroundColor(fgWhite, false)

  drawBox(tb, 2, 4, 90, 15, "Weekly Reset Time")

  tb.write(4, 6, "Visit https://claude.ai/settings/usage to see your reset time.")
  tb.write(4, 7, "Enter it in a format like:")

  tb.setForegroundColor(fgCyan, false)
  tb.write(6, 8, "\"Wed 5:59 PM\"  or  \"Wednesday 17:59\"")
  tb.setForegroundColor(fgWhite, false)

  tb.write(4, 10, "Reset time: ")
  tb.setBackgroundColor(bgBlue)
  tb.setForegroundColor(fgWhite, true)
  let inputDisplay = if tui.resetTimeInput.len > 0: tui.resetTimeInput else: "Wed 6:00 PM Central (default)"
  tb.write(16, 10, inputDisplay & "  ")
  tb.setBackgroundColor(bgNone)
  tb.setForegroundColor(fgWhite, false)

  if tui.parsedResetTime.isSome:
    let (weekday, hourUTC) = tui.parsedResetTime.get()
    tb.setForegroundColor(fgGreen, true)
    tb.write(4, 12, "✓ Parsed as: " & formatResetTime(weekday, hourUTC))
    tb.setForegroundColor(fgWhite, false)
  elif tui.resetTimeInput.len > 0:
    tb.setForegroundColor(fgRed, true)
    tb.write(4, 12, "✗ Could not parse. Try: \"Wed 5:59 PM\" or \"Wednesday 17:59\"")
    tb.setForegroundColor(fgWhite, false)

  tb.setForegroundColor(fgYellow, false)
  tb.write(2, height - 3, "Enter: Confirm  Backspace: Delete  Esc: Back  q: Quit")
  tb.setForegroundColor(fgWhite, false)

proc drawEmojiPreference(tb: var TerminalBuffer, tui: var InstallerTUI) =
  let width = terminalWidth()
  let height = terminalHeight()

  tb.setForegroundColor(fgWhite, true)
  tb.write(2, 2, "Heads Up Claude Installer")
  tb.setForegroundColor(fgWhite, false)

  drawBox(tb, 2, 4, 95, 16, "Display Style")

  let options = [
    ("With emoji", "💬 104.6K 65% 🟢 104.0K cached | 🕐 178/900 19% (3h22m) | 📅 19.3h/240h 8% (5d23h)"),
    ("No emoji (text)", "CTX 104.6K 65% CACHE 104.0K | 5HR 178/900 19% (3h22m) | WK 19.3h/240h 8% (5d23h)")
  ]

  var y = 6
  for i, (name, example) in options:
    if i == tui.emojiIndex:
      tb.setBackgroundColor(bgBlue)
      tb.setForegroundColor(fgWhite, true)
      tb.write(4, y, "▶ ")
    else:
      tb.setBackgroundColor(bgNone)
      tb.setForegroundColor(fgWhite, false)
      tb.write(4, y, "  ")

    tb.write(6, y, name)
    tb.setBackgroundColor(bgNone)

    tb.setForegroundColor(fgCyan, false)
    tb.write(6, y + 1, example)
    tb.setForegroundColor(fgWhite, false)

    y += 3

  tb.setForegroundColor(fgYellow, false)
  tb.write(2, height - 3, "↑/↓: Navigate  Enter: Confirm  Esc: Back  q: Quit")
  tb.setForegroundColor(fgWhite, false)

proc drawComplete(tb: var TerminalBuffer, tui: var InstallerTUI, selectedPlan: PlanType, useEmoji: bool) =
  let width = terminalWidth()
  let height = terminalHeight()

  tb.setForegroundColor(fgWhite, true)
  tb.write(2, 2, "Heads Up Claude Installer")
  tb.setForegroundColor(fgWhite, false)

  drawBox(tb, 2, 4, 80, 14, "Installation Complete")

  tb.setForegroundColor(fgGreen, true)
  tb.write(4, 6, "✓ Installation successful!")
  tb.setForegroundColor(fgWhite, false)

  tb.write(4, 8, "Plan configured: " & PLAN_INFO[ord(selectedPlan)].name)
  tb.write(4, 9, "Reset time: " & formatResetTime(tui.finalResetTime.weekday.ord, tui.finalResetTime.hour))
  tb.write(4, 10, "Display style: " & (if useEmoji: "emoji" else: "text"))

  tb.setForegroundColor(fgCyan, false)
  tb.write(4, 12, "Restart Claude Code to see the new statusline!")
  tb.setForegroundColor(fgWhite, false)

  tb.setForegroundColor(fgYellow, false)
  tb.write(2, height - 3, "Press any key to exit")
  tb.setForegroundColor(fgWhite, false)

proc handlePlanSelectionInput(tui: var InstallerTUI, key: Key): bool =
  case key
  of Key.Up:
    tui.selectedPlanIndex = max(0, tui.selectedPlanIndex - 1)
  of Key.Down:
    tui.selectedPlanIndex = min(2, tui.selectedPlanIndex + 1)
  of Key.Enter:
    tui.state = StateResetTime
  of Key.Q:
    return true
  else:
    discard
  return false

proc handleResetTimeInput(tui: var InstallerTUI, key: Key): bool =
  case key
  of Key.Escape:
    tui.state = StatePlanSelection
  of Key.Backspace:
    if tui.resetTimeInput.len > 0:
      tui.resetTimeInput.setLen(tui.resetTimeInput.len - 1)
      tui.parsedResetTime = parseResetTime(tui.resetTimeInput)
  of Key.Enter:
    if tui.resetTimeInput.len == 0:
      tui.parsedResetTime = some((2, 23))

    if tui.parsedResetTime.isSome:
      let (weekday, hourUTC) = tui.parsedResetTime.get()
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

      tui.finalResetTime = resetTime
      tui.state = StateEmojiPreference
  of Key.Q:
    return true
  else:
    let ch = char(key)
    if ch >= ' ' and ch <= '~':
      tui.resetTimeInput.add(ch)
      tui.parsedResetTime = parseResetTime(tui.resetTimeInput)
  return false

proc handleEmojiPreferenceInput(tui: var InstallerTUI, key: Key): bool =
  case key
  of Key.Up:
    tui.emojiIndex = max(0, tui.emojiIndex - 1)
  of Key.Down:
    tui.emojiIndex = min(1, tui.emojiIndex + 1)
  of Key.Escape:
    tui.state = StateResetTime
  of Key.Enter:
    tui.state = StateComplete
  of Key.Q:
    return true
  else:
    discard
  return false

proc runInstallerTUI*(detectedPlan: PlanType): InstallerResult =
  var tui = newInstallerTUI(detectedPlan)

  illwillInit(fullscreen=true)
  defer: illwillDeinit()

  setControlCHook(proc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)
  )

  hideCursor()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  var quit = false

  while not quit:
    tb.clear()

    case tui.state
    of StatePlanSelection:
      tb.drawPlanSelection(tui)
    of StateResetTime:
      tb.drawResetTime(tui)
    of StateEmojiPreference:
      tb.drawEmojiPreference(tui)
    of StateComplete:
      let selectedPlan = case tui.selectedPlanIndex
        of 0: Pro
        of 1: Max5
        of 2: Max20
        else: detectedPlan
      let useEmoji = tui.emojiIndex == 0
      tb.drawComplete(tui, selectedPlan, useEmoji)

    tb.display()

    let key = getKey()

    case tui.state
    of StatePlanSelection:
      quit = tui.handlePlanSelectionInput(key)
    of StateResetTime:
      quit = tui.handleResetTimeInput(key)
    of StateEmojiPreference:
      quit = tui.handleEmojiPreferenceInput(key)
    of StateComplete:
      if key != Key.None:
        let selectedPlan = case tui.selectedPlanIndex
          of 0: Pro
          of 1: Max5
          of 2: Max20
          else: detectedPlan
        let useEmoji = tui.emojiIndex == 0

        result.completed = true
        result.selectedPlan = selectedPlan
        result.resetTime = tui.finalResetTime
        result.useEmoji = useEmoji
        return

    sleep(20)

  result.completed = false
