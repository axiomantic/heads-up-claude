# Heads Up Claude

A custom statusline for Claude Code that shows real-time token usage, rate limits, and weekly usage metrics.

## Features

- **Token Usage Tracking**: Real-time conversation context size with cache read tokens
- **5-Hour Rate Limit**: Message count tracking with time until reset
- **Weekly Usage**: Hours used vs weekly minimum with time until reset
- **Plan Support**: Auto-detection and manual configuration for Pro, Max 5x, and Max 20x plans
- **Customizable Display**: Choose between emoji icons or descriptive text
- **Interactive Installer**: Easy setup with auto-detection of your plan and reset time

## Quick Start

### Installation

1. Build from source:
```bash
git clone https://github.com/axiomantic/heads-up-claude.git
cd heads-up-claude
nim c -d:release heads-up-claude.nim
cp heads-up-claude ~/.claude/statusline
```

2. Run the interactive installer:
```bash
~/.claude/statusline --install
```

This will configure your `~/.claude/settings.json` with the appropriate plan, reset time, and display style.

### Help

```bash
~/.claude/statusline --help
```

## Development

### Building from Source

```bash
git clone https://github.com/axiomantic/heads-up-claude.git
cd heads-up-claude
nim c heads-up-claude.nim
cp heads-up-claude ~/.claude/statusline
```

### Project Structure

- **Source**: `heads-up-claude.nim` - Main source file
- **Config**: `nim.cfg` - Compiler configuration
- **Binary**: `~/.claude/statusline` (installed)
- **Cache**: `~/.cache/claude-statusline/file-cache.json`

## Current Status

**Version**: 0.1.0 (2025-10-24)

**Features**:
1. **Weekday constant fix**: Was using 3=Thursday instead of 2=Wednesday in Nim's enum
2. **Percentage display**: Changed all metrics to show % USED instead of % remaining (matches Claude dashboard)
3. **5-hour window**: Now tracks LATEST window end instead of oldest (shows correct time until reset)
4. **Reset time config**: Interactive installer prompts for reset time from https://claude.ai/settings/usage
5. **ISO format**: Reset time now passed as ISO datetime string with timezone support
6. **Error handling**: Parse errors are now surfaced instead of silently discarded
7. **Display modes**: Added `--no-emoji` switch for descriptive text instead of emoji
8. **Help message**: Added `--help` flag with usage examples

## What's Working

### 1. Statusline Display
The statusline now shows:
```
~/Development/styleseat | elijahr/bisect-queries | Max 20x | Sonnet 4.5 | 💬 104.6K 65% 🟢 104.0K cached | 🕐 178/900 19% (3h22m) | 📅 19.3h/240h 8% (5d23h)
```

**Components**:
- **Project directory** (blue)
- **Git branch** (magenta)
- **Plan tier** (magenta): Pro, Max 5x, or Max 20x
- **Model name** (cyan): with 🧠 emoji if thinking mode enabled
- **💬 Conversation Context**: Actual context size, % USED of compact threshold (160K default)
  - Uses `cache_read_input_tokens` from most recent message for accuracy
  - Properly accounts for `/compact` (reduces) and `/clear` (resets)
  - Color-coded: yellow (normal) → red (≥80%) → bright red with ⚠️ (≥90%)
  - Shows percentage USED (matches Claude dashboard behavior)
- **🟢 Cache Read Tokens**: Shows tokens being read from cache (green)
- **🕐 5-Hour Window**: Message count vs plan limit, % USED, time until reset
  - Tracks messages in active 5-hour windows
  - **FIXED (2025-10-23)**: Now shows time until LATEST window expires (not oldest)
  - Max 20x limit: 900 messages per 5 hours
  - Shows percentage USED (matches Claude dashboard behavior)
- **📅 Weekly Usage**: Hours used vs weekly minimum, % USED, time until reset
  - **FIXED (2025-10-23)**: Corrected weekday constant (2=Wednesday in Nim, not 3)
  - Now properly calculates based on configured reset day/time (default: Wednesday 6pm Central)
  - Only counts session duration within current week
  - Shows percentage USED (matches Claude dashboard behavior)
  - Interactive installer prompts for reset time from https://claude.ai/settings/usage

### 2. Plan Detection & Configuration

