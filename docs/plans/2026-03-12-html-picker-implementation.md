# HTML Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ein schwebender Element-Picker der via Chrome DevTools Protocol ein DOM-Element anklickt, das outerHTML extrahiert, und automatisch in die aktive CLI einfügt.

**Architecture:** `ChromeCDPClient` verwaltet die WebSocket-Verbindung zu Chrome (Port 9222). `HTMLPickerPanel` ist ein schwebendes `NSPanel` mit Status-Dot, Pick-Button, HTML-Vorschau und Auto-Paste via CGEvent. Ein neuer `PaletteCommand("HTML Picker")` öffnet das Panel über die quickBAR.

**Tech Stack:** Swift 5.9, Cocoa, URLSessionWebSocketTask (CDP), CGEvent (auto-paste), NSPanel (.nonactivatingPanel)

---

## Kontext für den Implementierer

- **Einzige Datei:** `quickTerminal.swift` (~13.500 Zeilen)
- **Build:** `bash build.sh` — muss ohne Fehler durchlaufen
- **Kein Test-Framework** — Verifikation via Kompilierung + manuellem Test
- **Einfügepunkt für neue Klassen:** Suche nach `// MARK: - Split Container` (Zeile ~8747). Neuer Code kommt DIREKT VOR dieser Zeile.
- **quickBAR-Befehl einfügen:** Suche `PaletteCommand(title: "Git"` am Ende von `paletteCommands()` (Zeile ~11607). HTML Picker kommt davor.
- **AppDelegate-Properties:** Suche `var commandPalette: CommandPaletteView?` (Zeile ~10308). Neues Property kommt danach.

---

## Task 1: ChromeCDPClient

**Files:**
- Modify: `quickTerminal.swift` — direkt vor `// MARK: - Split Container`

**Step 1: Einfügen des kompletten ChromeCDPClient**

Suche in `quickTerminal.swift` nach der Zeile `// MARK: - Split Container`.
Füge DIREKT DAVOR ein (also nach dem NSButton shake-Block):

```swift
// MARK: - Chrome CDP Client

class ChromeCDPClient {
    static let debugPort = 9222
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var messageId = 0
    private var pendingCallbacks: [Int: ([String: Any]?) -> Void] = [:]

    /// Prüft ob Chrome mit --remote-debugging-port läuft (2s Timeout)
    func isAvailable(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://localhost:\(Self.debugPort)/json") else {
            completion(false); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        URLSession.shared.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                completion((response as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }

    /// Startet Chrome neu mit --remote-debugging-port=9222
    func launchChrome(completion: @escaping () -> Void) {
        let candidates = [
            "/Applications/Google Chrome.app",
            "/Applications/Chromium.app",
            "/Applications/Google Chrome Canary.app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            DispatchQueue.main.async { completion() }
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", path, "--args", "--remote-debugging-port=\(Self.debugPort)"]
        try? proc.run()
        // Chrome braucht ~1.5s zum Starten
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { completion() }
    }

    /// Gibt die WebSocket-URL des ersten aktiven Page-Tabs zurück
    func getActiveTabWS(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/list") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let tabs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let tab = tabs.first(where: { ($0["type"] as? String) == "page" }),
                  let wsURL = tab["webSocketDebuggerUrl"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(wsURL) }
        }.resume()
    }

    /// Verbindet via WebSocket mit einem Chrome-Tab
    func connect(wsURL: String, completion: @escaping (Bool) -> Void) {
        disconnect()
        guard let url = URL(string: wsURL) else { completion(false); return }
        wsSession = URLSession(configuration: .default)
        webSocketTask = wsSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveLoop()
        // Kurze Pause damit der WebSocket-Handshake abgeschlossen ist
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion(true) }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            if case .success(let msg) = result, case .string(let text) = msg {
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? Int,
                   let cb = self.pendingCallbacks[id] {
                    self.pendingCallbacks.removeValue(forKey: id)
                    DispatchQueue.main.async { cb(json["result"] as? [String: Any]) }
                }
            }
            self.receiveLoop()
        }
    }

    /// Führt JavaScript im aktiven Tab aus (Runtime.evaluate)
    func evaluate(_ expr: String, completion: @escaping ([String: Any]?) -> Void) {
        messageId += 1
        let id = messageId
        pendingCallbacks[id] = completion
        let msg: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": ["expression": expr, "returnByValue": true]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        wsSession = nil
        pendingCallbacks.removeAll()
        messageId = 0
    }
}
```

**Step 2: Kompilieren**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh
```

Erwartet: `Done! Run with: ./quickTerminal` — kein Fehler.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add ChromeCDPClient for WebSocket CDP connection"
```

