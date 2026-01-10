# Heads Up Claude

A statusline for Claude Code showing real-time token usage, rate limits, and weekly metrics extracted directly from Claude's usage data.

![Screenshot](docs/screenshot.png)

## Features

- **Token Usage Tracking**: Real-time conversation context size with cache read tokens
- **5-Hour Rate Limit**: Live session usage percentage and reset time from Claude's internal data
- **Weekly Usage**: Live weekly usage percentage and reset time from Claude's internal data
- **Automatic Data Extraction**: Reads usage directly from Claude's `/config` interface
- **Local-Only**: No browser extensions, no external API calls
- **Fallback Estimates**: Uses local transcript analysis if real data is unavailable
- **Customizable Display**: Choose between emoji icons or descriptive text

## Installation

### Quick Install (Recommended)

```bash
git clone https://github.com/axiomantic/heads-up-claude.git
cd heads-up-claude
bash install.sh
```

The install script will:
1. Auto-detect existing Claude config directories in your home directory
2. Prompt you to select which directory to install into
3. Check if Nim is installed (and offer to install it if not)
4. Build the binary and install it to `~/.local/bin/`
5. Install the usage data extraction script (`get_usage.exp`)
6. Prompt you to configure:
   - Your Claude plan (Free, Pro, Max 5×, or Max 20×)
   - Optional custom tag prefix for the statusline
   - Tag color (if using a custom tag)
   - Display style (emoji icons or text labels)
7. Configure your selected Claude config directory's `settings.json`

**Note**: Nim 2.0.0 or higher is required. Visit https://nim-lang.org/install.html for installation instructions.

### Upgrading

```bash
cd heads-up-claude
git pull
bash install.sh
```

### Uninstalling

```bash
bash uninstall.sh
```

This removes:
- Binary (`~/.local/bin/heads-up-claude`)
- Expect script (`~/.local/bin/get_usage.exp`)
- Config file (`~/.claude/heads_up_config.json`)
- Cache directory (`$TMPDIR/heads-up-claude`)
- `statusLine` entry from `~/.claude/settings.json` (requires `jq`)

## Understanding the Statusline

The statusline displays several key metrics to help you manage your Claude Code usage:

```
[ personal ] | ~/Development/project | feature-branch | Max 20 | Sonnet 4.5 | 💬 104.6K 65% 🟢 104.0K | 🕐 9/900 1% (5h) | 📅 50.4h/240h 21% (2d3h)
<custom tag> | <directory>          | <branch>        | <plan> | <model>    | <session tokens>       | <5-hour usage> | <weekly usage>
```

### Components

- **Custom Tag** (optional, customizable color): Personal identifier for this workspace (e.g., "personal", "work", "dev")
- **Project Directory** (blue): Current working directory
- **Git Branch** (magenta): Active git branch if in a repository
- **Plan Tier** (magenta): Your Claude plan (Free, Pro, Max 5, or Max 20)
- **Model** (cyan): Current model (🧠 emoji appears if thinking mode is enabled)

### 💬 Conversation Context (Session Tokens)

Shows the current conversation's token count and percentage of the auto-compact threshold (default: 160K tokens).

- Tracks actual context size from most recent API call
- Includes cache read tokens + new tokens from last exchange
- Color-coded warnings:
  - Yellow (normal)
  - Red (≥80%)
  - Bright red with ⚠️ (≥90%)
- Resets to zero after `/clear` or reduces after `/compact`

**Example**: `💬 104.6K 65% 🟢 104.0K` means 104,600 tokens used (65% of 160K threshold), with 104,000 tokens read from cache

### 🕐 5-Hour Rate Limit

Claude enforces message limits per rolling 5-hour window. This shows your current usage extracted directly from Claude's internal data:

- Reads actual session usage percentage from `claude /config`
- Shows percentage used and time until reset
- Automatically detects your plan tier (no configuration needed)
- **Plan Limits**:
  - Pro: 45 messages per 5 hours
  - Max 5×: 225 messages per 5 hours
  - Max 20×: 900 messages per 5 hours

