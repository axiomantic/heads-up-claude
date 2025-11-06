
type
  PlanType* = enum
    Pro, Max5, Max20

  PlanLimits* = object
    name*: string
    fiveHourMessages*: int
    weeklyHoursMin*: int
    weeklyHoursMax*: int

const
  PLAN_INFO* = [
    PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80),
    PlanLimits(name: "Max 5", fiveHourMessages: 225, weeklyHoursMin: 140, weeklyHoursMax: 280),
    PlanLimits(name: "Max 20", fiveHourMessages: 900, weeklyHoursMin: 240, weeklyHoursMax: 480)
  ]

var
  gUseEmoji* = true
