<div align="center">

<img src="icon.png" width="128" alt="quickTERMINAL">

<br>

<img src="quickTERMINAL.gif" width="700" alt="quickTERMINAL Demo">

<br>

**A blazing-fast, single-file terminal emulator for macOS.**

*Zero dependencies. Pure Swift. Lives in your menu bar. Built-in Git panel, Claude Code integration & auto-updater. 4.8 MB app bundle.*

<br>

![macOS](https://img.shields.io/badge/macOS-12%2B-black?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white)
![Lines](https://img.shields.io/badge/13000%2B_Lines-One_File-blue?style=for-the-badge)
![App](https://img.shields.io/badge/App-4.8_MB-purple?style=for-the-badge)
![License](https://img.shields.io/badge/License-Free_for_Personal_Use-green?style=for-the-badge)

<br>

[**Download quickTerminal.app (v1.3.0)**](https://github.com/LEVOGNE/quickTerminal/releases/latest) · [**Website**](https://levogne.github.io/quickTerminal/)

---

</div>

## Install

> **Download → Unzip → Remove Quarantine → Done.**

1. Download [`quickTerminal.zip`](https://github.com/LEVOGNE/quickTerminal/releases/latest)
2. Unzip and move `quickTerminal.app` to `/Applications/`

> [!CAUTION]
> ### macOS Gatekeeper — Important!
>
> quickTERMINAL is **not signed** with an Apple Developer certificate.
> macOS will block the app on first launch. **Run this command once to fix it:**
>
> ```bash
> xattr -cr /Applications/quickTerminal.app
> ```
>
> **Or use the included installer:**
>
> ```bash
> bash install.sh
> ```
>
> This removes the macOS quarantine flag and is completely safe.
> You only need to do this **once** after downloading.

3. Launch — quickTERMINAL appears in your **menu bar** (no dock icon)
4. Press <kbd>Ctrl</kbd> + <kbd><</kbd> to toggle the terminal

<br>

---

## Why quickTERMINAL?

> [!IMPORTANT]
> **13,000+ lines. One file. 4.8 MB app. Full terminal emulation.**
>
> No Electron. No WebView. No libvte. No SwiftTerm.
> Written from scratch with a hand-rolled VT parser, direct PTY management,
> and native Cocoa rendering. Every escape sequence, every pixel, every frame — built from zero.

<br>

<table>
<tr>
<td width="50%">

### Parser Engine
- **13-state finite automaton** — single-pass byte processing
- **Incremental UTF-8 decoding** — handles partial sequences across reads
- **Zero-allocation ASCII fast-path** — no String creation, no heap alloc
- **Inline Sixel parsing** — pixel data decoded on-the-fly

</td>
<td width="50%">

### Rendering
- **Sub-pixel rendering** at 60 FPS with dirty-flag optimization
- **Synchronized output** (mode 2026) eliminates flicker
- **24-bit TrueColor** — full 16.7M color support
- **Native Cocoa** — no WebView, no cross-platform shims

</td>
</tr>
</table>

<br>

---

## Features

### Terminal Emulation

> [!NOTE]
> quickTERMINAL implements a complete VT100/VT220/xterm-compatible terminal from scratch.

| | Feature | Details |
|:---:|---|---|
| :art: | **Colors** | 16 ANSI + 256 palette + 24-bit TrueColor (16.7M colors) |
| :pencil2: | **Text Styles** | Bold, Dim, Italic, Underline, Strikethrough, Inverse |
| :flashlight: | **Cursor Styles** | Block, Bar, Underline — steady or blinking (DECSCUSR) |
| :globe_with_meridians: | **Unicode** | Full-width CJK, Emoji, combining marks, zero-width chars |
| :triangular_ruler: | **Line Drawing** | DEC Special Graphics charset (box drawing, pipes, corners) |
| :mouse2: | **Mouse Tracking** | X10 (1000), Button-event (1002), Any-event (1003) |
| :computer_mouse: | **Mouse Encoding** | Legacy X11 + SGR (1006) for coordinates > 223 |
| :eyes: | **Focus Reporting** | Mode 1004 — sends ESC[I / ESC[O on focus change |
| :clipboard: | **Bracketed Paste** | Mode 2004 — apps distinguish typed vs pasted text |
| :paperclip: | **Clipboard** | OSC 52 — programs can read/write the system clipboard |
| :link: | **Hyperlinks** | OSC 8 — clickable URLs with Cmd+Click (dashed underline) |
| :framed_picture: | **Sixel Graphics** | Inline images via DCS q — full HLS/RGB color support |
| :keyboard: | **Kitty Keyboard** | Extended key protocol with modifier disambiguation |
| :zap: | **Sync Output** | Mode 2026 — batch screen updates, zero flicker |
| :desktop_computer: | **Alt Screen** | Modes 47/1047/1049 with cursor save/restore |
| :scroll: | **Scroll Region** | DECSTBM — apps define custom scroll areas |
| :left_right_arrow: | **Tab Stops** | Set/clear individual or all, 8-column default |
| :id: | **Device Attrs** | DA1 (Primary) + DA2 (Secondary) responses |
| :arrows_counterclockwise: | **Soft/Hard Reset** | DECSTR + RIS — full terminal state recovery |
| :left_right_arrow: | **BiDi / RTL** | Core Text bidi reordering for Arabic/Hebrew rendering |
| :shield: | **Protected Chars** | DECSCA / SPA / EPA — erase operations skip protected cells |
| :arrow_double_up: | **Double-Width/Height** | DECDWL / DECDHL — double-width and double-height lines |
| :left_right_arrow: | **Horizontal Margins** | DECLRMM + DECSLRM — left/right margin mode |
| :mag: | **Scrollback Search** | Search through scrollback buffer with match highlighting |
| :label: | **Shell Integration** | OSC 133 — semantic prompt marks (FinalTerm/iTerm2) |
| :card_file_box: | **Title Stack** | CSI t 22/23 — push/pop window title for nested TUI apps |
| :art: | **Color Reset** | OSC 104/110/111/112 — reset palette, FG, BG, cursor colors |
| :question: | **Mode Query** | DECRQM — query private and ANSI terminal modes |
| :wheelchair: | **Accessibility** | VoiceOver support — screen reader access to terminal content |
| :bar_chart: | **Diagnostics** | Built-in performance monitor and parser state viewer |
| :arrows_counterclockwise: | **Auto-Update** | Built-in update system — checks GitHub Releases every 72h, downloads + installs + restarts seamlessly |
| :octocat: | **Git Integration** | Built-in Git panel — branch, status, diff, commit history with GitHub API support |
| :bar_chart: | **Claude Code Usage** | Live Claude Code subscription usage in footer — session %, weekly limits, auto-connected |
| :globe_with_meridians: | **WebPicker** | CDP-based DOM element picker — connect to Chrome, hover-select any element, copies outerHTML to clipboard |
| :clapper: | **Onboarding Video** | First-launch intro video panel — plays once automatically, never shown again |

<br>

---

### The Parser

The terminal parser is a **13-state finite automaton** that processes every byte in a single pass:

```
                        ┌─────────────┐
                        │   ground    │ ◄── ASCII fast-path (0x20-0x7E)
                        └──────┬──────┘
                               │ ESC
                        ┌──────▼──────┐
                   ┌────┤     esc     ├────┐
                   │    └──────┬──────┘    │
                   │           │           │
            ┌──────▼──┐  ┌────▼────┐  ┌───▼───────┐
            │ escInter │  │   csi   │  │    osc    │
            └──────┬──┘  └────┬────┘  └───┬───────┘
                   │     (execute)    ┌───▼───────┐
                   │                  │  oscEsc   │
                   │                  └───┬───────┘
            ┌──────▼──────┐          (dispatch)
            │     dcs     │
            └──┬──────┬───┘
        ┌──────▼──┐ ┌─▼────────┐
        │ dcsPass │ │ dcsSixel │
        └─────────┘ └──────────┘
                    (render image)
```

> [!TIP]
> **What makes it special:**
> - **Zero-copy ASCII** — single bytes skip String decoding entirely
> - **Incremental UTF-8** — partial sequences buffer across reads, never drops a character
> - **Inline Sixel** — pixel data decoded in DCS passthrough, converted to CGImage with integer math
> - **Full SGR** — 30+ attributes including 256-color and TrueColor with coalesced parsing

<br>

<details>
<summary><b>Supported Escape Sequences</b> (click to expand)</summary>

<br>

**CSI** (Control Sequence Introducer)
```
CUU/CUD/CUF/CUB    Cursor movement .............. A/B/C/D
CNL/CPL             Next/previous line ........... E/F
CHA/HPA             Column absolute .............. G/`
CUP/HVP             Cursor position .............. H/f
CHT/CBT             Tab forward/backward ......... I/Z
ED/EL               Erase display/line ........... J/K
ICH/DCH/ECH         Insert/delete/erase chars .... @/P/X
IL/DL               Insert/delete lines .......... L/M
SU/SD               Scroll up/down ............... S/T
VPA/VPR             Vertical position ............ d/e
HPR                  Horizontal position rel ..... a
REP                  Repeat last char ............. b
SGR                  Graphics rendition ........... m (30+ codes)
SM/RM                Set/reset mode ............... h/l
DECSTBM              Scroll region ................ r
DECSLRM              Left/right margins ........... s (in DECLRMM)
XTWINOPS             Window operations ............ t
DA1/DA2              Device attributes ............ c / >c
DSR                  Status report ................ n
TBC                  Tab clear .................... g
DECSCUSR             Cursor style ................. SP q
DECSTR               Soft reset ................... !p
DECSCA               Char protection .............. " q
DECRQM               Mode query (private/ANSI) .... $ p
```

**CSI ? (Private Modes)**
```
1 ............ DECCKM (app cursor keys)
5 ............ DECSCNM (reverse video)
6 ............ DECOM (origin mode)
7 ............ DECAWM (auto-wrap)
25 ........... DECTCEM (cursor visible)
47/1047/1049 . Alt screen buffer
69 ........... DECLRMM (left/right margin mode)
1000/1002/1003 Mouse tracking modes
1004 ......... Focus reporting
1006 ......... SGR mouse encoding
2004 ......... Bracketed paste
2026 ......... Synchronized output
```

**OSC** (Operating System Command)
```
0/1/2 ......... Window/icon title
4 ............. Color palette set/query
7 ............. Current working directory
8 ............. Hyperlinks (uri)
10/11/12 ...... FG/BG/cursor color set/query
52 ............ Clipboard access (base64)
104 ........... Reset palette color(s)
110/111/112 ... Reset FG/BG/cursor color
133 ........... Shell integration (semantic prompt marks)
```

**ESC** (Escape Sequences)
```
ESC 7/8 ...... DECSC/DECRC (save/restore cursor)
ESC D/M/E .... IND/RI/NEL (index/reverse/next line)
ESC H ........ HTS (set tab stop)
ESC c ........ RIS (full reset)
ESC 6/9 ...... DECBI/DECFI (back/forward index)
ESC V/W ...... SPA/EPA (start/end protected area)
ESC =/> ...... DECKPAM/DECKPNM (keypad modes)
ESC ( / ) .... Designate G0/G1 charset
ESC # 3-6 .... DECDHL/DECDWL (double-height/width)
ESC # 8 ...... DECALN (alignment pattern)
```

**DCS** (Device Control String)
```
q ............. Sixel image data (HLS + RGB colors)
```

**C0/C1 Controls**
```
BEL  BS  TAB  LF  VT  FF  CR  SO  SI  ESC
IND  NEL  HTS  RI  DCS  CSI  OSC  ST (8-bit C1)
```

</details>

<br>

---

### Window & UI

| | Feature | Details |
|:---:|---|---|
| :gem: | **Menu Bar App** | Lives in the tray — no dock icon, instant access |
| :rocket: | **Global Hotkey** | `Ctrl+<` toggles from anywhere (Carbon API) |
| :crystal_ball: | **Frosted Glass** | NSVisualEffectView with HUD material + adjustable blur |
| :arrow_up_small: | **Popover Arrow** | Tracks tray icon position, collision-locked during resize |
| :card_index_dividers: | **Multi-Tab** | Unlimited tabs with drag-to-reorder and color coding |
| :straight_ruler: | **Split Panes** | Vertical + Horizontal with draggable divider (15-85%) |
| :mag: | **quickBAR** | Spotlight-style command bar with 37 commands, inline input prompts, and letterpress label |
| :gear: | **Settings Overlay** | Inline preferences with sliders, toggles, themes |
| :floppy_disk: | **Session Restore** | Tabs, shells, splits, directories restored on restart |
| :lock: | **Single Instance** | File lock prevents duplicate processes |
| :pushpin: | **Always on Top** | Pin window above all others |
| :low_brightness: | **Auto-Dim** | Dims window when unfocused (off by default) |
| :electric_plug: | **Auto-Start** | Launch at login via LaunchAgent |
| :open_file_folder: | **Drag & Drop** | Drag files/images into terminal — pastes shell-escaped path |
| :label: | **Custom Tab Names** | Double-click any tab to rename — custom names persist across sessions |
| :octocat: | **Git Panel** | Built-in Git panel with branch, status, diff, and commit history |
| :bar_chart: | **Claude Code Usage** | Live usage badge in footer — auto-connects to Claude Code, shows session & weekly limits |
| :shield: | **Crash Reporting** | Automatic crash logs to `~/.quickterminal/crash.log` |
| :arrows_counterclockwise: | **Auto-Update** | Checks GitHub Releases every 72h, one-click install with progress bar, session-preserving restart |
| :globe_with_meridians: | **WebPicker** | Floating sidebar for Chrome CDP element picking — connect, select DOM elements, auto-paste HTML |

<br>

---

## Shells

quickTERMINAL auto-discovers available shells and lets you switch instantly:

<table>
<tr>
<td>

| Shortcut | Shell |
|:---:|---|
| <kbd>⌘</kbd> <kbd>1</kbd> | zsh (default) |
| <kbd>⌘</kbd> <kbd>2</kbd> | bash |
| <kbd>⌘</kbd> <kbd>3</kbd> | sh / fish |

</td>
<td>

Each shell gets:
- Custom `ZDOTDIR` with syntax highlighting + prompt themes
- Per-tab history files (`~/.quickterminal/history/{tabId}`)
- Full environment: `TERM=xterm-256color`, `COLORTERM=truecolor`

</td>
</tr>
</table>

### Prompt Themes

> 7 built-in themes selectable from Settings:

| Theme | Style |
|---|---|
| `default` | Clean and minimal |
| `cyberpunk` | Neon accents |
| `minimal` | Ultra-stripped |
| `powerline` | Segments with arrows |
| `retro` | Classic green phosphor |
| `lambda` | Functional style |
| `starship` | Space-inspired |

<br>

---

## Keyboard Shortcuts

### Window & Tabs

| Shortcut | Action |
|:---|---|
| <kbd>Ctrl</kbd> + <kbd><</kbd> | Toggle window visibility (global) |
| <kbd>⌘</kbd> <kbd>T</kbd> | New tab |
| <kbd>⌘</kbd> <kbd>W</kbd> | Close tab |
| <kbd>⌘</kbd> <kbd>←</kbd> / <kbd>→</kbd> | Switch tabs |
| <kbd>⌘</kbd> <kbd>D</kbd> | Split pane vertical |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>D</kbd> | Split pane horizontal |
| <kbd>Alt</kbd> + <kbd>Tab</kbd> | Switch split pane focus |
| <kbd>⌘</kbd> <kbd>K</kbd> | Clear scrollback |
| <kbd>⌘</kbd> <kbd>C</kbd> | Copy selection |
| <kbd>⌘</kbd> <kbd>V</kbd> | Paste |
| <kbd>⌘</kbd> <kbd>A</kbd> | Select all |
| Double-tap <kbd>Ctrl</kbd> | quickBAR |

### Terminal Navigation

| Shortcut | Action |
|:---|---|
| <kbd>Alt</kbd> + <kbd>←</kbd> / <kbd>→</kbd> | Word backward / forward |
| <kbd>Alt</kbd> + <kbd>Backspace</kbd> | Delete word backward |
| <kbd>⌘</kbd> + <kbd>Backspace</kbd> | Kill line (Ctrl+U) |
| <kbd>Shift</kbd> + <kbd>←</kbd> / <kbd>→</kbd> / <kbd>↑</kbd> / <kbd>↓</kbd> | Extend text selection |
| <kbd>Ctrl</kbd> + <kbd>A-Z</kbd> | Standard control characters |
| <kbd>Ctrl</kbd> + <kbd>C</kbd> | SIGINT (interrupt) |
| <kbd>Ctrl</kbd> + <kbd>Z</kbd> | SIGTSTP (suspend) |
| <kbd>Ctrl</kbd> + <kbd>D</kbd> | EOF (end of input) |
| <kbd>Ctrl</kbd> + <kbd>\\</kbd> | SIGQUIT |

### German Keyboard

| Shortcut | Output |
|:---|:---:|
| <kbd>Alt</kbd> + <kbd>N</kbd> | `~` |
| <kbd>Alt</kbd> + <kbd>5</kbd> | `[` |
| <kbd>Alt</kbd> + <kbd>6</kbd> | `]` |
| <kbd>Alt</kbd> + <kbd>7</kbd> | `\|` |
| <kbd>Alt</kbd> + <kbd>8</kbd> | `{` |
| <kbd>Alt</kbd> + <kbd>9</kbd> | `}` |

<br>

---

## quickBAR

> Double-tap <kbd>Ctrl</kbd> to open the **quickBAR**. Type to filter by first letter.
> Navigate with <kbd>←</kbd> / <kbd>→</kbd>, execute with <kbd>Enter</kbd>, dismiss with <kbd>Esc</kbd>.

### Quick Actions

| Command | Shortcut | Action |
|---|:---:|---|
| **Quit** | `q` | Exit quickTERMINAL |
| **New Tab** | `⌘T` | Open new terminal tab |
| **Close Tab** | `⌘W` | Close current tab |
| **Clear** | `⌘K` | Clear terminal scrollback |
| **Hide** | `Ctrl+<` | Hide window |
| **Settings** | — | Open preferences overlay |
| **Help** | `?` | Show README viewer |
| **Commands** | — | Show command reference |

### Window Layout

| Command | Action |
|---|---|
| **Fullscreen** | Toggle fullscreen (entire desktop) |
| **Horizont** | Toggle full width (keep height) |
| **Vertical** | Toggle full height (keep width) |
| **Left** | Snap to top-left quadrant |
| **Right** | Snap to top-right quadrant |
| **Defaultsize** | Reset to 720×480 |
| **Reset Window** | Reset to default size + position |

### Split Panes

| Command | Shortcut | Action |
|---|:---:|---|
| **Split Vertical** | `⌘D` | Split pane side by side |
| **Split Horizontal** | `⇧⌘D` | Split pane top/bottom |

### Cursor

| Command | Action |
|---|---|
| **Cursor Block** | Switch to block cursor █ |
| **Cursor Beam** | Switch to beam cursor ▏ |
| **Cursor Underline** | Switch to underline cursor ▁ |
| **Cursor Blink (on/off)** | Toggle cursor blinking |

### Settings via quickBAR

> [!TIP]
> Commands with values show the current state in parentheses.
> Slider commands prompt for a new value after selection.

| Command | Type | Range |
|---|---|---|
| **Opacity (99%)** | Slider | 30–100% |
| **Blur (96%)** | Slider | 0–100% |
| **Fontsize (10pt)** | Slider | 8–18pt |
| **Theme (default)** | Choice | default, cyberpunk, minimal, powerline, retro, lambda, starship |
| **Font (Fira Code)** | Choice | Fira Code, JetBrains Mono, Monocraft, Iosevka Thin |
| **Shell (zsh)** | Choice | zsh, bash, sh |
| **Always on Top (on/off)** | Toggle | — |
| **Auto-Dim (on/off)** | Toggle | — |
| **Syntax Highlighting (on/off)** | Toggle | — |
| **Copy on Select (on/off)** | Toggle | — |
| **Hide on Click Outside (on/off)** | Toggle | — |
| **Hide on Deactivate (on/off)** | Toggle | — |
| **Launch at Login (on/off)** | Toggle | — |
| **Auto-Check Updates (on/off)** | Toggle | — |

### Update

| Command | Action |
|---|---|
| **Check for Updates** | Manually check GitHub for a new version |
| **Install Update (vX.Y.Z)** | Download and install available update (appears dynamically) |
| **Auto-Check Updates (on/off)** | Toggle automatic update checks (every 72h) |

### Tools

| Command | Action |
|---|---|
| **Search** | Search through scrollback buffer (highlights matches) |
| **Perf** | Toggle performance monitor (FPS, draw time, PTY throughput) |
| **Parser** | Toggle parser diagnostics (sequence counts, unhandled sequences) |

### System

| Command | Action |
|---|---|
| **Resetsystem** | Factory reset (confirmation: y/n) |

<br>

---

## Mouse

| Action | Effect |
|---|---|
| **Click** | Position cursor / clear selection |
| **Hold 0.3s + Drag** | Text selection |
| **Double-click** | Select word |
| <kbd>⌘</kbd> + **Click** | Open hyperlink |
| <kbd>⌥</kbd> + **Click** | Drag window |
| **Right-click** | Context menu (if mouse tracking on) |
| **Scroll wheel** | Scroll terminal / report to app |

> [!TIP]
> Selection auto-copies to clipboard (configurable in Settings).

<br>

---

## Settings

| Setting | Range | Default |
|---|:---:|:---:|
| Window Opacity | `30-100%` | `99%` |
| Blur Intensity | `0-100%` | `96%` |
| Font Size | `8-18pt` | `10pt` |
| Font Family | System monospace | Auto |
| Cursor Style | Underline / Beam / Block | Underline |
| Syntax Highlighting | On/Off | On |
| Prompt Theme | 7 themes | default |
| **Window** | | |
| Always on Top | On/Off | On |
| Auto-Dim | On/Off | Off |
| Hide on Click Outside | On/Off | Off |
| Hide on Deactivate | On/Off | Off |
| Copy on Select | On/Off | On |
| Auto-Start at Login | On/Off | Off |
| Auto-Check Updates | On/Off | On |
| **Claude Code** | | |
| Show Usage Badge | On/Off | On |
| Refresh Interval | 30s / 1m / 5m | 1m |

<br>

---

## Architecture

```
quickTerminal.app (4.8 MB)
├── Contents/
│   ├── MacOS/
│   │   ├── quickTerminal ·········· 1.3 MB binary (JetBrains + Monocraft embedded)
│   │   ├── _FiraCode-*-terminal.ttf  48 KB each
│   │   ├── _IosevkaThin-terminal.ttf 40 KB
│   │   └── shell/ ················· configs, themes, syntax highlighting
│   ├── Resources/
│   │   ├── AppIcon.icns ··········· app icon (16px–1024px)
│   │   └── quickTERMINAL.mp4 ·· Onboarding video (first-launch, plays once)
│   └── Info.plist ················· LSUIElement=true (menu bar app)

quickTerminal.swift (single file, ~13000 lines)
│
├── Terminal ·················· VT parser + state machine + grid
│   ├── Cell ················· Character + attributes + width + hyperlink
│   ├── TextAttrs ············ Bold, italic, underline, colors, etc.
│   ├── Sixel parser ········· DCS q inline image decoder
│   └── BiDi / RTL ··········· Core Text bidi reordering
│
├── TerminalView ·············· NSView + PTY + rendering + input
│   ├── Font system ·········· FiraCode, JetBrains, fallbacks
│   ├── Draw loop ············ 60 FPS, dirty-flag, sync output
│   ├── Selection ············ Click, drag, word-select, Shift+Arrow, copy
│   ├── Mouse ················ Tracking modes 1000-1006
│   ├── Keyboard ············· Full key encoding + Kitty protocol
│   └── Accessibility ········ VoiceOver / screen reader support
│
├── UpdateChecker ············· Auto-update system
│   ├── GitHub API ··········· Check releases every 72h
│   ├── Download ············· Progress-tracked ZIP download
│   └── Self-replace ········· Unzip, swap .app, rollback on failure, restart
│
├── GitPanelView ·············· Built-in Git integration
│   ├── Branch + Status ······ Current branch, changed/staged files
│   ├── Diff Viewer ·········· Inline diff display
│   └── GitHub Client ········ API integration for CI status
│
├── AIUsageManager ············ Claude Code usage tracking
│   ├── Token Auto-Discovery · Reads Claude Code credentials via security CLI
│   ├── Usage Polling ········ Fetches session/weekly limits at configurable interval
│   └── AIUsageBadge ········· Color-coded footer badge with detail popover
│
├── AppDelegate ··············· Window, tabs, splits, settings
│   ├── BorderlessWindow ····· Custom shape + popover arrow
│   ├── HeaderBarView ········ Tab bar + add button
│   ├── FooterBarView ········ Shell buttons + git branch + badges
│   ├── SettingsOverlay ······ Preferences UI
│   ├── CommandPaletteView ··· quickBAR — 40 commands with inline prompts
│   ├── HelpViewer ··········· Cinema-scroll markdown viewer
│   ├── DiagnosticsOverlay ··· Performance monitor + parser state viewer
│   ├── SplitContainer ······· Vertical/horizontal split panes
│   └── Scrollback Search ···· Full-text search with match highlighting
│
├── WebPickerSidebarView ·· Chrome CDP element picker with connect/disconnect
├── ChromeCDPClient ········ WebSocket CDP client for Chrome DevTools Protocol
└── OnboardingPanel ········ First-launch video panel (plays once, AVKit)
│
└── Build Pipeline
    bash build.sh     → quickTerminal binary (local testing)
    bash build_app.sh → quickTerminal.app (4.8 MB bundle)
    bash build_zip.sh → quickTerminal.zip (GitHub Release)
```

> [!IMPORTANT]
> **No dependencies. No packages. No XIBs. No storyboards.**
> One `swiftc` call. That's it.

<br>

---

## Build

```bash
# 1. Local testing
bash build.sh
./quickTerminal

# 2. App bundle (icon, fonts, shell configs)
bash build_app.sh
open quickTerminal.app

# 3. GitHub Release package (.app + install.sh + FIRST_READ.txt + LICENSE + README)
bash build_zip.sh
```

> [!NOTE]
> **Requirements:**
> - macOS 12+ (Monterey or later)
> - Swift toolchain (included with Xcode or Command Line Tools)
> - Frameworks: Cocoa, Carbon, AVKit

The `.app` bundle (4.8 MB) includes everything — binary, icon, 4 terminal-optimized fonts, shell configs, and prompt themes. The `.zip` adds the installer script and documentation for end users.

<br>

### Bundled Fonts

| Font | Style | Purpose |
|---|---|---|
| **FiraCode** | Regular, Bold | Primary monospace with ligatures (48 KB each) |
| **JetBrains Mono** | Light Italic | Italic text rendering (54 KB, embedded in binary) |
| **Monocraft** | Regular | Pixel-style alternative (60 KB, embedded in binary) |
| **Iosevka** | Thin | Ultra-light alternative (40 KB) |

> [!TIP]
> All fonts are terminal-optimized subsets — only the glyphs needed for terminal use.
> Total font payload: ~250 KB (vs. 61 MB for full font files).

<br>

---

## Open Source

quickTERMINAL is source-available with a dual license:

- **Personal & non-commercial use** — free and open
- **Commercial use** — requires a paid license

See [LICENSE](./LICENSE) for details. Contact: **l.ersen@icloud.com**

> **13,000+ lines of Swift. One file. Zero dependencies. 4.8 MB app. Full VT emulation + auto-updater.**

### Contributing

Contributions are welcome.

- Read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening a PR.
- Use small, focused PRs with a short manual test plan.
- For behavior changes, include before/after notes or screenshots.

### Security

Please do **not** report security issues in public issues.

- Read [SECURITY.md](./SECURITY.md) for the reporting process.
- Contact: **l.ersen@icloud.com**

### Roadmap

Planned milestones are tracked in [ROADMAP.md](./ROADMAP.md).

### Code of Conduct

This project follows [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).

<br>

---

<div align="center">

<img src="icon.png" width="64" alt="quickTERMINAL">

### quickTERMINAL v1.3.0

*13,000+ lines. One file. Zero dependencies. Git panel. Claude Code usage. Auto-updater.*

*Built with obsessive attention to every escape sequence, every pixel, every frame.*

*Copyright (c) 2026 LEVOGNE — Levent Ersen*

<br>

![Built with Swift](https://img.shields.io/badge/Built_with-Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS-000000?style=flat-square&logo=apple&logoColor=white)
![No Dependencies](https://img.shields.io/badge/Dependencies-Zero-brightgreen?style=flat-square)

</div>
