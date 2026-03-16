# Minimal Text Editor Tab — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a minimal, stable text editor tab using a plain NSTextView — no subclassing, no syntax highlighting, no file I/O. Just open an editor tab, type text.

**Architecture:** Add `TabType` enum + `tabEditorViews: [EditorView?]` parallel array. Change `termViews` from `[TerminalView]` to `[TerminalView?]` so editor tabs can store nil. All tab-management functions are updated to skip TerminalView operations when the active tab is an editor tab.

**Tech Stack:** Swift, Cocoa/AppKit — no external dependencies.

---

### Task 1: Add `TabType` enum

**Files:**
- Modify: `quickTerminal.swift` — insert just before `// MARK: - App Delegate` (line 14220)

**Step 1: Insert enum**

Find the line `// MARK: - App Delegate` (line 14220) and insert BEFORE it:

```swift
// MARK: - Tab Types

enum TabType {
    case terminal
    case editor
}
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Build succeeds, all tests pass.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add TabType enum (terminal/editor)"
```

---

### Task 2: Change `termViews` to optional + add editor arrays

**Files:**
- Modify: `quickTerminal.swift` — AppDelegate properties (around line 14224)

**Step 1: Change property types**

Find (line 14224):
```swift
var termViews: [TerminalView] = []
```
Replace with:
```swift
var termViews: [TerminalView?] = []
var tabTypes: [TabType] = []
var tabEditorViews: [EditorView?] = []
```

**Step 2: Build — fix compiler errors one by one**

```bash
bash build.sh
```

The compiler will flag every place that force-unwraps `termViews[i]` (now `TerminalView?`). For each error, apply the appropriate guard:

- `updateHeaderTabs()` (line ~15389) — skip title lookup if nil:
  ```swift
  let titles = (0..<termViews.count).map { i -> String in
      if tabTypes.indices.contains(i), tabTypes[i] == .editor { return "Editor" }
      if let tv = termViews[i], let custom = tabCustomNames.indices.contains(i) ? tabCustomNames[i] : nil { return custom }
      if let tv = termViews[i] {
          let pid = tv.childPid
          if pid > 0 {
              let cwd = cwdForPid(pid)
              return cwd == home ? "~" : (cwd as NSString).lastPathComponent
          }
      }
      return "~"
  }
  ```

- `updateFooter()` (line ~15407) — hide footer for editor tabs:
  ```swift
  func updateFooter() {
      guard !termViews.isEmpty && activeTab < termViews.count else { return }
      if activeTab < tabTypes.count, tabTypes[activeTab] == .editor {
          footerView.isHidden = true
          return
      }
      footerView.isHidden = false
      guard let tv = termViews[activeTab] else { return }
      // ... rest of existing code unchanged (replace termViews[activeTab] with tv)
  }
  ```

- `switchToTab()` (line ~15361) — focus editor view instead:
  ```swift
  if activeTab < tabTypes.count, tabTypes[activeTab] == .editor {
      window.makeFirstResponder(tabEditorViews[activeTab]?.textView)
  } else {
      if let tv = termViews[activeTab] { window.makeFirstResponder(tv) }
  }
  ```

- `closeTab()` (line ~14748) — guard on optional:
  ```swift
  termViews[index]?.onShellExit = nil   // silence any callbacks
  termViews.remove(at: index)
  tabTypes.remove(at: index)
  tabEditorViews.remove(at: index)
  ```

- `closeTab()` line ~14801 — guard:
  ```swift
  if activeTab >= 0 && activeTab < termViews.count {
      if let tv = termViews[activeTab] { window.makeFirstResponder(tv) }
  }
  ```

- `createTab()` (line ~14725-14730) — append matching entries:
  After `termViews.append(tv)` add:
  ```swift
  tabTypes.append(.terminal)
  tabEditorViews.append(nil)
  ```

**Step 3: Build until clean**

```bash
bash build.sh
```
Expected: Build succeeds, all tests pass.

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: make termViews optional, add tabTypes/tabEditorViews arrays"
```

---

### Task 3: Add `EditorView` class

**Files:**
- Modify: `quickTerminal.swift` — insert BEFORE `// MARK: - Tab Types` (which you just added above Task 1's enum)

**Step 1: Insert `EditorView` class**

Insert the following ~80-line class BEFORE the `// MARK: - Tab Types` block:

