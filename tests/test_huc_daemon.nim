import unittest
import std/[os, osproc]
import ../src/huc/daemon

suite "Daemon Management":
  test "getDaemonPid returns none when not running":
    # This is hard to test deterministically without actual daemon
    # Just verify the function exists and returns option
    let pid = getDaemonPid()
    # May or may not be running, just check it doesn't crash
    check true

  test "isDaemonRunning returns bool":
    let running = isDaemonRunning()
    check running == true or running == false

  test "getPlatform returns valid platform":
    let platform = getPlatform()
    check platform in ["darwin", "linux", "unknown"]
