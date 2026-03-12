# Changelog

All notable changes to quickTERMINAL are documented here.

---

## v1.3.0 — 2026-03-12

### New Features
- **WebPicker** — Chrome DevTools Protocol (CDP) based DOM element picker. Connects to Chrome via WebSocket, lets you hover-select any element on any webpage, copies `outerHTML` to clipboard and auto-pastes into terminal. Floating sidebar with Connect/Disconnect toggle, live hostname display, and element preview.
- **Onboarding Video** — First-launch intro panel (480×300, centered). Plays `quickTERMINAL.mp4` once using AVKit, auto-closes when done, has "✕ Skip" button. Never shown again after first view (UserDefaults flag).
- **Full English UI** — All UI strings translated to English: Git panel, WebPicker, GitHub auth, feedback toasts, error messages, Claude API strings.
- **Demo GIF** — `quickTERMINAL.gif` added to README (MP4 → GIF, 700px, 2.4 MB, auto-plays on GitHub).

### Bug Fixes
- **WebSocket silent death** — `ChromeCDPClient.receiveLoop` now fires `onDisconnected` callback on `.failure`, preventing the UI from getting stuck in "connected" state when Chrome crashes or the tab is killed externally.
- **pollTimer not reset on reconnect** — `connect()` now invalidates `pollTimer` before starting a new session, preventing duplicate polling timers when the user reconnects without disconnecting first.
- **Tab closed externally** — `refreshTabTitle` returning `nil` (tab not found in Chrome's `/json/list`) now triggers a full `handleUnexpectedDisconnect(message: "Tab was closed")` instead of incorrectly showing "Navigating" state.
- **Stale onDisconnected closure** — `disconnect()` now sets `cdp.onDisconnected = nil` before closing, preventing a stale closure race where a final WebSocket `.failure` after manual disconnect could re-trigger disconnect logic.
- **Teardown duplication** — Disconnect/cleanup logic was duplicated in 3 places. Extracted into `handleUnexpectedDisconnect(message:)` with a `guard isConnected` gate to prevent double-firing.
- **titlePollTimer churn** — `startTitlePolling()` was being recreated on every HTTP callback. Extracted into a dedicated method called once after connect, preventing timer accumulation.
- **targetId extraction** — Replaced hand-rolled `wsURL.components(separatedBy: "/").last` with `URL(string: wsURL)?.lastPathComponent` for correct and reliable target ID extraction.

### Renames / Cleanup
- `HTMLPickerSidebarView` → `WebPickerSidebarView`
- `htmlPickerSidebarView` → `webPickerSidebarView` (AppDelegate)
- `onHTMLPickerToggle` → `onWebPickerToggle` (HeaderBarView)
- `setHTMLPickerActive` → `setWebPickerActive`
- `htmlPickerRightDivider` → `webPickerRightDivider`
- `toggleHTMLPicker` → `toggleWebPicker`
- `htmlPickerBrowser` → `webPickerBrowser` (UserDefaults key)
- `htmlBtn` → `webPickerBtn` (HeaderBarView)
- Removed dead `HTMLPickerPanel` class (282 lines)
- Removed all `print("[CDP]...")` debug statements

---

## v1.2.1 — 2026-03-11

### Bug Fixes
- **Auto-updater** — Clickable toast notification for update install. `.app` guard prevents update on non-bundled binary.

---

## v1.2.0 — 2026-03-10

### New Features
- **Git Panel** — 7 new features: branch display, changed files, diff viewer, staged changes, commit history, GitHub API CI status, panel position toggle (right/bottom).
- **Claude Code Usage Badge** — Live session & weekly limits in footer. Auto-connects via local credentials, color-coded, click for detail popover.
- **Drag & Drop** — Drop files/images from Finder → shell-escaped path inserted at cursor.
- **Custom Tab Names** — Double-click tab to rename; persists across sessions.

---

## v1.1.0 — 2026-03-08

### New Features
- Session restore — tabs, shells, splits, working directories.
- quickBAR — 40-command Spotlight-style palette.
- Multi-tab with color coding and drag-to-reorder.
- Split panes — vertical and horizontal with draggable divider.
- Auto-updater — GitHub Releases check every 72h.

---

## v1.0.0 — 2026-03-01

### Initial Release
- VT100/VT220/xterm terminal emulator from scratch (13-state FSM parser).
- 60 FPS CGContext rendering. 24-bit TrueColor. Sixel graphics.
- Menu bar app, global hotkey Ctrl+<.
- Single Swift file, zero dependencies, 4.8 MB app bundle.
