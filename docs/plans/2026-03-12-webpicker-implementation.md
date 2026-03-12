# WebPicker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename HTML Picker → WebPicker, add teal design, Connect/Disconnect buttons (disconnect closes tab), tab title in status.

**Architecture:** All changes in `quickTerminal.swift`. Three tasks: (1) rename symbols, (2) add CDP closeTab + getTabTitle, (3) full UI redesign of WebPickerSidebarView.

**Tech Stack:** Swift, Cocoa (NSView, NSButton, NSTextField), Chrome DevTools Protocol (HTTP + WebSocket)

---

## Context for implementer

### File structure
- Everything is in `/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal/quickTerminal.swift` (~9900+ lines)
- Build: `cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal" && bash build.sh`
- Run to test: `./quickTerminal`

### Current class names to change
| Old | New |
|-----|-----|
| `HTMLPickerSidebarView` | `WebPickerSidebarView` |
| `htmlPickerSidebarView` | `webPickerSidebarView` |
| `htmlPickerRightDivider` | `webPickerRightDivider` |
| `onHTMLPickerToggle` | `onWebPickerToggle` |
| `setHTMLPickerActive` | `setWebPickerActive` |
| `toggleHTMLPicker` | `toggleWebPicker` |
| `showHTMLPickerSidebar` | `showWebPickerSidebar` |
| `hideHTMLPickerSidebar` | `hideWebPickerSidebar` |
| `handleHTMLPickerDividerDrag` | `handleWebPickerDividerDrag` |

### Teal accent color (use everywhere)
```swift
let teal = NSColor(calibratedRed: 0.24, green: 0.79, blue: 0.63, alpha: 1.0)
```

### Key lines to know
- `HTMLPickerSidebarView` class: ~line 9373
- `ChromeCDPClient.disconnect()`: ~line 9055
- `ChromeCDPClient.createBlankTab()`: ~line 9063
- `AppDelegate.htmlPickerSidebarView`: ~line 11224
- `HeaderBarView.onHTMLPickerToggle`: ~line 4075
- `HeaderBarView.setHTMLPickerActive`: ~line 4308
- `toggleHTMLPicker`: ~line 12212
- PaletteCommand "HTML Picker": ~line 12645

---

## Task 1: Rename HTML Picker → WebPicker everywhere

**Files:**
- Modify: `quickTerminal.swift` (multiple locations)

**Step 1: Rename all symbols**

Use the Edit tool with `replace_all: true` for each of these replacements, one at a time:

1. `HTMLPickerSidebarView` → `WebPickerSidebarView`
2. `htmlPickerSidebarView` → `webPickerSidebarView`
3. `htmlPickerRightDivider` → `webPickerRightDivider`
4. `onHTMLPickerToggle` → `onWebPickerToggle`
5. `setHTMLPickerActive` → `setWebPickerActive`
6. `toggleHTMLPicker` → `toggleWebPicker`
7. `showHTMLPickerSidebar` → `showWebPickerSidebar`
8. `hideHTMLPickerSidebar` → `hideWebPickerSidebar`
9. `handleHTMLPickerDividerDrag` → `handleWebPickerDividerDrag`

**Step 2: Rename string labels**

Find and update these string literals:
- `"◈  HTML Picker"` → `"◈  WebPicker"` (titleLabel in sidebar view)
- `"HTML Picker"` in PaletteCommand (~line 12645) → `"WebPicker"`
- `// MARK: - HTML Picker Sidebar View` → `// MARK: - WebPicker Sidebar View`
- `// MARK: - HTML Picker Panel` — leave as-is (HTMLPickerPanel is a separate floating panel, not being redesigned)

**Step 3: Build and verify**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal" && bash build.sh
```
Expected: `Done! Run with: ./quickTerminal` (no errors)

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "refactor: rename HTML Picker → WebPicker"
```

---

## Task 2: CDP enhancements — closeTab + getTabHostname

**Files:**
- Modify: `quickTerminal.swift` — `ChromeCDPClient` class (~lines 8840–9090)

The `ChromeCDPClient` currently ends at the `createBlankTab` method (after `disconnect()`). Add two new methods after `createBlankTab`.

**Step 1: Add `closeTab` method**

