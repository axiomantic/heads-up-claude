# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/axiomantic/heads-up-claude/releases/tag/v0.1.0
