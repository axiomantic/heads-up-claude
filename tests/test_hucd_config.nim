## Tests for daemon config module

import unittest
import std/[os, json]
import ../src/hucd/config
import ../src/shared/types

suite "Daemon Config":
  test "loadConfig returns defaults when file missing":
    let config = loadConfig("/nonexistent/hucd.json")
    check config.version == 1
    check config.scanIntervalMinutes == 5
    check config.configDirs.len == 1
    check config.configDirs[0] == getHomeDir() / ".claude"

  test "loadConfig parses valid JSON":
    let tempDir = getTempDir() / "test-hucd-config"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "hucd.json"
    writeFile(configPath, """{
      "version": 1,
      "config_dirs": ["/home/test/.claude", "/home/test/.claude-work"],
      "scan_interval_minutes": 10,
      "api_interval_minutes": 3,
      "prune_interval_minutes": 60,
      "debug": true
    }""")

    let config = loadConfig(configPath)
    check config.configDirs.len == 2
    check config.configDirs[0] == "/home/test/.claude"
    check config.scanIntervalMinutes == 10
    check config.debug == true

  test "configFileChanged detects mtime changes":
    let tempDir = getTempDir() / "test-config-change"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "hucd.json"
    writeFile(configPath, """{"version": 1}""")

    var state = ConfigWatchState(configPath: configPath)
    initConfigWatch(state)

    # First check should return false (just initialized)
    check configFileChanged(state) == false

    # Modify file
    sleep(1100)  # Ensure mtime changes (filesystem resolution)
    writeFile(configPath, """{"version": 1, "debug": true}""")

    # Now should detect change
    check configFileChanged(state) == true

    # After acknowledging, should return false
    check configFileChanged(state) == false
