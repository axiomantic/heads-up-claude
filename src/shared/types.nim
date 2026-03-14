## Shared types for huc statusline

import std/[json, os, times]

# ─────────────────────────────────────────────────────────────────
# Plan limits (static lookup)
# ─────────────────────────────────────────────────────────────────

type
  PlanLimits* = object
    name*: string
    fiveHourMessages*: int
    weeklyHoursMin*: int
    weeklyHoursMax*: int

const
  PLAN_INFO* = [
    PlanLimits(name: "Free", fiveHourMessages: 10, weeklyHoursMin: 0, weeklyHoursMax: 0),
    PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80),
    PlanLimits(name: "Max 5", fiveHourMessages: 225, weeklyHoursMin: 140, weeklyHoursMax: 280),
    PlanLimits(name: "Max 20", fiveHourMessages: 900, weeklyHoursMin: 240, weeklyHoursMax: 480)
  ]

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
# Plan name loading from config
# ─────────────────────────────────────────────────────────────────

proc loadPlanName*(claudeConfigDir: string): string =
  ## Read heads_up_config.json and return the display name for the configured plan.
  ## Returns empty string if config is missing or plan is not recognized.
  let configPath = claudeConfigDir / "heads_up_config.json"
  if not fileExists(configPath):
    return ""
  try:
    let j = parseFile(configPath)
    let planKey = j.getOrDefault("plan").getStr("")
    case planKey
    of "free": return "Free"
    of "pro": return "Pro"
    of "max5": return "Max 5"
    of "max20": return "Max 20"
    else: return ""
  except:
    return ""
