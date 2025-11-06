import unittest
import std/[times, os, options]
import ../src/usage

suite "Usage Module":
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
