import unittest
import std/strutils
import ../src/huc/render

suite "Statusline Renderer":
  test "renderTag with color":
    let output = renderTag("DEV", "\x1b[32m")
    check "\x1b[32m" in output
    check "DEV" in output
    check " | " in output

  test "renderTag without color":
    let output = renderTag("WORK", "")
    check output == "WORK | "

  test "renderTag with empty tag":
    check renderTag("", "green") == ""

  test "colorNameToAnsi maps standard colors":
    check colorNameToAnsi("red") == "\x1b[31m"
    check colorNameToAnsi("blue") == "\x1b[34m"
    check colorNameToAnsi("cyan") == "\x1b[36m"

  test "colorNameToAnsi maps bright colors":
    check colorNameToAnsi("bright-red") == "\x1b[91m"
    check colorNameToAnsi("bright-cyan") == "\x1b[96m"

  test "colorNameToAnsi returns empty for unknown":
    check colorNameToAnsi("rainbow") == ""

  test "colorNameToAnsi is case insensitive":
    check colorNameToAnsi("RED") == "\x1b[31m"
    check colorNameToAnsi("Blue") == "\x1b[34m"
