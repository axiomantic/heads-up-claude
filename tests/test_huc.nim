import unittest
import std/[os, osproc, strutils]

suite "Statusline Entry":
  test "huc binary can be built":
    let result = execShellCmd("nim c --hints:off -o:/tmp/test_huc src/huc.nim")
    check result == 0
    check fileExists("/tmp/test_huc")
    removeFile("/tmp/test_huc")

  test "huc shows help":
    discard execShellCmd("nim c --hints:off -o:/tmp/test_huc src/huc.nim")
    let (output, exitCode) = execCmdEx("/tmp/test_huc --help")
    check exitCode == 0
    check "huc" in output
    check "statusline" in output.toLowerAscii()
    removeFile("/tmp/test_huc")
