# HTML Picker — Design Doc
Date: 2026-03-12

## Ziel
Ein schwebender Element-Picker der via Chrome DevTools Protocol (CDP) ein beliebiges DOM-Element auf einer Webseite anklickt, das `outerHTML` extrahiert, ins Clipboard kopiert und automatisch in die aktive CLI (Claude Code, zsh, fish, etc.) einfügt.

## Aktivierung
- quickBAR-Befehl: `HTML Picker`
- Footer-Button: kleines Icon links unten

## Ablauf (5 Schritte)

```
[1] User aktiviert HTML Picker
[2] quickTerminal prüft: Chrome mit --remote-debugging-port=9222?
      Nein → open -a "Google Chrome" --args --remote-debugging-port=9222
      Ja   → direkt verbinden
[3] HTMLPickerPanel erscheint (schwebendes NSPanel)
[4] User klickt "Element wählen" → Picker-JS wird via CDP injiziert
      → Elemente leuchten beim Hover auf (blauer Rahmen wie DevTools)
[5] User klickt Element im Browser
      → outerHTML sofort ins Clipboard + automatisch Cmd+V ins Terminal
      → Vorschau im Panel, "✓ Eingefügt!" Feedback für 2s
      → Panel bleibt offen für "Neu wählen"
```

## HTMLPickerPanel UI

```
┌─────────────────────────────────┐
│  🔵 Chrome verbunden            │  ← Status-Dot + Text
│                                 │
│  [ 🎯 Element wählen ]          │  ← Button, aktiviert Picker
│                                 │
│  ┌─ Vorschau ─────────────────┐ │
│  │ <div class="hero">         │ │  ← erste ~150 Zeichen outerHTML
│  │   <h1>Mein Titel</h...     │ │
│  └────────────────────────────┘ │
│                                 │
│  ✓ Eingefügt!                   │  ← 2s Feedback, dann weg
└─────────────────────────────────┘
```

- `NSPanel` mit `.nonactivatingPanel` (Terminal verliert Fokus nicht)
- Immer im Vordergrund (`level = .floating`)
- `✕` schließt Panel + deaktiviert Picker-JS

## Technische Komponenten

### ChromeCDPClient
- HTTP GET `http://localhost:9222/json` → prüft ob Chrome im Debug-Modus läuft
- HTTP GET `http://localhost:9222/json/list` → aktiven Tab (erster `"page"` Typ) holen
- `URLSessionWebSocketTask` → WebSocket zu `ws://localhost:9222/devtools/page/{targetId}`
- CDP Nachrichten: `Runtime.evaluate` für JS-Injection + Polling

### Chrome Auto-Start
```swift
// Falls CDP nicht erreichbar:
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
proc.arguments = ["-a", "Google Chrome", "--args", "--remote-debugging-port=9222"]
try? proc.run()
// 1.5s warten, dann reconnect
```

### Picker-JavaScript (injiziert via CDP)
```javascript
(function() {
  let last = null;
  function over(e) {
    if (last) last.style.outline = '';
    last = e.target;
    last.style.outline = '2px solid #4A90D9';
    last.style.outlineOffset = '-2px';
  }
  function out(e) {
    if (e.target === last) e.target.style.outline = '';
  }
  function pick(e) {
    e.preventDefault(); e.stopPropagation();
    if (last) last.style.outline = '';
    window.__qtPickedHTML = e.target.outerHTML;
    document.removeEventListener('mouseover', over, true);
    document.removeEventListener('mouseout', out, true);
    document.removeEventListener('click', pick, true);
  }
  document.addEventListener('mouseover', over, true);
  document.addEventListener('mouseout', out, true);
  document.addEventListener('click', pick, true);
})();
```

### Polling + Extraction
- Alle 300ms: `Runtime.evaluate { window.__qtPickedHTML }`
- Sobald nicht-null → HTML extrahiert → Clipboard → Auto-Paste

### Auto-Paste (CGEvent)
```swift
NSPasteboard.general.setString(html, forType: .string)
// Cmd+V an zuletzt aktives Fenster (vor Panel-Öffnung gespeichert)
let src = CGEventSource(stateID: .hidSystemState)
let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
vDown?.flags = .maskCommand
vUp?.flags   = .maskCommand
vDown?.post(tap: .cghidEventTap)
vUp?.post(tap: .cghidEventTap)
```

## Safari-Option (Settings)
- Toggle in Settings: "Browser: Chrome / Safari"
- Safari braucht: Entwickler-Menü aktiviert + Web Inspector erlauben
- Beim ersten Wechsel auf Safari: einmalige Anleitung anzeigen
- Gleicher Ablauf, aber Verbindungsdetails via Safari Web Inspector Protocol

## Neue Einstellungen
- `htmlPickerBrowser`: "chrome" (default) / "safari"

## Neue Dateien / Code-Abschnitte in quickTerminal.swift
- `// MARK: - Chrome CDP Client` — WebSocket + CDP-Protokoll
- `// MARK: - HTML Picker Panel` — NSPanel + UI
- quickBAR: neuer Eintrag `HTML Picker`
- Footer: neuer kleiner Button
- AppDelegate: `htmlPickerPanel: HTMLPickerPanel?`