**Example**: `🕐 9/900 1% (5h)` means 9 messages used out of 900 allowed (1% of your limit), with 5 hours until reset.

### 📅 Weekly Usage

Claude tracks weekly usage hours (session duration, not wall clock time). This shows your progress extracted directly from Claude's internal data:

- Reads actual weekly usage percentage from `claude /config`
- Shows percentage used and time until weekly reset
- Automatically detects your plan tier and weekly limits
- **Plan Limits**:
  - Pro: 40-80 hours/week
  - Max 5×: 140-280 hours/week
  - Max 20×: 240-480 hours/week

**Example**: `📅 50.4h/240h 21% (2d3h)` means 50.4 hours used out of 240 hours allowed (21% of your weekly limit), with 2 days 3 hours until reset.

## How It Works

The statusline extracts real usage data directly from Claude Code's built-in `/config` interface:

1. **Automated Extraction**: An expect script (`get_usage.exp`) runs `claude /config` in the background
2. **Navigation**: The script automatically navigates to the Usage tab
3. **Data Parsing**: Extracts session and weekly usage percentages and reset times
4. **Display**: Shows the data in your statusline with calculated time-until-reset

**Fallback Mode**: If the automated extraction fails (e.g., Claude not running), the statusline falls back to estimating usage from local transcript files and displays a `~estimates` indicator.

**Performance**: The usage data extraction runs once per statusline refresh (typically when switching between conversations). It takes ~5-10 seconds but happens asynchronously.

## Configuration

### Command Line Options

- `--no-emoji` - Use text labels (CTX, 5HR, WK) instead of emoji
- `--help` - Show help message
- `--install` - Run interactive installer
- `--claude-config-dir=<path>` - Claude config directory (default: $CLAUDE_CONFIG_DIR or ~/.claude)
- `--tag=TEXT` - Prepend custom tag to statusline
- `--tag-color=COLOR` - Color for custom tag

### Manual Configuration

Edit `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.local/bin/heads-up-claude --tag=\"personal\" --tag-color=\"bright-cyan\""
  }
}
```

Available tag colors: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `gray`, `bright-red`, `bright-green`, `bright-yellow`, `bright-blue`, `bright-magenta`, `bright-cyan`, `bright-white`

**Note**: The statusline shows `~estimates` when it falls back to local transcript analysis (if usage data extraction fails).

**Windows users**: Use the full path like `C:\Users\YourName\AppData\Local\Programs\heads-up-claude.exe`

### Plan Configuration

During installation, you'll be prompted to configure your Claude plan. This is used as a fallback when real usage data is unavailable:

1. **Free**: 10 messages per 5 hours
2. **Pro** ($20/month): 45 messages per 5 hours, ~40 hours per week
3. **Max 5×** ($100/month): 225 messages per 5 hours, ~140 hours per week
4. **Max 20×** ($200/month): 900 messages per 5 hours, ~240 hours per week

The configuration is saved to `~/.claude/heads_up_config.json` and can be updated by running `~/.local/bin/heads-up-claude --install` again.

**Note**: When real usage data is extracted from Claude, these configured limits are not used - the actual percentages and reset times from Claude are displayed instead.

## Development

### Building from Source

```bash
nimble build    # Release build
nimble dev      # Debug build
```

### Project Structure

```
heads-up-claude/
├── src/
│   ├── heads_up_claude.nim    # Main entry point
│   ├── types.nim              # Type definitions
│   ├── usage.nim              # Usage extraction and calculation
│   ├── display.nim            # Statusline formatting
│   ├── installer.nim          # Installer functions
│   └── nim.cfg                # Compiler config
├── tests/                     # Test files
├── get_usage.exp              # Expect script for extracting usage from Claude
├── install.sh                 # Unified install script
├── heads_up_claude.nimble     # Package definition
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### Running Tests

```bash
nimble test
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Version

Current version: **0.2.0** (2025-01-09)

See [CHANGELOG.md](CHANGELOG.md) for version history.