**Command Line Arguments**:
- `--plan=<pro|max5x|max20x>` - Specify plan tier
- `--reset-time=<ISO datetime>` - Specify reset time (e.g., "2025-10-30T18:00:00-05:00")
  - Supports timezone offsets or assumes local timezone if omitted
  - Converts to UTC for internal use
- `--no-emoji` - Use descriptive text (CTX, 5HR, WK, CACHE, WARN) instead of emoji
- `--help` - Show help message with usage examples
- `--install` - Run interactive installation

**Plan Limits** (in `PLAN_INFO` const):
```nim
Pro:     45 msgs/5hr,  40-80 hrs/week
Max 5x:  225 msgs/5hr, 140-280 hrs/week
Max 20x: 900 msgs/5hr, 240-480 hrs/week
```

**Auto-detection**: Analyzes conversation history to detect plan by finding max messages in any 5-hour window.

### 3. Install Feature

Run the interactive installer:
```bash
~/.claude/statusline --install
```

This will:
1. Auto-detect plan from conversation history
2. Show interactive menu with detected plan pre-selected
3. **Prompt for weekly reset time** (can paste from https://claude.ai/settings/usage)
   - Accepts formats like "Resets Wed 5:59 PM", "Wed 5:59 PM", "Wednesday 17:59"
   - Parses natural language and confirms with user
   - Defaults to Wednesday 6:00 PM Central if left blank
4. **Prompt for display style** with example outputs:
   - With emoji (default): `💬 104.6K 65% 🟢 104.0K cached | 🕐 178/900 19% (3h22m) | 📅 19.3h/240h 8% (5d23h)`
   - No emoji: `CTX 104.6K 65% CACHE 104.0K cached | 5HR 178/900 19% (3h22m) | WK 19.3h/240h 8% (5d23h)`
5. Update `~/.claude/settings.json` with:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline --plan=max20x --reset-time=\"2025-10-30T23:00:00+00:00\" --no-emoji"
  }
}
```
6. Show confirmation message with instructions to re-run `--install` to change settings

### 4. Caching System

**Cache Location**: `~/.cache/claude-statusline/file-cache.json`

**Cached Data** (per JSONL file):
- `modTime`: File modification time (for invalidation)
- `contextTokens`: Current context size
- `cacheReadTokens`: Cache read tokens
- `apiTokens`: Total API tokens (for 5-hour window)
- `firstTimestamp`: First message timestamp
- `lastTimestamp`: Last message timestamp
- `messageCount`: Number of messages after last summary

**Cache invalidation**: Automatically re-reads files when modified.

## Weekly Reset Calculation Fix

**Problem 1**: Was calculating from 7 days ago, showing ~15.5h usage when dashboard showed 9%.

**Solution 1**:
- Weekly resets on **Wednesday at 6pm Central** (23:00 UTC during CST, 00:00 UTC during CDT)
- Now only counts session duration within current week (since last Wednesday reset)
- Properly handles sessions that span the reset time

**Problem 2**: Incorrect weekday constant and flawed time remaining display.

**Root Cause**:
- Used `DEFAULT_WEEKLY_RESET_DAY = 3` assuming Sunday=0, but Nim's `WeekDay` enum starts with Monday=0
- So `3` was Thursday, not Wednesday!
- This caused the "next reset" calculation to be off by 1 day

**Solution 2**:
- Fixed `DEFAULT_WEEKLY_RESET_DAY = 2` (Wednesday in Nim's 0=Monday enum)
- Improved `getNextWeeklyReset()` logic for clarity
- Time remaining now correctly shows `6d0h` on Thursday (6 days until next Wednesday reset)

**Problem 3**: Percentages showed "remaining" instead of "used", inconsistent with Claude dashboard.

**Solution 3**:
- Changed all percentage displays (context, 5-hour, weekly) to show % USED
- Updated color thresholds: yellow (normal) → red (≥80%) → bright red with ⚠️ (≥90%)

**Problem 4**: 5-hour window time showed incorrect reset time.

**Root Cause**:
- Was tracking the OLDEST window end time instead of the LATEST
- Multiple sessions create overlapping windows, need to show when the last one expires

**Solution 4**:
- Changed from `oldestWindowEnd` to `latestWindowEnd`
- Now tracks the window that expires LAST (closest future time)
- Shows correct time until 5-hour limit resets

**Implementation**:
```nim
const
  DEFAULT_WEEKLY_RESET_DAY = 2  # Wednesday (0=Monday in Nim's WeekDay enum)
  DEFAULT_WEEKLY_RESET_HOUR_UTC = 23  # 6pm Central

