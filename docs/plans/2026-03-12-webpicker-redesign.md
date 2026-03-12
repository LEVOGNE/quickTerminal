# WebPicker Redesign — Design Doc
Date: 2026-03-12

## Ziel
Den HTML Picker umbenennen zu **WebPicker**, ein Connect/Disconnect-Toggle einbauen, und das gesamte UI polieren.

## Name
- Überall: "HTML Picker" → "WebPicker"
- Header-Button im quickBAR / Footer-Button bleibt `</>`
- `kAppVersion` bleibt unverändert

## Größe
Kompakt: ~180px Höhe (unverändert), Breite richtet sich nach Sidebar.

## States & UI

### State: Disconnected
```
┌─────────────────────────────────┐
│  ◈  WebPicker          [✕]      │  ← Header 28px, Trennlinie mit teal Akzent
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│  ○  Nicht verbunden             │  ← grauer Dot
│                                 │
│  [  ⊕  Connect                ] │  ← Haupt-Button, teal, voll breit
│                                 │
│                                 │
└─────────────────────────────────┘
```

### State: Connecting
```
│  ◉  Verbinde...                 │  ← oranger pulsierender Dot
│  [  ⊕  Connect  (disabled)    ] │
```

### State: Navigating (about:blank geöffnet, noch keine Webseite)
```
│  ●  Navigiere zur Webseite      │  ← oranger Dot
│  [🎯  Element wählen (disabled)] │
│  [ ⏏  Disconnect              ] │
```

### State: Ready (verbunden mit echter Webseite)
```
│  ●  github.com                  │  ← grüner Dot + Tab-Titel (kein URL-Pfad, nur Hostname)
│  [🎯  Element wählen          ] │  ← teal Akzentfarbe, aktiv
│  [ ⏏  Disconnect              ] │  ← kleiner sekundärer Button
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│  <div class="hero">...          │  ← Monospace Preview 3 Zeilen
```

### State: Picking (nach Klick auf "Element wählen")
```
│  ●  github.com                  │
│  [⏳  Warte auf Klick...      ] │  ← disabled, gedimmt
│  [ ⏏  Disconnect              ] │
```

### State: Picked (nach erfolgreicher Auswahl)
```
│  ●  github.com                  │
│  [🎯  Element wählen          ] │  ← wieder aktiv
│  [ ⏏  Disconnect              ] │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│  ✓ Kopiert!                     │  ← 2s grünes Feedback
│  <div class="hero">...          │
```

## Farben / Visual
- **Akzentfarbe (teal)**: `#3DC9A0` / `NSColor(calibratedRed: 0.24, green: 0.79, blue: 0.63, alpha: 1.0)`
- **Pick-Button**: teal Hintergrund (0.15 alpha), teal Text/Rand
- **Connect-Button**: teal Hintergrund (0.15 alpha), teal Text/Rand
- **Disconnect-Button**: kleiner, sekundär — weiß 0.35 alpha, kein Hintergrund
- **Status-Dot**: 8px rund — grau (disconnected), orange (connecting/navigating), grün (ready)
- **Header-Trennlinie**: teal, 1px, 0.4 alpha (statt weißgrau)
- **Background**: `calibratedWhite: 0.07` (unverändert)
- **Tab-Titel**: hostname aus Tab-URL extrahieren (z.B. `github.com` aus `https://github.com/foo`)

## Connect / Disconnect Verhalten
- **Connect**: `connect()` aufrufen — startet Chrome falls nötig, öffnet Tab via `/json/new`, verbindet WebSocket
- **Disconnect**:
  1. Picker-JS cleanup evaluieren
  2. `Target.closeTarget` via CDP senden (schließt den Tab in Chrome)
  3. WebSocket trennen
  4. State → Disconnected

### Target.closeTarget CDP Call
```swift
// In ChromeCDPClient — neuer Method:
func closeTab(targetId: String, completion: @escaping () -> Void) {
    // Sends Target.closeTarget via existing WebSocket
    // Falls back to just disconnect() if WebSocket is gone
}
```
- `targetId` wird aus wsURL extrahiert: letztes Pfad-Segment von `ws://localhost:9222/devtools/page/{targetId}`
- Muss in `HTMLPickerSidebarView` als `private var currentTargetId: String?` gespeichert werden

## Tab-Titel im Status
Nach erfolgreichem Connect: Tab-URL aus `/json/list` holen, Hostname extrahieren.
- `https://github.com/foo/bar` → `github.com`
- `about:blank` → `Navigiere zur Webseite` (orange)
- Polling: Tab-Titel jede 3s aktualisieren (falls User navigiert)

## Umbenennung
- `HTMLPickerSidebarView` → `WebPickerSidebarView`
- `HTMLPickerPanel` bleibt (floating panel, selten genutzt)
- `htmlPickerSidebarView` in AppDelegate → `webPickerSidebarView`
- Header-Button `onHTMLPickerToggle` → `onWebPickerToggle`
- `setHTMLPickerActive` → `setWebPickerActive`
- `htmlPickerRightDivider` → `webPickerRightDivider`
- `toggleHTMLPicker` → `toggleWebPicker`

## Neue Dateien / Code-Abschnitte
- `// MARK: - WebPicker Sidebar View` ersetzt `// MARK: - HTML Picker Sidebar View`
- Alle Änderungen in `quickTerminal.swift`
