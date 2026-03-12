# quickTERMINAL Roadmap

This roadmap reflects current priorities and may change.

## ✅ 1.0 Stabilization (Done)

- Fixed PTY write-path reliability for large input bursts.
- Removed retain cycles in tab/split closure wiring.
- Tightened tab reorder consistency with repeated titles.
- Improved split restore correctness and persistence behavior.
- Added regression checks for parser and interaction edge cases.

## ✅ 1.1 Packaging and Distribution (Done)

- App bundle build pipeline (`build_app.sh`, `build_zip.sh`).
- Auto-updater via GitHub Releases (every 72h, clickable toast, session-preserving restart).
- Versioned changelog and release artifacts.

## ✅ 1.2 UX and Terminal Fidelity (Done)

- ~~Better scrollback/search ergonomics.~~ **Done** — scrollback search with match highlighting (quickBAR `Search` command).
- ~~Expanded diagnostics.~~ **Done** — parser diagnostics overlay (quickBAR `Parser` command).
- ~~Performance instrumentation.~~ **Done** — performance monitor overlay (quickBAR `Perf` command).
- ~~Git panel.~~ **Done** — branch, status, diff, commit history, GitHub API support, 7 new features in v1.2.0.
- ~~Claude Code usage badge.~~ **Done** — live session & weekly limits in footer, auto-connected.
- ~~Auto-updater.~~ **Done** — clickable toast, `.app` guard, session-preserving restart.

## ✅ 1.3 Developer Tools & Onboarding (Done)

- ~~WebPicker.~~ **Done** — CDP-based Chrome element picker via floating sidebar. Connect/Disconnect toggle, live hostname, DOM element selection, outerHTML → clipboard. Robust WebSocket handling.
- ~~Full English UI.~~ **Done** — all UI strings translated to English (Git panel, WebPicker, auth, feedback).
- ~~Onboarding video.~~ **Done** — first-launch AVKit video panel (480×300, auto-close, skip button, plays once).
- ~~Demo GIF.~~ **Done** — MP4 → GIF in README, 2.4 MB at 700px width.

## 1.4 Upcoming

- Signed app bundle and notarization flow.
- Homebrew formula support.
- Safari WebPicker support (Web Inspector Protocol).
- More quickBAR commands and inline prompt improvements.

## Community and Project Health

- Triage labels and issue templates in active use.
- Contributor onboarding docs maintained.
- Security response process with release notes.
