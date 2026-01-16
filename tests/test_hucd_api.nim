## Tests for API module

import unittest
import std/[os, json, options]
import ../src/hucd/api
import ../src/shared/types

suite "API Module":
  test "loadApiCredentials returns none for missing config":
    let creds = loadApiCredentials("/nonexistent/path")
    check creds.isNone

  test "loadApiCredentials returns none for empty credentials":
    let tempDir = getTempDir() / "test-empty-api-creds"
    createDir(tempDir)
    defer: removeDir(tempDir)

    writeFile(tempDir / "heads_up_config.json", """{"session_key": "", "org_id": ""}""")

    let creds = loadApiCredentials(tempDir)
    check creds.isNone

  test "loadApiCredentials returns credentials when valid":
    let tempDir = getTempDir() / "test-valid-api-creds"
    createDir(tempDir)
    defer: removeDir(tempDir)

    writeFile(tempDir / "heads_up_config.json", """{
      "session_key": "sk-ant-test-key",
      "org_id": "org-uuid-12345"
    }""")

    let creds = loadApiCredentials(tempDir)
    check creds.isSome
    check creds.get().sessionKey == "sk-ant-test-key"
    check creds.get().organizationId == "org-uuid-12345"

  test "hasCredentials checks for valid credentials":
    let tempDir = getTempDir() / "test-has-creds"
    createDir(tempDir)
    defer: removeDir(tempDir)

    check hasCredentials(tempDir) == false

    writeFile(tempDir / "heads_up_config.json", """{
      "session_key": "sk-ant-test",
      "org_id": "org-123"
    }""")

    check hasCredentials(tempDir) == true

  test "parseApiResponse extracts utilization data":
    let response = """{
      "five_hour": {"utilization": 45, "resets_at": "2099-01-16T17:00:00.000Z"},
      "seven_day": {"utilization": 12, "resets_at": "2099-01-21T00:00:00.000Z"}
    }"""

    let (sessionPct, sessionReset, weeklyPct, weeklyReset) = parseApiResponse(response)

    check sessionPct == 45
    check weeklyPct == 12
    # Resets should contain time strings since dates are in the future
    check sessionReset.len > 0
    check weeklyReset.len > 0
