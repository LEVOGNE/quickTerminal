# AI Usage Display Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show Claude Code subscription usage (session %, weekly limits, reset times) as a clickable badge in quickTerminal's footer bar with a detail popover.

**Architecture:** Read Claude Code OAuth token from macOS Keychain (`"Claude Code-credentials"`), poll `GET https://api.anthropic.com/api/oauth/usage` periodically, display a color-coded percentage badge in the footer bar. Clicking the badge opens a frosted-glass popover with full breakdown (5h session, 7-day all models, 7-day Sonnet, extra usage).

**Tech Stack:** Swift, Cocoa (NSView, Security framework), URLSession, JSONSerialization

---

### Task 1: AIUsageManager — Data Model & Keychain Token Reading

**Files:**
- Modify: `quickTerminal.swift` — insert new class after `GitHubClient` (after line ~6815)

**Step 1: Add the AIUsageData model and AIUsageManager class skeleton**

Insert after the closing `}` of `GitHubClient` (around line 6815):

```swift
// MARK: - AI Usage Manager

struct AIUsageCategory {
    let utilization: Double   // 0-100
    let resetsAt: Date?
}

struct AIUsageData {
    let fiveHour: AIUsageCategory?
    let sevenDay: AIUsageCategory?
    let sevenDayOpus: AIUsageCategory?
    let sevenDaySonnet: AIUsageCategory?
    let extraUsageEnabled: Bool
    let extraUsageUtilization: Double?
    let fetchedAt: Date
}

class AIUsageManager {
    static let shared = AIUsageManager()

    var onUpdate: ((AIUsageData?) -> Void)?
    private(set) var latestData: AIUsageData?
    private var pollTimer: Timer?
    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Read Claude Code OAuth token from macOS Keychain
    func readClaudeToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        guard status == errSecSuccess, let data = ref as? Data else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return token
    }
}
```

**Step 2: Build to verify it compiles**

Run: `bash build.sh`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add AIUsageManager skeleton with Keychain token reading"
```

---

### Task 2: AIUsageManager — API Fetch & JSON Parsing

**Files:**
- Modify: `quickTerminal.swift` — add methods to `AIUsageManager` class

**Step 1: Add the fetchUsage method to AIUsageManager**

Add inside the `AIUsageManager` class, after `readClaudeToken()`:

```swift
    /// Fetch usage data from Anthropic OAuth API
    func fetchUsage() {
        guard let token = readClaudeToken() else {
            DispatchQueue.main.async { self.onUpdate?(nil) }
            return
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self, let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { self?.onUpdate?(nil) }
                return
            }
            let result = self.parseUsageJSON(json)
            DispatchQueue.main.async {
                self.latestData = result
                self.onUpdate?(result)
            }
        }.resume()
    }

    private func parseCategory(_ json: [String: Any]?, key: String) -> AIUsageCategory? {
        guard let obj = json?[key] as? [String: Any] else { return nil }
        let util = obj["utilization"] as? Double ?? 0
        var date: Date? = nil
        if let str = obj["resets_at"] as? String {
            date = iso8601.date(from: str)
            // Fallback: try without fractional seconds
            if date == nil {
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                date = f2.date(from: str)
            }
        }
        return AIUsageCategory(utilization: util, resetsAt: date)
    }

    private func parseUsageJSON(_ json: [String: Any]) -> AIUsageData {
        let extra = json["extra_usage"] as? [String: Any]
        return AIUsageData(
            fiveHour: parseCategory(json, key: "five_hour"),
            sevenDay: parseCategory(json, key: "seven_day"),
            sevenDayOpus: parseCategory(json, key: "seven_day_opus"),
            sevenDaySonnet: parseCategory(json, key: "seven_day_sonnet"),
            extraUsageEnabled: extra?["is_enabled"] as? Bool ?? false,
            extraUsageUtilization: extra?["utilization"] as? Double,
            fetchedAt: Date()
        )
    }
```

**Step 2: Add start/stop polling methods**

Add after `parseUsageJSON`:

```swift
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        fetchUsage()  // immediate first fetch
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchUsage()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func updateInterval(_ interval: TimeInterval) {
        guard pollTimer != nil else { return }
        startPolling(interval: interval)
    }
```

**Step 3: Build to verify**

Run: `bash build.sh`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add AIUsageManager API fetch, JSON parsing, and polling"
```

---

### Task 3: AIUsageBadge — Footer Bar Badge View

**Files:**
- Modify: `quickTerminal.swift` — insert new class after `AIUsageManager` (before `// MARK: - Update Checker` or similar)

**Step 1: Create the AIUsageBadge NSView**

Insert after `AIUsageManager`:

