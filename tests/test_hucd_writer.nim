## Tests for atomic writer module

import unittest
import std/[os, json, times, tables, osproc, strutils]
import ../src/hucd/writer
import ../src/shared/types

suite "Atomic Writer":
  test "atomicWriteJson writes valid JSON":
    let tempDir = getTempDir() / "test-atomic-write"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let path = tempDir / "test.json"
    let data = %*{"key": "value", "number": 42}

    atomicWriteJson(path, data)

    check fileExists(path)
    let content = parseFile(path)
    check content["key"].getStr() == "value"
    check content["number"].getInt() == 42

  test "atomicWriteJson does not leave tmp files on success":
    let tempDir = getTempDir() / "test-atomic-no-tmp"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let path = tempDir / "test.json"
    atomicWriteJson(path, %*{"test": true})

    # Check no .tmp files remain
    for kind, p in walkDir(tempDir):
      check not p.endsWith(".tmp")

  test "writeStatus creates valid status.json":
    let tempDir = getTempDir() / "test-write-status"
    let cacheDir = tempDir / "heads-up-cache"
    createDir(cacheDir)
    defer: removeDir(tempDir)

    let status = Status(
      version: 1,
      updatedAt: now().utc(),
      configDir: tempDir,
      api: ApiStatus(configured: false),
      estimates: EstimateStatus(
        calculatedAt: now().utc(),
        messages5hr: 5,
        sessionPercent: 11,
        sessionReset: "4h",
        hoursWeekly: 2.0,
        weeklyPercent: 5,
        weeklyReset: "6d"
      ),
      context: ContextStatus(tokens: 10000, cacheReadTokens: 8000, percentUsed: 6),
      plan: PlanStatus(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40),
      errors: ErrorStatus()
    )

    writeStatus(cacheDir, status)

    let statusPath = cacheDir / "status.json"
    check fileExists(statusPath)

    let content = parseFile(statusPath)
    check content["version"].getInt() == 1
    check content["estimates"]["messages_5hr"].getInt() == 5

  test "writeTranscriptCache creates valid transcripts.json":
    let tempDir = getTempDir() / "test-write-cache"
    let cacheDir = tempDir / "heads-up-cache"
    createDir(cacheDir)
    defer: removeDir(tempDir)

    var cache = TranscriptCache(
      version: 1,
      lastPruned: now().utc(),
      transcripts: initTable[string, TranscriptEntry]()
    )
    cache.transcripts["/test/path.jsonl"] = TranscriptEntry(
      size: 1000,
      offset: 500,
      mtime: getTime(),
      lastChecked: now().utc(),
      tokensAfterSummary: 5000,
      messagesAfterSummary: 10,
      lastCacheReadTokens: 4000
    )

    writeTranscriptCache(cacheDir, cache)

    let cachePath = cacheDir / "transcripts.json"
    check fileExists(cachePath)

    let content = parseFile(cachePath)
    check content["version"].getInt() == 1
    check content["transcripts"]["/test/path.jsonl"]["size"].getInt() == 1000
