# Marketing Posts für quickTERMINAL
> Copy-paste ready. Einfach den Text kopieren und posten.

---

## Hacker News (Show HN)

**Title:**
```
Show HN: quickTERMINAL – A 10k-line single-file terminal emulator for macOS
```

**Text (optional, als erster Kommentar):**
```
Hey HN,

I built a terminal emulator for macOS from scratch in a single Swift file.

- 10,000+ lines, one file, zero dependencies
- Hand-rolled VT100/VT220/xterm parser (13-state FSM)
- Native Cocoa rendering at 60 FPS (no Electron, no WebView)
- Lives in the menu bar, toggle with Ctrl+<
- Full 24-bit TrueColor, Sixel graphics, mouse tracking, Kitty keyboard protocol
- Built-in command palette (quickBAR) with 40 commands
- Multi-tab, split panes, session restore
- Auto-updater that checks GitHub Releases every 72h
- 4.8 MB app bundle, ~1.4 MB binary

No SwiftTerm, no libvte, no terminal library. Every escape sequence parsed from scratch.

The whole thing compiles with a single `swiftc` call.

https://github.com/LEVOGNE/quickTerminal
```

**Post here:** https://news.ycombinator.com/submit

---

## Reddit — r/macapps

**Title:**
```
quickTERMINAL — A blazing-fast terminal for macOS, written from scratch in one Swift file (10k lines, zero dependencies, 4.8 MB)
```

**Text:**
```
I've been building a terminal emulator for macOS entirely from scratch.

The entire app is a single Swift file — 10,000+ lines, no external dependencies, no Electron, no WebView.

What makes it different:
- Lives in your menu bar (no dock icon), toggle with Ctrl+<
- Hand-rolled VT parser (13-state FSM) — every escape sequence built from zero
- 60 FPS native Cocoa rendering with sub-pixel text
- 24-bit TrueColor, Sixel inline images, mouse tracking
- quickBAR command palette (like Spotlight for your terminal)
- Multi-tab, split panes, 7 prompt themes
- Session restore — tabs, splits, working directories all preserved
- Built-in auto-updater
- 4.8 MB app bundle

Free for personal use. Source is open on GitHub.

Download: https://github.com/LEVOGNE/quickTerminal/releases/latest
GitHub: https://github.com/LEVOGNE/quickTerminal
```

**Post here:** https://www.reddit.com/r/macapps/submit

---

## Reddit — r/swift

**Title:**
```
I built a complete terminal emulator in a single Swift file — 10,000+ lines, zero dependencies, pure Cocoa
```

**Text:**
```
Wanted to share a project I've been working on: quickTERMINAL — a fully featured terminal emulator for macOS, written entirely in one Swift file.

Some technical highlights:
- 13-state finite automaton VT parser — single-pass byte processing
- Zero-allocation ASCII fast-path (no String creation for plain text)
- Incremental UTF-8 decoding across read boundaries
- Direct CGContext rendering at 60 FPS with dirty-flag optimization
- Synchronized output (mode 2026) for flicker-free drawing
- Full SGR with 24-bit TrueColor + 256-color palette
- Inline Sixel graphics decoded on-the-fly
- PTY management with Carbon global hotkey (Ctrl+<)
- Compiles with a single `swiftc` call — no Xcode project, no SPM

No SwiftTerm, no libvte — every escape sequence implemented from scratch.

The architecture: Terminal (parser + grid) → TerminalView (NSView + PTY + rendering) → AppDelegate (window, tabs, splits)

GitHub: https://github.com/LEVOGNE/quickTerminal

Would love feedback from other Swift devs. What would you do differently with a 10k-line single-file project?
```

**Post here:** https://www.reddit.com/r/swift/submit

---

## Reddit — r/commandline

**Title:**
```
quickTERMINAL: A macOS terminal emulator written from scratch — 10k lines, single file, native rendering
```

**Text:**
```
Built a terminal emulator for macOS that lives in your menu bar.

Quick facts:
- Single Swift file, ~10,000 lines
- VT100/VT220/xterm compatible (hand-rolled parser)
- 24-bit TrueColor, Sixel graphics, mouse tracking (1000/1002/1003)
- SGR mouse encoding, bracketed paste, focus reporting
- Kitty keyboard protocol
- OSC 52 clipboard, OSC 8 hyperlinks, OSC 133 shell integration
- TERM=xterm-256color, COLORTERM=truecolor
- Built-in command palette, multi-tab, split panes
- Auto-updater via GitHub Releases

Works great with vim, neovim, tmux, htop, and most TUI apps.

GitHub: https://github.com/LEVOGNE/quickTerminal
Download: https://github.com/LEVOGNE/quickTerminal/releases/latest
```

**Post here:** https://www.reddit.com/r/commandline/submit

---

## Twitter/X

**Thread (3 tweets):**

**Tweet 1:**
```
I built a terminal emulator for macOS in ONE Swift file.

10,000+ lines. Zero dependencies. 4.8 MB app.

→ Hand-rolled VT parser (13-state FSM)
→ 60 FPS native Cocoa rendering
→ 24-bit TrueColor + Sixel graphics
→ Lives in your menu bar

github.com/LEVOGNE/quickTerminal
```

**Tweet 2:**
```
What's inside that single file:

- Full VT100/VT220/xterm emulation
- Mouse tracking + SGR encoding
- Kitty keyboard protocol
- Split panes + multi-tab
- 40-command palette (quickBAR)
- 7 prompt themes
- Auto-updater
- Session restore

No Electron. No WebView. No libvte. Pure Swift.
```

**Tweet 3:**
```
Free for personal use. Source is open.

If you're on macOS and want a fast, lightweight terminal that stays out of your way — give it a try.

Download: github.com/LEVOGNE/quickTerminal/releases/latest

⭐ Stars appreciated!
```

---

## Product Hunt

**Tagline (60 chars):**
```
A 10k-line single-file terminal emulator for macOS
```

**Description:**
```
quickTERMINAL is a blazing-fast terminal emulator for macOS, written entirely from scratch in one Swift file.

🚀 10,000+ lines of pure Swift — zero external dependencies
⚡ Native Cocoa rendering at 60 FPS
🎨 24-bit TrueColor, Sixel inline images, 7 prompt themes
📌 Lives in your menu bar — toggle with Ctrl+<
🔍 Built-in command palette with 40 commands
🔄 Auto-updater via GitHub Releases
💾 4.8 MB app bundle

No Electron. No WebView. Every escape sequence, every pixel, every frame — built from zero.

Free for personal use. Source available on GitHub.
```

**Post here:** https://www.producthunt.com/posts/new

---

## Dev.to Article

**Title:**
```
I Built a Complete Terminal Emulator in One Swift File (10,000+ Lines)
```

**Tags:** swift, macos, terminal, opensource

**Artikel-Idee:** Schreibe über die technische Architektur — der Parser, das Rendering, warum single-file. Dev.to liebt technische Deep-Dives.

---

## Timing-Tipps

- **Hacker News:** Dienstag–Donnerstag, 9-11 AM EST (15-17 Uhr CET)
- **Reddit:** Montag–Mittwoch, Vormittag
- **Twitter:** Morgens oder Abends
- **Product Hunt:** Dienstag–Donnerstag, 00:01 AM PST (Launch-Zeit)
