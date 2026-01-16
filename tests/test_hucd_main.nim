## Tests for daemon main module

import unittest
import std/[os, times, tables, monotimes, options]
import ../src/hucd/main
import ../src/shared/types

suite "Daemon Main":
  test "initDaemonState creates valid initial state":
    let tempDir = getTempDir() / "test-daemon-init"
    createDir(tempDir / "heads-up-cache")
    defer: removeDir(tempDir)

    let config = DaemonConfig(
      version: 1,
      configDirs: @[tempDir],
      scanIntervalMinutes: 5,
      apiIntervalMinutes: 5,
      pruneIntervalMinutes: 30,
      debug: false
    )

    let state = initDaemonState(config)

    check state.running == true
    check state.config.configDirs.len == 1
    check state.lastScan.len == 1
    check state.lastApi.len == 1

  test "shouldScan returns true after interval":
    var state = DaemonState()
    state.config = DaemonConfig(scanIntervalMinutes: 5)
    state.lastScan = initTable[string, MonoTime]()

    # First call should return true (no previous scan)
    check shouldScan(state, "/test") == true

    # Update last scan time
    state.lastScan["/test"] = getMonoTime()

    # Immediately after should return false
    check shouldScan(state, "/test") == false

  test "shouldFetchApi respects credentials":
    let tempDir = getTempDir() / "test-api-check"
    createDir(tempDir)
    defer: removeDir(tempDir)

    var state = DaemonState()
    state.config = DaemonConfig(apiIntervalMinutes: 5)
    state.lastApi = initTable[string, MonoTime]()

    # Without credentials should return false
    check shouldFetchApi(state, tempDir) == false

    # Add credentials
    writeFile(tempDir / "heads_up_config.json", """{
      "session_key": "sk-test",
      "org_id": "org-123"
    }""")

    # With credentials should return true
    check shouldFetchApi(state, tempDir) == true

  test "shouldPrune returns true after interval":
    var state = DaemonState()
    state.config = DaemonConfig(pruneIntervalMinutes: 30)
    state.lastPrune = MonoTime()  # Zero value = never pruned

    # Should return true (first time)
    check shouldPrune(state) == true

    # Update last prune time
    state.lastPrune = getMonoTime()

    # Immediately after should return false
    check shouldPrune(state) == false

  test "buildStatus creates valid status object":
    let tempDir = getTempDir() / "test-build-status"
    createDir(tempDir / "heads-up-cache")
    createDir(tempDir / "projects" / "-test")
    defer: removeDir(tempDir)

    var state = DaemonState()
    state.config = DaemonConfig(
      version: 1,
      configDirs: @[tempDir]
    )
    state.transcriptCache = TranscriptCache(
      version: 1,
      lastPruned: now().utc(),
      transcripts: initTable[string, TranscriptEntry]()
    )
    state.apiStatus = initTable[string, ApiStatus]()
    state.apiStatus[tempDir] = ApiStatus(configured: false)

    let status = buildStatus(state, tempDir)

    check status.version == 1
    check status.configDir == tempDir