Insert after `createBlankTab`'s closing `}` and before the closing `}` of `ChromeCDPClient`:

```swift
/// Closes a Chrome tab via /json/close/{targetId}
func closeTab(targetId: String, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/close/\(targetId)") else {
        DispatchQueue.main.async { completion() }; return
    }
    var req = URLRequest(url: url)
    req.timeoutInterval = 3.0
    URLSession.shared.dataTask(with: req) { _, resp, _ in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        print("[CDP] closeTab /json/close/\(targetId) → HTTP \(code)")
        DispatchQueue.main.async { completion() }
    }.resume()
}

/// Returns hostname of the currently active page tab (e.g. "github.com")
func getTabHostname(targetId: String, completion: @escaping (String?) -> Void) {
    guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/list") else {
        DispatchQueue.main.async { completion(nil) }; return
    }
    URLSession.shared.dataTask(with: URLRequest(url: url)) { data, _, _ in
        guard let data = data,
              let tabs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let tab = tabs.first(where: { ($0["id"] as? String) == targetId }),
              let tabURL = tab["url"] as? String else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        // Extract hostname: "https://github.com/foo" → "github.com"
        let hostname: String
        if tabURL == "about:blank" || tabURL.isEmpty {
            hostname = ""
        } else if let host = URL(string: tabURL)?.host {
            hostname = host
        } else {
            hostname = tabURL
        }
        DispatchQueue.main.async { completion(hostname) }
    }.resume()
}
```

**Step 2: Build and verify**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal" && bash build.sh
```
Expected: `Done!` (no errors)

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add CDP closeTab + getTabHostname"
```

---

## Task 3: WebPickerSidebarView — full UI redesign

**Files:**
- Modify: `quickTerminal.swift` — `WebPickerSidebarView` class (~lines 9373–9630)

This task replaces the entire `WebPickerSidebarView` class body. The class starts at `// MARK: - WebPicker Sidebar View` and ends before `// MARK: - Split Container`.

### What the new UI looks like

**States:**
- `disconnected`: gray dot, "Nicht verbunden", Connect button full-width, no Disconnect
- `connecting`: orange dot, status message, Connect disabled, no Disconnect
- `navigating`: orange dot, "Navigiere zur Webseite", pickBtn disabled, Disconnect visible
- `ready`: green dot, hostname (e.g. "github.com"), pickBtn enabled+teal, Disconnect visible
- `picking`: green dot, "Warte auf Klick...", pickBtn disabled, Disconnect visible
- `picked`: green dot, hostname, pickBtn re-enabled, "✓ Kopiert!" feedback, preview shown

### New full class implementation

Replace the entire class (from `// MARK: - WebPicker Sidebar View` to just before `// MARK: - Split Container`) with:

