import std/[times, options]

type
  PlanType* = enum
    Pro, Max5, Max20

  PlanLimits* = object
    name*: string
    fiveHourMessages*: int
    weeklyHoursMin*: int
    weeklyHoursMax*: int

  FileCache* = object
    modTime*: Time
    contextTokens*: int
    cacheReadTokens*: int
    apiTokens*: int
    firstTimestamp*: Option[DateTime]
    lastTimestamp*: Option[DateTime]
    messageCount*: int

const
  PLAN_INFO* = [
    PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80),
    PlanLimits(name: "Max 5", fiveHourMessages: 225, weeklyHoursMin: 140, weeklyHoursMax: 280),
    PlanLimits(name: "Max 20", fiveHourMessages: 900, weeklyHoursMin: 240, weeklyHoursMax: 480)
  ]

  DEFAULT_WEEKLY_RESET_DAY* = 2
  DEFAULT_WEEKLY_RESET_HOUR_UTC* = 23

var
  gWeeklyResetDay* = DEFAULT_WEEKLY_RESET_DAY
  gWeeklyResetHourUTC* = DEFAULT_WEEKLY_RESET_HOUR_UTC
  gUseEmoji* = true