proc getNextWeeklyReset(): DateTime =
  # Calculate next Wednesday at 23:00 UTC
  # Handles both "reset later today" and "reset next Wednesday" cases

proc calculate5HourAndWeeklyUsage(...):
  let nextReset = getNextWeeklyReset()
  let lastReset = nextReset - initDuration(days = 7)
  # Only count sessions where lastTimestamp >= lastReset
```

## Next Steps (When Resuming)

### 1. Test Install Flow
```bash
# Test the installer
~/.claude/statusline --install

# Should:
# - Detect plan from conversation history
# - Show interactive prompt with auto-detected plan
# - Update settings.json
# - Show success message
```

### 2. Verify Settings Update
```bash
# Check that settings.json was updated correctly
cat ~/.claude/settings.json | jq '.statusLine'

# Should show:
# {
#   "type": "command",
#   "command": "/Users/elijahrutschman/.claude/statusline --plan=max20x"
# }
```

### 3. Test Different Plans
```bash
# Test with different plan arguments
cat /tmp/statusline-input.json | ~/.claude/statusline --plan=pro
cat /tmp/statusline-input.json | ~/.claude/statusline --plan=max5x
cat /tmp/statusline-input.json | ~/.claude/statusline --plan=max20x
```

### 4. Restart Claude Code
After installation, restart Claude Code to see the new statusline in action.

## Important Files

### Source Files
- `heads-up-claude.nim` - Main source code
- `nim.cfg` - Compiler configuration
- `README.md` - This documentation

### Installed Files
- `~/.claude/statusline` - Compiled binary (installed)
- `~/.claude/settings.json` - Claude settings (configured by installer)
- `~/.cache/claude-statusline/file-cache.json` - Token/usage cache

### Data Files
- `~/.claude/projects/*/session-*.jsonl` - Session transcripts

### Build Commands
```bash
# Compile from source
nim c heads-up-claude.nim

# Install compiled binary
cp heads-up-claude ~/.claude/statusline

# Run interactive installer
~/.claude/statusline --install

# Test with plan
cat /tmp/statusline-input.json | ~/.claude/statusline --plan=max20x
```

## Technical Details

### Token Counting Strategy

**Conversation Context** (most accurate):
- Uses `cache_read_input_tokens + new_tokens` from most recent API call
- Represents actual current context size
- Matches system reminder token counts

**5-Hour Window**:
- Counts messages (not tokens) in active 5-hour windows
- Each window starts at rounded hour, expires 5 hours later

**Weekly Usage**:
- Calculates session duration (last - first timestamp) in hours
- Only counts duration within current week
- Resets Wednesday 6pm Central

### Summary Types
JSONL files contain `{"type":"summary"}` entries when conversation is compacted. Token counting resets after each summary to get accurate "current context" size.

## Known Issues / Notes

1. **Unicode in output**: Using UTF-8 emoji bytes directly (e.g., `\xf0\x9f\x92\xac` for 💬)
2. **Nim warnings**: Deprecated DateTime field setters, MD5 module deprecation - not critical
3. **Weekly reset time**: Hardcoded to Wednesday 6pm Central (23:00 UTC) - using UTC so DST doesn't affect it
4. **Settings backup**: Created at `~/.claude/settings.json.backup` before testing install
5. **Weekday enum**: Nim's `WeekDay` starts with Monday=0, not Sunday=0 (fixed in latest version)

## Performance

- Compilation: ~17 seconds with full rebuild
- Runtime: <1 second (cached), ~2-3 seconds (uncached with 90+ JSONL files)
- Cache efficiency: Avoids re-reading unchanged JSONL files

## Testing Status

✅ **Completed**:
- Command line argument parsing
- Plan detection heuristics
- Weekly calculation fix
- Statusline display with all emojis
- Cache system
- Compilation successful

⏳ **Ready to Test**:
- Install flow (`--install`)
- Interactive plan selection
- Settings.json update
- Full integration with Claude Code

## Emojis Used

- 💬 (U+1F4AC): Conversation context
- 🟢 (U+1F7E2): Cached tokens
- 🕐 (U+1F550): 5-hour window
- 📅 (U+1F4C5): Weekly usage
- 🧠 (U+1F9E0): Thinking mode (conditional)
- ⚠️ (U+26A0): Warnings when approaching limits
