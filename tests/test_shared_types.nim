import unittest
import std/[os, json]
import ../src/shared/types

suite "Shared Types":
  test "PLAN_INFO contains all plan types":
    check PLAN_INFO.len == 4
    check PLAN_INFO[0].name == "Free"
    check PLAN_INFO[1].name == "Pro"
    check PLAN_INFO[2].name == "Max 5"
    check PLAN_INFO[3].name == "Max 20"

  test "Pro plan has correct limits":
    let pro = PLAN_INFO[1]
    check pro.fiveHourMessages == 45
    check pro.weeklyHoursMin == 40
    check pro.weeklyHoursMax == 80

  test "loadPlanName returns correct display name":
    let tmpDir = getTempDir() / "test_huc_plan"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    writeFile(tmpDir / "heads_up_config.json", $(%*{"plan": "max20"}))
    check loadPlanName(tmpDir) == "Max 20"

    writeFile(tmpDir / "heads_up_config.json", $(%*{"plan": "pro"}))
    check loadPlanName(tmpDir) == "Pro"

    writeFile(tmpDir / "heads_up_config.json", $(%*{"plan": "free"}))
    check loadPlanName(tmpDir) == "Free"

    writeFile(tmpDir / "heads_up_config.json", $(%*{"plan": "max5"}))
    check loadPlanName(tmpDir) == "Max 5"

  test "loadPlanName returns empty for missing config":
    let tmpDir = getTempDir() / "test_huc_plan_missing"
    check loadPlanName(tmpDir) == ""

  test "loadPlanName returns empty for unknown plan":
    let tmpDir = getTempDir() / "test_huc_plan_unknown"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    writeFile(tmpDir / "heads_up_config.json", $(%*{"plan": "enterprise"}))
    check loadPlanName(tmpDir) == ""
