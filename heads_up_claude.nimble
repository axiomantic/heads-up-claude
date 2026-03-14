# Package

version       = "0.4.0"
author        = "Axiomantic"
description   = "A minimal statusline for Claude Code showing project, branch, plan, and model"
license       = "MIT"
srcDir        = "src"
bin           = @["huc"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task install, "Install the program to ~/.local/bin":
  exec "nim c -d:release --hints:off --warnings:off -o:bin/huc src/huc.nim"
  when defined(windows):
    exec "copy bin\\huc.exe \"%LOCALAPPDATA%\\Programs\\huc.exe\""
  else:
    exec "mkdir -p ~/.local/bin"
    exec "cp bin/huc ~/.local/bin/huc"
    exec "chmod +x ~/.local/bin/huc"
    exec "ln -sf ~/.local/bin/huc ~/.local/bin/heads-up-claude"
  echo "Installed to ~/.local/bin/"

task build, "Build release binary":
  exec "nim c -d:release --hints:off --warnings:off -o:bin/huc src/huc.nim"
  echo "Built bin/huc"

task dev, "Build debug binary":
  exec "nim c --hints:off -o:bin/huc src/huc.nim"
  echo "Built bin/huc (debug)"

task test, "Run test suite":
  exec "nim c -r tests/test_all.nim"
