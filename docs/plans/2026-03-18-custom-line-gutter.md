# Custom LineGutterView Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eigene Zeilennummer-Leiste (44px breit, links vom ScrollView) im Text-Editor Tab, gebaut als reiner NSView ohne NSRulerView.

**Architecture:** `LineGutterView: NSView` sitzt als Geschwister neben `NSScrollView` in `EditorView`. Das existierende `layout()` Override in `EditorView` wird angepasst, um beide synchron zu halten. Drawing erfolgt in `draw(_ dirtyRect:)` via NSLayoutManager-Abfrage + direktem `NSString.draw(at:)`.

**Tech Stack:** Swift, AppKit, NSLayoutManager (nur lesend), NotificationCenter

---

### Task 1: `LineGutterView` Klasse schreiben

**Files:**
- Modify: `quickTerminal.swift` — direkt oberhalb von `class EditorView` (Zeile ~15750), nach dem `// ---------------------------------------------------------------------------` Separator

**Kontext:** Die Klasse bekommt schwache Referenzen auf `textView` und `scrollView`, die `EditorView` nach dem Setup setzt.

**Step 1: Klasse einfügen**

Füge folgenden Block direkt vor `class EditorView: NSView {` ein (nach dem `// ---------------------------------------------------------------------------` Separator):

```swift
class LineGutterView: NSView {

    override var isFlipped: Bool { true }

    var bgColor:  NSColor = NSColor(calibratedWhite: 0.06, alpha: 1.0)
    var numColor: NSColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
    var sepColor: NSColor = NSColor(calibratedWhite: 1.0,  alpha: 0.08)

    weak var textView:  NSTextView?
    weak var scrollView: NSScrollView?

    func applyColors(isDark: Bool, bg: NSColor) {
        if isDark {
            bgColor  = NSColor(calibratedWhite: 0.06, alpha: 1.0)
            numColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
            sepColor = NSColor(calibratedWhite: 1.0,  alpha: 0.08)
        } else {
            bgColor  = NSColor(calibratedWhite: 0.88, alpha: 1.0)
            numColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
            sepColor = NSColor(calibratedWhite: 0.0,  alpha: 0.08)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer,
              let sv = scrollView else {
            bgColor.setFill(); dirtyRect.fill(); return
        }

        // Background
        bgColor.setFill()
        bounds.fill()

        // Right separator (1 px)
        sepColor.setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        let str = tv.string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: numColor,
        ]

        if str.length == 0 {
            // Empty doc — always show "1"
            let label = "1" as NSString
            let sz = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: bounds.width - sz.width - 8, y: 4), withAttributes: attrs)
            return
        }

        // Visible rect in textView coordinates
        let docVisible = sv.documentVisibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: docVisible, in: tc)
        let charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Which line number starts at the top of the visible area?
        var lineNum = 1
        if charRange.location > 0 {
            lineNum = str.substring(to: charRange.location)
                         .components(separatedBy: "\n").count
        }

        var glyphIdx = glyphRange.location
        let glyphEnd = NSMaxRange(glyphRange)

        while glyphIdx < glyphEnd {
            var fragRange = NSRange(location: NSNotFound, length: 0)
            let lineRect  = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &fragRange)
            guard fragRange.location != NSNotFound, fragRange.length > 0 else { break }

            // Only first fragment of each paragraph gets a number
            let isFirst: Bool = {
                guard glyphIdx > glyphRange.location else { return true }
                let charIdx = lm.characterIndexForGlyph(at: glyphIdx)
                return charIdx == 0 || str.character(at: charIdx - 1) == 10  // '\n'
            }()

            if isFirst {
                // Convert textView coordinate → gutter coordinate
                let origin = convert(lineRect.origin, from: tv)
                let label  = "\(lineNum)" as NSString
                let sz     = label.size(withAttributes: attrs)
                let x      = bounds.width - sz.width - 8   // right-aligned, 8 px padding
                let y      = origin.y + (lineRect.height - sz.height) / 2
                label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                lineNum += 1
            }

            let next = NSMaxRange(fragRange)
            if next <= glyphIdx { break }
            glyphIdx = next
        }
    }
}

// ---------------------------------------------------------------------------
```

**Step 2: Bauen und prüfen**