---

## Task 2: HTMLPickerPanel

**Files:**
- Modify: `quickTerminal.swift` — direkt nach dem ChromeCDPClient-Block, noch vor `// MARK: - Split Container`

**Step 1: Einfügen des kompletten HTMLPickerPanel**

Suche in `quickTerminal.swift` nach `// MARK: - Split Container`.
Füge DIREKT DAVOR (nach ChromeCDPClient) ein:

```swift
// MARK: - HTML Picker Panel

class HTMLPickerPanel: NSPanel {
    private let cdp = ChromeCDPClient()
    private var pollTimer: Timer?

    // UI
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Nicht verbunden")
    private let pickBtn = NSButton()
    private let previewLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let divider = NSBox()

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 175),
                  styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
                  backing: .buffered, defer: false)
        title = "HTML Picker"
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        setupUI()
        center()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style,
                   backing: backingStoreType, defer: flag)
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        // Status Dot
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        // Status Label
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isEditable = false; statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Pick Button
        pickBtn.title = "🎯  Element wählen"
        pickBtn.bezelStyle = .rounded
        pickBtn.isEnabled = false
        pickBtn.target = self
        pickBtn.action = #selector(startPicking)
        pickBtn.translatesAutoresizingMaskIntoConstraints = false

        // Divider
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        // Preview Label
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.isEditable = false; previewLabel.isBordered = false
        previewLabel.drawsBackground = false
        previewLabel.maximumNumberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        // Feedback Label
        feedbackLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        feedbackLabel.textColor = NSColor.systemGreen
        feedbackLabel.isEditable = false; feedbackLabel.isBordered = false
        feedbackLabel.drawsBackground = false
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false

        [statusDot, statusLabel, pickBtn, divider, previewLabel, feedbackLabel].forEach { cv.addSubview($0) }

        NSLayoutConstraint.activate([
            // Status row
            statusDot.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            statusDot.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 7),
            statusLabel.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),

            // Pick button
            pickBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            pickBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            pickBtn.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 10),

            // Divider
            divider.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            divider.topAnchor.constraint(equalTo: pickBtn.bottomAnchor, constant: 10),

            // Preview
            previewLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            previewLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            previewLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),

            // Feedback
            feedbackLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            feedbackLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Connection

    func connect() {
        setStatus("Verbinde...", color: .systemOrange)
        pickBtn.isEnabled = false
        cdp.isAvailable { [weak self] available in
            guard let self = self else { return }
            if available {
                self.connectToTab()
            } else {
                self.setStatus("Chrome wird gestartet...", color: .systemOrange)
                self.cdp.launchChrome { self.connectToTab() }
            }
        }
    }

    private func connectToTab() {
        cdp.getActiveTabWS { [weak self] wsURL in
            guard let self = self else { return }
            guard let wsURL = wsURL else {
                self.setStatus("Kein Tab gefunden", color: .systemRed)
                return
            }
            self.cdp.connect(wsURL: wsURL) { success in
                if success {
                    self.setStatus("Chrome verbunden", color: .systemGreen)
                    self.pickBtn.isEnabled = true
                } else {
                    self.setStatus("Verbindung fehlgeschlagen", color: .systemRed)
                }
            }
        }
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusDot.layer?.backgroundColor = color.cgColor
    }

    // MARK: - Picker

    @objc func startPicking() {
        pickBtn.title = "⏳  Warte auf Klick..."
        pickBtn.isEnabled = false
        previewLabel.stringValue = ""
        feedbackLabel.isHidden = true

        // Vorherigen Wert löschen
        cdp.evaluate("window.__qtPickedHTML = null; void 0;") { _ in }

        let pickerJS = """
        (function() {
          if (window.__qtPickerActive) return 'already_active';
          window.__qtPickerActive = true;
          window.__qtPickedHTML = null;
          var last = null;
          function over(e) {
            if (last && last !== e.target) { last.style.outline = ''; last.style.outlineOffset = ''; }
            last = e.target;
            last.style.outline = '2px solid #4A90D9';
            last.style.outlineOffset = '-2px';
          }
          function out(e) {
            if (e.target === last) { e.target.style.outline = ''; e.target.style.outlineOffset = ''; }
          }
          function pick(e) {
            e.preventDefault(); e.stopPropagation();
            if (last) { last.style.outline = ''; last.style.outlineOffset = ''; }
            window.__qtPickedHTML = e.target.outerHTML;
            window.__qtPickerActive = false;
            document.removeEventListener('mouseover', over, true);
            document.removeEventListener('mouseout', out, true);
            document.removeEventListener('click', pick, true);
          }
          document.addEventListener('mouseover', over, true);
          document.addEventListener('mouseout', out, true);
          document.addEventListener('click', pick, true);
          return 'started';
        })();
        """

        cdp.evaluate(pickerJS) { [weak self] _ in
            self?.startPolling()
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.pollForResult()
        }
    }

    private func pollForResult() {
        cdp.evaluate("typeof window.__qtPickedHTML !== 'undefined' && window.__qtPickedHTML !== null ? window.__qtPickedHTML : null") { [weak self] result in
            guard let self = self,
                  let dict = result,
                  let value = dict["value"] as? String,
                  !value.isEmpty else { return }
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            self.onHTMLPicked(value)
        }
    }

    private func onHTMLPicked(_ html: String) {
        // UI aktualisieren
        pickBtn.title = "🎯  Element wählen"
        pickBtn.isEnabled = true
        previewLabel.stringValue = String(html.prefix(200))

        // Clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)

        // Auto-Paste mit kurzem Delay (Clipboard muss gesetzt sein)
        autoPaste()

        // Feedback
        showFeedback("✓ Eingefügt!")
    }

    private func autoPaste() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags   = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }

    private func showFeedback(_ text: String) {
        feedbackLabel.stringValue = text
        feedbackLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.feedbackLabel.isHidden = true
        }
    }

    override func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        cdp.evaluate("window.__qtPickerActive = false; document.querySelectorAll('*').forEach(function(el){el.style.outline='';el.style.outlineOffset='';})") { _ in }
        cdp.disconnect()
        super.close()
    }
}
```

