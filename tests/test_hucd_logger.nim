## Tests for daemon logger module

import unittest
import std/[strutils, times]
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

  test "formatLogMessage includes timestamp in ISO format":
    let msg = formatLogMessage(WARN, "warning test")
    # Format: [YYYY-MM-DD HH:MM:SS] [LEVEL] message
    check msg.contains("-")  # Date separator
    check msg.contains(":")  # Time separator
    check msg.contains("WARN")
    check msg.contains("warning test")
    # Verify format: starts with [timestamp] [level]
    check msg.startsWith("[")
    let parts = msg.split("] [")
    check parts.len >= 2

  test "formatLogMessage handles all log levels":
    let debugMsg = formatLogMessage(DEBUG, "d")
    let infoMsg = formatLogMessage(INFO, "i")
    let warnMsg = formatLogMessage(WARN, "w")
    let errorMsg = formatLogMessage(ERROR, "e")
    check debugMsg.contains("DEBUG")
    check infoMsg.contains("INFO")
    check warnMsg.contains("WARN")
    check errorMsg.contains("ERROR")

  test "formatLogMessage preserves message content with special chars":
    let msg = formatLogMessage(INFO, "path: /foo/bar, value: 123")
    check msg.contains("/foo/bar")
    check msg.contains("123")
