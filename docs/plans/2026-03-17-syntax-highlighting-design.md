# Design: Syntax Highlighting + File Drop onto Tab Header

**Date:** 2026-03-17
**Status:** Approved

---

## Overview

Two new features for the Text Editor tab:

1. **Syntax Highlighting** — Live token coloring for JSON, HTML, CSS, JavaScript, with auto-detection from file extension.
2. **File Drop on Tab Header** — Drag a file from Finder onto the tab header → opens it in a new editor tab.

---

## Feature 1: Syntax Highlighting

### Architecture

Custom `NSTextStorage` subclass (`SyntaxTextStorage`) that re-highlights on every edit, debounced at 0.15s.

```
SyntaxTextStorage: NSTextStorage
  └── var language: SyntaxLanguage
  └── var isDark: Bool  (synced from applyTheme)
  └── highlight()  — full-document regex pass
  └── processEditing()  — schedules debounced highlight

SyntaxLanguage: enum
  .none | .json | .html | .css | .javascript
  + static func detect(from url: URL) -> SyntaxLanguage

EditorView
  └── setup() builds: SyntaxTextStorage → NSLayoutManager → NSTextContainer → EditorTextView
  └── func setLanguage(_ lang: SyntaxLanguage)
  └── func setHighlightDark(_ isDark: Bool)  (called from applyTheme)
```

### Language Detection (file extension)

| Extension | Language |
|---|---|
| `.json` | `.json` |
| `.html`, `.htm` | `.html` |
| `.css` | `.css` |
| `.js`, `.mjs`, `.cjs`, `.ts`, `.tsx`, `.jsx` | `.javascript` |
| everything else | `.none` (no highlighting) |

### Token Rules per Language

**JSON**
- JSON keys (string before `:`): `"[^"\\]*(?:\\.[^"\\]*)*"(?=\s*:)`
- Strings (values): `"[^"\\]*(?:\\.[^"\\]*)*"`
- Numbers: `-?\b\d+\.?\d*([eE][+-]?\d+)?\b`
- Keywords: `\b(true|false|null)\b`
- Punctuation: `[{}\[\]:,]`

**HTML**
- Comments: `<!--[\s\S]*?-->`
- Doctype: `<!DOCTYPE[^>]*>`
- Tags: `</?[\w:-]+`
- Attribute names: `\b[\w:-]+(?=\s*=)`
- Attribute values: `"[^"]*"|'[^']*'`
- Tag close: `/?>`

**CSS**
- Comments: `\/\*[\s\S]*?\*\/`
- At-rules: `@[\w-]+`
- Selectors: `[^{};]+(?=\s*\{)`
- Property names: `[\w-]+(?=\s*:)`
- Colors: `#[0-9a-fA-F]{3,8}\b`
- Numbers+units: `\b\d+\.?\d*(%|px|em|rem|vh|vw|pt|s|ms)?\b`
- Strings: `"[^"]*"|'[^']*'`

**JavaScript**
- Block comments: `\/\*[\s\S]*?\*\/`
- Line comments: `\/\/[^\n]*`
- Template literals: `` `[^`]*` ``
- Strings: `"[^"\\]*(?:\\.[^"\\]*)*"|'[^'\\]*(?:\\.[^'\\]*)*'`
- Numbers: `\b\d+\.?\d*\b`
- Keywords: `\b(const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|this|class|extends|import|export|default|from|async|await|typeof|instanceof|null|undefined|true|false)\b`
- Function calls: `\b[\w$]+(?=\s*\()`

### Color Palette

| Token | Dark | Light |
|---|---|---|
| Keywords | `#569CD6` | `#0000FF` |
| Strings | `#CE9178` | `#A31515` |
| Numbers | `#B5CEA8` | `#098658` |
| Comments | `#6A9955` | `#008000` |
| JSON keys | `#9CDCFE` | `#001080` |
| HTML tags | `#4EC9B0` | `#800000` |
| HTML attr names | `#9CDCFE` | `#E50000` |
| HTML attr values | `#CE9178` | `#A31515` |
| CSS selectors | `#D7BA7D` | `#800000` |
| CSS properties | `#9CDCFE` | `#FF0000` |
| CSS at-rules | `#C586C0` | `#AF00DB` |
| JS function calls | `#DCDCAA` | `#795E26` |
| Punctuation | `#808080` | `#555555` |

### Integration Points

- `EditorView.setup()` — build custom text storage stack
- `AppDelegate.openEditorFile()` — call `setLanguage(SyntaxLanguage.detect(from: url))` after loading content
- `AppDelegate.createEditorTab(url:)` — same, if URL provided
- `AppDelegate.restoreSession()` — same, for saved editor URLs
- `applyTheme(_:)` / `EditorView.applyColors(bg:fg:)` — call `setHighlightDark(isDark)` + re-highlight
- `EditorView.setHighlightDark(_:)` — updates storage isDark flag, re-triggers highlight

---

## Feature 2: File Drop onto Tab Header

### Architecture

`HeaderBarView` adopts `NSDraggingDestination`.

```
HeaderBarView
  └── registerForDraggedTypes([.fileURL])  in init
  └── draggingEntered() → accept if fileURL, set dropHighlight = true
  └── draggingExited()  → dropHighlight = false
  └── performDragOperation() → extract URL, call onFileDropped?(url)
  └── var onFileDropped: ((URL) -> Void)?  (new callback)
  └── private var dropHighlight: Bool  → draw subtle overlay in draw(_:)
```

Visual feedback: subtle blue tint overlay (`NSColor.controlAccentColor` at 15% alpha) drawn over the entire HeaderBarView while a file is hovering.

### Constraints

- Only accepts file URLs (not folders, not plain text)
- Does not interfere with existing tab-reorder drag (which uses internal drag source)
- `onFileDropped` is wired in AppDelegate to: `createEditorTab(url: url)`

### AppDelegate wiring

```swift
headerView.onFileDropped = { [weak self] url in
    self?.createEditorTab(url: url)
}
```

`createEditorTab(url:)` needs a new optional `url` parameter:
- Loads file content into textView
- Sets tab name to `url.lastPathComponent`
- Sets `tabEditorURLs[i] = url`
- Calls `editorView.setLanguage(SyntaxLanguage.detect(from: url))`

---

## What Does NOT Change

- Undo/redo — NSTextStorage subclass preserves it naturally
- Existing tab-reorder drag — separate internal drag type, no conflict
- Terminal tabs — unaffected
- Vim/Nano modes — unaffected
- Session save/restore — editorURL already saved; language re-detected on restore

---

## Files Changed

- `quickTerminal.swift` — all changes (single-file project)
- `CHANGELOG.md` — document new features
- `tests.swift` — add tests for `SyntaxLanguage.detect(from:)` and basic highlight pass
