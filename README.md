# DiskSpace CLI

A single-file, lightweight macOS disk space monitor and cleaner with optional GUI notifications.

Features
- Visual, colored progress bar and icons
- Smart detection of common space hogs (Warp logs, Docker, VS Code, dev caches, browsers, trash, old downloads)
- Interactive cleanup or safe auto-clean
- Daily scheduled checks via LaunchAgent
- JSON output for integrations
- `ds` wrapper to use slash-style commands (e.g., `ds /clean`)

Quick Start
- Check usage: `diskspace check`
- Interactive cleanup: `diskspace clean`
- Safe auto-clean: `diskspace auto-clean`
- Schedule daily notification: `diskspace schedule`
- JSON report: `diskspace check --json`
- Slash-style wrapper: `ds /clean`

Install
```bash
# Global install (recommended):
sudo install -m 0755 "$HOME/diskspace" /usr/local/bin/diskspace

# Optional: add ds wrapper to PATH
mkdir -p "$HOME/bin"
cp "$HOME/bin/ds" /usr/local/bin/ds 2>/dev/null || true
```

Schedule
```bash
diskspace schedule   # daily at 10:00 AM
diskspace unschedule
```

Config
```bash
diskspace config  # change threshold (default 80%)
```

JSON Example
```json
{
  "disk_usage_percent": 76,
  "free_space": "47Gi",
  "threshold": 80,
  "status": "ok",
  "cleanup_opportunities": {
    "total_reclaimable": 1838416,
    "problems": [
      {"id": "devcache_.gradle", "size": 1838416, "description": "Dev cache - .gradle", "command": "rm -rf /Users/you/.gradle"}
    ]
  }
}
```

Development
- Single source file: `diskspace`
- Wrapper: `bin/ds`

License
MIT