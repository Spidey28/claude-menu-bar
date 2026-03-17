# Claude Monitor

A native macOS menu bar widget that shows your Claude Code context window usage in real-time.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Real-time context usage** — displays `CC 7%` in your menu bar, updating every 5 seconds
- **Color-coded percentage** — green, blue, yellow, orange, red as context fills up
- **Multi-session support** — tracks all active Claude Code sessions simultaneously
- **Detailed dropdown** — click to see per-session breakdown with progress bars, token counts, model, duration, and PID
- **Launch at Login** — one-click toggle to start automatically when you log in
- **Zero dependencies** — single Swift file, compiles with just `swiftc`
- **Native & lightweight** — pure AppKit, no Electron, no background services, no dock icon

## Screenshot

| Menu Bar | Dropdown |
|----------|----------|
| `CC 7%` (green) | Project name, progress bar, token count, model info |

### Color Scale

| Context Used | Color |
|-------------|-------|
| < 30% | Green |
| 30–60% | Blue |
| 60–80% | Yellow |
| 80–90% | Orange |
| > 90% | Red |

## Download

Download the latest DMG from the [Releases](https://github.com/nichochar/claude-menu-bar/releases) page. Open the DMG and drag **Claude Monitor** to your Applications folder.

## Requirements

- macOS 14.0+
- [Claude Code](https://claude.ai/code) installed and in use

## Build from Source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/nichochar/claude-menu-bar.git
cd claude-menu-bar
bash build.sh
open "Claude Monitor.app"
```

To also create a distributable DMG:

```bash
bash build.sh --dmg
```

## How It Works

1. Reads `~/.claude/sessions/*.json` to find running Claude Code processes (checks PID liveness)
2. Locates the JSONL conversation file for each active session in `~/.claude/projects/`
3. Parses the last assistant message's `usage` field to get token counts
4. Calculates context usage as a percentage of the 1M token context window
5. Renders in the menu bar with color coding and builds a detailed dropdown menu

### Data Sources

| File | Purpose |
|------|---------|
| `~/.claude/sessions/<pid>.json` | Active session metadata (PID, session ID, working directory) |
| `~/.claude/projects/<project>/<session-id>.jsonl` | Conversation log with per-message token usage |

No data is sent anywhere — everything is read locally from Claude Code's own files.

## Project Structure

```
claude-menu-bar/
  ClaudeUsage.swift    # Single-file Swift app (all logic)
  Info.plist           # macOS app bundle metadata
  build.sh             # Build script (icon gen, code sign, optional DMG)
  icon_gen.swift       # Generates app icon PNG at build time
  LICENSE              # MIT License
  README.md            # This file
```

## License

MIT