```swift
// MARK: - WebPicker Sidebar View

class WebPickerSidebarView: NSView {
    private let cdp = ChromeCDPClient()
    private var pollTimer: Timer?
    private var tabSearchTimer: Timer?
    private var titlePollTimer: Timer?
    private var isConnected = false
    private var currentTargetId: String?
    var onClose: (() -> Void)?

    // Teal accent
    private static let teal = NSColor(calibratedRed: 0.24, green: 0.79, blue: 0.63, alpha: 1.0)

    // UI elements
    private let titleLabel   = NSTextField(labelWithString: "◈  WebPicker")
    private let closeBtn     = NSButton()
    private let titleSep     = NSView()
    private let statusDot    = NSView()
    private let statusLabel  = NSTextField(labelWithString: "Nicht verbunden")
    private let pickBtn      = NSButton()
    private let connectBtn   = NSButton()
    private let disconnectBtn = NSButton()
    private let previewSep   = NSView()
    private let previewLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        // ── Title bar ──
        titleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.textColor = Self.teal
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeBtn.title = "✕"
        closeBtn.isBordered = false; closeBtn.bezelStyle = .inline
        closeBtn.font = NSFont.systemFont(ofSize: 11)
        closeBtn.contentTintColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        closeBtn.target = self; closeBtn.action = #selector(doClose)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeBtn)

        // Teal separator line under title
        titleSep.wantsLayer = true
        titleSep.layer?.backgroundColor = Self.teal.withAlphaComponent(0.35).cgColor
        titleSep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleSep)

        // ── Status row ──
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusDot)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        statusLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        // ── Pick button (main action, teal styled) ──
        pickBtn.title = "  🎯  Element wählen"
        pickBtn.bezelStyle = .rounded
        pickBtn.isEnabled = false
        pickBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        pickBtn.wantsLayer = true
        pickBtn.target = self; pickBtn.action = #selector(startPicking)
        pickBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pickBtn)
        styleTealButton(pickBtn, enabled: false)

        // ── Connect button ──
        connectBtn.title = "  ⊕  Connect"
        connectBtn.bezelStyle = .rounded
        connectBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        connectBtn.wantsLayer = true
        connectBtn.target = self; connectBtn.action = #selector(doConnect)
        connectBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectBtn)
        styleTealButton(connectBtn, enabled: true)

        // ── Disconnect button ──
        disconnectBtn.title = "⏏  Disconnect"
        disconnectBtn.bezelStyle = .inline
        disconnectBtn.isBordered = false
        disconnectBtn.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        disconnectBtn.contentTintColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        disconnectBtn.isHidden = true
        disconnectBtn.target = self; disconnectBtn.action = #selector(doDisconnect)
        disconnectBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(disconnectBtn)

        // ── Preview area ──
        previewSep.wantsLayer = true
        previewSep.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        previewSep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewSep)

        previewLabel.font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        previewLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        previewLabel.maximumNumberOfLines = 4
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewLabel)

        feedbackLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        feedbackLabel.textColor = Self.teal
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(feedbackLabel)

        NSLayoutConstraint.activate([
            // Title bar
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 18),
            titleSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleSep.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            titleSep.heightAnchor.constraint(equalToConstant: 1),
            // Status
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusDot.topAnchor.constraint(equalTo: titleSep.bottomAnchor, constant: 10),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            // Pick button
            pickBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pickBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pickBtn.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 9),
            // Connect button (full width, same position as pickBtn)
            connectBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            connectBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            connectBtn.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 9),
            // Disconnect button (small, below pick)
            disconnectBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            disconnectBtn.topAnchor.constraint(equalTo: pickBtn.bottomAnchor, constant: 4),
            // Preview sep
            previewSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewSep.topAnchor.constraint(equalTo: disconnectBtn.bottomAnchor, constant: 7),
            previewSep.heightAnchor.constraint(equalToConstant: 1),
            // Preview
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewLabel.topAnchor.constraint(equalTo: previewSep.bottomAnchor, constant: 6),
            feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            feedbackLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
        ])

        // Initial state: disconnected
        showDisconnectedState()
    }

    // MARK: - Button styling

    private func styleTealButton(_ btn: NSButton, enabled: Bool) {
        let t = Self.teal
        btn.layer?.cornerRadius = 5
        btn.layer?.backgroundColor = t.withAlphaComponent(enabled ? 0.15 : 0.06).cgColor
        btn.layer?.borderColor = t.withAlphaComponent(enabled ? 0.4 : 0.15).cgColor
        btn.layer?.borderWidth = 0.5
        btn.contentTintColor = t.withAlphaComponent(enabled ? 1.0 : 0.4)
        btn.alphaValue = enabled ? 1.0 : 0.5
    }

    // MARK: - State transitions

    private func showDisconnectedState() {
        setStatusDot(.systemGray)
        setStatusText("Nicht verbunden")
        pickBtn.isHidden = true
        disconnectBtn.isHidden = true
        connectBtn.isHidden = false
        connectBtn.isEnabled = true
        styleTealButton(connectBtn, enabled: true)
        previewSep.isHidden = true
        previewLabel.stringValue = ""
        feedbackLabel.isHidden = true
    }

    private func showConnectingState(_ msg: String) {
        setStatusDot(.systemOrange)
        setStatusText(msg)
        pickBtn.isHidden = true
        disconnectBtn.isHidden = true
        connectBtn.isHidden = false
        connectBtn.isEnabled = false
        styleTealButton(connectBtn, enabled: false)
        previewSep.isHidden = true
    }

    private func showConnectedState(hostname: String, navigating: Bool) {
        if navigating {
            setStatusDot(.systemOrange)
            setStatusText("Navigiere zur Webseite")
        } else {
            setStatusDot(Self.teal)
            setStatusText(hostname.isEmpty ? "Verbunden" : hostname)
        }
        connectBtn.isHidden = true
        pickBtn.isHidden = false
        pickBtn.isEnabled = !navigating
        styleTealButton(pickBtn, enabled: !navigating)
        disconnectBtn.isHidden = false
        previewSep.isHidden = false
    }

    private func setStatusDot(_ color: NSColor) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            statusDot.animator().layer?.backgroundColor = color.cgColor
        }
    }

    private func setStatusText(_ text: String) {
        statusLabel.stringValue = text
    }

    // MARK: - Connection

    func connect() {
        isConnected = false
        currentTargetId = nil
        tabSearchTimer?.invalidate(); tabSearchTimer = nil
        titlePollTimer?.invalidate(); titlePollTimer = nil
        showConnectingState("Verbinde...")
        cdp.isAvailable { [weak self] available in
            guard let self = self else { return }
            if available {
                self.connectToTab()
            } else {
                self.cdp.launchChrome(onStatus: { [weak self] msg in
                    self?.showConnectingState(msg)
                }) { [weak self] in self?.connectToTab() }
            }
        }
    }

    func disconnect() {
        pollTimer?.invalidate(); pollTimer = nil
        tabSearchTimer?.invalidate(); tabSearchTimer = nil
        titlePollTimer?.invalidate(); titlePollTimer = nil
        isConnected = false
        pickBtn.title = "  🎯  Element wählen"
        let cleanup = "window.__qtPickerActive = false; document.querySelectorAll('*').forEach(function(el){el.style.outline='';el.style.outlineOffset='';}); void 0;"
        if let tid = currentTargetId {
            cdp.evaluate(cleanup) { [weak self] _ in
                self?.cdp.closeTab(targetId: tid) {
                    self?.cdp.disconnect()
                }
            }
        } else {
            cdp.evaluate(cleanup) { [weak self] _ in self?.cdp.disconnect() }
        }
        currentTargetId = nil
        showDisconnectedState()
    }

    private func connectToTab() {
        cdp.getActiveTabWS { [weak self] wsURL in
            guard let self = self else { return }
            if let wsURL = wsURL {
                self.doConnect(to: wsURL)
            } else {
                self.showConnectingState("Öffne neuen Tab...")
                self.cdp.createBlankTab { [weak self] newWS in
                    guard let self = self else { return }
                    if let newWS = newWS {
                        self.doConnect(to: newWS)
                    } else {
                        self.showDisconnectedState()
                        self.setStatusText("Chrome nicht erreichbar")
                    }
                }
            }
        }
    }

    private func doConnect(to wsURL: String) {
        // Extract targetId from wsURL: "ws://localhost:9222/devtools/page/{id}"
        currentTargetId = wsURL.components(separatedBy: "/").last
        tabSearchTimer?.invalidate(); tabSearchTimer = nil
        cdp.connect(wsURL: wsURL) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.isConnected = true
                self.refreshTabTitle()
            } else {
                self.showDisconnectedState()
                self.setStatusText("Verbindung fehlgeschlagen")
                self.scheduleTabSearch()
            }
        }
    }

    private func refreshTabTitle() {
        guard let tid = currentTargetId else { return }
        cdp.getTabHostname(targetId: tid) { [weak self] hostname in
            guard let self = self else { return }
            let navigating = hostname == nil || hostname!.isEmpty
            self.showConnectedState(hostname: hostname ?? "", navigating: navigating)
            // Poll title every 3s to catch page navigation
            self.titlePollTimer?.invalidate()
            self.titlePollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.refreshTabTitle()
            }
        }
    }

    private func scheduleTabSearch() {
        tabSearchTimer?.invalidate()
        tabSearchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            self.connectToTab()
        }
    }

    // MARK: - Buttons

    @objc private func doConnect() { connect() }

    @objc private func doDisconnect() { disconnect() }

    @objc private func doClose() { onClose?() }

    // MARK: - Picker

    @objc private func startPicking() {
        pickBtn.title = "⏳  Warte auf Klick..."; pickBtn.isEnabled = false
        styleTealButton(pickBtn, enabled: false)
        previewLabel.stringValue = ""; feedbackLabel.isHidden = true
        cdp.evaluate("window.__qtPickedHTML = null; window.__qtPickerActive = false; void 0;") { _ in }
        let pickerJS = """
        (function() {
          if (window.__qtPickerActive) return 'already_active';
          window.__qtPickerActive = true; window.__qtPickedHTML = null;
          var last = null;
          function over(e) {
            if (last && last !== e.target) { last.style.outline=''; last.style.outlineOffset=''; }
            last = e.target; last.style.outline='2px solid #3DC9A0'; last.style.outlineOffset='-2px';
          }
          function out(e) { if (e.target===last){e.target.style.outline='';e.target.style.outlineOffset='';} }
          function pick(e) {
            e.preventDefault(); e.stopPropagation();
            if (last){last.style.outline='';last.style.outlineOffset='';}
            window.__qtPickedHTML=e.target.outerHTML; window.__qtPickerActive=false;
            document.removeEventListener('mouseover',over,true);
            document.removeEventListener('mouseout',out,true);
            document.removeEventListener('click',pick,true);
          }
          document.addEventListener('mouseover',over,true);
          document.addEventListener('mouseout',out,true);
          document.addEventListener('click',pick,true);
          return 'started';
        })();
        """
        cdp.evaluate(pickerJS) { [weak self] _ in
            self?.pollTimer?.invalidate()
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.cdp.evaluate("typeof window.__qtPickedHTML!=='undefined'&&window.__qtPickedHTML!==null?window.__qtPickedHTML:null") { [weak self] result in
                    guard let self = self,
                          let inner = (result?["result"] as? [String: Any]),
                          let val = inner["value"] as? String, !val.isEmpty else { return }
                    self.pollTimer?.invalidate(); self.pollTimer = nil
                    DispatchQueue.main.async { self.onHTMLPicked(val) }
                }
            }
        }
    }

    private func onHTMLPicked(_ html: String) {
        pickBtn.title = "  🎯  Element wählen"; pickBtn.isEnabled = true
        styleTealButton(pickBtn, enabled: true)
        previewLabel.stringValue = String(html.prefix(300))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand; vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap); vUp?.post(tap: .cghidEventTap)
        }
        feedbackLabel.stringValue = "✓ Kopiert!"; feedbackLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.feedbackLabel.isHidden = true
        }
    }

    deinit {
        pollTimer?.invalidate()
        tabSearchTimer?.invalidate()
        titlePollTimer?.invalidate()
        cdp.disconnect()
    }
}
```

