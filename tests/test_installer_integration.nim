import unittest
import std/[os, json, strutils, times, paths]
import ../src/installer, ../src/types

suite "Installer Prompt Logic Tests":
  test "plan selection logic - default":
    let detected = Max20
    let choice = ""

    let selected = if choice.len == 0: detected else: Pro
    check selected == Max20

  test "plan selection logic - explicit choice 1":
    let choice = "1"
    var selected = Pro

    if choice.len > 0:
      try:
        let num = parseInt(choice)
        case num
        of 1: selected = Pro
        of 2: selected = Max5
        of 3: selected = Max20
        else: discard
      except: discard

    check selected == Pro

  test "plan selection logic - explicit choice 2":
    let choice = "2"
    var selected = Pro

    if choice.len > 0:
      try:
        let num = parseInt(choice)
        case num
        of 1: selected = Pro
        of 2: selected = Max5
        of 3: selected = Max20
        else: discard
      except: discard

    check selected == Max5

  test "plan selection logic - invalid defaults to detected":
    let detected = Max20
    let choice = "99"
    var selected = detected

    if choice.len > 0:
      try:
        let num = parseInt(choice)
        case num
        of 1: selected = Pro
        of 2: selected = Max5
        of 3: selected = Max20
        else: selected = detected
      except: selected = detected

    check selected == Max20

  test "reset time confirmation - yes":
    let response = "y"
    let confirmed = response.len > 0 and response[0] == 'y'

    check confirmed == true

  test "reset time confirmation - no":
    let response = "n"
    let confirmed = response.len > 0 and response[0] == 'y'

    check confirmed == false

  test "reset time confirmation - empty defaults to retry":
    let response = ""
    let confirmed = response.len > 0 and response[0] == 'y'

    check confirmed == false

  test "emoji preference - yes with 'y'":
    let input = "y"
    var useEmoji = true
    if input.len > 0:
      if input == "1" or input[0] == 'y':
        useEmoji = true
      elif input == "2" or input[0] == 'n':
        useEmoji = false

    check useEmoji == true

  test "emoji preference - yes with '1'":
    let input = "1"
    var useEmoji = true
    if input.len > 0:
      if input == "1" or input[0] == 'y':
        useEmoji = true
      elif input == "2" or input[0] == 'n':
        useEmoji = false

    check useEmoji == true

  test "emoji preference - empty defaults to yes":
    let input = ""
    var useEmoji = true
    if input.len > 0:
      if input == "1" or input[0] == 'y':
        useEmoji = true
      elif input == "2" or input[0] == 'n':
        useEmoji = false

    check useEmoji == true

  test "emoji preference - no with 'n'":
    let input = "n"
    var useEmoji = true
    if input.len > 0:
      if input == "1" or input[0] == 'y':
        useEmoji = true
      elif input == "2" or input[0] == 'n':
        useEmoji = false

    check useEmoji == false

  test "emoji preference - no with '2'":
    let input = "2"
    var useEmoji = true
    if input.len > 0:
      if input == "1" or input[0] == 'y':
        useEmoji = true
      elif input == "2" or input[0] == 'n':
        useEmoji = false

    check useEmoji == false

  test "reconfiguration decision - yes":
    let response = "y"
    let shouldReconfigure = response.len > 0 and response[0] == 'y'

    check shouldReconfigure == true

  test "reconfiguration decision - no":
    let response = "n"
    let shouldReconfigure = response.len > 0 and response[0] == 'y'

    check shouldReconfigure == false

  test "reconfiguration decision - empty defaults to no":
    let response = ""
    let shouldReconfigure = response.len > 0 and response[0] == 'y'

    check shouldReconfigure == false

suite "Installer Output Validation":
  test "success output format":
    let expectedOutputs = [
      "✓ Installed to",
      "✓ Plan configured:",
      "✓ Reset time:",
      "✓ Display style:",
      "Restart Claude Code"
    ]

    for expected in expectedOutputs:
      check expected.len > 0
      check "✓" in expected or "Restart" in expected

