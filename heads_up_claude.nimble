# Package

version       = "0.2.0"
author        = "Axiomantic"
description   = "A statusline for Claude Code showing estimated token usage, rate limits, and weekly metrics"
license       = "MIT"
srcDir        = "src"
bin           = @["heads_up_claude"]
namedBin      = {"heads_up_claude": "heads-up-claude"}.toTable
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task install, "Install the program to ~/.local/bin":
  exec "nim c -d:release --hints:off --warnings:off -o:bin/heads-up-claude src/heads_up_claude.nim"
  when defined(windows):
    exec "if not exist \"%LOCALAPPDATA%\\Programs\" mkdir \"%LOCALAPPDATA%\\Programs\""
    exec "copy bin\\heads-up-claude.exe \"%LOCALAPPDATA%\\Programs\\heads-up-claude.exe\""
    echo "✓ Installed to %LOCALAPPDATA%\\Programs\\heads-up-claude.exe"
    echo ""
    echo "Next step: Run the interactive installer to configure Claude Code:"
    echo "  heads-up-claude --install"
  else:
    exec "mkdir -p ~/.local/bin"
    exec "cp bin/heads-up-claude ~/.local/bin/heads-up-claude"
    exec "chmod +x ~/.local/bin/heads-up-claude"
    echo "✓ Installed to ~/.local/bin/heads-up-claude"
    echo ""
    echo "Next step: Run the interactive installer to configure Claude Code:"
    echo "  ~/.local/bin/heads-up-claude --install"

task build, "Build release binary":
  exec "nim c -d:release --hints:off --warnings:off -o:bin/heads_up_claude src/heads_up_claude.nim"
  echo "✓ Built bin/heads_up_claude"

task dev, "Build debug binary":
  exec "nim c --hints:off -o:bin/heads_up_claude src/heads_up_claude.nim"
  echo "✓ Built bin/heads_up_claude (debug)"

task test, "Run test suite":
  exec "nim c -r tests/test_all.nim"
