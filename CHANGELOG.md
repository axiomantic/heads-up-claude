# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-16

### Changed (BREAKING)
- **Architecture overhaul**: Split from single binary into daemon+statusline two-component system
  - `hucd` (daemon): Background process that monitors transcripts and fetches API data
  - `huc` (statusline): Lightweight binary that reads cached status and renders output
- **Performance**: Statusline rendering now < 5ms (previously 10+ seconds with large transcripts)
- Binary paths changed:
  - Old: `~/.local/bin/heads-up-claude`
  - New: `~/.local/bin/huc` (statusline) + `~/.local/bin/hucd` (daemon)
  - Backward-compat symlink: `heads-up-claude` -> `huc`

### Added
- **Daemon process (`hucd`)**:
  - Background transcript monitoring with incremental reads
  - API polling for real-time usage data (5-minute intervals)
  - Configuration hot-reload (edit hucd.json without restart)
  - Graceful signal handling (SIGTERM, SIGINT)
  - Atomic file writes to prevent race conditions
  - Transcript cache pruning (30-minute intervals)
- **Statusline improvements (`huc`)**:
  - Daemon management commands: `--daemon-status`, `--daemon-restart`, `--daemon-logs`
  - Staleness detection with warnings when daemon is not running
  - Instant rendering from cached status.json
- **Platform services**:
  - macOS: launchd service (`~/Library/LaunchAgents/com.headsup.claude.plist`)
  - Linux: systemd user service (`~/.config/systemd/user/hucd.service`)
- **Multi-config support**: Monitor multiple Claude config directories simultaneously
- **New cache files**:
  - `~/.claude/heads-up-cache/status.json` - Current usage stats
  - `~/.claude/heads-up-cache/hucd.json` - Daemon configuration
  - `~/.claude/heads-up-cache/transcripts.json` - Transcript offsets for incremental reads

### Fixed
- Eliminated blocking API calls during statusline refresh
- No more re-reading 400MB transcript files on every refresh
- Proper partial JSON line buffering for incremental reads
- Transcript truncation/rotation detection with automatic cache reset

### Removed
- Expect script (`get_usage.exp`) - replaced by daemon API polling
- Synchronous usage fetching - all I/O now happens in background daemon
- Legacy cache directory (`$TMPDIR/heads-up-claude`)

## [0.2.0] - 2025-01-09

### Fixed
- Zombie process prevention: subprocesses now have proper timeouts and are killed when parent dies
- Expect script explicitly kills spawned `claude /config` process on exit
- Stale lock cleanup now kills orphaned processes before removing locks
- Estimates now properly count messages within the 5-hour window (not all messages from recently-touched sessions)
- Graceful handling when `claude /config` prompts for input (trust dialogs, etc.)

### Added
- Uninstall script (`uninstall.sh`) with automatic settings.json cleanup
- PID tracking for background processes to enable cleanup of orphans
- `[usage fetch failed]` warning when cache data is stale (>5 hours)
- Signal traps (SIGINT, SIGTERM, SIGHUP) in expect script for proper cleanup

### Changed
- Reduced subprocess timeout from 60s to 30s with 5s kill-after grace period
- macOS timeout handling now uses explicit watchdog process instead of perl alarm

## [0.1.0] - 2025-10-24

### Added
- Initial release
- Real-time token usage tracking with conversation context display
- 5-hour rate limit monitoring with message counts
- Weekly usage tracking with session duration calculations
- Multi-plan support (Pro, Max 5, Max 20)
- Interactive installer with auto-detection
- Customizable display modes (emoji or descriptive text)
- Git branch detection and project directory display
- ISO datetime support for custom weekly reset times
- Efficient file caching system to minimize disk reads
- Percentage-based color-coded warnings for approaching limits
- Time-until-reset displays for both 5-hour and weekly windows

### Features
- Conversation context tracking shows actual context size from API calls
- Cache read tokens displayed separately with green indicator
- Plan auto-detection by analyzing message history
- Weekly reset time configuration (default: Wednesday 6pm Central)
- Command-line options: `--plan`, `--reset-time`, `--no-emoji`, `--install`, `--help`

[1.0.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v1.0.0
[0.2.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.2.0
[0.1.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.1.0
