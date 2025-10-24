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