```swift
// MARK: - AI Usage Badge

class AIUsageBadge: NSView {
    var onClick: (() -> Void)?
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "—")
    private var trackingArea: NSTrackingArea?
    private var utilization: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        addSubview(dot)

        label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.6, alpha: 1.0)
        label.isEditable = false; label.isBordered = false; label.drawsBackground = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(data: AIUsageData?) {
        guard let data = data, let session = data.fiveHour else {
            label.stringValue = "—"
            dot.layer?.backgroundColor = NSColor(calibratedWhite: 0.4, alpha: 1.0).cgColor
            return
        }
        utilization = session.utilization
        label.stringValue = "\(Int(utilization))%"

        let color: NSColor
        if utilization >= 80 {
            color = NSColor.systemRed
        } else if utilization >= 50 {
            color = NSColor.systemOrange
        } else {
            color = NSColor.systemGreen
        }
        dot.layer?.backgroundColor = color.cgColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        dot.frame = NSRect(x: 5, y: h / 2 - 3, width: 6, height: 6)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 14, y: h / 2 - label.frame.height / 2)
    }

    override var intrinsicContentSize: NSSize {
        label.sizeToFit()
        return NSSize(width: label.frame.width + 20, height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        }
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        }
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
```

**Step 2: Build to verify**

Run: `bash build.sh`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add AIUsageBadge view with color-coded utilization dot"
```

---

### Task 4: AIUsagePopover — Detail Overlay View

**Files:**
- Modify: `quickTerminal.swift` — insert after `AIUsageBadge`

**Step 1: Create the AIUsagePopover NSView**

Insert after `AIUsageBadge`:

```swift
// MARK: - AI Usage Popover

class AIUsagePopover: NSView {
    var onDismiss: (() -> Void)?
    private let contentStack = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.1).cgColor
        layer?.borderWidth = 1
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow?.shadowBlurRadius = 12
        shadow?.shadowOffset = NSSize(width: 0, height: -4)

        addSubview(contentStack)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(data: AIUsageData?) {
        contentStack.subviews.forEach { $0.removeFromSuperview() }

        guard let data = data else {
            let noData = makeLabel("No usage data", size: 10, color: NSColor(calibratedWhite: 0.5, alpha: 1))
            contentStack.addSubview(noData)
            noData.frame = NSRect(x: 12, y: 12, width: 180, height: 16)
            return
        }

        var y: CGFloat = 12
        let w: CGFloat = bounds.width - 24

        // Timestamp
        let elapsed = Int(Date().timeIntervalSince(data.fetchedAt))
        let agoStr = elapsed < 5 ? "gerade eben" : "vor \(elapsed)s"
        let ts = makeLabel("↻ \(agoStr)", size: 8, color: NSColor(calibratedWhite: 0.4, alpha: 1))
        contentStack.addSubview(ts)
        ts.frame = NSRect(x: 12, y: y, width: w, height: 12)
        y += 18

        // Extra usage
        if data.extraUsageEnabled {
            y = addCategory(y: y, w: w, title: "Extra Usage",
                util: data.extraUsageUtilization ?? 0, resetsAt: nil)
        }

        // Sonnet
        if let s = data.sevenDaySonnet {
            y = addCategory(y: y, w: w, title: "Weekly (Sonnet)", util: s.utilization, resetsAt: s.resetsAt)
        }

        // Opus
        if let o = data.sevenDayOpus {
            y = addCategory(y: y, w: w, title: "Weekly (Opus)", util: o.utilization, resetsAt: o.resetsAt)
        }

        // 7-day
        if let week = data.sevenDay {
            y = addCategory(y: y, w: w, title: "Weekly (All Models)", util: week.utilization, resetsAt: week.resetsAt)
        }

        // 5-hour session
        if let session = data.fiveHour {
            y = addCategory(y: y, w: w, title: "Session (5h)", util: session.utilization, resetsAt: session.resetsAt)
        }

        // Title
        let title = makeLabel("Claude Code Usage", size: 11, color: NSColor(calibratedWhite: 0.85, alpha: 1), bold: true)
        contentStack.addSubview(title)
        title.frame = NSRect(x: 12, y: y, width: w, height: 16)
        y += 24

        // Resize
        let totalH = y
        frame.size.height = totalH
        frame.origin.y = superview != nil ? frame.origin.y : 0
        contentStack.frame = bounds
    }

    private func addCategory(y: CGFloat, w: CGFloat, title: String, util: Double, resetsAt: Date?) -> CGFloat {
        var cy = y

        // Reset time
        if let reset = resetsAt {
            let resetStr = formatReset(reset)
            let resetLbl = makeLabel("Reset: \(resetStr)", size: 8, color: NSColor(calibratedWhite: 0.4, alpha: 1))
            contentStack.addSubview(resetLbl)
            resetLbl.frame = NSRect(x: 12, y: cy, width: w, height: 12)
            cy += 14
        }

        // Progress bar + percentage
        let barBg = NSView()
        barBg.wantsLayer = true
        barBg.layer?.cornerRadius = 2.5
        barBg.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        contentStack.addSubview(barBg)
        barBg.frame = NSRect(x: 12, y: cy, width: w - 40, height: 5)

        let barFill = NSView()
        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 2.5
        let color: NSColor = util >= 80 ? .systemRed : util >= 50 ? .systemOrange : .systemGreen
        barFill.layer?.backgroundColor = color.cgColor
        barBg.addSubview(barFill)
        let fillW = max(0, min(barBg.frame.width, barBg.frame.width * CGFloat(util / 100)))
        barFill.frame = NSRect(x: 0, y: 0, width: fillW, height: 5)

        let pctLbl = makeLabel("\(Int(util))%", size: 9, color: NSColor(calibratedWhite: 0.6, alpha: 1))
        contentStack.addSubview(pctLbl)
        pctLbl.frame = NSRect(x: w - 24, y: cy - 4, width: 36, height: 14)
        cy += 12

        // Title
        let titleLbl = makeLabel(title, size: 9, color: NSColor(calibratedWhite: 0.65, alpha: 1), bold: true)
        contentStack.addSubview(titleLbl)
        titleLbl.frame = NSRect(x: 12, y: cy, width: w, height: 14)
        cy += 22

        return cy
    }

    private func formatReset(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "jetzt" }
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        if h > 24 {
            let fmt = DateFormatter()
            fmt.dateFormat = "E, d. MMM HH:mm"
            fmt.locale = Locale(identifier: "de_DE")
            return fmt.string(from: date)
        }
        if h > 0 { return "in \(h)h \(m)m" }
        return "in \(m)m"
    }

    private func makeLabel(_ text: String, size: CGFloat, color: NSColor, bold: Bool = false) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        lbl.textColor = color
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        return lbl
    }

    override func mouseDown(with event: NSEvent) {
        // Consume click inside popover
    }
}
```

**Step 2: Build to verify**

Run: `bash build.sh`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add AIUsagePopover detail overlay with progress bars"
```

