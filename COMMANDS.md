<div align="center">

```
              _      _    ____    _    ____
   __ _ _   _(_) ___| | _| __ )  / \  |  _ \
  / _` | | | | |/ __| |/ /  _ \ / _ \ | |_) |
 | (_| | |_| | | (__|   <| |_) / ___ \|  _ <
  \__, |\__,_|_|\___|_|\_\____/_/   \_\_| \_\
     |_|
```

<br>

**quickBAR Command Reference**

*Your complete guide to every command in quickTERMINAL's command bar.*

<br>

![Version](https://img.shields.io/badge/Version-1.2.0-blue?style=for-the-badge)
![Commands](https://img.shields.io/badge/Commands-40-brightgreen?style=for-the-badge)
![Shortcuts](https://img.shields.io/badge/Shortcuts-25%2B-orange?style=for-the-badge)
![App](https://img.shields.io/badge/App-4.8_MB-purple?style=for-the-badge)

<br>

---

</div>

## :mag: quickBAR

> [!TIP]
> Double-tap <kbd>Ctrl</kbd> to summon the **quickBAR**.
> Type a letter to filter. <kbd>←</kbd> <kbd>→</kbd> to navigate. <kbd>Enter</kbd> to execute. <kbd>Esc</kbd> to dismiss.

> [!NOTE]
> Commands with values show the current state in parentheses, e.g. `Opacity (99%)`.
> Slider/choice commands prompt for a new value. Toggle commands switch instantly.

---

### :zap: Quick Actions

| | Command | Shortcut | Description |
|:---:|---|:---:|---|
| :heavy_plus_sign: | **New Tab** | <kbd>⌘</kbd> <kbd>T</kbd> | Open a fresh terminal tab |
| :heavy_multiplication_x: | **Close Tab** | <kbd>⌘</kbd> <kbd>W</kbd> | Close the active tab |
| :broom: | **Clear** | <kbd>⌘</kbd> <kbd>K</kbd> | Wipe the scrollback buffer |
| :eye: | **Hide** | <kbd>Ctrl</kbd> + <kbd><</kbd> | Hide the terminal window |
| :gear: | **Settings** | — | Open preferences overlay |
| :question: | **Help** | <kbd>?</kbd> | Open the README viewer |
| :clipboard: | **Commands** | — | Show this reference |
| :stop_button: | **Quit** | <kbd>q</kbd> | Exit quickTERMINAL |

### :straight_ruler: Split Panes

| | Command | Shortcut | Description |
|:---:|---|:---:|---|
| :arrow_right: | **Split Vertical** | <kbd>⌘</kbd> <kbd>D</kbd> | Side by side panes |
| :arrow_down: | **Split Horizontal** | <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>D</kbd> | Top / bottom panes |

### :desktop_computer: Window Layout

> [!TIP]
> Snap your terminal to any position. Toggle commands restore previous size on second use.

| | Command | Description |
|:---:|---|---|
| :arrows_counterclockwise: | **Fullscreen** | Toggle entire desktop |
| :left_right_arrow: | **Horizont** | Toggle full screen width (keep height) |
| :arrow_up_down: | **Vertical** | Toggle full screen height (keep width) |
| :arrow_left: | **Left** | Snap to top-left quadrant (50% × 50%) |
| :arrow_right: | **Right** | Snap to top-right quadrant (50% × 50%) |
| :1234: | **Defaultsize** | Reset to 720×480 |
| :arrows_counterclockwise: | **Reset Window** | Reset size + position under tray icon |

### :flashlight: Cursor Commands

| | Command | Description |
|:---:|---|---|
| :black_large_square: | **Cursor Block** | Switch to block cursor █ |
| :straight_ruler: | **Cursor Beam** | Switch to beam cursor ▏ |
| :heavy_minus_sign: | **Cursor Underline** | Switch to underline cursor ▁ |
| :sparkles: | **Cursor Blink (on/off)** | Toggle cursor blinking |

### :art: Appearance Commands

> [!NOTE]
> These commands prompt for a value after selection. Type the new value and press <kbd>Enter</kbd>.

| | Command | Type | Range |
|:---:|---|---|---|
| :crystal_ball: | **Opacity (99%)** | Slider | 30–100% |
| :gem: | **Blur (96%)** | Slider | 0–100% |
| :pencil2: | **Fontsize (10pt)** | Slider | 8–18pt |
| :art: | **Theme (default)** | Choice | default, cyberpunk, minimal, powerline, retro, lambda, starship |
| :keyboard: | **Font (Fira Code)** | Choice | Fira Code, JetBrains Mono, Monocraft, Iosevka Thin |
| :rocket: | **Shell (zsh)** | Choice | zsh, bash, sh |

### :octocat: Git Panel

| | Command | Description |
|:---:|---|---|
| :octocat: | **GIT** | Toggle Git panel — shows branch, status, diff, recent commits |

> [!NOTE]
> The Git panel auto-detects the current repository. Toggle position between right side and bottom.
> Displays: current branch, changed files, staged changes, commit history.

### :bar_chart: Claude Code Usage

| | Command | Description |
|:---:|---|---|
| :bar_chart: | **AI Usage Badge** | Shows Claude Code session utilization in footer bar |

> [!NOTE]
> Auto-connects to Claude Code via local credentials. Shows session (5h) and weekly usage.
> Click the badge for detailed breakdown with progress bars and reset times.
> Toggle in Settings under "Claude Code". No manual token entry needed.

### :gear: Behavior Toggles

> [!NOTE]
> Toggle commands switch the setting instantly. Current state shown in parentheses.

| | Command | Default |
|:---:|---|:---:|
| :pushpin: | **Always on Top (on/off)** | On |
| :low_brightness: | **Auto-Dim (on/off)** | Off |
| :bulb: | **Syntax Highlighting (on/off)** | On |
| :clipboard: | **Copy on Select (on/off)** | On |
| :eye: | **Hide on Click Outside (on/off)** | Off |
| :eye: | **Hide on Deactivate (on/off)** | Off |
| :electric_plug: | **Launch at Login (on/off)** | Off |
| :arrows_counterclockwise: | **Auto-Check Updates (on/off)** | On |

### :arrows_counterclockwise: Update

| | Command | Description |
|:---:|---|---|
| :mag: | **Check for Updates** | Manually check GitHub for a new version |
| :arrow_down: | **Install Update (vX.Y.Z)** | Download + install available update (appears when update found) |
| :arrows_counterclockwise: | **Auto-Check Updates (on/off)** | Toggle automatic checks every 72 hours |

> [!NOTE]
> Updates preserve all settings, tabs, splits, working directories, and window state.
> The app restarts seamlessly after installing.

### :mag: Tools

| | Command | Description |
|:---:|---|---|
| :mag: | **Search** | Search through scrollback buffer — highlights matches with auto-clear |
| :bar_chart: | **Perf** | Toggle performance overlay — FPS, draw time, PTY read/write throughput |
| :wrench: | **Parser** | Toggle parser diagnostics — sequence counts, unhandled sequences |

### :warning: System

| | Command | Description |
|:---:|---|---|
| :rotating_light: | **Resetsystem** | Factory reset — confirmation prompt: `Sure? (y/n)` |

---

## :keyboard: Keyboard Shortcuts

> [!IMPORTANT]
> These shortcuts work globally in quickTERMINAL.

---

### :card_index_dividers: Window & Tabs

| Shortcut | Action |
|:---|---|
| <kbd>Ctrl</kbd> + <kbd><</kbd> | :rocket: Toggle window visibility (global hotkey) |
| <kbd>⌘</kbd> <kbd>T</kbd> | :heavy_plus_sign: New tab |
| <kbd>⌘</kbd> <kbd>W</kbd> | :heavy_multiplication_x: Close tab |
| <kbd>⌘</kbd> <kbd>←</kbd> / <kbd>→</kbd> | :left_right_arrow: Switch between tabs |
| <kbd>⌘</kbd> <kbd>D</kbd> | :arrow_right: Split pane vertical |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>D</kbd> | :arrow_down: Split pane horizontal |
| <kbd>Alt</kbd> + <kbd>Tab</kbd> | :arrows_counterclockwise: Switch split pane focus |
| <kbd>⌘</kbd> <kbd>K</kbd> | :broom: Clear scrollback buffer |
| <kbd>⌘</kbd> <kbd>C</kbd> | :clipboard: Copy selection |
| <kbd>⌘</kbd> <kbd>V</kbd> | :paperclip: Paste from clipboard |
| <kbd>⌘</kbd> <kbd>A</kbd> | :pencil2: Select all |
| Double-tap <kbd>Ctrl</kbd> | :mag: Open quickBAR |

---

### :flashlight: Terminal Navigation

| Shortcut | Action |
|:---|---|
| <kbd>Alt</kbd> + <kbd>←</kbd> / <kbd>→</kbd> | Move cursor word backward / forward |
| <kbd>Alt</kbd> + <kbd>Backspace</kbd> | Delete word backward |
| <kbd>⌘</kbd> + <kbd>Backspace</kbd> | Kill entire line (Ctrl+U) |
| <kbd>Shift</kbd> + <kbd>←</kbd> / <kbd>→</kbd> / <kbd>↑</kbd> / <kbd>↓</kbd> | Extend text selection |

---

### :zap: Signal Controls

> [!NOTE]
> Standard Unix signals for process control.

| Shortcut | Signal | Effect |
|:---:|:---:|---|
| <kbd>Ctrl</kbd> + <kbd>C</kbd> | SIGINT | :stop_button: Interrupt process |
| <kbd>Ctrl</kbd> + <kbd>Z</kbd> | SIGTSTP | :arrows_counterclockwise: Suspend process |
| <kbd>Ctrl</kbd> + <kbd>D</kbd> | EOF | :heavy_multiplication_x: End of input |
| <kbd>Ctrl</kbd> + <kbd>\\</kbd> | SIGQUIT | :stop_button: Quit process |
| <kbd>Ctrl</kbd> + <kbd>A</kbd>-<kbd>Z</kbd> | — | Standard control characters |

---

### :rocket: Shell Switching

> [!TIP]
> quickTERMINAL auto-discovers installed shells at startup.
> Switch instantly without leaving your workflow.

| Shortcut | Shell | Icon |
|:---:|---|:---:|
| <kbd>⌘</kbd> <kbd>1</kbd> | zsh (default) | :gem: |
| <kbd>⌘</kbd> <kbd>2</kbd> | bash | :crystal_ball: |
| <kbd>⌘</kbd> <kbd>3</kbd> | sh / fish | :globe_with_meridians: |

---

### :globe_with_meridians: German Keyboard Specials

> [!NOTE]
> Essential mappings for German (QWERTZ) keyboards.

| Shortcut | Output | Name |
|:---:|:---:|---|
| <kbd>Alt</kbd> + <kbd>N</kbd> | `~` | Tilde |
| <kbd>Alt</kbd> + <kbd>5</kbd> | `[` | Left bracket |
| <kbd>Alt</kbd> + <kbd>6</kbd> | `]` | Right bracket |
| <kbd>Alt</kbd> + <kbd>7</kbd> | `\|` | Pipe |
| <kbd>Alt</kbd> + <kbd>8</kbd> | `{` | Left brace |
| <kbd>Alt</kbd> + <kbd>9</kbd> | `}` | Right brace |

---

## :mouse2: Mouse Actions

> [!TIP]
> Hold 0.3 seconds before dragging to start text selection.
> Selection auto-copies to clipboard (configurable in Settings).

| | Action | Effect |
|:---:|---|---|
| :mouse2: | **Click** | Position cursor / clear selection |
| :point_right: | **Hold 0.3s + Drag** | Text selection |
| :speech_balloon: | **Double-click** | Select entire word |
| :link: | <kbd>⌘</kbd> + **Click** | Open hyperlink in browser |
| :hand: | <kbd>⌥</kbd> + **Click** | Drag the window |
| :trackball: | **Right-click** | Context menu (mouse tracking) |
| :scroll: | **Scroll wheel** | Scroll buffer / report to app |

---

## :gear: Settings Overview

> [!NOTE]
> Open via quickBAR (`Settings`) or the :gear: gear icon in the footer bar.

---

### :art: Appearance

| Setting | Range | Default |
|---|:---:|:---:|
| :crystal_ball: Window Opacity | `30-100%` | `99%` |
| :gem: Blur Intensity | `0-100%` | `96%` |
| :pencil2: Font Size | `8-18pt` | `10pt` |
| :keyboard: Font Family | System monospace | Auto |
| :flashlight: Cursor Style | Underline / Beam / Block | Underline |
| :sparkles: Cursor Blink | On / Off | Off |

### :zap: Behavior

| Setting | Range | Default |
|---|:---:|:---:|
| :pushpin: Always on Top | On / Off | On |
| :low_brightness: Auto-Dim | On / Off | Off |
| :eye: Hide on Click Outside | On / Off | Off |
| :eye: Hide on Deactivate | On / Off | Off |
| :clipboard: Copy on Select | On / Off | On |
| :electric_plug: Auto-Start at Login | On / Off | Off |
| :arrows_counterclockwise: Auto-Check Updates | On / Off | On |

### :art: Shell & Theme

| Setting | Range | Default |
|---|:---:|:---:|
| :rocket: Syntax Highlighting | On / Off | On |
| :gem: Prompt Theme | 7 themes | default |

---

## :framed_picture: Prompt Themes

> [!TIP]
> Switch themes via quickBAR (`Theme`) or Settings. Each theme styles your prompt differently.

| Theme | Style | Vibe |
|---|---|---|
| :gem: `default` | Clean and minimal | Everyday use |
| :zap: `cyberpunk` | Neon accents | Hacker aesthetic |
| :flashlight: `minimal` | Ultra-stripped | Maximum focus |
| :arrow_right: `powerline` | Segments with arrows | Status-rich |
| :art: `retro` | Classic green phosphor | Nostalgia |
| :globe_with_meridians: `lambda` | Functional style | Developer |
| :rocket: `starship` | Space-inspired | Exploration |

---

<div align="center">

> [!IMPORTANT]
> Double-tap <kbd>Ctrl</kbd> to open the **quickBAR** anytime.
> Type a letter to filter. <kbd>←</kbd> <kbd>→</kbd> to browse. <kbd>Enter</kbd> to execute.

<br>

![Built with Swift](https://img.shields.io/badge/Built_with-Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS-000000?style=flat-square&logo=apple&logoColor=white)
![quickTERMINAL](https://img.shields.io/badge/quickTERMINAL-v1.2.0-blue?style=flat-square)
![Lines](https://img.shields.io/badge/10000%2B_Lines-One_File-blue?style=flat-square)
![App](https://img.shields.io/badge/App-4.8_MB-brightgreen?style=flat-square)

</div>
