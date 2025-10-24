import unittest
import ../src/types

suite "Types Module":
  test "PLAN_INFO contains correct plan data":
    check PLAN_INFO.len == 3
    check PLAN_INFO[ord(Pro)].name == "Pro"
    check PLAN_INFO[ord(Max5)].name == "Max 5"
    check PLAN_INFO[ord(Max20)].name == "Max 20"

  test "Pro plan has correct limits":
    let pro = PLAN_INFO[ord(Pro)]
    check pro.fiveHourMessages == 45
    check pro.weeklyHoursMin == 40
    check pro.weeklyHoursMax == 80

  test "Max 5 plan has correct limits":
    let max5 = PLAN_INFO[ord(Max5)]
    check max5.fiveHourMessages == 225
    check max5.weeklyHoursMin == 140
    check max5.weeklyHoursMax == 280

  test "Max 20 plan has correct limits":
    let max20 = PLAN_INFO[ord(Max20)]
    check max20.fiveHourMessages == 900
    check max20.weeklyHoursMin == 240
    check max20.weeklyHoursMax == 480

  test "Default weekly reset values":
    check DEFAULT_WEEKLY_RESET_DAY == 2
    check DEFAULT_WEEKLY_RESET_HOUR_UTC == 23

  test "Global variables initialize correctly":
    check gWeeklyResetDay == DEFAULT_WEEKLY_RESET_DAY
    check gWeeklyResetHourUTC == DEFAULT_WEEKLY_RESET_HOUR_UTC
    check gUseEmoji == true