---

### Task 5: FooterBarView Integration — Add Badge

**Files:**
- Modify: `quickTerminal.swift:5107-5321` — FooterBarView class

**Step 1: Add the AIUsageBadge property to FooterBarView**

At line 5112, after `private var quitBtn: QuitButton!`, add:

```swift
    private(set) var usageBadge: AIUsageBadge!
```

**Step 2: Create the badge in `init(frame:)`**

In `FooterBarView.init(frame:)` (line 5166), after the quit button setup (after line 5237 `rechtsContent.addSubview(quitBtn)`), add:

```swift
        // AI Usage badge
        usageBadge = AIUsageBadge(frame: .zero)
        rechtsContent.addSubview(usageBadge)
```

**Step 3: Add badge to layout**

In `FooterBarView.layout()` (line 5241), insert the badge layout BEFORE the gear button layout. Find line 5277 `rx += 13` and insert before it:

```swift
        // AI usage badge (only if enabled)
        if !usageBadge.isHidden {
            let ubSz = usageBadge.intrinsicContentSize
            usageBadge.frame = NSRect(x: rx, y: cy - ubSz.height / 2, width: ubSz.width, height: ubSz.height)
            rx += ubSz.width + badgeGap
        }
```

**Step 4: Add callback for badge click**

After `var onNextTab: (() -> Void)?` (line 5129), add:

```swift
    var onUsageBadgeClick: (() -> Void)?
```

And wire it up in `init(frame:)` after `rechtsContent.addSubview(usageBadge)`:

```swift
        usageBadge.onClick = { [weak self] in self?.onUsageBadgeClick?() }
        // Hide by default, shown when data arrives
        usageBadge.isHidden = !UserDefaults.standard.bool(forKey: "showAIUsage")
```

**Step 5: Build to verify**

Run: `bash build.sh`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: integrate AIUsageBadge into FooterBarView"
```

---

### Task 6: Settings Integration — AI Usage Section

**Files:**
- Modify: `quickTerminal.swift:5713-6595` — SettingsOverlay class

**Step 1: Add AI Usage settings section**

In `SettingsOverlay.init()`, find the line `rows.append(makeResetRow())` (around line 5848). Insert BEFORE it:

```swift
        // AI Usage
        rows.append(makeSectionHeader("AI Usage"))
        rows.append(makeToggleRow(label: "Show Usage Badge", settingsKey: "showAIUsage"))
        rows.append(makeSegmentRow(label: "Refresh", options: ["30s", "1m", "5m"],
            selected: UserDefaults.standard.integer(forKey: "aiUsageRefreshIndex"),
            key: "aiUsageRefreshIndex"))
```

**Step 2: Add default settings**

Find `defaultSettings` dictionary (around line 6501). Add these entries:

```swift
        "showAIUsage": true,
        "aiUsageRefreshIndex": 1,
