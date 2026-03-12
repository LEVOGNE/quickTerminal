# Git Panel Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Das Git Panel komplett neu aufbauen — radikal vereinfacht, kein Fachjargon, für Einsteiger benutzbar, mit Git-Init + GitHub-Repo-Erstellung.

**Architecture:** Ersetzt die gesamte `GitPanelView` Klasse (Zeilen 7573–9295 in quickTerminal.swift) durch eine neue, auf NSStackView basierende Implementierung. Fügt `createRepo()` zur `GitHubClient` Klasse hinzu. Alle anderen Klassen (`GitHubClient`, `GitPanelDividerView`, `MarqueeLabel`, `ClickableFileRow`) bleiben unverändert.

**Tech Stack:** Swift 5.9, Cocoa (AppKit), /usr/bin/git, GitHub REST API v3, `gh` CLI für Token-Auto-Detection.

---

## Wichtige Zeilen-Referenzen (quickTerminal.swift)

- `GitHubClient` class: Zeilen 6710–6914
- `logout()` Methode: Zeile 6908
- `GitPanelView` class (zu ersetzen): Zeilen 7573–9295
- `// MARK: - Split Container` (danach): Zeile 9297

---

## Task 1: `createRepo()` zu GitHubClient hinzufügen

**Files:**
- Modify: `quickTerminal.swift` — vor `logout()` bei Zeile 6908

**Step 1: Methode einfügen**

Füge direkt VOR `func logout()` (Zeile 6908) diese Methode ein:

```swift
    func createRepo(name: String, isPrivate: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let token = token,
              let url = URL(string: "https://api.github.com/user/repos") else {
            completion(false, "Nicht angemeldet"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["name": name, "private": isPrivate, "auto_init": false]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(false, error?.localizedDescription ?? "Netzwerkfehler") }
                return
            }
            if http.statusCode == 201 {
                // Parse clone_url from response
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let cloneURL = json?["clone_url"] as? String
                DispatchQueue.main.async { completion(true, cloneURL) }
            } else {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let msg = json?["message"] as? String ?? "Fehler \(http.statusCode)"
                DispatchQueue.main.async { completion(false, msg) }
            }
        }.resume()
    }
```

**Step 2: Build testen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh 2>&1 | tail -5
```

Erwartetes Ergebnis: kein Fehler, `Build successful` oder leere Ausgabe.

**Step 3: Commit**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
git add quickTerminal.swift
git commit -m "feat: add createRepo() to GitHubClient"
```

---

## Task 2: Neue GitPanelView — Kompletter Ersatz (Zeilen 7573–9295)

**Files:**
- Modify: `quickTerminal.swift` — Zeilen 7573–9295 vollständig ersetzen

**Step 1: Den alten Block identifizieren und ersetzen**

Ersetze den gesamten Block von:
```
class GitPanelView: NSView {
```
bis zur schließenden `}` bei Zeile 9295 (vor `// MARK: - Split Container`) mit folgendem vollständigen Code:

