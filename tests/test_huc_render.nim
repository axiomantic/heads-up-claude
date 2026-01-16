import unittest
import std/[times, options, strutils]
import ../src/huc/render
import ../src/shared/types

suite "Statusline Renderer":
  test "renderWaiting produces expected output":
    let output = renderWaiting("waiting for data")
    check "waiting for data" in output

  test "renderUsageSection formats session data":
    let output = renderUsageSection(45, "Pro", 22, "3h45m", 5.5, 40, 5, "5d12h", true)
    check "22" in output
    check "45" in output  # messages/limit

  test "renderContextSection formats tokens":
    let output = renderContextSection(85000, 72000, 47)
    check "85" in output  # 85K
    check "47" in output  # percent

  test "renderWarning formats warning message":
    let output = renderWarning("credentials expired")
    check "credentials expired" in output
    check "\x1b[33m" in output  # yellow

  test "formatTokenCount handles large numbers":
    check formatTokenCount(500) == "500"
    check formatTokenCount(1500) == "1.5K"
    check formatTokenCount(85000) == "85.0K"