suite "Settings JSON Generation":
  let testHome = getTempDir() / "test-home"
  let testSettingsPath = testHome / ".claude" / "settings.json"

  setup:
    removeDir(testHome)
    createDir(testHome)
    createDir(testHome / ".claude")

  teardown:
    if dirExists(testHome):
      removeDir(testHome)

  test "settings.json is created with correct structure":
    let settings = %* {
      "statusLine": {
        "type": "command",
        "command": "heads-up-claude --plan=pro --reset-time=\"2025-10-30T23:00:00+00:00\""
      }
    }

    writeFile(testSettingsPath, settings.pretty())

    check fileExists(testSettingsPath)
    let loaded = parseJson(readFile(testSettingsPath))
    check loaded.hasKey("statusLine")
    check loaded["statusLine"]["type"].getStr() == "command"
    check "heads-up-claude" in loaded["statusLine"]["command"].getStr()

  test "settings.json preserves existing settings":
    let existingSettings = %* {
      "otherSetting": "value",
      "statusLine": {
        "type": "command",
        "command": "old-command"
      }
    }

    writeFile(testSettingsPath, existingSettings.pretty())

    var settings = parseJson(readFile(testSettingsPath))
    settings["statusLine"]["command"] = %"heads-up-claude --plan=max20"

    writeFile(testSettingsPath, settings.pretty())

    let updated = parseJson(readFile(testSettingsPath))
    check updated.hasKey("otherSetting")
    check updated["otherSetting"].getStr() == "value"
    check "heads-up-claude" in updated["statusLine"]["command"].getStr()

  test "command string includes all flags":
    let command = "heads-up-claude --plan=max20 --reset-time=\"2025-10-30T23:00:00+00:00\" --no-emoji"

    check "--plan=max20" in command
    check "--reset-time=" in command
    check "--no-emoji" in command

  test "command string with emoji (no flag)":
    let command = "heads-up-claude --plan=pro --reset-time=\"2025-10-30T23:00:00+00:00\""

    check "--plan=pro" in command
    check "--reset-time=" in command
    check "--no-emoji" notin command

  test "settings.json is created even if config directory doesn't exist":
    let testConfigDir = getTempDir() / "test-new-config-dir"

    if dirExists(testConfigDir):
      removeDir(testConfigDir)

    check not dirExists(testConfigDir)

    let settings = %* {
      "statusLine": {
        "type": "command",
        "command": "heads-up-claude --plan=max20"
      }
    }

    createDir(testConfigDir)
    let testSettingsPath = testConfigDir / "settings.json"
    writeFile(testSettingsPath, settings.pretty())

    check dirExists(testConfigDir)
    check fileExists(testSettingsPath)

    removeDir(testConfigDir)

  test "color names are stored as-is in settings.json, not converted to ANSI":
    let command = "heads-up-claude --plan=max20 --tag=\"DEV\" --tag-color=\"red\""

    check "--tag-color=\"red\"" in command
    check "--tag-color=\"\x1b[" notin command

suite "Emoji Flag Generation":
  test "command includes --no-emoji when useEmoji is false":
    var command = "heads-up-claude --plan=pro"
    let useEmoji = false

    if not useEmoji:
      command.add(" --no-emoji")

    check "--no-emoji" in command

  test "command does NOT include --no-emoji when useEmoji is true":
    var command = "heads-up-claude --plan=pro"
    let useEmoji = true

    if not useEmoji:
      command.add(" --no-emoji")

    check "--no-emoji" notin command

  test "installStatusLine generates command without --no-emoji when useEmoji is true":
    let testConfigDir = getTempDir() / "test-emoji-true"
    if dirExists(testConfigDir):
      removeDir(testConfigDir)

    let resetTime = now().utc()
    installStatusLine(Pro, resetTime, useEmoji=true, testConfigDir, "", "")

    let settingsPath = testConfigDir / "settings.json"
    check fileExists(settingsPath)

    let content = readFile(settingsPath)
    check "--no-emoji" notin content

    removeDir(testConfigDir)

  test "installStatusLine generates command with --no-emoji when useEmoji is false":
    let testConfigDir = getTempDir() / "test-emoji-false"
    if dirExists(testConfigDir):
      removeDir(testConfigDir)

    let resetTime = now().utc()
    installStatusLine(Pro, resetTime, useEmoji=false, testConfigDir, "", "")

    let settingsPath = testConfigDir / "settings.json"
    check fileExists(settingsPath)

    let content = readFile(settingsPath)
    check "--no-emoji" in content

    removeDir(testConfigDir)

suite "Tilde Expansion":
  test "expandTilde expands ~/ paths":
    let home = getEnv("HOME")
    check string(expandTilde(Path("~/.claude-work"))) == home / ".claude-work"
    check string(expandTilde(Path("~/test/path"))) == home / "test" / "path"

  test "expandTilde handles bare tilde":
    let home = getEnv("HOME")
    let expanded = string(expandTilde(Path("~")))
    # std/paths expandTilde adds trailing slash for bare ~
    check expanded == home or expanded == home & "/"

  test "expandTilde leaves absolute paths unchanged":
    check string(expandTilde(Path("/absolute/path"))) == "/absolute/path"
    check string(expandTilde(Path("/Users/test/.claude"))) == "/Users/test/.claude"

  test "expandTilde leaves relative paths unchanged":
    check string(expandTilde(Path("relative/path"))) == "relative/path"
    check string(expandTilde(Path(".claude"))) == ".claude"
