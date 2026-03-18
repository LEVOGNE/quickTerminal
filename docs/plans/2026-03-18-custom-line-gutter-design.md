# Design: Custom LineGutterView

**Datum**: 2026-03-18
**Status**: Approved

## Ziel

Eigene Zeilennummer-Leiste im Text-Editor Tab, ohne NSRulerView oder andere System-Frameworks. Volle Kontrolle über Layout, Farben und Font.

## Layout

```
EditorView (isFlipped: true)
├── LineGutterView   x=0,  width=44,  y=modeBarH..bottom
├── NSScrollView     x=44, width-44,  y=modeBarH..bottom
└── modeBar          x=0,  height=26, y=0 (unverändert)
```

`EditorView` bekommt ein `layout()` Override das beide Views (Gutter + ScrollView) synchron hält wenn das Fenster resized wird.

## Komponenten

### `LineGutterView: NSView`

- `isFlipped: true` (konsistent mit EditorView)
- Properties: `bgColor`, `numColor`, `sepColor` (von `applyColors()` gesetzt)
- Schwache Referenz auf `textView` und `scrollView` für Layout-Manager-Zugriff

### Drawing (`draw(_ dirtyRect:)`)

1. Hintergrund füllen (`bgColor.setFill(); rect.fill()`)
2. 1px rechte Trennlinie zeichnen (`sepColor`)
3. Sichtbaren Glyph-Range aus `scrollView.contentView.bounds` ermitteln via `NSLayoutManager.glyphRange(forBoundingRect:in:)`
4. Durch alle Zeilen-Fragmente iterieren — nur erstes Fragment pro Absatz bekommt eine Nummer (geprüft via Zeichen vor dem Fragment)
5. Koordinate via `convert(lineRect.origin, from: textView)` in eigenen Koordinatenraum umrechnen
6. Nummer rechts-bündig mit 8px Padding: `NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)`
7. Edge-case: leeres Dokument → "1" oben zeichnen

## Sync (Scroll & Text)

Zwei NotificationCenter Observer auf `LineGutterView`:
- `NSText.didChangeNotification` (object: textView) → `needsDisplay = true`
- `NSView.boundsDidChangeNotification` (object: scrollView.contentView) → `needsDisplay = true`

## Farben

| Token  | Dark                        | Light                       |
|--------|-----------------------------|-----------------------------|
| bg     | calibratedWhite 0.06 α 1.0  | calibratedWhite 0.88 α 1.0  |
| num    | calibratedWhite 0.35 α 1.0  | calibratedWhite 0.45 α 1.0  |
| sep    | white α 0.08                | black α 0.08                |

Farben werden via `applyColors(isDark:bg:)` auf `LineGutterView` gesetzt — aufgerufen aus `EditorView.applyColors()`.

## Änderungen an EditorView

- Neue Property: `private var lineGutter: LineGutterView`
- `setup()`: Gutter vor ScrollView erstellen und hinzufügen; ScrollView x=44 setzen
- `layout()` Override: Gutter-Frame und ScrollView-Frame synchron halten
- `applyColors()`: `lineGutter.applyColors(isDark:bg:)` aufrufen

## Was NICHT geändert wird

- NSRulerView / NSScrollView ruler APIs — nicht verwendet
- textContainerInset — bleibt unverändert
- modeBar — unverändert
- SyntaxTextStorage / NSLayoutManager — nur gelesen, nicht verändert
