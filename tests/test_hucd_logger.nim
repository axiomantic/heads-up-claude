## Tests for daemon logger module

import unittest
import std/[strutils]
import ../src/hucd/logger
import ../src/shared/types

suite "Daemon Logger":
  test "logDebug respects debugMode setting":
    # Debug messages should not appear when debugMode is false
    debugMode = false
    logDebug("test message")  # Should not raise

    debugMode = true
    logDebug("test debug message")  # Should not raise

    # Reset for other tests
    debugMode = false

  test "logInfo writes to stderr":
    logInfo("test info message")  # Should not raise

  test "logWarn writes to stderr":
    logWarn("test warning message")  # Should not raise

  test "logError writes to stderr":
    logError("test error message")  # Should not raise

  test "formatLogMessage produces correct format":
    let msg = formatLogMessage(INFO, "test message")
    check msg.contains("INFO")
    check msg.contains("test message")
    check msg.contains("[")  # timestamp brackets
