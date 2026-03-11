# AI Usage Display for quickTerminal

## Overview

Display Claude Code subscription usage (session limits, weekly limits) as a small badge in quickTerminal's Footer Bar. Clicking the badge opens a detail popover with full usage breakdown.

## Data Source

- **API Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
- **Authentication:** Bearer token from macOS Keychain
  - Service: `"Claude Code-credentials"`
  - Field: `claudeAiOauth.accessToken`
  - Header: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
- **Response format:**

```json
{
  "five_hour": {
    "utilization": 37.0,
    "resets_at": "2026-02-08T04:59:59.000000+00:00"
  },
  "seven_day": {
    "utilization": 26.0,
    "resets_at": "2026-02-12T14:59:59.771647+00:00"
  },
  "seven_day_opus": null,
  "seven_day_sonnet": {
    "utilization": 1.0,
    "resets_at": "2026-02-13T20:59:59.771655+00:00"
  },
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  }
}
```

## UI Components

### 1. Footer Bar Badge

- Small chip next to existing footer elements (left of version label)
- Shows: `◉ 37%` (5h session utilization) with color coding:
  - Green (accent): 0-50%
  - Yellow/Orange: 50-80%
  - Red: 80-100%
- Click opens detail popover
- Hidden when no token is available or feature is disabled

### 2. Detail Popover (on click)

```
┌─────────────────────────────┐
│  Claude Code Usage          │
│─────────────────────────────│
│  Session (5h)               │
│  ██████░░░░  37%            │
│  Reset: 14:59 (in 2h 13m)  │
│                             │
│  Weekly (All Models)        │
│  ████░░░░░░  26%            │
│  Reset: Mi, 12. Feb         │
│                             │
│  Weekly (Sonnet)            │
│  █░░░░░░░░░  1%             │
│  Reset: Do, 13. Feb         │
│                             │
│  Extra Usage: Deaktiviert   │
│─────────────────────────────│
│  ↻ Aktualisiert vor 30s     │
└─────────────────────────────┘
```

- Opus entry shown only when `seven_day_opus` is non-null
- Sonnet entry shown only when `seven_day_sonnet` is non-null
- Extra usage section shown only when `is_enabled` is true
- Relative time display for reset timestamps (e.g., "in 2h 13m", "Mi, 12. Feb")

### 3. Settings Integration

- New section "AI Usage" in SettingsOverlay
- Toggle: Show usage badge (On/Off), default: On
- Refresh interval picker: 30s / 1min / 5min, default: 60s
- Status display: "Connected" / "No token found" / "Error: ..."

## Architecture

### New Classes

**`AIUsageManager`**
- Reads OAuth token from macOS Keychain via `Security` framework
- Polls `api.anthropic.com/api/oauth/usage` at configurable interval
- Parses JSON response into structured data
- Notifies UI via callback/delegate pattern
- Caches last response for immediate display
- Handles token expiry and network errors gracefully

**`AIUsageBadge`** (NSView)
- Small badge rendered in FooterBarView
- Shows utilization percentage with color-coded dot
- Handles click to toggle popover

**`AIUsagePopover`** (NSView)
- Frosted-glass overlay (matching existing quickTerminal style)
- Progress bars for each usage category
- Relative time formatting for reset timestamps
- Auto-dismisses on click outside

### Integration Points

- `FooterBarView`: Add AIUsageBadge as subview
- `SettingsOverlay`: Add AI Usage settings section
- `AppDelegate/TerminalController`: Instantiate and own AIUsageManager
- `UserDefaults`: Store preferences (enabled, refresh interval)

### Keychain Access

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "Claude Code-credentials",
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]
// Parse JSON -> claudeAiOauth.accessToken
```

## Extensibility

- `AIUsageManager` designed as base pattern for future providers
- Provider-specific subclasses can implement different APIs (OpenAI, etc.)
- Badge and popover support multiple provider entries

## Non-Goals (for v1)

- Manual API key input (uses existing Claude Code OAuth token)
- Multiple simultaneous providers
- Historical usage graphs
- Push notifications for limit warnings
