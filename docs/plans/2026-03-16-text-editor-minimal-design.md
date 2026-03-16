# Text Editor Tab — Minimal Design

**Date:** 2026-03-16
**Status:** Approved

## Goal

Add a minimal, stable text editor tab to quickTerminal. No subclassing, no complex storage — just native AppKit components wired together cleanly. Start minimal, extend iteratively.

## Architecture

### `EditorView: NSView`

Single class, ~100–120 lines. Contains:
- `NSScrollView` filling the entire view
- Standard `NSTextView` (no subclassing)
  - `isRichText = false`
  - `isAutomaticSpellCheckingEnabled = false`
  - `font`: SF Mono, matches terminal font size
  - Background/foreground colors synced to active theme
- `layout()` override syncs frames on resize

### Tab System Integration

Minimal changes to `AppDelegate`:
- `TabType` enum: `.terminal | .editor`
- `tabTypes: [TabType]` — parallel to existing tab arrays
- `tabEditorViews: [EditorView?]` — nil for terminal tabs
- `createEditorTab()` — appends new editor tab, shows EditorView
- `updateHeaderTabs()` — renders tab label "Editor" for editor tabs
- `updateFooter()` — hides footer for editor tabs

### HeaderBar

- Long-press on `+` button → dropdown: "Terminal" / "Text Editor"
- No other HeaderBar changes

### Theme Sync

`applyTheme(_ t: TerminalTheme)` sets `EditorView.backgroundColor` and `EditorView.textColor` to match terminal theme.

## Explicitly Out of Scope (v1)

- File open / save
- Syntax highlighting
- Line numbers / gutter
- Search / replace
- Code folding
- Dirty state indicator

## Iterative Roadmap (future)

1. Cmd+S / Cmd+O (file I/O)
2. Line numbers (GutterView)
3. Syntax highlighting (then: NSTextStorage subclass)
4. Search panel (Cmd+F)

## Key Constraints

- No NSTextStorage / NSLayoutManager subclassing in v1
- NSTextView must use correct frame + textContainer setup if ever needed
- Keep EditorView self-contained — no cross-dependencies
