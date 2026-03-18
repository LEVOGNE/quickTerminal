# Design: Project Rename — quickTerminal → SYSTEM TRAY TERMINAL (STT)

**Date:** 2026-03-18
**Status:** Approved

## Overview

Complete rename of the project from "quickTerminal" to "SYSTEM TRAY TERMINAL" with abbreviation "STT". The rename covers all layers: source files, binary, app bundle, bundle ID, config directory, display strings, build scripts, and documentation.

## Scope

### File & Directory Renames

| What | From | To |
|---|---|---|
| Project directory | `quickTerminal/` | `STT/` |
| Source file | `quickTerminal.swift` | `STT.swift` |
| Compiled binary | `quickTerminal` | `STT` |
| App bundle | `quickTerminal.app` | `STT.app` |

### Identifiers

| What | From | To |
|---|---|---|
| Bundle ID | `com.l3v0.quickterminal` | `com.l3v0.stt` |
| Config directory | `~/.quickterminal/` | `~/.stt/` |
| UserDefaults domain | `com.l3v0.quickterminal` | `com.l3v0.stt` |

### Display Strings (in-app)

| Location | From | To |
|---|---|---|
| Footer bar | `quickTERMINAL v{ver} — LEVOGNE © 2026` | `STT v{ver} — LEVOGNE © 2026` |
| Settings overlay title | `quickTERMINAL` | `SYSTEM TRAY TERMINAL` |
| About/version badge | `quickTERMINAL` | `STT` |
| Toast notifications | `quickTERMINAL` | `STT` |
| All other in-app text | `quickTERMINAL` / `quickTerminal` | `STT` |

### Build Scripts

- `build.sh`: update source file reference, binary output name
- `build_app.sh`: update `APP_NAME`, `BUNDLE_ID`, source file reference
- `build_zip.sh`: update output name, zip filename prefix, app bundle reference

### Documentation

- `README.md`, `CHANGELOG.md`, `COMMANDS.md`, `ROADMAP.md`, `MARKETING.md`, `CONTRIBUTING.md`, `SECURITY.md`, `FIRST_READ.txt`, `install.sh`
- `docs/index.html` (if contains branding)
- `CLAUDE.md`

## Migration Logic

On first launch after rename, the app checks for existing legacy data and migrates it:

```
1. If ~/.quickterminal/ exists AND ~/.stt/ does NOT exist:
   → Copy ~/.quickterminal/ to ~/.stt/
   → Delete ~/.quickterminal/ after successful copy

2. UserDefaults migration:
   → Read all keys from com.l3v0.quickterminal domain
   → Write into com.l3v0.stt domain (only if not already set)
   → Remove old com.l3v0.quickterminal domain after migration
```

Migration runs once at app startup (in `applicationDidFinishLaunching`), silently in the background. Old data is deleted after successful migration.

## Out of Scope

- GitHub repository rename (must be done manually on github.com)
- Update-checker URLs pointing to `l3v0/quickTerminal` — these will break if the GitHub repo is renamed. Update separately once the repo is renamed on GitHub.
- LaunchAgent plist name (kept as-is for simplicity; label inside updated to `com.l3v0.stt`)

## Risk / Notes

- **UserDefaults domain change**: New bundle ID means a fresh preferences domain. Migration logic copies old prefs to avoid user data loss.
- **Build cache**: After file rename, clean build recommended (`rm -f STT quickTerminal`).
- **git history**: `git mv quickTerminal.swift STT.swift` preserves history.
- **Existing `.app` bundles**: Old `quickTerminal.app` installed on other machines won't auto-update to new name — user must reinstall.
