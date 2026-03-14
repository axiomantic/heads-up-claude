# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-03-13

### Changed (BREAKING)
- **Simplified architecture**: Removed the background daemon (`hucd`) entirely. The statusline is now a single lightweight binary (`huc`) with no background process, no service files, no cache directories.
- **Minimal statusline output**: Displays only `tag | project_dir | branch | plan | model` instead of token counts, rate limits, and weekly usage data.
- Plan config (`heads_up_config.json`) now stores only the `plan` key (no more `five_hour_messages` or `weekly_hours_min`).

### Added
- **Git worktree detection**: When working in a git worktree, the statusline shows the worktree name: `main (wt: feature-branch)`.
- `loadPlanName` reads plan display name directly from config (no daemon dependency).

### Removed
- **Daemon (`hucd`)**: Background process, launchd plist, systemd service, daemon config (`~/.config/hucd/`), daemon logs, status.json, transcript cache.
- **Usage data display**: Token counts, cache read tokens, 5-hour rate limit, weekly usage tracking, context percentage.
- **API credentials setup**: `--setup-api` flag and `runApiSetup` removed. No more session key or org ID configuration.
- **Daemon management flags**: `--daemon-status`, `--daemon-restart`, `--daemon-logs` removed from `huc`.
- **Status file reader**: `huc/reader.nim` and `huc/daemon.nim` modules removed.
- All daemon-related rendering: `formatTokenCount`, `formatDuration`, `renderWaiting`, `renderWarning`, `renderError`, `renderContextSection`, `renderUsageSection`.
- All daemon-related types: `ApiStatus`, `EstimateStatus`, `ContextStatus`, `PlanStatus`, `ErrorStatus`, `Status`, `TranscriptEntry`, `TranscriptCache`, `DaemonConfig`, `ApiCredentials`.

### Migration
- The updated `install.sh` automatically cleans up the running daemon (stops launchd/systemd service, removes plist/unit, kills processes, removes daemon binary and config).
- The updated `uninstall.sh` still removes legacy daemon artifacts for users who skip the install step.

## [0.3.5] - 2026-02-02

### Fixed
- **Stale transcript counts** - Fixed bug where daemon would miss file content changes because directory mtime optimization was skipping files whose content grew but directory didn't change. The daemon now uses a two-phase scan:
  1. Walk directories to discover new files (still skips 30+ day cold directories)
  2. Check all cached transcripts for file size changes to catch modifications
- Token and message counts now update correctly as conversations progress

## [0.3.0] - 2026-01-16

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
- **New file locations**:
  - `~/.config/hucd/config.json` - Central daemon configuration (shared across all accounts)
  - `~/.config/hucd/logs/` - Daemon logs
  - `<config_dir>/heads-up-cache/status.json` - Per-account usage stats
  - `<config_dir>/heads-up-cache/transcripts.json` - Transcript offsets for incremental reads

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

[0.4.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.4.0
[0.3.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.3.0
[0.2.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.2.0
[0.1.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.1.0
