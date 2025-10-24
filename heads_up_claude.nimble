# Package

version       = "0.1.0"
author        = "Axiomantic"
description   = "A custom statusline for Claude Code that shows real-time token usage, rate limits, and weekly usage metrics"
license       = "MIT"
srcDir        = "src"
bin           = @["heads_up_claude"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task install, "Install the statusline to ~/.claude/statusline":
  exec "nim c -d:release -o:bin/heads_up_claude src/heads_up_claude.nim"
  exec "mkdir -p ~/.claude"
  exec "cp bin/heads_up_claude ~/.claude/statusline"
  echo "✓ Installed to ~/.claude/statusline"
  echo "Run '~/.claude/statusline --install' to configure"

task build, "Build release binary":
  exec "nim c -d:release -o:bin/heads_up_claude src/heads_up_claude.nim"
  echo "✓ Built bin/heads_up_claude"

task dev, "Build debug binary":
  exec "nim c -o:bin/heads_up_claude src/heads_up_claude.nim"
  echo "✓ Built bin/heads_up_claude (debug)"