```bash
bash build.sh 2>&1 | tail -10
```
Erwartetes Ergebnis: Kompiliert, alle Tests grün. Die Klasse wird noch nirgends benutzt, also kein sichtbarer Effekt.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add LineGutterView class (not yet wired)"
```

---

### Task 2: `EditorView` verdrahten

**Files:**
- Modify: `quickTerminal.swift` — `EditorView` class (Zeile ~15750 nach Task 1)

**Step 1: Property hinzufügen**

In `class EditorView: NSView {` — direkt nach `private var scrollView: NSScrollView!`:

```swift
private var lineGutter: LineGutterView!
```

**Step 2: Gutter in `setup()` erstellen**

In `setup()`, **vor** der Zeile `scrollView = NSScrollView(...)`, füge ein:

```swift
let gutterW: CGFloat = 44
```

Ändere dann die `scrollView`-Init-Zeile von:

```swift
scrollView = NSScrollView(frame: NSRect(x: 0, y: modeBarH, width: bounds.width,
                                        height: max(0, bounds.height - modeBarH)))
```

zu:

```swift
scrollView = NSScrollView(frame: NSRect(x: gutterW, y: modeBarH,
                                        width: max(0, bounds.width - gutterW),
                                        height: max(0, bounds.height - modeBarH)))
```

Dann — direkt **nach** `scrollView.documentView = textView` und **vor** `// Mode bar`:

```swift
        // Line number gutter — custom NSView, left of scrollView
        lineGutter = LineGutterView(frame: NSRect(x: 0, y: modeBarH,
                                                   width: gutterW,
                                                   height: max(0, bounds.height - modeBarH)))
        lineGutter.textView  = textView
        lineGutter.scrollView = scrollView
        addSubview(lineGutter)

        // Redraw gutter on text change
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification,
                                               object: textView,
                                               queue: .main) { [weak self] _ in
            self?.lineGutter?.needsDisplay = true
        }
        // Redraw gutter on scroll
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView,
                                               queue: .main) { [weak self] _ in
            self?.lineGutter?.needsDisplay = true
        }
```

**Step 3: `layout()` anpassen**

Das existierende `layout()` Override sieht so aus:

```swift
    override func layout() {
        super.layout()
        guard let sv = scrollView, let tv = textView, let mb = modeBar else { return }
        let modeBarH: CGFloat = mb.isHidden ? 0 : 26
        // Resize scrollView: top of view down to above modeBar
        sv.frame = NSRect(x: 0, y: modeBarH, width: bounds.width,
                          height: max(0, bounds.height - modeBarH))
        mb.frame.size.width = bounds.width
        let w = sv.contentSize.width
        tv.frame = NSRect(x: 0, y: 0, width: w,
                          height: max(tv.frame.height, sv.contentSize.height))
        tv.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }
```

Ersetze es durch:

```swift
    override func layout() {
        super.layout()
        guard let sv = scrollView, let tv = textView, let mb = modeBar else { return }
        let modeBarH: CGFloat = mb.isHidden ? 0 : 26
        let gutterW:  CGFloat = 44
        let availH = max(0, bounds.height - modeBarH)

        // Gutter: left strip
        lineGutter?.frame = NSRect(x: 0, y: modeBarH, width: gutterW, height: availH)

        // ScrollView: remainder to the right
        sv.frame = NSRect(x: gutterW, y: modeBarH,
                          width: max(0, bounds.width - gutterW),
                          height: availH)
        mb.frame.size.width = bounds.width
        let w = sv.contentSize.width
        tv.frame = NSRect(x: 0, y: 0, width: w,
                          height: max(tv.frame.height, sv.contentSize.height))
        tv.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }
```

**Step 4: `applyColors()` erweitern**

Am Ende von `applyColors(bg:fg:)`, nach `syntaxStorage?.baseFG = fg`:

```swift
        let isDark = bg.brightnessComponent < 0.5
        lineGutter?.applyColors(isDark: isDark, bg: bg)
```

Achtung: `isDark` ist in `applyColors` bereits berechnet — einfach die vorhandene Zeile nutzen.

**Step 5: Bauen und visuell prüfen**

```bash
bash build.sh 2>&1 | tail -10
```

Dann App starten, einen Editor-Tab öffnen: Links sollte jetzt eine 44px breite Leiste mit Zeilennummern sichtbar sein. Text scrollt synchron.

**Step 6: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: wire LineGutterView into EditorView"
```

---

### Task 3: Theme-Sync prüfen und feintunen

**Files:**
- Modify: `quickTerminal.swift` (nur wenn Farben nach Theme-Wechsel nicht stimmen)

**Step 1: Theme-Wechsel testen**

Settings öffnen → Theme wechseln (Dark → Light → OLED → System). Gutter-Farben müssen sich sofort anpassen.

**Wenn Farben nicht stimmen:** Prüfen, ob `applyTheme(_:)` die globale Funktion `applyColors` auf `EditorView` aufruft. Suche in `quickTerminal.swift`:

```bash
grep -n "applyColors\|applyTheme" quickTerminal.swift | grep -i "editor\|EditorView" | head -20
```

Sicherstellen, dass der Pfad `applyTheme → EditorView.applyColors → lineGutter.applyColors` lückenlos ist.

**Step 2: Commit falls Fixes nötig**

```bash
git add quickTerminal.swift
git commit -m "fix: gutter theme sync"
```

---

### Task 4: Abschluss

**Step 1: Finalen Build + alle Tests**

```bash
bash build.sh 2>&1 | tail -15
```

Erwartetes Ergebnis: Alle 197+ Tests grün.

**Step 2: Final Commit**

Wenn alles sauber ist und kein offener Dirty State:

```bash
git status
```

Falls noch uncommitted changes:

```bash
git add quickTerminal.swift
git commit -m "feat: custom line number gutter in editor tab"
```
