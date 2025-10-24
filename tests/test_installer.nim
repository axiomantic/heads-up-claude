import unittest
import std/[options, strutils]
import ../src/installer

suite "Installer Module":
  test "parseResetTime parses Wed 5:59 PM":
    let result = parseResetTime("Wed 5:59 PM")

    check result.isSome
    let (weekday, hourUTC) = result.get()
    check weekday == 2
    check hourUTC == 23

  test "parseResetTime parses Resets Wed 5:59 PM":
    let result = parseResetTime("Resets Wed 5:59 PM")

    check result.isSome
    let (weekday, hourUTC) = result.get()
    check weekday == 2

  test "parseResetTime parses Wednesday 17:59":
    let result = parseResetTime("Wednesday 17:59")

    check result.isSome
    let (weekday, hourUTC) = result.get()
    check weekday == 2

  test "parseResetTime parses Mon 12:00 AM":
    let result = parseResetTime("Mon 12:00 AM")

    check result.isSome
    let (weekday, hourUTC) = result.get()
    check weekday == 0
    check hourUTC == 6

  test "parseResetTime parses Thu 12:00 PM":
    let result = parseResetTime("Thu 12:00 PM")

    check result.isSome
    let (weekday, hourUTC) = result.get()
    check weekday == 3
    check hourUTC == 18

  test "parseResetTime handles all weekdays":
    check parseResetTime("Mon 10:00 AM").isSome
    check parseResetTime("Tue 10:00 AM").isSome
    check parseResetTime("Wed 10:00 AM").isSome
    check parseResetTime("Thu 10:00 AM").isSome
    check parseResetTime("Fri 10:00 AM").isSome
    check parseResetTime("Sat 10:00 AM").isSome
    check parseResetTime("Sun 10:00 AM").isSome

  test "parseResetTime returns none for invalid input":
    check parseResetTime("").isNone
    check parseResetTime("invalid").isNone
    check parseResetTime("123").isNone

  test "parseResetTime returns none for invalid day":
    check parseResetTime("Xyz 10:00 AM").isNone

  test "parseResetTime returns none for invalid time":
    check parseResetTime("Wed 25:00").isNone
    check parseResetTime("Wed 10:60").isNone

  test "formatResetTime formats correctly":
    let formatted = formatResetTime(2, 23)
    check "Wednesday" in formatted
    check "Central" in formatted
    check "UTC" in formatted

  test "formatResetTime handles all weekdays":
    check "Monday" in formatResetTime(0, 12)
    check "Tuesday" in formatResetTime(1, 12)
    check "Wednesday" in formatResetTime(2, 12)
    check "Thursday" in formatResetTime(3, 12)
    check "Friday" in formatResetTime(4, 12)
    check "Saturday" in formatResetTime(5, 12)
    check "Sunday" in formatResetTime(6, 12)
