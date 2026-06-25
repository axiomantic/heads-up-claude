import unittest
import std/[os, json]
import ../src/shared/types

suite "Shared Types":
  test "loadProjectsDir returns configured directory":
    let tmpDir = getTempDir() / "test_huc_projects"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    writeFile(tmpDir / "heads_up_config.json", $(%*{"projects_dir": "/Users/test/Development"}))
    check loadProjectsDir(tmpDir) == "/Users/test/Development"

  test "loadProjectsDir returns empty for missing config":
    let tmpDir = getTempDir() / "test_huc_projects_missing"
    check loadProjectsDir(tmpDir) == ""

  test "loadProjectsDir returns empty when key not present":
    let tmpDir = getTempDir() / "test_huc_projects_nokey"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    writeFile(tmpDir / "heads_up_config.json", $(%*{}))
    check loadProjectsDir(tmpDir) == ""
