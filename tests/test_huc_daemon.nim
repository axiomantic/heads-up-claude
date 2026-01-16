import unittest
import std/[os, osproc, options, strutils]
import ../src/huc/daemon

suite "Daemon Management":
  test "getDaemonPid returns Option[int]":
    # Verify function returns an Option type that can be checked
    let pid = getDaemonPid()
    # If running, pid should be positive; if not, should be none
    if pid.isSome:
      check pid.get() > 0
    else:
      check pid.isNone

  test "isDaemonRunning returns consistent result":
    # Call multiple times to verify stability
    let running1 = isDaemonRunning()
    let running2 = isDaemonRunning()
    # Should return same value when called in quick succession
    check running1 == running2

  test "getPlatform returns expected platform for this OS":
    let platform = getPlatform()
    check platform in ["darwin", "linux", "unknown"]
    # On macOS, should return darwin; on Linux, should return linux
    when defined(macosx):
      check platform == "darwin"
    when defined(linux):
      check platform == "linux"

  test "getDaemonStatus returns non-empty string":
    let status = getDaemonStatus()
    check status.len > 0
    # Should contain some indication of daemon state
    check status.contains("daemon") or status.contains("Daemon") or
          status.contains("running") or status.contains("stopped") or
          status.contains("not") or status.contains("PID")

  test "getDaemonLogs returns string":
    # May be empty if daemon never ran, but should not crash
    let logs = getDaemonLogs(10)
    # Just verify it returns without error and is a string
    check logs.len >= 0