**Step 2: Kompilieren**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh
```

Erwartet: `Done! Run with: ./quickTerminal` — kein Fehler.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add HTMLPickerPanel — floating CDP element picker"
```

---

## Task 3: AppDelegate-Integration

**Files:**
- Modify: `quickTerminal.swift` — 2 Stellen

**Step 1: Property in AppDelegate hinzufügen**

Suche nach:
```swift
    var commandPalette: CommandPaletteView?
```

Füge DANACH ein:
```swift
    var htmlPickerPanel: HTMLPickerPanel?
```

**Step 2: Methode `toggleHTMLPicker()` hinzufügen**

Suche nach:
```swift
    func toggleGitPanel() {
```

Füge DAVOR ein:
```swift
    func toggleHTMLPicker() {
        if let p = htmlPickerPanel, p.isVisible {
            p.close()
            htmlPickerPanel = nil
            return
        }
        let panel = HTMLPickerPanel()
        htmlPickerPanel = panel
        panel.connect()
        panel.makeKeyAndOrderFront(nil)
    }

```

**Step 3: quickBAR-Befehl hinzufügen**

Suche nach:
```swift
            PaletteCommand(title: "Git", shortcut: "") { [weak self] in self?.toggleGitPanel() },
```

Füge DAVOR ein:
```swift
            PaletteCommand(title: "HTML Picker", shortcut: "") { [weak self] in self?.toggleHTMLPicker() },
```

**Step 4: Kompilieren**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh
```

Erwartet: `Done! Run with: ./quickTerminal` — kein Fehler.

**Step 5: Manuell testen**

1. `./quickTerminal` starten
2. Doppelt Ctrl drücken → quickBAR öffnet sich
3. "html" tippen → "HTML Picker" erscheint → Enter
4. HTMLPickerPanel erscheint (schwebt, HUD-Stil)
5. Chrome muss laufen — Status-Dot wird grün
6. "Element wählen" klicken
7. Im Browser über Elemente hovern → blauer Rahmen erscheint
8. Element anklicken → Panel zeigt Vorschau + "✓ Eingefügt!"
9. Im Terminal erscheint das HTML automatisch

**Step 6: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: wire HTMLPickerPanel into AppDelegate + quickBAR command"
```

---

## Task 4: Settings — Safari-Option

**Files:**
- Modify: `quickTerminal.swift` — Settings-Overlay + ChromeCDPClient

**Step 1: Settings-Toggle hinzufügen**

Suche nach:
```swift
        // AI Usage
        rows.append(makeSectionHeader("Claude Code"))
```

Füge DAVOR ein:
```swift
        // HTML Picker
        rows.append(makeSectionHeader("HTML Picker"))
        rows.append(makeSegmentRow(label: "Browser", options: ["Chrome", "Safari"],
            selected: UserDefaults.standard.integer(forKey: "htmlPickerBrowser"),
            key: "htmlPickerBrowser"))
```

**Step 2: Default-Wert registrieren**

Suche nach:
```swift
        "showAIUsage": true,
```

Füge DAVOR ein:
```swift
        "htmlPickerBrowser": 0,
```

**Step 3: Safari-Port in ChromeCDPClient**