```swift
class GitPanelView: NSView {

    // MARK: - State & Data

    private var lastCwd = ""
    private var refreshTimer: Timer?
    private var feedbackTimer: Timer?
    private let github = GitHubClient()

    private var isGitRepo = false
    private var currentBranch = ""
    private var ahead = 0
    private var behind = 0
    private var hasRemote = false
    private var fileEntries: [(path: String, x: Character, y: Character, attr: NSAttributedString)] = []
    private var lastFilesKey = ""
    private var expandedDiffFile: String?
    private weak var currentDiffView: NSView?

    // isHorizontal: API-kompatibel behalten, aber ignoriert
    var isHorizontal: Bool { get { false } set {} }

    // MARK: - UI: Scroll + Stack

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()

    // MARK: - UI: Header Card

    private let headerCard = NSView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let branchBadge = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    // MARK: - UI: No-Repo Card

    private let noRepoCard = NSView()

    // MARK: - UI: Files Card

    private let filesCard = NSView()
    private let filesHeaderLabel = NSTextField(labelWithString: "")
    private let filesStack = NSStackView()
    private let filesScrollView = NSScrollView()

    // MARK: - UI: Commit Card

    private let commitCard = NSView()
    private let commitField = NSTextField()
    private let saveBtn = NSButton()
    private let feedbackLabel = NSTextField(labelWithString: "")

    // MARK: - UI: GitHub Card

    private let githubCard = NSView()
    private let githubConnectedStack = NSStackView()  // shown when logged in
    private let githubAuthStack = NSStackView()        // shown when not logged in
    private let githubUserLabel = NSTextField(labelWithString: "")
    private let githubSyncLabel = NSTextField(labelWithString: "")
    private let uploadBtn = NSButton()
    private let updateBtn = NSButton()
    private let disconnectBtn = NSButton()
    private let tokenField = NSSecureTextField()
    private let tokenSaveBtn = NSButton()
    private let tokenLinkBtn = NSButton()

    // MARK: - UI: New Repo Overlay (inline)

    private let newRepoOverlay = NSView()
    private let repoNameField = NSTextField()
    private var repoIsPrivate = true
    private let repoPublicBtn = NSButton()
    private let repoPrivateBtn = NSButton()
    private let repoCreateBtn = NSButton()
    private var newRepoOverlayVisible = false

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.85).cgColor
        setupScrollAndStack()
        buildHeaderCard()
        buildNoRepoCard()
        buildFilesCard()
        buildCommitCard()
        buildGithubCard()
        buildNewRepoOverlay()
        if github.isAuthenticated {
            github.fetchUser { [weak self] _ in
                DispatchQueue.main.async { self?.updateGithubCard() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout Helpers

    private func makeCard(alpha: Double = 0.04) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: alpha).cgColor
        v.layer?.cornerRadius = 10
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.isEditable = false
        l.isBordered = false
        l.drawsBackground = false
        l.maximumNumberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func makeBtn(_ title: String, color: NSColor, target: AnyObject?, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: target, action: action)
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.contentTintColor = color
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        btn.layer?.cornerRadius = 6
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    private func addToCard(_ card: NSView, views: [NSView], padding: CGFloat = 14, spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
            card.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: padding),
        ])
        return stack
    }

    // MARK: - Scroll & Stack Setup

    private func setupScrollAndStack() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 16, right: 10)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentStack
        contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
    }

    private func fullWidthInStack(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor,
                                     constant: -contentStack.edgeInsets.left - contentStack.edgeInsets.right).isActive = true
    }

    // MARK: - Header Card

    private func buildHeaderCard() {
        headerCard.wantsLayer = true
        headerCard.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        headerCard.layer?.cornerRadius = 10
        headerCard.translatesAutoresizingMaskIntoConstraints = false

        projectLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        projectLabel.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        projectLabel.translatesAutoresizingMaskIntoConstraints = false

        branchBadge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        branchBadge.textColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
        branchBadge.wantsLayer = true
        branchBadge.layer?.backgroundColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 0.12).cgColor
        branchBadge.layer?.cornerRadius = 4
        branchBadge.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [projectLabel, branchBadge])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false

        _ = addToCard(headerCard, views: [topRow, statusLabel], padding: 12, spacing: 5)

        contentStack.addArrangedSubview(headerCard)
        fullWidthInStack(headerCard)
    }

    // MARK: - No-Repo Card

    private func buildNoRepoCard() {
        noRepoCard.wantsLayer = true
        noRepoCard.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor
        noRepoCard.layer?.cornerRadius = 10
        noRepoCard.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel("Noch kein Projekt-Tracking", size: 12, weight: .medium,
                              color: NSColor(calibratedWhite: 0.6, alpha: 1.0))
        let sub = makeLabel("Klicke auf den Button um das Tracking für diesen Ordner zu starten.", size: 10.5, weight: .regular,
                            color: NSColor(calibratedWhite: 0.4, alpha: 1.0))
        let initBtn = makeBtn("🚀  Mit Tracking starten", color: NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0),
                              target: self, action: #selector(initRepoClicked))

        _ = addToCard(noRepoCard, views: [title, sub, initBtn], padding: 14, spacing: 8)

        contentStack.addArrangedSubview(noRepoCard)
        fullWidthInStack(noRepoCard)
        noRepoCard.isHidden = true
    }

    // MARK: - Files Card

    private func buildFilesCard() {
        filesCard.wantsLayer = true
        filesCard.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor
        filesCard.layer?.cornerRadius = 10
        filesCard.translatesAutoresizingMaskIntoConstraints = false

        filesHeaderLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        filesHeaderLabel.textColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        filesHeaderLabel.attributedStringValue = NSAttributedString(string: "GEÄNDERTE DATEIEN", attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
            .kern: 1.5
        ])
        filesHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

        filesStack.orientation = .vertical
        filesStack.alignment = .leading
        filesStack.spacing = 2
        filesStack.translatesAutoresizingMaskIntoConstraints = false

        filesScrollView.drawsBackground = false
        filesScrollView.hasVerticalScroller = true
        filesScrollView.hasHorizontalScroller = false
        filesScrollView.autohidesScrollers = true
        filesScrollView.scrollerStyle = .overlay
        filesScrollView.borderType = .noBorder
        filesScrollView.translatesAutoresizingMaskIntoConstraints = false
        filesScrollView.documentView = filesStack

        filesStack.widthAnchor.constraint(equalTo: filesScrollView.widthAnchor).isActive = true
        let hug = filesScrollView.heightAnchor.constraint(equalTo: filesStack.heightAnchor)
        hug.priority = .defaultHigh
        hug.isActive = true
        filesScrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true

        let inner = NSStackView(views: [filesHeaderLabel, filesScrollView])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false

        filesCard.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: filesCard.topAnchor, constant: 12),
            inner.leadingAnchor.constraint(equalTo: filesCard.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: filesCard.trailingAnchor, constant: -12),
            filesCard.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: 12),
            filesScrollView.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])

        contentStack.addArrangedSubview(filesCard)
        fullWidthInStack(filesCard)
        filesCard.isHidden = true
    }

    // MARK: - Commit Card

    private func buildCommitCard() {
        commitCard.wantsLayer = true
        commitCard.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor
        commitCard.layer?.cornerRadius = 10
        commitCard.translatesAutoresizingMaskIntoConstraints = false

        let label = makeLabel("Was hast du geändert?", size: 10, weight: .semibold,
                              color: NSColor(calibratedWhite: 0.38, alpha: 1.0))
        // Apply kern
        label.attributedStringValue = NSAttributedString(string: "WAS HAST DU GEÄNDERT?", attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
            .kern: 1.5
        ])

        commitField.isEditable = true
        commitField.isBordered = false
        commitField.focusRingType = .none
        commitField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        commitField.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        commitField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
        commitField.placeholderString = "z.B. Login-Seite verbessert, Bug behoben..."
        commitField.wantsLayer = true
        commitField.layer?.cornerRadius = 6
        commitField.translatesAutoresizingMaskIntoConstraints = false
        commitField.target = self
        commitField.action = #selector(saveClicked)

        saveBtn.title = "💾  Speichern"
        saveBtn.bezelStyle = .rounded
        saveBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        saveBtn.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
        saveBtn.wantsLayer = true
        saveBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 0.12).cgColor
        saveBtn.layer?.cornerRadius = 6
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)

        feedbackLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.maximumNumberOfLines = 2
        feedbackLabel.lineBreakMode = .byWordWrapping
        feedbackLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let inner = NSStackView(views: [label, commitField, saveBtn, feedbackLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        commitCard.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: commitCard.topAnchor, constant: 12),
            inner.leadingAnchor.constraint(equalTo: commitCard.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: commitCard.trailingAnchor, constant: -12),
            commitCard.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: 12),
            commitField.widthAnchor.constraint(equalTo: inner.widthAnchor),
            commitField.heightAnchor.constraint(equalToConstant: 28),
            saveBtn.widthAnchor.constraint(equalTo: inner.widthAnchor),
            saveBtn.heightAnchor.constraint(equalToConstant: 30),
            feedbackLabel.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])

        contentStack.addArrangedSubview(commitCard)
        fullWidthInStack(commitCard)
        commitCard.isHidden = true
    }

    // MARK: - GitHub Card

    private func buildGithubCard() {
        githubCard.wantsLayer = true
        githubCard.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.22, alpha: 0.7).cgColor
        githubCard.layer?.cornerRadius = 10
        githubCard.translatesAutoresizingMaskIntoConstraints = false

        // === AUTH STACK (not logged in) ===
        let authTitle = makeLabel("🔗  Noch nicht mit GitHub verbunden", size: 11, weight: .medium,
                                  color: NSColor(calibratedWhite: 0.55, alpha: 1.0))

        tokenField.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        tokenField.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        tokenField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
        tokenField.isBordered = false
        tokenField.focusRingType = .none
        tokenField.bezelStyle = .roundedBezel
        tokenField.placeholderString = "GitHub Token einfügen (ghp_...)"
        tokenField.translatesAutoresizingMaskIntoConstraints = false

        tokenSaveBtn.title = "Verbinden"
        tokenSaveBtn.bezelStyle = .inline
        tokenSaveBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        tokenSaveBtn.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
        tokenSaveBtn.translatesAutoresizingMaskIntoConstraints = false
        tokenSaveBtn.target = self
        tokenSaveBtn.action = #selector(saveTokenClicked)

        tokenLinkBtn.title = "Token erstellen →"
        tokenLinkBtn.bezelStyle = .inline
        tokenLinkBtn.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        tokenLinkBtn.contentTintColor = NSColor(calibratedWhite: 0.38, alpha: 1.0)
        tokenLinkBtn.translatesAutoresizingMaskIntoConstraints = false
        tokenLinkBtn.target = self
        tokenLinkBtn.action = #selector(openTokenPage)

        let tokenRow = NSStackView(views: [tokenSaveBtn, tokenLinkBtn])
        tokenRow.orientation = .horizontal
        tokenRow.spacing = 12
        tokenRow.alignment = .centerY
        tokenRow.translatesAutoresizingMaskIntoConstraints = false

        githubAuthStack.orientation = .vertical
        githubAuthStack.alignment = .leading
        githubAuthStack.spacing = 8
        githubAuthStack.translatesAutoresizingMaskIntoConstraints = false
        githubAuthStack.addArrangedSubview(authTitle)
        githubAuthStack.addArrangedSubview(tokenField)
        githubAuthStack.addArrangedSubview(tokenRow)

        // === CONNECTED STACK (logged in) ===
        githubUserLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        githubUserLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.78, blue: 1.0, alpha: 1.0)
        githubUserLabel.translatesAutoresizingMaskIntoConstraints = false

        githubSyncLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        githubSyncLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        githubSyncLabel.maximumNumberOfLines = 2
        githubSyncLabel.lineBreakMode = .byWordWrapping
        githubSyncLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        githubSyncLabel.translatesAutoresizingMaskIntoConstraints = false

        uploadBtn.title = "↑  Auf GitHub hochladen"
        uploadBtn.bezelStyle = .rounded
        uploadBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        uploadBtn.contentTintColor = NSColor(calibratedRed: 0.5, green: 0.78, blue: 1.0, alpha: 1.0)
        uploadBtn.wantsLayer = true
        uploadBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.5, green: 0.78, blue: 1.0, alpha: 0.1).cgColor
        uploadBtn.layer?.cornerRadius = 6
        uploadBtn.translatesAutoresizingMaskIntoConstraints = false
        uploadBtn.target = self
        uploadBtn.action = #selector(uploadClicked)

        updateBtn.title = "↓  Aktualisieren"
        updateBtn.bezelStyle = .rounded
        updateBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        updateBtn.contentTintColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.35, alpha: 1.0)
        updateBtn.wantsLayer = true
        updateBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.35, alpha: 0.1).cgColor
        updateBtn.layer?.cornerRadius = 6
        updateBtn.translatesAutoresizingMaskIntoConstraints = false
        updateBtn.target = self
        updateBtn.action = #selector(updateClicked)

        disconnectBtn.title = "Abmelden"
        disconnectBtn.bezelStyle = .inline
        disconnectBtn.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        disconnectBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        disconnectBtn.translatesAutoresizingMaskIntoConstraints = false
        disconnectBtn.target = self
        disconnectBtn.action = #selector(disconnectClicked)

        let userRow = NSStackView(views: [githubUserLabel, disconnectBtn])
        userRow.orientation = .horizontal
        userRow.spacing = 0
        userRow.alignment = .centerY
        userRow.translatesAutoresizingMaskIntoConstraints = false
        // push disconnectBtn to the right
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        userRow.insertArrangedSubview(spacer, at: 1)
        userRow.setCustomSpacing(0, after: githubUserLabel)

        githubConnectedStack.orientation = .vertical
        githubConnectedStack.alignment = .leading
        githubConnectedStack.spacing = 8
        githubConnectedStack.translatesAutoresizingMaskIntoConstraints = false
        githubConnectedStack.addArrangedSubview(userRow)
        githubConnectedStack.addArrangedSubview(githubSyncLabel)
        githubConnectedStack.addArrangedSubview(uploadBtn)
        githubConnectedStack.addArrangedSubview(updateBtn)

        // Outer stack holds both, only one visible at a time
        let outerStack = NSStackView(views: [githubAuthStack, githubConnectedStack])
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        githubCard.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: githubCard.topAnchor, constant: 12),
            outerStack.leadingAnchor.constraint(equalTo: githubCard.leadingAnchor, constant: 12),
            outerStack.trailingAnchor.constraint(equalTo: githubCard.trailingAnchor, constant: -12),
            githubCard.bottomAnchor.constraint(equalTo: outerStack.bottomAnchor, constant: 12),
            githubAuthStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            githubConnectedStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor),
            tokenField.widthAnchor.constraint(equalTo: githubAuthStack.widthAnchor),
            tokenField.heightAnchor.constraint(equalToConstant: 26),
            uploadBtn.widthAnchor.constraint(equalTo: githubConnectedStack.widthAnchor),
            uploadBtn.heightAnchor.constraint(equalToConstant: 30),
            updateBtn.widthAnchor.constraint(equalTo: githubConnectedStack.widthAnchor),
            updateBtn.heightAnchor.constraint(equalToConstant: 28),
            userRow.widthAnchor.constraint(equalTo: githubConnectedStack.widthAnchor),
            githubSyncLabel.widthAnchor.constraint(equalTo: githubConnectedStack.widthAnchor),
        ])

        contentStack.addArrangedSubview(githubCard)
        fullWidthInStack(githubCard)
        githubCard.isHidden = true
    }

    // MARK: - New Repo Overlay

    private func buildNewRepoOverlay() {
        newRepoOverlay.wantsLayer = true
        newRepoOverlay.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.97).cgColor
        newRepoOverlay.layer?.cornerRadius = 10
        newRepoOverlay.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.1).cgColor
        newRepoOverlay.layer?.borderWidth = 1
        newRepoOverlay.translatesAutoresizingMaskIntoConstraints = false
        newRepoOverlay.isHidden = true
        addSubview(newRepoOverlay)

        let title = makeLabel("Neues GitHub-Projekt erstellen", size: 13, weight: .semibold,
                              color: NSColor(calibratedWhite: 0.85, alpha: 1.0))

        repoNameField.isEditable = true
        repoNameField.isBordered = false
        repoNameField.focusRingType = .none
        repoNameField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        repoNameField.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        repoNameField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.07)
        repoNameField.placeholderString = "projekt-name"
        repoNameField.wantsLayer = true
        repoNameField.layer?.cornerRadius = 6
        repoNameField.translatesAutoresizingMaskIntoConstraints = false

        let visLabel = makeLabel("Sichtbarkeit:", size: 10.5, weight: .regular,
                                 color: NSColor(calibratedWhite: 0.5, alpha: 1.0))

        repoPublicBtn.setButtonType(.radio)
        repoPublicBtn.title = "Öffentlich"
        repoPublicBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        repoPublicBtn.contentTintColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        repoPublicBtn.translatesAutoresizingMaskIntoConstraints = false
        repoPublicBtn.target = self
        repoPublicBtn.action = #selector(repoVisibilityChanged(_:))
        repoPublicBtn.state = .off

        repoPrivateBtn.setButtonType(.radio)
        repoPrivateBtn.title = "Privat"
        repoPrivateBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        repoPrivateBtn.contentTintColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        repoPrivateBtn.translatesAutoresizingMaskIntoConstraints = false
        repoPrivateBtn.target = self
        repoPrivateBtn.action = #selector(repoVisibilityChanged(_:))
        repoPrivateBtn.state = .on

        let visRow = NSStackView(views: [visLabel, repoPublicBtn, repoPrivateBtn])
        visRow.orientation = .horizontal
        visRow.spacing = 12
        visRow.alignment = .centerY
        visRow.translatesAutoresizingMaskIntoConstraints = false

        repoCreateBtn.title = "✔  Erstellen & Hochladen"
        repoCreateBtn.bezelStyle = .rounded
        repoCreateBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        repoCreateBtn.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
        repoCreateBtn.wantsLayer = true
        repoCreateBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 0.12).cgColor
        repoCreateBtn.layer?.cornerRadius = 6
        repoCreateBtn.translatesAutoresizingMaskIntoConstraints = false
        repoCreateBtn.target = self
        repoCreateBtn.action = #selector(createRepoClicked)

        let cancelBtn = makeBtn("Abbrechen", color: NSColor(calibratedWhite: 0.45, alpha: 1.0),
                                target: self, action: #selector(cancelNewRepo))

        let innerStack = NSStackView(views: [title, repoNameField, visRow, repoCreateBtn, cancelBtn])
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 10
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        newRepoOverlay.addSubview(innerStack)

        // Center overlay in self
        NSLayoutConstraint.activate([
            newRepoOverlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            newRepoOverlay.centerYAnchor.constraint(equalTo: centerYAnchor),
            newRepoOverlay.widthAnchor.constraint(equalTo: widthAnchor, constant: -24),
            innerStack.topAnchor.constraint(equalTo: newRepoOverlay.topAnchor, constant: 16),
            innerStack.leadingAnchor.constraint(equalTo: newRepoOverlay.leadingAnchor, constant: 16),
            innerStack.trailingAnchor.constraint(equalTo: newRepoOverlay.trailingAnchor, constant: -16),
            newRepoOverlay.bottomAnchor.constraint(equalTo: innerStack.bottomAnchor, constant: 16),
            repoNameField.widthAnchor.constraint(equalTo: innerStack.widthAnchor),
            repoNameField.heightAnchor.constraint(equalToConstant: 28),
            repoCreateBtn.widthAnchor.constraint(equalTo: innerStack.widthAnchor),
            repoCreateBtn.heightAnchor.constraint(equalToConstant: 30),
            cancelBtn.widthAnchor.constraint(equalTo: innerStack.widthAnchor),
        ])
    }

    // MARK: - Public API (called by AppDelegate)

    func startRefreshing(cwd: String) {
        lastCwd = cwd
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func updateCwd(_ cwd: String) {
        guard cwd != lastCwd else { return }
        lastCwd = cwd
        github.cache = GitHubClient.RemoteCache()
        refresh()
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Git Helpers

    private func runGit(_ args: [String], cwd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = ["GIT_TERMINAL_PROMPT": "0", "PATH": "/usr/bin:/usr/local/bin:/opt/homebrew/bin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard var str = String(data: data, encoding: .utf8) else { return nil }
            while str.hasSuffix("\n") || str.hasSuffix("\r") { str.removeLast() }
            return str
        } catch { return nil }
    }

    private func runGitAction(_ args: [String], cwd: String) -> (success: Bool, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = ["GIT_TERMINAL_PROMPT": "0", "PATH": "/usr/bin:/usr/local/bin:/opt/homebrew/bin"]
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
            let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ok = proc.terminationStatus == 0
            return (ok, ok ? outStr : errStr)
        } catch { return (false, error.localizedDescription) }
    }

    // MARK: - Refresh

    private func refresh() {
        let cwd = lastCwd
        guard !cwd.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Is git repo?
            let topLevel = self.runGit(["rev-parse", "--show-toplevel"], cwd: cwd)
            let isRepo = topLevel != nil

            // 2. Branch
            let branch = isRepo ? (self.runGit(["branch", "--show-current"], cwd: cwd) ?? "main") : ""

            // 3. Remote exists?
            let remoteURL = isRepo ? self.runGit(["remote", "get-url", "origin"], cwd: cwd) : nil
            let hasRemote = remoteURL != nil

            // 4. Ahead / behind (only if remote)
            var aheadCount = 0, behindCount = 0
            if hasRemote, let ab = self.runGit(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], cwd: cwd) {
                let parts = ab.split(separator: "\t")
                if parts.count == 2 {
                    aheadCount = Int(parts[0]) ?? 0
                    behindCount = Int(parts[1]) ?? 0
                }
            }

            // 5. Changed files
            var entries: [(path: String, x: Character, y: Character, attr: NSAttributedString)] = []
            if isRepo, let status = self.runGit(["status", "--porcelain=v1"], cwd: cwd) {
                for line in status.split(separator: "\n", omittingEmptySubsequences: false) {
                    guard line.count >= 3 else { continue }
                    let x = line[line.startIndex]
                    let y = line[line.index(line.startIndex, offsetBy: 1)]
                    let file = String(line.dropFirst(3))

                    let (tag, tagColor, fileColor): (String, NSColor, NSColor)
                    if x == "?" {
                        (tag, tagColor, fileColor) = ("NEU", NSColor(calibratedWhite: 0.45, alpha: 1.0), NSColor(calibratedWhite: 0.6, alpha: 1.0))
                    } else if x == "D" || y == "D" {
                        (tag, tagColor, fileColor) = ("GELÖSCHT", NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 0.8), NSColor(calibratedRed: 0.8, green: 0.5, blue: 0.5, alpha: 0.8))
                    } else if x == "U" || y == "U" {
                        (tag, tagColor, fileColor) = ("KONFLIKT", NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0), NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.5, alpha: 1.0))
                    } else if "MADRC".contains(x) && x != " " && "MD".contains(y) && y != " " {
                        (tag, tagColor, fileColor) = ("BEREIT+MOD", NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.55, alpha: 1.0), NSColor(calibratedRed: 0.9, green: 0.75, blue: 0.3, alpha: 1.0))
                    } else if "MADRC".contains(x) && x != " " {
                        (tag, tagColor, fileColor) = ("BEREIT", NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.45, alpha: 1.0), NSColor(calibratedRed: 0.5, green: 0.8, blue: 0.55, alpha: 1.0))
                    } else {
                        (tag, tagColor, fileColor) = ("GEÄNDERT", NSColor(calibratedRed: 0.95, green: 0.7, blue: 0.25, alpha: 1.0), NSColor(calibratedRed: 0.85, green: 0.7, blue: 0.4, alpha: 1.0))
                    }

                    let attr = NSMutableAttributedString()
                    attr.append(NSAttributedString(string: tag, attributes: [
                        .foregroundColor: tagColor, .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
                    ]))
                    attr.append(NSAttributedString(string: "  \((file as NSString).lastPathComponent)", attributes: [
                        .foregroundColor: fileColor, .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                    ]))
                    entries.append((path: file, x: x, y: y, attr: attr))
                }
            }

            // 6. Project name from cwd
            let projectName = (cwd as NSString).lastPathComponent

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isGitRepo = isRepo
                self.currentBranch = branch
                self.ahead = aheadCount
                self.behind = behindCount
                self.hasRemote = hasRemote
                self.fileEntries = entries

                self.updateLayout(projectName: projectName)
                self.refreshGithubStatus(cwd: cwd)
            }
        }
    }

    // MARK: - Layout Update

    private func updateLayout(projectName: String) {
        // Header always visible
        projectLabel.stringValue = projectName
        if !currentBranch.isEmpty {
            branchBadge.stringValue = " \(currentBranch) "
            branchBadge.isHidden = false
        } else {
            branchBadge.isHidden = true
        }

        // Status summary in header
        if !isGitRepo {
            statusLabel.stringValue = "Kein Tracking — starte es mit dem Button"
            statusLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1.0)
        } else if fileEntries.isEmpty {
            statusLabel.stringValue = "✅  Alles gespeichert – nichts zu tun"
            statusLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.5, alpha: 1.0)
        } else {
            statusLabel.stringValue = "\(fileEntries.count) Datei\(fileEntries.count == 1 ? "" : "en") geändert"
            statusLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.3, alpha: 1.0)
        }

        // No-repo card
        noRepoCard.isHidden = isGitRepo

        // Files card
        filesCard.isHidden = !isGitRepo || fileEntries.isEmpty
        if isGitRepo {
            rebuildFilesStack()
        }

        // Commit card
        commitCard.isHidden = !isGitRepo

        // GitHub card
        githubCard.isHidden = !isGitRepo
        updateGithubCard()
    }

    // MARK: - Files Stack

    private func rebuildFilesStack() {
        let key = fileEntries.map { $0.path }.joined()
        guard key != lastFilesKey else { return }
        lastFilesKey = key
        expandedDiffFile = nil
        currentDiffView?.removeFromSuperview()
        currentDiffView = nil
        filesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for entry in fileEntries.prefix(30) {
            let row = ClickableFileRow()
            row.filePath = entry.path
            row.statusX = entry.x
            row.statusY = entry.y
            row.marqueeLabel.attributedText = entry.attr
            row.heightAnchor.constraint(equalToConstant: 18).isActive = true
            row.onClick = { [weak self] in self?.toggleDiff(for: entry.path, x: entry.x, y: entry.y) }
            filesStack.addArrangedSubview(row)
        }
    }

    private func toggleDiff(for filePath: String, x: Character, y: Character) {
        if expandedDiffFile == filePath {
            expandedDiffFile = nil
            currentDiffView?.removeFromSuperview()
            currentDiffView = nil
            return
        }
        currentDiffView?.removeFromSuperview()
        expandedDiffFile = filePath

        let args: [String]
        if "MADRC".contains(x) && x != " " && x != "?" {
            args = ["diff", "--cached", filePath]
        } else {
            args = ["diff", filePath]
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let diffOut = self.runGit(args, cwd: self.lastCwd) ?? "Kein Diff verfügbar"
            DispatchQueue.main.async {
                let diffView = self.makeDiffView(diffOut)
                if let idx = self.filesStack.arrangedSubviews.firstIndex(where: { ($0 as? ClickableFileRow)?.filePath == filePath }) {
                    self.filesStack.insertArrangedSubview(diffView, at: idx + 1)
                }
                self.currentDiffView = diffView
            }
        }
    }

    private func makeDiffView(_ diff: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isEditable = false
        label.isSelectable = true
        label.drawsBackground = false
        label.isBordered = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let attr = NSMutableAttributedString()
        for (i, line) in diff.split(separator: "\n", omittingEmptySubsequences: false).prefix(200).enumerated() {
            let s = String(line)
            let color: NSColor
            if s.hasPrefix("+++") || s.hasPrefix("---") { color = NSColor(calibratedWhite: 0.5, alpha: 1.0) }
            else if s.hasPrefix("+") { color = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.45, alpha: 1.0) }
            else if s.hasPrefix("-") { color = NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0) }
            else if s.hasPrefix("@@") { color = NSColor(calibratedRed: 0.5, green: 0.7, blue: 1.0, alpha: 1.0) }
            else { color = NSColor(calibratedWhite: 0.45, alpha: 1.0) }
            if i > 0 { attr.append(NSAttributedString(string: "\n")) }
            attr.append(NSAttributedString(string: s, attributes: [
                .foregroundColor: color, .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
            ]))
        }
        label.attributedStringValue = attr

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = label
        label.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
        let hug = scroll.heightAnchor.constraint(equalTo: label.heightAnchor)
        hug.priority = .defaultHigh
        hug.isActive = true
        scroll.heightAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.25).cgColor
        scroll.layer?.cornerRadius = 4
        return scroll
    }

    // MARK: - GitHub Card Update

    private func updateGithubCard() {
        let loggedIn = github.isAuthenticated
        githubAuthStack.isHidden = loggedIn
        githubConnectedStack.isHidden = !loggedIn
        if loggedIn {
            let user = github.username ?? "verbunden"
            githubUserLabel.stringValue = "🔗  @\(user)"
        }
    }

    private func refreshGithubStatus(cwd: String) {
        guard github.isAuthenticated, isGitRepo, hasRemote else {
            // Update sync label for no-auth or no-remote case
            if isGitRepo && !hasRemote && github.isAuthenticated {
                githubSyncLabel.stringValue = "Noch nicht hochgeladen"
                githubSyncLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
                uploadBtn.isHidden = false
                updateBtn.isHidden = true
            }
            return
        }

        // Sync label
        if ahead > 0 && behind > 0 {
            githubSyncLabel.stringValue = "↑ \(ahead) zu senden, ↓ \(behind) zu holen"
            githubSyncLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.7, blue: 0.3, alpha: 1.0)
        } else if ahead > 0 {
            githubSyncLabel.stringValue = "↑ \(ahead) Änderung\(ahead == 1 ? "" : "en") zu senden"
            githubSyncLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.35, alpha: 1.0)
        } else if behind > 0 {
            githubSyncLabel.stringValue = "↓ \(behind) neue Änderung\(behind == 1 ? "" : "en") verfügbar"
            githubSyncLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
        } else {
            githubSyncLabel.stringValue = "✓  Alles auf dem aktuellen Stand"
            githubSyncLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.5, alpha: 1.0)
        }

        uploadBtn.isHidden = ahead == 0
        updateBtn.isHidden = behind == 0
    }

    // MARK: - Feedback

    private func showFeedback(_ msg: String, success: Bool) {
        feedbackLabel.stringValue = msg
        feedbackLabel.textColor = success
            ? NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.5, alpha: 1.0)
            : NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        feedbackLabel.isHidden = false
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.feedbackLabel.isHidden = true
        }
    }

    // MARK: - Actions: Init

    @objc private func initRepoClicked() {
        let cwd = lastCwd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runGitAction(["init"], cwd: cwd)
            DispatchQueue.main.async {
                if result.success {
                    self.refresh()
                } else {
                    self.showFeedback("Fehler: \(result.output)", success: false)
                }
            }
        }
    }

    // MARK: - Actions: Save (Stage All + Commit)

    @objc private func saveClicked() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else {
            showFeedback("Bitte beschreibe zuerst was du geändert hast.", success: false)
            window?.makeFirstResponder(commitField)
            return
        }
        commitField.stringValue = ""
        commitField.isEnabled = false
        saveBtn.isEnabled = false
        let cwd = lastCwd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let stage = self.runGitAction(["add", "-A"], cwd: cwd)
            guard stage.success else {
                DispatchQueue.main.async {
                    self.showFeedback("Fehler: \(stage.output)", success: false)
                    self.commitField.isEnabled = true
                    self.saveBtn.isEnabled = true
                }
                return
            }
            let commit = self.runGitAction(["commit", "-m", msg], cwd: cwd)
            DispatchQueue.main.async {
                self.commitField.isEnabled = true
                self.saveBtn.isEnabled = true
                self.showFeedback(commit.success ? "✓  Gespeichert: \(msg)" : "Fehler: \(commit.output)", success: commit.success)
                self.refresh()
            }
        }
    }

    // MARK: - Actions: Upload (Push)

    @objc private func uploadClicked() {
        // If no remote: show new repo dialog
        if !hasRemote {
            showNewRepoOverlay()
            return
        }
        uploadBtn.isEnabled = false
        let cwd = lastCwd
        let branch = currentBranch
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runGitAction(["push", "-u", "origin", branch], cwd: cwd)
            DispatchQueue.main.async {
                self.uploadBtn.isEnabled = true
                self.showFeedback(result.success ? "✓  Hochgeladen!" : "Fehler: \(result.output)", success: result.success)
                self.github.cache.lastFetch = .distantPast
                self.refresh()
            }
        }
    }

    // MARK: - Actions: Update (Pull)

    @objc private func updateClicked() {
        updateBtn.isEnabled = false
        let cwd = lastCwd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runGitAction(["pull"], cwd: cwd)
            DispatchQueue.main.async {
                self.updateBtn.isEnabled = true
                self.showFeedback(result.success ? "✓  Aktualisiert!" : "Fehler: \(result.output)", success: result.success)
                self.github.cache.lastFetch = .distantPast
                self.refresh()
            }
        }
    }

    // MARK: - Actions: GitHub Auth

    @objc private func saveTokenClicked() {
        let value = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        tokenSaveBtn.title = "Prüfe..."
        tokenSaveBtn.isEnabled = false
        github.setToken(value)
        github.fetchUser { [weak self] username in
            guard let self = self else { return }
            if username != nil {
                self.tokenField.stringValue = ""
                self.updateGithubCard()
                self.refresh()
            } else {
                self.github.logout()
                self.showFeedback("Ungültiges Token — bitte nochmal versuchen", success: false)
            }
            self.tokenSaveBtn.title = "Verbinden"
            self.tokenSaveBtn.isEnabled = true
        }
    }

    @objc private func openTokenPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=quickTerminal")!)
    }

    @objc private func disconnectClicked() {
        github.logout()
        updateGithubCard()
    }

    // MARK: - New Repo Overlay

    private func showNewRepoOverlay() {
        let name = (lastCwd as NSString).lastPathComponent
        repoNameField.stringValue = name
        newRepoOverlayVisible = true
        newRepoOverlay.isHidden = false
        newRepoOverlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.newRepoOverlay.animator().alphaValue = 1
        }
        window?.makeFirstResponder(repoNameField)
    }

    @objc private func cancelNewRepo() {
        newRepoOverlayVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.newRepoOverlay.animator().alphaValue = 0
        }, completionHandler: {
            self.newRepoOverlay.isHidden = true
        })
    }

    @objc private func repoVisibilityChanged(_ sender: NSButton) {
        repoIsPrivate = sender === repoPrivateBtn
        repoPublicBtn.state = repoIsPrivate ? .off : .on
        repoPrivateBtn.state = repoIsPrivate ? .on : .off
    }

    @objc private func createRepoClicked() {
        var name = repoNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            repoCreateBtn.shake()
            return
        }
        // Sanitize: replace spaces/invalid with dashes
        name = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        repoCreateBtn.isEnabled = false
        repoCreateBtn.title = "Wird erstellt..."

        let cwd = lastCwd
        let branch = currentBranch.isEmpty ? "main" : currentBranch
        let isPrivate = repoIsPrivate

        github.createRepo(name: name, isPrivate: isPrivate) { [weak self] success, cloneURLOrError in
            guard let self = self else { return }
            if success, let cloneURL = cloneURLOrError {
                // Add remote + push
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = self.runGitAction(["remote", "add", "origin", cloneURL], cwd: cwd)
                    let push = self.runGitAction(["push", "-u", "origin", branch], cwd: cwd)
                    DispatchQueue.main.async {
                        self.repoCreateBtn.isEnabled = true
                        self.repoCreateBtn.title = "✔  Erstellen & Hochladen"
                        self.cancelNewRepo()
                        self.showFeedback(push.success ? "✓  Projekt auf GitHub erstellt & hochgeladen!" : "Repo erstellt, Push fehlgeschlagen: \(push.output)", success: push.success)
                        self.github.cache.lastFetch = .distantPast
                        self.refresh()
                    }
                }
            } else {
                self.repoCreateBtn.isEnabled = true
                self.repoCreateBtn.title = "✔  Erstellen & Hochladen"
                self.showFeedback("Fehler: \(cloneURLOrError ?? "Unbekannter Fehler")", success: false)
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        feedbackTimer?.invalidate()
    }
}

// MARK: - NSButton shake animation helper
private extension NSButton {
    func shake() {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.duration = 0.35
        anim.values = [-8, 8, -6, 6, -4, 4, 0]
        layer?.add(anim, forKey: "shake")
    }
}
```