```swift
// MARK: - Text Editor

class EditorView: NSView {

    private(set) var textView: NSTextView!
    private var scrollView: NSScrollView!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Scroll view fills the entire EditorView
        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        // Text view — standard NSTextView, no subclassing
        let contentSize = scrollView.contentSize
        textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        // Behaviour
        textView.isRichText = false
        textView.isAutomaticSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true

        // Font — match terminal's monospace font
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Initial colors (dark theme defaults — theme sync updates later)
        applyColors(bg: NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1),
                    fg: NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.90, alpha: 1))

        scrollView.documentView = textView
    }

    func applyColors(bg: NSColor, fg: NSColor) {
        scrollView?.backgroundColor = bg
        textView?.backgroundColor = bg
        textView?.textColor = fg
        textView?.insertionPointColor = fg
    }

    // Keep textView frame in sync with scroll view content size on resize
    override func layout() {
        super.layout()
        let w = scrollView.contentSize.width
        textView.frame = NSRect(x: 0, y: 0, width: w, height: max(textView.frame.height, scrollView.contentSize.height))
        textView.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }
}
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add EditorView class (minimal NSTextView wrapper)"
```

---

### Task 4: Add `createEditorTab()` to AppDelegate

**Files:**
- Modify: `quickTerminal.swift` — insert after `createTab()` function (after line ~14746)

**Step 1: Insert method**

Find the end of `createTab()` (the closing `}` after `saveSession()` near line 14746) and insert after it:

```swift
func createEditorTab() {
    let tf = termFrame()

    // Editor view fills the terminal frame
    let editorView = EditorView(frame: tf)
    editorView.autoresizingMask = [.width, .height]

    // Sync colors to current theme
    let bg = NSColor(cgColor: kDefaultBG) ?? .black
    let fg = NSColor(cgColor: kDefaultFG) ?? .white
    editorView.applyColors(bg: bg, fg: fg)

    // Hide current container
    if !splitContainers.isEmpty && activeTab < splitContainers.count {
        splitContainers[activeTab].isHidden = true
        if activeTab < tabGitPanels.count {
            tabGitPanels[activeTab]?.isHidden = true
            tabGitDividers[activeTab]?.isHidden = true
        }
    }

    // Append parallel-array entries (SplitContainer placeholder keeps indices aligned)
    let placeholder = SplitContainer(frame: tf, primary: TerminalView(frameRect: tf, shell: "/bin/true", cwd: nil, historyId: nil))
    placeholder.isHidden = true  // never shown — editor view is shown directly

    termViews.append(nil)
    tabTypes.append(.editor)
    tabEditorViews.append(editorView)
    splitContainers.append(placeholder)
    tabColors.append(NSColor(calibratedHue: CGFloat.random(in: 0...1), saturation: 0.65, brightness: 0.85, alpha: 1.0))
    tabCustomNames.append("Editor")
    tabGitPositions.append(.none)
    tabGitPanels.append(nil)
    tabGitDividers.append(nil)
    tabGitRatios.append(gitDefaultRatioH)
    tabGitRatiosV.append(gitDefaultRatioV)
    tabGitRatiosH.append(gitDefaultRatioH)

    activeTab = termViews.count - 1

    editorView.alphaValue = 0
    window.contentView?.addSubview(editorView)
    window.makeFirstResponder(editorView.textView)

    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        editorView.animator().alphaValue = 1
    })

    updateHeaderTabs()
    updateFooter()
    saveSession()
}
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Build succeeds.

> **Note:** The placeholder SplitContainer approach avoids making `splitContainers` optional. The TerminalView inside it will immediately `exit(0)` since shell is `/bin/true` — that triggers `onShellExit` which would close the tab. We need to NOT set `onShellExit` on placeholder views. Since we pass `nil` as `historyId` and use `/bin/true`, make sure `onShellExit` is not set (it's only set in `createTab()`, not here). ✓

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add createEditorTab() to AppDelegate"
```

---

### Task 5: Fix `switchToTab()` for editor tabs

**Files:**
- Modify: `quickTerminal.swift` — `switchToTab()` at line ~15326

**Step 1: Update the guard and firstResponder logic**

Find `func switchToTab(_ index: Int)` (line 15326). The current guard:
```swift
guard index >= 0 && index < termViews.count && index != activeTab else { return }
```
is fine — keep it.

Find line ~15361:
```swift
window.makeFirstResponder(termViews[activeTab])
```
Replace with:
```swift
if activeTab < tabTypes.count, tabTypes[activeTab] == .editor {
    window.makeFirstResponder(tabEditorViews[activeTab]?.textView)
} else if let tv = termViews[activeTab] {
    window.makeFirstResponder(tv)
}
```