Safari nutzt Port 9222 wenn Web Inspector Remote Debugging aktiviert ist.
Füge in `ChromeCDPClient` eine Property hinzu:

Suche nach:
```swift
class ChromeCDPClient {
    static let debugPort = 9222
```

Ersetze durch:
```swift
class ChromeCDPClient {
    static var debugPort: Int {
        UserDefaults.standard.integer(forKey: "htmlPickerBrowser") == 1 ? 9221 : 9222
    }
```

Hinweis: Safari Web Inspector verwendet Port 9221 für Remote Debugging (wenn aktiviert via `Entwickler > Remote Automation erlauben`). Die `launchChrome`-Methode überspringt Safari-Modus automatisch da Safari kein `--remote-debugging-port`-Flag kennt.

**Step 4: Safari-Hinweis in `toggleHTMLPicker()`**

Suche nach:
```swift
    func toggleHTMLPicker() {
        if let p = htmlPickerPanel, p.isVisible {
            p.close()
            htmlPickerPanel = nil
            return
        }
        let panel = HTMLPickerPanel()
        htmlPickerPanel = panel
        panel.connect()
        panel.makeKeyAndOrderFront(nil)
    }
```

Ersetze durch:
```swift
    func toggleHTMLPicker() {
        if let p = htmlPickerPanel, p.isVisible {
            p.close()
            htmlPickerPanel = nil
            return
        }
        // Safari-Hinweis beim ersten Mal
        if UserDefaults.standard.integer(forKey: "htmlPickerBrowser") == 1 &&
           !UserDefaults.standard.bool(forKey: "htmlPickerSafariHintShown") {
            UserDefaults.standard.set(true, forKey: "htmlPickerSafariHintShown")
            showGenericToast(badge: "SAFARI",
                text: "Web Inspector aktivieren: Safari → Entwickler → Remote Automation erlauben",
                badgeColor: NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.9, alpha: 1.0))
        }
        let panel = HTMLPickerPanel()
        htmlPickerPanel = panel
        panel.connect()
        panel.makeKeyAndOrderFront(nil)
    }
```

**Step 5: Kompilieren**

```bash
bash build.sh
```

Erwartet: `Done! Run with: ./quickTerminal`

**Step 6: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add Safari browser option for HTML Picker in Settings"
```

---

## Task 5: Version Bump + ZIP

**Files:**
- Modify: `quickTerminal.swift` — `kAppVersion`
- Modify: `build_app.sh` — `VERSION`
- Modify: `build_zip.sh` — `VERSION`

**Step 1: Version aktualisieren**

In `quickTerminal.swift`, Zeile ~12:
```swift
let kAppVersion = "1.3.0"
```
→
```swift
let kAppVersion = "1.4.0"
```

In `build_app.sh`:
```bash
VERSION="1.3.0"
```
→
```bash
VERSION="1.4.0"
```

In `build_zip.sh`:
```bash
VERSION="1.3.0"
```
→
```bash
VERSION="1.4.0"
```

**Step 2: ZIP bauen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build_zip.sh
```

Erwartet:
```
=== Building quickTERMINAL_v1.4.0.zip (v1.4.0) ===
...
quickTERMINAL_v1.4.0.zip  →  ~3.3M
Ready for GitHub Release v1.4.0
```

**Step 3: Final Commit**

```bash
git add quickTerminal.swift build_app.sh build_zip.sh
git commit -m "v1.4.0: HTML Picker — CDP element selector with auto-paste"
```

---

## Manuelle Gesamttest-Checkliste

Nach vollständiger Implementierung:

- [ ] quickBAR `html` → "HTML Picker" erscheint
- [ ] Panel öffnet sich (HUD, schwebt)
- [ ] Status-Dot: grau → orange ("Verbinde...") → grün ("Chrome verbunden")
- [ ] Chrome nicht im Debug-Modus → Panel zeigt "Chrome wird gestartet..." → startet Chrome → verbindet
- [ ] "Element wählen" klicken → Cursor zeigt Picker-Modus
- [ ] Hovern im Browser → blauer Rahmen um Elemente
- [ ] Element klicken → Rahmen verschwindet, Panel zeigt HTML-Vorschau
- [ ] "✓ Eingefügt!" erscheint für 2 Sekunden
- [ ] Im Terminal: `Cmd+V` würde dasselbe HTML zeigen (automatisch passiert)
- [ ] Panel `✕` → Verbindung getrennt, JS-Outline entfernt
- [ ] Settings → "HTML Picker" Sektion → "Safari" auswählen → Toast erscheint mit Anleitung
- [ ] Zweites Öffnen mit Safari: kein Toast mehr
