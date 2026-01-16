import unittest
import std/[os, json, times, options]
import ../src/huc/reader
import ../src/shared/types

suite "Status Reader":
  test "readStatus returns none for missing file":
    let result = readStatus("/nonexistent/status.json")
    check result.isNone

  test "readStatus parses valid status.json":
    let tempDir = getTempDir() / "test-read-status"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let statusJson = %*{
      "version": 1,
      "updated_at": "2026-01-16T12:00:00Z",
      "config_dir": tempDir,
      "api": {"configured": true, "error": nil},
      "estimates": {
        "calculated_at": "2026-01-16T12:00:00Z",
        "messages_5hr": 10,
        "session_percent": 22,
        "session_reset": "4h",
        "hours_weekly": 5.5,
        "weekly_percent": 5,
        "weekly_reset": "6d"
      },
      "context": {"transcript_path": nil, "tokens": 50000, "cache_read_tokens": 40000, "percent_used": 31},
      "plan": {"name": "Pro", "five_hour_messages": 45, "weekly_hours_min": 40},
      "errors": {"api": nil, "transcripts": nil, "daemon": nil}
    }
    writeFile(tempDir / "status.json", $statusJson)

    let result = readStatus(tempDir / "status.json")
    check result.isSome
    check result.get().version == 1
    check result.get().api.configured == true
    check result.get().estimates.messages5hr == 10

  test "getStatusAge calculates correct age":
    let tempDir = getTempDir() / "test-status-age"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let pastTime = now().utc() - initDuration(minutes = 5)
    let statusJson = %*{
      "version": 1,
      "updated_at": pastTime.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "config_dir": tempDir,
      "api": {"configured": false, "error": nil},
      "estimates": {
        "calculated_at": pastTime.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
        "messages_5hr": 0,
        "session_percent": 0,
        "session_reset": "",
        "hours_weekly": 0.0,
        "weekly_percent": 0,
        "weekly_reset": ""
      },
      "context": {"transcript_path": nil, "tokens": 0, "cache_read_tokens": 0, "percent_used": 0},
      "plan": {"name": "Free", "five_hour_messages": 10, "weekly_hours_min": 0},
      "errors": {"api": nil, "transcripts": nil, "daemon": nil}
    }
    writeFile(tempDir / "status.json", $statusJson)

    let result = readStatus(tempDir / "status.json")
    check result.isSome

    let age = getStatusAge(result.get())
    check age.inMinutes >= 4
    check age.inMinutes <= 6

  test "isStatusStale returns true for old status":
    let status = Status(
      updatedAt: now().utc() - initDuration(minutes = 15)
    )
    check isStatusStale(status) == true

  test "isStatusStale returns false for fresh status":
    let status = Status(
      updatedAt: now().utc() - initDuration(minutes = 3)
    )
    check isStatusStale(status) == false