```

**Step 3: Build to verify**

Run: `bash build.sh`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add AI Usage toggle and refresh interval to Settings"
```

---

### Task 7: AppDelegate Wiring — Connect Everything

**Files:**
- Modify: `quickTerminal.swift:9455-9520` — AppDelegate properties
- Modify: `quickTerminal.swift:9710+` — footer setup area
- Modify: `quickTerminal.swift:9939+` — applySetting() cases

**Step 1: Add AppDelegate properties**

After `var parserOverlay: DiagnosticsOverlay?` (line 9508), add:

```swift
    var usagePopover: AIUsagePopover?
```

**Step 2: Wire footer badge click & start polling**

After footer setup (find the line where `window.contentView?.addSubview(footerView)` is, around line 9740+), add:

```swift
        // AI Usage
        footerView.onUsageBadgeClick = { [weak self] in self?.toggleUsagePopover() }
        AIUsageManager.shared.onUpdate = { [weak self] data in
            self?.footerView.usageBadge.update(data: data)
            self?.usagePopover?.update(data: data)
        }
        if UserDefaults.standard.bool(forKey: "showAIUsage") {
            let intervals: [TimeInterval] = [30, 60, 300]
            let idx = UserDefaults.standard.integer(forKey: "aiUsageRefreshIndex")
            AIUsageManager.shared.startPolling(interval: intervals[min(idx, 2)])
        }
```

**Step 3: Add toggleUsagePopover method**

Add this method to AppDelegate (near `toggleSettings()`, around line 10147):

```swift
    func toggleUsagePopover() {
        if let pop = usagePopover {
            pop.removeFromSuperview()
            usagePopover = nil
            return
        }
        guard let contentView = window.contentView else { return }
        let popW: CGFloat = 220
        let popH: CGFloat = 200  // will auto-resize on update
        let footerH = FooterBarView.barHeight
        let badge = footerView.usageBadge!
        let badgeMid = badge.convert(NSPoint(x: badge.bounds.midX, y: 0), to: contentView)

        let pop = AIUsagePopover(frame: NSRect(
            x: min(max(badgeMid.x - popW / 2, 8), contentView.bounds.width - popW - 8),
            y: footerH + 4,
            width: popW, height: popH))
        pop.update(data: AIUsageManager.shared.latestData)
        contentView.addSubview(pop)
        usagePopover = pop
    }
```

**Step 4: Handle settings changes in `applySetting()`**

In `applySetting(key:value:)` (around line 9939), add new cases:

```swift
        case "showAIUsage":
            let on = value as? Bool ?? false
            footerView.usageBadge.isHidden = !on
            if on {
                let intervals: [TimeInterval] = [30, 60, 300]
                let idx = UserDefaults.standard.integer(forKey: "aiUsageRefreshIndex")
                AIUsageManager.shared.startPolling(interval: intervals[min(idx, 2)])
            } else {
                AIUsageManager.shared.stopPolling()
                if let pop = usagePopover { pop.removeFromSuperview(); usagePopover = nil }
            }
            footerView.needsLayout = true
        case "aiUsageRefreshIndex":
            let intervals: [TimeInterval] = [30, 60, 300]
            let idx = value as? Int ?? 1
            AIUsageManager.shared.updateInterval(intervals[min(idx, 2)])
```

**Step 5: Dismiss popover on click outside**

In the existing global click monitor (or where the settings overlay dismiss is handled), add:

```swift
        if let pop = usagePopover {
            let loc = pop.convert(event.locationInWindow, from: nil)
            if !pop.bounds.contains(loc) {
                pop.removeFromSuperview()
                usagePopover = nil
            }
        }
```

**Step 6: Build to verify**

Run: `bash build.sh`
Expected: Build succeeds

**Step 7: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: wire AIUsageManager, popover toggle, and settings to AppDelegate"
```

---

### Task 8: Polish & Manual Testing

**Files:**
- Modify: `quickTerminal.swift` — minor adjustments as needed

**Step 1: Build and run the app**

Run: `bash build.sh && ./quickTerminal`
Expected: App launches, footer shows usage badge (or "—" if no Claude Code token)

**Step 2: Verify Keychain token reading**

Check macOS Keychain has `"Claude Code-credentials"` entry. If present, the badge should show a percentage within ~60 seconds.

**Step 3: Verify popover opens/closes**

Click the badge → popover appears with usage breakdown.
Click outside → popover dismisses.
Click badge again → popover toggles.

**Step 4: Verify settings**

Open Settings → AI Usage section visible.
Toggle "Show Usage Badge" off → badge disappears.
Toggle back on → badge reappears, polling restarts.
Change refresh interval → polling interval updates.

**Step 5: Final commit if adjustments were made**

```bash
git add quickTerminal.swift
git commit -m "feat: polish AI usage display"
```
