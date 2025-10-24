# Package

version       = "0.1.0"
author        = "Axiomantic"
description   = "A custom statusline for Claude Code that shows real-time token usage, rate limits, and weekly usage metrics"
license       = "MIT"
srcDir        = "src"
bin           = @["heads_up_claude"]
namedBin      = {"heads_up_claude": "heads-up-claude"}.toTable
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task install, "Install the program to ~/.claude/heads-up-claude":
  exec "nim c -d:release -o:bin/heads-up-claude src/heads_up_claude.nim"
  exec "mkdir -p ~/.claude"
  exec "cp bin/heads-up-claude ~/.claude/heads-up-claude"
  echo "✓ Installed to ~/.claude/heads-up-claude"
  exec "~/.claude/heads-up-claude --install"

task build, "Build release binary":
  exec "nim c -d:release -o:bin/heads_up_claude src/heads_up_claude.nim"
  echo "✓ Built bin/heads_up_claude"

task dev, "Build debug binary":
  exec "nim c -o:bin/heads_up_claude src/heads_up_claude.nim"
  echo "✓ Built bin/heads_up_claude (debug)"

task test, "Run test suite":
  exec "nim c -r tests/test_all.nim"
