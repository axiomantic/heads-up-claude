## Tests for transcript watcher module

import unittest
import std/[os, json, times, tables]
import ../src/hucd/watcher
import ../src/shared/types

suite "Transcript Watcher":
  test "processTranscript handles new content":
    let tempDir = getTempDir() / "test-incremental"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let transcript = tempDir / "test.jsonl"
    writeFile(transcript, """{"type":"user","timestamp":"2026-01-16T10:00:00.000Z"}
{"type":"assistant","timestamp":"2026-01-16T10:01:00.000Z","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":500,"output_tokens":50}}}
""")

    var entry = TranscriptEntry(
      size: 0,
      offset: 0,
      mtime: getTime(),
      lastChecked: now().utc()
    )

    processTranscript(transcript, entry)

    check entry.messagesAfterSummary == 2
    check entry.lastCacheReadTokens == 500
    check entry.tokensAfterSummary == 150  # input + output

  test "processTranscript resets on summary":
    let tempDir = getTempDir() / "test-summary-reset"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let transcript = tempDir / "test.jsonl"
    writeFile(transcript, """{"type":"user","timestamp":"2026-01-16T10:00:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":50}}}
{"type":"summary","timestamp":"2026-01-16T10:02:00.000Z"}
{"type":"user","timestamp":"2026-01-16T10:03:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":200,"cache_read_input_tokens":1000,"output_tokens":100}}}
""")

    var entry = TranscriptEntry()
    processTranscript(transcript, entry)

    # Should only count messages after summary
    check entry.messagesAfterSummary == 2
    check entry.lastCacheReadTokens == 1000
    check entry.tokensAfterSummary == 300  # 200 + 100

  test "processTranscript handles partial lines":
    let tempDir = getTempDir() / "test-partial"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let transcript = tempDir / "test.jsonl"
    # Write content without trailing newline (simulating mid-write)
    writeFile(transcript, """{"type":"user","timestamp":"2026-01-16T10:00:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":100}}}
{"type":"user","timestamp":"2026-01-16T10:01:00.000Z""")

    var entry = TranscriptEntry()
    processTranscript(transcript, entry)

    # Should have buffered the incomplete line
    check entry.incompleteLineBuffer.len > 0
    check entry.messagesAfterSummary == 2

  test "scanTranscripts finds jsonl files":
    let tempDir = getTempDir() / "test-scan"
    let projectsDir = tempDir / "projects"
    let projectDir = projectsDir / "-test-project"
    createDir(projectDir)
    defer: removeDir(tempDir)

    writeFile(projectDir / "abc123.jsonl", """{"type":"user"}
""")
    writeFile(projectDir / "def456.jsonl", """{"type":"user"}
""")

    var cache = TranscriptCache(
      version: 1,
      lastPruned: now().utc(),
      transcripts: initTable[string, TranscriptEntry]()
    )

    scanTranscripts(projectsDir, cache)

    check cache.transcripts.len == 2