**Step 1: Find the exact start and end of old class body**

The class starts with `// MARK: - WebPicker Sidebar View` (after Task 1 rename) and ends just before `// MARK: - Split Container`. Read those line numbers to find exact boundaries.

**Step 2: Replace old class with new class**

Use Edit tool to replace from `// MARK: - WebPicker Sidebar View` through the old `deinit` + closing `}` with the new implementation above.

**Step 3: Build and verify**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal" && bash build.sh
```
Expected: `Done! Run with: ./quickTerminal` (no errors)

If there are compile errors, check for:
- Missing method references (the `createBlankTab` from Task 2 must exist)
- `onHTMLPickerToggle` still referenced anywhere (should be renamed in Task 1)

**Step 4: Manual test**

Run `./quickTerminal`, open the WebPicker sidebar (`</>` button):
- Should see "◈  WebPicker" title in teal
- Status dot gray, "Nicht verbunden"
- "⊕ Connect" button (teal styled)
- Click Connect → Chrome opens, tab created
- Status: "Navigiere zur Webseite" (orange dot)
- Navigate Chrome to e.g. `github.com`
- Status updates to "github.com" (teal dot) within 3s
- Pick button becomes active (teal)
- Click "Element wählen" → hover outline is teal (#3DC9A0) in Chrome
- Click element → HTML in clipboard, "✓ Kopiert!" feedback
- Click Disconnect → tab closes in Chrome, state returns to disconnected

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: WebPicker redesign — teal design, Connect/Disconnect, tab title"
```
