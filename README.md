# Heads Up Claude

A minimal statusline for Claude Code showing your project, branch, plan, and model.

```
personal | ~/Development/heads-up-claude | main | Max 20 | Opus 4.6
```

## Features

- **Project Directory**: Current working directory (from Claude Code stdin)
- **Git Branch**: Active branch with worktree detection
- **Plan Tier**: Your configured Claude plan (Free, Pro, Max 5, Max 20)
- **Model**: Current model name (with thinking indicator)
- **Custom Tag**: Optional colored prefix for identifying workspaces
- **Worktree Aware**: Shows worktree name when working in a git worktree

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
4. Build the `huc` binary and install to `~/.local/bin/`
5. Prompt you to configure:
   - Your Claude plan (Free, Pro, Max 5x, or Max 20x)
   - Optional custom tag prefix for the statusline
   - Tag color (if using a custom tag)
   - Display style (emoji icons or text labels)
6. Configure your selected Claude config directory's `settings.json`

**Fresh Install**: Use `bash install.sh --clear` to clear all previous settings and start fresh.

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

## Configuration

### Command Line Options

- `--tag=TEXT` - Prepend custom tag to statusline
- `--tag-color=COLOR` - Color for custom tag
- `--claude-config-dir=<path>` - Claude config directory (default: `$CLAUDE_CONFIG_DIR` or `~/.claude`)
- `--no-emoji` - Use text labels instead of emoji
- `--debug` - Enable debug logging to stderr
- `--install` - Run interactive installer
- `--help` - Show help message

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

### Git Worktrees

When working in a git worktree, the statusline shows the worktree name:

```
personal | ~/Development/heads-up-claude | main (wt: feature-branch) | Max 20 | Opus 4.6
```

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
│   ├── huc.nim                # Statusline entry point
│   ├── shared/
│   │   └── types.nim          # Shared type definitions
│   ├── huc/
│   │   └── render.nim         # Statusline rendering
│   └── installer.nim          # Interactive installer
├── tests/                     # Test files
├── install.sh                 # Installation script
├── uninstall.sh               # Uninstallation script
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