**Step 2: Build testen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh 2>&1 | tail -20
```

Erwartetes Ergebnis: Keine Fehler. Falls Fehler auftreten: genau lesen und beheben.

**Häufige Fehler & Fixes:**

- `'shake' is not a member of 'NSButton'` → Die Extension am Ende der Klasse prüfen
- `Cannot find type 'GitHubClient'` → Prüfen ob der Block korrekt eingefügt wurde (nicht zu viel gelöscht)
- `Cannot find 'ClickableFileRow'` → Sicherstellen dass die Klassen vor `GitPanelView` noch existieren (Zeilen 7531–7571)

**Step 3: Commit**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
git add quickTerminal.swift
git commit -m "feat: replace GitPanelView with simplified redesign"
```

---

## Task 3: `GitHubKeychainStore` PATH-Fix für gh CLI (optional)

**Context:** Der `runGit()` Helper in der neuen GitPanelView hat bereits `/opt/homebrew/bin` im PATH. Falls `gh` CLI an einem ungewöhnlichen Ort liegt, kann `ghCliToken()` in `GitHubClient` scheitern. Das ist aber meist kein Problem — Token-Fallback deckt das ab.

**Step 1: Verify gh CLI Detection**

Prüfe im Terminal:
```bash
which gh
gh auth token
```

