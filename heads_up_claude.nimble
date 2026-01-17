# Package

version       = "0.3.0"
author        = "Axiomantic"
description   = "A statusline for Claude Code showing token usage, rate limits, and weekly metrics"
license       = "MIT"
srcDir        = "src"
bin           = @["huc", "hucd"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task install, "Install the program to ~/.local/bin":
  exec "nim c -d:release --hints:off --warnings:off -o:bin/huc src/huc.nim"
  exec "nim c -d:release --hints:off --warnings:off -o:bin/hucd src/hucd.nim"
  when defined(windows):
    exec "copy bin\\huc.exe \"%LOCALAPPDATA%\\Programs\\huc.exe\""
    exec "copy bin\\hucd.exe \"%LOCALAPPDATA%\\Programs\\hucd.exe\""
  else:
    exec "mkdir -p ~/.local/bin"
    exec "cp bin/huc ~/.local/bin/huc"
    exec "cp bin/hucd ~/.local/bin/hucd"
    exec "chmod +x ~/.local/bin/huc"
    exec "chmod +x ~/.local/bin/hucd"
    exec "ln -sf ~/.local/bin/huc ~/.local/bin/heads-up-claude"
  echo "Installed to ~/.local/bin/"
  echo ""
  echo "Next: Run ./install.sh to configure the daemon service"

task build, "Build release binaries":
  exec "nim c -d:release --hints:off --warnings:off -o:bin/huc src/huc.nim"
  exec "nim c -d:release --hints:off --warnings:off -o:bin/hucd src/hucd.nim"
  echo "Built bin/huc and bin/hucd"

task dev, "Build debug binaries":
  exec "nim c --hints:off -o:bin/huc src/huc.nim"
  exec "nim c --hints:off -o:bin/hucd src/hucd.nim"
  echo "Built bin/huc and bin/hucd (debug)"

task test, "Run test suite":
  exec "nim c -r tests/test_all.nim"
