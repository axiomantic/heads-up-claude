## Shared types for huc statusline

import std/[json, os, times]

# ─────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────

type
  LogLevel* = enum
    DEBUG, INFO, WARN, ERROR

var debugMode* = false

proc log*(level: LogLevel, msg: string) =
  if level == DEBUG and not debugMode:
    return
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let levelStr = case level
    of DEBUG: "DEBUG"
    of INFO: "INFO"
    of WARN: "WARN"
    of ERROR: "ERROR"
  stderr.writeLine("[" & timestamp & "] [" & levelStr & "] " & msg)
  stderr.flushFile()

# ─────────────────────────────────────────────────────────────────
# Config loading
# ─────────────────────────────────────────────────────────────────

proc loadProjectsDir*(claudeConfigDir: string): string =
  ## Read heads_up_config.json and return the configured projects directory.
  ## Returns empty string if not configured.
  let configPath = claudeConfigDir / "heads_up_config.json"
  if not fileExists(configPath):
    return ""
  try:
    let j = parseFile(configPath)
    return j.getOrDefault("projects_dir").getStr("")
  except:
    return ""
