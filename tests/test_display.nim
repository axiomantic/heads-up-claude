import unittest
import std/[os, osproc]
import ../src/display

suite "Display Module":
  test "formatTokenCount formats numbers under 1000":
    check formatTokenCount(0) == "0"
    check formatTokenCount(100) == "100"
    check formatTokenCount(999) == "999"

  test "formatTokenCount formats thousands with K":
    check formatTokenCount(1000) == "1.0K"
    check formatTokenCount(1500) == "1.5K"
    check formatTokenCount(10000) == "10.0K"
    check formatTokenCount(104600) == "104.6K"

  test "getGitBranch returns empty string for non-git directory":
    let tempDir = getTempDir() / "test-no-git"
    createDir(tempDir)
    defer: removeDir(tempDir)

    let branch = getGitBranch(tempDir)
    check branch == ""

  test "getGitBranch returns branch name for git directory":
    let tempDir = getTempDir() / "test-git-repo"
    createDir(tempDir)
    defer: removeDir(tempDir)

    discard execCmd("cd " & quoteShell(tempDir) & " && git init && git config user.email 'test@test.com' && git config user.name 'Test' && touch test.txt && git add test.txt && git commit -m 'init' && git checkout -b test-branch 2>/dev/null")

    let branch = getGitBranch(tempDir)
    check branch == "test-branch"

  test "getGitBranch handles errors gracefully":
    let branch = getGitBranch("/nonexistent/directory")
    check branch == ""

suite "Color Name Conversion":
  test "colorNameToAnsi converts basic colors":
    check colorNameToAnsi("black") == "\x1b[30m"
    check colorNameToAnsi("red") == "\x1b[31m"
    check colorNameToAnsi("green") == "\x1b[32m"
    check colorNameToAnsi("yellow") == "\x1b[33m"
    check colorNameToAnsi("blue") == "\x1b[34m"
    check colorNameToAnsi("magenta") == "\x1b[35m"
    check colorNameToAnsi("cyan") == "\x1b[36m"
    check colorNameToAnsi("white") == "\x1b[37m"

  test "colorNameToAnsi converts bright colors":
    check colorNameToAnsi("gray") == "\x1b[90m"
    check colorNameToAnsi("bright-red") == "\x1b[91m"
    check colorNameToAnsi("bright-green") == "\x1b[92m"
    check colorNameToAnsi("bright-yellow") == "\x1b[93m"
    check colorNameToAnsi("bright-blue") == "\x1b[94m"
    check colorNameToAnsi("bright-magenta") == "\x1b[95m"
    check colorNameToAnsi("bright-cyan") == "\x1b[96m"
    check colorNameToAnsi("bright-white") == "\x1b[97m"

  test "colorNameToAnsi handles aliases":
    check colorNameToAnsi("purple") == "\x1b[35m"
    check colorNameToAnsi("grey") == "\x1b[90m"
    check colorNameToAnsi("brightred") == "\x1b[91m"
    check colorNameToAnsi("bright-purple") == "\x1b[95m"

  test "colorNameToAnsi is case insensitive":
    check colorNameToAnsi("RED") == "\x1b[31m"
    check colorNameToAnsi("Green") == "\x1b[32m"
    check colorNameToAnsi("BRIGHT-BLUE") == "\x1b[94m"

  test "colorNameToAnsi handles whitespace":
    check colorNameToAnsi("  red  ") == "\x1b[31m"
    check colorNameToAnsi(" green ") == "\x1b[32m"

  test "colorNameToAnsi returns empty string for invalid color":
    check colorNameToAnsi("invalid") == ""
    check colorNameToAnsi("notacolor") == ""
    check colorNameToAnsi("") == ""