Also handle showing/hiding the editorView. After the crossfade block (after line ~15350), add:

```swift
// Show/hide editor views
for (i, ev) in tabEditorViews.enumerated() {
    ev?.isHidden = (i != activeTab)
}
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "fix: switchToTab handles editor tabs (firstResponder + view visibility)"
```

---

### Task 6: Fix `closeTab()` for editor tabs

**Files:**
- Modify: `quickTerminal.swift` — `closeTab()` at line ~14748

**Step 1: Remove editor view from superview on close**

Find the beginning of `closeTab()`. After `let container = splitContainers[index]`, add:

```swift
// Remove editor view if this is an editor tab
if index < tabEditorViews.count, let ev = tabEditorViews[index] {
    ev.removeFromSuperview()
}
```

After `splitContainers.remove(at: index)`, add:
```swift
if index < tabTypes.count { tabTypes.remove(at: index) }
if index < tabEditorViews.count { tabEditorViews.remove(at: index) }
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Build succeeds, all tests pass.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "fix: closeTab cleans up editor view + arrays"
```

---

### Task 7: Wire `+` button to open editor tab

**Files:**
- Modify: `quickTerminal.swift` — HeaderBarView setup (line ~14496) and HeaderBarView class

**Step 1: Add `onAddEditorTab` callback to HeaderBarView**

In `HeaderBarView` class properties (around line 5358), add:
```swift
var onAddEditorTab: (() -> Void)?
```

**Step 2: Change addBtn to show a menu on click**

Find `addBtn.onClick` (line ~5418):
```swift
addBtn.onClick = { [weak self] in self?.onAddTab?() }
```
Replace with:
```swift
addBtn.onClick = { [weak self] in
    guard let self = self, let btn = self.addBtn else { return }
    let menu = NSMenu()
    menu.addItem(withTitle: "Terminal", action: nil, keyEquivalent: "")
    menu.addItem(withTitle: "Text Editor", action: nil, keyEquivalent: "")
    menu.item(at: 0)?.target = self
    menu.item(at: 0)?.action = #selector(HeaderBarView._addTerminal)
    menu.item(at: 1)?.target = self
    menu.item(at: 1)?.action = #selector(HeaderBarView._addEditor)
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.height + 4), in: btn)
}
```

Add these two `@objc` methods inside `HeaderBarView`:
```swift
@objc private func _addTerminal() { onAddTab?() }
@objc private func _addEditor()   { onAddEditorTab?() }
```

**Step 3: Wire callback in AppDelegate** (line ~14496)

After:
```swift
headerView.onAddTab = { [weak self] in self?.addTab() }
```
Add:
```swift
headerView.onAddEditorTab = { [weak self] in self?.createEditorTab() }
```

**Step 4: Build**

```bash
bash build.sh
```
Expected: Build succeeds.

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: + button shows Terminal/Text Editor menu"
```

---

### Task 8: Sync theme colors to editor views

**Files:**
- Modify: `quickTerminal.swift` — `applyTheme()` at line ~1012

**Step 1: Find applyTheme and add editor sync at the end**

Find `func applyTheme(_ t: TerminalTheme)` (line 1012). At the **end** of the function, after all existing lines, add:

```swift
// Sync editor views to new theme
if let delegate = NSApp.delegate as? AppDelegate {
    let bg = NSColor(cgColor: kDefaultBG) ?? .black
    let fg = NSColor(cgColor: kDefaultFG) ?? .white
    for ev in delegate.tabEditorViews.compactMap({ $0 }) {
        ev.applyColors(bg: bg, fg: fg)
    }
}
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Build succeeds, all tests pass.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: applyTheme syncs colors to all open editor views"
```

---

### Task 9: Final smoke test

**Step 1: Build the app bundle**

```bash
bash build_app.sh
```
Expected: `quickTerminal.app` created without errors.

**Step 2: Manual test checklist**

Open the built app and verify:
- [ ] Click `+` button → dropdown shows "Terminal" and "Text Editor"
- [ ] Click "Terminal" → new terminal tab opens normally
- [ ] Click "Text Editor" → new editor tab opens with label "Editor"
- [ ] Can type text in editor tab
- [ ] Switching between tabs with Ctrl+1/2/etc. works
- [ ] Footer hides when editor tab is active
- [ ] Closing an editor tab works, remaining tabs are accessible
- [ ] Changing theme (Settings) updates editor background/text color

**Step 3: Commit if all good**

```bash
git add quickTerminal.swift
git commit -m "feat: minimal text editor tab — working v1"
```
