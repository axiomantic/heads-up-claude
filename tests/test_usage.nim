import unittest
import std/[times, os, options, tables]
import ../src/types
import ../src/usage

suite "Usage Module":
  test "roundToHour rounds down to nearest hour":
    let dt = parse("2025-01-01T12:34:56.789Z", "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
    let rounded = roundToHour(dt)

    check rounded.hour == 12
    check rounded.minute == 0
    check rounded.second == 0
    check rounded.nanosecond == 0

  test "calculateWindowEnd adds 5 hours to rounded hour":
    let dt = parse("2025-01-01T12:34:56.789Z", "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
    let windowEnd = calculateWindowEnd(dt)

    check windowEnd.hour == 17
    check windowEnd.minute == 0

  test "getNextWeeklyReset calculates correct reset time":
    gWeeklyResetDay = 2
    gWeeklyResetHourUTC = 23

    let nextReset = getNextWeeklyReset()

    check nextReset.weekday.ord == 2
    check nextReset.hour == 23
    check nextReset.minute == 0
    check nextReset.second == 0

  test "detectPlan returns Pro for no sessions":
    let tempDir = getTempDir() / "test-detect-plan-empty"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let plan = detectPlan(tempDir)
    check plan == Pro

  test "getFirstTimestampAndContextTokens handles missing file":
    let (first, last, ctx, cache, api, msgs) = getFirstTimestampAndContextTokens("/nonexistent/file.jsonl")

    check first.isNone
    check last.isNone
    check ctx == 0
    check cache == 0
    check api == 0
    check msgs == 0

  test "getFirstTimestampAndContextTokens parses valid JSONL":
    let tempDir = getTempDir() / "test-parse-jsonl"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let testFile = tempDir / "test.jsonl"
    let content = """{"type":"user","timestamp":"2025-01-01T10:00:00.000Z"}
{"type":"assistant","timestamp":"2025-01-01T10:01:00.000Z","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":500,"output_tokens":50}}}
"""
    writeFile(testFile, content)

    let (first, last, ctx, cache, api, msgs) = getFirstTimestampAndContextTokens(testFile)

    check first.isSome
    check last.isSome
    check ctx == 650
    check cache == 500
    check msgs == 2

  test "getFirstTimestampAndContextTokens resets on summary":
    let tempDir = getTempDir() / "test-summary"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let testFile = tempDir / "test.jsonl"
    let content = """{"type":"user","timestamp":"2025-01-01T10:00:00.000Z"}
{"type":"assistant","timestamp":"2025-01-01T10:01:00.000Z","message":{"usage":{"input_tokens":100,"output_tokens":50}}}
{"type":"summary","timestamp":"2025-01-01T10:02:00.000Z"}
{"type":"user","timestamp":"2025-01-01T10:03:00.000Z"}
{"type":"assistant","timestamp":"2025-01-01T10:04:00.000Z","message":{"usage":{"input_tokens":200,"cache_read_input_tokens":1000,"output_tokens":100}}}
"""
    writeFile(testFile, content)

    let (first, last, ctx, cache, api, msgs) = getFirstTimestampAndContextTokens(testFile)

    check first.isSome
    check last.isSome
    check ctx == 1300
    check cache == 1000
    check api == 300
    check msgs == 2
