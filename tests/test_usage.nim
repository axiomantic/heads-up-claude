import unittest
import std/[times, os, options, json]
import ../src/usage
import ../src/types

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

suite "API Credentials":
  test "loadApiCredentials returns none for missing config":
    let creds = loadApiCredentials("/nonexistent/path")
    check creds.isNone

  test "loadApiCredentials returns none for config without credentials":
    let tempDir = getTempDir() / "test-no-creds"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"plan": "pro", "five_hour_messages": 45}""")

    let creds = loadApiCredentials(tempDir)
    check creds.isNone

  test "loadApiCredentials returns none for empty credentials":
    let tempDir = getTempDir() / "test-empty-creds"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"session_key": "", "org_id": ""}""")

    let creds = loadApiCredentials(tempDir)
    check creds.isNone

  test "loadApiCredentials returns credentials when present":
    let tempDir = getTempDir() / "test-valid-creds"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"session_key": "sk-ant-test123", "org_id": "org-uuid-here"}""")

    let creds = loadApiCredentials(tempDir)
    check creds.isSome
    check creds.get().sessionKey == "sk-ant-test123"
    check creds.get().orgId == "org-uuid-here"

suite "Plan Config":
  test "loadPlanConfig returns defaults for missing config":
    let limits = loadPlanConfig("/nonexistent/path")
    check limits.name == "Free"
    check limits.fiveHourMessages == 10

  test "loadPlanConfig parses pro plan":
    let tempDir = getTempDir() / "test-pro-plan"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"plan": "pro", "five_hour_messages": 45, "weekly_hours_min": 40}""")

    let limits = loadPlanConfig(tempDir)
    check limits.name == "Pro"
    check limits.fiveHourMessages == 45
    check limits.weeklyHoursMin == 40
    check limits.weeklyHoursMax == 80

  test "loadPlanConfig parses max5 plan":
    let tempDir = getTempDir() / "test-max5-plan"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"plan": "max5", "five_hour_messages": 225, "weekly_hours_min": 140}""")

    let limits = loadPlanConfig(tempDir)
    check limits.name == "Max 5"
    check limits.fiveHourMessages == 225
    check limits.weeklyHoursMin == 140
    check limits.weeklyHoursMax == 280

  test "loadPlanConfig parses max20 plan":
    let tempDir = getTempDir() / "test-max20-plan"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"plan": "max20", "five_hour_messages": 900, "weekly_hours_min": 240}""")

    let limits = loadPlanConfig(tempDir)
    check limits.name == "Max 20"
    check limits.fiveHourMessages == 900
    check limits.weeklyHoursMin == 240
    check limits.weeklyHoursMax == 480

suite "Usage Status":
  test "getRealUsageData returns NoCredentials when no API config":
    let tempDir = getTempDir() / "test-no-api"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let configPath = tempDir / "heads_up_config.json"
    writeFile(configPath, """{"plan": "pro"}""")

    let (sessionPct, sessionReset, weeklyPct, weeklyReset, status) = getRealUsageData(tempDir)
    check status == UsageNoCredentials

  test "UsageStatus enum has expected values":
    check ord(UsageOk) == 0
    check ord(UsageStale) == 1
    check ord(UsageAuthExpired) == 2
    check ord(UsageNoCredentials) == 3
    check ord(UsageEstimates) == 4

suite "Estimate Calculations":
  test "estimateUsageFromTranscripts handles missing directory":
    let limits = PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80)
    let (msgs, pct5hr, time5hr, hoursWk, pctWk, timeWk) = estimateUsageFromTranscripts("/nonexistent", limits)

    check msgs == 0
    check pct5hr == 0
    check hoursWk == 0.0
    check pctWk == 0

  test "estimateUsageFromTranscripts handles empty directory":
    let tempDir = getTempDir() / "test-empty-projects"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let limits = PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80)
    let (msgs, pct5hr, time5hr, hoursWk, pctWk, timeWk) = estimateUsageFromTranscripts(tempDir, limits)

    check msgs == 0
    check pct5hr == 0