Falls `gh` vorhanden ist und ein Token zurückgibt: Auto-Login funktioniert, Task abgeschlossen.

Falls nicht: Kein Fix nötig — Benutzer kann Token manuell eingeben.

---

## Task 4: App Bundle bauen und manuell testen

**Step 1: App Bundle bauen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build_app.sh 2>&1 | tail -10
```

**Step 2: Starten**

```bash
open quickTerminal.app
```

**Step 3: Manuell testen — Checkliste**

Folgende Szenarien nacheinander prüfen:

1. **Kein Git-Repo:** In einem leeren Ordner navigieren → Git-Panel öffnen → Card "Noch kein Projekt-Tracking" erscheint → Button "🚀 Mit Tracking starten" klicken → Panel zeigt jetzt Dateikarten
2. **Dateien ändern:** Datei in Ordner erstellen → Panel zeigt "1 Datei geändert" in Header → `GEÄNDERT`-Tag in Dateiliste → Datei anklicken → Diff klappt auf
3. **Speichern:** Beschreibung eingeben → "💾 Speichern" klicken → Grünes Feedback erscheint
4. **GitHub auth:** Token einfügen → "Verbinden" → @username erscheint
5. **Repo erstellen:** "Auf GitHub hochladen" ohne Remote → Dialog erscheint → Name eingeben → Privat → "Erstellen & Hochladen" → Feedback erscheint
6. **Pull:** Behind-Commits simulieren → "Aktualisieren" erscheint → klicken → Erfolg
7. **Clean state:** Nach Push → Header zeigt "✅ Alles gespeichert – nichts zu tun"

**Step 4: Commit wenn alles ok**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
git add -A
git commit -m "feat: git panel redesign complete"
```

---

## Task 5: Version bumpen und ZIP bauen

**Step 1: Version in quickTerminal.swift erhöhen**

In `quickTerminal.swift` Zeile 12:
```swift
let kAppVersion = "1.3.0"
```

**Step 2: Version in allen Build-Skripten anpassen**

In `build.sh`, `build_app.sh`, `build_zip.sh`:
- Suche `VERSION` oder `1.2.1` und ersetze durch `1.3.0`

**Step 3: ZIP bauen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build_zip.sh
```

**Step 4: Final commit**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
git add -A
git commit -m "v1.3.0: Git Panel complete redesign — simplified UX, GitHub repo creation, git init"
```

---

## Zusammenfassung

| Task | Was | Zeilen |
|---|---|---|
| 1 | `createRepo()` zu GitHubClient | vor Z. 6908 |
| 2 | Gesamte `GitPanelView` ersetzen | Z. 7573–9295 |
| 3 | gh CLI PATH prüfen (optional) | — |
| 4 | Manuell testen | — |
| 5 | Version bumpen, ZIP bauen | Z. 12, build-skripte |
