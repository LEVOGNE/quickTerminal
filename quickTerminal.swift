// quickTerminal.swift — A simple native terminal emulator for macOS
// Build: swiftc -O quickTerminal.swift -o quickTerminal -framework Cocoa

import Cocoa
import Carbon
import Darwin
import Darwin.POSIX
import Security
import AVKit

// MARK: - Version

let kAppVersion = "1.4.1"

func isNewerVersion(remote: String, local: String) -> Bool {
    let strip: (String) -> String = { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
    let rParts = strip(remote).split(separator: ".").compactMap { Int($0) }
    let lParts = strip(local).split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(rParts.count, lParts.count) {
        let r = i < rParts.count ? rParts[i] : 0
        let l = i < lParts.count ? lParts[i] : 0
        if r > l { return true }
        if r < l { return false }
    }
    return false
}

// MARK: - Types

struct TextAttrs: Equatable {
    var fg: Int = 7
    var bg: Int = 0
    var bold = false
    var dim = false
    var italic = false
    var underline: UInt8 = 0  // 0=none, 1=single, 2=double, 3=curly, 4=dotted, 5=dashed
    var blink: UInt8 = 0      // 0=none, 1=slow, 2=rapid
    var inverse = false
    var hidden = false
    var strikethrough = false
    var overline = false
    var fgRGB: (UInt8, UInt8, UInt8)? = nil
    var bgRGB: (UInt8, UInt8, UInt8)? = nil
    var ulColor: Int16 = -1  // underline color: -1=default (use fg), 0-255=palette
    var ulRGB: (UInt8, UInt8, UInt8)? = nil
    var protected = false    // DECSCA character protection

    static func == (lhs: TextAttrs, rhs: TextAttrs) -> Bool {
        lhs.fg == rhs.fg && lhs.bg == rhs.bg && lhs.bold == rhs.bold &&
        lhs.dim == rhs.dim && lhs.italic == rhs.italic &&
        lhs.underline == rhs.underline && lhs.blink == rhs.blink &&
        lhs.inverse == rhs.inverse &&
        lhs.hidden == rhs.hidden && lhs.strikethrough == rhs.strikethrough &&
        lhs.overline == rhs.overline && lhs.protected == rhs.protected &&
        lhs.fgRGB?.0 == rhs.fgRGB?.0 && lhs.fgRGB?.1 == rhs.fgRGB?.1 && lhs.fgRGB?.2 == rhs.fgRGB?.2 &&
        lhs.bgRGB?.0 == rhs.bgRGB?.0 && lhs.bgRGB?.1 == rhs.bgRGB?.1 && lhs.bgRGB?.2 == rhs.bgRGB?.2 &&
        lhs.ulColor == rhs.ulColor &&
        lhs.ulRGB?.0 == rhs.ulRGB?.0 && lhs.ulRGB?.1 == rhs.ulRGB?.1 && lhs.ulRGB?.2 == rhs.ulRGB?.2
    }
}

struct Cell {
    var char: Unicode.Scalar = " "
    var attrs = TextAttrs()
    var width: UInt8 = 1  // 1=normal, 2=wide (this cell is the left half), 0=continuation (right half of wide char)
    var hyperlink: String? = nil  // OSC 8 hyperlink URL
}

struct CursorState {
    var x: Int = 0
    var y: Int = 0
    var pendingWrap: Bool = false
}

// MARK: - Localization

extension Notification.Name {
    static let appLanguageChanged = Notification.Name("qtLanguageChanged")
}

enum Loc {
    static var lang: String {
        get { UserDefaults.standard.string(forKey: "appLanguage").flatMap { $0.isEmpty ? nil : $0 } ?? Loc.systemLang }
        set { UserDefaults.standard.set(newValue, forKey: "appLanguage") }
    }
    static var systemLang: String {
        let code = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        return supported.contains(code) ? code : "en"
    }
    static let supported = ["en","de","tr","es","fr","it","ar","ja","zh","ru"]
    static let flags     = ["en":"🇬🇧","de":"🇩🇪","tr":"🇹🇷","es":"🇪🇸","fr":"🇫🇷",
                            "it":"🇮🇹","ar":"🇸🇦","ja":"🇯🇵","zh":"🇨🇳","ru":"🇷🇺"]
    static let names     = ["en":"English","de":"Deutsch","tr":"Türkçe","es":"Español",
                            "fr":"Français","it":"Italiano","ar":"العربية",
                            "ja":"日本語","zh":"中文","ru":"Русский"]

    static func t(_ k: String) -> String {
        strings[lang]?[k] ?? strings["en"]![k] ?? k
    }

    // MARK: Settings
    static var language: String     { t("language") }
    static var opacity: String      { t("opacity") }
    static var blur: String         { t("blur") }
    static var fontSize: String     { t("fontSize") }
    static var cursor: String       { t("cursor") }
    static var cursorBlink: String  { t("cursorBlink") }
    static var font: String         { t("font") }
    static var syntaxHighlight: String { t("syntaxHighlight") }
    static var defaultShell: String { t("defaultShell") }
    static var colorThemeSection: String { t("colorThemeSection") }
    static var windowSection: String { t("windowSection") }
    static var alwaysOnTop: String  { t("alwaysOnTop") }
    static var followAllSpaces: String { t("followAllSpaces") }
    static var autoDim: String      { t("autoDim") }
    static var hideOnClickOutside: String { t("hideOnClickOutside") }
    static var hideOnDeactivate: String   { t("hideOnDeactivate") }
    static var copyOnSelect: String { t("copyOnSelect") }
    static var launchAtLogin: String { t("launchAtLogin") }
    static var autoCheckUpdates: String { t("autoCheckUpdates") }
    static var webpickerSection: String { t("webpickerSection") }
    static var browser: String      { t("browser") }
    static var claudeSection: String { t("claudeSection") }
    static var showUsageBadge: String { t("showUsageBadge") }
    static var refresh: String      { t("refresh") }
    static var status: String       { t("status") }
    static var connected: String    { t("connected") }
    static var noToken: String      { t("noToken") }
    static var resetToDefaults: String { t("resetToDefaults") }
    static var sure: String         { t("sure") }
    static var sendFeedback: String { t("sendFeedback") }
    static var sent: String         { t("sent") }
    // MARK: WebPicker
    static var notConnected: String { t("notConnected") }
    static var connecting: String   { t("connecting") }
    static var openingTab: String   { t("openingTab") }
    static var navigateTo: String   { t("navigateTo") }
    static var verbunden: String    { t("verbunden") }
    static var disconnect: String   { t("disconnect") }
    static var pickElement: String  { t("pickElement") }
    static var connectToChrome: String { t("connectToChrome") }
    static var resetMarks: String   { t("resetMarks") }
    static var picks: String        { t("picks") }
    static var chromeNotReachable: String { t("chromeNotReachable") }
    static var connectionLost: String { t("connectionLost") }
    static var connectionFailed: String { t("connectionFailed") }
    static var tabClosed: String    { t("tabClosed") }
    static var waitingForClick: String { t("waitingForClick") }
    // MARK: Git
    static var noProjectYet: String { t("noProjectYet") }
    static var clickToStartTracking: String { t("clickToStartTracking") }
    static var startTracking: String { t("startTracking") }
    static var changedFiles: String { t("changedFiles") }
    static var whatChanged: String  { t("whatChanged") }
    static var commitPlaceholder: String { t("commitPlaceholder") }
    static var save: String         { t("save") }
    static var notConnectedGH: String { t("notConnectedGH") }
    static var pasteToken: String   { t("pasteToken") }
    static var connect: String      { t("connect") }
    static var createToken: String  { t("createToken") }
    static var uploadGH: String     { t("uploadGH") }
    static var updateGH: String     { t("updateGH") }
    static var logout: String       { t("logout") }
    static var createProject: String { t("createProject") }
    static var projectNamePlaceholder: String { t("projectNamePlaceholder") }
    static var visibility: String   { t("visibility") }
    static var public_: String      { t("public_") }
    static var private_: String     { t("private_") }
    static var createAndUpload: String { t("createAndUpload") }
    static var cancel: String       { t("cancel") }
    static var noTracking: String   { t("noTracking") }
    static var allSaved: String     { t("allSaved") }
    static func filesChanged(_ n: Int) -> String { String(format: t("filesChanged"), n, n == 1 ? "" : t("filesChangedPlural")) }
    static var describeChanges: String { t("describeChanges") }
    static var invalidToken: String { t("invalidToken") }
    static var savedMsg: String     { t("savedMsg") }
    static var uploaded: String     { t("uploaded") }
    static var updated: String      { t("updated") }
    static var projectCreated: String { t("projectCreated") }
    static var creating: String     { t("creating") }
    static var checking: String     { t("checking") }
    static var notYetUploaded: String { t("notYetUploaded") }
    static func aheadBehind(_ a: Int, _ b: Int) -> String { String(format: t("aheadBehind"), a, b) }
    static func aheadOnly(_ a: Int) -> String { String(format: t("aheadOnly"), a, a == 1 ? "" : "s") }
    static func behindOnly(_ b: Int) -> String { String(format: t("behindOnly"), b, b == 1 ? "" : "s") }
    static var upToDate: String     { t("upToDate") }
    // MARK: Toasts / Alerts
    static var noUpdateAvailable: String { t("noUpdateAvailable") }
    static var updateAvailable: String { t("updateAvailable") }
    static var onlyWithAppBundle: String { t("onlyWithAppBundle") }
    static var alreadyUpToDate: String { t("alreadyUpToDate") }
    static var checkFailed: String  { t("checkFailed") }
    static var updateInstalled: String { t("updateInstalled") }
    static var fullDiskAccess: String { t("fullDiskAccess") }
    static var fullDiskAccessMsg: String { t("fullDiskAccessMsg") }
    static var openSettings: String { t("openSettings") }
    static var later: String        { t("later") }
    // MARK: Context Menu
    static var copy: String         { t("copy") }
    static var paste: String        { t("paste") }
    static var selectAll: String    { t("selectAll") }
    static var clear: String        { t("clear") }
    static var newTab: String       { t("newTab") }
    static var showHide: String     { t("showHide") }
    static var detachWindow: String { t("detachWindow") }
    static var reattachWindow: String { t("reattachWindow") }
    static var quitApp: String      { t("quitApp") }
    static var splitVertical: String   { t("splitVertical") }
    static var splitHorizontal: String { t("splitHorizontal") }
    static var panels: String       { t("panels") }

    // MARK: SSH
    static var sshNewConn: String   { t("sshNewConn") }
    static var sshNoSaved: String   { t("sshNoSaved") }
    static var sshNamePh: String    { t("sshNamePh") }
    static var sshConnPh: String    { t("sshConnPh") }
    static var sshKeyPh: String     { t("sshKeyPh") }

    // MARK: - Translation Table
    static let strings: [String: [String: String]] = [
        "en": [
            "language": "LANGUAGE",
            "opacity": "Opacity", "blur": "Blur", "fontSize": "Font Size",
            "cursor": "Cursor", "cursorBlink": "Cursor Blink", "font": "Font",
            "syntaxHighlight": "Syntax Highlighting", "defaultShell": "Default Shell",
            "colorThemeSection": "COLOR THEME",
            "windowSection": "Window", "alwaysOnTop": "Always on Top", "followAllSpaces": "Follow All Spaces", "autoDim": "Auto-Dim",
            "hideOnClickOutside": "Hide on Click Outside", "hideOnDeactivate": "Hide on Deactivate",
            "copyOnSelect": "Copy on Select", "launchAtLogin": "Launch at Login",
            "autoCheckUpdates": "Auto-Check Updates", "webpickerSection": "WebPicker",
            "browser": "Browser", "claudeSection": "Claude Code", "showUsageBadge": "Show Usage Badge",
            "refresh": "Refresh", "status": "Status", "connected": "Connected",
            "noToken": "No Claude Code Token", "resetToDefaults": "Reset to Defaults",
            "sure": "Sure?", "sendFeedback": "Send Feedback", "sent": "✓ Sent!",
            "notConnected": "Not connected", "connecting": "Connecting...",
            "openingTab": "Opening new tab...", "navigateTo": "Navigate to a website",
            "verbunden": "Connected", "disconnect": "⏏ Disconnect",
            "pickElement": "✦  Pick Element", "connectToChrome": "  ⊕  Connect to Chrome",
            "resetMarks": "⌫ Reset Marks", "picks": "PICKS",
            "chromeNotReachable": "Chrome not reachable", "connectionLost": "Connection lost",
            "connectionFailed": "Connection failed", "tabClosed": "Tab was closed",
            "waitingForClick": "Waiting for click...",
            "noProjectYet": "No project tracking yet",
            "clickToStartTracking": "Click the button to start tracking this folder.",
            "startTracking": "Start Tracking", "changedFiles": "CHANGED FILES",
            "whatChanged": "WHAT DID YOU CHANGE?",
            "commitPlaceholder": "e.g. Improved login page, fixed bug...",
            "save": "💾  Save", "notConnectedGH": "🔗  Not connected to GitHub",
            "pasteToken": "Paste GitHub token (ghp_...)", "connect": "Connect",
            "createToken": "Create token →", "uploadGH": "↑  Upload to GitHub",
            "updateGH": "↓  Update", "logout": "Logout",
            "createProject": "Create new GitHub project", "projectNamePlaceholder": "project-name",
            "visibility": "Visibility:", "public_": "Public", "private_": "Private",
            "createAndUpload": "✔  Create & Upload", "cancel": "Cancel",
            "noTracking": "No tracking — start it with the button",
            "allSaved": "✅  All saved — nothing to do",
            "filesChanged": "%d file%@ changed", "filesChangedPlural": "s",
            "describeChanges": "Please describe what you changed first.",
            "invalidToken": "Invalid token — please try again",
            "savedMsg": "✓  Saved", "uploaded": "✓  Uploaded!", "updated": "✓  Updated!",
            "projectCreated": "✓  Project created & uploaded to GitHub!",
            "creating": "Creating...", "checking": "Checking...",
            "notYetUploaded": "Not yet uploaded",
            "aheadBehind": "↑ %d to push, ↓ %d to pull",
            "aheadOnly": "↑ %d change%@ to push", "behindOnly": "↓ %d new change%@ available",
            "upToDate": "✓  All up to date",
            "noUpdateAvailable": "No update available",
            "updateAvailable": "%@ available — click to install",
            "onlyWithAppBundle": "Only works with .app bundle",
            "alreadyUpToDate": "Already up to date (v%@)",
            "checkFailed": "Check failed — try again later",
            "updateInstalled": "Update installed — restarting…",
            "fullDiskAccess": "Full Disk Access",
            "fullDiskAccessMsg": "quickTERMINAL works best with Full Disk Access so your shell can navigate the entire filesystem.\n\nGrant access in:\nSystem Settings → Privacy & Security → Full Disk Access",
            "openSettings": "Open Settings", "later": "Later",
            "copy": "Copy", "paste": "Paste", "selectAll": "Select All", "clear": "Clear",
            "newTab": "New Tab", "splitVertical": "Split Vertical", "splitHorizontal": "Split Horizontal", "panels": "Panels",
            "showHide": "Show / Hide", "detachWindow": "Detach Window", "reattachWindow": "Reattach Window", "quitApp": "Quit quickTerminal",
            "sshNewConn": "NEW CONNECTION", "sshNoSaved": "No saved connections",
            "sshNamePh": "Name  (optional, e.g. Production)",
            "sshConnPh": "user@host  or  user@host:port  *",
            "sshKeyPh": "~/.ssh/id_rsa  (optional – leave empty for password auth)",
        ],
        "de": [
            "language": "SPRACHE",
            "opacity": "Deckkraft", "blur": "Unschärfe", "fontSize": "Schriftgröße",
            "cursor": "Cursor", "cursorBlink": "Cursor blinkt", "font": "Schrift",
            "syntaxHighlight": "Syntax-Hervorhebung", "defaultShell": "Standard-Shell",
            "colorThemeSection": "FARBSCHEMA",
            "windowSection": "Fenster", "alwaysOnTop": "Immer im Vordergrund", "followAllSpaces": "Allen Spaces folgen", "autoDim": "Auto-Dimmen",
            "hideOnClickOutside": "Bei Klick außen ausblenden", "hideOnDeactivate": "Bei Deaktivierung ausblenden",
            "copyOnSelect": "Kopieren bei Auswahl", "launchAtLogin": "Beim Start öffnen",
            "autoCheckUpdates": "Updates automatisch prüfen", "webpickerSection": "WebPicker",
            "browser": "Browser", "claudeSection": "Claude Code", "showUsageBadge": "Nutzungs-Badge anzeigen",
            "refresh": "Aktualisieren", "status": "Status", "connected": "Verbunden",
            "noToken": "Kein Claude Code Token", "resetToDefaults": "Auf Standard zurücksetzen",
            "sure": "Sicher?", "sendFeedback": "Feedback senden", "sent": "✓ Gesendet!",
            "notConnected": "Nicht verbunden", "connecting": "Verbinde...",
            "openingTab": "Neuen Tab öffnen...", "navigateTo": "Webseite aufrufen",
            "verbunden": "Verbunden", "disconnect": "⏏ Trennen",
            "pickElement": "✦  Element wählen", "connectToChrome": "  ⊕  Mit Chrome verbinden",
            "resetMarks": "⌫ Markierungen löschen", "picks": "AUSWAHL",
            "chromeNotReachable": "Chrome nicht erreichbar", "connectionLost": "Verbindung unterbrochen",
            "connectionFailed": "Verbindung fehlgeschlagen", "tabClosed": "Tab wurde geschlossen",
            "waitingForClick": "Warte auf Klick...",
            "noProjectYet": "Noch kein Projekt-Tracking",
            "clickToStartTracking": "Klicke auf den Button um diesen Ordner zu verfolgen.",
            "startTracking": "Tracking starten", "changedFiles": "GEÄNDERTE DATEIEN",
            "whatChanged": "WAS HAST DU GEÄNDERT?",
            "commitPlaceholder": "z.B. Login-Seite verbessert, Bug behoben...",
            "save": "💾  Speichern", "notConnectedGH": "🔗  Nicht mit GitHub verbunden",
            "pasteToken": "GitHub Token einfügen (ghp_...)", "connect": "Verbinden",
            "createToken": "Token erstellen →", "uploadGH": "↑  Auf GitHub hochladen",
            "updateGH": "↓  Aktualisieren", "logout": "Abmelden",
            "createProject": "Neues GitHub-Projekt erstellen", "projectNamePlaceholder": "projekt-name",
            "visibility": "Sichtbarkeit:", "public_": "Öffentlich", "private_": "Privat",
            "createAndUpload": "✔  Erstellen & Hochladen", "cancel": "Abbrechen",
            "noTracking": "Kein Tracking — starte es mit dem Button",
            "allSaved": "✅  Alles gespeichert — nichts zu tun",
            "filesChanged": "%d Datei%@ geändert", "filesChangedPlural": "en",
            "describeChanges": "Bitte beschreibe zuerst was du geändert hast.",
            "invalidToken": "Ungültiger Token — bitte erneut versuchen",
            "savedMsg": "✓  Gespeichert", "uploaded": "✓  Hochgeladen!", "updated": "✓  Aktualisiert!",
            "projectCreated": "✓  Projekt erstellt & auf GitHub hochgeladen!",
            "creating": "Erstelle...", "checking": "Prüfe...",
            "notYetUploaded": "Noch nicht hochgeladen",
            "aheadBehind": "↑ %d zu senden, ↓ %d zu holen",
            "aheadOnly": "↑ %d Änderung%@ zu pushen", "behindOnly": "↓ %d neue Änderung%@ verfügbar",
            "upToDate": "✓  Alles auf dem aktuellen Stand",
            "noUpdateAvailable": "Kein Update verfügbar",
            "updateAvailable": "%@ verfügbar — zum Installieren klicken",
            "onlyWithAppBundle": "Nur mit .app Bundle möglich",
            "alreadyUpToDate": "Bereits aktuell (v%@)",
            "checkFailed": "Prüfung fehlgeschlagen — später erneut versuchen",
            "updateInstalled": "Update installiert — startet neu…",
            "fullDiskAccess": "Vollständiger Festplattenzugriff",
            "fullDiskAccessMsg": "quickTERMINAL funktioniert am besten mit vollständigem Festplattenzugriff.\n\nZugriff gewähren unter:\nSystemeinstellungen → Datenschutz & Sicherheit → Voller Festplattenzugriff",
            "openSettings": "Einstellungen öffnen", "later": "Später",
            "copy": "Kopieren", "paste": "Einfügen", "selectAll": "Alles auswählen", "clear": "Leeren",
            "newTab": "Neuer Tab", "splitVertical": "Vertikal teilen", "splitHorizontal": "Horizontal teilen", "panels": "Panels",
            "showHide": "Einblenden / Ausblenden", "detachWindow": "Fenster lösen", "reattachWindow": "Fenster andocken", "quitApp": "quickTerminal beenden",
            "sshNewConn": "NEUE VERBINDUNG", "sshNoSaved": "Keine gespeicherten Verbindungen",
            "sshNamePh": "Name  (optional, z.B. Produktion)",
            "sshConnPh": "user@host  oder  user@host:port  *",
            "sshKeyPh": "~/.ssh/id_rsa  (optional – leer lassen für Passwort-Auth)",
        ],
        "tr": [
            "language": "DİL",
            "opacity": "Saydamlık", "blur": "Bulanıklık", "fontSize": "Yazı Boyutu",
            "cursor": "İmleç", "cursorBlink": "İmleç Yanıp Sönme", "font": "Yazı Tipi",
            "syntaxHighlight": "Sözdizimi Vurgulama", "defaultShell": "Varsayılan Kabuk",
            "colorThemeSection": "RENK TEMASI",
            "windowSection": "Pencere", "alwaysOnTop": "Her Zaman Üstte", "followAllSpaces": "Tüm Alanlarda Görün", "autoDim": "Otomatik Karart",
            "hideOnClickOutside": "Dış Tıklamada Gizle", "hideOnDeactivate": "Devre Dışında Gizle",
            "copyOnSelect": "Seçimde Kopyala", "launchAtLogin": "Girişte Başlat",
            "autoCheckUpdates": "Güncellemeleri Otomatik Kontrol Et", "webpickerSection": "WebPicker",
            "browser": "Tarayıcı", "claudeSection": "Claude Code", "showUsageBadge": "Kullanım Rozeti",
            "refresh": "Yenile", "status": "Durum", "connected": "Bağlı",
            "noToken": "Claude Code Token Yok", "resetToDefaults": "Varsayılanlara Sıfırla",
            "sure": "Emin misin?", "sendFeedback": "Geri Bildirim Gönder", "sent": "✓ Gönderildi!",
            "notConnected": "Bağlı değil", "connecting": "Bağlanıyor...",
            "openingTab": "Yeni sekme açılıyor...", "navigateTo": "Bir web sitesine git",
            "verbunden": "Bağlı", "disconnect": "⏏ Bağlantıyı Kes",
            "pickElement": "✦  Öğe Seç", "connectToChrome": "  ⊕  Chrome'a Bağlan",
            "resetMarks": "⌫ İşaretleri Sıfırla", "picks": "SEÇİMLER",
            "chromeNotReachable": "Chrome erişilemiyor", "connectionLost": "Bağlantı kesildi",
            "connectionFailed": "Bağlantı başarısız", "tabClosed": "Sekme kapatıldı",
            "waitingForClick": "Tıklama bekleniyor...",
            "noProjectYet": "Henüz proje takibi yok",
            "clickToStartTracking": "Bu klasörü takip etmek için düğmeye tıklayın.",
            "startTracking": "Takibi Başlat", "changedFiles": "DEĞİŞEN DOSYALAR",
            "whatChanged": "NE DEĞİŞTİRDİN?",
            "commitPlaceholder": "örn. Giriş sayfası iyileştirildi, hata düzeltildi...",
            "save": "💾  Kaydet", "notConnectedGH": "🔗  GitHub'a bağlı değil",
            "pasteToken": "GitHub tokenini yapıştır (ghp_...)", "connect": "Bağlan",
            "createToken": "Token oluştur →", "uploadGH": "↑  GitHub'a Yükle",
            "updateGH": "↓  Güncelle", "logout": "Çıkış Yap",
            "createProject": "Yeni GitHub projesi oluştur", "projectNamePlaceholder": "proje-adı",
            "visibility": "Görünürlük:", "public_": "Genel", "private_": "Özel",
            "createAndUpload": "✔  Oluştur & Yükle", "cancel": "İptal",
            "noTracking": "Takip yok — düğmeyle başlat",
            "allSaved": "✅  Hepsi kaydedildi — yapılacak bir şey yok",
            "filesChanged": "%d dosya%@ değişti", "filesChangedPlural": "",
            "describeChanges": "Lütfen önce ne değiştirdiğini açıkla.",
            "invalidToken": "Geçersiz token — lütfen tekrar dene",
            "savedMsg": "✓  Kaydedildi", "uploaded": "✓  Yüklendi!", "updated": "✓  Güncellendi!",
            "projectCreated": "✓  Proje oluşturuldu & GitHub'a yüklendi!",
            "creating": "Oluşturuluyor...", "checking": "Kontrol ediliyor...",
            "notYetUploaded": "Henüz yüklenmedi",
            "aheadBehind": "↑ %d gönderilecek, ↓ %d alınacak",
            "aheadOnly": "↑ %d değişiklik%@ gönderilecek", "behindOnly": "↓ %d yeni değişiklik%@ mevcut",
            "upToDate": "✓  Her şey güncel",
            "noUpdateAvailable": "Güncelleme yok",
            "updateAvailable": "%@ mevcut — yüklemek için tıkla",
            "onlyWithAppBundle": "Yalnızca .app paketi ile çalışır",
            "alreadyUpToDate": "Zaten güncel (v%@)",
            "checkFailed": "Kontrol başarısız — daha sonra tekrar dene",
            "updateInstalled": "Güncelleme yüklendi — yeniden başlatılıyor…",
            "fullDiskAccess": "Tam Disk Erişimi",
            "fullDiskAccessMsg": "quickTERMINAL, tam disk erişimiyle en iyi şekilde çalışır.\n\nErişim ver:\nSistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi",
            "openSettings": "Ayarları Aç", "later": "Sonra",
            "copy": "Kopyala", "paste": "Yapıştır", "selectAll": "Tümünü Seç", "clear": "Temizle",
            "newTab": "Yeni Sekme", "splitVertical": "Dikey Böl", "splitHorizontal": "Yatay Böl", "panels": "Paneller",
            "showHide": "Göster / Gizle", "detachWindow": "Pencereyi Ayır", "reattachWindow": "Pencereyi Yerleştir", "quitApp": "quickTerminal'i Kapat",
            "sshNewConn": "YENİ BAĞLANTI", "sshNoSaved": "Kayıtlı bağlantı yok",
            "sshNamePh": "Ad  (isteğe bağlı, örn. Üretim)",
            "sshConnPh": "kullanıcı@host  veya  kullanıcı@host:port  *",
            "sshKeyPh": "~/.ssh/id_rsa  (isteğe bağlı – şifre için boş bırakın)",
        ],
        "es": [
            "language": "IDIOMA",
            "opacity": "Opacidad", "blur": "Desenfoque", "fontSize": "Tamaño de Fuente",
            "cursor": "Cursor", "cursorBlink": "Parpadeo del Cursor", "font": "Fuente",
            "syntaxHighlight": "Resaltado de Sintaxis", "defaultShell": "Shell Predeterminado",
            "colorThemeSection": "TEMA DE COLOR",
            "windowSection": "Ventana", "alwaysOnTop": "Siempre Visible", "followAllSpaces": "Seguir Todos los Espacios", "autoDim": "Auto-Atenuar",
            "hideOnClickOutside": "Ocultar al Hacer Clic Fuera", "hideOnDeactivate": "Ocultar al Desactivar",
            "copyOnSelect": "Copiar al Seleccionar", "launchAtLogin": "Iniciar al Entrar",
            "autoCheckUpdates": "Buscar Actualizaciones Automáticamente", "webpickerSection": "WebPicker",
            "browser": "Navegador", "claudeSection": "Claude Code", "showUsageBadge": "Mostrar Insignia de Uso",
            "refresh": "Actualizar", "status": "Estado", "connected": "Conectado",
            "noToken": "Sin Token de Claude Code", "resetToDefaults": "Restablecer Valores",
            "sure": "¿Seguro?", "sendFeedback": "Enviar Comentarios", "sent": "✓ ¡Enviado!",
            "notConnected": "No conectado", "connecting": "Conectando...",
            "openingTab": "Abriendo nueva pestaña...", "navigateTo": "Navegar a un sitio web",
            "verbunden": "Conectado", "disconnect": "⏏ Desconectar",
            "pickElement": "✦  Seleccionar Elemento", "connectToChrome": "  ⊕  Conectar a Chrome",
            "resetMarks": "⌫ Borrar Marcas", "picks": "SELECCIONES",
            "chromeNotReachable": "Chrome no disponible", "connectionLost": "Conexión perdida",
            "connectionFailed": "Conexión fallida", "tabClosed": "Pestaña cerrada",
            "waitingForClick": "Esperando clic...",
            "noProjectYet": "Aún sin seguimiento de proyecto",
            "clickToStartTracking": "Haz clic en el botón para rastrear esta carpeta.",
            "startTracking": "Iniciar Seguimiento", "changedFiles": "ARCHIVOS CAMBIADOS",
            "whatChanged": "¿QUÉ CAMBIASTE?",
            "commitPlaceholder": "ej. Mejoré la página de inicio, arreglé un error...",
            "save": "💾  Guardar", "notConnectedGH": "🔗  No conectado a GitHub",
            "pasteToken": "Pegar token de GitHub (ghp_...)", "connect": "Conectar",
            "createToken": "Crear token →", "uploadGH": "↑  Subir a GitHub",
            "updateGH": "↓  Actualizar", "logout": "Cerrar Sesión",
            "createProject": "Crear nuevo proyecto GitHub", "projectNamePlaceholder": "nombre-proyecto",
            "visibility": "Visibilidad:", "public_": "Público", "private_": "Privado",
            "createAndUpload": "✔  Crear y Subir", "cancel": "Cancelar",
            "noTracking": "Sin seguimiento — inicia con el botón",
            "allSaved": "✅  Todo guardado — nada que hacer",
            "filesChanged": "%d archivo%@ cambiado", "filesChangedPlural": "s",
            "describeChanges": "Por favor describe primero qué cambiaste.",
            "invalidToken": "Token inválido — por favor inténtalo de nuevo",
            "savedMsg": "✓  Guardado", "uploaded": "✓  ¡Subido!", "updated": "✓  ¡Actualizado!",
            "projectCreated": "✓  ¡Proyecto creado y subido a GitHub!",
            "creating": "Creando...", "checking": "Verificando...",
            "notYetUploaded": "Aún no subido",
            "aheadBehind": "↑ %d por enviar, ↓ %d por recibir",
            "aheadOnly": "↑ %d cambio%@ por enviar", "behindOnly": "↓ %d cambio%@ nuevo disponible",
            "upToDate": "✓  Todo al día",
            "noUpdateAvailable": "No hay actualización disponible",
            "updateAvailable": "%@ disponible — haz clic para instalar",
            "onlyWithAppBundle": "Solo funciona con paquete .app",
            "alreadyUpToDate": "Ya actualizado (v%@)",
            "checkFailed": "Verificación fallida — intenta más tarde",
            "updateInstalled": "Actualización instalada — reiniciando…",
            "fullDiskAccess": "Acceso Completo al Disco",
            "fullDiskAccessMsg": "quickTERMINAL funciona mejor con Acceso Completo al Disco.\n\nOtorgar acceso en:\nAjustes del Sistema → Privacidad y Seguridad → Acceso Completo al Disco",
            "openSettings": "Abrir Ajustes", "later": "Después",
            "copy": "Copiar", "paste": "Pegar", "selectAll": "Seleccionar Todo", "clear": "Limpiar",
            "newTab": "Nueva Pestaña", "splitVertical": "División Vertical", "splitHorizontal": "División Horizontal", "panels": "Paneles",
            "showHide": "Mostrar / Ocultar", "detachWindow": "Desacoplar Ventana", "reattachWindow": "Acoplar Ventana", "quitApp": "Salir de quickTerminal",
            "sshNewConn": "NUEVA CONEXIÓN", "sshNoSaved": "No hay conexiones guardadas",
            "sshNamePh": "Nombre  (opcional, p.ej. Producción)",
            "sshConnPh": "usuario@host  o  usuario@host:puerto  *",
            "sshKeyPh": "~/.ssh/id_rsa  (opcional – dejar vacío para auth por contraseña)",
        ],
        "fr": [
            "language": "LANGUE",
            "opacity": "Opacité", "blur": "Flou", "fontSize": "Taille de Police",
            "cursor": "Curseur", "cursorBlink": "Clignotement du Curseur", "font": "Police",
            "syntaxHighlight": "Coloration Syntaxique", "defaultShell": "Shell par Défaut",
            "colorThemeSection": "THÈME DE COULEUR",
            "windowSection": "Fenêtre", "alwaysOnTop": "Toujours au Premier Plan", "followAllSpaces": "Suivre Tous les Espaces", "autoDim": "Assombrissement Auto",
            "hideOnClickOutside": "Masquer au Clic Extérieur", "hideOnDeactivate": "Masquer à la Désactivation",
            "copyOnSelect": "Copier à la Sélection", "launchAtLogin": "Lancer à la Connexion",
            "autoCheckUpdates": "Vérifier les MàJ Automatiquement", "webpickerSection": "WebPicker",
            "browser": "Navigateur", "claudeSection": "Claude Code", "showUsageBadge": "Afficher Badge d'Utilisation",
            "refresh": "Actualiser", "status": "Statut", "connected": "Connecté",
            "noToken": "Pas de Token Claude Code", "resetToDefaults": "Réinitialiser",
            "sure": "Sûr ?", "sendFeedback": "Envoyer un Commentaire", "sent": "✓ Envoyé !",
            "notConnected": "Non connecté", "connecting": "Connexion...",
            "openingTab": "Ouverture d'un nouvel onglet...", "navigateTo": "Naviguer vers un site web",
            "verbunden": "Connecté", "disconnect": "⏏ Déconnecter",
            "pickElement": "✦  Sélectionner Élément", "connectToChrome": "  ⊕  Connecter à Chrome",
            "resetMarks": "⌫ Effacer Marques", "picks": "SÉLECTIONS",
            "chromeNotReachable": "Chrome inaccessible", "connectionLost": "Connexion perdue",
            "connectionFailed": "Connexion échouée", "tabClosed": "Onglet fermé",
            "waitingForClick": "En attente de clic...",
            "noProjectYet": "Pas encore de suivi de projet",
            "clickToStartTracking": "Cliquez sur le bouton pour suivre ce dossier.",
            "startTracking": "Démarrer le Suivi", "changedFiles": "FICHIERS MODIFIÉS",
            "whatChanged": "QU'AVEZ-VOUS MODIFIÉ ?",
            "commitPlaceholder": "ex. Page de connexion améliorée, bug corrigé...",
            "save": "💾  Sauvegarder", "notConnectedGH": "🔗  Non connecté à GitHub",
            "pasteToken": "Coller le token GitHub (ghp_...)", "connect": "Connecter",
            "createToken": "Créer un token →", "uploadGH": "↑  Envoyer sur GitHub",
            "updateGH": "↓  Mettre à Jour", "logout": "Déconnexion",
            "createProject": "Créer un nouveau projet GitHub", "projectNamePlaceholder": "nom-projet",
            "visibility": "Visibilité :", "public_": "Public", "private_": "Privé",
            "createAndUpload": "✔  Créer et Envoyer", "cancel": "Annuler",
            "noTracking": "Pas de suivi — démarrez avec le bouton",
            "allSaved": "✅  Tout sauvegardé — rien à faire",
            "filesChanged": "%d fichier%@ modifié", "filesChangedPlural": "s",
            "describeChanges": "Veuillez d'abord décrire ce que vous avez modifié.",
            "invalidToken": "Token invalide — veuillez réessayer",
            "savedMsg": "✓  Sauvegardé", "uploaded": "✓  Envoyé !", "updated": "✓  Mis à jour !",
            "projectCreated": "✓  Projet créé et envoyé sur GitHub !",
            "creating": "Création...", "checking": "Vérification...",
            "notYetUploaded": "Pas encore envoyé",
            "aheadBehind": "↑ %d à envoyer, ↓ %d à récupérer",
            "aheadOnly": "↑ %d changement%@ à envoyer", "behindOnly": "↓ %d nouveau changement%@ disponible",
            "upToDate": "✓  Tout à jour",
            "noUpdateAvailable": "Pas de mise à jour disponible",
            "updateAvailable": "%@ disponible — cliquez pour installer",
            "onlyWithAppBundle": "Fonctionne uniquement avec le bundle .app",
            "alreadyUpToDate": "Déjà à jour (v%@)",
            "checkFailed": "Vérification échouée — réessayez plus tard",
            "updateInstalled": "Mise à jour installée — redémarrage…",
            "fullDiskAccess": "Accès Complet au Disque",
            "fullDiskAccessMsg": "quickTERMINAL fonctionne mieux avec l'Accès Complet au Disque.\n\nAccorder l'accès dans :\nRéglages Système → Confidentialité et Sécurité → Accès Complet au Disque",
            "openSettings": "Ouvrir les Réglages", "later": "Plus tard",
            "copy": "Copier", "paste": "Coller", "selectAll": "Tout Sélectionner", "clear": "Effacer",
            "newTab": "Nouvel Onglet", "splitVertical": "Division Verticale", "splitHorizontal": "Division Horizontale", "panels": "Panneaux",
            "showHide": "Afficher / Masquer", "detachWindow": "Détacher Fenêtre", "reattachWindow": "Réattacher Fenêtre", "quitApp": "Quitter quickTerminal",
            "sshNewConn": "NOUVELLE CONNEXION", "sshNoSaved": "Aucune connexion enregistrée",
            "sshNamePh": "Nom  (optionnel, ex. Production)",
            "sshConnPh": "utilisateur@hôte  ou  utilisateur@hôte:port  *",
            "sshKeyPh": "~/.ssh/id_rsa  (optionnel – laisser vide pour auth par mot de passe)",
        ],
        "it": [
            "language": "LINGUA",
            "opacity": "Opacità", "blur": "Sfocatura", "fontSize": "Dimensione Font",
            "cursor": "Cursore", "cursorBlink": "Lampeggio Cursore", "font": "Font",
            "syntaxHighlight": "Evidenziazione Sintassi", "defaultShell": "Shell Predefinita",
            "colorThemeSection": "TEMA COLORI",
            "windowSection": "Finestra", "alwaysOnTop": "Sempre in Primo Piano", "followAllSpaces": "Segui Tutti gli Spazi", "autoDim": "Oscuramento Auto",
            "hideOnClickOutside": "Nascondi al Clic Esterno", "hideOnDeactivate": "Nascondi alla Disattivazione",
            "copyOnSelect": "Copia alla Selezione", "launchAtLogin": "Avvia all'Accesso",
            "autoCheckUpdates": "Controlla Aggiornamenti Auto", "webpickerSection": "WebPicker",
            "browser": "Browser", "claudeSection": "Claude Code", "showUsageBadge": "Mostra Badge Utilizzo",
            "refresh": "Aggiorna", "status": "Stato", "connected": "Connesso",
            "noToken": "Nessun Token Claude Code", "resetToDefaults": "Ripristina Impostazioni",
            "sure": "Sicuro?", "sendFeedback": "Invia Feedback", "sent": "✓ Inviato!",
            "notConnected": "Non connesso", "connecting": "Connessione...",
            "openingTab": "Apertura nuova scheda...", "navigateTo": "Naviga verso un sito web",
            "verbunden": "Connesso", "disconnect": "⏏ Disconnetti",
            "pickElement": "✦  Seleziona Elemento", "connectToChrome": "  ⊕  Connetti a Chrome",
            "resetMarks": "⌫ Cancella Segni", "picks": "SELEZIONI",
            "chromeNotReachable": "Chrome non raggiungibile", "connectionLost": "Connessione persa",
            "connectionFailed": "Connessione fallita", "tabClosed": "Scheda chiusa",
            "waitingForClick": "In attesa del clic...",
            "noProjectYet": "Nessun tracciamento progetto",
            "clickToStartTracking": "Clicca il pulsante per tracciare questa cartella.",
            "startTracking": "Avvia Tracciamento", "changedFiles": "FILE MODIFICATI",
            "whatChanged": "COSA HAI MODIFICATO?",
            "commitPlaceholder": "es. Migliorata pagina login, corretto bug...",
            "save": "💾  Salva", "notConnectedGH": "🔗  Non connesso a GitHub",
            "pasteToken": "Incolla token GitHub (ghp_...)", "connect": "Connetti",
            "createToken": "Crea token →", "uploadGH": "↑  Carica su GitHub",
            "updateGH": "↓  Aggiorna", "logout": "Disconnetti",
            "createProject": "Crea nuovo progetto GitHub", "projectNamePlaceholder": "nome-progetto",
            "visibility": "Visibilità:", "public_": "Pubblico", "private_": "Privato",
            "createAndUpload": "✔  Crea e Carica", "cancel": "Annulla",
            "noTracking": "Nessun tracciamento — avvia con il pulsante",
            "allSaved": "✅  Tutto salvato — niente da fare",
            "filesChanged": "%d file%@ modificato", "filesChangedPlural": "",
            "describeChanges": "Per favore descrivi prima cosa hai modificato.",
            "invalidToken": "Token non valido — riprova",
            "savedMsg": "✓  Salvato", "uploaded": "✓  Caricato!", "updated": "✓  Aggiornato!",
            "projectCreated": "✓  Progetto creato e caricato su GitHub!",
            "creating": "Creazione...", "checking": "Verifica...",
            "notYetUploaded": "Non ancora caricato",
            "aheadBehind": "↑ %d da inviare, ↓ %d da ricevere",
            "aheadOnly": "↑ %d modifica%@ da inviare", "behindOnly": "↓ %d nuova modifica%@ disponibile",
            "upToDate": "✓  Tutto aggiornato",
            "noUpdateAvailable": "Nessun aggiornamento disponibile",
            "updateAvailable": "%@ disponibile — clicca per installare",
            "onlyWithAppBundle": "Funziona solo con bundle .app",
            "alreadyUpToDate": "Già aggiornato (v%@)",
            "checkFailed": "Verifica fallita — riprova più tardi",
            "updateInstalled": "Aggiornamento installato — riavvio…",
            "fullDiskAccess": "Accesso Completo al Disco",
            "fullDiskAccessMsg": "quickTERMINAL funziona meglio con Accesso Completo al Disco.\n\nConcedi accesso in:\nImpostazioni di Sistema → Privacy e Sicurezza → Accesso Completo al Disco",
            "openSettings": "Apri Impostazioni", "later": "Dopo",
            "copy": "Copia", "paste": "Incolla", "selectAll": "Seleziona Tutto", "clear": "Pulisci",
            "newTab": "Nuova Scheda", "splitVertical": "Divisione Verticale", "splitHorizontal": "Divisione Orizzontale", "panels": "Pannelli",
            "showHide": "Mostra / Nascondi", "detachWindow": "Sgancia Finestra", "reattachWindow": "Aggancia Finestra", "quitApp": "Esci da quickTerminal",
            "sshNewConn": "NUOVA CONNESSIONE", "sshNoSaved": "Nessuna connessione salvata",
            "sshNamePh": "Nome  (opzionale, es. Produzione)",
            "sshConnPh": "utente@host  o  utente@host:porta  *",
            "sshKeyPh": "~/.ssh/id_rsa  (opzionale – lasciare vuoto per auth con password)",
        ],
        "ar": [
            "language": "اللغة",
            "opacity": "الشفافية", "blur": "التمويه", "fontSize": "حجم الخط",
            "cursor": "المؤشر", "cursorBlink": "وميض المؤشر", "font": "الخط",
            "syntaxHighlight": "تمييز البنية", "defaultShell": "الصدفة الافتراضية",
            "colorThemeSection": "نمط الألوان",
            "windowSection": "النافذة", "alwaysOnTop": "دائماً في المقدمة", "followAllSpaces": "متابعة جميع الفضاءات", "autoDim": "تعتيم تلقائي",
            "hideOnClickOutside": "إخفاء عند النقر خارجاً", "hideOnDeactivate": "إخفاء عند التعطيل",
            "copyOnSelect": "نسخ عند التحديد", "launchAtLogin": "تشغيل عند تسجيل الدخول",
            "autoCheckUpdates": "فحص التحديثات تلقائياً", "webpickerSection": "منتقي الويب",
            "browser": "المتصفح", "claudeSection": "كلود كود", "showUsageBadge": "إظهار شارة الاستخدام",
            "refresh": "تحديث", "status": "الحالة", "connected": "متصل",
            "noToken": "لا يوجد رمز كلود كود", "resetToDefaults": "إعادة تعيين الافتراضيات",
            "sure": "متأكد؟", "sendFeedback": "إرسال ملاحظات", "sent": "✓ تم الإرسال!",
            "notConnected": "غير متصل", "connecting": "جاري الاتصال...",
            "openingTab": "فتح تبويب جديد...", "navigateTo": "التنقل إلى موقع",
            "verbunden": "متصل", "disconnect": "⏏ قطع الاتصال",
            "pickElement": "✦  اختر عنصراً", "connectToChrome": "  ⊕  الاتصال بكروم",
            "resetMarks": "⌫ إعادة تعيين العلامات", "picks": "الاختيارات",
            "chromeNotReachable": "كروم غير متاح", "connectionLost": "انقطع الاتصال",
            "connectionFailed": "فشل الاتصال", "tabClosed": "تم إغلاق التبويب",
            "waitingForClick": "في انتظار النقر...",
            "noProjectYet": "لا يوجد تتبع للمشروع بعد",
            "clickToStartTracking": "انقر على الزر لبدء تتبع هذا المجلد.",
            "startTracking": "بدء التتبع", "changedFiles": "الملفات المعدلة",
            "whatChanged": "ماذا غيرت؟",
            "commitPlaceholder": "مثال: تحسين صفحة الدخول، إصلاح خطأ...",
            "save": "💾  حفظ", "notConnectedGH": "🔗  غير متصل بـ GitHub",
            "pasteToken": "لصق رمز GitHub (ghp_...)", "connect": "اتصال",
            "createToken": "إنشاء رمز ←", "uploadGH": "↑  رفع إلى GitHub",
            "updateGH": "↓  تحديث", "logout": "تسجيل الخروج",
            "createProject": "إنشاء مشروع GitHub جديد", "projectNamePlaceholder": "اسم-المشروع",
            "visibility": "الرؤية:", "public_": "عام", "private_": "خاص",
            "createAndUpload": "✔  إنشاء ورفع", "cancel": "إلغاء",
            "noTracking": "لا تتبع — ابدأ بالزر",
            "allSaved": "✅  تم حفظ الكل — لا شيء للفعل",
            "filesChanged": "%d ملف%@ معدل", "filesChangedPlural": "",
            "describeChanges": "يرجى وصف ما غيرته أولاً.",
            "invalidToken": "رمز غير صالح — يرجى المحاولة مرة أخرى",
            "savedMsg": "✓  تم الحفظ", "uploaded": "✓  تم الرفع!", "updated": "✓  تم التحديث!",
            "projectCreated": "✓  تم إنشاء المشروع ورفعه إلى GitHub!",
            "creating": "جاري الإنشاء...", "checking": "جاري الفحص...",
            "notYetUploaded": "لم يُرفع بعد",
            "aheadBehind": "↑ %d للإرسال، ↓ %d للاستلام",
            "aheadOnly": "↑ %d تغيير%@ للإرسال", "behindOnly": "↓ %d تغيير%@ جديد متاح",
            "upToDate": "✓  كل شيء محدث",
            "noUpdateAvailable": "لا يوجد تحديث",
            "updateAvailable": "%@ متاح — انقر للتثبيت",
            "onlyWithAppBundle": "يعمل فقط مع حزمة .app",
            "alreadyUpToDate": "محدث بالفعل (v%@)",
            "checkFailed": "فشل الفحص — حاول لاحقاً",
            "updateInstalled": "تم تثبيت التحديث — إعادة التشغيل…",
            "fullDiskAccess": "الوصول الكامل للقرص",
            "fullDiskAccessMsg": "quickTERMINAL يعمل بشكل أفضل مع الوصول الكامل للقرص.\n\nامنح الوصول في:\nإعدادات النظام → الخصوصية والأمان → الوصول الكامل للقرص",
            "openSettings": "فتح الإعدادات", "later": "لاحقاً",
            "copy": "نسخ", "paste": "لصق", "selectAll": "تحديد الكل", "clear": "مسح",
            "newTab": "تبويب جديد", "splitVertical": "تقسيم عمودي", "splitHorizontal": "تقسيم أفقي", "panels": "الألواح",
            "showHide": "إظهار / إخفاء", "detachWindow": "فصل النافذة", "reattachWindow": "إرساء النافذة", "quitApp": "إنهاء quickTerminal",
            "sshNewConn": "اتصال جديد", "sshNoSaved": "لا توجد اتصالات محفوظة",
            "sshNamePh": "الاسم  (اختياري، مثل: الإنتاج)",
            "sshConnPh": "مستخدم@مضيف  أو  مستخدم@مضيف:منفذ  *",
            "sshKeyPh": "~/.ssh/id_rsa  (اختياري – اتركه فارغاً لاستخدام كلمة المرور)",
        ],
        "ja": [
            "language": "言語",
            "opacity": "透明度", "blur": "ぼかし", "fontSize": "フォントサイズ",
            "cursor": "カーソル", "cursorBlink": "カーソル点滅", "font": "フォント",
            "syntaxHighlight": "シンタックスハイライト", "defaultShell": "デフォルトシェル",
            "colorThemeSection": "カラーテーマ",
            "windowSection": "ウィンドウ", "alwaysOnTop": "常に最前面", "followAllSpaces": "全スペースに表示", "autoDim": "自動暗転",
            "hideOnClickOutside": "外クリックで非表示", "hideOnDeactivate": "非アクティブ時に非表示",
            "copyOnSelect": "選択時にコピー", "launchAtLogin": "ログイン時に起動",
            "autoCheckUpdates": "自動更新確認", "webpickerSection": "WebPicker",
            "browser": "ブラウザ", "claudeSection": "Claude Code", "showUsageBadge": "使用バッジを表示",
            "refresh": "更新", "status": "ステータス", "connected": "接続済み",
            "noToken": "Claude Codeトークンなし", "resetToDefaults": "デフォルトにリセット",
            "sure": "確認?", "sendFeedback": "フィードバック送信", "sent": "✓ 送信済み!",
            "notConnected": "未接続", "connecting": "接続中...",
            "openingTab": "新しいタブを開いています...", "navigateTo": "ウェブサイトに移動",
            "verbunden": "接続済み", "disconnect": "⏏ 切断",
            "pickElement": "✦  要素を選択", "connectToChrome": "  ⊕  Chromeに接続",
            "resetMarks": "⌫ マークをリセット", "picks": "選択",
            "chromeNotReachable": "Chromeに接続できません", "connectionLost": "接続が切断されました",
            "connectionFailed": "接続に失敗しました", "tabClosed": "タブが閉じられました",
            "waitingForClick": "クリック待機中...",
            "noProjectYet": "まだプロジェクト追跡なし",
            "clickToStartTracking": "このフォルダを追跡するにはボタンをクリックしてください。",
            "startTracking": "追跡を開始", "changedFiles": "変更されたファイル",
            "whatChanged": "何を変更しましたか?",
            "commitPlaceholder": "例: ログインページを改善、バグを修正...",
            "save": "💾  保存", "notConnectedGH": "🔗  GitHubに未接続",
            "pasteToken": "GitHubトークンを貼り付け (ghp_...)", "connect": "接続",
            "createToken": "トークンを作成 →", "uploadGH": "↑  GitHubにアップロード",
            "updateGH": "↓  更新", "logout": "ログアウト",
            "createProject": "新しいGitHubプロジェクトを作成", "projectNamePlaceholder": "プロジェクト名",
            "visibility": "公開範囲:", "public_": "公開", "private_": "非公開",
            "createAndUpload": "✔  作成してアップロード", "cancel": "キャンセル",
            "noTracking": "追跡なし — ボタンで開始",
            "allSaved": "✅  すべて保存済み — 何もなし",
            "filesChanged": "%dファイル%@変更", "filesChangedPlural": "",
            "describeChanges": "まず何を変更したか説明してください。",
            "invalidToken": "無効なトークン — もう一度試してください",
            "savedMsg": "✓  保存しました", "uploaded": "✓  アップロード完了!", "updated": "✓  更新完了!",
            "projectCreated": "✓  プロジェクトを作成してGitHubにアップロードしました!",
            "creating": "作成中...", "checking": "確認中...",
            "notYetUploaded": "まだアップロードされていません",
            "aheadBehind": "↑ %d件を送信、↓ %d件を受信",
            "aheadOnly": "↑ %d件%@の変更を送信", "behindOnly": "↓ %d件%@の新しい変更あり",
            "upToDate": "✓  すべて最新",
            "noUpdateAvailable": "更新はありません",
            "updateAvailable": "%@ 利用可能 — クリックしてインストール",
            "onlyWithAppBundle": ".appバンドルでのみ機能します",
            "alreadyUpToDate": "すでに最新です (v%@)",
            "checkFailed": "確認に失敗 — 後でもう一度試してください",
            "updateInstalled": "更新がインストールされました — 再起動中…",
            "fullDiskAccess": "フルディスクアクセス",
            "fullDiskAccessMsg": "quickTERMINALはフルディスクアクセスで最もよく動作します。\n\nアクセスを許可:\nシステム設定 → プライバシーとセキュリティ → フルディスクアクセス",
            "openSettings": "設定を開く", "later": "後で",
            "copy": "コピー", "paste": "ペースト", "selectAll": "すべて選択", "clear": "クリア",
            "newTab": "新しいタブ", "splitVertical": "縦分割", "splitHorizontal": "横分割", "panels": "パネル",
            "showHide": "表示 / 非表示", "detachWindow": "ウィンドウを分離", "reattachWindow": "ウィンドウを固定", "quitApp": "quickTerminal を終了",
            "sshNewConn": "新規接続", "sshNoSaved": "保存された接続がありません",
            "sshNamePh": "名前  (任意、例: 本番)",
            "sshConnPh": "ユーザー@ホスト  または  ユーザー@ホスト:ポート  *",
            "sshKeyPh": "~/.ssh/id_rsa  (任意 – パスワード認証は空のまま)",
        ],
        "zh": [
            "language": "语言",
            "opacity": "不透明度", "blur": "模糊", "fontSize": "字体大小",
            "cursor": "光标", "cursorBlink": "光标闪烁", "font": "字体",
            "syntaxHighlight": "语法高亮", "defaultShell": "默认 Shell",
            "colorThemeSection": "颜色主题",
            "windowSection": "窗口", "alwaysOnTop": "始终置顶", "followAllSpaces": "跟随所有空间", "autoDim": "自动变暗",
            "hideOnClickOutside": "点击外部时隐藏", "hideOnDeactivate": "失活时隐藏",
            "copyOnSelect": "选中即复制", "launchAtLogin": "登录时启动",
            "autoCheckUpdates": "自动检查更新", "webpickerSection": "WebPicker",
            "browser": "浏览器", "claudeSection": "Claude Code", "showUsageBadge": "显示使用徽章",
            "refresh": "刷新", "status": "状态", "connected": "已连接",
            "noToken": "无 Claude Code 令牌", "resetToDefaults": "恢复默认设置",
            "sure": "确定?", "sendFeedback": "发送反馈", "sent": "✓ 已发送!",
            "notConnected": "未连接", "connecting": "连接中...",
            "openingTab": "正在打开新标签页...", "navigateTo": "导航到网站",
            "verbunden": "已连接", "disconnect": "⏏ 断开连接",
            "pickElement": "✦  选择元素", "connectToChrome": "  ⊕  连接到 Chrome",
            "resetMarks": "⌫ 重置标记", "picks": "已选择",
            "chromeNotReachable": "Chrome 无法访问", "connectionLost": "连接已断开",
            "connectionFailed": "连接失败", "tabClosed": "标签页已关闭",
            "waitingForClick": "等待点击...",
            "noProjectYet": "尚无项目跟踪",
            "clickToStartTracking": "点击按钮开始跟踪此文件夹。",
            "startTracking": "开始跟踪", "changedFiles": "已更改的文件",
            "whatChanged": "你改了什么?",
            "commitPlaceholder": "例如：改进登录页面，修复了错误...",
            "save": "💾  保存", "notConnectedGH": "🔗  未连接到 GitHub",
            "pasteToken": "粘贴 GitHub 令牌 (ghp_...)", "connect": "连接",
            "createToken": "创建令牌 →", "uploadGH": "↑  上传到 GitHub",
            "updateGH": "↓  更新", "logout": "退出登录",
            "createProject": "创建新 GitHub 项目", "projectNamePlaceholder": "项目名称",
            "visibility": "可见性:", "public_": "公开", "private_": "私有",
            "createAndUpload": "✔  创建并上传", "cancel": "取消",
            "noTracking": "无跟踪 — 用按钮开始",
            "allSaved": "✅  全部已保存 — 无需操作",
            "filesChanged": "%d 个文件%@已更改", "filesChangedPlural": "",
            "describeChanges": "请先描述您更改了什么。",
            "invalidToken": "令牌无效 — 请重试",
            "savedMsg": "✓  已保存", "uploaded": "✓  已上传!", "updated": "✓  已更新!",
            "projectCreated": "✓  项目已创建并上传到 GitHub!",
            "creating": "创建中...", "checking": "检查中...",
            "notYetUploaded": "尚未上传",
            "aheadBehind": "↑ %d 待推送，↓ %d 待拉取",
            "aheadOnly": "↑ %d 个%@更改待推送", "behindOnly": "↓ %d 个%@新更改可用",
            "upToDate": "✓  一切都是最新的",
            "noUpdateAvailable": "没有可用更新",
            "updateAvailable": "%@ 可用 — 点击安装",
            "onlyWithAppBundle": "仅适用于 .app 包",
            "alreadyUpToDate": "已是最新版本 (v%@)",
            "checkFailed": "检查失败 — 请稍后重试",
            "updateInstalled": "更新已安装 — 正在重启…",
            "fullDiskAccess": "完全磁盘访问",
            "fullDiskAccessMsg": "quickTERMINAL 在完全磁盘访问下运行最佳。\n\n在以下位置授予访问权限：\n系统设置 → 隐私与安全性 → 完全磁盘访问",
            "openSettings": "打开设置", "later": "稍后",
            "copy": "复制", "paste": "粘贴", "selectAll": "全选", "clear": "清除",
            "newTab": "新标签页", "splitVertical": "垂直分割", "splitHorizontal": "水平分割", "panels": "面板",
            "showHide": "显示 / 隐藏", "detachWindow": "分离窗口", "reattachWindow": "重新固定窗口", "quitApp": "退出 quickTerminal",
            "sshNewConn": "新建连接", "sshNoSaved": "没有保存的连接",
            "sshNamePh": "名称  (可选，例如 生产)",
            "sshConnPh": "用户@主机  或  用户@主机:端口  *",
            "sshKeyPh": "~/.ssh/id_rsa  (可选 – 留空则使用密码认证)",
        ],
        "ru": [
            "language": "ЯЗЫК",
            "opacity": "Прозрачность", "blur": "Размытие", "fontSize": "Размер шрифта",
            "cursor": "Курсор", "cursorBlink": "Мигание курсора", "font": "Шрифт",
            "syntaxHighlight": "Подсветка синтаксиса", "defaultShell": "Оболочка по умолчанию",
            "colorThemeSection": "ЦВЕТОВАЯ ТЕМА",
            "windowSection": "Окно", "alwaysOnTop": "Всегда поверх", "followAllSpaces": "На всех рабочих столах", "autoDim": "Авто-затемнение",
            "hideOnClickOutside": "Скрыть при клике вне", "hideOnDeactivate": "Скрыть при деактивации",
            "copyOnSelect": "Копировать при выборе", "launchAtLogin": "Запуск при входе",
            "autoCheckUpdates": "Автопроверка обновлений", "webpickerSection": "WebPicker",
            "browser": "Браузер", "claudeSection": "Claude Code", "showUsageBadge": "Показать значок",
            "refresh": "Обновить", "status": "Статус", "connected": "Подключено",
            "noToken": "Нет токена Claude Code", "resetToDefaults": "Сбросить настройки",
            "sure": "Уверен?", "sendFeedback": "Отправить отзыв", "sent": "✓ Отправлено!",
            "notConnected": "Не подключено", "connecting": "Подключение...",
            "openingTab": "Открытие новой вкладки...", "navigateTo": "Перейти на сайт",
            "verbunden": "Подключено", "disconnect": "⏏ Отключить",
            "pickElement": "✦  Выбрать элемент", "connectToChrome": "  ⊕  Подключиться к Chrome",
            "resetMarks": "⌫ Сбросить метки", "picks": "ВЫБОРКИ",
            "chromeNotReachable": "Chrome недоступен", "connectionLost": "Соединение потеряно",
            "connectionFailed": "Ошибка подключения", "tabClosed": "Вкладка закрыта",
            "waitingForClick": "Ожидание клика...",
            "noProjectYet": "Отслеживание проекта не начато",
            "clickToStartTracking": "Нажмите кнопку чтобы отслеживать эту папку.",
            "startTracking": "Начать отслеживание", "changedFiles": "ИЗМЕНЁННЫЕ ФАЙЛЫ",
            "whatChanged": "ЧТО ВЫ ИЗМЕНИЛИ?",
            "commitPlaceholder": "напр. Улучшена страница входа, исправлена ошибка...",
            "save": "💾  Сохранить", "notConnectedGH": "🔗  Не подключено к GitHub",
            "pasteToken": "Вставьте токен GitHub (ghp_...)", "connect": "Подключить",
            "createToken": "Создать токен →", "uploadGH": "↑  Загрузить на GitHub",
            "updateGH": "↓  Обновить", "logout": "Выйти",
            "createProject": "Создать новый проект GitHub", "projectNamePlaceholder": "имя-проекта",
            "visibility": "Видимость:", "public_": "Публичный", "private_": "Приватный",
            "createAndUpload": "✔  Создать и загрузить", "cancel": "Отмена",
            "noTracking": "Нет отслеживания — начните с кнопки",
            "allSaved": "✅  Всё сохранено — нечего делать",
            "filesChanged": "%d файл%@ изменён", "filesChangedPlural": "",
            "describeChanges": "Сначала опишите что вы изменили.",
            "invalidToken": "Неверный токен — попробуйте ещё раз",
            "savedMsg": "✓  Сохранено", "uploaded": "✓  Загружено!", "updated": "✓  Обновлено!",
            "projectCreated": "✓  Проект создан и загружен на GitHub!",
            "creating": "Создание...", "checking": "Проверка...",
            "notYetUploaded": "Ещё не загружено",
            "aheadBehind": "↑ %d отправить, ↓ %d получить",
            "aheadOnly": "↑ %d изменение%@ отправить", "behindOnly": "↓ %d новое изменение%@ доступно",
            "upToDate": "✓  Всё актуально",
            "noUpdateAvailable": "Обновлений нет",
            "updateAvailable": "%@ доступно — нажмите для установки",
            "onlyWithAppBundle": "Работает только с .app",
            "alreadyUpToDate": "Уже актуально (v%@)",
            "checkFailed": "Проверка не удалась — попробуйте позже",
            "updateInstalled": "Обновление установлено — перезапуск…",
            "fullDiskAccess": "Полный доступ к диску",
            "fullDiskAccessMsg": "quickTERMINAL работает лучше с полным доступом к диску.\n\nРазрешить в:\nНастройки системы → Конфиденциальность и безопасность → Полный доступ к диску",
            "openSettings": "Открыть настройки", "later": "Позже",
            "copy": "Копировать", "paste": "Вставить", "selectAll": "Выбрать всё", "clear": "Очистить",
            "newTab": "Новая вкладка", "splitVertical": "Разделить вертикально", "splitHorizontal": "Разделить горизонтально", "panels": "Панели",
            "showHide": "Показать / Скрыть", "detachWindow": "Открепить окно", "reattachWindow": "Прикрепить окно", "quitApp": "Выйти из quickTerminal",
            "sshNewConn": "НОВОЕ ПОДКЛЮЧЕНИЕ", "sshNoSaved": "Нет сохранённых подключений",
            "sshNamePh": "Имя  (необязательно, напр. Продакшн)",
            "sshConnPh": "пользователь@хост  или  пользователь@хост:порт  *",
            "sshKeyPh": "~/.ssh/id_rsa  (необязательно – оставьте пустым для пароля)",
        ],
    ]
}

// MARK: - Unicode Width

/// Returns the display width of a Unicode scalar (1 or 2 columns).
/// Wide characters (CJK, emoji, etc.) return 2; most others return 1.
func unicodeWidth(_ s: Unicode.Scalar) -> Int {
    let v = s.value
    // C0/C1 control characters
    if v < 0x20 || (v >= 0x7F && v < 0xA0) { return 0 }
    // Combining characters (zero width)
    if (v >= 0x0300 && v <= 0x036F) ||   // Combining Diacritical Marks
       (v >= 0x1AB0 && v <= 0x1AFF) ||   // Combining Diacritical Marks Extended
       (v >= 0x1DC0 && v <= 0x1DFF) ||   // Combining Diacritical Marks Supplement
       (v >= 0x20D0 && v <= 0x20FF) ||   // Combining Diacritical Marks for Symbols
       (v >= 0xFE00 && v <= 0xFE0F) ||   // Variation Selectors
       (v >= 0xFE20 && v <= 0xFE2F) ||   // Combining Half Marks
       (v >= 0xE0100 && v <= 0xE01EF) {  // Variation Selectors Supplement
        return 0
    }
    // Wide: CJK, fullwidth, emoji, etc.
    if (v >= 0x1100 && v <= 0x115F) ||   // Hangul Jamo
       (v >= 0x2E80 && v <= 0x303E) ||   // CJK Radicals, Kangxi, CJK Symbols
       (v >= 0x3041 && v <= 0x33BF) ||   // Hiragana, Katakana, Bopomofo, CJK Compat
       (v >= 0x3400 && v <= 0x4DBF) ||   // CJK Unified Extension A
       (v >= 0x4E00 && v <= 0xA4CF) ||   // CJK Unified, Yi
       (v >= 0xA960 && v <= 0xA97C) ||   // Hangul Jamo Extended-A
       (v >= 0xAC00 && v <= 0xD7A3) ||   // Hangul Syllables
       (v >= 0xF900 && v <= 0xFAFF) ||   // CJK Compatibility Ideographs
       (v >= 0xFE10 && v <= 0xFE19) ||   // Vertical Forms
       (v >= 0xFE30 && v <= 0xFE6F) ||   // CJK Compatibility Forms + Small Forms
       (v >= 0xFF01 && v <= 0xFF60) ||   // Fullwidth Forms
       (v >= 0xFFE0 && v <= 0xFFE6) ||   // Fullwidth Signs
       (v >= 0x1F000 && v <= 0x1FBFF) || // Mahjong, Dominos, Emoji, Symbols
       (v >= 0x20000 && v <= 0x2FA1F) || // CJK Extensions B-F, Compat Supplement
       (v >= 0x30000 && v <= 0x3134F) {  // CJK Extension G
        return 2
    }
    return 1
}

// MARK: - Colors

let kAnsiColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.00, 0.00, 0.00), (0.80, 0.22, 0.22), (0.22, 0.80, 0.22), (0.80, 0.75, 0.22),
    (0.35, 0.45, 0.80), (0.75, 0.25, 0.75), (0.25, 0.75, 0.75), (0.75, 0.75, 0.75),
    (0.45, 0.45, 0.45), (1.00, 0.35, 0.35), (0.35, 1.00, 0.35), (1.00, 1.00, 0.35),
    (0.50, 0.55, 1.00), (1.00, 0.35, 1.00), (0.35, 1.00, 1.00), (1.00, 1.00, 1.00),
]

var kDefaultBG = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
var kDefaultFG = NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
var kTermBgCGColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 0.28).cgColor
var kSelectionCGColor = NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.8, alpha: 0.4).cgColor
var kCursorCGColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0).cgColor
let kHyperlinkCGColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 0.8).cgColor

func nsColorFromAnsi(_ index: Int) -> NSColor {
    if index >= 0 && index < 16 {
        let (r, g, b) = kAnsiColors[index]
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    } else if index >= 16 && index < 232 {
        let i = index - 16
        let rv: CGFloat = i / 36 == 0 ? 0.0 : (CGFloat(i / 36) * 40.0 + 55.0) / 255.0
        let gv: CGFloat = (i % 36) / 6 == 0 ? 0.0 : (CGFloat((i % 36) / 6) * 40.0 + 55.0) / 255.0
        let bv: CGFloat = i % 6 == 0 ? 0.0 : (CGFloat(i % 6) * 40.0 + 55.0) / 255.0
        return NSColor(calibratedRed: rv, green: gv, blue: bv, alpha: 1)
    } else if index >= 232 && index < 256 {
        let v: CGFloat = (CGFloat(index - 232) * 10.0 + 8.0) / 255.0
        return NSColor(calibratedRed: v, green: v, blue: v, alpha: 1)
    }
    return kDefaultFG
}

var kAnsiColorCache: [NSColor] = (0..<256).map { nsColorFromAnsi($0) }

private func nsColorFromRGB(_ rgb: (UInt8, UInt8, UInt8)) -> NSColor {
    NSColor(calibratedRed: CGFloat(rgb.0) / 255.0, green: CGFloat(rgb.1) / 255.0,
            blue: CGFloat(rgb.2) / 255.0, alpha: 1)
}

func fgColor(for attrs: TextAttrs, terminal t: Terminal? = nil) -> NSColor {
    if let rgb = attrs.fgRGB { return nsColorFromRGB(rgb) }
    if let t = t, let ov = t.paletteOverrides[attrs.bold && attrs.fg < 8 ? attrs.fg + 8 : attrs.fg] {
        return nsColorFromRGB(ov)
    }
    if attrs.fg == 7 && !attrs.bold {
        if let t = t, let dyn = t.dynamicFG { return nsColorFromRGB(dyn) }
        return kDefaultFG
    }
    let idx = attrs.bold && attrs.fg < 8 ? attrs.fg + 8 : attrs.fg
    guard idx >= 0 && idx < kAnsiColorCache.count else { return kDefaultFG }
    return kAnsiColorCache[idx]
}

func bgColor(for attrs: TextAttrs, terminal t: Terminal? = nil) -> NSColor {
    if let rgb = attrs.bgRGB { return nsColorFromRGB(rgb) }
    if let t = t, let ov = t.paletteOverrides[attrs.bg] { return nsColorFromRGB(ov) }
    if attrs.bg == 0 {
        if let t = t, let dyn = t.dynamicBG { return nsColorFromRGB(dyn) }
        return kDefaultBG
    }
    guard attrs.bg >= 0 && attrs.bg < kAnsiColorCache.count else { return kDefaultBG }
    return kAnsiColorCache[attrs.bg]
}

// MARK: - Themes

struct TerminalTheme {
    let id: String
    let defaultBG: NSColor
    let defaultFG: NSColor
    let termBgAlpha: CGFloat
    let selectionColor: NSColor
    let cursorColor: NSColor
    let ansiColors: [(CGFloat, CGFloat, CGFloat)]
    let visualMaterial: NSVisualEffectView.Material

    static let dark = TerminalTheme(
        id: "dark",
        defaultBG: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        defaultFG: NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
        termBgAlpha: 0.28,
        selectionColor: NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.8, alpha: 0.4),
        cursorColor: NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0),
        ansiColors: kAnsiColors,
        visualMaterial: .hudWindow
    )

    static let light: TerminalTheme = {
        var c = kAnsiColors
        c[0]  = (0.05, 0.05, 0.05)
        c[7]  = (0.40, 0.40, 0.42)
        c[15] = (0.15, 0.15, 0.18)
        return TerminalTheme(
            id: "light",
            defaultBG: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0),
            defaultFG: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.13, alpha: 1.0),
            termBgAlpha: 0.15,
            selectionColor: NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.3),
            cursorColor: NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
            ansiColors: c,
            visualMaterial: .sheet
        )
    }()

    static let oledBlack = TerminalTheme(
        id: "oled",
        defaultBG: NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        defaultFG: NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.90, alpha: 1.0),
        termBgAlpha: 0.98,
        selectionColor: NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.8, alpha: 0.4),
        cursorColor: NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0),
        ansiColors: kAnsiColors,
        visualMaterial: .underWindowBackground
    )
}

var activeTheme: TerminalTheme = .dark

func applyTheme(_ t: TerminalTheme) {
    activeTheme = t
    kDefaultBG = t.defaultBG
    kDefaultFG = t.defaultFG
    // Explicit overlay colors — light and oled need nearly-opaque fills
    switch t.id {
    case "light":
        kTermBgCGColor = NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.96, alpha: 0.95).cgColor
    case "oled":
        kTermBgCGColor = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.99).cgColor
    default: // dark + system-resolved dark/light
        kTermBgCGColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 0.28).cgColor
    }
    kSelectionCGColor = t.selectionColor.cgColor
    kCursorCGColor = t.cursorColor.cgColor
    kAnsiColorCache = (0..<256).map { i in
        if i < t.ansiColors.count {
            let (r, g, b) = t.ansiColors[i]
            return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        }
        return nsColorFromAnsi(i)
    }
    // Update all open editor tabs
    if let del = NSApp.delegate as? AppDelegate {
        let editorDark = t.id != "light"
        for ev in del.tabEditorViews.compactMap({ $0 }) {
            ev.isDark = editorDark
        }
    }
}

func resolveSystemTheme() -> TerminalTheme {
    // System light → use light theme but mark id as "light" so applyTheme picks the right overlay color
    if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua {
        return .light
    }
    return .dark
}

/// For system theme we also need to update appearance on visual effect
func applySystemThemeAppearance(to visualEffect: NSVisualEffectView) {
    if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua {
        visualEffect.appearance = NSAppearance(named: .aqua)
    } else {
        visualEffect.appearance = NSAppearance(named: .darkAqua)
    }
}

// MARK: - Terminal Engine

// MARK: - Parser Diagnostics

struct ParserDiagnostics {
    var totalScalars = 0
    var csiCount = 0
    var oscCount = 0
    var escCount = 0
    var dcsCount = 0
    private(set) var unhandled: [(seq: String, count: Int)] = []
    private var unhandledMap: [String: Int] = [:]

    mutating func recordUnhandled(_ seq: String) {
        if let idx = unhandledMap[seq] {
            unhandled[idx].count += 1
        } else {
            unhandledMap[seq] = unhandled.count
            unhandled.append((seq: seq, count: 1))
            if unhandled.count > 50 {
                unhandled.removeFirst()
                // Rebuild map (all indices shift by -1 after removeFirst)
                unhandledMap.removeAll()
                for (i, entry) in unhandled.enumerated() { unhandledMap[entry.seq] = i }
            }
        }
    }
}

class Terminal {
    var diag = ParserDiagnostics()
    var cols: Int
    var rows: Int
    var cursor      = CursorState()
    var savedCursor = CursorState()
    var altCursor   = CursorState()
    // Computed shims — all existing callers remain unchanged
    var cursorX: Int      { get { cursor.x }           set { cursor.x = newValue } }
    var cursorY: Int      { get { cursor.y }           set { cursor.y = newValue } }
    var pendingWrap: Bool { get { cursor.pendingWrap } set { cursor.pendingWrap = newValue } }
    var grid: [[Cell]]
    var lineAttrs: [UInt8]   // per-line: 0=normal, 1=double-width(DECDWL), 2=DH-top(DECDHL), 3=DH-bottom(DECDHL)
    var attrs = TextAttrs()
    var savedAttrs = TextAttrs()
    var savedG0IsGraphics = false
    var savedG1IsGraphics = false
    var savedUseG1 = false
    var savedOriginMode = false
    var savedAutoWrap = true
    var scrollTop = 0
    var scrollBottom: Int
    var scrollback: [[Cell]] = []
    var altGrid: [[Cell]]? = nil
    var altLineAttrs: [UInt8]? = nil
    var cursorVisible = true
    var insertMode = false    // IRM: insert mode (SM 4 / RM 4)
    var appCursorMode = false
    var appKeypadMode = false
    var autoWrapMode = true
    var originMode = false
    var reverseVideoMode = false
    var leftRightMarginMode = false
    var leftMargin = 0
    var rightMargin: Int = 0  // initialized to cols-1 in init
    var bracketedPasteMode = false
    var lastChar: Unicode.Scalar = " "   // for CSI b (repeat)
    var cursorStyle = 0                  // 0=default, 1=block blink, 2=block steady, 3=underline blink, 4=underline steady, 5=bar blink, 6=bar steady
    // Mouse tracking modes
    var mouseMode = 0                    // 0=off, 1000=X10 normal, 1002=button-event, 1003=any-event
    var mouseEncoding = 0                // 0=X11 legacy, 1006=SGR
    // Focus reporting
    var focusReportingMode = false
    // Synchronized output (mode 2026)
    var synchronizedOutput = false
    // Charset state: G0/G1 charsets, active charset
    var charsetG0IsGraphics = false      // true = DEC Special Graphics, false = ASCII
    var charsetG1IsGraphics = false
    var useG1 = false                    // SO/SI: true = G1 active, false = G0 active
    // Tab stops
    var tabStops = Set<Int>()
    // Hyperlink state (OSC 8)
    var currentHyperlink: String? = nil
    // Kitty keyboard protocol — progressive enhancement flag stack
    var kittyKbdStack: [Int] = []
    var kittyKbdFlags: Int { kittyKbdStack.last ?? 0 }
    // Sixel image rendering
    var sixelBuf = [UInt8]()
    var sixelImages: [(row: Int, col: Int, image: CGImage)] = []
    var onSixelImage: (() -> Void)?
    var currentDirectory: String? = nil
    var promptMarks: [(mark: Character, row: Int)] = []
    // Mutable palette overrides (OSC 4)
    var paletteOverrides: [Int: (UInt8, UInt8, UInt8)] = [:]
    // Dynamic fg/bg/cursor colors (OSC 10/11/12)
    var dynamicFG: (UInt8, UInt8, UInt8)? = nil
    var dynamicBG: (UInt8, UInt8, UInt8)? = nil
    var dynamicCursor: (UInt8, UInt8, UInt8)? = nil
    var titleStack: [String] = []
    var currentTitle: String = ""
    var onTitleChange: ((String) -> Void)?
    var onResponse: ((String) -> Void)?
    var onColorChange: (() -> Void)?     // notify view when dynamic colors change
    var onResize: ((Int, Int) -> Void)?  // (rows, cols) — request window resize
    var cellPixelWidth: Int = 8           // actual cell pixel dimensions (set by view)
    var cellPixelHeight: Int = 16

    // Parser state
    enum PState { case ground, esc, escInter, csi, osc, oscEsc, dcs, dcsPass, dcsSixel, charsetG0, charsetG1 }
    var pstate: PState = .ground
    var csiPrefix: UInt8 = 0
    var csiIntermediate: UInt8 = 0       // track intermediate bytes like SP in 'CSI Ps SP q'
    var csiParams: [Int] = []
    var csiSubParams: [[Int]] = []   // colon-separated sub-params per CSI param
    var csiColonSub: [Int] = []      // current colon sub-param accumulator
    var csiCur = ""
    var oscBuf = ""
    var escInterByte: UInt8 = 0      // intermediate byte for ESC # sequences

    // Incremental UTF-8 decoder: buffers incomplete multi-byte sequences across reads
    private var utf8Buf = [UInt8]()

    // DEC Special Graphics charset mapping (ASCII 0x60-0x7E → Unicode box-drawing)
    static let decGraphicsMap: [Unicode.Scalar: Unicode.Scalar] = [
        "`": "\u{25C6}", // ◆ diamond
        "a": "\u{2592}", // ▒ checker board
        "b": "\u{2409}", // ␉ HT symbol
        "c": "\u{240C}", // ␌ FF symbol
        "d": "\u{240D}", // ␍ CR symbol
        "e": "\u{240A}", // ␊ LF symbol
        "f": "\u{00B0}", // ° degree
        "g": "\u{00B1}", // ± plus/minus
        "h": "\u{2424}", // ␤ NL symbol
        "i": "\u{240B}", // ␋ VT symbol
        "j": "\u{2518}", // ┘ lower-right corner
        "k": "\u{2510}", // ┐ upper-right corner
        "l": "\u{250C}", // ┌ upper-left corner
        "m": "\u{2514}", // └ lower-left corner
        "n": "\u{253C}", // ┼ crossing lines
        "o": "\u{23BA}", // ⎺ scan line 1
        "p": "\u{23BB}", // ⎻ scan line 3
        "q": "\u{2500}", // ─ horizontal line
        "r": "\u{23BC}", // ⎼ scan line 7
        "s": "\u{23BD}", // ⎽ scan line 9
        "t": "\u{251C}", // ├ left-tee
        "u": "\u{2524}", // ┤ right-tee
        "v": "\u{2534}", // ┴ bottom-tee
        "w": "\u{252C}", // ┬ top-tee
        "x": "\u{2502}", // │ vertical line
        "y": "\u{2264}", // ≤ less-than-or-equal
        "z": "\u{2265}", // ≥ greater-than-or-equal
        "{": "\u{03C0}", // π pi
        "|": "\u{2260}", // ≠ not-equal
        "}": "\u{00A3}", // £ pound sign
        "~": "\u{00B7}", // · bullet/middle dot
    ]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1
        self.rightMargin = cols - 1
        self.grid = Self.emptyGrid(cols, rows)
        self.lineAttrs = Array(repeating: 0, count: rows)
        resetTabStops()
    }

    func resetTabStops() {
        tabStops.removeAll()
        for i in stride(from: 0, to: cols, by: 8) { tabStops.insert(i) }
    }

    func advanceToNextTab() {
        pendingWrap = false
        for x in (cursorX + 1)..<cols {
            if tabStops.contains(x) { cursorX = x; return }
        }
        cursorX = cols - 1
    }

    func backToPrevTab() {
        for x in stride(from: cursorX - 1, through: 0, by: -1) {
            if tabStops.contains(x) { cursorX = x; return }
        }
        cursorX = 0
    }

    static func emptyGrid(_ c: Int, _ r: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell(), count: c), count: r)
    }

    // MARK: Process input — incremental UTF-8 decoder

    func process(_ data: Data) {
        utf8Buf.append(contentsOf: data)
        var i = 0
        while i < utf8Buf.count {
            let byte = utf8Buf[i]
            // Fast path: ASCII byte — skip String decoding overhead
            if byte < 0x80 {
                feed(Unicode.Scalar(byte))
                i += 1
                continue
            }

            let seqLen: Int
            if byte < 0xC0 { i += 1; continue }       // stray continuation byte — skip
            else if byte < 0xE0 { seqLen = 2 }
            else if byte < 0xF0 { seqLen = 3 }
            else if byte < 0xF8 { seqLen = 4 }
            else                { i += 1; continue }   // invalid lead byte — skip

            if i + seqLen > utf8Buf.count {
                break  // incomplete sequence at end — wait for more data
            }

            let slice = utf8Buf[i..<(i + seqLen)]
            let str = String(decoding: slice, as: UTF8.self)
            for scalar in str.unicodeScalars {
                if scalar != "\u{FFFD}" { feed(scalar) }
            }
            i += seqLen
        }
        // Keep unprocessed trailing bytes for next call
        if i < utf8Buf.count {
            utf8Buf = Array(utf8Buf[i...])
        } else {
            utf8Buf.removeAll(keepingCapacity: true)
        }
    }

    // MARK: State machine

    func feed(_ s: Unicode.Scalar) {
        diag.totalScalars += 1
        let v = s.value

        // C0 control characters are executed in MOST states (except string passthrough)
        if v < 0x20 && pstate != .dcsPass && pstate != .osc && pstate != .oscEsc {
            switch v {
            case 0x1B:
                // ESC always starts a new escape sequence, aborting current
                pstate = .esc; return
            case 0x07: return // BEL — ignore in non-OSC states
            case 0x08: cursorX = max(0, cursorX - 1); pendingWrap = false; return
            case 0x09: advanceToNextTab(); return
            case 0x0A, 0x0B, 0x0C: lf(); return
            case 0x0D: cursorX = 0; pendingWrap = false; return
            case 0x0E: useG1 = true; return   // SO — shift out (activate G1)
            case 0x0F: useG1 = false; return  // SI — shift in (activate G0)
            default: return // other C0 — ignore
            }
        }

        // C1 control codes (8-bit equivalents of ESC sequences)
        if v >= 0x80 && v <= 0x9F && pstate != .dcsPass && pstate != .osc && pstate != .oscEsc {
            switch v {
            case 0x84: lf(); return                           // IND — index (same as ESC D)
            case 0x85: cursorX = 0; lf(); return              // NEL — next line (same as ESC E)
            case 0x88: tabStops.insert(cursorX); return       // HTS — horizontal tab set (same as ESC H)
            case 0x8D: rlf(); return                          // RI — reverse index (same as ESC M)
            case 0x90:                                        // DCS — device control string
                pstate = .dcs; csiPrefix = 0; csiParams = []; csiCur = ""; return
            case 0x9B:                                        // CSI
                pstate = .csi; csiPrefix = 0; csiIntermediate = 0; csiParams = []; csiSubParams = []; csiColonSub = []; csiCur = ""; return
            case 0x9D:                                        // OSC
                pstate = .osc; oscBuf = ""; return
            case 0x9C:                                        // ST — string terminator
                pstate = .ground; return
            default: return                                   // other C1 — ignore
            }
        }

        switch pstate {
        case .ground:
            if v == 0x1B { pstate = .esc }
            else if v >= 0x20 { put(s) }

        case .esc:
            diag.escCount += 1
            switch v {
            case 0x5B: // [
                pstate = .csi; csiPrefix = 0; csiIntermediate = 0; csiParams = []; csiSubParams = []; csiColonSub = []; csiCur = ""
            case 0x5D: // ]
                pstate = .osc; oscBuf = ""
            case 0x50: // P — DCS
                pstate = .dcs; csiPrefix = 0; csiParams = []; csiCur = ""
            case 0x5F, 0x5E, 0x58: // _ APC, ^ PM, X SOS — consume until ST
                pstate = .dcsPass
            case 0x37: // ESC 7 — DECSC (save cursor + attrs)
                savedCursor = cursor
                savedAttrs = attrs; savedG0IsGraphics = charsetG0IsGraphics
                savedG1IsGraphics = charsetG1IsGraphics; savedUseG1 = useG1
                savedOriginMode = originMode; savedAutoWrap = autoWrapMode
                pstate = .ground
            case 0x38: // ESC 8 — DECRC (restore cursor + attrs)
                cursor = savedCursor
                attrs = savedAttrs; charsetG0IsGraphics = savedG0IsGraphics
                charsetG1IsGraphics = savedG1IsGraphics; useG1 = savedUseG1
                originMode = savedOriginMode; autoWrapMode = savedAutoWrap
                pstate = .ground
            case 0x44: lf(); pstate = .ground                                     // ESC D — index (IND)
            case 0x4D: rlf(); pstate = .ground                                    // ESC M — reverse index (RI)
            case 0x45: cursorX = 0; lf(); pstate = .ground                        // ESC E — next line (NEL)
            case 0x48: tabStops.insert(cursorX); pstate = .ground                   // ESC H — set tab stop
            case 0x36: // ESC 6 — DECBI (back index)
                if cursorX > 0 { cursorX -= 1 }
                else {
                    // Scroll line content right within scroll margins
                    if cursorY >= scrollTop && cursorY <= scrollBottom {
                        grid[cursorY].removeLast()
                        grid[cursorY].insert(Cell(), at: 0)
                    }
                }
                pstate = .ground
            case 0x39: // ESC 9 — DECFI (forward index)
                let eCols = effectiveCols(row: cursorY)
                if cursorX < eCols - 1 { cursorX += 1 }
                else {
                    // Scroll line content left within scroll margins
                    if cursorY >= scrollTop && cursorY <= scrollBottom {
                        grid[cursorY].remove(at: 0)
                        grid[cursorY].append(Cell())
                    }
                }
                pstate = .ground
            case 0x63: fullReset(); pstate = .ground                              // ESC c — full reset (RIS)
            case 0x28: pstate = .charsetG0                                        // ESC ( — designate G0 charset
            case 0x29: pstate = .charsetG1                                        // ESC ) — designate G1 charset
            case 0x56: attrs.protected = true; pstate = .ground                   // ESC V — SPA (start protected area)
            case 0x57: attrs.protected = false; pstate = .ground                  // ESC W — EPA (end protected area)
            case 0x3D: appKeypadMode = true; pstate = .ground                      // ESC = — DECKPAM (app keypad)
            case 0x3E: appKeypadMode = false; pstate = .ground                    // ESC > — DECKPNM (normal keypad)
            case 0x2A, 0x2B: pstate = .charsetG0                                 // ESC * / ESC + — G2/G3 (treat as G0)
            case 0x20...0x2F: escInterByte = UInt8(v); pstate = .escInter           // ESC intermediate
            default: pstate = .ground
            }

        case .escInter:
            // Intermediate bytes after ESC (e.g., ESC # 8). Final byte ends it.
            if v >= 0x30 && v <= 0x7E {
                if escInterByte == 0x23 {
                    switch v {
                    case 0x33: // ESC # 3 — DECDHL top half
                        if cursorY < rows { lineAttrs[cursorY] = 2 }
                    case 0x34: // ESC # 4 — DECDHL bottom half
                        if cursorY < rows { lineAttrs[cursorY] = 3 }
                    case 0x35: // ESC # 5 — DECSWL (single-width, normal)
                        if cursorY < rows { lineAttrs[cursorY] = 0 }
                    case 0x36: // ESC # 6 — DECDWL (double-width)
                        if cursorY < rows { lineAttrs[cursorY] = 1 }
                    case 0x38: // DECALN — Screen Alignment Pattern: fill screen with 'E'
                        for r in 0..<rows {
                            for c in 0..<cols {
                                grid[r][c] = Cell(char: "E", attrs: TextAttrs(), width: 1)
                            }
                            lineAttrs[r] = 0
                        }
                        cursorX = 0; cursorY = 0
                        scrollTop = 0; scrollBottom = rows - 1
                    default: break
                    }
                }
                pstate = .ground
            }
            else if v < 0x20 || v > 0x2F { pstate = .ground }

        case .charsetG0:
            charsetG0IsGraphics = (v == 0x30) // '0' = DEC Special Graphics, 'B' or anything else = ASCII
            pstate = .ground

        case .charsetG1:
            charsetG1IsGraphics = (v == 0x30)
            pstate = .ground

        case .csi:
            if v >= 0x3C && v <= 0x3F && csiCur.isEmpty && csiParams.isEmpty && csiPrefix == 0 {
                csiPrefix = UInt8(v)
            } else if v >= 0x30 && v <= 0x39 {
                csiCur.append(Character(s))
            } else if v == 0x3B {
                // Semicolon: finalize current param with its colon sub-params
                if !csiColonSub.isEmpty {
                    csiColonSub.append(Int(csiCur) ?? 0)
                    csiParams.append(csiColonSub[0])
                    csiSubParams.append(csiColonSub)
                    csiColonSub = []
                } else {
                    csiParams.append(Int(csiCur) ?? 0)
                    csiSubParams.append([])
                }
                csiCur = ""
            } else if v == 0x3A {
                // Colon: push current value as sub-param of current parameter
                csiColonSub.append(Int(csiCur) ?? 0); csiCur = ""
            } else if v >= 0x40 && v <= 0x7E {
                // Finalize last param
                if !csiColonSub.isEmpty {
                    csiColonSub.append(Int(csiCur) ?? 0)
                    csiParams.append(csiColonSub[0])
                    csiSubParams.append(csiColonSub)
                } else {
                    csiParams.append(Int(csiCur) ?? 0)
                    csiSubParams.append([])
                }
                csiCur = ""; csiColonSub = []
                let final = UInt8(v)
                switch csiPrefix {
                case 0x3F: // CSI ? ...
                    if final == 0x75 { // CSI ? u — query kitty keyboard flags
                        onResponse?("\u{1B}[?\(kittyKbdFlags)u")
                    } else if csiIntermediate == 0x24 && final == 0x70 { // CSI ? Ps $ p — DECRQM
                        let mode = csiParams.first ?? 0
                        let status = queryPrivateMode(mode)
                        onResponse?("\u{1B}[?\(mode);\(status)$y")
                    } else {
                        doPrivate(csiParams, final)
                    }
                case 0x3E: doSecondaryPrefix(csiParams, final)
                case 0x3C: doLessThanPrefix(csiParams, final) // CSI < ...
                case 0:
                    if csiIntermediate == 0x20 { doCSISpace(csiParams, final) }       // CSI ... SP ...
                    else if csiIntermediate == 0x21 { doCSIBang(csiParams, final) }    // CSI ... ! ...
                    else if csiIntermediate == 0x22 { doCSIQuote(csiParams, final) }   // CSI ... " ...
                    else if csiIntermediate == 0x24 { doCSIDollar(csiParams, final) } // CSI ... $ ...
                    else { doCSI(csiParams, final) }
                default: break  // CSI = ... — silently ignore
                }
                pstate = .ground
            } else if v >= 0x20 && v <= 0x2F {
                csiIntermediate = UInt8(v)
            } else {
                pstate = .ground
            }

        case .osc:
            if v == 0x07 || v == 0x9C { handleOSC(); pstate = .ground }  // BEL or ST
            else if v == 0x1B { pstate = .oscEsc }
            else { oscBuf.append(Character(s)) }

        case .oscEsc:
            if v == 0x5C { handleOSC() }  // ESC \ = ST
            pstate = .ground

        case .dcs:
            diag.dcsCount += 1
            // DCS parameter parsing (same as CSI), then enter passthrough
            if v >= 0x30 && v <= 0x39 {
                csiCur.append(Character(s))
            } else if v == 0x3B {
                csiParams.append(Int(csiCur) ?? 0); csiCur = ""
            } else if v >= 0x40 && v <= 0x7E {
                if v == 0x71 { // DCS q — Sixel
                    sixelBuf.removeAll(keepingCapacity: true)
                    pstate = .dcsSixel
                } else {
                    pstate = .dcsPass
                }
            } else if v >= 0x20 && v <= 0x2F {
                // intermediate byte, continue
            } else {
                pstate = .dcsPass // any unexpected char → passthrough
            }

        case .dcsSixel:
            if v == 0x1B { parseSixelData(); pstate = .oscEsc }
            else if v == 0x9C || v == 0x07 { parseSixelData(); pstate = .ground }
            else { sixelBuf.append(UInt8(v & 0xFF)) }

        case .dcsPass:
            // Consume everything until ST (ESC \) or BEL
            if v == 0x1B { pstate = .oscEsc } // will handle ST
            else if v == 0x9C || v == 0x07 { pstate = .ground }
            // else: silently consume
        }
    }

    /// Effective column count for a line (halved for double-width/height lines)
    func effectiveCols(row: Int) -> Int {
        (row >= 0 && row < rows && lineAttrs[row] & 0x03 > 0) ? max(1, cols / 2) : cols
    }

    func put(_ s: Unicode.Scalar) {
        // Apply DEC Special Graphics charset mapping
        var s = s
        let graphicsActive = useG1 ? charsetG1IsGraphics : charsetG0IsGraphics
        if graphicsActive, s.value >= 0x60, s.value <= 0x7E,
           let mapped = Self.decGraphicsMap[s] {
            s = mapped
        }
        let w = unicodeWidth(s)
        let eCols = effectiveCols(row: cursorY)
        // Combining character: attach to previous cell
        if w == 0 {
            let prevCol = cursorX > 0 ? cursorX - 1 : (cursorY > 0 ? cols - 1 : -1)
            let prevRow = cursorX > 0 ? cursorY : cursorY - 1
            if prevRow >= 0, prevRow < rows, prevCol >= 0, prevCol < cols {
                let base = grid[prevRow][prevCol].char
                // Compose base + combining into a single character string, take first scalar
                let combined = String(base) + String(s)
                if let composed = combined.precomposedStringWithCanonicalMapping.unicodeScalars.first {
                    grid[prevRow][prevCol].char = composed
                }
            }
            return
        }
        let isWide = (w == 2)
        // Deferred wrap: if pending wrap flag is set, wrap now before placing next printable char
        if pendingWrap && autoWrapMode {
            lineAttrs[cursorY] |= 0x08  // mark as soft-wrapped (auto-wrap, not hard newline)
            cursorX = 0; pendingWrap = false; lf()
        }
        // Wide char at last column: wrap early (can't fit 2 cells)
        if isWide && autoWrapMode && cursorX == eCols - 1 {
            lineAttrs[cursorY] |= 0x08  // mark as soft-wrapped
            grid[cursorY][cursorX] = Cell(char: " ", attrs: attrs, width: 1)
            cursorX = 0; pendingWrap = false; lf()
        }
        guard cursorY >= 0, cursorY < rows, cursorX >= 0, cursorX < cols else { return }
        // IRM: insert mode — shift cells right before writing
        if insertMode {
            let shift = isWide ? 2 : 1
            if cursorX + shift < cols {
                for c in stride(from: cols - 1, through: cursorX + shift, by: -1) {
                    grid[cursorY][c] = grid[cursorY][c - shift]
                }
            }
        }
        if isWide && cursorX + 1 < cols {
            grid[cursorY][cursorX] = Cell(char: s, attrs: attrs, width: 2, hyperlink: currentHyperlink)
            grid[cursorY][cursorX + 1] = Cell(char: " ", attrs: attrs, width: 0, hyperlink: currentHyperlink)
            lastChar = s
            cursorX += 2
        } else {
            grid[cursorY][cursorX] = Cell(char: s, attrs: attrs, width: 1, hyperlink: currentHyperlink)
            lastChar = s
            cursorX += 1
        }
        // If cursor reached right margin, set pending wrap instead of advancing past it
        if cursorX >= eCols { cursorX = eCols - 1; pendingWrap = true }
    }

    func lf() {
        if cursorY == scrollBottom { scrollUp(1) }
        else if cursorY < rows - 1 { cursorY += 1 }
    }

    func rlf() {
        if cursorY == scrollTop { scrollDown(1) }
        else if cursorY > 0 { cursorY -= 1 }
    }

    func scrollUp(_ n: Int) {
        guard scrollBottom < rows && scrollTop < scrollBottom else { return }
        let useHMargins = leftRightMarginMode && (leftMargin > 0 || rightMargin < cols - 1)
        for _ in 0..<n {
            if useHMargins {
                // H-margin scroll: only cell content within the margin shifts.
                // Rows themselves stay in place → do NOT copy lineAttrs (would corrupt DW/soft-wrap flags).
                for i in scrollTop..<scrollBottom {
                    for x in leftMargin...rightMargin where x < cols {
                        grid[i][x] = grid[i + 1][x]
                    }
                }
                for x in leftMargin...rightMargin where x < cols {
                    grid[scrollBottom][x] = Cell()
                }
            } else {
                // Full-row scroll: push to scrollback only at screen top on the main screen.
                // Partial scroll regions (scrollTop > 0) and alt screen must NOT feed scrollback.
                if altGrid == nil && scrollTop == 0 {
                    scrollback.append(grid[scrollTop])
                    if scrollback.count > 10000 { scrollback.removeFirst() }
                }
                for i in scrollTop..<scrollBottom {
                    grid[i] = grid[i + 1]
                    lineAttrs[i] = lineAttrs[i + 1]
                }
                grid[scrollBottom] = Array(repeating: Cell(), count: cols)
                lineAttrs[scrollBottom] = 0
            }
        }
        // Adjust sixel images: only move those inside the scroll region; discard if scrolled past top.
        if !sixelImages.isEmpty {
            sixelImages = sixelImages.compactMap { img in
                if useHMargins { return img }  // H-margin: rows don't move
                guard img.row >= scrollTop && img.row <= scrollBottom else { return img }
                let newRow = img.row - n
                return newRow >= scrollTop ? (row: newRow, col: img.col, image: img.image) : nil
            }
        }
    }

    func scrollDown(_ n: Int) {
        guard scrollBottom < rows && scrollTop < scrollBottom else { return }
        let useHMargins = leftRightMarginMode && (leftMargin > 0 || rightMargin < cols - 1)
        for _ in 0..<n {
            if useHMargins {
                // Only partial columns shift — do NOT copy lineAttrs (DW/soft-wrap are whole-row flags)
                for i in stride(from: scrollBottom, to: scrollTop, by: -1) {
                    for x in leftMargin...rightMargin where x < cols {
                        grid[i][x] = grid[i - 1][x]
                    }
                }
                for x in leftMargin...rightMargin where x < cols {
                    grid[scrollTop][x] = Cell()
                }
            } else {
                for i in stride(from: scrollBottom, to: scrollTop, by: -1) {
                    grid[i] = grid[i - 1]
                    lineAttrs[i] = lineAttrs[i - 1]
                }
                grid[scrollTop] = Array(repeating: Cell(), count: cols)
                lineAttrs[scrollTop] = 0
            }
        }
    }

    func fullReset() {
        cursorX = 0; cursorY = 0; attrs = TextAttrs()
        scrollTop = 0; scrollBottom = rows - 1
        leftRightMarginMode = false; leftMargin = 0; rightMargin = cols - 1
        insertMode = false
        appCursorMode = false; appKeypadMode = false; bracketedPasteMode = false; autoWrapMode = true; pendingWrap = false; originMode = false; reverseVideoMode = false
        cursorVisible = true; cursorStyle = 0
        mouseMode = 0; mouseEncoding = 0; focusReportingMode = false
        synchronizedOutput = false
        charsetG0IsGraphics = false; charsetG1IsGraphics = false; useG1 = false
        currentHyperlink = nil
        paletteOverrides.removeAll()
        dynamicFG = nil; dynamicBG = nil; dynamicCursor = nil
        kittyKbdStack.removeAll()
        sixelImages.removeAll()
        altGrid = nil; altLineAttrs = nil
        grid = Self.emptyGrid(cols, rows)
        lineAttrs = Array(repeating: 0, count: rows)
        resetTabStops()
    }

    // MARK: Sixel Parser

    func parseSixelData() {
        guard !sixelBuf.isEmpty else { return }
        // Sixel format: each byte 0x3F-0x7E encodes 6 vertical pixels (subtract 0x3F)
        // '$' = carriage return (go to start of current 6-pixel band)
        // '-' = new line (advance 6 pixels down, go to start)
        // '#' followed by color index or color definition
        // '!' followed by repeat count and sixel char

        // Default Sixel palette (16 colors — VT340 compatible)
        var palette = [Int: (UInt8, UInt8, UInt8)]()
        let defaultColors: [(UInt8, UInt8, UInt8)] = [
            (0,0,0), (51,51,204), (51,204,51), (51,204,204),
            (204,51,51), (204,51,204), (204,204,51), (170,170,170),
            (85,85,85), (85,85,255), (85,255,85), (85,255,255),
            (255,85,85), (255,85,255), (255,255,85), (255,255,255)
        ]
        for (i, c) in defaultColors.enumerated() { palette[i] = c }

        var pixels = [[UInt8]]() // rows of [R,G,B,A, R,G,B,A, ...]
        var bandY = 0 // current band (each band = 6 pixel rows)
        var x = 0
        var maxX = 0
        var currentColor: (UInt8, UInt8, UInt8) = (255, 255, 255)
        var i = 0

        // Ensure 6 rows exist for a band
        func ensureRows(upTo row: Int) {
            while pixels.count <= row { pixels.append([]) }
        }

        // Draw sixel column at position (x, bandY) with 6-bit data
        func drawSixel(_ data: Int, at px: Int) {
            let neededBytes = (px + 1) * 4
            for bit in 0..<6 {
                if data & (1 << bit) != 0 {
                    let row = bandY * 6 + bit
                    ensureRows(upTo: row)
                    // Extend row in chunks of 256 pixels to avoid per-pixel growth
                    if pixels[row].count < neededBytes {
                        let chunkBytes = ((neededBytes + 1023) / 1024) * 1024
                        pixels[row].append(contentsOf: repeatElement(UInt8(0), count: chunkBytes - pixels[row].count))
                    }
                    let off = px * 4
                    pixels[row][off] = currentColor.0
                    pixels[row][off + 1] = currentColor.1
                    pixels[row][off + 2] = currentColor.2
                    pixels[row][off + 3] = 255
                }
            }
            if px >= maxX { maxX = px + 1 }
        }

        while i < sixelBuf.count {
            let b = sixelBuf[i]
            if b >= 0x3F && b <= 0x7E {
                // Sixel data byte
                drawSixel(Int(b) - 0x3F, at: x)
                x += 1
                i += 1
            } else if b == 0x24 { // $ — carriage return
                x = 0; i += 1
            } else if b == 0x2D { // - — new line
                bandY += 1; x = 0; i += 1
            } else if b == 0x21 { // ! — repeat
                i += 1
                var count = 0
                while i < sixelBuf.count && sixelBuf[i] >= 0x30 && sixelBuf[i] <= 0x39 {
                    count = count * 10 + Int(sixelBuf[i]) - 0x30
                    i += 1
                }
                if count == 0 { count = 1 }
                if i < sixelBuf.count && sixelBuf[i] >= 0x3F && sixelBuf[i] <= 0x7E {
                    let data = Int(sixelBuf[i]) - 0x3F
                    for _ in 0..<count { drawSixel(data, at: x); x += 1 }
                    i += 1
                }
            } else if b == 0x23 { // # — color control
                i += 1
                var colorIdx = 0
                while i < sixelBuf.count && sixelBuf[i] >= 0x30 && sixelBuf[i] <= 0x39 {
                    colorIdx = colorIdx * 10 + Int(sixelBuf[i]) - 0x30
                    i += 1
                }
                if i < sixelBuf.count && sixelBuf[i] == 0x3B {
                    // Color definition: #idx;type;a;b;c
                    i += 1
                    var nums = [Int]()
                    var cur = 0
                    while i < sixelBuf.count && (sixelBuf[i] >= 0x30 && sixelBuf[i] <= 0x39 || sixelBuf[i] == 0x3B) {
                        if sixelBuf[i] == 0x3B {
                            nums.append(cur); cur = 0
                        } else {
                            cur = cur * 10 + Int(sixelBuf[i]) - 0x30
                        }
                        i += 1
                    }
                    nums.append(cur)
                    if nums.count >= 4 && colorIdx >= 0 && colorIdx < 256 {
                        let type = nums[0]
                        let a = min(100, max(0, nums[1]))
                        let b2 = min(100, max(0, nums[2]))
                        let c = min(100, max(0, nums[3]))
                        if type == 2 {
                            // RGB (0-100 range)
                            palette[colorIdx] = (UInt8(a * 255 / 100), UInt8(b2 * 255 / 100), UInt8(c * 255 / 100))
                        } else if type == 1 {
                            // HLS → RGB conversion
                            let h = Double(a), l = Double(b2) / 100.0, s = Double(c) / 100.0
                            let r2: Double, g2: Double, b3: Double
                            if s == 0 { r2 = l; g2 = l; b3 = l }
                            else {
                                let q = l < 0.5 ? l * (1 + s) : l + s - l * s
                                let p = 2 * l - q
                                func hue2rgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
                                    var t = t; if t < 0 { t += 360 }; if t > 360 { t -= 360 }
                                    if t < 60 { return p + (q - p) * t / 60 }
                                    if t < 180 { return q }
                                    if t < 240 { return p + (q - p) * (240 - t) / 60 }
                                    return p
                                }
                                r2 = hue2rgb(p, q, h + 120); g2 = hue2rgb(p, q, h); b3 = hue2rgb(p, q, h - 120)
                            }
                            palette[colorIdx] = (UInt8(r2 * 255), UInt8(g2 * 255), UInt8(b3 * 255))
                        }
                    }
                }
                currentColor = palette[colorIdx] ?? (255, 255, 255)
            } else {
                i += 1 // skip unknown
            }
        }

        // Build CGImage from pixel data
        let width = maxX
        let height = pixels.count
        guard width > 0 && height > 0 else { sixelBuf.removeAll(); return }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let rowPixels = pixels[row]
            let copyLen = min(rowPixels.count, width * 4)
            for j in 0..<copyLen { rgba[row * width * 4 + j] = rowPixels[j] }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let provider = CGDataProvider(data: Data(rgba) as CFData),
           let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) {
            // Calculate how many terminal rows/cols this image occupies
            // (will be computed by TerminalView using cell dimensions)
            sixelImages.append((row: cursorY, col: cursorX, image: cgImage))
            onSixelImage?()
        }

        sixelBuf.removeAll(keepingCapacity: true)
    }

    /// Parse color spec: "rgb:RR/GG/BB", "rgb:RRRR/GGGG/BBBB", or "#RRGGBB"
    func parseColorSpec(_ spec: String) -> (UInt8, UInt8, UInt8)? {
        if spec.hasPrefix("rgb:") {
            let parts = spec.dropFirst(4).split(separator: "/")
            guard parts.count == 3 else { return nil }
            // Support both 2-digit (8-bit) and 4-digit (16-bit) hex components
            func parse(_ s: Substring) -> UInt8? {
                guard let v = UInt16(s, radix: 16) else { return nil }
                return s.count <= 2 ? UInt8(v) : UInt8(v >> 8)
            }
            guard let r = parse(parts[0]), let g = parse(parts[1]), let b = parse(parts[2]) else { return nil }
            return (r, g, b)
        } else if spec.hasPrefix("#") && spec.count == 7 {
            let hex = spec.dropFirst()
            guard let v = UInt32(hex, radix: 16) else { return nil }
            return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
        }
        return nil
    }

    func handleOSC() {
        diag.oscCount += 1
        let code: Int
        let text: String
        if let sep = oscBuf.firstIndex(of: ";") {
            code = Int(oscBuf[oscBuf.startIndex..<sep]) ?? -1
            text = String(oscBuf[oscBuf.index(after: sep)...])
        } else {
            code = Int(oscBuf) ?? -1
            text = ""
        }
        switch code {
        case 0, 2: currentTitle = text; onTitleChange?(text)
        case 1: break     // icon name — ignore
        case 4: // color palette — OSC 4;index;? ST (query) or OSC 4;index;spec ST (set)
            let parts = text.split(separator: ";", maxSplits: 2)
            if parts.count >= 2, let idx = Int(parts[0]), idx >= 0 && idx < 256 {
                if parts[1] == "?" {
                    let rgb = paletteOverrides[idx]
                    let c = rgb.map { NSColor(calibratedRed: CGFloat($0.0)/255, green: CGFloat($0.1)/255, blue: CGFloat($0.2)/255, alpha: 1) } ?? nsColorFromAnsi(idx)
                    let r = String(format: "%02x", Int(c.redComponent * 255))
                    let g = String(format: "%02x", Int(c.greenComponent * 255))
                    let b = String(format: "%02x", Int(c.blueComponent * 255))
                    onResponse?("\u{1B}]4;\(idx);rgb:\(r)/\(g)/\(b)\u{1B}\\")
                } else if let rgb = parseColorSpec(String(parts[1])) {
                    paletteOverrides[idx] = rgb
                    onColorChange?()
                }
            }
        case 7: // current working directory — OSC 7;file://host/path ST
            if text.hasPrefix("file://") {
                let path = text.dropFirst(7)
                if let slashIdx = path.firstIndex(of: "/") {
                    currentDirectory = String(path[slashIdx...])
                }
            }
        case 8: // hyperlinks — OSC 8 ; params ; uri ST
            // text is "params;uri" — params can be empty, uri can be empty (to end link)
            if let sep2 = text.firstIndex(of: ";") {
                let uri = String(text[text.index(after: sep2)...])
                currentHyperlink = uri.isEmpty ? nil : uri
            } else {
                currentHyperlink = nil
            }
        case 10, 11, 12: // Query or set fg/bg/cursor color
            if text == "?" {
                // Report current color
                let dyn: (UInt8, UInt8, UInt8)?
                let fallback: NSColor
                switch code {
                case 10: dyn = dynamicFG; fallback = kDefaultFG
                case 11: dyn = dynamicBG; fallback = kDefaultBG
                default: dyn = dynamicCursor; fallback = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
                }
                let c = dyn.map { NSColor(calibratedRed: CGFloat($0.0)/255, green: CGFloat($0.1)/255, blue: CGFloat($0.2)/255, alpha: 1) } ?? fallback
                let r = String(format: "%02x", Int(c.redComponent * 255))
                let g = String(format: "%02x", Int(c.greenComponent * 255))
                let b = String(format: "%02x", Int(c.blueComponent * 255))
                onResponse?("\u{1B}]\(code);rgb:\(r)/\(g)/\(b)\u{1B}\\")
            } else if let rgb = parseColorSpec(text) {
                switch code {
                case 10: dynamicFG = rgb
                case 11: dynamicBG = rgb
                default: dynamicCursor = rgb
                }
                onColorChange?()
            }
        case 52: // clipboard
            // Format: 52;<targets>;<data>  — targets is e.g. "c" (clipboard), "p" (primary)
            if let sep2 = text.firstIndex(of: ";") {
                let payload = String(text[text.index(after: sep2)...])
                if payload == "?" {
                    // Query: respond with base64-encoded clipboard contents
                    if let clipStr = NSPasteboard.general.string(forType: .string),
                       let clipData = clipStr.data(using: .utf8) {
                        let b64 = clipData.base64EncodedString()
                        let targets = String(text[text.startIndex..<sep2])
                        onResponse?("\u{1B}]52;\(targets);\(b64)\u{1B}\\")
                    }
                } else if !payload.isEmpty {
                    // Set: decode base64 and copy to clipboard
                    if let decoded = Data(base64Encoded: payload),
                       let str = String(data: decoded, encoding: .utf8) {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(str, forType: .string)
                    }
                }
            }
        case 104: // OSC 104 — reset palette color(s)
            if text.isEmpty {
                paletteOverrides.removeAll()
            } else {
                for part in text.split(separator: ";") {
                    if let idx = Int(part), idx >= 0 && idx < 256 {
                        paletteOverrides.removeValue(forKey: idx)
                    }
                }
            }
            onColorChange?()
        case 110: dynamicFG = nil; onColorChange?()      // reset foreground color
        case 111: dynamicBG = nil; onColorChange?()      // reset background color
        case 112: dynamicCursor = nil; onColorChange?()  // reset cursor color
        case 133: // semantic prompt / shell integration (FinalTerm/iTerm2)
            // text is a single letter: A=prompt start, B=command start, C=output start, D=command done
            if let mark = text.first {
                promptMarks.append((mark: mark, row: cursorY))
                // Keep only last 1000 marks to prevent unbounded growth
                if promptMarks.count > 1000 { promptMarks.removeFirst(promptMarks.count - 1000) }
            }
        default: diag.recordUnhandled("OSC \(code)")
        }
    }

    // MARK: CSI commands

    func doCSI(_ p: [Int], _ f: UInt8) {
        diag.csiCount += 1
        let n = p.first ?? 0
        switch f {
        case 0x40: insertChars(max(1, n))                                         // @ — ICH
        case 0x41: cursorY = max(scrollTop, cursorY - max(1, n)); pendingWrap = false  // A — CUU
        case 0x42: cursorY = min(scrollBottom, cursorY + max(1, n)); pendingWrap = false  // B — CUD
        case 0x43: cursorX = min(cols - 1, cursorX + max(1, n)); pendingWrap = false  // C — CUF
        case 0x44: cursorX = max(0, cursorX - max(1, n)); pendingWrap = false         // D — CUB
        case 0x45: cursorX = 0; cursorY = min(scrollBottom, cursorY + max(1, n)); pendingWrap = false  // E — CNL
        case 0x46: cursorX = 0; cursorY = max(scrollTop, cursorY - max(1, n)); pendingWrap = false     // F — CPL
        case 0x47: cursorX = max(0, min(cols - 1, (n > 0 ? n : 1) - 1)); pendingWrap = false  // G — CHA
        case 0x48, 0x66:                                                          // H/f — CUP
            let r = (p.count > 0 && p[0] > 0) ? p[0] : 1
            let c = (p.count > 1 && p[1] > 0) ? p[1] : 1
            if originMode {
                cursorY = max(scrollTop, min(scrollBottom, scrollTop + r - 1))
            } else {
                cursorY = max(0, min(rows - 1, r - 1))
            }
            cursorX = max(0, min(cols - 1, c - 1)); pendingWrap = false
        case 0x49: // I — CHT (cursor forward tab)
            for _ in 0..<max(1, n) { advanceToNextTab() }
        case 0x4A: eraseDisplay(n)                                                // J — ED
        case 0x4B: eraseLine(n)                                                   // K — EL
        case 0x4C: insertLines(max(1, n))                                         // L — IL
        case 0x4D: deleteLines(max(1, n))                                         // M — DL
        case 0x50: deleteChars(max(1, n))                                         // P — DCH
        case 0x53: scrollUp(max(1, n))                                            // S — SU
        case 0x54: scrollDown(max(1, n))                                          // T — SD
        case 0x58: eraseChars(max(1, n))                                          // X — ECH
        case 0x5A: // Z — CBT (cursor backward tab)
            for _ in 0..<max(1, n) { backToPrevTab() }
        case 0x60: cursorX = max(0, min(cols - 1, (n > 0 ? n : 1) - 1)); pendingWrap = false  // ` — HPA
        case 0x61: cursorX = min(cols - 1, cursorX + max(1, n)); pendingWrap = false           // a — HPR
        case 0x62: // b — REP (repeat preceding character)
            for _ in 0..<max(1, n) { put(lastChar) }
        case 0x63: // c — DA1
            if n == 0 { onResponse?("\u{1B}[?62;22c") }
        case 0x64: // d — VPA
            if originMode {
                cursorY = max(scrollTop, min(scrollBottom, scrollTop + (n > 0 ? n : 1) - 1))
            } else {
                cursorY = max(0, min(rows - 1, (n > 0 ? n : 1) - 1))
            }
            pendingWrap = false
        case 0x65: cursorY = min(rows - 1, cursorY + max(1, n)); pendingWrap = false  // e — VPR
        case 0x67: // g — TBC (tab clear)
            if n == 0 { tabStops.remove(cursorX) }       // clear tab at cursor
            else if n == 3 { tabStops.removeAll() }       // clear all tabs
        case 0x68: // h — SM (set mode)
            for mode in (p.isEmpty ? [0] : p) {
                if mode == 4 { insertMode = true }
                if mode == 20 { /* LNM auto newline — ignore */ }
            }
        case 0x6C: // l — RM (reset mode)
            for mode in (p.isEmpty ? [0] : p) {
                if mode == 4 { insertMode = false }
            }
        case 0x6D: doSGR(p.isEmpty ? [0] : p, csiSubParams)                       // m — SGR
        case 0x6E: // n — DSR
            if n == 6 {
                let reportY = originMode ? cursorY - scrollTop + 1 : cursorY + 1
                onResponse?("\u{1B}[\(reportY);\(cursorX + 1)R")
            }
            else if n == 5 { onResponse?("\u{1B}[0n") }
        case 0x72: // r — DECSTBM (set scroll region)
            let top = (p.count > 0 && p[0] > 0) ? p[0] - 1 : 0
            let bot = (p.count > 1 && p[1] > 0) ? p[1] - 1 : rows - 1
            scrollTop = max(0, min(rows - 1, top))
            scrollBottom = max(scrollTop, min(rows - 1, bot))
            cursorX = 0; cursorY = originMode ? scrollTop : 0; pendingWrap = false
        case 0x73: // s — SCOSC or DECSLRM
            if leftRightMarginMode && p.count >= 2 {
                // DECSLRM — set left/right margins
                let l = (p[0] > 0) ? p[0] - 1 : 0
                let r = (p[1] > 0) ? p[1] - 1 : cols - 1
                if l < r {
                    leftMargin = max(0, min(cols - 2, l))
                    rightMargin = max(leftMargin + 1, min(cols - 1, r))
                    cursorX = originMode ? leftMargin : 0
                    cursorY = originMode ? scrollTop : 0
                }
            } else {
                savedCursor = cursor  // SCOSC
            }
        case 0x74: // t — window operations (XTWINOPS)
            let ps = p.first ?? 0
            if ps == 8 {
                // CSI 8 ; rows ; cols t — resize text area
                let newRows = (p.count > 1 && p[1] > 0) ? p[1] : rows
                let newCols = (p.count > 2 && p[2] > 0) ? p[2] : cols
                onResize?(newRows, newCols)
            } else if ps == 14 {
                // Report window size in pixels (use actual cell dimensions)
                onResponse?("\u{1B}[4;\(rows * cellPixelHeight);\(cols * cellPixelWidth)t")
            } else if ps == 18 {
                // Report text area size in characters
                onResponse?("\u{1B}[8;\(rows);\(cols)t")
            } else if ps == 22 {
                // Push title to stack
                titleStack.append(currentTitle)
            } else if ps == 23 {
                // Pop title from stack
                if let title = titleStack.popLast() {
                    currentTitle = title
                    onTitleChange?(title)
                }
            }
        case 0x75: cursor = savedCursor                                            // u — SCORC
        default: diag.recordUnhandled("CSI \(String(format: "%c", f))")
        }
    }

    // CSI ... SP <final> — sequences with space intermediate byte
    func doCSISpace(_ p: [Int], _ f: UInt8) {
        switch f {
        case 0x71: // CSI Ps SP q — DECSCUSR (set cursor style)
            cursorStyle = p.first ?? 0
        default: break
        }
    }

    // CSI ... ! <final>
    func doCSIBang(_ p: [Int], _ f: UInt8) {
        switch f {
        case 0x70: // CSI ! p — DECSTR (soft reset)
            attrs = TextAttrs()
            cursorX = 0; cursorY = 0
            scrollTop = 0; scrollBottom = rows - 1
            leftRightMarginMode = false; leftMargin = 0; rightMargin = cols - 1
            appCursorMode = false; appKeypadMode = false; originMode = false; autoWrapMode = true; pendingWrap = false
            cursorVisible = true; cursorStyle = 0
            mouseMode = 0; mouseEncoding = 0; focusReportingMode = false
            synchronizedOutput = false
            charsetG0IsGraphics = false; charsetG1IsGraphics = false; useG1 = false
            currentHyperlink = nil
            kittyKbdStack.removeAll()
            resetTabStops()
        default: break
        }
    }

    // CSI ... " <final>
    func doCSIQuote(_ p: [Int], _ f: UInt8) {
        switch f {
        case 0x70: break // CSI " p — DECSCL (set conformance level) — ignore
        case 0x71: // CSI Ps " q — DECSCA (select char protection)
            let v = p.first ?? 0
            if v == 1 { attrs.protected = true }
            else { attrs.protected = false } // 0 or 2 = reset
        default: break
        }
    }

    // CSI ... $ <final>
    func doCSIDollar(_ p: [Int], _ f: UInt8) {
        switch f {
        case 0x70: // CSI Ps $ p — DECRQM (ANSI mode query)
            let mode = p.first ?? 0
            let status: Int
            switch mode {
            case 4: status = insertMode ? 1 : 2        // IRM
            case 20: status = 2                         // LNM — always reset
            default: status = 0                         // not recognized
            }
            onResponse?("\u{1B}[\(mode);\(status)$y")
        default: break
        }
    }

    func doSecondaryPrefix(_ p: [Int], _ f: UInt8) {
        switch f {
        case 0x63: onResponse?("\u{1B}[>1;0;0c")    // Secondary DA
        case 0x6D, 0x6E: break                       // XTMODKEYS — ignore
        case 0x71: // XTVERSION
            if p.first ?? 0 == 0 { onResponse?("\u{1B}P>|quickTerminal(1.0)\u{1B}\\") }
        case 0x75: // CSI > Ps u — push kitty keyboard mode
            let flags = p.first ?? 0
            kittyKbdStack.append(flags)
        default: break
        }
    }

    func doLessThanPrefix(_ p: [Int], _ f: UInt8) {
        switch f {
        case 0x75: // CSI < u — pop kitty keyboard mode
            let count = max(1, p.first ?? 1)
            for _ in 0..<count {
                if !kittyKbdStack.isEmpty { kittyKbdStack.removeLast() }
            }
        default: break
        }
    }

    func doPrivate(_ p: [Int], _ f: UInt8) {
        for n in (p.isEmpty ? [0] : p) {
            switch f {
            case 0x68: // CSI ? Ps h — set
                switch n {
                case 1: appCursorMode = true
                case 5: reverseVideoMode = true
                case 6: originMode = true; cursorX = 0; cursorY = scrollTop
                case 7: autoWrapMode = true
                case 12: break // cursor blink
                case 25: cursorVisible = true
                case 47, 1047:
                    altGrid = grid; altLineAttrs = lineAttrs; altCursor = cursor
                    grid = Self.emptyGrid(cols, rows); lineAttrs = Array(repeating: 0, count: rows)
                    cursorX = 0; cursorY = 0; scrollTop = 0; scrollBottom = rows - 1; pendingWrap = false
                case 1048: savedCursor = cursor
                case 1049:
                    savedCursor = cursor; savedAttrs = attrs
                    altGrid = grid; altLineAttrs = lineAttrs; altCursor = cursor
                    grid = Self.emptyGrid(cols, rows); lineAttrs = Array(repeating: 0, count: rows)
                    cursorX = 0; cursorY = 0; scrollTop = 0; scrollBottom = rows - 1; pendingWrap = false
                case 1000: mouseMode = 1000  // X10 normal tracking
                case 1002: mouseMode = 1002  // button-event tracking (report drag)
                case 1003: mouseMode = 1003  // any-event tracking (report all motion)
                case 1004: focusReportingMode = true
                case 1005: mouseEncoding = 1005  // UTF-8 encoding (legacy)
                case 1006: mouseEncoding = 1006  // SGR encoding
                case 1015, 1016: break // URXVT/SGR-Pixel — not widely used
                case 69: leftRightMarginMode = true
                case 2004: bracketedPasteMode = true
                case 2026: synchronizedOutput = true
                default: diag.recordUnhandled("CSI ? \(n) h")
                }
            case 0x6C: // CSI ? Ps l — reset
                switch n {
                case 1: appCursorMode = false
                case 5: reverseVideoMode = false
                case 6: originMode = false; cursorX = 0; cursorY = 0
                case 7: autoWrapMode = false
                case 12: break
                case 25: cursorVisible = false
                case 47, 1047:
                    if let ag = altGrid {
                        grid = ag; cursor = altCursor; cursor.pendingWrap = false; altGrid = nil
                        if let ala = altLineAttrs { lineAttrs = ala; altLineAttrs = nil }
                        scrollTop = 0; scrollBottom = rows - 1
                    }
                case 1048: cursor = savedCursor
                case 1049:
                    if let ag = altGrid {
                        grid = ag; altGrid = nil
                        if let ala = altLineAttrs { lineAttrs = ala; altLineAttrs = nil }
                        scrollTop = 0; scrollBottom = rows - 1
                    }
                    cursor = savedCursor; attrs = savedAttrs
                case 1000, 1002, 1003: mouseMode = 0
                case 1004: focusReportingMode = false
                case 1005, 1006: mouseEncoding = 0
                case 1015, 1016: break
                case 69: leftRightMarginMode = false; leftMargin = 0; rightMargin = cols - 1
                case 2004: bracketedPasteMode = false
                case 2026: synchronizedOutput = false
                default: diag.recordUnhandled("CSI ? \(n) l")
                }
            default: break
            }
        }
    }

    // DECRQM — query private mode: returns 1=set, 2=reset, 0=not recognized
    func queryPrivateMode(_ mode: Int) -> Int {
        switch mode {
        case 1: return appCursorMode ? 1 : 2
        case 5: return reverseVideoMode ? 1 : 2
        case 6: return originMode ? 1 : 2
        case 7: return autoWrapMode ? 1 : 2
        case 12: return 2 // cursor blink — always reset (we handle it in view)
        case 25: return cursorVisible ? 1 : 2
        case 47, 1047, 1049: return altGrid != nil ? 1 : 2
        case 69: return leftRightMarginMode ? 1 : 2
        case 1000, 1002, 1003: return mouseMode == mode ? 1 : 2
        case 1004: return focusReportingMode ? 1 : 2
        case 1006: return mouseEncoding == 1006 ? 1 : 2
        case 2004: return bracketedPasteMode ? 1 : 2
        case 2026: return synchronizedOutput ? 1 : 2
        default: return 0 // not recognized
        }
    }

    private func eraseCell(_ row: Int, _ col: Int) {
        if !grid[row][col].attrs.protected { grid[row][col] = Cell() }
    }

    private func eraseCellsInRow(_ row: Int, from: Int, to: Int) {
        for x in from...to where x < cols { eraseCell(row, x) }
    }

    private func eraseFullRow(_ row: Int) {
        let hasProtected = grid[row].contains { $0.attrs.protected }
        if hasProtected { eraseCellsInRow(row, from: 0, to: cols - 1) }
        else { grid[row] = Array(repeating: Cell(), count: cols) }
    }

    func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseCellsInRow(cursorY, from: cursorX, to: cols - 1)
            for y in (cursorY + 1)..<rows { eraseFullRow(y) }
        case 1:
            for y in 0..<cursorY { eraseFullRow(y) }
            eraseCellsInRow(cursorY, from: 0, to: min(cursorX, cols - 1))
        case 2:
            let hasAnyProtected = grid.contains { row in row.contains { $0.attrs.protected } }
            if hasAnyProtected { for y in 0..<rows { eraseFullRow(y) } }
            else { grid = Self.emptyGrid(cols, rows) }
        case 3:
            scrollback.removeAll()
            let hasAnyProtected = grid.contains { row in row.contains { $0.attrs.protected } }
            if hasAnyProtected { for y in 0..<rows { eraseFullRow(y) } }
            else { grid = Self.emptyGrid(cols, rows) }
        default: break
        }
    }

    func eraseLine(_ mode: Int) {
        guard cursorY >= 0, cursorY < rows else { return }
        switch mode {
        case 0: eraseCellsInRow(cursorY, from: cursorX, to: cols - 1)
        case 1: eraseCellsInRow(cursorY, from: 0, to: min(cursorX, cols - 1))
        case 2:
            eraseFullRow(cursorY)
            lineAttrs[cursorY] &= ~UInt8(0x08)  // clear soft-wrap flag on full-line erase
        default: break
        }
    }

    func insertLines(_ n: Int) {
        guard cursorY >= scrollTop, cursorY <= scrollBottom,
              scrollBottom < grid.count else { return }
        for _ in 0..<n {
            grid.insert(Array(repeating: Cell(), count: cols), at: cursorY)
            grid.remove(at: scrollBottom + 1)
            lineAttrs.insert(0, at: cursorY)
            lineAttrs.remove(at: scrollBottom + 1)
        }
    }

    func deleteLines(_ n: Int) {
        guard cursorY >= scrollTop, cursorY <= scrollBottom,
              cursorY < grid.count, scrollBottom < grid.count else { return }
        for _ in 0..<n {
            grid.remove(at: cursorY)
            grid.insert(Array(repeating: Cell(), count: cols), at: scrollBottom)
            lineAttrs.remove(at: cursorY)
            lineAttrs.insert(0, at: scrollBottom)
        }
    }

    func deleteChars(_ n: Int) {
        guard cursorY >= 0, cursorY < rows else { return }
        let rm = leftRightMarginMode ? min(rightMargin, cols - 1) : cols - 1
        for _ in 0..<n where cursorX <= rm {
            grid[cursorY].remove(at: cursorX)
            grid[cursorY].insert(Cell(), at: rm)
        }
    }

    func insertChars(_ n: Int) {
        guard cursorY >= 0, cursorY < rows else { return }
        let rm = leftRightMarginMode ? min(rightMargin, cols - 1) : cols - 1
        for _ in 0..<n where cursorX <= rm {
            grid[cursorY].remove(at: rm)
            grid[cursorY].insert(Cell(), at: cursorX)
        }
    }

    func eraseChars(_ n: Int) {
        guard cursorY >= 0, cursorY < rows else { return }
        for i in 0..<n { let x = cursorX + i; if x < cols { eraseCell(cursorY, x) } }
    }

    // MARK: SGR (colors / attributes)

    func doSGR(_ p: [Int], _ sub: [[Int]] = []) {
        var i = 0
        while i < p.count {
            let sp = i < sub.count ? sub[i] : []
            switch p[i] {
            case 0: attrs = TextAttrs()
            case 1: attrs.bold = true
            case 2: attrs.dim = true
            case 3: attrs.italic = true
            case 4:
                if !sp.isEmpty {
                    // Colon sub-params: 4:0=none, 4:1=single, 4:2=double, 4:3=curly, 4:4=dotted, 4:5=dashed
                    let style = sp.count > 1 ? sp[1] : (sp.count == 1 ? sp[0] : 1)
                    attrs.underline = UInt8(clamping: style)
                } else {
                    attrs.underline = 1
                }
            case 5: attrs.blink = 1   // slow blink
            case 6: attrs.blink = 2   // rapid blink
            case 7: attrs.inverse = true
            case 8: attrs.hidden = true
            case 9: attrs.strikethrough = true
            case 21: attrs.underline = 2  // double underline
            case 22: attrs.bold = false; attrs.dim = false
            case 23: attrs.italic = false
            case 24: attrs.underline = 0
            case 25: attrs.blink = 0
            case 27: attrs.inverse = false
            case 28: attrs.hidden = false
            case 29: attrs.strikethrough = false
            case 30...37: attrs.fg = p[i] - 30; attrs.fgRGB = nil
            case 38:
                if i+1 < p.count && p[i+1] == 5 && i+2 < p.count {
                    attrs.fg = p[i+2]; attrs.fgRGB = nil; i += 2
                } else if i+1 < p.count && p[i+1] == 2 {
                    // True color: support both 38;2;r;g;b and 38;2;id;r;g;b formats
                    if i+4 < p.count {
                        attrs.fgRGB = (UInt8(clamping: p[i+2]), UInt8(clamping: p[i+3]), UInt8(clamping: p[i+4])); i += 4
                    }
                }
            case 39: attrs.fg = 7; attrs.fgRGB = nil
            case 40...47: attrs.bg = p[i] - 40; attrs.bgRGB = nil
            case 48:
                if i+1 < p.count && p[i+1] == 5 && i+2 < p.count {
                    attrs.bg = p[i+2]; attrs.bgRGB = nil; i += 2
                } else if i+1 < p.count && p[i+1] == 2 {
                    if i+4 < p.count {
                        attrs.bgRGB = (UInt8(clamping: p[i+2]), UInt8(clamping: p[i+3]), UInt8(clamping: p[i+4])); i += 4
                    }
                }
            case 49: attrs.bg = 0; attrs.bgRGB = nil
            case 53: attrs.overline = true
            case 55: attrs.overline = false
            case 58: // underline color
                if !sp.isEmpty {
                    // Colon sub-param format: 58:5:idx or 58:2::[r]:[g]:[b]
                    let mode = sp.count > 1 ? sp[1] : sp[0]
                    if mode == 5 && sp.count > 2 {
                        attrs.ulColor = Int16(clamping: sp[2]); attrs.ulRGB = nil
                    } else if mode == 2 {
                        // 58:2::r:g:b or 58:2:r:g:b — colorspace ID is optional
                        let rIdx = sp.count > 4 ? 3 : 2
                        if rIdx + 2 < sp.count {
                            attrs.ulRGB = (UInt8(clamping: sp[rIdx]), UInt8(clamping: sp[rIdx+1]), UInt8(clamping: sp[rIdx+2]))
                            attrs.ulColor = -1
                        }
                    }
                } else if i+1 < p.count && p[i+1] == 5 && i+2 < p.count {
                    attrs.ulColor = Int16(clamping: p[i+2]); attrs.ulRGB = nil; i += 2
                } else if i+1 < p.count && p[i+1] == 2 && i+4 < p.count {
                    let r = UInt8(clamping: p[i+2]), g = UInt8(clamping: p[i+3]), b = UInt8(clamping: p[i+4])
                    attrs.ulRGB = (r, g, b); attrs.ulColor = -1; i += 4
                }
            case 59: attrs.ulColor = -1; attrs.ulRGB = nil  // default underline color
            case 90...97: attrs.fg = p[i] - 90 + 8; attrs.fgRGB = nil
            case 100...107: attrs.bg = p[i] - 100 + 8; attrs.bgRGB = nil
            default: break
            }
            i += 1
        }
    }

    // MARK: Resize

    /// Re-wrap soft-wrapped logical lines at a new column width.
    /// Rows marked with lineAttrs bit 0x08 are soft-wrapped continuations that can be rejoined.
    /// Hard-wrapped (non-joined) rows are only truncated/padded — never split into extra rows.
    private func reflowGrid(
        _ sourceGrid: [[Cell]], attrs sourceAttrs: [UInt8],
        fromCols: Int, toCols: Int,
        cursorRow: Int, cursorCol: Int
    ) -> (grid: [[Cell]], attrs: [UInt8], cursorRow: Int, cursorCol: Int) {
        guard fromCols != toCols, !sourceGrid.isEmpty else {
            return (sourceGrid, sourceAttrs, cursorRow, cursorCol)
        }

        // Group visual rows into logical lines.
        // 0x08 = currently soft-wrapped (row continues on next row).
        // 0x10 = formerly soft-wrapped (fits in one row now, but can be re-split when narrowing).
        // 0x00 = hard-wrapped (shell output, \n-terminated) — truncate, never split.
        var logicalCells:     [[Cell]] = []
        var logicalHasCursor: [Bool]   = []
        var logicalCursorOff: [Int]    = []
        var logicalIsReflow:  [Bool]   = []  // true → trim+re-wrap; false → truncate

        var r = 0
        while r < sourceGrid.count {
            var cells     = Array(sourceGrid[r].prefix(fromCols))
            var hasCursor = (r == cursorRow)
            var cursorOff = hasCursor ? min(cursorCol, fromCols - 1) : 0
            // 0x10 = "reflowable single row" — treat like a multi-row group
            var isReflow  = r < sourceAttrs.count && (sourceAttrs[r] & 0x10) != 0

            // Collect soft-wrapped continuation rows (0x08)
            while r < sourceGrid.count - 1 && r < sourceAttrs.count && (sourceAttrs[r] & 0x08) != 0 {
                r += 1
                isReflow = true
                if r == cursorRow {
                    hasCursor = true
                    cursorOff = cells.count + min(cursorCol, fromCols - 1)
                }
                cells += Array(sourceGrid[r].prefix(fromCols))
            }

            logicalCells.append(cells)
            logicalHasCursor.append(hasCursor)
            logicalCursorOff.append(cursorOff)
            logicalIsReflow.append(isReflow)
            r += 1
        }

        var newGrid:      [[Cell]] = []
        var newAttrs:     [UInt8]  = []
        var newCursorRow = 0
        var newCursorCol = 0

        for i in 0..<logicalCells.count {
            let cells     = logicalCells[i]
            let hasCursor = logicalHasCursor[i]
            let cursorOff = logicalCursorOff[i]
            let isReflow  = logicalIsReflow[i]

            if !isReflow {
                // Hard-wrapped single row: truncate or pad to toCols — never split.
                // This preserves traditional terminal behavior for shell output (\n-terminated lines).
                let end = min(toCols, cells.count)
                var chunk = Array(cells[0..<end])
                while chunk.count < toCols { chunk.append(Cell()) }
                newGrid.append(chunk)
                newAttrs.append(0x00)
                if hasCursor {
                    newCursorRow = newGrid.count - 1
                    newCursorCol = min(cursorOff, toCols - 1)
                }
                continue
            }

            // Reflowable logical line: trim trailing blanks + re-wrap at toCols.
            var mutableCells  = cells
            var mutableCursor = cursorOff
            var trimEnd = mutableCells.count
            while trimEnd > 0 {
                let c = mutableCells[trimEnd - 1]
                if c.char == " " && c.attrs == TextAttrs() && c.hyperlink == nil && c.width == 1 {
                    trimEnd -= 1
                } else { break }
            }
            mutableCells = Array(mutableCells[0..<trimEnd])
            if hasCursor && !mutableCells.isEmpty {
                mutableCursor = min(mutableCursor, mutableCells.count - 1)
            }

            if mutableCells.isEmpty {
                newGrid.append(Array(repeating: Cell(), count: toCols))
                newAttrs.append(0x00)
                if hasCursor { newCursorRow = newGrid.count - 1; newCursorCol = 0 }
                continue
            }

            var offset = 0
            repeat {
                var end = min(offset + toCols, mutableCells.count)
                // Don't split a wide-char pair (w=2 base + w=0 continuation) at chunk boundary.
                if end > offset && end < mutableCells.count && mutableCells[end - 1].width == 2 {
                    end -= 1  // wide char goes to next chunk; current chunk gets a padding space instead
                }
                var chunk     = Array(mutableCells[offset..<end])
                let isWrapped = end < mutableCells.count

                if hasCursor && mutableCursor >= offset && mutableCursor < offset + toCols {
                    newCursorRow = newGrid.count
                    newCursorCol = mutableCursor - offset
                }

                while chunk.count < toCols { chunk.append(Cell()) }
                newGrid.append(chunk)
                // Intermediate chunks: 0x08 (soft-wrapped, continues).
                // Final chunk: 0x10 (reflowable — marks it can be re-split if terminal narrows again).
                newAttrs.append(isWrapped ? 0x08 : 0x10)
                offset = end  // advance by actual cells consumed (handles wide-char backed-off case)
            } while offset < mutableCells.count
        }

        return (newGrid, newAttrs, newCursorRow, newCursorCol)
    }

    func resize(_ newCols: Int, _ newRows: Int) {
        guard newCols > 0, newRows > 0, newCols != cols || newRows != rows else { return }

        // Preserve content across vertical resize by using the scrollback buffer.
        // Only applies to main screen (alt screen has no scrollback).
        var workGrid = grid
        var workLineAttrs = lineAttrs
        var workCursorY = cursorY
        var workRows = rows

        if altGrid == nil {
            if newRows < rows {
                // Shrink: push rows above the cursor into scrollback so content isn't lost.
                let overflow = rows - newRows
                let pushable = min(overflow, workCursorY)
                if pushable > 0 {
                    for y in 0..<pushable {
                        scrollback.append(workGrid[y])
                        if scrollback.count > 10000 { scrollback.removeFirst() }
                    }
                    workGrid = Array(workGrid[pushable...])
                    workLineAttrs = Array(workLineAttrs[pushable...])
                    workCursorY -= pushable
                    workRows -= pushable
                }
            } else if newRows > rows {
                // Grow: pull rows from scrollback back onto the screen top.
                let needed = newRows - rows
                let available = min(needed, scrollback.count)
                if available > 0 {
                    let pulled = Array(scrollback.suffix(available))
                    scrollback.removeLast(available)
                    workGrid = pulled + workGrid
                    workLineAttrs = Array(repeating: UInt8(0), count: available) + workLineAttrs
                    workCursorY += available
                    workRows += available
                }
            }
        }

        // Column reflow: re-wrap soft-wrapped logical lines at new column width (main screen only)
        var workCursorX = cursorX
        if altGrid == nil && newCols != cols && workRows > 0 {
            let (rGrid, rAttrs, rCursorY, rCursorX) = reflowGrid(
                workGrid, attrs: workLineAttrs,
                fromCols: cols, toCols: newCols,
                cursorRow: workCursorY, cursorCol: cursorX
            )
            workGrid      = rGrid
            workLineAttrs = rAttrs
            workCursorY   = rCursorY
            workCursorX   = rCursorX
            workRows      = rGrid.count

            // Push excess rows from the top into scrollback if reflow expanded beyond newRows
            if workRows > newRows {
                let excess = workRows - newRows
                for y in 0..<excess {
                    scrollback.append(workGrid[y])
                    if scrollback.count > 10000 { scrollback.removeFirst() }
                }
                workGrid      = Array(workGrid[excess...])
                workLineAttrs = Array(workLineAttrs[excess...])
                workCursorY   = max(0, workCursorY - excess)
                workRows      = newRows
            }
        }

        var newGrid = Self.emptyGrid(newCols, newRows)
        var newLineAttrs = Array(repeating: UInt8(0), count: newRows)
        for y in 0..<min(workRows, newRows) {
            for x in 0..<min(workGrid[y].count, newCols) { newGrid[y][x] = workGrid[y][x] }
            if y < workLineAttrs.count { newLineAttrs[y] = workLineAttrs[y] }
        }
        if altGrid != nil {
            var newAlt = Self.emptyGrid(newCols, newRows)
            for y in 0..<min(rows, newRows) {
                for x in 0..<min(cols, newCols) { newAlt[y][x] = altGrid![y][x] }
            }
            altGrid = newAlt
            if altLineAttrs != nil {
                var newAltLA = Array(repeating: UInt8(0), count: newRows)
                for y in 0..<min(rows, newRows) { newAltLA[y] = altLineAttrs![y] }
                altLineAttrs = newAltLA
            }
        }
        grid = newGrid; lineAttrs = newLineAttrs; cols = newCols; rows = newRows
        scrollTop = 0; scrollBottom = newRows - 1
        leftMargin = 0; rightMargin = newCols - 1
        cursorX = min(workCursorX, newCols - 1)
        cursorY = min(workCursorY, newRows - 1)
        pendingWrap = false
        // Extend tab stops to cover new columns if needed
        tabStops = tabStops.filter { $0 < newCols }
        let maxTab = tabStops.max() ?? -1
        for i in stride(from: ((maxTab / 8) + 1) * 8, to: newCols, by: 8) { tabStops.insert(i) }
    }
}

// MARK: - BiDi / RTL Support

/// Check if a Unicode code point is a strong RTL character
func isStrongRTL(_ v: UInt32) -> Bool {
    (v >= 0x0590 && v <= 0x05FF) ||  // Hebrew
    (v >= 0x0600 && v <= 0x06FF) ||  // Arabic
    (v >= 0x0700 && v <= 0x074F) ||  // Syriac
    (v >= 0x0750 && v <= 0x077F) ||  // Arabic Supplement
    (v >= 0x0780 && v <= 0x07BF) ||  // Thaana
    (v >= 0x08A0 && v <= 0x08FF) ||  // Arabic Extended-A
    (v >= 0xFB1D && v <= 0xFDFF) ||  // Hebrew + Arabic Presentation Forms A
    (v >= 0xFE70 && v <= 0xFEFF) ||  // Arabic Presentation Forms B
    (v >= 0x10800 && v <= 0x10FFF)   // Other RTL scripts
}

/// Returns visual column ordering for a terminal line using Core Text bidi analysis.
/// Returns nil for LTR-only lines (no reordering needed).
/// For lines with RTL content, returns array where result[visualPos] = logicalCol.
func bidiVisualOrder(for line: [Cell], cols: Int) -> [Int]? {
    // Quick scan: skip if no RTL characters present
    var hasRTL = false
    for col in 0..<min(cols, line.count) {
        if isStrongRTL(line[col].char.value) { hasRTL = true; break }
    }
    guard hasRTL else { return nil }

    // Build string and track column mapping (string char index → grid column)
    var str = ""
    var charToCol: [Int] = []
    for col in 0..<min(cols, line.count) {
        if line[col].width == 0 { continue } // skip wide-char continuation
        str.append(String(line[col].char))
        charToCol.append(col)
        if line[col].width == 2 { charToCol.append(col) } // wide char occupies 2 visual positions
    }
    guard !str.isEmpty else { return nil }

    // Use Core Text for bidi analysis
    let attrStr = NSAttributedString(string: str, attributes: [
        .font: NSFont.systemFont(ofSize: 12)
    ])
    let ctLine = CTLineCreateWithAttributedString(attrStr)
    guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun], !runs.isEmpty else { return nil }

    // Build visual ordering from CTRun glyph runs
    var visualCols: [Int] = []
    for run in runs {
        let range = CTRunGetStringRange(run)
        let status = CTRunGetStatus(run)
        let isRTLRun = status.contains(.rightToLeft)

        if isRTLRun {
            // RTL run: traverse string indices in reverse
            for i in stride(from: range.location + range.length - 1, through: range.location, by: -1) {
                if i < charToCol.count { visualCols.append(charToCol[i]) }
            }
        } else {
            // LTR run: normal order
            for i in range.location..<(range.location + range.length) {
                if i < charToCol.count { visualCols.append(charToCol[i]) }
            }
        }
    }

    // Pad to full column count if needed
    let used = Set(visualCols)
    for col in 0..<cols where !used.contains(col) && line[col].width != 0 {
        visualCols.append(col)
    }

    return visualCols.isEmpty ? nil : visualCols
}

// MARK: - Utilities

func cwdForPid(_ pid: pid_t) -> String {
    let pathInfoSize = MemoryLayout<proc_vnodepathinfo>.size
    let pathInfo = UnsafeMutablePointer<proc_vnodepathinfo>.allocate(capacity: 1)
    defer { pathInfo.deallocate() }
    let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pathInfo, Int32(pathInfoSize))
    if ret > 0 {
        let cwd = withUnsafePointer(to: &pathInfo.pointee.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        if !cwd.isEmpty { return cwd }
    }
    return FileManager.default.currentDirectoryPath
}

// MARK: - Terminal View

// MARK: - Performance Metrics

struct PerfMetrics {
    // Draw metrics
    var drawCount = 0
    var drawTimeSum: Double = 0
    var lastDrawTime: Double = 0
    // PTY read metrics
    var readBytes = 0
    var readCount = 0
    // PTY write metrics
    var writeBytes = 0
    var writeCount = 0
    var writeRetries = 0
    // Computed rates (updated by sampling timer)
    var fps: Double = 0
    var avgDrawMs: Double = 0
    var readBytesPerSec = 0
    var writeBytesPerSec = 0
    var readsPerSec = 0
    var writesPerSec = 0
    // Snapshot interval
    var lastSampleTime: Double = CFAbsoluteTimeGetCurrent()

    mutating func sample() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - lastSampleTime
        guard dt > 0.01 else { return }
        fps = Double(drawCount) / dt
        avgDrawMs = drawCount > 0 ? (drawTimeSum / Double(drawCount)) * 1000 : 0
        readBytesPerSec = Int(Double(readBytes) / dt)
        writeBytesPerSec = Int(Double(writeBytes) / dt)
        readsPerSec = Int(Double(readCount) / dt)
        writesPerSec = Int(Double(writeCount) / dt)
        // Reset counters
        drawCount = 0; drawTimeSum = 0
        readBytes = 0; readCount = 0
        writeBytes = 0; writeCount = 0; writeRetries = 0
        lastSampleTime = now
    }
}

class TerminalView: NSView {
    let terminal: Terminal
    var masterFd: Int32 = -1
    var childPid: pid_t = 0
    var font: NSFont
    var boldFont: NSFont
    var italicFont: NSFont
    var boldItalicFont: NSFont
    var cellW: CGFloat
    var cellH: CGFloat
    var userCursorStyle = 0  // settings: 0=underline, 1=beam, 2=block (used when app sends DECSCUSR 0=default)
    var userCursorBlink = false
    let paddingX: CGFloat = 16
    let paddingY: CGFloat = 10
    var dirty = false
    var perf = PerfMetrics()
    var smoothScrollY: CGFloat = 0          // pixel offset into scrollback (0 = live)
    var scrollbackOffset: Int { max(0, Int(smoothScrollY / max(1, cellH))) }
    var scrollVelocity: CGFloat = 0
    var momentumTimer: Timer?
    var suppressResize = false
    private var winSizeWorkItem: DispatchWorkItem?  // debounce TIOCSWINSZ during sidebar drag
    private var isFirstResize = true               // fire TIOCSWINSZ immediately on first layout
    var source: DispatchSourceRead?
    var refreshTimer: Timer?
    var cursorBlinkOn = true
    var blinkTimer: Timer?
    var textBlinkVisible = true
    var textBlinkTimer: Timer?
    private var lastKeystrokeTime: TimeInterval = -.infinity
    private var dimColorCache: [NSColor: NSColor] = [:]
    private var a11yValueCache: String? = nil
    private var bidiCacheData: [[Int]?] = []
    private var bidiCacheValid: [Bool] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && terminal.focusReportingMode {
            writePTY("\u{1B}[I") // focus in
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result && terminal.focusReportingMode {
            writePTY("\u{1B}[O") // focus out
        }
        return result
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var mouseTrackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = mouseTrackingArea { removeTrackingArea(t) }
        mouseTrackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(mouseTrackingArea!)
    }

    private var settingsVisible: Bool {
        (NSApp.delegate as? AppDelegate)?.settingsOverlay != nil
    }

    /// Check if point (in window coords) is in the resize edge zone (top disabled)
    private func isInEdgeZone(_ event: NSEvent) -> Bool {
        guard let cv = window?.contentView else { return false }
        let e = BorderlessWindow.edgeInset
        let p = event.locationInWindow
        let b = cv.bounds
        return p.x < e || p.x > b.width - e || p.y < e
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !settingsVisible else { return }
        // Hover-to-activate: bring window to front when mouse enters
        // Skip if window was just hidden (e.g. via Ctrl+< hotkey) to prevent instant reappear
        if let w = window, !w.isKeyWindow {
            let ad = NSApp.delegate as? AppDelegate
            let sinceHide = ProcessInfo.processInfo.systemUptime - (ad?.lastHideTime ?? 0)
            if sinceHide > 0.5 {
                w.makeKeyAndOrderFront(nil)
                if #available(macOS 14.0, *) { NSApp.activate() }
                else { NSApp.activate(ignoringOtherApps: true) }
            }
        }
        if isInEdgeZone(event), let w = window as? BorderlessWindow {
            w.setEdgeCursor(at: event.locationInWindow)
            return
        }
        NSCursor.iBeam.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
        (NSApp.delegate as? AppDelegate)?.handleBorderHover(nearEdge: false)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !settingsVisible {
            let e = BorderlessWindow.edgeInset
            let w = bounds.width, h = bounds.height
            // Inner area: iBeam (top edge not reserved for resize)
            addCursorRect(NSRect(x: e, y: e, width: w - e * 2, height: h - e), cursor: .iBeam)
            // Edges: resize cursors (no top)
            addCursorRect(NSRect(x: 0, y: e, width: e, height: h - e), cursor: .resizeLeftRight)            // left
            addCursorRect(NSRect(x: w - e, y: e, width: e, height: h - e), cursor: .resizeLeftRight)        // right
            addCursorRect(NSRect(x: e, y: 0, width: w - e * 2, height: e), cursor: .resizeUpDown)           // bottom
            // Bottom corners (diagonal)
            addCursorRect(NSRect(x: 0, y: 0, width: e, height: e), cursor: BorderlessWindow.resizeNESW)     // bottomLeft
            addCursorRect(NSRect(x: w - e, y: 0, width: e, height: e), cursor: BorderlessWindow.resizeNWSE) // bottomRight
        }
    }

    // Available font families: (display name, regular name, bold name or nil)
    static let availableFonts: [(String, String, String?)] = [
        ("Fira Code", "Fira Code", "FiraCode-Bold"),
        ("JetBrains Mono", "JetBrains Mono Light", nil),
        ("Monocraft", "Monocraft", nil),
        ("Iosevka Thin", "Iosevka Thin", nil),
    ]

    // Get advance width of 'M' glyph — avoids maximumAdvancement returning CJK double-width
    static func monoAdvance(_ f: NSFont) -> CGFloat {
        var glyphs: [CGGlyph] = [0]
        var chars: [UniChar] = [0x4D] // 'M'
        CTFontGetGlyphsForCharacters(f, &chars, &glyphs, 1)
        if glyphs[0] != 0 {
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(f, .horizontal, &glyphs, &advance, 1)
            if advance.width > 0 { return ceil(advance.width) }
        }
        return f.maximumAdvancement.width
    }

    private static var fontsLoaded = false
    static func loadFonts() {
        guard !fontsLoaded else { return }
        fontsLoaded = true
        // Load FiraCode + Iosevka from files next to binary
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for name in ["_FiraCode-Regular-terminal.ttf", "_FiraCode-Bold-terminal.ttf", "_IosevkaThin-terminal.ttf"] {
            let fontURL = execURL.appendingPathComponent(name)
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
        // Load JetBrains Mono + Monocraft embedded in binary
        let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
        for (section, fileName) in [("__jbmono", "jbmono.ttf"), ("__monocraft", "monocraft.ttf")] {
            var size: UInt = 0
            guard let ptr = getsectiondata(header, "__FONTS", section, &size), size > 0 else { continue }
            let data = Data(bytes: ptr, count: Int(size))
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? data.write(to: tmpURL)
            CTFontManagerRegisterFontsForURL(tmpURL as CFURL, .process, nil)
        }
    }

    init(frameRect: NSRect, shell: String = "/bin/zsh", cwd: String? = nil, historyId: String? = nil) {
        Self.loadFonts()
        let fontSize = CGFloat(UserDefaults.standard.double(forKey: "terminalFontSize"))
        let fontIdx = UserDefaults.standard.integer(forKey: "fontFamily")
        let fontInfo = fontIdx < Self.availableFonts.count ? Self.availableFonts[fontIdx] : Self.availableFonts[0]
        font = NSFont(name: fontInfo.1, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = (fontInfo.2.flatMap { NSFont(name: $0, size: fontSize) })
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italicFont = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? font
        boldItalicFont = NSFont(descriptor: boldFont.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? boldFont
        cellW = Self.monoAdvance(font)
        cellH = ceil(font.ascender - font.descender + font.leading)
        let c = max(1, Int((frameRect.width - paddingX * 2) / cellW))
        let r = max(1, Int((frameRect.height - paddingY * 2) / cellH))
        terminal = Terminal(cols: c, rows: r)
        terminal.cellPixelWidth = Int(cellW); terminal.cellPixelHeight = Int(cellH)
        let savedCursor = UserDefaults.standard.integer(forKey: "cursorStyle")
        userCursorStyle = savedCursor
        userCursorBlink = UserDefaults.standard.bool(forKey: "cursorBlink")
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL, .string])
        currentShell = shell
        if let id = historyId { tabId = id }
        terminal.onSixelImage = { [weak self] in self?.dirty = true }
        terminal.onResponse = { [weak self] response in self?.writePTY(response) }
        terminal.onResize = { [weak self] rows, cols in
            guard let self = self, let win = self.window else { return }
            let newW = CGFloat(cols) * self.cellW + self.paddingX * 2
            let newH = CGFloat(rows) * self.cellH + self.paddingY * 2
            var frame = win.frame
            let dh = newH - win.contentView!.bounds.height
            frame.size.width = newW
            frame.size.height += dh
            frame.origin.y -= dh
            win.setFrame(frame, display: true, animate: true)
        }
        startPTY(shell: shell, cwd: cwd)
        startIO()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let s = self, s.dirty else { return }
            // Synchronized output: suppress redraws until mode is reset
            if s.terminal.synchronizedOutput { return }
            s.dirty = false
            s.needsDisplay = true
        }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - s.lastKeystrokeTime
            if elapsed >= 0.5 {
                s.cursorBlinkOn.toggle()
                s.needsDisplay = true
            }
        }
        textBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.textBlinkVisible.toggle()
            let hasBlinking = s.terminal.grid.contains { $0.contains { $0.attrs.blink > 0 } }
            if hasBlinking { s.needsDisplay = true }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        refreshTimer?.invalidate()
        blinkTimer?.invalidate()
        textBlinkTimer?.invalidate()
        momentumTimer?.invalidate()
        winSizeWorkItem?.cancel()
        source?.cancel()           // cancel handler closes masterFd
        let pid = childPid
        if pid > 0 { DispatchQueue.global().async { waitpid(pid, nil, 0) } }
    }

    // MARK: PTY

    static let availableShells: [(name: String, path: String)] = {
        let candidates = [
            ("zsh", "/bin/zsh"),
            ("bash", "/bin/bash"),
            ("sh", "/bin/sh"),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.1) }
    }()

    var currentShell = "/bin/zsh"
    var tabId: String = UUID().uuidString
    var shellReady = false

    // Resolved once at startup — safe to use in forked child
    static let shellConfigDir: String = {
        let execPath = CommandLine.arguments[0]
        let absPath = execPath.hasPrefix("/") ? execPath
            : FileManager.default.currentDirectoryPath + "/" + execPath
        return URL(fileURLWithPath: absPath).deletingLastPathComponent()
            .appendingPathComponent("shell").path
    }()

    func startPTY(shell: String, cwd: String? = nil) {
        currentShell = shell
        // Prepare all strings before fork (avoid Swift runtime in child)
        let homeDir = NSHomeDirectory()
        let histDir = "\(homeDir)/.quickterminal/history"
        let histPath = "\(histDir)/\(tabId)"
        let zdotdir = Self.shellConfigDir
        let syntaxHL = UserDefaults.standard.bool(forKey: "syntaxHighlighting")
        let promptTheme = UserDefaults.standard.string(forKey: "promptTheme") ?? "default"
        // Resolve start directory BEFORE fork — use C string to avoid Swift runtime in child
        let startDirC: UnsafeMutablePointer<CChar>
        if let dir = cwd, !dir.isEmpty, let dup = strdup(dir) {
            startDirC = dup
        } else if let dup = strdup(homeDir) {
            startDirC = dup
        } else {
            // Last resort — strdup("/tmp") should never fail in practice
            startDirC = strdup("/tmp") ?? strdup(".")!
        }
        var ws = winsize(ws_row: UInt16(terminal.rows), ws_col: UInt16(terminal.cols),
                         ws_xpixel: UInt16(frame.width), ws_ypixel: UInt16(frame.height))
        var fd: Int32 = 0
        let pid = forkpty(&fd, nil, nil, &ws)
        if pid == 0 {
            chdir(startDirC)
            setenv("TERM", "xterm-256color", 1)
            setenv("COLORTERM", "truecolor", 1)
            setenv("CLICOLOR", "1", 1)
            setenv("CLICOLOR_FORCE", "1", 1)
            if syntaxHL {
                setenv("QT_SYNTAX_HL", "1", 1)
            }
            setenv("LANG", "en_US.UTF-8", 1)
            setenv("LC_ALL", "en_US.UTF-8", 1)
            setenv("SHELL_SESSIONS_DISABLE", "1", 1)
            mkdir(histDir, 0o755)
            setenv("HISTFILE", histPath, 1)
            setenv("ZDOTDIR", zdotdir, 1)
            setenv("QT_PROMPT_THEME", promptTheme, 1)
            let bashrc = "\(zdotdir)/.bashrc"
            if shell == "/bin/bash" {
                var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("--rcfile"), strdup(bashrc), nil]
                execv(shell, &cArgs)
                _exit(1)
            }
            if shell == "/bin/sh" {
                setenv("ENV", "\(zdotdir)/.shrc", 1)
                var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("-i"), nil]
                execv(shell, &cArgs)
                _exit(1)
            }
            var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("--login"), nil]
            execv(shell, &cArgs)
            _exit(1)
        }
        // Parent process — free C string
        free(startDirC)
        if pid < 0 {
            // forkpty failed — leave fd/pid invalid so PTY reads/writes are no-ops
            masterFd = -1
            childPid = 0
            return
        }
        masterFd = fd
        childPid = pid
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    var isSwitching = false

    func switchShell(_ shell: String) {
        isSwitching = true
        shellReady = false
        // Tear down old session — cancel handler will close the old fd
        winSizeWorkItem?.cancel()
        let oldPid = childPid
        source?.cancel()
        source = nil
        masterFd = -1
        childPid = 0
        if oldPid > 0 {
            kill(oldPid, SIGHUP)
            DispatchQueue.global().async { waitpid(oldPid, nil, 0) }
        }
        // Reset terminal
        terminal.fullReset()
        terminal.scrollback.removeAll()
        // Start new PTY
        startPTY(shell: shell)
        startIO()
        isSwitching = false
        dirty = true
    }

    func startIO() {
        guard masterFd >= 0 else { return }
        let fd = masterFd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source?.setEventHandler { [weak self] in self?.readPTY() }
        source?.setCancelHandler { close(fd) }
        source?.resume()
    }

    var onShellExit: (() -> Void)?

    func readPTY() {
        // Capture source by reference so we only cancel THIS source, not a newer one
        // that may have been installed by a concurrent switchShell().
        let mySource = source
        let fd = masterFd
        var buf = [UInt8](repeating: 0, count: 32768)
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                perf.readBytes += n; perf.readCount += 1
                if !shellReady { shellReady = true }
                let sbBefore = terminal.scrollback.count
                terminal.process(Data(buf[0..<n]))
                // Keep viewport anchored when new rows arrive in scrollback
                if smoothScrollY > 0 {
                    let sbDelta = terminal.scrollback.count - sbBefore
                    if sbDelta != 0 {
                        smoothScrollY = max(0, smoothScrollY + CGFloat(sbDelta) * cellH)
                        clampScrollY()
                    }
                }
                dirty = true
                for i in bidiCacheValid.indices { bidiCacheValid[i] = false }
                a11yValueCache = nil
            } else {
                if n == 0 || (errno != EAGAIN && errno != EINTR) {
                    mySource?.cancel()
                    if source === mySource { source = nil }
                    let pid = childPid
                    if pid > 0 { DispatchQueue.global().async { waitpid(pid, nil, 0) } }
                    if !isSwitching {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            if let cb = self.onShellExit {
                                cb()
                            } else {
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
                break
            }
        }
    }

    func writePTY(_ data: Data) {
        let fd = masterFd
        guard fd >= 0 else { return }
        perf.writeBytes += data.count; perf.writeCount += 1
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var off = 0
            var retries = 0
            while off < data.count {
                let n = write(fd, base + off, data.count - off)
                if n > 0 {
                    off += n
                    retries = 0
                } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                    retries += 1
                    perf.writeRetries += 1
                    if retries > 5 { break } // 5ms max to avoid blocking main thread
                    usleep(1000)
                    continue
                } else {
                    break
                }
            }
        }
    }

    func writePTY(_ string: String) {
        if let d = string.data(using: .utf8) { writePTY(d) }
    }

    // MARK: Drawing

    private static let emptyCell = Cell()
    private static let badgeAttrsDict: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.7)
    ]
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]

    /// Resolve a display row to the correct cell in the combined buffer
    /// (scrollback[0..S-1] + grid[0..R-1]), given an absolute buffer index.
    private func cellForDisplay(bufferIndex: Int, col: Int, scrollbackCount S: Int) -> Cell {
        if bufferIndex < 0 { return Self.emptyCell }
        if bufferIndex < S {
            let sbLine = terminal.scrollback[bufferIndex]
            return col < sbLine.count ? sbLine[col] : Self.emptyCell
        }
        let gridRow = bufferIndex - S
        if gridRow < terminal.rows && col < terminal.grid[gridRow].count {
            return terminal.grid[gridRow][col]
        }
        return Self.emptyCell
    }

    override func draw(_ dirtyRect: NSRect) {
        let drawStart = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - drawStart
            perf.drawCount += 1
            perf.drawTimeSum += elapsed
            perf.lastDrawTime = elapsed
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(kTermBgCGColor)
        ctx.fill(bounds)

        let isScrolledBack = smoothScrollY > 0.5
        let subPixel = smoothScrollY.truncatingRemainder(dividingBy: cellH)
        let lineOff = scrollbackOffset

        // How many display rows we need (one extra for partial line at top)
        let extraTop = subPixel > 0.001 ? 1 : 0
        let totalRows = terminal.rows + extraTop

        // Pre-compute selection range (also shown when scrolled back so selection stays visible)
        let selRange = selectionRange()
        let lastTextCols: [Int] = selRange != nil
            ? (0..<terminal.rows).map { lastTextCol(row: $0) }
            : []

        // Clip to terminal content area
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: paddingY, width: bounds.width, height: CGFloat(terminal.rows) * cellH))

        let S = terminal.scrollback.count
        let baseIndex = S - lineOff  // first visible line in combined buffer

        for vrow in 0..<totalRows {
            // Absolute index in combined buffer (scrollback + grid)
            let bufIdx = baseIndex - extraTop + vrow
            let drawY = CGFloat(vrow - extraTop) * cellH + paddingY + subPixel

            // Double-width/height line attributes
            let la: UInt8 = (!isScrolledBack && vrow >= 0 && vrow < terminal.rows) ? terminal.lineAttrs[vrow] : 0
            let effectiveCols = (la & 0x03 > 0) ? max(1, terminal.cols / 2) : terminal.cols
            if la & 0x03 > 0 {
                ctx.saveGState()
                if la >= 2 { // double-height (top or bottom)
                    ctx.clip(to: CGRect(x: 0, y: drawY, width: bounds.width, height: cellH))
                    let ay = (la == 2) ? drawY : drawY + cellH
                    ctx.translateBy(x: paddingX, y: ay)
                    ctx.scaleBy(x: 2, y: 2)
                    ctx.translateBy(x: -paddingX, y: -ay)
                } else { // double-width only
                    ctx.translateBy(x: paddingX, y: 0)
                    ctx.scaleBy(x: 2, y: 1)
                    ctx.translateBy(x: -paddingX, y: 0)
                }
            }

            // BiDi: compute visual ordering for this row (cached per row, invalidated on PTY read)
            let bidiOrder: [Int]?
            if !isScrolledBack && vrow >= 0 && vrow < terminal.rows {
                // Resize cache if terminal rows changed
                if bidiCacheData.count != terminal.rows {
                    bidiCacheData = Array(repeating: nil, count: terminal.rows)
                    bidiCacheValid = Array(repeating: false, count: terminal.rows)
                }
                if bidiCacheValid[vrow] {
                    bidiOrder = bidiCacheData[vrow]
                } else {
                    let computed = bidiVisualOrder(for: terminal.grid[vrow], cols: effectiveCols)
                    bidiCacheData[vrow] = computed
                    bidiCacheValid[vrow] = true
                    bidiOrder = computed
                }
            } else { bidiOrder = nil }

            for vpos in 0..<effectiveCols {
                let col = bidiOrder != nil && vpos < bidiOrder!.count ? bidiOrder![vpos] : vpos
                let cell: Cell
                if isScrolledBack {
                    cell = cellForDisplay(bufferIndex: bufIdx, col: col, scrollbackCount: S)
                } else if vrow < terminal.rows && col < terminal.grid[vrow].count {
                    cell = terminal.grid[vrow][col]
                } else {
                    cell = Self.emptyCell
                }
                if cell.width == 0 { continue }
                let x = CGFloat(vpos) * cellW + paddingX
                let cw = cell.width == 2 ? cellW * 2 : cellW

                var fg = fgColor(for: cell.attrs, terminal: terminal)
                var bg = bgColor(for: cell.attrs, terminal: terminal)
                if cell.attrs.inverse { swap(&fg, &bg) }
                if terminal.reverseVideoMode { swap(&fg, &bg) }
                if cell.attrs.hidden { fg = bg }

                var selected = false
                if let (lo, hi) = selRange {
                    // When scrolled back, screen row 0 is at visual row lineOff
                    let screenRow = isScrolledBack ? vrow - lineOff : vrow
                    if screenRow >= 0, screenRow < terminal.rows, screenRow < lastTextCols.count {
                        let cur = screenRow * terminal.cols + col
                        selected = cur >= lo && cur <= hi && col <= lastTextCols[screenRow]
                    }
                }

                if selected {
                    ctx.setFillColor(kSelectionCGColor)
                    ctx.fill(CGRect(x: x, y: drawY, width: cw, height: cellH))
                } else if bg != kDefaultBG {
                    ctx.setFillColor(bg.cgColor)
                    ctx.fill(CGRect(x: x, y: drawY, width: cw, height: cellH))
                }

                let blinkHidden = cell.attrs.blink > 0 && !textBlinkVisible
                if cell.char != " " && cell.char != "\0" && !blinkHidden {
                    let s = String(cell.char)
                    let f: NSFont
                    if cell.attrs.bold {
                        f = cell.attrs.italic ? boldItalicFont : boldFont
                    } else {
                        f = cell.attrs.italic ? italicFont : font
                    }
                    let textColor: NSColor
                    if cell.attrs.dim {
                        if let cached = dimColorCache[fg] {
                            textColor = cached
                        } else {
                            let c = fg.withAlphaComponent(0.5)
                            dimColorCache[fg] = c
                            textColor = c
                        }
                    } else {
                        textColor = fg
                    }
                    NSAttributedString(string: s, attributes: [
                        .font: f, .foregroundColor: textColor
                    ]).draw(at: NSPoint(x: x, y: drawY))
                }

                if cell.attrs.underline > 0 || cell.hyperlink != nil {
                    let ulCG: CGColor
                    if cell.hyperlink != nil {
                        ulCG = kHyperlinkCGColor
                    } else if let rgb = cell.attrs.ulRGB {
                        ulCG = CGColor(red: CGFloat(rgb.0)/255, green: CGFloat(rgb.1)/255, blue: CGFloat(rgb.2)/255, alpha: 1)
                    } else if cell.attrs.ulColor >= 0 && Int(cell.attrs.ulColor) < kAnsiColorCache.count {
                        ulCG = kAnsiColorCache[Int(cell.attrs.ulColor)].cgColor
                    } else {
                        ulCG = fg.cgColor
                    }
                    ctx.setStrokeColor(ulCG)
                    ctx.setLineWidth(1)
                    let uy = drawY + cellH - 2
                    let style = cell.hyperlink != nil ? UInt8(1) : cell.attrs.underline
                    switch style {
                    case 1: // single straight line
                        if cell.hyperlink != nil { ctx.setLineDash(phase: 0, lengths: [2, 2]) }
                        ctx.move(to: CGPoint(x: x, y: uy))
                        ctx.addLine(to: CGPoint(x: x + cw, y: uy))
                        ctx.strokePath()
                        if cell.hyperlink != nil { ctx.setLineDash(phase: 0, lengths: []) }
                    case 2: // double underline
                        ctx.move(to: CGPoint(x: x, y: uy))
                        ctx.addLine(to: CGPoint(x: x + cw, y: uy))
                        ctx.strokePath()
                        ctx.move(to: CGPoint(x: x, y: uy - 2))
                        ctx.addLine(to: CGPoint(x: x + cw, y: uy - 2))
                        ctx.strokePath()
                    case 3: // curly underline (wave)
                        let path = CGMutablePath()
                        let waveH: CGFloat = 2
                        let step: CGFloat = cw / 4
                        path.move(to: CGPoint(x: x, y: uy))
                        path.addCurve(to: CGPoint(x: x + step * 2, y: uy),
                                      control1: CGPoint(x: x + step, y: uy - waveH),
                                      control2: CGPoint(x: x + step, y: uy - waveH))
                        path.addCurve(to: CGPoint(x: x + cw, y: uy),
                                      control1: CGPoint(x: x + step * 3, y: uy + waveH),
                                      control2: CGPoint(x: x + step * 3, y: uy + waveH))
                        ctx.addPath(path)
                        ctx.strokePath()
                    case 4: // dotted
                        ctx.setLineDash(phase: 0, lengths: [1, 2])
                        ctx.move(to: CGPoint(x: x, y: uy))
                        ctx.addLine(to: CGPoint(x: x + cw, y: uy))
                        ctx.strokePath()
                        ctx.setLineDash(phase: 0, lengths: [])
                    case 5: // dashed
                        ctx.setLineDash(phase: 0, lengths: [4, 2])
                        ctx.move(to: CGPoint(x: x, y: uy))
                        ctx.addLine(to: CGPoint(x: x + cw, y: uy))
                        ctx.strokePath()
                        ctx.setLineDash(phase: 0, lengths: [])
                    default:
                        ctx.move(to: CGPoint(x: x, y: uy))
                        ctx.addLine(to: CGPoint(x: x + cw, y: uy))
                        ctx.strokePath()
                    }
                }

                if cell.attrs.overline {
                    ctx.setStrokeColor(fg.cgColor)
                    ctx.setLineWidth(1)
                    let oy = drawY + 1
                    ctx.move(to: CGPoint(x: x, y: oy))
                    ctx.addLine(to: CGPoint(x: x + cw, y: oy))
                    ctx.strokePath()
                }

                if cell.attrs.strikethrough {
                    ctx.setStrokeColor(fg.cgColor)
                    ctx.setLineWidth(1)
                    let sy = drawY + cellH / 2
                    ctx.move(to: CGPoint(x: x, y: sy))
                    ctx.addLine(to: CGPoint(x: x + cw, y: sy))
                    ctx.strokePath()
                }
            }
            if la & 0x03 > 0 { ctx.restoreGState() }
        }

        ctx.restoreGState()

        // Search highlights
        if let appDel = NSApp.delegate as? AppDelegate, !appDel.searchHighlights.isEmpty {
            let scrollLines = terminal.scrollback.count
            let activeIdx = appDel.searchCurrentIndex
            let cornerR: CGFloat = 3
            let insetV: CGFloat = 1

            for (i, hl) in appDel.searchHighlights.enumerated() {
                let screenRow: Int
                if hl.row < 0 {
                    let scrollIdx = scrollLines + hl.row
                    let visRow = scrollIdx - (scrollLines - lineOff)
                    screenRow = visRow
                } else {
                    if isScrolledBack { continue }
                    screenRow = hl.row
                }
                if screenRow < 0 || screenRow >= terminal.rows + extraTop { continue }
                let hy = CGFloat(screenRow) * cellH + paddingY + subPixel + insetV
                let hx = CGFloat(hl.col) * cellW + paddingX
                let hw = CGFloat(hl.len) * cellW
                let rect = CGRect(x: hx, y: hy, width: hw, height: cellH - insetV * 2)
                let path = CGPath(roundedRect: rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

                if i == activeIdx {
                    // Active match: glow + fill + border
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 8, color: NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 0.7).cgColor)
                    ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.0, alpha: 0.55).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                    ctx.restoreGState()
                    ctx.setStrokeColor(NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.3, alpha: 0.9).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.addPath(path)
                    ctx.strokePath()
                } else {
                    // Passive match: subtle fill + bottom accent line
                    ctx.setFillColor(NSColor(calibratedRed: 0.9, green: 0.75, blue: 0.2, alpha: 0.22).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                    let underY = hy + cellH - insetV * 2 - 1
                    ctx.setStrokeColor(NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.0, alpha: 0.4).cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.move(to: CGPoint(x: hx + 1, y: underY))
                    ctx.addLine(to: CGPoint(x: hx + hw - 1, y: underY))
                    ctx.strokePath()
                }
            }
        }

        // Cursor — only when live (not scrolled back) and focused
        if !isScrolledBack {
            let isFocused = window?.isKeyWindow == true && window?.firstResponder === self
            let appCS = terminal.cursorStyle
            let cs: Int
            if appCS == 0 {
                let blink = userCursorBlink
                switch userCursorStyle {
                case 1: cs = blink ? 5 : 6
                case 2: cs = blink ? 1 : 2
                default: cs = blink ? 3 : 4
                }
            } else {
                cs = appCS
            }
            let cursorBlinks = (cs == 1 || cs == 3 || cs == 5)
            let showCursor = terminal.cursorVisible && isFocused && (!cursorBlinks || cursorBlinkOn)
            if showCursor {
                let cx = CGFloat(terminal.cursorX) * cellW + paddingX
                let cy = CGFloat(terminal.cursorY) * cellH + paddingY
                ctx.setFillColor(kCursorCGColor)
                switch cs {
                case 3, 4:
                    let lineH: CGFloat = 2
                    ctx.fill(CGRect(x: cx, y: cy + cellH - lineH, width: cellW, height: lineH))
                case 5, 6:
                    ctx.fill(CGRect(x: cx, y: cy, width: 2, height: cellH))
                default:
                    ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 0.35).cgColor)
                    ctx.fill(CGRect(x: cx, y: cy, width: cellW, height: cellH))
                }
            }
        }

        // Sixel images (only in live view)
        if !isScrolledBack {
            for img in terminal.sixelImages {
                let ix = CGFloat(img.col) * cellW + paddingX
                let iy = CGFloat(img.row) * cellH + paddingY
                let imgW = CGFloat(img.image.width)
                let imgH = CGFloat(img.image.height)
                let maxW = CGFloat(terminal.cols - img.col) * cellW
                let scale = min(1.0, maxW / imgW)
                let drawW = imgW * scale
                let drawH = imgH * scale
                ctx.saveGState()
                ctx.translateBy(x: ix, y: iy + drawH)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img.image, in: CGRect(x: 0, y: 0, width: drawW, height: drawH))
                ctx.restoreGState()
            }
        }

        // Scrollback indicator badge
        if isScrolledBack {
            let text = "\u{2191} \(lineOff) lines"
            let nsStr = NSAttributedString(string: text, attributes: Self.badgeAttrsDict)
            let sz = nsStr.size()
            let badgeW = sz.width + 12
            let badgeH = sz.height + 4
            let badgeX = bounds.width - badgeW - 8
            let badgeY: CGFloat = 4
            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
            ctx.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.85).cgColor)
            let path = CGPath(roundedRect: badgeRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
            nsStr.draw(at: NSPoint(x: badgeX + 6, y: badgeY + 2))
        }

    }

    // MARK: Keyboard

    // Kitty keyboard protocol: encode a key event as CSI codepoint ; modifiers u
    private func kittyEncode(event: NSEvent, isRelease: Bool = false) -> String? {
        let flags = terminal.kittyKbdFlags
        guard flags > 0 else { return nil }
        // Flag bit 1 (report event types): if not set, ignore release events
        if isRelease && flags & 2 == 0 { return nil }
        var mods = 0
        let nsFlags = event.modifierFlags
        if nsFlags.contains(.shift) { mods |= 1 }
        if nsFlags.contains(.option) { mods |= 2 }
        if nsFlags.contains(.control) { mods |= 4 }
        if nsFlags.contains(.command) { mods |= 8 }
        let codepoint: Int
        switch event.keyCode {
        case 36: codepoint = 13       // Return
        case 48: codepoint = 9        // Tab
        case 51: codepoint = 127      // Backspace
        case 53: codepoint = 27       // Escape
        case 114: codepoint = 57348   // Insert
        case 117: codepoint = 57367   // Delete
        case 123: codepoint = 57419   // Left
        case 124: codepoint = 57421   // Right
        case 125: codepoint = 57420   // Down
        case 126: codepoint = 57418   // Up
        case 115: codepoint = 57423   // Home
        case 119: codepoint = 57424   // End
        case 116: codepoint = 57425   // PageUp
        case 121: codepoint = 57426   // PageDown
        case 76: codepoint = 57414    // KP Enter
        case 122: codepoint = 57376   // F1
        case 120: codepoint = 57377   // F2
        case 99: codepoint = 57378    // F3
        case 118: codepoint = 57379   // F4
        case 96: codepoint = 57380    // F5
        case 97: codepoint = 57381    // F6
        case 98: codepoint = 57382    // F7
        case 100: codepoint = 57383   // F8
        case 101: codepoint = 57384   // F9
        case 109: codepoint = 57385   // F10
        case 103: codepoint = 57386   // F11
        case 111: codepoint = 57387   // F12
        default:
            if let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first {
                let v = Int(scalar.value)
                // Flag bit 0 (disambiguate): plain printable keys without modifiers → normal encoding
                if flags & 1 != 0 && mods == 0 && v >= 0x20 && v < 0x7F && !isRelease { return nil }
                codepoint = v
            } else { return nil }
        }
        let modParam = mods + 1
        // Flag bit 1 (report event types): append :eventType (1=press, 2=repeat, 3=release)
        let eventType: Int = isRelease ? 3 : (event.isARepeat ? 2 : 1)
        let reportEventType = flags & 2 != 0
        // Flag bit 2 (report alternate keys): append alternate key codepoint
        var altKey = ""
        if flags & 4 != 0, let chars = event.characters, let shifted = chars.unicodeScalars.first {
            let sv = Int(shifted.value)
            if sv != codepoint && sv >= 0x20 { altKey = ";\(sv)" } // shifted variant differs
        }
        // Build response: CSI codepoint ; modifiers:eventType u
        if modParam > 1 || reportEventType {
            let eventSuffix = reportEventType ? ":\(eventType)" : ""
            return "\u{1B}[\(codepoint);\(modParam)\(eventSuffix)\(altKey)u"
        } else {
            return "\u{1B}[\(codepoint)\(altKey)u"
        }
    }

    @objc func switchToShell1(_ sender: Any?) {
        if Self.availableShells.count > 0 { switchShell(Self.availableShells[0].path) }
    }
    @objc func switchToShell2(_ sender: Any?) {
        if Self.availableShells.count > 1 { switchShell(Self.availableShells[1].path) }
    }
    @objc func switchToShell3(_ sender: Any?) {
        if Self.availableShells.count > 2 { switchShell(Self.availableShells[2].path) }
    }
    @objc func clearScrollback(_ sender: Any?) {
        terminal.scrollback.removeAll()
        terminal.grid = Terminal.emptyGrid(terminal.cols, terminal.rows)
        terminal.cursorX = 0; terminal.cursorY = 0
        smoothScrollY = 0; stopMomentum()
        selStart = nil; selEnd = nil
        dirty = true
        // Re-draw prompt by sending clear to shell
        writePTY("\u{0C}") // Ctrl+L (form feed) → shell redraws prompt
    }

    private static let numberKeyCodes: [UInt16: Int] = [
        18:0, 19:1, 20:2, 21:3, 23:4, 22:5, 26:6, 28:7, 25:8
    ]

    override func keyDown(with event: NSEvent) {
        guard shellReady else { return }
        if smoothScrollY > 0 { smoothScrollY = 0; scrollAccumulator = 0; stopMomentum(); dirty = true; needsDisplay = true }
        cursorBlinkOn = true
        lastKeystrokeTime = ProcessInfo.processInfo.systemUptime
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if flags.contains(.command) {
            // Cmd+Arrow Left/Right → switch tabs
            if event.keyCode == 123 { // Left arrow
                if let d = NSApp.delegate as? AppDelegate {
                    let prev = d.activeTab > 0 ? d.activeTab - 1 : d.splitContainers.count - 1
                    d.switchToTab(prev)
                }
                return
            }
            if event.keyCode == 124 { // Right arrow
                if let d = NSApp.delegate as? AppDelegate {
                    let next = d.activeTab < d.splitContainers.count - 1 ? d.activeTab + 1 : 0
                    d.switchToTab(next)
                }
                return
            }
            // Cmd+⌥+1/2/3/4: Fenster-Presets (muss vor Cmd+1-3 Shell-Switch stehen)
            if flags.contains(.option) {
                if let d = NSApp.delegate as? AppDelegate {
                    switch event.keyCode {
                    case 18: d.resetWindowSize();   return   // 1 → Default
                    case 19: d.snapLeft();           return   // 2 → Links
                    case 20: d.snapRight();          return   // 3 → Rechts
                    case 21: d.toggleFullscreen();   return   // 4 → Vollbild
                    default: break
                    }
                }
            }
            // Cmd+1/2/3 → switch shell (keyCode: 18=1, 19=2, 20=3)
            if event.keyCode == 18 { switchToShell1(nil); (NSApp.delegate as? AppDelegate)?.updateHeaderTabs(); (NSApp.delegate as? AppDelegate)?.updateFooter(); return }
            if event.keyCode == 19 { switchToShell2(nil); (NSApp.delegate as? AppDelegate)?.updateHeaderTabs(); (NSApp.delegate as? AppDelegate)?.updateFooter(); return }
            if event.keyCode == 20 { switchToShell3(nil); (NSApp.delegate as? AppDelegate)?.updateHeaderTabs(); (NSApp.delegate as? AppDelegate)?.updateFooter(); return }
            // Cmd+Backspace → kill entire line (Ctrl+U)
            if event.keyCode == 51 { writePTY(Data([0x15])); return }
            switch event.charactersIgnoringModifiers {
            case "v": paste(); return
            case "c": copyText(nil); return
            case "a": selectAll(nil); return
            case "\\": writePTY(Data([0x15])); return // Cmd+\ → kill line (Ctrl+U)
            case "d", "D":
                if let d = NSApp.delegate as? AppDelegate {
                    if flags.contains(.shift) {
                        d.toggleSplit(vertical: false)  // Cmd+Shift+D → horizontal
                    } else {
                        d.toggleSplit(vertical: true)   // Cmd+D → vertical
                    }
                }
                return
            default:
                super.keyDown(with: event); return
            }
        }
        // Ctrl+1-9: Tab wechseln (nur Ctrl, kein Cmd/Shift/Option)
        if flags == .control, let idx = Self.numberKeyCodes[event.keyCode] {
            (NSApp.delegate as? AppDelegate)?.switchToTab(idx)
            return
        }
        // Ctrl+Shift+1-9: Tab umbenennen
        if flags == [.control, .shift], let idx = Self.numberKeyCodes[event.keyCode] {
            if let d = NSApp.delegate as? AppDelegate, idx < d.splitContainers.count {
                let title = idx < d.tabCustomNames.count ? (d.tabCustomNames[idx] ?? "") : ""
                d.headerView.startEditingTab(at: idx, currentTitle: title)
            }
            return
        }
        if flags.contains(.option) {
            // Alt+Tab → switch between split panes
            if event.keyCode == 48 {
                if let d = NSApp.delegate as? AppDelegate { d.switchSplitPane() }
                return
            }
            // Alt+Backspace → delete word backward (ESC + DEL)
            if event.keyCode == 51 { writePTY(Data([0x1B, 0x7F])); return }
            // Alt+Arrow Left/Right → move word (ESC + b / ESC + f)
            if event.keyCode == 123 { writePTY(Data([0x1B, 0x62])); return } // Alt+Left → ESC b
            if event.keyCode == 124 { writePTY(Data([0x1B, 0x66])); return } // Alt+Right → ESC f
            // Alt+N → ~ (German keyboard: dead key tilde)
            if event.keyCode == 45 { writePTY("~"); return }
            // Alt+5 → [ , Alt+6 → ] , Alt+7 → | , Alt+8 → { , Alt+9 → } , Alt+L → @ , Alt+E → €
            // Forward other Alt combos that produce special chars on German keyboard
            if let chars = event.characters, !chars.isEmpty, chars != event.charactersIgnoringModifiers {
                writePTY(chars); return
            }
        }
        // Shift+Arrow → terminal text selection (only when Kitty protocol is NOT active)
        if terminal.kittyKbdFlags == 0 &&
           event.modifierFlags.contains(.shift) && !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control) {
            if Self.arrowKeyCodes.contains(event.keyCode) {
                handleShiftArrow(keyCode: event.keyCode)
                return
            }
        }
        // Kitty keyboard protocol: encode keys in CSI u format when active
        if let kittySeq = kittyEncode(event: event) {
            writePTY(kittySeq)
            if selStart != nil { selStart = nil; selEnd = nil; dirty = true }
            needsDisplay = true
            return
        }
        if flags.contains(.control) {
            if let c = event.charactersIgnoringModifiers?.unicodeScalars.first {
                let v = c.value
                if v >= 0x61 && v <= 0x7A { writePTY(Data([UInt8(v - 0x60)])); return }
                if v == 0x40 { writePTY(Data([0])); return }
                if v >= 0x5B && v <= 0x5F { writePTY(Data([UInt8(v - 0x40)])); return }
            }
        }
        // Clear any text selection on regular typing/navigation
        if selStart != nil { selStart = nil; selEnd = nil; dirty = true }

        // Compute xterm modifier: 2=Shift, 3=Alt, 5=Ctrl, etc.
        let nsf = event.modifierFlags
        var xmod = 0
        if nsf.contains(.shift) { xmod |= 1 }
        if nsf.contains(.option) { xmod |= 2 }
        if nsf.contains(.control) { xmod |= 4 }
        let mod = xmod + 1  // xterm uses 1-based (1=none, 2=shift, 3=alt, ...)
        let hasMod = mod > 1

        switch event.keyCode {
        // --- Fundamental keys ---
        case 36: writePTY("\r")                                                      // Return
        case 51: writePTY(Data([0x7F]))                                              // Backspace
        case 48: writePTY(nsf.contains(.shift) ? "\u{1B}[Z" : "\t")                 // Tab / Shift+Tab
        case 53: writePTY(Data([0x1B]))                                              // Escape

        // --- Arrow keys (with modifier support) ---
        case 123: writePTY(hasMod ? "\u{1B}[1;\(mod)D" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")D")
        case 124: writePTY(hasMod ? "\u{1B}[1;\(mod)C" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")C")
        case 125: writePTY(hasMod ? "\u{1B}[1;\(mod)B" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")B")
        case 126: writePTY(hasMod ? "\u{1B}[1;\(mod)A" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")A")

        // --- Navigation keys (with modifier support) ---
        case 115: writePTY(hasMod ? "\u{1B}[1;\(mod)H" : "\u{1B}[H")                // Home
        case 119: writePTY(hasMod ? "\u{1B}[1;\(mod)F" : "\u{1B}[F")                // End
        case 116: writePTY(hasMod ? "\u{1B}[5;\(mod)~" : "\u{1B}[5~")               // Page Up
        case 121: writePTY(hasMod ? "\u{1B}[6;\(mod)~" : "\u{1B}[6~")               // Page Down
        case 114: writePTY(hasMod ? "\u{1B}[2;\(mod)~" : "\u{1B}[2~")               // Insert
        case 117: writePTY(hasMod ? "\u{1B}[3;\(mod)~" : "\u{1B}[3~")               // Delete

        // --- Function keys F1-F12 (xterm fallback) ---
        case 122: writePTY(hasMod ? "\u{1B}[1;\(mod)P"  : "\u{1B}OP")               // F1
        case 120: writePTY(hasMod ? "\u{1B}[1;\(mod)Q"  : "\u{1B}OQ")               // F2
        case  99: writePTY(hasMod ? "\u{1B}[1;\(mod)R"  : "\u{1B}OR")               // F3
        case 118: writePTY(hasMod ? "\u{1B}[1;\(mod)S"  : "\u{1B}OS")               // F4
        case  96: writePTY(hasMod ? "\u{1B}[15;\(mod)~" : "\u{1B}[15~")             // F5
        case  97: writePTY(hasMod ? "\u{1B}[17;\(mod)~" : "\u{1B}[17~")             // F6
        case  98: writePTY(hasMod ? "\u{1B}[18;\(mod)~" : "\u{1B}[18~")             // F7
        case 100: writePTY(hasMod ? "\u{1B}[19;\(mod)~" : "\u{1B}[19~")             // F8
        case 101: writePTY(hasMod ? "\u{1B}[20;\(mod)~" : "\u{1B}[20~")             // F9
        case 109: writePTY(hasMod ? "\u{1B}[21;\(mod)~" : "\u{1B}[21~")             // F10
        case 103: writePTY(hasMod ? "\u{1B}[23;\(mod)~" : "\u{1B}[23~")             // F11
        case 111: writePTY(hasMod ? "\u{1B}[24;\(mod)~" : "\u{1B}[24~")             // F12

        default:
            if let chars = event.characters, !chars.isEmpty { writePTY(chars) }
        }
        // Force immediate redraw after any key to keep cursor responsive
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {}

    override func keyUp(with event: NSEvent) {
        // Kitty keyboard protocol: report key release when flag bit 1 is set
        if let kittySeq = kittyEncode(event: event, isRelease: true) {
            writePTY(kittySeq)
        }
    }

    // MARK: Shift+Arrow selection

    func handleShiftArrow(keyCode: UInt16) {
        let curPos = (row: terminal.cursorY, col: terminal.cursorX)
        // Initialize selection at cursor if not started
        if selStart == nil {
            selStart = curPos
            selEnd = curPos
        }
        guard var end = selEnd else { return }
        switch keyCode {
        case 123: // Left
            end.col -= 1
            if end.col < 0 { end.col = terminal.cols - 1; end.row = max(0, end.row - 1) }
        case 124: // Right
            end.col += 1
            if end.col >= terminal.cols { end.col = 0; end.row = min(terminal.rows - 1, end.row + 1) }
        case 126: // Up
            end.row = max(0, end.row - 1)
        case 125: // Down
            end.row = min(terminal.rows - 1, end.row + 1)
        default: break
        }
        selEnd = end
        dirty = true
        needsDisplay = true
    }

    // MARK: Mouse selection

    var selStart: (row: Int, col: Int)? = nil
    var selEnd: (row: Int, col: Int)? = nil
    private var mouseDownPos: (row: Int, col: Int)? = nil
    private var mouseDownTime: TimeInterval = 0
    private var isDragging = false
    private var isWordSelect = false

    func gridPos(from event: NSEvent) -> (row: Int, col: Int) {
        let loc = convert(event.locationInWindow, from: nil)
        let visualCol = max(0, min(terminal.cols - 1, Int((loc.x - paddingX) / cellW)))
        let row = max(0, min(terminal.rows - 1, Int((loc.y - paddingY) / cellH)))
        // Map visual column → logical column for BiDi rows
        var col = visualCol
        if row < terminal.rows, row < terminal.grid.count {
            let order: [Int]?
            if row < bidiCacheValid.count && bidiCacheValid[row] {
                order = bidiCacheData[row]
            } else {
                order = bidiVisualOrder(for: terminal.grid[row], cols: terminal.cols)
            }
            if let o = order, visualCol < o.count { col = o[visualCol] }
        }
        return (row, col)
    }

    // MARK: Mouse tracking helpers

    /// Encode and send a mouse event to the PTY when mouse tracking is active.
    private func sendMouseEvent(button: Int, x: Int, y: Int, release: Bool = false) {
        let cx = min(x + 1, 223)  // 1-based, clamped for legacy encoding
        let cy = min(y + 1, 223)
        if terminal.mouseEncoding == 1006 {
            // SGR encoding: CSI < Pb ; Px ; Py M/m
            let suffix = release ? "m" : "M"
            let seq = "\u{1B}[<\(max(0, button));\(x + 1);\(y + 1)\(suffix)"
            writePTY(seq)
        } else {
            // X11 legacy encoding: ESC [ M Cb Cx Cy (all + 32)
            if release { return } // X11 encoding doesn't reliably support release
            let cb = UInt8(truncatingIfNeeded: button + 32)
            let data = Data([0x1B, 0x5B, 0x4D, cb, UInt8(cx + 32), UInt8(cy + 32)])
            writePTY(data)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Close command palette if open
        if let d = NSApp.delegate as? AppDelegate, let p = d.commandPalette, p.superview != nil {
            p.dismiss()
        }
        // Close settings overlay if open
        if let d = NSApp.delegate as? AppDelegate, d.settingsOverlay != nil {
            d.hideSettings()
        }
        // Cmd+Click: open hyperlink
        if event.modifierFlags.contains(.command) {
            let pos = gridPos(from: event)
            if pos.row >= 0, pos.row < terminal.rows, pos.col >= 0, pos.col < terminal.cols,
               let url = terminal.grid[pos.row][pos.col].hyperlink,
               let nsUrl = URL(string: url) {
                NSWorkspace.shared.open(nsUrl)
                return
            }
        }
        if event.modifierFlags.contains(.option) {
            window?.performDrag(with: event)
            return
        }
        // Notify split container of focus change
        if let sc = superview as? SplitContainer {
            let isPrimary = sc.primaryView === self
            if isPrimary != sc.activePaneIsPrimary {
                window?.makeFirstResponder(self)
                sc.setActivePane(primary: isPrimary)
                sc.onFocusChanged?(self)
            }
        }
        // Mouse tracking: send event to PTY instead of UI selection
        if terminal.mouseMode >= 1000 {
            let pos = gridPos(from: event)
            sendMouseEvent(button: 0, x: pos.col, y: pos.row)
            return
        }
        mouseDownPos = gridPos(from: event)
        mouseDownTime = ProcessInfo.processInfo.systemUptime
        isDragging = false

        isWordSelect = false
        // Double-click: select word
        if event.clickCount == 2, let pos = mouseDownPos {
            let (wStart, wEnd) = wordBounds(at: pos)
            selStart = wStart
            selEnd = wEnd
            isDragging = true
            isWordSelect = true
            dirty = true
            needsDisplay = true
            return
        }

        // Clear existing selection on new click
        selStart = nil
        selEnd = nil
        dirty = true
    }

    private func wordBounds(at pos: (row: Int, col: Int)) -> ((row: Int, col: Int), (row: Int, col: Int)) {
        let row = pos.row
        guard row >= 0 && row < terminal.rows else { return (pos, pos) }
        let grid = terminal.grid
        let ch = grid[row][pos.col].char
        let isWordChar = { (c: Unicode.Scalar) -> Bool in
            CharacterSet.alphanumerics.contains(c) || c == "_" || c == "-" || c == "."
        }
        let checkWord = isWordChar(ch)
        var startCol = pos.col
        var endCol = pos.col
        if checkWord {
            while startCol > 0 && isWordChar(grid[row][startCol - 1].char) { startCol -= 1 }
            while endCol < terminal.cols - 1 && isWordChar(grid[row][endCol + 1].char) { endCol += 1 }
        }
        return ((row: row, col: startCol), (row: row, col: endCol))
    }

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) { return }
        // Mouse tracking: send drag events (button-event mode 1002 or any-event mode 1003)
        if terminal.mouseMode >= 1002 {
            let pos = gridPos(from: event)
            sendMouseEvent(button: 32, x: pos.col, y: pos.row) // 32 = motion with button 0 held
            return
        }
        if terminal.mouseMode >= 1000 { return } // X10 mode doesn't report drag
        if isWordSelect { return }
        // Start selection immediately on drag (no delay)
        if !isDragging {
            isDragging = true
            selStart = mouseDownPos
        }
        selEnd = gridPos(from: event)
        dirty = true
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        // Don't interfere with cursor when settings overlay is visible
        guard !settingsVisible else { return }
        let pos = gridPos(from: event)
        // Any-event tracking (1003): report all motion even without buttons
        if terminal.mouseMode >= 1003, window?.isKeyWindow == true {
            sendMouseEvent(button: 35, x: pos.col, y: pos.row)
        }
        // In edge zone: show resize cursor instead of iBeam
        if isInEdgeZone(event), let w = window as? BorderlessWindow {
            w.setEdgeCursor(at: event.locationInWindow)
            return
        }

        let hasLink = pos.row >= 0 && pos.row < terminal.rows && pos.col < terminal.grid[pos.row].count
            && terminal.grid[pos.row][pos.col].hyperlink != nil
        if hasLink {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Mouse tracking: send release event
        if terminal.mouseMode >= 1000 {
            let pos = gridPos(from: event)
            if terminal.mouseEncoding == 1006 {
                sendMouseEvent(button: 0, x: pos.col, y: pos.row, release: true)
            } else {
                sendMouseEvent(button: 3, x: pos.col, y: pos.row) // 3 = release in X11 encoding
            }
            return
        }
        if isDragging {
            if event.clickCount < 2 { selEnd = gridPos(from: event) }
            let copyOnSelect = UserDefaults.standard.bool(forKey: "copyOnSelect")
            if copyOnSelect, let text = selectedText(), !text.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
        } else {
            selStart = nil
            selEnd = nil
        }
        mouseDownPos = nil
        isDragging = false
        isWordSelect = false
        dirty = true
    }

    override func otherMouseDown(with event: NSEvent) {
        if terminal.mouseMode >= 1000 {
            let pos = gridPos(from: event)
            sendMouseEvent(button: 1, x: pos.col, y: pos.row)
            return
        }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if terminal.mouseMode >= 1000 {
            let pos = gridPos(from: event)
            if terminal.mouseEncoding == 1006 {
                sendMouseEvent(button: 1, x: pos.col, y: pos.row, release: true)
            } else {
                sendMouseEvent(button: 3, x: pos.col, y: pos.row)
            }
            return
        }
        super.otherMouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if terminal.mouseMode >= 1000 {
            let pos = gridPos(from: event)
            sendMouseEvent(button: 2, x: pos.col, y: pos.row)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if terminal.mouseMode >= 1000 {
            let pos = gridPos(from: event)
            if terminal.mouseEncoding == 1006 {
                sendMouseEvent(button: 2, x: pos.col, y: pos.row, release: true)
            } else {
                sendMouseEvent(button: 3, x: pos.col, y: pos.row)
            }
            return
        }
        super.rightMouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if terminal.mouseMode >= 1000 { return nil }
        let menu = NSMenu()
        let del = NSApp.delegate as? AppDelegate

        // ── Clipboard ────────────────────────────────────────────────────────
        let copyItem = NSMenuItem(title: Loc.copy, action: #selector(copyText(_:)), keyEquivalent: "")
        copyItem.keyEquivalentModifierMask = []
        copyItem.isEnabled = (selStart != nil && selEnd != nil)
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: Loc.paste, action: #selector(paste), keyEquivalent: "")
        pasteItem.keyEquivalentModifierMask = []
        menu.addItem(pasteItem)

        menu.addItem(NSMenuItem.separator())

        // ── Edit ─────────────────────────────────────────────────────────────
        let selectAllItem = NSMenuItem(title: Loc.selectAll, action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAllItem.keyEquivalentModifierMask = []
        menu.addItem(selectAllItem)

        let clearItem = NSMenuItem(title: Loc.clear, action: #selector(clearScrollback(_:)), keyEquivalent: "")
        clearItem.keyEquivalentModifierMask = []
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        // ── Tabs ─────────────────────────────────────────────────────────────
        let newTabItem = NSMenuItem(title: Loc.newTab, action: #selector(contextMenuNewTab), keyEquivalent: "")
        menu.addItem(newTabItem)

        menu.addItem(NSMenuItem.separator())

        // ── Split ─────────────────────────────────────────────────────────────
        let splitVItem = NSMenuItem(title: Loc.splitVertical, action: #selector(contextMenuSplitV), keyEquivalent: "")
        menu.addItem(splitVItem)

        let splitHItem = NSMenuItem(title: Loc.splitHorizontal, action: #selector(contextMenuSplitH), keyEquivalent: "")
        menu.addItem(splitHItem)

        menu.addItem(NSMenuItem.separator())

        // ── Panels ────────────────────────────────────────────────────────────
        let panelsMenu = NSMenu()
        let gitOn: Bool = del.map { d in d.activeTab < d.tabGitPositions.count && d.tabGitPositions[d.activeTab] != .none } ?? false
        let gitItem = NSMenuItem(title: "Git", action: #selector(contextMenuToggleGit), keyEquivalent: "")
        gitItem.state = gitOn ? .on : .off
        panelsMenu.addItem(gitItem)

        let pickerOn = del?.webPickerSidebarView != nil
        let pickerItem = NSMenuItem(title: "WebPicker", action: #selector(contextMenuTogglePicker), keyEquivalent: "")
        pickerItem.state = pickerOn ? .on : .off
        panelsMenu.addItem(pickerItem)

        let sshOn = del?.sshManagerView != nil
        let sshItem = NSMenuItem(title: "SSH", action: #selector(contextMenuToggleSSH), keyEquivalent: "")
        sshItem.state = sshOn ? .on : .off
        panelsMenu.addItem(sshItem)

        let panelsParent = NSMenuItem(title: Loc.panels, action: nil, keyEquivalent: "")
        panelsParent.submenu = panelsMenu
        menu.addItem(panelsParent)

        menu.addItem(NSMenuItem.separator())

        // ── Credits ───────────────────────────────────────────────────────────
        let footerItem = NSMenuItem()
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .light),
            .foregroundColor: NSColor.gray
        ]
        footerItem.attributedTitle = NSAttributedString(
            string: "quickTERMINAL v\(kAppVersion) — LEVOGNE © 2026", attributes: footerAttrs)
        footerItem.isEnabled = false
        menu.addItem(footerItem)

        return menu
    }

    @objc private func contextMenuNewTab()      { (NSApp.delegate as? AppDelegate)?.addTab() }
    @objc private func contextMenuSplitV()      { (NSApp.delegate as? AppDelegate)?.toggleSplit(vertical: true) }
    @objc private func contextMenuSplitH()      { (NSApp.delegate as? AppDelegate)?.toggleSplit(vertical: false) }
    @objc private func contextMenuToggleGit()   { (NSApp.delegate as? AppDelegate)?.toggleGitPanel() }
    @objc private func contextMenuTogglePicker(){ (NSApp.delegate as? AppDelegate)?.toggleWebPicker() }
    @objc private func contextMenuToggleSSH()   { (NSApp.delegate as? AppDelegate)?.toggleSSHManager() }

    private var scrollAccumulator: CGFloat = 0
    private var hScrollAccumulator: CGFloat = 0

    /// Accumulate scroll delta and return number of discrete lines (max 10), or nil if threshold not reached.
    private func consumeScrollLines(dy: CGFloat) -> Int? {
        scrollAccumulator += dy
        let lines = Int(abs(scrollAccumulator) / 3)
        guard lines > 0 else { return nil }
        scrollAccumulator = scrollAccumulator.truncatingRemainder(dividingBy: 3)
        return min(lines, 10)
    }

    private func consumeHScrollCols(dx: CGFloat) -> Int? {
        hScrollAccumulator += dx
        let cols = Int(abs(hScrollAccumulator) / 3)
        guard cols > 0 else { return nil }
        hScrollAccumulator = hScrollAccumulator.truncatingRemainder(dividingBy: 3)
        return min(cols, 20)
    }

    private func clampScrollY() {
        let maxPx = CGFloat(terminal.scrollback.count) * cellH
        smoothScrollY = max(0, min(maxPx, smoothScrollY))
    }

    private func startMomentumTimer() {
        guard momentumTimer == nil else { return }
        momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            guard abs(s.scrollVelocity) > 0.3 else {
                s.scrollVelocity = 0
                s.momentumTimer?.invalidate()
                s.momentumTimer = nil
                return
            }
            s.smoothScrollY += s.scrollVelocity
            s.clampScrollY()
            s.scrollVelocity *= 0.92  // deceleration
            s.dirty = true
            s.needsDisplay = true
        }
    }

    func stopMomentum() {
        scrollVelocity = 0
        momentumTimer?.invalidate()
        momentumTimer = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
        guard dy != 0 || dx != 0 else { return }

        // Mouse tracking active → forward as mouse events (SGR or legacy)
        if terminal.mouseMode >= 1000 {
            if dy != 0, let lines = consumeScrollLines(dy: dy) {
                let pos = gridPos(from: event)
                let button = dy < 0 ? 65 : 64
                for _ in 0..<lines { sendMouseEvent(button: button, x: pos.col, y: pos.row) }
            }
            if dx != 0, let cols = consumeHScrollCols(dx: dx) {
                let pos = gridPos(from: event)
                let button = dx > 0 ? 67 : 66  // 66=wheel-right, 67=wheel-left
                for _ in 0..<cols { sendMouseEvent(button: button, x: pos.col, y: pos.row) }
            }
            return
        }

        // Alternate screen (TUI apps like vim, htop) → arrow keys
        if terminal.altGrid != nil {
            if dy != 0, let lines = consumeScrollLines(dy: dy) {
                let up = terminal.appCursorMode ? "\u{1B}OA" : "\u{1B}[A"
                let down = terminal.appCursorMode ? "\u{1B}OB" : "\u{1B}[B"
                let arrow = dy > 0 ? up : down
                for _ in 0..<lines { writePTY(arrow) }
            }
            if dx != 0, let cols = consumeHScrollCols(dx: dx) {
                let left = terminal.appCursorMode ? "\u{1B}OD" : "\u{1B}[D"
                let right = terminal.appCursorMode ? "\u{1B}OC" : "\u{1B}[C"
                let arrow = dx < 0 ? left : right
                for _ in 0..<cols { writePTY(arrow) }
            }
            return
        }

        // Normal screen → smooth pixel scrollback with momentum (vertical)
        if dy != 0 {
            if event.phase == .began || event.phase == .changed {
                stopMomentum()
                smoothScrollY += dy * 1.8
                clampScrollY()
                needsDisplay = true
            } else if event.momentumPhase == .changed {
                smoothScrollY += dy * 1.8
                clampScrollY()
                needsDisplay = true
            } else if event.phase == .ended || event.momentumPhase == .ended {
                if smoothScrollY < cellH * 0.5 { smoothScrollY = 0 }
                needsDisplay = true
            } else if event.phase.rawValue == 0 && event.momentumPhase.rawValue == 0 {
                // Discrete mouse wheel — use momentum animation
                stopMomentum()
                scrollVelocity += dy * 4.0
                let maxVel = cellH * 20
                scrollVelocity = max(-maxVel, min(maxVel, scrollVelocity))
                smoothScrollY += scrollVelocity
                clampScrollY()
                startMomentumTimer()
                needsDisplay = true
            }
        }

        // Normal screen → horizontal swipe = cursor left/right in shell
        if dx != 0, let cols = consumeHScrollCols(dx: dx) {
            let left = terminal.appCursorMode ? "\u{1B}OD" : "\u{1B}[D"
            let right = terminal.appCursorMode ? "\u{1B}OC" : "\u{1B}[C"
            let arrow = dx < 0 ? left : right
            for _ in 0..<cols { writePTY(arrow) }
        }

        // If user is actively dragging a selection, extend selEnd to current mouse position
        if isDragging {
            let mouseLoc = window?.mouseLocationOutsideOfEventStream ?? .zero
            let viewLoc = convert(mouseLoc, from: nil)
            let lineOff = scrollbackOffset
            let visualRow = max(0, Int((viewLoc.y - paddingY) / cellH))
            // TerminalView is flipped: row 0=top, rows-1=bottom
            // When scrolled back lineOff lines, screen row 0 appears at visual row lineOff
            let screenRow = max(0, min(terminal.rows - 1, visualRow - lineOff))
            let col = max(0, min(terminal.cols - 1, Int((viewLoc.x - paddingX) / cellW)))
            selEnd = (row: screenRow, col: col)
        }
    }

    // Find the last non-space column in a row
    private func lastTextCol(row: Int) -> Int {
        guard row >= 0 && row < terminal.rows else { return -1 }
        for c in stride(from: terminal.cols - 1, through: 0, by: -1) {
            let ch = terminal.grid[row][c].char
            if ch != " " && ch != "\0" { return c }
        }
        return -1
    }

    private func selectionRange() -> (lo: Int, hi: Int)? {
        guard let s = selStart, let e = selEnd else { return nil }
        let a = s.row * terminal.cols + s.col
        let b = e.row * terminal.cols + e.col
        return (min(a, b), max(a, b))
    }

    func isSelected(row: Int, col: Int) -> Bool {
        guard let (lo, hi) = selectionRange() else { return false }
        let cur = row * terminal.cols + col
        guard cur >= lo && cur <= hi else { return false }
        return col <= lastTextCol(row: row)
    }

    func selectedText() -> String? {
        guard let (lo, hi) = selectionRange(), lo != hi else { return nil }
        var text = ""
        var lastRow = lo / terminal.cols
        var rowLastCol = lastTextCol(row: lastRow)
        for pos in lo...hi {
            let r = pos / terminal.cols
            let c = pos % terminal.cols
            if r != lastRow {
                text += "\n"
                lastRow = r
                rowLastCol = lastTextCol(row: r)
            }
            if r < terminal.rows && c < terminal.cols && c <= rowLastCol {
                text.append(String(terminal.grid[r][c].char))
            }
        }
        // Trim trailing whitespace per line
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var s = line[...]
            while s.last?.isWhitespace == true { s = s.dropLast() }
            return String(s)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Write text to PTY, wrapping in bracketed paste escape sequences if mode is active
    private func pasteText(_ text: String) {
        if terminal.bracketedPasteMode {
            writePTY("\u{1B}[200~")
            writePTY(text)
            writePTY("\u{1B}[201~")
        } else {
            writePTY(text)
        }
    }

    @objc func paste() {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        pasteText(s)
    }

    // MARK: Drag & Drop (file path insertion)

    /// Track active drag session so hideOnClickOutside doesn't dismiss during drag
    private(set) var isDragSessionActive = false
    private var cachedDragOperation: NSDragOperation = []

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ||
           pb.canReadObject(forClasses: [NSString.self], options: nil) {
            cachedDragOperation = .copy
            isDragSessionActive = true
        } else {
            cachedDragOperation = []
        }
        return cachedDragOperation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        cachedDragOperation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragSessionActive = false
        cachedDragOperation = []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragSessionActive = false
        cachedDragOperation = []
        let pb = sender.draggingPasteboard
        // File URLs: insert shell-escaped paths
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            pasteText(urls.map { shellEscape($0.path) }.joined(separator: " "))
            return true
        }
        // Plain text fallback
        if let str = pb.string(forType: .string), !str.isEmpty {
            pasteText(str)
            return true
        }
        return false
    }

    /// Shell-escape a file path: wrap in single quotes, escape existing single quotes
    private func shellEscape(_ path: String) -> String {
        if path.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_.-+:@")).inverted) == nil {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @objc func copyText(_ sender: Any?) {
        if let text = selectedText(), !text.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        selStart = (row: 0, col: 0)
        selEnd = (row: terminal.rows - 1, col: terminal.cols - 1)
        dirty = true
        needsDisplay = true
    }

    // MARK: Accessibility (VoiceOver)

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityRoleDescription() -> String? { "terminal" }
    override func accessibilityLabel() -> String? { "Terminal" }

    override func accessibilityValue() -> Any? {
        if let cached = a11yValueCache { return cached }
        // Rebuild visible screen content for VoiceOver
        var lines: [String] = []
        for row in 0..<terminal.rows {
            var line = ""
            for col in 0..<terminal.cols {
                line.append(String(terminal.grid[row][col].char))
            }
            while line.last?.isWhitespace == true { line.removeLast() }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let result = lines.joined(separator: "\n")
        a11yValueCache = result
        return result
    }

    override func accessibilitySelectedText() -> String? {
        selectedText()
    }

    override func accessibilityInsertionPointLineNumber() -> Int {
        terminal.cursorY
    }

    override func accessibilityNumberOfCharacters() -> Int {
        terminal.rows * terminal.cols
    }

    override func isAccessibilityFocused() -> Bool {
        window?.firstResponder === self
    }

    // MARK: Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let c = max(1, Int((newSize.width - paddingX * 2) / cellW))
        let r = max(1, Int((newSize.height - paddingY * 2) / cellH))
        guard !suppressResize else { return }
        if c != terminal.cols || r != terminal.rows {
            let sbBefore = terminal.scrollback.count
            terminal.resize(c, r)
            // Keep viewport anchored if scrollback size changed during resize
            let sbDelta = terminal.scrollback.count - sbBefore
            if sbDelta != 0 && smoothScrollY > 0 {
                smoothScrollY = max(0, smoothScrollY + CGFloat(sbDelta) * cellH)
                clampScrollY()
            }
            selStart = nil; selEnd = nil  // clear stale selection after resize
            dirty = true
            let fd = masterFd
            guard fd >= 0 else { return }
            var ws = winsize(ws_row: UInt16(r), ws_col: UInt16(c),
                             ws_xpixel: UInt16(newSize.width), ws_ypixel: UInt16(newSize.height))
            if isFirstResize {
                isFirstResize = false
                _ = ioctl(fd, TIOCSWINSZ, &ws)
            } else {
                winSizeWorkItem?.cancel()
                let item = DispatchWorkItem { _ = ioctl(fd, TIOCSWINSZ, &ws) }
                winSizeWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
            }
        }
    }

    func updateFontSize(_ size: CGFloat) {
        let fontIdx = UserDefaults.standard.integer(forKey: "fontFamily")
        let fontInfo = fontIdx < Self.availableFonts.count ? Self.availableFonts[fontIdx] : Self.availableFonts[0]
        font = NSFont(name: fontInfo.1, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        boldFont = (fontInfo.2.flatMap { NSFont(name: $0, size: size) })
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        italicFont = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? font
        boldItalicFont = NSFont(descriptor: boldFont.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? boldFont
        cellW = Self.monoAdvance(font)
        cellH = ceil(font.ascender - font.descender + font.leading)
        terminal.cellPixelWidth = Int(cellW); terminal.cellPixelHeight = Int(cellH)
        setFrameSize(frame.size)
        setNeedsDisplay(bounds)
    }
}

// MARK: - Borderless Key Window

class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Set to true when window is detached (floating) — enables top-edge resize
    var isDetached = false

    /// Inset for iBeam cursor rect so native resize cursors show at edges
    static let edgeInset: CGFloat = 10

    // MARK: - Wide grab zone resize (no custom cursors — native handles that)

    private enum Edge { case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
    private var activeEdge: Edge = .none
    private var dragStart: NSPoint = .zero
    private var dragFrame: NSRect = .zero
    private var preMaxFrame: NSRect? = nil

    private func edgeAt(_ p: NSPoint) -> Edge {
        guard let cv = contentView else { return .none }
        let b = cv.bounds
        let e = Self.edgeInset
        let l = p.x < e
        let r = p.x > b.width - e
        let bot = p.y < e
        let top = isDetached && p.y > b.height - e   // top enabled only when detached
        if top && l { return .topLeft }
        if top && r { return .topRight }
        if top { return .top }
        if bot && l { return .bottomLeft }
        if bot && r { return .bottomRight }
        if bot { return .bottom }
        if l { return .left }
        if r { return .right }
        return .none
    }

    private func toggleMaximize(edge: Edge) {
        guard let screen = screen ?? NSScreen.main else { return }
        let vis = screen.visibleFrame  // excludes menu bar & dock

        // If restoring from a previous maximize
        if let prev = preMaxFrame {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().setFrame(prev, display: true)
            }
            preMaxFrame = nil
            return
        }

        preMaxFrame = frame
        var target = frame

        switch edge {
        case .bottom:
            // Full height
            target.origin.y = vis.origin.y
            target.size.height = vis.height
        case .left:
            // Full height, snap left half
            target.origin.x = vis.origin.x
            target.origin.y = vis.origin.y
            target.size.width = vis.width / 2
            target.size.height = vis.height
        case .right:
            // Full height, snap right half
            target.origin.x = vis.origin.x + vis.width / 2
            target.origin.y = vis.origin.y
            target.size.width = vis.width / 2
            target.size.height = vis.height
        case .top, .topLeft, .topRight, .bottomLeft, .bottomRight, .none:
            // Full screen
            target = vis
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().setFrame(target, display: true)
        }
    }

    /// NW↔SE diagonal resize cursor (topLeft, bottomRight)
    static let resizeNWSE: NSCursor = {
        if let c = NSCursor.perform(NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?.takeUnretainedValue() as? NSCursor { return c }
        return .resizeLeftRight
    }()
    /// NE↔SW diagonal resize cursor (topRight, bottomLeft)
    static let resizeNESW: NSCursor = {
        if let c = NSCursor.perform(NSSelectorFromString("_windowResizeNorthEastSouthWestCursor"))?.takeUnretainedValue() as? NSCursor { return c }
        return .resizeLeftRight
    }()

    private func cursorFor(_ edge: Edge) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return Self.resizeNWSE
        case .topRight, .bottomLeft: return Self.resizeNESW
        case .none: return .arrow
        }
    }

    func setEdgeCursor(at point: NSPoint) {
        let edge = edgeAt(point)
        if edge != .none { cursorFor(edge).set() }
    }

    private var lastEdge: Edge = .none

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let edge = edgeAt(event.locationInWindow)
            if edge != .none {
                // Double-click: toggle maximize
                if event.clickCount == 2 {
                    toggleMaximize(edge: edge)
                    return
                }
                activeEdge = edge
                dragStart = NSEvent.mouseLocation
                dragFrame = frame
                cursorFor(edge).set()
                return
            }

        case .leftMouseDragged:
            guard activeEdge != .none else { break }
            let cur = NSEvent.mouseLocation
            let dx = cur.x - dragStart.x
            let dy = cur.y - dragStart.y
            var r = dragFrame

            if activeEdge == .right || activeEdge == .bottomRight || activeEdge == .topRight {
                r.size.width = max(minSize.width, dragFrame.width + dx)
            }
            if activeEdge == .left || activeEdge == .bottomLeft || activeEdge == .topLeft {
                let newW = max(minSize.width, dragFrame.width - dx)
                r.origin.x = dragFrame.maxX - newW
                r.size.width = newW
            }
            if activeEdge == .top || activeEdge == .topLeft || activeEdge == .topRight {
                r.size.height = max(minSize.height, dragFrame.height + dy)
            }
            if activeEdge == .bottom || activeEdge == .bottomLeft || activeEdge == .bottomRight {
                let newH = max(minSize.height, dragFrame.height - dy)
                r.origin.y = dragFrame.maxY - newH
                r.size.height = newH
            }

            cursorFor(activeEdge).set()
            setFrame(r, display: true)
            contentView?.layoutSubtreeIfNeeded()
            return

        case .leftMouseUp:
            if activeEdge != .none {
                activeEdge = .none
                return
            }

        case .mouseMoved:
            let edge = edgeAt(event.locationInWindow)
            if edge != lastEdge {
                if edge != .none {
                    cursorFor(edge).set()
                } else if lastEdge != .none {
                    NSCursor.arrow.set()
                }
                lastEdge = edge
                (NSApp.delegate as? AppDelegate)?.handleBorderHover(nearEdge: edge != .none)
            }

        case .mouseExited:
            if lastEdge != .none {
                lastEdge = .none
                (NSApp.delegate as? AppDelegate)?.handleBorderHover(nearEdge: false)
            }

        default:
            break
        }

        super.sendEvent(event)
    }

    /// During live resize, prevent the window from shrinking past the Popover-Arrow.
    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        // Detached (free-floating) windows must never be constrained to the tray position.
        guard inLiveResize || activeEdge != .none,
              !isDetached,
              let appDelegate = NSApp.delegate as? AppDelegate,
              let button = appDelegate.statusItem?.button,
              let btnWindow = button.window else {
            super.setFrame(frameRect, display: displayFlag)
            return
        }
        let btnRect = button.convert(button.bounds, to: nil)
        let arrowScreenX = btnWindow.convertToScreen(btnRect).midX
        let pad: CGFloat = 30

        var rect = frameRect

        if rect.origin.x > arrowScreenX - pad {
            let rightEdge = rect.origin.x + rect.size.width
            rect.origin.x = arrowScreenX - pad
            rect.size.width = rightEdge - rect.origin.x
        }

        if rect.origin.x + rect.size.width < arrowScreenX + pad {
            rect.size.width = arrowScreenX + pad - rect.origin.x
        }

        super.setFrame(rect, display: displayFlag)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let cmd  = event.modifierFlags.contains(.command)
        let shft = event.modifierFlags.contains(.shift)
        guard cmd else { return super.performKeyEquivalent(with: event) }
        let key  = event.charactersIgnoringModifiers ?? ""
        let del  = NSApp.delegate as? AppDelegate
        let isEditor = (del?.activeTab ?? -1) < (del?.tabTypes.count ?? 0)
                    && del?.tabTypes[del!.activeTab] == .editor

        switch key {
        case "s" where !shft && isEditor:
            del?.saveCurrentEditor(); return true
        case "s" where shft && isEditor:
            del?.saveCurrentEditorAs(); return true
        case "f" where !shft && isEditor:
            (del?.tabEditorViews[del!.activeTab] as? EditorView)?.showSearch(replace: false)
            return true
        case "h" where !shft && isEditor:
            (del?.tabEditorViews[del!.activeTab] as? EditorView)?.showSearch(replace: true)
            return true
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Header Interactive Views

class HoverButton: NSView {
    var label: NSTextField!
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private let normalBg: CGColor
    private let hoverBg: CGColor
    private let pressBg: CGColor
    private let normalColor: NSColor
    private let hoverColor: NSColor
    var hoverScale: CGFloat = 1.0
    var isActive: Bool = false

    func setActive(_ active: Bool) {
        isActive = active
        guard !isHovered else { return }
        let targetColor = active ? hoverColor : normalColor
        let targetBg    = active ? hoverBg    : normalBg
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            label.animator().textColor = targetColor
        }
        animateBg(to: targetBg, duration: 0.25)
    }

    init(title: String, fontSize: CGFloat, weight: NSFont.Weight,
         normalColor: NSColor, hoverColor: NSColor,
         normalBg: NSColor = .clear,
         hoverBg: NSColor = NSColor(calibratedWhite: 1.0, alpha: 0.1),
         pressBg: NSColor = NSColor(calibratedWhite: 1.0, alpha: 0.2),
         cornerRadius: CGFloat = 6) {
        self.normalBg = normalBg.cgColor
        self.hoverBg = hoverBg.cgColor
        self.pressBg = pressBg.cgColor
        self.normalColor = normalColor
        self.hoverColor = hoverColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = self.normalBg

        label = NSTextField(labelWithString: title)
        label.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        label.textColor = normalColor
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = label.intrinsicContentSize
        return NSSize(width: s.width + 12, height: s.height + 6)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.arrow.push()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            label.animator().textColor = hoverColor
        }
        animateBg(to: hoverBg)
        if hoverScale != 1.0 {
            label.wantsLayer = true
            label.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            label.layer?.position = CGPoint(x: label.frame.midX, y: label.frame.midY)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.toValue = hoverScale
            scale.duration = 0.2
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            label.layer?.add(scale, forKey: "hoverScale")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            label.layer?.transform = CATransform3DMakeScale(hoverScale, hoverScale, 1)
            CATransaction.commit()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        NSCursor.pop()
        let targetColor = isActive ? hoverColor : normalColor
        let targetBg    = isActive ? hoverBg    : normalBg
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            label.animator().textColor = targetColor
        }
        animateBg(to: targetBg, duration: 0.25)
        if hoverScale != 1.0 {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.toValue = 1.0
            scale.duration = 0.2
            label.layer?.add(scale, forKey: "hoverScale")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            label.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        animateBg(to: pressBg, duration: 0.06)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            animateBg(to: hoverBg, duration: 0.12)
            onClick?()
        } else {
            let targetColor = isActive ? hoverColor : normalColor
            let targetBg    = isActive ? hoverBg    : normalBg
            animateBg(to: targetBg)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                label.animator().textColor = targetColor
            }
        }
    }

    func animateBg(to color: CGColor, duration: CFTimeInterval = 0.15) {
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        anim.toValue = color
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(anim, forKey: "bg")
        layer?.backgroundColor = color
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label.stringValue }
}

class TabCloseButton: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        // Solid dark background so it stands out over text
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.95).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset: CGFloat = 4.0
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.move(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        (isHovered
            ? NSColor(calibratedWhite: 1.0, alpha: 0.95)
            : NSColor(calibratedWhite: 0.6, alpha: 1.0)
        ).setStroke()
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    private func animateBg(to color: NSColor, duration: CFTimeInterval = 0.15) {
        let c = color.cgColor
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        anim.toValue = c
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(anim, forKey: "bg")
        layer?.backgroundColor = c
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        animateBg(to: NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.2, alpha: 0.9))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        animateBg(to: NSColor(calibratedWhite: 0.12, alpha: 0.95), duration: 0.2)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0.5
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1.0
        }
        animateBg(to: isHovered
            ? NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.2, alpha: 0.9)
            : NSColor(calibratedWhite: 0.12, alpha: 0.95), duration: 0.12)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Close Tab" }
}

class TabItemView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    var onDragMoved: ((Int, CGFloat) -> Void)?  // (tabIndex, deltaX)
    var onDragEnded: ((Int) -> Void)?           // (tabIndex)
    private static let closeBtnRestAlpha: CGFloat = 0.25
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    let isActive: Bool
    let showClose: Bool
    private let titleLabel: NSTextField
    private var closeBtn: TabCloseButton?
    let tabIndex: Int
    let tabColor: NSColor
    private let clipView: NSView
    private var clipTrailing: NSLayoutConstraint!
    private let closeBtnSpace: CGFloat = 19  // 16 btn + 3 padding
    private var dragOrigin: NSPoint?

    init(index: Int, title: String, active: Bool, showClose: Bool, color: NSColor) {
        self.tabIndex = index
        self.isActive = active
        self.showClose = showClose
        self.tabColor = color
        self.titleLabel = NSTextField(labelWithString: title)
        self.clipView = NSView()
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4

        if active {
            layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Clipping container for title marquee — always full width
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clipView)

        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: active ? .medium : .regular)
        titleLabel.textColor = active
            ? NSColor(calibratedWhite: 0.92, alpha: 1.0)
            : NSColor(calibratedWhite: 0.48, alpha: 1.0)
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byClipping
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.isScrollable = true
        titleLabel.cell?.wraps = false
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.wantsLayer = true
        clipView.addSubview(titleLabel)

        // clipView: reserve space for close button when showClose is true
        let trailingPad: CGFloat = showClose ? (7 + closeBtnSpace) : 7
        clipTrailing = clipView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingPad)
        var constraints = [
            clipView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            clipTrailing!,
            clipView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            clipView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ]

        // Close button overlays on right edge, hidden until hover
        if showClose {
            let cb = TabCloseButton(frame: .zero)
            cb.translatesAutoresizingMaskIntoConstraints = false
            cb.onClick = { [weak self] in self?.onClose?() }
            cb.wantsLayer = true
            cb.alphaValue = Self.closeBtnRestAlpha
            addSubview(cb)
            closeBtn = cb

            constraints += [
                cb.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
                cb.centerYAnchor.constraint(equalTo: centerYAnchor),
                cb.widthAnchor.constraint(equalToConstant: 16),
                cb.heightAnchor.constraint(equalToConstant: 16),
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // Measure true text width (intrinsicContentSize respects lineBreakMode and truncates)
        let textSize = titleLabel.attributedStringValue.size()
        let labelW = max(ceil(textSize.width) + 4, clipView.bounds.width)
        let labelH = ceil(textSize.height)
        let clipH = clipView.bounds.height
        let y = max(0, (clipH - labelH) / 2)
        titleLabel.frame = NSRect(x: 0, y: y, width: labelW, height: labelH)
    }

    private var titleOverflows: Bool {
        return titleLabel.frame.width > clipView.bounds.width && clipView.bounds.width > 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        // Show close button with fade-in
        if let cb = closeBtn {
            cb.isHidden = false
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                cb.animator().alphaValue = 1
            })
        }
        if !isActive {
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.toValue = tabColor.withAlphaComponent(0.12).cgColor
            anim.duration = 0.2
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(anim, forKey: "bg")
            layer?.backgroundColor = tabColor.withAlphaComponent(0.12).cgColor
            titleLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1.0)
        }
        startMarquee()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        // Fade close button back to subtle 25% opacity
        if let cb = closeBtn {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                cb.animator().alphaValue = Self.closeBtnRestAlpha
            })
        }
        stopMarquee()
        if !isActive {
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.toValue = NSColor.clear.cgColor
            anim.duration = 0.2
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(anim, forKey: "bg")
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = NSColor(calibratedWhite: 0.48, alpha: 1.0)
        }
    }

    private func startMarquee() {
        guard titleOverflows, let labelLayer = titleLabel.layer else { return }
        let overflow = titleLabel.frame.width - clipView.bounds.width
        let speed: Double = 28.0  // px per second
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -overflow
        anim.duration = Double(overflow) / speed
        anim.beginTime = CACurrentMediaTime() + 0.7
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        labelLayer.add(anim, forKey: "marquee")
    }

    private func stopMarquee() {
        titleLabel.layer?.removeAnimation(forKey: "marquee")
    }

    override func mouseDown(with event: NSEvent) {
        if let cb = closeBtn, !cb.isHidden {
            let loc = convert(event.locationInWindow, from: nil)
            if cb.frame.contains(loc) { return }
        }
        if event.clickCount == 2 {
            onDoubleClick?(tabIndex)
            return
        }
        dragOrigin = event.locationInWindow
        if !isActive {
            layer?.backgroundColor = tabColor.withAlphaComponent(0.25).cgColor
        }
    }

    private var isDragging = false

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let current = event.locationInWindow
        let dx = current.x - origin.x
        if !isDragging && abs(dx) > 5 {
            isDragging = true
            // Lower opacity when drag begins
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                self.animator().alphaValue = 0.5
            })
        }
        if isDragging {
            onDragMoved?(tabIndex, dx)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            dragOrigin = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.animator().alphaValue = 1.0
            })
            onDragEnded?(tabIndex)
            return
        }
        dragOrigin = nil
        if let cb = closeBtn, !cb.isHidden {
            let loc = convert(event.locationInWindow, from: nil)
            if cb.frame.contains(loc) { return }
        }
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        if !isActive {
            layer?.backgroundColor = isHovered
                ? tabColor.withAlphaComponent(0.12).cgColor
                : NSColor.clear.cgColor
        }
    }
}

// MARK: - Header Bar

class HeaderBarView: NSView, NSTextFieldDelegate {
    static let barHeight: CGFloat = 34

    override func resetCursorRects() {
        super.resetCursorRects()
        let e = BorderlessWindow.edgeInset
        let w = bounds.width, h = bounds.height
        // Inner area: arrow
        addCursorRect(NSRect(x: e, y: 0, width: w - e * 2, height: h), cursor: .arrow)
        // Left/right edges
        addCursorRect(NSRect(x: 0, y: 0, width: e, height: h), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: w - e, y: 0, width: e, height: h), cursor: .resizeLeftRight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let e = BorderlessWindow.edgeInset
        // Left/right edges only — top corners disabled (arrow area)
        if local.x < e || local.x > bounds.width - e { return nil }
        return super.hitTest(point)
    }

    // ── Drag-to-move when window is detached ───────────────────────────────
    private var dragOffset: NSPoint = .zero

    override func mouseDragged(with event: NSEvent) {
        guard (NSApp.delegate as? AppDelegate)?.isWindowDetached == true else {
            super.mouseDragged(with: event)
            return
        }
        let loc = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: loc.x - dragOffset.x, y: loc.y - dragOffset.y))
    }

    var onTabClicked: ((Int) -> Void)?
    var onAddTab: (() -> Void)?
    var onAddEditorTab: (() -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var onTabDoubleClicked: ((Int) -> Void)?
    var onTabRenamed: ((Int, String?) -> Void)?
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?
    var onGitToggle: (() -> Void)?
    var onWebPickerToggle: (() -> Void)?
    var onSSHToggle: (() -> Void)?

    private var tabContainer = NSView()
    private let tabScrollView = NSScrollView()
    private var addBtn: HoverButton!
    private var splitVBtn: SplitIconButton!
    private var splitHBtn: SplitIconButton!
    private var gitBtn: HoverButton!
    private var webPickerBtn: HoverButton!
    private var sshBtn: HoverButton!
    private let sep = NSView()
    private var lastTitles: [String] = []
    private var lastActiveIndex: Int = -1
    private var lastCount: Int = 0
    private var lastColors: [NSColor] = []
    private var lastScrollWidth: CGFloat = 0

    // Drag-to-reorder state
    private var dragTabOrigX: CGFloat = 0
    private var currentTabW: CGFloat = 160

    // Inline tab rename state
    private var editingTabIndex: Int? = nil
    private var editField: NSTextField?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.3).cgColor

        // Scrollable tab container
        tabScrollView.drawsBackground = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.horizontalScrollElasticity = .allowed
        tabScrollView.wantsLayer = true
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabContainer.wantsLayer = true
        tabScrollView.documentView = tabContainer
        addSubview(tabScrollView)

        // "+" button (right-aligned, blue hover)
        addBtn = HoverButton(title: "+", fontSize: 18, weight: .medium,
            normalColor: NSColor(calibratedWhite: 0.55, alpha: 1.0),
            hoverColor: NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 1.0),
            hoverBg: NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 0.12),
            pressBg: NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 0.25),
            cornerRadius: 6)
        addBtn.hoverScale = 1.3
        addBtn.onClick = { [weak self] in self?.onAddTab?() }
        let press = NSPressGestureRecognizer(target: self, action: #selector(addBtnLongPress(_:)))
        press.minimumPressDuration = 0.4
        addBtn.addGestureRecognizer(press)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addBtn)

        // Split buttons (left of "+")
        splitVBtn = SplitIconButton(vertical: true)
        splitVBtn.onClick = { [weak self] in self?.onSplitVertical?() }
        splitVBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitVBtn)

        splitHBtn = SplitIconButton(vertical: false)
        splitHBtn.onClick = { [weak self] in self?.onSplitHorizontal?() }
        splitHBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitHBtn)

        // GIT button
        gitBtn = HoverButton(title: "GIT", fontSize: 9, weight: .bold,
            normalColor: NSColor(calibratedWhite: 0.5, alpha: 1.0),
            hoverColor: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0),
            hoverBg: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 0.12),
            pressBg: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 0.25),
            cornerRadius: 4)
        gitBtn.onClick = { [weak self] in self?.onGitToggle?() }
        gitBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gitBtn)

        // WebPicker button
        webPickerBtn = HoverButton(title: "</>", fontSize: 9, weight: .bold,
            normalColor: NSColor(calibratedWhite: 0.5, alpha: 1.0),
            hoverColor: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 1.0),
            hoverBg: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 0.12),
            pressBg: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 0.25),
            cornerRadius: 4)
        webPickerBtn.onClick = { [weak self] in self?.onWebPickerToggle?() }
        webPickerBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webPickerBtn)

        // SSH button
        sshBtn = HoverButton(title: "SSH", fontSize: 9, weight: .bold,
            normalColor: NSColor(calibratedWhite: 0.5, alpha: 1.0),
            hoverColor: NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 1.0),
            hoverBg: NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.12),
            pressBg: NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.25),
            cornerRadius: 4)
        sshBtn.onClick = { [weak self] in self?.onSSHToggle?() }
        sshBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sshBtn)

        // Separator line at bottom
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            tabScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tabScrollView.trailingAnchor.constraint(equalTo: splitVBtn.leadingAnchor, constant: -4),
            tabScrollView.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: 24),

            // Buttons: [splitV] [splitH] [GIT] [+]
            splitVBtn.trailingAnchor.constraint(equalTo: splitHBtn.leadingAnchor, constant: -2),
            splitVBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitVBtn.widthAnchor.constraint(equalToConstant: 20),
            splitVBtn.heightAnchor.constraint(equalToConstant: 20),

            splitHBtn.trailingAnchor.constraint(equalTo: gitBtn.leadingAnchor, constant: -4),
            splitHBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitHBtn.widthAnchor.constraint(equalToConstant: 20),
            splitHBtn.heightAnchor.constraint(equalToConstant: 20),

            gitBtn.trailingAnchor.constraint(equalTo: webPickerBtn.leadingAnchor, constant: -4),
            gitBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            gitBtn.widthAnchor.constraint(equalToConstant: 30),
            gitBtn.heightAnchor.constraint(equalToConstant: 20),

            webPickerBtn.trailingAnchor.constraint(equalTo: sshBtn.leadingAnchor, constant: -4),
            webPickerBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            webPickerBtn.widthAnchor.constraint(equalToConstant: 30),
            webPickerBtn.heightAnchor.constraint(equalToConstant: 20),

            sshBtn.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -4),
            sshBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            sshBtn.widthAnchor.constraint(equalToConstant: 30),
            sshBtn.heightAnchor.constraint(equalToConstant: 20),

            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 24),
            addBtn.heightAnchor.constraint(equalToConstant: 24),

            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])

        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        dragOffset = event.locationInWindow   // save for drag-to-move in detached mode
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        let newW = tabScrollView.frame.width
        if newW != lastScrollWidth && lastCount > 0 {
            lastScrollWidth = newW
            forceRelayout()
        }
    }

    private func forceRelayout() {
        let count = lastCount
        let titles = lastTitles
        let activeIndex = lastActiveIndex
        let colors = lastColors
        // Reset to force full rebuild
        lastCount = 0
        updateTabs(count: count, activeIndex: activeIndex, titles: titles, colors: colors)
    }

    func updateTabs(count: Int, activeIndex: Int, titles: [String], colors: [NSColor]) {
        // Skip rebuild during drag-to-reorder or inline rename
        if draggedTab != nil || editingTabIndex != nil { return }
        // Skip rebuild if nothing changed (preserves hover/marquee state)
        if count == lastCount && activeIndex == lastActiveIndex && titles == lastTitles && colors == lastColors {
            return
        }
        let isNewTab = count > lastCount
        lastCount = count
        lastActiveIndex = activeIndex
        lastTitles = titles
        lastColors = colors
        lastScrollWidth = tabScrollView.frame.width

        for sub in tabContainer.subviews { sub.removeFromSuperview() }

        var xOff: CGFloat = 0
        let spacing: CGFloat = 3
        let tabHeight: CGFloat = 24
        // Fixed 160px tab width, horizontal scroll when overflow
        let tabW: CGFloat = 160
        currentTabW = tabW

        for i in 0..<count {
            let title = i < titles.count ? titles[i] : "~"
            let color = i < colors.count ? colors[i] : NSColor(calibratedWhite: 0.5, alpha: 1.0)
            let isActive = (i == activeIndex)
            let canClose = count > 1

            let tab = TabItemView(index: i, title: title, active: isActive, showClose: canClose,
                                  color: color)
            tab.onClick = { [weak self] in self?.onTabClicked?(i) }
            tab.onClose = { [weak self] in self?.onCloseTab?(i) }
            tab.onDoubleClick = { [weak self] idx in self?.startEditingTab(at: idx, currentTitle: title) }
            tab.onDragMoved = { [weak self] (idx, dx) in self?.handleDragMoved(tabIndex: idx, deltaX: dx) }
            tab.onDragEnded = { [weak self] idx in self?.handleDragEnded(tabIndex: idx) }

            tab.frame = NSRect(x: xOff, y: 0, width: tabW, height: tabHeight)
            tabContainer.addSubview(tab)

            // Fade-in animation for newly created tab
            if isNewTab && i == activeIndex {
                tab.wantsLayer = true
                tab.alphaValue = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    tab.animator().alphaValue = 1
                })
            }

            xOff += tabW + spacing
        }

        tabContainer.frame = NSRect(x: 0, y: 0, width: xOff, height: tabHeight)

        if activeIndex < tabContainer.subviews.count {
            let activeFrame = tabContainer.subviews[activeIndex].frame
            tabContainer.scrollToVisible(activeFrame)
        }
    }

    func setGitActive(_ active: Bool) {
        gitBtn.setActive(active)
    }

    func setWebPickerActive(_ active: Bool) {
        webPickerBtn.setActive(active)
    }

    func setSSHActive(_ active: Bool) {
        sshBtn.setActive(active)
    }

    func setSplitActive(vertical: Bool, active: Bool) {
        splitVBtn.setActive(vertical && active)
        splitHBtn.setActive(!vertical && active)
    }

    func resetSplitButtons() {
        splitVBtn.setActive(false)
        splitHBtn.setActive(false)
    }

    // MARK: Inline Tab Rename

    func startEditingTab(at index: Int, currentTitle: String) {
        // End any existing edit first
        finishEditingTab()

        editingTabIndex = index

        // Find the TabItemView for this index
        let tabs = tabContainer.subviews.compactMap { $0 as? TabItemView }
        guard let tabView = tabs.first(where: { $0.tabIndex == index }) else { return }

        // Create an editable text field overlaying the tab
        let field = NSTextField()
        field.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        field.stringValue = currentTitle
        field.isEditable = true
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        field.textColor = NSColor.white
        field.focusRingType = .none
        field.alignment = .center
        field.delegate = self
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        field.layer?.borderColor = tabView.tabColor.withAlphaComponent(0.6).cgColor
        field.layer?.borderWidth = 1

        // Position over the tab (in tabContainer coordinates)
        let inset: CGFloat = 2
        field.frame = NSRect(x: tabView.frame.origin.x + inset,
                             y: tabView.frame.origin.y,
                             width: tabView.frame.width - inset * 2,
                             height: tabView.frame.height)
        tabContainer.addSubview(field)
        editField = field

        // Select all text for easy replacement
        field.selectText(nil)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.count)
    }

    private func finishEditingTab() {
        guard let index = editingTabIndex, let field = editField else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)

        editingTabIndex = nil
        field.removeFromSuperview()
        editField = nil

        // Notify: empty string → reset to auto title (nil)
        onTabRenamed?(index, newName.isEmpty ? nil : newName)

        // Force rebuild
        forceRelayout()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishEditingTab()
    }

    // Handle Enter key to confirm
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            finishEditingTab()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            // Escape: cancel without saving
            editingTabIndex = nil
            editField?.removeFromSuperview()
            editField = nil
            forceRelayout()
            return true
        }
        return false
    }

    // MARK: Drag-to-Reorder

    private var draggedTab: TabItemView?
    private var dragCurrentSlot: Int = 0


    /// Logical order of tab indices during drag — maps slot → tabIndex
    private var dragSlotOrder: [Int] = []

    private func handleDragMoved(tabIndex: Int, deltaX: CGFloat) {
        let tabW = currentTabW
        let spacing: CGFloat = 3
        let tabs = tabContainer.subviews.compactMap { $0 as? TabItemView }
        let count = tabs.count

        if draggedTab == nil {
            // First drag move — initialize
            draggedTab = tabs.first { $0.tabIndex == tabIndex }
            dragCurrentSlot = tabIndex
            dragTabOrigX = CGFloat(tabIndex) * (tabW + spacing)
            dragSlotOrder = Array(0..<count)
        }

        guard let tab = draggedTab else { return }

        // Move tab to follow cursor
        let newX = dragTabOrigX + deltaX
        // Clamp to container bounds
        let maxX = CGFloat(count - 1) * (tabW + spacing)
        tab.frame.origin.x = max(0, min(maxX, newX))

        let midX = tab.frame.origin.x + tabW / 2

        // Determine which slot the dragged tab's midpoint falls into
        var targetSlot = Int(midX / (tabW + spacing))
        targetSlot = max(0, min(count - 1, targetSlot))

        if targetSlot != dragCurrentSlot {
            // Update logical order: move dragged tab from current slot to target slot
            dragSlotOrder.remove(at: dragCurrentSlot)
            dragSlotOrder.insert(tabIndex, at: targetSlot)

            // Animate all non-dragged tabs to their correct slot positions
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (slot, idx) in dragSlotOrder.enumerated() {
                    if idx == tabIndex { continue }  // skip dragged tab
                    if let otherTab = tabs.first(where: { $0.tabIndex == idx }) {
                        let slotX = CGFloat(slot) * (tabW + spacing)
                        otherTab.animator().frame.origin.x = slotX
                    }
                }
            })

            dragCurrentSlot = targetSlot
        }
    }

    private func handleDragEnded(tabIndex: Int) {
        guard let tab = draggedTab else { return }
        let tabW = currentTabW
        let spacing: CGFloat = 3
        let finalX = CGFloat(dragCurrentSlot) * (tabW + spacing)
        let movedToSlot = dragCurrentSlot

        // Clear drag state BEFORE notify so updateTabs isn't blocked
        draggedTab = nil
        dragSlotOrder = []

        // Snap tab to final slot position
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            tab.animator().frame.origin.x = finalX
        }, completionHandler: { [weak self] in
            // Force full rebuild after snap animation completes
            if tabIndex != movedToSlot {
                self?.forceRelayout()
            }
        })

        // Notify delegate if position changed
        if tabIndex != movedToSlot {
            onReorderTab?(tabIndex, movedToSlot)
        }
    }

    // MARK: Long-press on + button

    @objc private func addBtnLongPress(_ gr: NSPressGestureRecognizer) {
        guard gr.state == .began else { return }
        let menu = NSMenu()
        let termItem = NSMenuItem(title: "Terminal", action: #selector(longPressAddTerminal), keyEquivalent: "")
        termItem.target = self
        let editorItem = NSMenuItem(title: "Text Editor", action: #selector(longPressAddEditor), keyEquivalent: "")
        editorItem.target = self
        menu.addItem(termItem)
        menu.addItem(editorItem)
        let btnBounds = addBtn.bounds
        menu.popUp(positioning: nil,
                   at: NSPoint(x: btnBounds.midX, y: btnBounds.minY),
                   in: addBtn)
    }
    @objc private func longPressAddTerminal() { onAddTab?() }
    @objc private func longPressAddEditor()   { onAddEditorTab?() }

    // MARK: Drag destination (file drop → editor tab)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.createEditorTab(url: url)
        }
        return true
    }
}

// MARK: - Footer Bar

// Marquee scroll view — clips a label and scrolls it if wider than container
class MarqueeView: NSView {
    let label = NSTextField(labelWithString: "")
    private var scrollTimer: Timer?
    private var scrollOffset: CGFloat = 0
    private var needsScroll = false
    private var pauseCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        addSubview(label)

        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        label.stringValue = text
        label.sizeToFit()
        scrollOffset = 0
        pauseCount = 0
        needsScroll = label.frame.width > bounds.width
        label.frame = NSRect(x: 0, y: 0, width: label.frame.width, height: bounds.height)
    }

    private func tick() {
        guard needsScroll else {
            label.frame.origin.x = 0
            return
        }
        if pauseCount < 50 { // ~2s pause at start
            pauseCount += 1
            return
        }
        scrollOffset += 0.5
        let overflow = label.frame.width - bounds.width
        if scrollOffset > overflow + 30 {
            scrollOffset = 0
            pauseCount = 0
        }
        label.frame.origin.x = -scrollOffset
    }

    override func layout() {
        super.layout()
        needsScroll = label.frame.width > bounds.width
        if !needsScroll { label.frame.origin.x = 0 }
    }
}

// Clickable shell button with active state + hover animation
class ShellButton: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    let label: NSTextField
    var isActiveShell = false

    var accentColor: NSColor = NSColor(calibratedRed: 0.4, green: 0.65, blue: 1.0, alpha: 1.0)
    var inactiveColor: NSColor = NSColor(calibratedWhite: 0.4, alpha: 1.0)

    // Cached attributed string variants (avoid rebuilding on every hover)
    private var inactiveTitle: NSAttributedString!
    private var activeTitle: NSAttributedString!
    private var hoveredTitle: NSAttributedString!

    init(title: String, accent: NSColor? = nil) {
        label = NSTextField(labelWithString: "")
        super.init(frame: .zero)
        if let a = accent { accentColor = a }
        wantsLayer = true
        layer?.cornerRadius = 4

        // Pre-build all three styled variants
        inactiveTitle = Self.styledTitle(title, color: inactiveColor, weight: .regular)
        activeTitle = Self.styledTitle(title, color: NSColor(calibratedWhite: 0.92, alpha: 1.0), weight: .medium)
        hoveredTitle = Self.styledTitle(title, color: accentColor.withAlphaComponent(0.85), weight: .regular)

        label.attributedStringValue = inactiveTitle
        label.alignment = .center
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func styledTitle(_ title: String, color: NSColor, weight: NSFont.Weight) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: weight)
        let cmdFont = NSFont.systemFont(ofSize: 13, weight: weight)
        for char in title {
            let str = String(char)
            if str == "\u{2318}" {
                result.append(NSAttributedString(string: str, attributes: [
                    .font: cmdFont,
                    .foregroundColor: color,
                    .baselineOffset: -1.5
                ]))
            } else {
                result.append(NSAttributedString(string: str, attributes: [
                    .font: baseFont,
                    .foregroundColor: color
                ]))
            }
        }
        return result
    }

    private func animateBg(to color: NSColor, duration: CFTimeInterval = 0.15) {
        let c = color.cgColor
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        anim.toValue = c
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(anim, forKey: "bg")
        layer?.backgroundColor = c
    }

    func setActive(_ active: Bool) {
        isActiveShell = active
        if active {
            label.attributedStringValue = activeTitle
            animateBg(to: accentColor.withAlphaComponent(0.12), duration: 0.2)
        } else if !isHovered {
            label.attributedStringValue = inactiveTitle
            animateBg(to: .clear, duration: 0.2)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if !isActiveShell {
            animateBg(to: accentColor.withAlphaComponent(0.1))
            label.attributedStringValue = hoveredTitle
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isActiveShell {
            animateBg(to: .clear, duration: 0.2)
            label.attributedStringValue = inactiveTitle
        }
    }

    override func mouseDown(with event: NSEvent) {
        animateBg(to: accentColor.withAlphaComponent(0.18), duration: 0.06)
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        let target: NSColor = isActiveShell || isHovered
            ? accentColor.withAlphaComponent(0.1)
            : .clear
        animateBg(to: target, duration: 0.12)
    }
}

class SplitIconButton: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var iconLayer: CAShapeLayer!
    let isVertical: Bool
    private(set) var isActive = false

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard !isHovered else { return }
        let targetColor = active
            ? NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.9, alpha: 0.7).cgColor
            : NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        let targetBg = active
            ? NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
            : NSColor.clear.cgColor
        let colorAnim = CABasicAnimation(keyPath: "fillColor")
        colorAnim.toValue = targetColor
        colorAnim.duration = 0.25
        iconLayer.add(colorAnim, forKey: "iconColor")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        iconLayer.fillColor = targetColor
        layer?.backgroundColor = targetBg
        CATransaction.commit()
    }

    init(vertical: Bool) {
        self.isVertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5

        let sz: CGFloat = vertical ? 20 : 18
        iconLayer = CAShapeLayer()
        iconLayer.frame = CGRect(x: 0, y: 0, width: sz, height: sz)
        iconLayer.fillColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        iconLayer.position = CGPoint(x: 10, y: 10)
        buildIconPath()
        layer?.addSublayer(iconLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }

    private func buildIconPath() {
        let sz: CGFloat = isVertical ? 20.0 : 18.0
        let s: CGFloat = sz / 24.0  // scale to fit
        let path = CGMutablePath()
        if isVertical {
            path.addRect(CGRect(x: 11*s, y: 4*s, width: 1.5*s, height: 16*s))
            path.addRoundedRect(in: CGRect(x: 3*s, y: 5*s, width: 7*s, height: 14*s), cornerWidth: 1.2, cornerHeight: 1.2)
            path.addRoundedRect(in: CGRect(x: 4.2*s, y: 6.2*s, width: 4.6*s, height: 11.6*s), cornerWidth: 0.6, cornerHeight: 0.6)
            path.addRoundedRect(in: CGRect(x: 14*s, y: 5*s, width: 7*s, height: 14*s), cornerWidth: 1.2, cornerHeight: 1.2)
            path.addRoundedRect(in: CGRect(x: 15.2*s, y: 6.2*s, width: 4.6*s, height: 11.6*s), cornerWidth: 0.6, cornerHeight: 0.6)
        } else {
            path.addRect(CGRect(x: 4*s, y: 11*s, width: 16*s, height: 1.5*s))
            path.addRoundedRect(in: CGRect(x: 5*s, y: 3*s, width: 14*s, height: 7*s), cornerWidth: 1.2, cornerHeight: 1.2)
            path.addRoundedRect(in: CGRect(x: 6.2*s, y: 4.2*s, width: 11.6*s, height: 4.6*s), cornerWidth: 0.6, cornerHeight: 0.6)
            path.addRoundedRect(in: CGRect(x: 5*s, y: 14*s, width: 14*s, height: 7*s), cornerWidth: 1.2, cornerHeight: 1.2)
            path.addRoundedRect(in: CGRect(x: 6.2*s, y: 15.2*s, width: 11.6*s, height: 4.6*s), cornerWidth: 0.6, cornerHeight: 0.6)
        }
        iconLayer.path = path
        iconLayer.fillRule = .evenOdd
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor

        // Animate color to cyan/teal
        let colorAnim = CABasicAnimation(keyPath: "fillColor")
        let hoverColor = NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.9, alpha: 0.9).cgColor
        colorAnim.toValue = hoverColor
        colorAnim.duration = 0.25
        iconLayer.add(colorAnim, forKey: "iconColor")

        // Subtle scale pop
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.toValue = 1.15
        scale.duration = 0.2
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
        iconLayer.add(scale, forKey: "iconScale")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        iconLayer.fillColor = hoverColor
        iconLayer.transform = CATransform3DMakeScale(1.15, 1.15, 1)
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        let targetColor = isActive
            ? NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.9, alpha: 0.7).cgColor
            : NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        let targetBg = isActive
            ? NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
            : NSColor.clear.cgColor
        layer?.backgroundColor = targetBg

        let colorAnim = CABasicAnimation(keyPath: "fillColor")
        colorAnim.toValue = targetColor
        colorAnim.duration = 0.25
        iconLayer.add(colorAnim, forKey: "iconColor")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.toValue = 1.0
        scale.duration = 0.2
        iconLayer.add(scale, forKey: "iconScale")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        iconLayer.fillColor = targetColor
        iconLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.15).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        layer?.backgroundColor = (isHovered || isActive)
            ? NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
            : NSColor.clear.cgColor
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { isVertical ? "Split Vertically" : "Split Horizontally" }
}

class GearButton: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var gearLayer: CAShapeLayer!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5

        // Create gear icon as sublayer so only it rotates
        gearLayer = CAShapeLayer()
        gearLayer.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        gearLayer.fillColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        gearLayer.fillRule = .evenOdd
        gearLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        gearLayer.position = CGPoint(x: 12, y: 12)
        buildGearPath()
        layer?.addSublayer(gearLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    private func buildGearPath() {
        let cx: CGFloat = 12, cy: CGFloat = 12
        let innerR: CGFloat = 3.5, outerR: CGFloat = 6.5, toothR: CGFloat = 8.5
        let toothW: CGFloat = 3.0, teeth = 6

        let path = CGMutablePath()
        for i in 0..<teeth {
            let angle = (CGFloat(i) / CGFloat(teeth)) * .pi * 2 - .pi / 2
            let halfTooth = (toothW / 2) / toothR
            let a1 = angle - halfTooth, a2 = angle + halfTooth

            if i == 0 {
                path.move(to: CGPoint(x: cx + outerR * cos(a1), y: cy + outerR * sin(a1)))
            } else {
                let prevAngle = (CGFloat(i - 1) / CGFloat(teeth)) * .pi * 2 - .pi / 2
                let prevEnd = prevAngle + halfTooth
                path.addArc(center: CGPoint(x: cx, y: cy), radius: outerR,
                    startAngle: prevEnd, endAngle: a1, clockwise: false)
            }
            path.addLine(to: CGPoint(x: cx + toothR * cos(a1), y: cy + toothR * sin(a1)))
            path.addLine(to: CGPoint(x: cx + toothR * cos(a2), y: cy + toothR * sin(a2)))
            path.addLine(to: CGPoint(x: cx + outerR * cos(a2), y: cy + outerR * sin(a2)))
        }
        let lastAngle = (CGFloat(teeth - 1) / CGFloat(teeth)) * .pi * 2 - .pi / 2
        let lastEnd = lastAngle + (toothW / 2) / toothR
        let firstAngle = -CGFloat.pi / 2 - (toothW / 2) / toothR
        path.addArc(center: CGPoint(x: cx, y: cy), radius: outerR,
            startAngle: lastEnd, endAngle: firstAngle, clockwise: false)
        path.closeSubpath()

        // Center hole (even-odd fill cuts it out)
        path.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR,
                                    width: innerR * 2, height: innerR * 2))
        gearLayer.path = path
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor

        // Rotate gear icon 45° with spring feel
        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        let hoverAngle = CGFloat.pi / 4
        let hoverGearColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.28, alpha: 0.9).cgColor
        rotate.toValue = hoverAngle
        rotate.duration = 0.35
        rotate.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
        gearLayer.add(rotate, forKey: "gearRotate")

        // Animate color to warm amber/gold
        let colorAnim = CABasicAnimation(keyPath: "fillColor")
        colorAnim.toValue = hoverGearColor
        colorAnim.duration = 0.3
        gearLayer.add(colorAnim, forKey: "gearColor")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gearLayer.setValue(hoverAngle, forKeyPath: "transform.rotation.z")
        gearLayer.fillColor = hoverGearColor
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        layer?.backgroundColor = NSColor.clear.cgColor
        resetGearToNormal()
    }

    func resetGearToNormal() {
        // Rotate back to 0°
        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        rotate.toValue = 0
        rotate.duration = 0.3
        rotate.timingFunction = CAMediaTimingFunction(name: .easeOut)
        gearLayer.add(rotate, forKey: "gearRotate")

        // Animate color back to dim white
        let colorAnim = CABasicAnimation(keyPath: "fillColor")
        colorAnim.toValue = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        colorAnim.duration = 0.3
        gearLayer.add(colorAnim, forKey: "gearColor")

        // Set actual layer values so state is clean
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gearLayer.transform = CATransform3DIdentity
        gearLayer.fillColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.15).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        layer?.backgroundColor = isHovered
            ? NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
            : NSColor.clear.cgColor
    }
}

class QuitButton: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var arcLayer: CAShapeLayer!
    private var lineLayer: CAShapeLayer!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5

        let cx: CGFloat = 12, cy: CGFloat = 12, r: CGFloat = 6
        let dimColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor

        // Arc (open circle with gap at top)
        arcLayer = CAShapeLayer()
        arcLayer.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        arcLayer.fillColor = nil
        arcLayer.strokeColor = dimColor
        arcLayer.lineWidth = 1.8
        arcLayer.lineCap = .round
        let arc = CGMutablePath()
        // Gap at top (π/2). Arc from 50° to 130° going the long way clockwise.
        // In y-up coords: 50° is 2 o'clock, 130° is 10 o'clock
        arc.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: CGFloat.pi / 180 * 50,
                   endAngle: CGFloat.pi / 180 * 130,
                   clockwise: true)
        arcLayer.path = arc
        layer?.addSublayer(arcLayer)

        // Vertical line (top of circle down to center)
        lineLayer = CAShapeLayer()
        lineLayer.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        lineLayer.fillColor = nil
        lineLayer.strokeColor = dimColor
        lineLayer.lineWidth = 1.8
        lineLayer.lineCap = .round
        let line = CGMutablePath()
        line.move(to: CGPoint(x: cx, y: cy + r + 1))
        line.addLine(to: CGPoint(x: cx, y: cy))
        lineLayer.path = line
        layer?.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.12).cgColor
        let red = NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.95).cgColor

        for sl in [arcLayer!, lineLayer!] {
            let c = CABasicAnimation(keyPath: "strokeColor")
            c.toValue = red; c.duration = 0.25
            sl.add(c, forKey: "color")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            sl.strokeColor = red
            CATransaction.commit()
        }
        // Line bounces up → down → back
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, 2.5, -2.0, 0]
        bounce.keyTimes = [0, 0.3, 0.65, 1.0]
        bounce.duration = 0.45
        bounce.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0),
            CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0),
            CAMediaTimingFunction(name: .easeOut),
        ]
        lineLayer.add(bounce, forKey: "drop")
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false; isPressed = false
        layer?.backgroundColor = NSColor.clear.cgColor
        let dim = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor

        for sl in [arcLayer!, lineLayer!] {
            let c = CABasicAnimation(keyPath: "strokeColor")
            c.toValue = dim; c.duration = 0.25
            sl.add(c, forKey: "color")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            sl.strokeColor = dim
            CATransaction.commit()
        }
        let up = CABasicAnimation(keyPath: "transform.translation.y")
        up.toValue = 0; up.duration = 0.25
        lineLayer.add(up, forKey: "drop")
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.25).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        layer?.backgroundColor = isHovered
            ? NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.12).cgColor
            : NSColor.clear.cgColor
    }
}

class BadgeButton: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(keys: String, label: String, accentColor: NSColor? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        layer?.cornerRadius = 3.5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor

        let baseColor = accentColor ?? NSColor(calibratedRed: 0.4, green: 0.65, blue: 1.0, alpha: 1.0)
        let keyColor = baseColor.withAlphaComponent(0.6)
        let lblColor = baseColor.withAlphaComponent(0.85)

        let keyLbl = NSTextField(labelWithString: "")
        let keyAttr = NSMutableAttributedString()
        for ch in keys {
            let isShift = ch == "\u{21E7}"
            let isOption = ch == "\u{2325}"
            let sz: CGFloat = isShift ? 12 : (isOption ? 11 : 13)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: sz, weight: .regular),
                .foregroundColor: keyColor,
            ]
            if isShift { attrs[.baselineOffset] = 1.0 }
            keyAttr.append(NSAttributedString(string: String(ch), attributes: attrs))
        }
        keyLbl.attributedStringValue = keyAttr
        keyLbl.isEditable = false; keyLbl.isBordered = false; keyLbl.drawsBackground = false
        keyLbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLbl)

        let isSymbolLabel = label.unicodeScalars.contains { $0.value > 0x2000 }
        let txtLbl = NSTextField(labelWithString: label)
        txtLbl.font = isSymbolLabel
            ? NSFont.systemFont(ofSize: 13.5, weight: .medium)
            : NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        txtLbl.textColor = lblColor
        txtLbl.isEditable = false; txtLbl.isBordered = false; txtLbl.drawsBackground = false
        txtLbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(txtLbl)

        NSLayoutConstraint.activate([
            keyLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            keyLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            txtLbl.leadingAnchor.constraint(equalTo: keyLbl.trailingAnchor, constant: 3),
            txtLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            txtLbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.2).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.2).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        layer?.backgroundColor = isHovered
            ? NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
            : NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
    }
}

class FooterBarView: NSView {
    private var toggleBadge: BadgeButton!
    private var shellButtons: [ShellButton] = []
    private var tabShortcutBadges: [BadgeButton] = []
    var gearBtn: GearButton!
    private var quitBtn: QuitButton!
    private(set) var usageBadge: AIUsageBadge!
    // Scroll containers for each column
    private let linksScroll = NSScrollView()
    private let linksContent = NSView()
    private let rechtsScroll = NSScrollView()
    private let rechtsContent = NSView()
    static let barHeight: CGFloat = 44

    var onSwitchShell: ((Int) -> Void)?
    var onSettings: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onCloseTab: (() -> Void)?
    var onSplitV: (() -> Void)?
    var onSplitH: (() -> Void)?
    var onToggleWindow: (() -> Void)?
    var onSwitchSplitPane: (() -> Void)?
    var onPrevTab: (() -> Void)?
    var onNextTab: (() -> Void)?
    var onUsageBadgeClick: (() -> Void)?

    private func makeScrollView(_ sv: NSScrollView, content: NSView) {
        sv.drawsBackground = false
        sv.hasHorizontalScroller = false
        sv.hasVerticalScroller = false
        sv.horizontalScrollElasticity = .allowed
        sv.verticalScrollElasticity = .none
        content.wantsLayer = true
        sv.documentView = content
        addSubview(sv)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let e = BorderlessWindow.edgeInset
        if local.x > bounds.width - e || local.y < e ||
           (local.x > bounds.width - e * 2 && local.y < e * 2) { return nil }
        if local.x < e { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let e = BorderlessWindow.edgeInset
        let w = bounds.width, h = bounds.height
        // Bottom edge (resize up/down)
        addCursorRect(NSRect(x: e, y: 0, width: w - e * 2, height: e), cursor: .resizeUpDown)
        // Left edge
        addCursorRect(NSRect(x: 0, y: e, width: e, height: h - e), cursor: .resizeLeftRight)
        // Right edge
        addCursorRect(NSRect(x: w - e, y: e, width: e, height: h - e), cursor: .resizeLeftRight)
        // Bottom corners (diagonal)
        addCursorRect(NSRect(x: 0, y: 0, width: e, height: e), cursor: BorderlessWindow.resizeNESW)
        addCursorRect(NSRect(x: w - e, y: 0, width: e, height: e), cursor: BorderlessWindow.resizeNWSE)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.3).cgColor

        // Separator at top
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])

        // --- LINKS: AI usage badge + shell buttons ---
        makeScrollView(linksScroll, content: linksContent)

        // AI Usage badge (first element, far left)
        usageBadge = AIUsageBadge(frame: .zero)
        usageBadge.onClick = { [weak self] in self?.onUsageBadgeClick?() }
        usageBadge.isHidden = !UserDefaults.standard.bool(forKey: "showAIUsage")
        linksContent.addSubview(usageBadge)

        let shellItems: [(title: String, accent: NSColor)] = [
            ("\u{2318} 1 zsh",  NSColor(calibratedRed: 0.4, green: 0.65, blue: 1.0, alpha: 1.0)),
            ("\u{2318} 2 bash", NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.45, alpha: 1.0)),
            ("\u{2318} 3 sh",   NSColor(calibratedRed: 0.9, green: 0.65, blue: 0.35, alpha: 1.0)),
        ]
        for (i, item) in shellItems.enumerated() {
            let btn = ShellButton(title: item.title, accent: item.accent)
            btn.onClick = { [weak self] in self?.onSwitchShell?(i) }
            linksContent.addSubview(btn)
            shellButtons.append(btn)
        }

        // --- RECHTS: branch + badges + gear + quit ---
        makeScrollView(rechtsScroll, content: rechtsContent)

        // Git branch removed — info now in Git Panel

        toggleBadge = BadgeButton(keys: "^", label: "<",
            accentColor: NSColor(calibratedRed: 0.9, green: 0.6, blue: 0.2, alpha: 1.0))
        toggleBadge.onClick = { [weak self] in self?.onToggleWindow?() }
        rechtsContent.addSubview(toggleBadge)

        let badgeItems: [(keys: String, label: String, color: NSColor?)] = [
            ("\u{2318}", "\u{2190}", NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.5, alpha: 1.0)),
            ("\u{2318}", "\u{2192}", NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.5, alpha: 1.0)),
            ("\u{2325}", "\u{21E5}", NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.5, alpha: 1.0)),
            ("\u{2318}", "T", nil), ("\u{2318}", "W", nil),
            ("\u{2318}", "D", nil), ("\u{2318}\u{21E7}", "D", nil),
        ]
        for (i, item) in badgeItems.enumerated() {
            let badge = BadgeButton(keys: item.keys, label: item.label, accentColor: item.color)
            rechtsContent.addSubview(badge)
            switch i {
            case 0: badge.onClick = { [weak self] in self?.onPrevTab?() }
            case 1: badge.onClick = { [weak self] in self?.onNextTab?() }
            case 2: badge.onClick = { [weak self] in self?.onSwitchSplitPane?() }
            case 3: badge.onClick = { [weak self] in self?.onNewTab?() }
            case 4: badge.onClick = { [weak self] in self?.onCloseTab?() }
            case 5: badge.onClick = { [weak self] in self?.onSplitV?() }
            case 6: badge.onClick = { [weak self] in self?.onSplitH?() }
            default: break
            }
            tabShortcutBadges.append(badge)
        }

        gearBtn = GearButton(frame: .zero)
        gearBtn.onClick = { [weak self] in self?.onSettings?() }
        rechtsContent.addSubview(gearBtn)

        quitBtn = QuitButton(frame: .zero)
        quitBtn.onClick = { NSApp.terminate(nil) }
        rechtsContent.addSubview(quitBtn)


    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let cy = h / 2 + 2
        let pad: CGFloat = 20
        let gap: CGFloat = 4
        let badgeGap: CGFloat = 3
        let itemH: CGFloat = 24
        let iconSize: CGFloat = 24

        // --- LINKS: AI usage badge + shell buttons ---
        let shellBtnW: CGFloat = 70
        var lx: CGFloat = pad
        // AI usage badge first (far left)
        if !usageBadge.isHidden {
            let ubSz = usageBadge.intrinsicContentSize
            usageBadge.frame = NSRect(x: lx, y: cy - ubSz.height / 2, width: ubSz.width, height: ubSz.height)
            lx += ubSz.width + gap
        }
        for btn in shellButtons {
            btn.frame = NSRect(x: lx, y: cy - itemH / 2, width: shellBtnW, height: itemH)
            lx += shellBtnW + gap
        }
        let linksW = lx + pad  // content width with padding

        // --- RECHTS: measure content ---
        var rx: CGFloat = 4

        let tbSz = toggleBadge.fittingSize
        let tbW = max(tbSz.width, 30)
        let tbH = max(tbSz.height, 22)
        toggleBadge.frame = NSRect(x: rx, y: cy - tbH / 2, width: tbW, height: tbH)
        rx += tbW + badgeGap

        for badge in tabShortcutBadges {
            let sz = badge.fittingSize
            let bw = max(sz.width, 30)
            let bh = max(sz.height, 22)
            badge.frame = NSRect(x: rx, y: cy - bh / 2, width: bw, height: bh)
            rx += bw + badgeGap
        }
        rx += 13
        gearBtn.frame = NSRect(x: rx, y: cy - iconSize / 2, width: iconSize, height: iconSize)
        rx += iconSize + gap
        quitBtn.frame = NSRect(x: rx, y: cy - iconSize / 2, width: iconSize, height: iconSize)
        rx += iconSize + 16
        let rechtsW = rx

        // --- Column layout: LINKS fixed left, RECHTS fixed right ---
        let linksColW = min(linksW, w * 0.4)
        let rechtsColW = min(rechtsW, w * 0.6)

        // LINKS: pinned left
        linksScroll.frame = NSRect(x: 0, y: 0, width: linksColW, height: h)
        linksContent.frame = NSRect(x: 0, y: 0, width: max(linksW, linksColW), height: h)

        // RECHTS: pinned right
        let rechtsX = w - rechtsColW
        rechtsScroll.frame = NSRect(x: rechtsX, y: 0, width: rechtsColW, height: h)
        let rechtsInternalW = max(rechtsW, rechtsColW)
        // Shift all right items so they end at the right edge
        let rechtsShift = rechtsInternalW - rechtsW
        if rechtsShift > 0 {
            for sub in rechtsContent.subviews {
                sub.frame.origin.x += rechtsShift
            }
        }
        rechtsContent.frame = NSRect(x: 0, y: 0, width: rechtsInternalW, height: h)
        // Scroll to right end to show gear+quit
        if rechtsW > rechtsColW {
            let scrollX = rechtsInternalW - rechtsColW
            rechtsScroll.contentView.scroll(to: NSPoint(x: scrollX, y: 0))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(shell: String, pid: pid_t) {
        // Highlight active shell button
        let shellPaths = ["/bin/zsh", "/bin/bash", "/bin/sh"]
        for (i, btn) in shellButtons.enumerated() {
            let isActive = (i < shellPaths.count && shell == shellPaths[i])
            btn.setActive(isActive)
        }
    }
}

// MARK: - Settings Overlay

// Interactive settings row with hover effect and pointer cursor
class SettingsRowView: NSView {
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    var hoverControl: NSView?  // optional control to fade on hover
    private static let normalBg = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor
    private static let hoverBg = NSColor(calibratedWhite: 1.0, alpha: 0.09).cgColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = Self.normalBg
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = Self.hoverBg
            self.hoverControl?.animator().alphaValue = 0.9
        }
        NSCursor.arrow.push()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().layer?.backgroundColor = Self.normalBg
            self.hoverControl?.animator().alphaValue = 1.0
        }
        NSCursor.pop()
    }
}

class SettingsToggle: NSView {
    var isOn: Bool { didSet { updateAppearance() } }
    var onChange: ((Bool) -> Void)?
    private var trackLayer: CALayer!
    private var thumbLayer: CALayer!
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 18))
        wantsLayer = true

        trackLayer = CALayer()
        trackLayer.cornerRadius = 9
        trackLayer.frame = CGRect(x: 0, y: 0, width: 34, height: 18)
        layer?.addSublayer(trackLayer)

        thumbLayer = CALayer()
        thumbLayer.cornerRadius = 7
        thumbLayer.frame = CGRect(x: 2, y: 2, width: 14, height: 14)
        thumbLayer.backgroundColor = NSColor.white.cgColor
        thumbLayer.shadowColor = NSColor.black.cgColor
        thumbLayer.shadowOpacity = 0.25
        thumbLayer.shadowRadius = 1
        thumbLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(thumbLayer)

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.arrow.push()
        // Subtle scale-up on hover
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        layer?.transform = CATransform3DMakeScale(1.08, 1.08, 1)
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        if isOn {
            trackLayer.backgroundColor = NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 1.0).cgColor
            thumbLayer.frame.origin.x = 18
        } else {
            trackLayer.backgroundColor = NSColor(calibratedWhite: 0.3, alpha: 1.0).cgColor
            thumbLayer.frame.origin.x = 2
        }
        CATransaction.commit()
    }

    func setOn(_ value: Bool, animated: Bool) {
        isOn = value
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onChange?(isOn)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 34, height: 18) }
}

// Helper for target-action closures on NSSlider/NSSegmentedControl
class BlockTarget: NSObject {
    static let shared = BlockTarget()
    private var sliderHandlers: [ObjectIdentifier: (NSSlider) -> Void] = [:]
    private var segHandlers: [ObjectIdentifier: (NSSegmentedControl) -> Void] = [:]
    private var btnHandlers: [ObjectIdentifier: () -> Void] = [:]

    func register(_ slider: NSSlider, handler: @escaping (NSSlider) -> Void) {
        sliderHandlers[ObjectIdentifier(slider)] = handler
        slider.target = self
        slider.action = #selector(sliderAction(_:))
    }
    func registerSeg(_ seg: NSSegmentedControl, handler: @escaping (NSSegmentedControl) -> Void) {
        segHandlers[ObjectIdentifier(seg)] = handler
        seg.target = self
        seg.action = #selector(segAction(_:))
    }
    func register(_ btn: NSButton, handler: @escaping () -> Void) {
        btnHandlers[ObjectIdentifier(btn)] = handler
        btn.target = self
        btn.action = #selector(btnAction(_:))
    }
    @objc func sliderAction(_ sender: NSSlider) {
        sliderHandlers[ObjectIdentifier(sender)]?(sender)
    }
    @objc func segAction(_ sender: NSSegmentedControl) {
        segHandlers[ObjectIdentifier(sender)]?(sender)
    }
    @objc func btnAction(_ sender: NSButton) {
        btnHandlers[ObjectIdentifier(sender)]?()
    }
    func registerField(_ field: NSTextField, handler: @escaping () -> Void) {
        btnHandlers[ObjectIdentifier(field)] = handler
        field.target = self
        field.action = #selector(fieldAction(_:))
    }
    @objc func fieldAction(_ sender: NSTextField) {
        btnHandlers[ObjectIdentifier(sender)]?()
    }

}

class ResetRowView: NSView {
    var onClick: (() -> Void)?
    var isDisabled = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private let normalBg = NSColor(calibratedRed: 0.4, green: 0.1, blue: 0.1, alpha: 0.25).cgColor
    private let hoverBg = NSColor(calibratedRed: 0.55, green: 0.12, blue: 0.12, alpha: 0.45).cgColor
    private let pressBg = NSColor(calibratedRed: 0.65, green: 0.15, blue: 0.15, alpha: 0.55).cgColor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isDisabled else { return }
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = hoverBg
        }
        NSCursor.arrow.push()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = isDisabled
                ? NSColor(calibratedWhite: 0.2, alpha: 0.1).cgColor : normalBg
        }
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isDisabled else { return }
        layer?.backgroundColor = pressBg
    }

    override func mouseUp(with event: NSEvent) {
        guard !isDisabled else { return }
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            onClick?()
        }
        layer?.backgroundColor = isHovered ? hoverBg : normalBg
    }
}

private class ThemeCardView: NSView {
    var isChosen = false { didSet { updateLook() } }
    var onClick: (() -> Void)?
    private var isHovered = false

    init(preview: NSAttributedString) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        let lbl = NSTextField(labelWithAttributedString: preview)
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            lbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
        ])
        updateLook()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.arrow.push()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.updateLook(animated: true)
        }
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.updateLook(animated: true)
        }
    }
    override func mouseDown(with event: NSEvent) {
        // Press effect
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        CATransaction.commit()
    }
    override func mouseUp(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
    }

    private func updateLook(animated: Bool = false) {
        let bg: CGColor
        let borderW: CGFloat
        let borderC: CGColor
        if isChosen {
            bg = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
            borderW = 1
            borderC = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 0.4).cgColor
        } else if isHovered {
            bg = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
            borderW = 0.5
            borderC = NSColor(calibratedWhite: 1.0, alpha: 0.15).cgColor
        } else {
            bg = NSColor.clear.cgColor
            borderW = 0
            borderC = NSColor.clear.cgColor
        }
        if animated {
            animator().layer?.backgroundColor = bg
        } else {
            layer?.backgroundColor = bg
        }
        layer?.borderWidth = borderW
        layer?.borderColor = borderC
    }
}

// MARK: - Diagnostics Overlay

class DiagnosticsOverlay: NSView {
    enum Mode { case perf, parser }
    let mode: Mode
    private let textView = NSTextView()
    private var updateTimer: Timer?
    weak var terminalView: TerminalView?

    init(frame: NSRect, mode: Mode) {
        self.mode = mode
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.72).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.3, alpha: 0.6).cgColor

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor(calibratedRed: 0.4, green: 1.0, blue: 0.4, alpha: 1.0)
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.autoresizingMask = [.width, .height]
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError() }

    func startUpdating() {
        refresh()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func refresh() {
        guard let tv = terminalView else { return }
        switch mode {
        case .perf:
            tv.perf.sample()
            let p = tv.perf
            let text = """
            --- Performance ---
            FPS:          \(String(format: "%.1f", p.fps))
            Draw avg:     \(String(format: "%.2f", p.avgDrawMs)) ms
            Last draw:    \(String(format: "%.2f", p.lastDrawTime * 1000)) ms
            PTY read:     \(formatBytes(p.readBytesPerSec))/s (\(p.readsPerSec) calls/s)
            PTY write:    \(formatBytes(p.writeBytesPerSec))/s (\(p.writesPerSec) calls/s)
            Grid:         \(tv.terminal.cols)x\(tv.terminal.rows)
            Scrollback:   \(tv.terminal.scrollback.count) lines
            """
            textView.string = text
        case .parser:
            let d = tv.terminal.diag
            var text = """
            --- Parser ---
            Total scalars: \(d.totalScalars)
            CSI:           \(d.csiCount)
            OSC:           \(d.oscCount)
            ESC:           \(d.escCount)
            DCS:           \(d.dcsCount)
            """
            if !d.unhandled.isEmpty {
                text += "\n\n--- Unhandled Sequences ---"
                for entry in d.unhandled.suffix(15) {
                    text += "\n  \(entry.seq)  x\(entry.count)"
                }
            } else {
                text += "\n\nNo unhandled sequences."
            }
            textView.string = text
        }
    }

    private func formatBytes(_ bps: Int) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f MB", Double(bps) / 1_048_576) }
        if bps >= 1024 { return String(format: "%.1f KB", Double(bps) / 1024) }
        return "\(bps) B"
    }

    override func mouseDown(with event: NSEvent) {
        // Consume clicks so they don't pass through
    }
}

class SettingsOverlay: NSView {
    var onClose: (() -> Void)?
    var onChanged: ((String, Any) -> Void)?
    private var headerView: NSView!
    private var contentScroll: NSScrollView!
    private var contentDoc: NSView!
    private let headerH: CGFloat = 30
    private var messagePopup: NSView?
    private var resetRow: NSView?
    private var themeCards: [ThemeCardView] = []
    private weak var themePickerView: NSView?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true

        // Frosted glass blur background
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .withinWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 8
        blur.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(blur)

        // Dark tint overlay — gradient from opaque top to transparent bottom
        let tintView = NSView(frame: bounds)
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedWhite: 0.03, alpha: 1.0).cgColor,
            NSColor(calibratedWhite: 0.03, alpha: 0.0).cgColor,
        ]
        gradient.locations = [0.0, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.frame = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        tintView.layer?.addSublayer(gradient)
        addSubview(tintView)

        // --- Scrollable content area (added BEFORE header so header is on top) ---
        contentScroll = NSScrollView()
        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.verticalScroller?.alphaValue = 0
        contentScroll.scrollerStyle = .overlay
        contentScroll.drawsBackground = false
        contentScroll.borderType = .noBorder
        addSubview(contentScroll)

        contentDoc = NSView()
        contentDoc.wantsLayer = true
        contentScroll.documentView = contentDoc

        // --- Settings rows in content (positioned from top via layout) ---
        let rowH: CGFloat = 28
        var rows: [NSView] = []

        // Language
        rows.append(makeSectionHeader(Loc.language))
        rows.append(makeLanguageRow())

        // Color Theme
        rows.append(makeSectionHeader(Loc.colorThemeSection))
        let themeIdx = UserDefaults.standard.integer(forKey: "colorTheme")
        let colorThemeRow = ColorThemeRow(selected: themeIdx)
        colorThemeRow.onChanged = { [weak self] key, idx in
            UserDefaults.standard.set(idx, forKey: key)
            self?.onChanged?(key, idx)
            self?.updateResetButtonState()
        }
        colorThemeRow.onPreview = { idx in
            (NSApp.delegate as? AppDelegate)?.previewTheme(idx)
        }
        rows.append(colorThemeRow)

        // Visual
        rows.append(makeSliderRow(label: Loc.opacity, min: 0.3, max: 1.0,
            value: UserDefaults.standard.double(forKey: "windowOpacity"),
            fmt: "%0.f%%", fmtScale: 100, key: "windowOpacity"))

        rows.append(makeSliderRow(label: Loc.blur, min: 0.0, max: 1.0,
            value: UserDefaults.standard.double(forKey: "blurIntensity"),
            fmt: "%0.f%%", fmtScale: 100, key: "blurIntensity"))

        rows.append(makeSliderRow(label: Loc.fontSize, min: 8, max: 18,
            value: UserDefaults.standard.double(forKey: "terminalFontSize"),
            fmt: "%0.fpt", fmtScale: 1,
            key: "terminalFontSize"))

        let cursorVal = UserDefaults.standard.integer(forKey: "cursorStyle")
        rows.append(makeSegmentRow(label: Loc.cursor, options: ["▁ Line", "▏Beam", "█ Block"],
            selected: cursorVal, key: "cursorStyle"))
        rows.append(makeToggleRow(label: Loc.cursorBlink, settingsKey: "cursorBlink"))

        let fontNames = TerminalView.availableFonts.map { $0.0 }
        let fontIdx = UserDefaults.standard.integer(forKey: "fontFamily")
        rows.append(makeSegmentRow(label: Loc.font, options: fontNames,
            selected: fontIdx, key: "fontFamily"))

        rows.append(makeToggleRow(label: Loc.syntaxHighlight, settingsKey: "syntaxHighlighting"))

        // Theme picker — each button IS the preview
        let themeNames = ["default", "cyberpunk", "minimal", "powerline", "retro", "lambda", "starship"]
        let currentTheme = UserDefaults.standard.string(forKey: "promptTheme") ?? "default"
        let promptThemeIdx = themeNames.firstIndex(of: currentTheme) ?? 0
        for i in 0..<7 {
            let card = ThemeCardView(preview: themeCardPreview(i))
            card.isChosen = (i == promptThemeIdx)
            themeCards.append(card)
        }
        for (i, card) in themeCards.enumerated() {
            card.onClick = { [weak self] in self?.selectTheme(i) }
        }
        let picker = NSView()
        picker.wantsLayer = true
        picker.layer?.cornerRadius = 6
        picker.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.25).cgColor
        picker.layer?.borderWidth = 1
        picker.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor
        themeCards.forEach { picker.addSubview($0) }
        themePickerView = picker
        rows.append(picker)

        // Behavior
        let shellIdx = UserDefaults.standard.integer(forKey: "defaultShellIndex")
        rows.append(makeSegmentRow(label: Loc.defaultShell, options: ["zsh", "bash", "sh"],
            selected: shellIdx, key: "defaultShellIndex"))

        // Window behavior group
        rows.append(makeSectionHeader(Loc.windowSection))
        rows.append(makeToggleRow(label: Loc.alwaysOnTop, settingsKey: "alwaysOnTop"))
        rows.append(makeToggleRow(label: Loc.followAllSpaces, settingsKey: "followAllSpaces"))
        rows.append(makeToggleRow(label: Loc.autoDim, settingsKey: "autoDim"))
        rows.append(makeToggleRow(label: Loc.hideOnClickOutside, settingsKey: "hideOnClickOutside"))
        rows.append(makeToggleRow(label: Loc.hideOnDeactivate, settingsKey: "hideOnDeactivate"))

        rows.append(makeToggleRow(label: Loc.copyOnSelect, settingsKey: "copyOnSelect"))
        rows.append(makeToggleRow(label: Loc.launchAtLogin, settingsKey: "autoStartEnabled"))
        rows.append(makeToggleRow(label: Loc.autoCheckUpdates, settingsKey: "autoCheckUpdates"))
        rows.append(makeToggleRow(label: "Tabs verwenden (Editor)", settingsKey: "editorUseTabs"))

        // WebPicker
        rows.append(makeSectionHeader(Loc.webpickerSection))
        rows.append(makeSegmentRow(label: Loc.browser, options: ["Chrome", "Safari"],
            selected: 0,
            key: "webPickerBrowser",
            disabled: true))

        // AI Usage
        rows.append(makeSectionHeader(Loc.claudeSection))
        rows.append(makeToggleRow(label: Loc.showUsageBadge, settingsKey: "showAIUsage"))
        rows.append(makeSegmentRow(label: Loc.refresh, options: ["5m", "10m", "30m"],
            selected: UserDefaults.standard.integer(forKey: "aiUsageRefreshIndex"),
            key: "aiUsageRefreshIndex"))
        rows.append(makeStatusRow())

        rows.append(makeResetRow())

        let pickerH: CGFloat = 124  // 7 cards × 16px + gaps + padding
        var contentH: CGFloat = 12
        for row in rows {
            let h = (row === themePickerView) ? pickerH : rowH
            contentH += h + 12
        }
        contentDoc.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentH)
        for row in rows {
            let h = (row === themePickerView) ? pickerH : rowH
            row.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: h)
            contentDoc.addSubview(row)
        }

        // --- Fixed header (added AFTER content so it's on top z-order) ---
        headerView = NSView()
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.5).cgColor
        addSubview(headerView)

        // Blur behind header
        let headerBlur = NSVisualEffectView()
        headerBlur.blendingMode = .withinWindow
        headerBlur.material = .hudWindow
        headerBlur.state = .active
        headerBlur.autoresizingMask = [.width, .height]
        headerView.addSubview(headerBlur, positioned: .below, relativeTo: nil)

        // Close button in header — big icon, small bg
        let closeBtn = HoverButton(title: "\u{2715}", fontSize: 11, weight: .bold,
            normalColor: NSColor(calibratedWhite: 0.4, alpha: 1.0),
            hoverColor: .white,
            hoverBg: NSColor(calibratedRed: 0.85, green: 0.18, blue: 0.18, alpha: 0.75),
            pressBg: NSColor(calibratedRed: 0.7, green: 0.12, blue: 0.12, alpha: 1.0),
            cornerRadius: 3)
        // Nudge glyph up to visually center in small button
        let closeLblAttr = NSMutableAttributedString(string: "\u{2715}", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1.0),
            .baselineOffset: 0.5,
        ])
        closeBtn.label.attributedStringValue = closeLblAttr
        closeBtn.onClick = { [weak self] in self?.onClose?() }
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeBtn)

        // Separator line at bottom of header
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(sep)

        NSLayoutConstraint.activate([
            closeBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -6),
            closeBtn.widthAnchor.constraint(equalToConstant: 16),
            closeBtn.heightAnchor.constraint(equalToConstant: 16),

            sep.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Scroll to top on open
        DispatchQueue.main.async { [weak self] in
            guard let doc = self?.contentDoc else { return }
            doc.scroll(NSPoint(x: 0, y: doc.frame.height))
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        // Fixed header at top (y-up: top = h - headerH)
        headerView.frame = CGRect(x: 0, y: h - headerH, width: w, height: headerH)

        // Scrollable content below header
        let contentY: CGFloat = 0
        let contentH = h - headerH
        contentScroll.frame = CGRect(x: 0, y: contentY, width: w, height: contentH)

        // Resize content doc to fill scroll area
        let docH = max(contentDoc.frame.height, contentH)
        contentDoc.frame = NSRect(x: 0, y: 0, width: w, height: docH)

        // Position rows from top, resize width
        var rowY = docH - 12
        for sub in contentDoc.subviews {
            rowY -= sub.frame.height
            sub.frame = CGRect(x: 16, y: rowY, width: w - 32, height: sub.frame.height)
            rowY -= 12
        }

        // Layout theme cards inside picker
        if let picker = themePickerView {
            let cardH: CGFloat = 16
            let gap: CGFloat = 1
            let pad: CGFloat = 3
            let cw = picker.bounds.width - pad * 2
            for (i, card) in themeCards.enumerated() {
                let y = picker.bounds.height - pad - CGFloat(i + 1) * (cardH + gap) + gap
                card.frame = CGRect(x: pad, y: y, width: cw, height: cardH)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func showMessagePopup() {
        guard messagePopup == nil else { hideMessagePopup(); return }

        let popW: CGFloat = bounds.width - 16
        let popH: CGFloat = 140
        let popup = NSView(frame: NSRect(x: 8, y: bounds.height - headerH - popH - 4,
                                          width: popW, height: popH))
        popup.wantsLayer = true
        popup.layer?.cornerRadius = 8
        popup.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor
        popup.layer?.borderColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 0.2).cgColor
        popup.layer?.borderWidth = 1

        // Blur behind
        let blur = NSVisualEffectView(frame: popup.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .withinWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 8
        popup.addSubview(blur)

        // Title
        let titleLbl = NSTextField(labelWithString: Loc.sendFeedback)
        titleLbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        titleLbl.textColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        titleLbl.isEditable = false; titleLbl.isBordered = false; titleLbl.drawsBackground = false
        titleLbl.frame = NSRect(x: 12, y: popH - 24, width: 120, height: 16)
        popup.addSubview(titleLbl)

        // Close X
        let xBtn = HoverButton(title: "\u{2715}", fontSize: 9, weight: .medium,
            normalColor: NSColor(calibratedWhite: 0.4, alpha: 1.0),
            hoverColor: .white,
            hoverBg: NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.2, alpha: 0.6),
            pressBg: NSColor(calibratedRed: 0.6, green: 0.15, blue: 0.15, alpha: 0.8),
            cornerRadius: 3)
        xBtn.frame = NSRect(x: popW - 24, y: popH - 26, width: 18, height: 18)
        xBtn.onClick = { [weak self] in self?.hideMessagePopup() }
        popup.addSubview(xBtn)

        // Text field
        let textView = NSTextView(frame: NSRect(x: 12, y: 36, width: popW - 24, height: popH - 64))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.9, alpha: 1.0)
        textView.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.8)
        textView.insertionPointColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 4)
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 5
        textView.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        textView.layer?.borderWidth = 1
        popup.addSubview(textView)

        // Send button
        let sendBtn = HoverButton(title: "\(Loc.sendFeedback) \u{2197}", fontSize: 9.5, weight: .bold,
            normalColor: NSColor(calibratedRed: 0.35, green: 0.6, blue: 1.0, alpha: 1.0),
            hoverColor: .white,
            hoverBg: NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 0.25),
            pressBg: NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 0.4),
            cornerRadius: 5)
        sendBtn.frame = NSRect(x: popW - 72, y: 8, width: 60, height: 22)
        // Status label for feedback
        let statusLbl = NSTextField(labelWithString: "")
        statusLbl.font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
        statusLbl.isEditable = false; statusLbl.isBordered = false; statusLbl.drawsBackground = false
        statusLbl.frame = NSRect(x: 12, y: 10, width: popW - 96, height: 16)
        popup.addSubview(statusLbl)

        sendBtn.onClick = { [weak self] in
            let msg = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !msg.isEmpty else { return }
            // Send directly via /usr/sbin/sendmail (built into macOS)
            let to = "l.ersen@icloud.com"
            let subject = "quickTERMINAL Feedback"
            let hostname = Host.current().localizedName ?? "quickTerminal-user"
            let email = "From: quickTerminal@\(hostname)\r\nTo: \(to)\r\nSubject: \(subject)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(msg)"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/sendmail")
            proc.arguments = ["-t"]
            let pipe = Pipe()
            proc.standardInput = pipe
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                if let emailData = email.data(using: .utf8) {
                    pipe.fileHandleForWriting.write(emailData)
                }
                pipe.fileHandleForWriting.closeFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    statusLbl.textColor = NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
                    statusLbl.stringValue = Loc.sent
                    textView.string = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.hideMessagePopup()
                    }
                } else {
                    // Fallback to mailto
                    Self.openMailto(msg)
                    self?.hideMessagePopup()
                }
            } catch {
                // Fallback to mailto
                Self.openMailto(msg)
                self?.hideMessagePopup()
            }
        }
        popup.addSubview(sendBtn)

        popup.alphaValue = 0
        addSubview(popup)
        messagePopup = popup

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            popup.animator().alphaValue = 1
        }
        // Focus text field
        window?.makeFirstResponder(textView)
    }

    private static func openMailto(_ msg: String) {
        let subject = "quickTERMINAL Feedback"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = msg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? msg
        if let url = URL(string: "mailto:l.ersen@icloud.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func hideMessagePopup() {
        guard let popup = messagePopup else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            popup.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            popup.removeFromSuperview()
            self?.messagePopup = nil
        })
    }

    func updateToggle(forKey key: String, value: Bool) {
        // Walk content doc to find the toggle row with matching key
        for sub in contentDoc.subviews {
            for child in sub.subviews {
                if let toggle = child as? SettingsToggle {
                    // Check if this row's toggle matches by finding its parent's label
                    for sibling in sub.subviews {
                        if let lbl = sibling as? NSTextField, lbl.stringValue == labelForKey(key) {
                            toggle.setOn(value, animated: true)
                            return
                        }
                    }
                }
            }
        }
    }

    private func labelForKey(_ key: String) -> String {
        switch key {
        case "alwaysOnTop": return Loc.alwaysOnTop
        case "autoDim": return Loc.autoDim
        case "hideOnClickOutside": return Loc.hideOnClickOutside
        case "hideOnDeactivate": return Loc.hideOnDeactivate
        case "copyOnSelect": return Loc.copyOnSelect
        case "cursorBlink": return Loc.cursorBlink
        case "autoStartEnabled": return Loc.launchAtLogin
        default: return ""
        }
    }

    private func makeLanguageRow() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        let currentLang = Loc.lang
        for code in Loc.supported {
            let flag = Loc.flags[code] ?? code
            let btn = NSButton(title: flag, target: nil, action: nil)
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 15)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 5
            btn.translatesAutoresizingMaskIntoConstraints = false
            if code == currentLang {
                btn.layer?.borderWidth = 1.5
                btn.layer?.borderColor = NSColor(calibratedRed: 0.24, green: 0.79, blue: 0.63, alpha: 0.8).cgColor
                btn.layer?.backgroundColor = NSColor(calibratedRed: 0.24, green: 0.79, blue: 0.63, alpha: 0.12).cgColor
            } else {
                btn.layer?.borderWidth = 0
                btn.layer?.backgroundColor = NSColor.clear.cgColor
            }
            let capturedCode = code
            BlockTarget.shared.register(btn) { [weak self] in
                Loc.lang = capturedCode
                UserDefaults.standard.set(capturedCode, forKey: "appLanguage")
                NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
                // Rebuild settings panel with new language
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.onClose?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
                    }
                }
            }
            stack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let row = NSView()
        row.wantsLayer = true

        let lbl = NSTextField(labelWithString: title.uppercased())
        lbl.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        lbl.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(line)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            lbl.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
            line.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 8),
            line.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            line.centerYAnchor.constraint(equalTo: lbl.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])

        return row
    }

    private func makeToggleRow(label: String, settingsKey: String) -> NSView {
        let row = SettingsRowView()

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        lbl.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)

        let isOn = UserDefaults.standard.bool(forKey: settingsKey)
        let toggle = SettingsToggle(isOn: isOn)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.onChange = { [weak self] on in
            UserDefaults.standard.set(on, forKey: settingsKey)
            if settingsKey == "autoStartEnabled" {
                Self.setAutoStart(on)
            }
            self?.onChanged?(settingsKey, on)
            self?.updateResetButtonState()
        }
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),

            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            toggle.widthAnchor.constraint(equalToConstant: 34),
            toggle.heightAnchor.constraint(equalToConstant: 18),
        ])

        return row
    }

    private func makeSliderRow(label: String, min: Double, max: Double, value: Double,
                                fmt: String, fmtScale: Double, key: String) -> NSView {
        let row = SettingsRowView()

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        lbl.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)

        let valLbl = NSTextField(labelWithString: String(format: fmt, value * fmtScale))
        valLbl.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        valLbl.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
        valLbl.alignment = .right
        valLbl.isEditable = false; valLbl.isBordered = false; valLbl.drawsBackground = false
        valLbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(valLbl)

        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        slider.isContinuous = true
        slider.controlSize = .mini
        slider.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(slider)

        row.hoverControl = slider

        slider.target = BlockTarget.shared
        let handler: (NSSlider) -> Void = { [weak self] s in
            let v = s.doubleValue
            UserDefaults.standard.set(v, forKey: key)
            valLbl.stringValue = String(format: fmt, v * fmtScale)
            self?.onChanged?(key, CGFloat(v))
            self?.updateResetButtonState()
        }
        BlockTarget.shared.register(slider, handler: handler)

        NSLayoutConstraint.activate([
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            lbl.widthAnchor.constraint(equalToConstant: 90),

            slider.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 4),
            slider.trailingAnchor.constraint(equalTo: valLbl.leadingAnchor, constant: -4),

            valLbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valLbl.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            valLbl.widthAnchor.constraint(equalToConstant: 40),
        ])

        return row
    }

    private func makeSegmentRow(label: String, options: [String], selected: Int, key: String, onChange: ((Int) -> Void)? = nil, disabled: Bool = false) -> NSView {
        let row = SettingsRowView()

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        lbl.textColor = disabled ? NSColor(calibratedWhite: 0.4, alpha: 1.0) : NSColor(calibratedWhite: 0.75, alpha: 1.0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)

        let seg = NSSegmentedControl(labels: options, trackingMode: .selectOne,
                                      target: nil, action: nil)
        seg.selectedSegment = min(selected, options.count - 1)
        seg.controlSize = .mini
        seg.segmentStyle = .rounded
        seg.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        seg.isEnabled = !disabled
        seg.alphaValue = disabled ? 0.35 : 1.0
        seg.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(seg)

        if !disabled {
            row.hoverControl = seg
            seg.target = BlockTarget.shared
            let handler: (NSSegmentedControl) -> Void = { [weak self] s in
                let idx = s.selectedSegment
                UserDefaults.standard.set(idx, forKey: key)
                self?.onChanged?(key, idx)
                self?.updateResetButtonState()
                onChange?(idx)
            }
            BlockTarget.shared.registerSeg(seg, handler: handler)
        }

        NSLayoutConstraint.activate([
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),

            seg.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            seg.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
        ])

        return row
    }

    private func selectTheme(_ idx: Int) {
        for (i, card) in themeCards.enumerated() { card.isChosen = (i == idx) }
        onChanged?("promptTheme", idx)
        updateResetButtonState()
    }

    private func themeCardPreview(_ index: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let f = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let dim = NSColor(calibratedWhite: 0.4, alpha: 1.0)
        let cyan = NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.95, alpha: 1.0)
        let yel = NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.35, alpha: 1.0)
        let mag = NSColor(calibratedRed: 0.85, green: 0.45, blue: 0.9, alpha: 1.0)
        let grn = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
        let blu = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
        let wht = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        func a(_ t: String, _ c: NSColor) {
            s.append(NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c]))
        }
        switch index {
        case 0: a("Default   ", wht); a("~ %", dim)
        case 1: a("Cyber     ", wht); a("╭─ ", dim); a("⚡user", cyan); a(" ~/dev", yel); a(" ‹main ✔›", mag); a(" ╰─", dim); a("❯", cyan)
        case 2: a("Minimal   ", wht); a("dev", blu); a(" ❯", wht)
        case 3: a("Power     ", wht); a("▌", grn); a("user", wht); a("▌", yel); a("~/dev", wht); a("▌", blu); a("main", wht); a("▌", dim)
        case 4: a("Retro     ", wht); a("[user@qt ~/dev", grn); a(" (main)", yel); a("]$", grn)
        case 5: a("Lambda    ", wht); a("λ", mag); a(" ~/dev ", cyan); a("[main]", grn); a(" →", mag)
        case 6: a("Starship  ", wht); a("~/dev", cyan); a(" on ", dim); a("main", mag); a(" ❯", grn)
        default: break
        }
        return s
    }

    private var confirmView: NSView?
    private var resetConfirmTimer: Timer?

    private func makeStatusRow() -> NSView {
        let row = SettingsRowView()
        let hasToken = AIUsageManager.shared.hasToken

        let lbl = NSTextField(labelWithString: Loc.status)
        lbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        lbl.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)

        let statusLbl = NSTextField(labelWithString: hasToken ? Loc.connected : Loc.noToken)
        statusLbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLbl.textColor = hasToken
            ? NSColor(calibratedRed: 0.3, green: 0.75, blue: 0.4, alpha: 1.0)
            : NSColor(calibratedRed: 0.85, green: 0.4, blue: 0.3, alpha: 1.0)
        statusLbl.isEditable = false; statusLbl.isBordered = false; statusLbl.drawsBackground = false
        statusLbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(statusLbl)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lbl.widthAnchor.constraint(equalToConstant: 42),
            statusLbl.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 4),
            statusLbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

    private var resetLabel: NSTextField?

    private func makeResetRow() -> NSView {
        let row = ResetRowView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 6
        row.layer?.backgroundColor = NSColor(calibratedRed: 0.4, green: 0.1, blue: 0.1, alpha: 0.25).cgColor

        let lbl = NSTextField(labelWithString: Loc.resetToDefaults)
        lbl.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
        lbl.textColor = NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 0.8)
        lbl.alignment = .center
        lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)

        NSLayoutConstraint.activate([
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lbl.centerXAnchor.constraint(equalTo: row.centerXAnchor),
        ])

        row.onClick = { [weak self] in
            guard let self = self, self.resetRow != nil, !self.isAtDefaults() else { return }
            self.showResetConfirm()
        }

        resetLabel = lbl
        resetRow = row
        updateResetButtonState()
        return row
    }

    private func showResetConfirm() {
        guard let row = resetRow, confirmView == nil else { return }

        // Hide the reset text
        resetLabel?.isHidden = true

        let cv = NSView(frame: row.bounds)
        cv.wantsLayer = true
        cv.autoresizingMask = [.width, .height]

        let sureLabel = NSTextField(labelWithString: Loc.sure)
        sureLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
        sureLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.4, blue: 0.4, alpha: 1.0)
        sureLabel.isEditable = false; sureLabel.isBordered = false; sureLabel.drawsBackground = false
        sureLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sureLabel)

        let yesBtn = HoverButton(title: "\u{2713}", fontSize: 12, weight: .bold,
            normalColor: NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.4, alpha: 0.9),
            hoverColor: .white,
            hoverBg: NSColor(calibratedRed: 0.3, green: 0.7, blue: 0.3, alpha: 0.3),
            pressBg: NSColor(calibratedRed: 0.3, green: 0.7, blue: 0.3, alpha: 0.5),
            cornerRadius: 4)
        yesBtn.translatesAutoresizingMaskIntoConstraints = false
        yesBtn.onClick = { [weak self] in
            self?.hideResetConfirm()
            self?.onChanged?("resetDefaults", true)
        }
        cv.addSubview(yesBtn)

        let noBtn = HoverButton(title: "\u{2715}", fontSize: 11, weight: .bold,
            normalColor: NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 0.8),
            hoverColor: .white,
            hoverBg: NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.2, alpha: 0.3),
            pressBg: NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.2, alpha: 0.5),
            cornerRadius: 4)
        noBtn.translatesAutoresizingMaskIntoConstraints = false
        noBtn.onClick = { [weak self] in self?.hideResetConfirm() }
        cv.addSubview(noBtn)

        NSLayoutConstraint.activate([
            sureLabel.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            sureLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor, constant: -24),
            yesBtn.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            yesBtn.leadingAnchor.constraint(equalTo: sureLabel.trailingAnchor, constant: 8),
            yesBtn.widthAnchor.constraint(equalToConstant: 22),
            yesBtn.heightAnchor.constraint(equalToConstant: 22),
            noBtn.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            noBtn.leadingAnchor.constraint(equalTo: yesBtn.trailingAnchor, constant: 4),
            noBtn.widthAnchor.constraint(equalToConstant: 22),
            noBtn.heightAnchor.constraint(equalToConstant: 22),
        ])

        cv.alphaValue = 0
        row.addSubview(cv)
        confirmView = cv

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            cv.animator().alphaValue = 1
        }

        // Auto-cancel after 4 seconds
        resetConfirmTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.hideResetConfirm()
        }
    }

    private func hideResetConfirm() {
        resetConfirmTimer?.invalidate()
        resetConfirmTimer = nil
        guard let cv = confirmView else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            cv.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            cv.removeFromSuperview()
            self?.confirmView = nil
            self?.resetLabel?.isHidden = false
        })
    }

    static let defaultSettings: [String: Any] = [
        "appLanguage": "",
        "windowOpacity": 0.99,
        "blurIntensity": 0.96,
        "terminalFontSize": 10.0,
        "cursorStyle": 0,
        "fontFamily": 0,
        "defaultShellIndex": 0,
        "alwaysOnTop": true,
        "followAllSpaces": false,
        "autoDim": false,
        "hideOnClickOutside": false,
        "hideOnDeactivate": false,
        "copyOnSelect": true,
        "cursorBlink": true,
        "syntaxHighlighting": true,
        "promptTheme": "default",
        "autoStartEnabled": false,
        "autoCheckUpdates": true,
        "editorUseTabs": false,
        "webPickerBrowser": 0,
        "showAIUsage": true,
        "aiUsageRefreshIndex": 0,
        "colorTheme": 0,
    ]

    private func isAtDefaults() -> Bool {
        let ud = UserDefaults.standard
        for (key, defVal) in Self.defaultSettings {
            if let d = defVal as? Double {
                if abs(ud.double(forKey: key) - d) > 0.001 { return false }
            } else if let i = defVal as? Int {
                if ud.integer(forKey: key) != i { return false }
            } else if let b = defVal as? Bool {
                if ud.bool(forKey: key) != b { return false }
            } else if let s = defVal as? String {
                if ud.string(forKey: key) != s { return false }
            }
        }
        // Window size not at default 720×480
        let w = ud.double(forKey: "windowWidth")
        let h = ud.double(forKey: "windowHeight")
        if w > 0 && abs(w - 860) > 1 { return false }
        if h > 0 && abs(h - 480) > 1 { return false }
        // Window was moved from default centered position
        let sx = ud.double(forKey: "windowX")
        let sy = ud.double(forKey: "windowY")
        if sx != 0 || sy != 0 { return false }
        return true
    }

    func updateResetButtonState() {
        let atDefaults = isAtDefaults()
        resetLabel?.textColor = atDefaults
            ? NSColor(calibratedWhite: 0.35, alpha: 0.4)
            : NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 0.8)
        (resetRow as? ResetRowView)?.isDisabled = atDefaults
        resetRow?.layer?.backgroundColor = atDefaults
            ? NSColor(calibratedWhite: 0.2, alpha: 0.1).cgColor
            : NSColor(calibratedRed: 0.4, green: 0.1, blue: 0.1, alpha: 0.25).cgColor
    }

    static func setAutoStart(_ enabled: Bool) {
        // Use SMAppService on macOS 13+ or LaunchAgent for older
        if #available(macOS 13.0, *) {
            import_SMAppService_setAutoStart(enabled)
        } else {
            setAutoStartLegacy(enabled)
        }
    }

    @available(macOS 13.0, *)
    private static func import_SMAppService_setAutoStart(_ enabled: Bool) {
        // SMAppService requires a bundled app; fall back to LaunchAgent
        setAutoStartLegacy(enabled)
    }

    private static func setAutoStartLegacy(_ enabled: Bool) {
        let home = NSHomeDirectory()
        let agentDir = "\(home)/Library/LaunchAgents"
        let plistPath = "\(agentDir)/com.quickterminal.autostart.plist"

        if enabled {
            // Create LaunchAgent plist
            let execPath = CommandLine.arguments[0]
            let absPath = execPath.hasPrefix("/") ? execPath
                : FileManager.default.currentDirectoryPath + "/" + execPath
            let plist: [String: Any] = [
                "Label": "com.quickterminal.autostart",
                "ProgramArguments": [absPath],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            try? FileManager.default.createDirectory(atPath: agentDir,
                withIntermediateDirectories: true)
            (plist as NSDictionary).write(toFile: plistPath, atomically: true)
        } else {
            try? FileManager.default.removeItem(atPath: plistPath)
        }
    }
}

// MARK: - GitHub Auth & API

struct GitHubKeychainStore {
    private static let service = "com.quickTerminal.github"

    static func save(key: String, value: String) {
        delete(key: key)
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        guard status == errSecSuccess, let data = ref as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

class GitHubClient {
    var token: String? { didSet { if let t = token, !t.isEmpty { GitHubKeychainStore.save(key: "oauth-token", value: t) } } }
    var username: String?

    struct RemoteCache {
        var pullRequests: [(number: Int, title: String, author: String)] = []
        var remoteCommits: [(hash: String, message: String)] = []
        var workflowRuns: [(name: String, status: String, conclusion: String?, branch: String, htmlURL: String)] = []
        var lastFetch: Date = .distantPast
    }
    var cache = RemoteCache()
    private let cacheTTL: TimeInterval = 30

    init() {
        // Try gh CLI token first, then keychain
        if let ghToken = GitHubClient.ghCliToken(), !ghToken.isEmpty {
            token = ghToken
        } else {
            token = GitHubKeychainStore.load(key: "oauth-token")
        }
    }

    var isAuthenticated: Bool { token != nil && !(token?.isEmpty ?? true) }

    // MARK: - gh CLI Token Detection

    static func ghCliToken() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["gh", "auth", "token"]
        proc.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (token?.isEmpty ?? true) ? nil : token
        } catch { return nil }
    }

    func setToken(_ value: String) {
        token = value
    }

    // MARK: - Remote URL Parsing

    func parseRemoteURL(cwd: String) -> (owner: String, repo: String)? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["remote", "get-url", "origin"]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.environment = ["GIT_TERMINAL_PROMPT": "0", "PATH": "/usr/bin:/usr/local/bin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let url = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            return extractOwnerRepo(from: url)
        } catch { return nil }
    }

    private func extractOwnerRepo(from urlString: String) -> (owner: String, repo: String)? {
        if urlString.contains("github.com:") {
            let parts = urlString.split(separator: ":").last?.replacingOccurrences(of: ".git", with: "").split(separator: "/")
            if let parts = parts, parts.count >= 2 {
                return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
            }
        }
        if urlString.contains("github.com/") {
            let cleaned = urlString.replacingOccurrences(of: ".git", with: "")
            let parts = cleaned.split(separator: "/")
            if parts.count >= 2 {
                return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
            }
        }
        return nil
    }

    // MARK: - API Calls

    func fetchUser(completion: @escaping (String?) -> Void) {
        apiGet(path: "/user") { [weak self] json in
            let dict = json as? [String: Any]
            self?.username = dict?["login"] as? String
            DispatchQueue.main.async { completion(self?.username) }
        }
    }

    func fetchPRs(owner: String, repo: String, completion: @escaping ([(number: Int, title: String, author: String)]) -> Void) {
        apiGet(path: "/repos/\(owner)/\(repo)/pulls?state=open&per_page=10") { jsonAny in
            guard let arr = jsonAny as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let prs: [(Int, String, String)] = arr.compactMap { item in
                guard let num = item["number"] as? Int,
                      let title = item["title"] as? String else { return nil }
                let author = (item["user"] as? [String: Any])?["login"] as? String ?? "?"
                return (num, title, author)
            }
            DispatchQueue.main.async { completion(prs) }
        }
    }

    func fetchRemoteCommits(owner: String, repo: String, branch: String, completion: @escaping ([(hash: String, message: String)]) -> Void) {
        apiGet(path: "/repos/\(owner)/\(repo)/commits?sha=\(branch)&per_page=8") { jsonAny in
            guard let arr = jsonAny as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let commits: [(String, String)] = arr.compactMap { item in
                guard let sha = item["sha"] as? String,
                      let commit = item["commit"] as? [String: Any],
                      let msg = commit["message"] as? String else { return nil }
                let shortSha = String(sha.prefix(7))
                let firstLine = msg.split(separator: "\n").first.map(String.init) ?? msg
                return (shortSha, firstLine)
            }
            DispatchQueue.main.async { completion(commits) }
        }
    }

    private func apiGet(path: String, completion: @escaping (Any?) -> Void) {
        guard let token = token, let url = URL(string: "https://api.github.com\(path)") else {
            completion(nil); return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data = data else { completion(nil); return }
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 401 {
                completion(nil); return
            }
            let json = try? JSONSerialization.jsonObject(with: data)
            completion(json)
        }.resume()
    }

    func fetchWorkflowRuns(owner: String, repo: String, completion: @escaping ([(name: String, status: String, conclusion: String?, branch: String, htmlURL: String)]) -> Void) {
        apiGet(path: "/repos/\(owner)/\(repo)/actions/runs?per_page=5") { json in
            guard let dict = json as? [String: Any],
                  let runs = dict["workflow_runs"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let result = runs.compactMap { run -> (name: String, status: String, conclusion: String?, branch: String, htmlURL: String)? in
                guard let name = run["name"] as? String,
                      let status = run["status"] as? String,
                      let branch = run["head_branch"] as? String,
                      let htmlURL = run["html_url"] as? String else { return nil }
                let conclusion = run["conclusion"] as? String
                return (name, status, conclusion, branch, htmlURL)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func fetchRemoteDataIfNeeded(cwd: String, branch: String, completion: @escaping () -> Void) {
        guard isAuthenticated else { completion(); return }
        if Date().timeIntervalSince(cache.lastFetch) < cacheTTL { completion(); return }

        guard let (owner, repo) = parseRemoteURL(cwd: cwd) else { completion(); return }
        let group = DispatchGroup()

        group.enter()
        fetchPRs(owner: owner, repo: repo) { [weak self] prs in
            self?.cache.pullRequests = prs
            group.leave()
        }

        group.enter()
        fetchRemoteCommits(owner: owner, repo: repo, branch: branch) { [weak self] commits in
            self?.cache.remoteCommits = commits
            group.leave()
        }

        group.enter()
        fetchWorkflowRuns(owner: owner, repo: repo) { [weak self] runs in
            self?.cache.workflowRuns = runs
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.cache.lastFetch = Date()
            completion()
        }
    }

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
                let msg = json?["message"] as? String ?? "Error \(http.statusCode)"
                DispatchQueue.main.async { completion(false, msg) }
            }
        }.resume()
    }

    func logout() {
        token = nil
        username = nil
        cache = RemoteCache()
        GitHubKeychainStore.delete(key: "oauth-token")
    }
}

// MARK: - Clickable Toast View

class ClickableToastView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onClick?()
        removeFromSuperview()
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - AI Usage Manager

struct AITokenStore {
    /// Read Claude Code OAuth token via `security` CLI (no macOS permission dialog)
    static func readClaudeCodeToken() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        // Parse JSON: {"claudeAiOauth":{"accessToken":"sk-ant-oat01-..."}}
        guard let jsonData = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return token
    }
}

struct AIUsageCategory: Codable {
    let utilization: Double   // 0-100
    let resetsAt: Date?
}

struct AIUsageData: Codable {
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
    private static let usageURL = "https://api.anthropic.com/api/oauth/usage"

    var onUpdate: ((AIUsageData?) -> Void)?
    private(set) var latestData: AIUsageData? { didSet { if let d = latestData { saveToDisk(d) } } }
    private(set) var lastStatusCode = 0
    private var pollTimer: Timer?
    private var cachedToken: String?
    private var tokenChecked = false
    private static let cacheKey = "aiUsageDataCache"
    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Read token from Claude Code's Keychain via security CLI (cached)
    func readToken() -> String? {
        if tokenChecked { return cachedToken }
        tokenChecked = true
        cachedToken = AITokenStore.readClaudeCodeToken()
        return cachedToken
    }

    var hasToken: Bool { readToken() != nil }

    func clearData() { latestData = nil; cachedToken = nil; tokenChecked = false }

    /// Load last cached data from disk (called on startup so badge shows immediately)
    func loadCachedData() {
        guard let raw = UserDefaults.standard.data(forKey: Self.cacheKey),
              let data = try? JSONDecoder().decode(AIUsageData.self, from: raw) else { return }
        latestData = data
        onUpdate?(data)
    }

    private func saveToDisk(_ data: AIUsageData) {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.cacheKey)
        }
    }

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let path = "/tmp/qt-aiusage.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    /// Fetch usage data from Claude Code OAuth API
    func fetchUsage() {
        guard let token = readToken() else {
            debugLog("No token found — stopping polling")
            stopPolling()
            DispatchQueue.main.async { self.onUpdate?(nil) }
            return
        }
        debugLog("Token loaded (\(token.count) chars), fetching...")
        var request = URLRequest(url: URL(string: Self.usageURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error = error { self.debugLog("Network error: \(error.localizedDescription)") }
            self.debugLog("HTTP \(statusCode)")
            if let data = data, let body = String(data: data, encoding: .utf8) {
                self.debugLog("Response: \(String(body.prefix(500)))")
            }
            DispatchQueue.main.async { self.lastStatusCode = statusCode }
            // Auth errors → clear badge + reset token cache so next poll re-reads Keychain
            // (Claude Code rotates OAuth tokens; cached token becomes stale over time)
            if statusCode == 401 || statusCode == 403 {
                self.cachedToken = nil
                self.tokenChecked = false
                DispatchQueue.main.async { self.onUpdate?(nil) }
                return
            }
            // Transient errors (429, network, 5xx) → keep last data, badge stays green
            guard let data = data, statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
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

    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        fetchUsage()
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
}

// MARK: - AI Usage Badge

class AIUsageBadge: NSView {
    var onClick: (() -> Void)?
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "AI \u{2014}")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var utilization: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3.5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = NSColor(calibratedWhite: 0.4, alpha: 1.0).cgColor
        addSubview(dot)

        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        label.textColor = NSColor(calibratedWhite: 0.4, alpha: 0.85)
        label.isEditable = false; label.isBordered = false; label.drawsBackground = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        dot.frame = NSRect(x: 7, y: (h - 7) / 2, width: 7, height: 7)
        label.sizeToFit()
        label.frame = NSRect(x: 19, y: (h - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
    }

    func update(data: AIUsageData?) {
        guard let data = data, let session = data.fiveHour else {
            label.stringValue = "AI \u{2014}"
            label.textColor = NSColor(calibratedWhite: 0.4, alpha: 0.85)
            dot.layer?.backgroundColor = NSColor(calibratedWhite: 0.4, alpha: 1.0).cgColor
            needsLayout = true
            superview?.needsLayout = true
            return
        }
        utilization = session.utilization
        label.stringValue = "AI \(Int(utilization))%"

        let color: NSColor
        if utilization >= 80 {
            color = NSColor.systemRed
        } else if utilization >= 50 {
            color = NSColor.systemOrange
        } else {
            color = NSColor.systemGreen
        }
        dot.layer?.backgroundColor = color.cgColor
        label.textColor = color.withAlphaComponent(0.85)
        needsLayout = true
        superview?.needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        label.sizeToFit()
        let w = max(80, label.frame.width + 28)
        return NSSize(width: w, height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.2).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.2).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onClick?() }
        layer?.backgroundColor = isHovered
            ? NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
            : NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
    }
}

// MARK: - AI Usage Popover

class AIUsagePopover: NSView {
    var onDismiss: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let contentStack = NSView()
    private let refreshBtn = NSButton()

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

        refreshBtn.title = "↻"
        refreshBtn.isBordered = false
        refreshBtn.bezelStyle = .inline
        refreshBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        refreshBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        refreshBtn.toolTip = "Jetzt aktualisieren"
        refreshBtn.target = self
        refreshBtn.action = #selector(doRefresh)

        addSubview(contentStack)
        addSubview(refreshBtn)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func doRefresh() {
        refreshBtn.isEnabled = false
        refreshBtn.contentTintColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        onRefresh?()
    }

    func setRefreshDone() {
        refreshBtn.isEnabled = true
        refreshBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
    }

    func update(data: AIUsageData?) {
        contentStack.subviews.forEach { $0.removeFromSuperview() }

        guard let data = data else {
            let statusCode = AIUsageManager.shared.lastStatusCode
            let msg: String
            let msgColor: NSColor
            if statusCode == 429 {
                msg = "API rate limited (429) — please wait"
                msgColor = NSColor(calibratedRed: 0.9, green: 0.6, blue: 0.2, alpha: 1)
            } else if statusCode == 401 || statusCode == 403 {
                msg = "Invalid token — please sign in again"
                msgColor = NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.35, alpha: 1)
            } else if statusCode == 0 {
                msg = "Waiting for first response..."
                msgColor = NSColor(calibratedWhite: 0.5, alpha: 1)
            } else {
                msg = "No data (HTTP \(statusCode))"
                msgColor = NSColor(calibratedWhite: 0.5, alpha: 1)
            }
            let noData = makeLabel(msg, size: 10, color: msgColor)
            contentStack.addSubview(noData)
            noData.frame = NSRect(x: 12, y: 14, width: bounds.width - 44, height: 16)
            frame.size.height = 46
            contentStack.frame = bounds
            refreshBtn.frame = NSRect(x: bounds.width - 28, y: 12, width: 22, height: 18)
            return
        }

        var y: CGFloat = 12
        let w: CGFloat = bounds.width - 24

        // Timestamp
        let elapsed = Int(Date().timeIntervalSince(data.fetchedAt))
        let agoStr = elapsed < 5 ? "gerade eben" : "vor \(elapsed)s"
        let ts = makeLabel("\u{21BB} \(agoStr)", size: 8, color: NSColor(calibratedWhite: 0.4, alpha: 1))
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
        contentStack.frame = bounds
        // Refresh button — bottom-right corner, aligned with timestamp row
        refreshBtn.frame = NSRect(x: bounds.width - 28, y: 10, width: 22, height: 18)
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

// MARK: - Sidebar Context Menu

/// Shared right-click menu for all sidebar panels (Git, WebPicker, SSH).
private func showSidebarContextMenu(in view: NSView, event: NSEvent) {
    guard let del = NSApp.delegate as? AppDelegate else { return }
    let menu = NSMenu()

    let gitOn = del.activeTab < del.tabGitPositions.count && del.tabGitPositions[del.activeTab] != .none
    let gitItem = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
    gitItem.state = gitOn ? .on : .off
    gitItem.target = del
    gitItem.action = #selector(AppDelegate.toggleGitPanel)
    menu.addItem(gitItem)

    let pickerItem = NSMenuItem(title: "WebPicker", action: #selector(AppDelegate.toggleWebPicker), keyEquivalent: "")
    pickerItem.state = del.webPickerSidebarView != nil ? .on : .off
    pickerItem.target = del
    menu.addItem(pickerItem)

    let sshItem = NSMenuItem(title: "SSH", action: #selector(AppDelegate.toggleSSHManager), keyEquivalent: "")
    sshItem.state = del.sshManagerView != nil ? .on : .off
    sshItem.target = del
    menu.addItem(sshItem)

    NSMenu.popUpContextMenu(menu, with: event, for: view)
}

// MARK: - Git Panel

enum GitPanelPosition { case none, right, bottom }

class GitPanelDividerView: NSView {
    var isVertical = true
    var onDrag: ((CGFloat) -> Void)?
    private var dragStart: CGFloat = 0
    private var isHovered = false
    private var isDragging = false

    // The visible 2px strip is drawn by a sublayer; the view frame is expanded
    // by `grab` pixels on each side so the full grab zone IS the frame — this
    // ensures AppKit's frame pre-check never prevents hitTest from being called.
    static let grab: CGFloat      = 5    // extra pixels on each side
    static let stripThick: CGFloat = 2   // visual strip width

    static let normalColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
    static let hoverColor  = NSColor(calibratedRed: 0.4, green: 0.65, blue: 1.0, alpha: 0.5).cgColor
    static let dragColor   = NSColor(calibratedRed: 0.4, green: 0.65, blue: 1.0, alpha: 0.75).cgColor

    private let stripLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupStrip()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupStrip()
    }
    private func setupStrip() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        stripLayer.backgroundColor = Self.normalColor
        layer?.addSublayer(stripLayer)
        positionStripLayer()
    }

    private func positionStripLayer() {
        let g = Self.grab
        let t = Self.stripThick
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Center the visual 2px strip inside the (expanded) bounds
        if isVertical {
            stripLayer.frame = CGRect(x: g, y: 0, width: t, height: bounds.height)
        } else {
            stripLayer.frame = CGRect(x: 0, y: g, width: bounds.width, height: t)
        }
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        positionStripLayer()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Animate the strip color (CATransaction, no NSAnimationContext needed)
    private func setStripColor(_ color: CGColor, animated: Bool = true) {
        if animated {
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.fromValue = stripLayer.presentation()?.backgroundColor ?? stripLayer.backgroundColor
            anim.toValue   = color
            anim.duration  = 0.15
            stripLayer.add(anim, forKey: "bgColor")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stripLayer.backgroundColor = color
        CATransaction.commit()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isVertical ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = isVertical ? event.locationInWindow.x : event.locationInWindow.y
        isDragging = true
        setStripColor(Self.dragColor, animated: false)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = isVertical ? event.locationInWindow.x : event.locationInWindow.y
        let delta = current - dragStart
        dragStart = current
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        setStripColor(isHovered ? Self.hoverColor : Self.normalColor)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if !isDragging { setStripColor(Self.hoverColor) }
        (isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging { setStripColor(Self.normalColor) }
        NSCursor.pop()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // The frame already covers the full grab zone, so track the whole bounds
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        (isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
    }
}

// MARK: - Marquee Label (single-line, scrolls on hover)
class MarqueeLabel: NSView {
    private let textLabel = NSTextField(labelWithString: "")
    private var scrollTimer: Timer?
    private var isHovering = false
    private var pauseCounter = 0
    private var textWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        textLabel.isEditable = false
        textLabel.isBordered = false
        textLabel.drawsBackground = false
        textLabel.lineBreakMode = .byClipping
        textLabel.maximumNumberOfLines = 1
        textLabel.cell?.truncatesLastVisibleLine = false
        textLabel.cell?.wraps = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        // Only pin top/bottom — NO leading/trailing constraints
        // We control x position via frame directly
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    var attributedText: NSAttributedString {
        get { textLabel.attributedStringValue }
        set {
            textLabel.attributedStringValue = newValue
            // Calculate actual text width from attributed string
            let size = newValue.size()
            textWidth = ceil(size.width) + 4
            textLabel.frame = NSRect(x: 0, y: 0, width: textWidth, height: bounds.height)
        }
    }

    override func layout() {
        super.layout()
        // Keep text label at full width, positioned at x=0 unless scrolling
        if !isHovering {
            textLabel.frame = NSRect(x: 0, y: 0, width: max(textWidth, bounds.width), height: bounds.height)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        let overflow = textWidth - bounds.width
        guard overflow > 5 else { return }
        isHovering = true
        pauseCounter = 60 // brief pause before starting

        var offset: CGFloat = 0
        let speed: CGFloat = 30.0
        let step: CGFloat = speed / 60.0
        var dir: CGFloat = -1

        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isHovering else { timer.invalidate(); return }
            if self.pauseCounter > 0 { self.pauseCounter -= 1; return }

            offset += step * dir
            if offset < -overflow {
                offset = -overflow; dir = 1; self.pauseCounter = 90
            } else if offset > 0 {
                offset = 0; dir = -1; self.pauseCounter = 60
            }
            var f = self.textLabel.frame
            f.origin.x = offset
            self.textLabel.frame = f
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        // Animate back to start
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            self.textLabel.animator().frame = NSRect(x: 0, y: 0, width: max(self.textWidth, self.bounds.width), height: self.bounds.height)
        }
    }

    deinit { scrollTimer?.invalidate() }
}

// MARK: - Clickable File Row (Phase 3)

class ClickableFileRow: NSView {
    let marqueeLabel = MarqueeLabel()
    var filePath: String = ""
    var statusX: Character = " "
    var statusY: Character = " "
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        marqueeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(marqueeLabel)
        NSLayoutConstraint.activate([
            marqueeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            marqueeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            marqueeLabel.topAnchor.constraint(equalTo: topAnchor),
            marqueeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

class GitPanelView: NSView {

    // MARK: - State & Data

    private var lastCwd = ""
    private var refreshTimer: Timer?
    private var isRefreshing = false
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

    // MARK: - Move callbacks (multi-panel sidebar)
    var onMoveUp:   (() -> Void)?
    var onMoveDown: (() -> Void)?
    private let moveUpBtn   = NSButton()
    private let moveDownBtn = NSButton()

    func setMoveButtonsEnabled(up: Bool, down: Bool) {
        let visible = up || down
        moveUpBtn.isHidden   = !visible
        moveDownBtn.isHidden = !visible
        moveUpBtn.isEnabled   = up
        moveDownBtn.isEnabled = down
        moveUpBtn.alphaValue   = up   ? 1.0 : 0.35
        moveDownBtn.alphaValue = down ? 1.0 : 0.35
    }

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

    // MARK: - UI: Language-refreshable refs (locally created in build functions)

    private var noRepoTitleLabel: NSTextField!
    private var noRepoSubLabel: NSTextField!
    private var noRepoInitBtn: NSButton!
    private var commitHeaderLabel: NSTextField!
    private var githubAuthTitleLabel: NSTextField!
    private var newRepoTitleLabel: NSTextField!
    private var newRepoVisLabel: NSTextField!
    private var newRepoCancelBtn: NSButton!

    // MARK: - Init

    override func layout() {
        super.layout()
        let bw: CGFloat = 18
        let y = bounds.height - 28
        moveUpBtn.frame   = NSRect(x: bounds.width - bw*2 - 10, y: y + 4, width: bw, height: bw)
        moveDownBtn.frame = NSRect(x: bounds.width - bw   -  4, y: y + 4, width: bw, height: bw)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.85).cgColor
        setupScrollAndStack()

        for (btn, symbol, sel) in [(moveUpBtn, "▲", #selector(moveUpTapped)),
                                   (moveDownBtn, "▼", #selector(moveDownTapped))] {
            btn.title = symbol
            btn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            btn.isBordered = false
            btn.contentTintColor = NSColor(calibratedWhite: 0.55, alpha: 1)
            btn.target = self; btn.action = sel
            btn.isHidden = true
            addSubview(btn)
        }

        buildHeaderCard()
        buildNoRepoCard()
        buildFilesCard()
        buildCommitCard()
        buildGithubCard()
        buildNewRepoOverlay()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage),
                                               name: .appLanguageChanged, object: nil)
        if github.isAuthenticated {
            github.fetchUser { [weak self] _ in
                DispatchQueue.main.async { self?.updateGithubCard() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func moveUpTapped()   { onMoveUp?() }
    @objc private func moveDownTapped() { onMoveDown?() }

    // MARK: - Language Refresh

    @objc private func refreshLanguage() {
        // noRepoCard
        noRepoTitleLabel.stringValue = Loc.noProjectYet
        noRepoSubLabel.stringValue = Loc.clickToStartTracking
        noRepoInitBtn.title = Loc.startTracking
        // filesCard header
        filesHeaderLabel.attributedStringValue = NSAttributedString(string: Loc.changedFiles, attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
            .kern: 1.5
        ])
        // commitCard
        commitHeaderLabel.attributedStringValue = NSAttributedString(string: Loc.whatChanged, attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
            .kern: 1.5
        ])
        (commitField.cell as? NSTextFieldCell)?.placeholderString = Loc.commitPlaceholder
        saveBtn.title = Loc.save
        // githubCard - auth
        githubAuthTitleLabel.stringValue = Loc.notConnectedGH
        tokenField.placeholderString = Loc.pasteToken
        tokenSaveBtn.title = Loc.connect
        tokenLinkBtn.title = Loc.createToken
        // githubCard - connected
        uploadBtn.title = Loc.uploadGH
        updateBtn.title = Loc.updateGH
        disconnectBtn.title = Loc.logout
        // newRepoOverlay
        newRepoTitleLabel.stringValue = Loc.createProject
        repoNameField.placeholderString = Loc.projectNamePlaceholder
        newRepoVisLabel.stringValue = Loc.visibility
        repoPublicBtn.title = Loc.public_
        repoPrivateBtn.title = Loc.private_
        repoCreateBtn.title = Loc.createAndUpload
        newRepoCancelBtn.title = Loc.cancel
        // statusLabel — re-apply current state
        if !isGitRepo {
            statusLabel.stringValue = Loc.noTracking
        } else if fileEntries.isEmpty {
            statusLabel.stringValue = Loc.allSaved
        } else {
            statusLabel.stringValue = Loc.filesChanged(fileEntries.count)
        }
    }

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

        noRepoTitleLabel = makeLabel(Loc.noProjectYet, size: 12, weight: .medium,
                                     color: NSColor(calibratedWhite: 0.6, alpha: 1.0))
        noRepoSubLabel = makeLabel(Loc.clickToStartTracking, size: 10.5, weight: .regular,
                                   color: NSColor(calibratedWhite: 0.4, alpha: 1.0))
        noRepoInitBtn = makeBtn(Loc.startTracking, color: NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0),
                                target: self, action: #selector(initRepoClicked))

        _ = addToCard(noRepoCard, views: [noRepoTitleLabel, noRepoSubLabel, noRepoInitBtn], padding: 14, spacing: 8)

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
        filesHeaderLabel.attributedStringValue = NSAttributedString(string: Loc.changedFiles, attributes: [
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

        commitHeaderLabel = NSTextField(labelWithString: "")
        commitHeaderLabel.attributedStringValue = NSAttributedString(string: Loc.whatChanged, attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
            .kern: 1.5
        ])

        let commitCell = VertCenteredTextFieldCell(textCell: "")
        commitCell.isEditable = true
        commitCell.isBezeled = false
        commitCell.focusRingType = .none
        commitCell.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        commitCell.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        commitCell.drawsBackground = false
        commitCell.placeholderString = Loc.commitPlaceholder
        commitCell.usesSingleLineMode = true
        commitCell.wraps = false
        commitCell.leftPad = 10
        commitField.cell = commitCell
        commitField.isBordered = false
        commitField.focusRingType = .none
        commitField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
        commitField.wantsLayer = true
        commitField.layer?.cornerRadius = 6
        commitField.translatesAutoresizingMaskIntoConstraints = false
        commitField.target = self
        commitField.action = #selector(saveClicked)

        saveBtn.title = Loc.save
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

        let inner = NSStackView(views: [commitHeaderLabel, commitField, saveBtn, feedbackLabel])
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
        githubAuthTitleLabel = makeLabel(Loc.notConnectedGH, size: 11, weight: .medium,
                                         color: NSColor(calibratedWhite: 0.55, alpha: 1.0))

        tokenField.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        tokenField.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        tokenField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
        tokenField.isBordered = false
        tokenField.focusRingType = .none
        tokenField.bezelStyle = .roundedBezel
        tokenField.placeholderString = Loc.pasteToken
        tokenField.translatesAutoresizingMaskIntoConstraints = false

        tokenSaveBtn.title = Loc.connect
        tokenSaveBtn.bezelStyle = .inline
        tokenSaveBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        tokenSaveBtn.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
        tokenSaveBtn.translatesAutoresizingMaskIntoConstraints = false
        tokenSaveBtn.target = self
        tokenSaveBtn.action = #selector(saveTokenClicked)

        tokenLinkBtn.title = Loc.createToken
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
        githubAuthStack.addArrangedSubview(githubAuthTitleLabel)
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

        uploadBtn.title = Loc.uploadGH
        uploadBtn.bezelStyle = .rounded
        uploadBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        uploadBtn.contentTintColor = NSColor(calibratedRed: 0.5, green: 0.78, blue: 1.0, alpha: 1.0)
        uploadBtn.wantsLayer = true
        uploadBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.5, green: 0.78, blue: 1.0, alpha: 0.1).cgColor
        uploadBtn.layer?.cornerRadius = 6
        uploadBtn.translatesAutoresizingMaskIntoConstraints = false
        uploadBtn.target = self
        uploadBtn.action = #selector(uploadClicked)

        updateBtn.title = Loc.updateGH
        updateBtn.bezelStyle = .rounded
        updateBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        updateBtn.contentTintColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.35, alpha: 1.0)
        updateBtn.wantsLayer = true
        updateBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.35, alpha: 0.1).cgColor
        updateBtn.layer?.cornerRadius = 6
        updateBtn.translatesAutoresizingMaskIntoConstraints = false
        updateBtn.target = self
        updateBtn.action = #selector(updateClicked)

        disconnectBtn.title = Loc.logout
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

        newRepoTitleLabel = makeLabel(Loc.createProject, size: 13, weight: .semibold,
                                      color: NSColor(calibratedWhite: 0.85, alpha: 1.0))

        repoNameField.isEditable = true
        repoNameField.isBordered = false
        repoNameField.focusRingType = .none
        repoNameField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        repoNameField.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        repoNameField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.07)
        repoNameField.placeholderString = Loc.projectNamePlaceholder
        repoNameField.wantsLayer = true
        repoNameField.layer?.cornerRadius = 6
        repoNameField.translatesAutoresizingMaskIntoConstraints = false

        newRepoVisLabel = makeLabel(Loc.visibility, size: 10.5, weight: .regular,
                                    color: NSColor(calibratedWhite: 0.5, alpha: 1.0))

        repoPublicBtn.setButtonType(.radio)
        repoPublicBtn.title = Loc.public_
        repoPublicBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        repoPublicBtn.contentTintColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        repoPublicBtn.translatesAutoresizingMaskIntoConstraints = false
        repoPublicBtn.target = self
        repoPublicBtn.action = #selector(repoVisibilityChanged(_:))
        repoPublicBtn.state = .off

        repoPrivateBtn.setButtonType(.radio)
        repoPrivateBtn.title = Loc.private_
        repoPrivateBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        repoPrivateBtn.contentTintColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        repoPrivateBtn.translatesAutoresizingMaskIntoConstraints = false
        repoPrivateBtn.target = self
        repoPrivateBtn.action = #selector(repoVisibilityChanged(_:))
        repoPrivateBtn.state = .on

        let visRow = NSStackView(views: [newRepoVisLabel, repoPublicBtn, repoPrivateBtn])
        visRow.orientation = .horizontal
        visRow.spacing = 12
        visRow.alignment = .centerY
        visRow.translatesAutoresizingMaskIntoConstraints = false

        repoCreateBtn.title = Loc.createAndUpload
        repoCreateBtn.bezelStyle = .rounded
        repoCreateBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        repoCreateBtn.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
        repoCreateBtn.wantsLayer = true
        repoCreateBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 0.12).cgColor
        repoCreateBtn.layer?.cornerRadius = 6
        repoCreateBtn.translatesAutoresizingMaskIntoConstraints = false
        repoCreateBtn.target = self
        repoCreateBtn.action = #selector(createRepoClicked)

        newRepoCancelBtn = makeBtn(Loc.cancel, color: NSColor(calibratedWhite: 0.45, alpha: 1.0),
                                   target: self, action: #selector(cancelNewRepo))

        let innerStack = NSStackView(views: [newRepoTitleLabel, repoNameField, visRow, repoCreateBtn, newRepoCancelBtn])
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 10
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        newRepoOverlay.addSubview(innerStack)

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
            newRepoCancelBtn.widthAnchor.constraint(equalTo: innerStack.widthAnchor),
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
        guard !isRefreshing else { return }
        isRefreshing = true

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
                        (tag, tagColor, fileColor) = ("DELETED", NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 0.8), NSColor(calibratedRed: 0.8, green: 0.5, blue: 0.5, alpha: 0.8))
                    } else if x == "U" || y == "U" {
                        (tag, tagColor, fileColor) = ("KONFLIKT", NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0), NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.5, alpha: 1.0))
                    } else if "MADRC".contains(x) && x != " " && "MD".contains(y) && y != " " {
                        (tag, tagColor, fileColor) = ("BEREIT+MOD", NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.55, alpha: 1.0), NSColor(calibratedRed: 0.9, green: 0.75, blue: 0.3, alpha: 1.0))
                    } else if "MADRC".contains(x) && x != " " {
                        (tag, tagColor, fileColor) = ("BEREIT", NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.45, alpha: 1.0), NSColor(calibratedRed: 0.5, green: 0.8, blue: 0.55, alpha: 1.0))
                    } else {
                        (tag, tagColor, fileColor) = ("MODIFIED", NSColor(calibratedRed: 0.95, green: 0.7, blue: 0.25, alpha: 1.0), NSColor(calibratedRed: 0.85, green: 0.7, blue: 0.4, alpha: 1.0))
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
                self.isRefreshing = false
                self.isGitRepo = isRepo
                self.currentBranch = branch
                self.ahead = aheadCount
                self.behind = behindCount
                self.hasRemote = hasRemote
                self.fileEntries = entries

                self.updateLayout(projectName: projectName)
                self.refreshGithubStatus(cwd: cwd)

                // Intervall: 3s in Repos, 30s außerhalb
                let newInterval: TimeInterval = isRepo ? 3.0 : 30.0
                if let t = self.refreshTimer, abs(t.timeInterval - newInterval) > 0.1 {
                    self.refreshTimer?.invalidate()
                    self.refreshTimer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
                        self?.refresh()
                    }
                }
            }
        }
    }

    // MARK: - Layout Update

    private func updateLayout(projectName: String) {
        projectLabel.stringValue = projectName
        if !currentBranch.isEmpty {
            branchBadge.stringValue = " \(currentBranch) "
            branchBadge.isHidden = false
        } else {
            branchBadge.isHidden = true
        }

        if !isGitRepo {
            statusLabel.stringValue = Loc.noTracking
            statusLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1.0)
        } else if fileEntries.isEmpty {
            statusLabel.stringValue = Loc.allSaved
            statusLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.5, alpha: 1.0)
        } else {
            statusLabel.stringValue = Loc.filesChanged(fileEntries.count)
            statusLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.3, alpha: 1.0)
        }

        noRepoCard.isHidden = isGitRepo
        filesCard.isHidden = !isGitRepo || fileEntries.isEmpty
        if isGitRepo { rebuildFilesStack() }
        commitCard.isHidden = !isGitRepo
        githubCard.isHidden = !isGitRepo
        updateGithubCard()
    }

    // MARK: - Files Stack

    private func rebuildFilesStack() {
        let key = fileEntries.map { $0.path }.joined(separator: "\n")
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
            let diffOut = self.runGit(args, cwd: self.lastCwd) ?? "No diff available"
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
            let user = github.username ?? Loc.verbunden
            githubUserLabel.stringValue = "🔗  @\(user)"
        }
    }

    private func refreshGithubStatus(cwd: String) {
        guard github.isAuthenticated, isGitRepo, hasRemote else {
            if isGitRepo && !hasRemote && github.isAuthenticated {
                githubSyncLabel.stringValue = Loc.notYetUploaded
                githubSyncLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
                uploadBtn.isHidden = false
                updateBtn.isHidden = true
            }
            return
        }

        if ahead > 0 && behind > 0 {
            githubSyncLabel.stringValue = Loc.aheadBehind(ahead, behind)
            githubSyncLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.7, blue: 0.3, alpha: 1.0)
        } else if ahead > 0 {
            githubSyncLabel.stringValue = Loc.aheadOnly(ahead)
            githubSyncLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.35, alpha: 1.0)
        } else if behind > 0 {
            githubSyncLabel.stringValue = Loc.behindOnly(behind)
            githubSyncLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
        } else {
            githubSyncLabel.stringValue = Loc.upToDate
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
                    self.showFeedback("Error: \(result.output)", success: false)
                }
            }
        }
    }

    // MARK: - Actions: Save (Stage All + Commit)

    @objc private func saveClicked() {
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else {
            showFeedback(Loc.describeChanges, success: false)
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
                    self.showFeedback("Error: \(stage.output)", success: false)
                    self.commitField.isEnabled = true
                    self.saveBtn.isEnabled = true
                }
                return
            }
            let commit = self.runGitAction(["commit", "-m", msg], cwd: cwd)
            DispatchQueue.main.async {
                self.commitField.isEnabled = true
                self.saveBtn.isEnabled = true
                self.showFeedback(commit.success ? "\(Loc.savedMsg): \(msg)" : "Error: \(commit.output)", success: commit.success)
                self.refresh()
            }
        }
    }

    // MARK: - Actions: Upload (Push)

    @objc private func uploadClicked() {
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
                self.showFeedback(result.success ? Loc.uploaded : "Error: \(result.output)", success: result.success)
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
                self.showFeedback(result.success ? Loc.updated : "Error: \(result.output)", success: result.success)
                self.github.cache.lastFetch = .distantPast
                self.refresh()
            }
        }
    }

    // MARK: - Actions: GitHub Auth

    @objc private func saveTokenClicked() {
        let value = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        tokenSaveBtn.title = Loc.checking
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
                self.showFeedback(Loc.invalidToken, success: false)
            }
            self.tokenSaveBtn.title = Loc.connect
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
        name = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        repoCreateBtn.isEnabled = false
        repoCreateBtn.title = Loc.creating

        let cwd = lastCwd
        let branch = currentBranch.isEmpty ? "main" : currentBranch
        let isPrivate = repoIsPrivate

        github.createRepo(name: name, isPrivate: isPrivate) { [weak self] success, cloneURLOrError in
            guard let self = self else { return }
            if success, let cloneURL = cloneURLOrError {
                DispatchQueue.global(qos: .userInitiated).async {
                    let remoteAdd = self.runGitAction(["remote", "add", "origin", cloneURL], cwd: cwd)
                    if !remoteAdd.success {
                        // remote may already exist — try updating it instead
                        _ = self.runGitAction(["remote", "set-url", "origin", cloneURL], cwd: cwd)
                    }
                    let push = self.runGitAction(["push", "-u", "origin", branch], cwd: cwd)
                    DispatchQueue.main.async {
                        self.repoCreateBtn.isEnabled = true
                        self.repoCreateBtn.title = Loc.createAndUpload
                        self.cancelNewRepo()
                        self.showFeedback(push.success ? Loc.projectCreated : "Repo created, push failed: \(push.output)", success: push.success)
                        self.github.cache.lastFetch = .distantPast
                        self.refresh()
                    }
                }
            } else {
                self.repoCreateBtn.isEnabled = true
                self.repoCreateBtn.title = "✔  Create & Upload"
                self.showFeedback("Error: \(cloneURLOrError ?? "Unknown error")", success: false)
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        feedbackTimer?.invalidate()
    }

    override func rightMouseDown(with event: NSEvent) {
        showSidebarContextMenu(in: self, event: event)
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

// MARK: - Chrome CDP Client

class ChromeCDPClient {
    static var debugPort: Int {
        UserDefaults.standard.integer(forKey: "webPickerBrowser") == 1 ? 9221 : 9222
    }
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var messageId = 0
    private var pendingCallbacks: [Int: ([String: Any]?) -> Void] = [:]
    var onDisconnected: (() -> Void)?

    /// The specific Chrome process listening on our debug port (found via lsof).
    /// Used to activate the CORRECT Chrome instance (not the user's regular Chrome).
    private(set) var managedApp: NSRunningApplication?

    /// Finds the exact Chrome NSRunningApplication that is running with our debug port.
    /// Uses `ps` to find the Chrome process that was launched with --remote-debugging-port=PORT.
    /// Falls back to single-instance detection if ps fails.
    func findManagedApp() {
        let port = Self.debugPort
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Method 1: ps — find Chrome process started with our exact debug port arg
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c",
                "ps axww -o pid=,args= | grep -F -- '--remote-debugging-port=\(port)' | grep -v grep | awk '{print $1}' | head -1"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let pid = pid_t(output), pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                DispatchQueue.main.async { self?.managedApp = app }
                return
            }
            // Method 2: Fallback — if exactly one Chrome instance is running it must be ours
            DispatchQueue.main.async { [weak self] in
                let bundleIds = ["com.google.Chrome", "org.chromium.Chromium", "com.google.Chrome.canary"]
                let allChromes = bundleIds.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
                if allChromes.count == 1 { self?.managedApp = allChromes[0] }
            }
        }
    }

    /// Focuses a specific tab in Chrome via the HTTP /json/activate endpoint.
    /// This ensures Chrome shows the correct tab regardless of which tab was last active.
    func activateTarget(targetId: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/activate/\(targetId)") else {
            completion(); return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url)) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }

    /// Prüft ob Chrome mit --remote-debugging-port läuft (2s Timeout)
    func isAvailable(completion: @escaping (Bool) -> Void) {
        let urlStr = "http://localhost:\(Self.debugPort)/json"
        guard let url = URL(string: urlStr) else { completion(false); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        URLSession.shared.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = code == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    /// Startet Chrome mit --remote-debugging-port, dann polling bis CDP bereit
    func launchChrome(onStatus: ((String) -> Void)? = nil, completion: @escaping () -> Void) {
        openChrome()
        pollUntilAvailable(attempts: 14, interval: 0.7, onStatus: onStatus, completion: completion)
    }

    /// Beendet laufendes Chrome und startet es neu mit --remote-debugging-port
    func forceRelaunchChrome(onStatus: ((String) -> Void)? = nil, completion: @escaping () -> Void) {
        for name in ["Google Chrome", "Chromium", "Google Chrome Canary"] {
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            kill.arguments = [name]
            kill.standardOutput = FileHandle.nullDevice
            kill.standardError  = FileHandle.nullDevice
            _ = try? kill.run()
        }
        onStatus?("Stopping Chrome...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self = self else { return }
            self.openChrome()
            self.pollUntilAvailable(attempts: 16, interval: 0.8, onStatus: onStatus, completion: completion)
        }
    }

    /// Pollt isAvailable bis CDP antwortet oder Versuche erschöpft
    private func pollUntilAvailable(attempts: Int, interval: TimeInterval,
                                     onStatus: ((String) -> Void)?, completion: @escaping () -> Void) {
        if attempts <= 0 { completion(); return }
        isAvailable { [weak self] available in
            guard let self = self else { return }
            if available {
                completion()
            } else {
                let dots = String(repeating: ".", count: 4 - (attempts % 4))
                onStatus?("Waiting for Chrome\(dots)")
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    self.pollUntilAvailable(attempts: attempts - 1, interval: interval,
                                             onStatus: onStatus, completion: completion)
                }
            }
        }
    }

    private func openChrome() {
        // Key insight (same approach as Puppeteer/Playwright):
        // Chrome ignores --remote-debugging-port when another instance already runs in the SAME profile.
        // Solution: --user-data-dir points to a fresh tmp dir → forces a truly new instance with its own port.
        let tmpDir = "/tmp/qt-chrome-debug-\(Self.debugPort)"
        let candidates = [
            "/Applications/Google Chrome.app",
            "/Applications/Chromium.app",
            "/Applications/Google Chrome Canary.app",
        ]
        guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-na", app, "--args",
                          "--user-data-dir=\(tmpDir)",
                          "--remote-debugging-port=\(Self.debugPort)",
                          "--no-first-run",
                          "--no-default-browser-check",
                          "--disable-session-restore"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
    }

    /// Gibt die WebSocket-URL des ersten aktiven Page-Tabs zurück
    func getActiveTabWS(preferredTargetId: String? = nil, completion: @escaping (String?) -> Void) {
        let urlStr = "http://localhost:\(Self.debugPort)/json/list"
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let tabs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let pages = tabs.filter {
                guard ($0["type"] as? String) == "page",
                      let tabURL = $0["url"] as? String else { return false }
                // Skip Chrome-internal pages — JS injection doesn't work there
                return tabURL.hasPrefix("http://") || tabURL.hasPrefix("https://") || tabURL == "about:blank"
            }
            // Prefer the previously connected tab if it still exists
            if let preferred = preferredTargetId,
               let tab = pages.first(where: { ($0["id"] as? String) == preferred }),
               let wsURL = tab["webSocketDebuggerUrl"] as? String {
                DispatchQueue.main.async { completion(wsURL) }
                return
            }
            // Fall back to first available page tab
            if let tab = pages.first, let wsURL = tab["webSocketDebuggerUrl"] as? String {
                DispatchQueue.main.async { completion(wsURL) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
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
        // Verify connectivity with a ping — don't optimistically assume success
        var done = false
        let task = webSocketTask
        task?.sendPing { [weak self] error in
            guard !done else { return }; done = true
            DispatchQueue.main.async {
                if error == nil { completion(true) }
                else { self?.disconnect(); completion(false) }
            }
        }
        // 3s hard timeout in case Chrome doesn't respond to ping
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard !done else { return }; done = true
            self?.disconnect(); completion(false)
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { [weak self] in self?.onDisconnected?() }
                return
            case .success(let msg):
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? Int {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              let cb = self.pendingCallbacks.removeValue(forKey: id) else { return }
                        cb(json["result"] as? [String: Any])
                    }
                }
                self.receiveLoop()
            }
        }
    }

    /// Führt JavaScript im aktiven Tab aus (Runtime.evaluate)
    func evaluate(_ expr: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let webSocketTask = webSocketTask else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        messageId += 1
        let id = messageId
        let msg: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": ["expression": expr, "returnByValue": true]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        pendingCallbacks[id] = completion
        webSocketTask.send(.string(text)) { [weak self] error in
            if error != nil {
                DispatchQueue.main.async {
                    self?.pendingCallbacks.removeValue(forKey: id)
                    completion(nil)
                }
            }
        }
    }

    /// Generic CDP command with callback
    func cdpCommand(_ method: String, params: [String: Any] = [:], completion: @escaping ([String: Any]?) -> Void) {
        guard let webSocketTask = webSocketTask else { DispatchQueue.main.async { completion(nil) }; return }
        messageId += 1
        let id = messageId
        let msg: [String: Any] = ["id": id, "method": method, "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { DispatchQueue.main.async { completion(nil) }; return }
        pendingCallbacks[id] = completion
        webSocketTask.send(.string(text)) { [weak self] error in
            if error != nil { DispatchQueue.main.async { self?.pendingCallbacks.removeValue(forKey: id); completion(nil) } }
        }
    }

    /// Sets Chrome window size and position via Browser.setWindowBounds
    func setChromeWindowBounds(width: Int, height: Int, left: Int = 0, top: Int = 0, targetId: String) {
        cdpCommand("Browser.getWindowForTarget", params: ["targetId": targetId]) { [weak self] result in
            guard let windowId = result?["windowId"] as? Int else { return }
            self?.cdpCommand("Browser.setWindowBounds", params: [
                "windowId": windowId,
                "bounds": ["width": width, "height": height, "left": left, "top": top]
            ]) { _ in }
        }
    }

    /// Navigates the connected tab to a URL (Page.navigate)
    func navigate(to rawURL: String) {
        var urlStr = rawURL.trimmingCharacters(in: .whitespaces)
        if !urlStr.isEmpty && !urlStr.contains("://") {
            let isLocal = urlStr.hasPrefix("localhost") || urlStr.hasPrefix("127.0.0.1") || urlStr.hasPrefix("0.0.0.0")
            urlStr = (isLocal ? "http://" : "https://") + urlStr
        }
        guard !urlStr.isEmpty, let _ = URL(string: urlStr) else { return }
        cdpCommand("Page.navigate", params: ["url": urlStr]) { _ in }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        wsSession = nil
        pendingCallbacks.removeAll()
        messageId = 0
    }

    /// Creates a new blank tab via /json/new (works even when Chrome has no open windows)
    func createBlankTab(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/new?about:blank") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.timeoutInterval = 3.0
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let tab = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let wsURL = tab["webSocketDebuggerUrl"] as? String else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            DispatchQueue.main.async { completion(wsURL) }
        }.resume()
    }

    /// Closes a Chrome tab via /json/close/{targetId}
    func closeTab(targetId: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/close/\(targetId)") else {
            DispatchQueue.main.async { completion() }; return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }

    /// Returns hostname of the currently active page tab (e.g. "github.com")
    func getTabHostname(targetId: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://localhost:\(Self.debugPort)/json/list") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var listReq = URLRequest(url: url)
        listReq.timeoutInterval = 3.0
        URLSession.shared.dataTask(with: listReq) { data, _, _ in
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
}
// MARK: - SSH Manager

struct SSHProfile: Codable {
    var id: String = UUID().uuidString
    var label: String
    var user: String
    var host: String
    var port: Int = 22
    var keyFile: String = ""

    var connectCommand: String {
        var cmd = "ssh \(user)@\(host)"
        if port != 22 { cmd += " -p \(port)" }
        if !keyFile.isEmpty {
            let expanded = keyFile.replacingOccurrences(of: "~", with: NSHomeDirectory())
            cmd += " -i \(expanded)"
        }
        return cmd
    }
}

// NSScrollView contentView with flipped coords so documentView starts at top
private class FlippedClipView: NSClipView {
    override var isFlipped: Bool { return true }
}

class SSHManagerView: NSView {
    var onConnect: ((SSHProfile) -> Void)?
    var onClose:   (() -> Void)?
    var onMoveUp:  (() -> Void)?
    var onMoveDown: (() -> Void)?
    private var moveUpBtn: NSButton!
    private var moveDownBtn: NSButton!

    func setMoveButtonsEnabled(up: Bool, down: Bool) {
        let visible = up || down
        moveUpBtn?.isHidden   = !visible
        moveDownBtn?.isHidden = !visible
        moveUpBtn?.isEnabled   = up;   moveUpBtn?.alphaValue   = up   ? 1.0 : 0.35
        moveDownBtn?.isEnabled = down; moveDownBtn?.alphaValue = down ? 1.0 : 0.35
    }

    private static let accent = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.50, alpha: 1.0)
    private static let formH: CGFloat = 114

    private var profiles: [SSHProfile] = []
    private let listStack  = NSStackView()
    private let scrollView = NSScrollView()
    // Collapsible form wrapper — clips to animated height
    private let formWrap  = NSView()
    private let formInner = NSView()
    private var nameField = NSTextField()   // optional label
    private var connField = NSTextField()   // user@host[:port]
    private var keyField  = NSTextField()   // optional key file
    private var formTitleLbl = NSTextField(labelWithString: "")
    private var formHeightConstraint: NSLayoutConstraint!
    private var formVisible  = false
    private var editingIndex: Int? = nil
    private var addBtn: NSButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
        loadProfiles()
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshSSHLanguage),
                                               name: .appLanguageChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        // ── Header ──
        let titleLabel = NSTextField(labelWithString: "⌗  SSH")
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = Self.accent
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let closeBtn = NSButton()
        closeBtn.title = "✕"
        closeBtn.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        closeBtn.isBordered = false
        closeBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        closeBtn.target = self
        closeBtn.action = #selector(closePanel)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeBtn)

        moveDownBtn = NSButton()
        moveDownBtn.title = "▼"
        moveDownBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        moveDownBtn.isBordered = false
        moveDownBtn.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        moveDownBtn.target = self; moveDownBtn.action = #selector(moveDownTapped)
        moveDownBtn.isHidden = true
        moveDownBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(moveDownBtn)

        moveUpBtn = NSButton()
        moveUpBtn.title = "▲"
        moveUpBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        moveUpBtn.isBordered = false
        moveUpBtn.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        moveUpBtn.target = self; moveUpBtn.action = #selector(moveUpTapped)
        moveUpBtn.isHidden = true
        moveUpBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(moveUpBtn)

        addBtn = NSButton()
        addBtn.title = "+"
        addBtn.font = NSFont.systemFont(ofSize: 14, weight: .light)
        addBtn.isBordered = false
        addBtn.contentTintColor = Self.accent
        addBtn.target = self
        addBtn.action = #selector(toggleForm)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addBtn)

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.07).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        // ── Collapsible form (at TOP, slides down) ──
        formWrap.wantsLayer = true
        formWrap.layer?.masksToBounds = true
        formWrap.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formWrap)

        formInner.wantsLayer = true
        formInner.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor
        formInner.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.07).cgColor
        formInner.layer?.borderWidth = 1
        formInner.translatesAutoresizingMaskIntoConstraints = false
        formWrap.addSubview(formInner)

        formTitleLbl.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        formTitleLbl.textColor = Self.accent
        formTitleLbl.stringValue = Loc.sshNewConn
        formTitleLbl.translatesAutoresizingMaskIntoConstraints = false
        formInner.addSubview(formTitleLbl)

        func makeField(_ placeholder: String) -> NSTextField {
            let f = NSTextField()
            f.placeholderString = placeholder
            f.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            f.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
            f.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08)
            f.isBordered = false
            f.focusRingType = .none
            f.wantsLayer = true
            f.layer?.cornerRadius = 3
            f.translatesAutoresizingMaskIntoConstraints = false
            return f
        }

        nameField = makeField(Loc.sshNamePh)
        connField = makeField(Loc.sshConnPh)
        keyField  = makeField(Loc.sshKeyPh)

        let saveBtn = NSButton()
        saveBtn.title = Loc.save.components(separatedBy: "  ").last ?? Loc.save
        saveBtn.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        saveBtn.isBordered = false
        saveBtn.contentTintColor = Self.accent
        saveBtn.target = self
        saveBtn.action = #selector(saveProfile)
        saveBtn.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = NSButton()
        cancelBtn.title = Loc.cancel
        cancelBtn.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        cancelBtn.isBordered = false
        cancelBtn.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelForm)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        [nameField, connField, keyField, saveBtn, cancelBtn].forEach { formInner.addSubview($0) }

        // Tab key navigation through form fields
        nameField.nextKeyView = connField
        connField.nextKeyView = keyField
        keyField.nextKeyView  = nameField

        // ── Scroll list (below form) ──
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // Use flipped clip view so list content starts at top, not bottom
        let flippedClip = FlippedClipView()
        flippedClip.drawsBackground = false
        scrollView.contentView = flippedClip
        addSubview(scrollView)

        listStack.orientation = .vertical
        listStack.spacing = 1
        listStack.alignment = .leading
        listStack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        listStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = listStack
        listStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
        listStack.topAnchor.constraint(equalTo: flippedClip.topAnchor).isActive = true

        formHeightConstraint = formWrap.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 22),

            moveDownBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -2),
            moveDownBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moveDownBtn.widthAnchor.constraint(equalToConstant: 18),

            moveUpBtn.trailingAnchor.constraint(equalTo: moveDownBtn.leadingAnchor, constant: -2),
            moveUpBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moveUpBtn.widthAnchor.constraint(equalToConstant: 18),

            addBtn.trailingAnchor.constraint(equalTo: moveUpBtn.leadingAnchor, constant: -4),
            addBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 22),

            sep.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            formWrap.topAnchor.constraint(equalTo: sep.bottomAnchor),
            formWrap.leadingAnchor.constraint(equalTo: leadingAnchor),
            formWrap.trailingAnchor.constraint(equalTo: trailingAnchor),
            formHeightConstraint,

            // formInner anchored to the BOTTOM of formWrap so it slides in from above
            formInner.bottomAnchor.constraint(equalTo: formWrap.bottomAnchor),
            formInner.leadingAnchor.constraint(equalTo: formWrap.leadingAnchor),
            formInner.trailingAnchor.constraint(equalTo: formWrap.trailingAnchor),
            formInner.heightAnchor.constraint(equalToConstant: Self.formH),

            formTitleLbl.topAnchor.constraint(equalTo: formInner.topAnchor, constant: 8),
            formTitleLbl.leadingAnchor.constraint(equalTo: formInner.leadingAnchor, constant: 10),

            nameField.topAnchor.constraint(equalTo: formTitleLbl.bottomAnchor, constant: 5),
            nameField.leadingAnchor.constraint(equalTo: formInner.leadingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: formInner.trailingAnchor, constant: -8),
            nameField.heightAnchor.constraint(equalToConstant: 18),

            connField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 4),
            connField.leadingAnchor.constraint(equalTo: formInner.leadingAnchor, constant: 8),
            connField.trailingAnchor.constraint(equalTo: formInner.trailingAnchor, constant: -8),
            connField.heightAnchor.constraint(equalToConstant: 18),

            keyField.topAnchor.constraint(equalTo: connField.bottomAnchor, constant: 4),
            keyField.leadingAnchor.constraint(equalTo: formInner.leadingAnchor, constant: 8),
            keyField.trailingAnchor.constraint(equalTo: formInner.trailingAnchor, constant: -8),
            keyField.heightAnchor.constraint(equalToConstant: 18),

            saveBtn.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 7),
            saveBtn.trailingAnchor.constraint(equalTo: formInner.trailingAnchor, constant: -8),
            saveBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            saveBtn.heightAnchor.constraint(equalToConstant: 16),

            cancelBtn.centerYAnchor.constraint(equalTo: saveBtn.centerYAnchor),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancelBtn.heightAnchor.constraint(equalToConstant: 16),

            scrollView.topAnchor.constraint(equalTo: formWrap.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        rebuildList()
        // Z-order fix: formWrap must be in front of scrollView so buttons are clickable
        addSubview(formWrap)
    }

    private func rebuildList() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if profiles.isEmpty {
            let empty = NSTextField(labelWithString: Loc.sshNoSaved)
            empty.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            empty.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                wrapper.heightAnchor.constraint(equalToConstant: 50),
            ])
            listStack.addArrangedSubview(wrapper)
            return
        }

        for (i, profile) in profiles.enumerated() {
            let row = SSHProfileRowView(profile: profile, index: i, accent: Self.accent)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onConnect = { [weak self] idx in
                guard let self = self, idx < self.profiles.count else { return }
                self.onConnect?(self.profiles[idx])
            }
            row.onEdit = { [weak self] idx in self?.startEditing(at: idx) }
            row.onDelete = { [weak self] idx in
                guard let self = self, idx < self.profiles.count else { return }
                self.profiles.remove(at: idx)
                self.saveProfiles()
                self.rebuildList()
            }
            listStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: listStack.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: listStack.trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 44),
            ])
        }
    }

    private func startEditing(at index: Int) {
        guard index < profiles.count else { return }
        let p = profiles[index]
        editingIndex = index
        formTitleLbl.stringValue = "EDIT CONNECTION"
        nameField.stringValue = p.label
        let portSuffix = p.port == 22 ? "" : ":\(p.port)"
        connField.stringValue = "\(p.user)@\(p.host)\(portSuffix)"
        keyField.stringValue  = p.keyFile
        openForm()
    }

    @objc private func toggleForm() {
        if formVisible {
            cancelForm()
        } else {
            editingIndex = nil
            formTitleLbl.stringValue = Loc.sshNewConn
            [nameField, connField, keyField].forEach { $0.stringValue = "" }
            openForm()
        }
    }

    private func openForm() {
        guard !formVisible else { return }
        formVisible = true
        addBtn.title = "−"
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            self.formHeightConstraint.animator().constant = Self.formH
        }
        window?.makeFirstResponder(nameField)
    }

    @objc private func cancelForm() {
        formVisible = false
        editingIndex = nil
        addBtn.title = "+"
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.formHeightConstraint.animator().constant = 0
        }
        window?.makeFirstResponder(nil)
    }

    @objc private func saveProfile() {
        let conn = connField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !conn.isEmpty else {
            // Visual error hint
            connField.layer?.borderColor = NSColor.systemRed.cgColor
            connField.layer?.borderWidth = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.connField.layer?.borderWidth = 0
            }
            return
        }

        // Parse user@host:port
        var user = "root", host = conn, port = 22
        if conn.contains("@") {
            let parts = conn.split(separator: "@", maxSplits: 1)
            user = String(parts[0])
            host = String(parts[1])
        }
        if host.contains(":") {
            let parts = host.split(separator: ":", maxSplits: 1)
            host = String(parts[0])
            port = Int(String(parts[1])) ?? 22
        }

        let label = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let key   = keyField.stringValue.trimmingCharacters(in: .whitespaces)

        if let idx = editingIndex, idx < profiles.count {
            profiles[idx] = SSHProfile(id: profiles[idx].id,
                label: label, user: user, host: host, port: port, keyFile: key)
        } else {
            profiles.append(SSHProfile(label: label, user: user, host: host, port: port, keyFile: key))
        }
        saveProfiles()
        rebuildList()
        cancelForm()
    }

    @objc private func closePanel()    { onClose?() }
    @objc private func moveUpTapped()   { onMoveUp?() }
    @objc private func moveDownTapped() { onMoveDown?() }

    @objc private func refreshSSHLanguage() {
        formTitleLbl.stringValue = Loc.sshNewConn
        nameField.placeholderString = Loc.sshNamePh
        connField.placeholderString = Loc.sshConnPh
        keyField.placeholderString  = Loc.sshKeyPh
        rebuildList()
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: "sshProfiles"),
              let loaded = try? JSONDecoder().decode([SSHProfile].self, from: data) else { return }
        profiles = loaded
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "sshProfiles")
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showSidebarContextMenu(in: self, event: event)
    }
}

// Profile row with hover-reveal action buttons
private class SSHProfileRowView: NSView {
    var onConnect: ((Int) -> Void)?
    var onEdit:    ((Int) -> Void)?
    var onDelete:  ((Int) -> Void)?

    private let rowIndex: Int
    private let accent: NSColor
    private var trackingArea: NSTrackingArea?
    private let deleteBtn = NSButton()
    private let editBtn   = NSButton()

    init(profile: SSHProfile, index: Int, accent: NSColor) {
        self.rowIndex = index
        self.accent   = accent
        super.init(frame: .zero)
        wantsLayer = true
        setupRow(profile: profile)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupRow(profile: SSHProfile) {
        let nameLbl = NSTextField(labelWithString: profile.label.isEmpty ? profile.host : profile.label)
        nameLbl.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        nameLbl.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        nameLbl.lineBreakMode = .byTruncatingTail
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLbl)

        let portStr = profile.port == 22 ? "" : ":\(profile.port)"
        let sub = NSTextField(labelWithString: "\(profile.user)@\(profile.host)\(portStr)")
        sub.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        sub.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        sub.lineBreakMode = .byTruncatingTail
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sub)

        let connectBtn = NSButton()
        connectBtn.title = "▶"
        connectBtn.font = NSFont.systemFont(ofSize: 10)
        connectBtn.isBordered = false
        connectBtn.contentTintColor = accent
        connectBtn.target = self
        connectBtn.action = #selector(connectTapped)
        connectBtn.toolTip = "Connect in new tab"
        connectBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectBtn)

        editBtn.title = "✎"
        editBtn.font = NSFont.systemFont(ofSize: 10)
        editBtn.isBordered = false
        editBtn.contentTintColor = NSColor(calibratedWhite: 0.50, alpha: 1)
        editBtn.target = self
        editBtn.action = #selector(editTapped)
        editBtn.toolTip = "Edit"
        editBtn.alphaValue = 0
        editBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editBtn)

        deleteBtn.title = "✕"
        deleteBtn.font = NSFont.systemFont(ofSize: 9)
        deleteBtn.isBordered = false
        deleteBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTapped)
        deleteBtn.toolTip = "Delete"
        deleteBtn.alphaValue = 0
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteBtn)

        // Key indicator
        if !profile.keyFile.isEmpty {
            let keyLbl = NSTextField(labelWithString: "⚿ \(URL(fileURLWithPath: profile.keyFile).lastPathComponent)")
            keyLbl.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
            keyLbl.textColor = NSColor(calibratedWhite: 0.40, alpha: 1)
            keyLbl.toolTip = profile.keyFile
            keyLbl.lineBreakMode = .byTruncatingTail
            keyLbl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(keyLbl)
            NSLayoutConstraint.activate([
                keyLbl.leadingAnchor.constraint(equalTo: sub.leadingAnchor),
                keyLbl.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 1),
                keyLbl.trailingAnchor.constraint(lessThanOrEqualTo: connectBtn.leadingAnchor, constant: -4),
            ])
        }

        NSLayoutConstraint.activate([
            nameLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLbl.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            nameLbl.trailingAnchor.constraint(lessThanOrEqualTo: connectBtn.leadingAnchor, constant: -4),

            sub.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sub.topAnchor.constraint(equalTo: nameLbl.bottomAnchor, constant: 2),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: connectBtn.leadingAnchor, constant: -4),

            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 18),

            editBtn.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -2),
            editBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            editBtn.widthAnchor.constraint(equalToConstant: 18),

            connectBtn.trailingAnchor.constraint(equalTo: editBtn.leadingAnchor, constant: -2),
            connectBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            connectBtn.widthAnchor.constraint(equalToConstant: 22),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            deleteBtn.animator().alphaValue = 1
            editBtn.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            deleteBtn.animator().alphaValue = 0
            editBtn.animator().alphaValue = 0
        }
    }

    @objc private func connectTapped() { onConnect?(rowIndex) }
    @objc private func editTapped()    { onEdit?(rowIndex) }
    @objc private func deleteTapped()  { onDelete?(rowIndex) }
}

// MARK: - Color Theme Picker

private class ColorThemeRow: NSView {
    var onChanged: ((String, Int) -> Void)?
    var onPreview: ((Int) -> Void)?

    private var savedIdx: Int
    private var buttons: [ColorChipButton] = []

    private static let labels  = ["Dark", "Light", "OLED", "System"]
    private static let chipBG: [NSColor] = [
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0),
        NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.02, alpha: 1.0),
        NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.24, alpha: 1.0),
    ]
    private static let chipFG: [NSColor] = [
        NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0),
        NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.90, alpha: 1.0),
        NSColor(calibratedRed: 0.70, green: 0.70, blue: 0.75, alpha: 1.0),
    ]

    init(selected: Int) {
        self.savedIdx = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupButtons()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        var prev: NSView? = nil
        for i in 0..<4 {
            let btn = ColorChipButton(
                title: Self.labels[i], index: i,
                bg: Self.chipBG[i], fg: Self.chipFG[i],
                isSelected: i == savedIdx
            )
            btn.target = self
            btn.action = #selector(chipTapped(_:))
            btn.onHoverEnter = { [weak self] idx in self?.onPreview?(idx) }
            btn.onHoverExit  = { [weak self] in  self?.onPreview?(self?.savedIdx ?? 0) }
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
            buttons.append(btn)
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                btn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
                btn.widthAnchor.constraint(equalToConstant: 56),
            ])
            if let p = prev {
                btn.leadingAnchor.constraint(equalTo: p.trailingAnchor, constant: 4).isActive = true
            } else {
                btn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
            }
            prev = btn
        }
    }

    @objc private func chipTapped(_ sender: NSButton) {
        guard let btn = sender as? ColorChipButton else { return }
        savedIdx = btn.themeIndex
        buttons.forEach { $0.isSelected = $0.themeIndex == savedIdx }
        onChanged?("colorTheme", savedIdx)
    }
}

private class ColorChipButton: NSButton {
    let themeIndex: Int
    private let chipBG: NSColor
    private let chipFG: NSColor
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    var onHoverEnter: ((Int) -> Void)?
    var onHoverExit:  (() -> Void)?
    private var ta: NSTrackingArea?

    init(title: String, index: Int, bg: NSColor, fg: NSColor, isSelected: Bool) {
        self.themeIndex = index
        self.chipBG = bg
        self.chipFG = fg
        super.init(frame: .zero)
        self.title = title
        self.isSelected = isSelected
        isBordered = false
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
        chipBG.setFill(); path.fill()
        let border: NSColor = isSelected
            ? NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
            : NSColor(calibratedWhite: 1.0, alpha: 0.12)
        border.setStroke()
        path.lineWidth = isSelected ? 1.5 : 0.5
        path.stroke()
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: isSelected ? .semibold : .regular),
            .foregroundColor: chipFG,
        ]
        let s = NSAttributedString(string: title, attributes: attr)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta { removeTrackingArea(ta) }
        ta = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(ta!)
    }

    override func mouseEntered(with event: NSEvent) { onHoverEnter?(themeIndex) }
    override func mouseExited(with event: NSEvent)  { onHoverExit?() }
}

// MARK: - WebPicker Sidebar View


private final class VertCenteredTextFieldCell: NSTextFieldCell {
    var leftPad: CGFloat = 0

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let h = cellSize(forBounds: rect).height
        let y = rect.minY + (rect.height - h) / 2
        return NSRect(x: rect.minX + leftPad, y: y, width: rect.width - leftPad, height: h)
    }

    override func select(withFrame rect: NSRect, in cv: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: cv, editor: editor, delegate: delegate, start: start, length: length)
    }

    override func edit(withFrame rect: NSRect, in cv: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: cv, editor: editor, delegate: delegate, event: event)
    }
}

private final class PickRowView: NSView {
    var onHighlight: (() -> Void)?
    var onUnhighlight: (() -> Void)?
    var onRemove: (() -> Void)?
    var onCopied: (() -> Void)?
    private let xBtn = NSButton()
    private let labelScroll = NSScrollView()
    private var rowArea: NSTrackingArea?
    private var xArea: NSTrackingArea?
    private var html: String = ""

    init(html: String, color: NSColor) {
        self.html = html
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        // Label inside a horizontal scroll view — swipe to read full HTML
        let text = html.replacingOccurrences(of: "\n", with: " ")
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        label.textColor = color.withAlphaComponent(0.9)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.sizeToFit()

        let labelH = label.frame.height

        labelScroll.documentView = label
        labelScroll.hasVerticalScroller = false
        labelScroll.hasHorizontalScroller = true
        labelScroll.autohidesScrollers = true
        labelScroll.scrollerStyle = .overlay
        labelScroll.drawsBackground = false
        labelScroll.horizontalScrollElasticity = .allowed
        labelScroll.verticalScrollElasticity = .none
        labelScroll.translatesAutoresizingMaskIntoConstraints = false

        xBtn.title = "×"; xBtn.isBordered = false
        xBtn.font = NSFont.systemFont(ofSize: 11, weight: .light)
        xBtn.contentTintColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        xBtn.translatesAutoresizingMaskIntoConstraints = false
        xBtn.target = self; xBtn.action = #selector(removed)

        addSubview(dot); addSubview(labelScroll); addSubview(xBtn)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            xBtn.trailingAnchor.constraint(equalTo: trailingAnchor),
            xBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            xBtn.widthAnchor.constraint(equalToConstant: 14),
            labelScroll.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
            labelScroll.trailingAnchor.constraint(equalTo: xBtn.leadingAnchor, constant: -2),
            labelScroll.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelScroll.heightAnchor.constraint(equalToConstant: labelH),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = rowArea { removeTrackingArea(a) }
        if let a = xArea   { xBtn.removeTrackingArea(a) }
        rowArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: ["t": "row"])
        xArea   = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: ["t": "x"])
        addTrackingArea(rowArea!)
        xBtn.addTrackingArea(xArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        if (event.trackingArea?.userInfo?["t"] as? String) == "x" {
            xBtn.contentTintColor = NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 1)
        } else {
            layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
            alphaValue = 1.0
            onHighlight?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if (event.trackingArea?.userInfo?["t"] as? String) == "x" {
            xBtn.contentTintColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        } else {
            layer?.backgroundColor = .clear
            onUnhighlight?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if !xBtn.frame.contains(pt) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(html, forType: .string)
            onCopied?()
        }
        super.mouseDown(with: event)
    }

    @objc private func removed() { onRemove?() }
}

class WebPickerSidebarView: NSView {
    private let cdp = ChromeCDPClient()
    private var pollTimer: Timer?
    private var tabSearchTimer: Timer?
    private var titlePollTimer: Timer?
    private var isConnected = false
    private var currentTargetId: String?
    var onClose:    (() -> Void)?
    var onConnected: (() -> Void)?
    var onMoveUp:   (() -> Void)?
    var onMoveDown: (() -> Void)?
    private let moveUpBtn   = NSButton()
    private let moveDownBtn = NSButton()

    func setMoveButtonsEnabled(up: Bool, down: Bool) {
        let visible = up || down
        moveUpBtn.isHidden   = !visible
        moveDownBtn.isHidden = !visible
        moveUpBtn.isEnabled   = up;   moveUpBtn.alphaValue   = up   ? 1.0 : 0.35
        moveDownBtn.isEnabled = down; moveDownBtn.alphaValue = down ? 1.0 : 0.35
    }

    // Teal accent
    private static let teal = NSColor(calibratedRed: 0.24, green: 0.79, blue: 0.63, alpha: 1.0)

    // UI elements
    private let titleLabel    = NSTextField(labelWithString: "◈  WebPicker")
    private let closeBtn      = NSButton()
    private let debugLink1    = NSTextField(labelWithString: "chrome://inspect")
    private let debugLink2    = NSTextField(labelWithString: "localhost:9222/json")
    private let titleSep      = NSView()
    private let statusDot     = NSView()
    private let statusLabel   = NSTextField(labelWithString: "")
    private let pickBtn       = NSButton()
    private let connectBtn    = NSButton()
    private let disconnectBtn = NSButton()
    private let urlBg         = NSView()
    private let urlField      = NSTextField()
    private let previewSep         = NSView()
    private let picksHeaderLabel   = NSTextField(labelWithString: "")
    private let picksSep           = NSView()
    private let clearPicksBtn      = NSButton()
    private let picksStack         = NSStackView()
    private let feedbackLabel      = NSTextField(labelWithString: "")
    private var statusLabelTrailingConnected: NSLayoutConstraint!
    private var statusLabelTrailingDisconnected: NSLayoutConstraint!
    private struct PickEntry { let id: Int; let html: String; let hex: String; let color: NSColor }
    private var picks: [PickEntry] = []
    private var nextPickId = 0

    // ── URL history ──
    private let suggestBox = NSView()
    private var suggestBoxH: NSLayoutConstraint!
    private static let historyKey = "webPickerURLHistory"
    private static let historyMax = 15
    private static let pickColors: [(NSColor, String)] = [
        (NSColor(calibratedRed: 1.0,  green: 0.42, blue: 0.42, alpha: 1), "#FF6B6B"),
        (NSColor(calibratedRed: 0.27, green: 0.72, blue: 0.82, alpha: 1), "#45B7D1"),
        (NSColor(calibratedRed: 0.97, green: 0.86, blue: 0.44, alpha: 1), "#F7DC6F"),
        (NSColor(calibratedRed: 0.59, green: 0.81, blue: 0.68, alpha: 1), "#96CEB4"),
        (NSColor(calibratedRed: 0.87, green: 0.63, blue: 0.87, alpha: 1), "#DE99DE"),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage),
                                               name: .appLanguageChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refreshLanguage() {
        picksHeaderLabel.stringValue = Loc.picks
        clearPicksBtn.title = Loc.resetMarks
        if isConnected {
            disconnectBtn.title = Loc.disconnect
            pickBtn.title = Loc.pickElement
        } else {
            showDisconnectedState()
        }
    }

    private func setupUI() {
        // ── Title bar ──
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = Self.teal
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeBtn.title = "✕"
        closeBtn.isBordered = false; closeBtn.bezelStyle = .inline
        closeBtn.font = NSFont.systemFont(ofSize: 11)
        closeBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        closeBtn.target = self; closeBtn.action = #selector(doClose)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeBtn)

        for (btn, symbol, sel) in [(moveDownBtn, "▼", #selector(moveDownTapped)),
                                   (moveUpBtn,   "▲", #selector(moveUpTapped))] {
            btn.title = symbol
            btn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            btn.isBordered = false
            btn.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
            btn.target = self; btn.action = sel
            btn.isHidden = true
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
        }

        // ── Debug links ──
        for (lbl, tip) in [(debugLink1, "Open chrome://inspect in Chrome"),
                           (debugLink2, "Open http://localhost:9222/json in browser")] {
            lbl.font = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .regular)
            lbl.textColor = Self.teal.withAlphaComponent(0.45)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.toolTip = tip
            addSubview(lbl)
        }
        debugLink1.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openChromeInspect)))
        debugLink2.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openDebugJSON)))

        // ── Separators ──
        for sep in [titleSep, previewSep] {
            sep.wantsLayer = true
            sep.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sep)
        }
        titleSep.layer?.backgroundColor   = Self.teal.withAlphaComponent(0.25).cgColor
        previewSep.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor

        // ── Status row ──
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusDot)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        statusLabel.textColor = NSColor(calibratedWhite: 0.6, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        // ── Disconnect button (in status row) ──
        disconnectBtn.title = Loc.disconnect
        disconnectBtn.bezelStyle = .inline
        disconnectBtn.isBordered = false
        disconnectBtn.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        disconnectBtn.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        disconnectBtn.isHidden = true
        disconnectBtn.target = self; disconnectBtn.action = #selector(doDisconnect)
        disconnectBtn.translatesAutoresizingMaskIntoConstraints = false
        disconnectBtn.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: ["btn": "disconnect"]))
        addSubview(disconnectBtn)

        // ── URL bar ──
        urlBg.wantsLayer = true
        urlBg.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        urlBg.layer?.cornerRadius = 5
        urlBg.layer?.borderColor = NSColor(calibratedWhite: 0.20, alpha: 1).cgColor
        urlBg.layer?.borderWidth = 0.5
        urlBg.isHidden = true
        urlBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlBg)

        let urlCell = VertCenteredTextFieldCell(textCell: "")
        urlCell.leftPad = 10
        urlCell.placeholderString = "https://..."
        urlCell.font = NSFont.systemFont(ofSize: 10)
        urlCell.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        urlCell.isBezeled = false
        urlCell.isEditable = true
        urlCell.drawsBackground = false
        urlCell.focusRingType = .none
        urlField.cell = urlCell
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.target = self; urlField.action = #selector(navigateURL)
        urlField.delegate = self
        urlBg.addSubview(urlField)

        // ── Pick button ──
        pickBtn.title = Loc.pickElement
        pickBtn.bezelStyle = .rounded
        pickBtn.isEnabled = false
        pickBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        pickBtn.wantsLayer = true
        pickBtn.target = self; pickBtn.action = #selector(startPicking)
        pickBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pickBtn)
        styleTealButton(pickBtn, enabled: false)

        // ── Connect button ──
        connectBtn.title = Loc.connectToChrome
        connectBtn.bezelStyle = .rounded
        connectBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        connectBtn.wantsLayer = true
        connectBtn.target = self; connectBtn.action = #selector(doConnectBtn)
        connectBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectBtn)
        styleTealButton(connectBtn, enabled: true)

        // ── Picks section header ──
        picksHeaderLabel.font = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        picksHeaderLabel.textColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        picksHeaderLabel.stringValue = Loc.picks
        picksHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        picksHeaderLabel.isHidden = true
        addSubview(picksHeaderLabel)

        clearPicksBtn.title = Loc.resetMarks
        clearPicksBtn.isBordered = false
        clearPicksBtn.font = NSFont.systemFont(ofSize: 8.5, weight: .regular)
        clearPicksBtn.contentTintColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        clearPicksBtn.translatesAutoresizingMaskIntoConstraints = false
        clearPicksBtn.isHidden = true
        clearPicksBtn.target = self; clearPicksBtn.action = #selector(clearAllPicksAction)
        addSubview(clearPicksBtn)

        picksSep.wantsLayer = true
        picksSep.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
        picksSep.translatesAutoresizingMaskIntoConstraints = false
        picksSep.isHidden = true
        addSubview(picksSep)

        picksStack.orientation = .vertical
        picksStack.spacing = 2
        picksStack.alignment = .leading
        picksStack.distribution = .fillProportionally
        picksStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picksStack)

        feedbackLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        feedbackLabel.textColor = Self.teal
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(feedbackLabel)

        NSLayoutConstraint.activate([
            // ── Title bar ──
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 18),
            moveDownBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -2),
            moveDownBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moveDownBtn.widthAnchor.constraint(equalToConstant: 16),
            moveUpBtn.trailingAnchor.constraint(equalTo: moveDownBtn.leadingAnchor, constant: -1),
            moveUpBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moveUpBtn.widthAnchor.constraint(equalToConstant: 16),
            // ── Debug links ──
            debugLink1.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            debugLink1.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            debugLink2.leadingAnchor.constraint(equalTo: debugLink1.trailingAnchor, constant: 6),
            debugLink2.centerYAnchor.constraint(equalTo: debugLink1.centerYAnchor),
            // ── Title separator ──
            titleSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleSep.topAnchor.constraint(equalTo: debugLink1.bottomAnchor, constant: 6),
            titleSep.heightAnchor.constraint(equalToConstant: 1),
            // ── Status row ──
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusDot.topAnchor.constraint(equalTo: titleSep.bottomAnchor, constant: 10),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 7),
            statusLabel.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            // Disconnect — right of status row
            disconnectBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            disconnectBtn.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            // ── URL bar ──
            urlBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            urlBg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            urlBg.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 8),
            urlBg.heightAnchor.constraint(equalToConstant: 24),
            urlField.leadingAnchor.constraint(equalTo: urlBg.leadingAnchor, constant: 10),
            urlField.trailingAnchor.constraint(equalTo: urlBg.trailingAnchor, constant: -8),
            urlField.topAnchor.constraint(equalTo: urlBg.topAnchor),
            urlField.bottomAnchor.constraint(equalTo: urlBg.bottomAnchor),
            // ── Pick / Connect buttons (below urlBg) ──
            pickBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pickBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pickBtn.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 8),
            connectBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            connectBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            connectBtn.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 8),
            // ── Section separator ──
            previewSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewSep.topAnchor.constraint(equalTo: pickBtn.bottomAnchor, constant: 10),
            previewSep.heightAnchor.constraint(equalToConstant: 1),
            // ── Picks header ──
            picksHeaderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            picksHeaderLabel.topAnchor.constraint(equalTo: previewSep.bottomAnchor, constant: 8),
            clearPicksBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            clearPicksBtn.centerYAnchor.constraint(equalTo: picksHeaderLabel.centerYAnchor),
            // ── Picks divider ──
            picksSep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            picksSep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            picksSep.topAnchor.constraint(equalTo: picksHeaderLabel.bottomAnchor, constant: 5),
            picksSep.heightAnchor.constraint(equalToConstant: 1),
            // ── Picks list ──
            picksStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            picksStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            picksStack.topAnchor.constraint(equalTo: picksSep.bottomAnchor, constant: 5),
            // ── Feedback ──
            feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            feedbackLabel.topAnchor.constraint(equalTo: picksStack.bottomAnchor, constant: 6),
        ])

        // Dynamic statusLabel trailing — narrow when disconnect visible, full when hidden
        statusLabelTrailingConnected    = statusLabel.trailingAnchor.constraint(equalTo: disconnectBtn.leadingAnchor, constant: -4)
        statusLabelTrailingDisconnected = statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        statusLabelTrailingDisconnected.isActive = true

        // ── URL history dropdown (added after other views to stay on top) ──
        suggestBox.wantsLayer = true
        suggestBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.97).cgColor
        suggestBox.layer?.cornerRadius = 5
        suggestBox.layer?.borderColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        suggestBox.layer?.borderWidth = 0.5
        suggestBox.isHidden = true
        suggestBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(suggestBox)

        NSLayoutConstraint.activate([
            suggestBox.leadingAnchor.constraint(equalTo: urlBg.leadingAnchor),
            suggestBox.trailingAnchor.constraint(equalTo: urlBg.trailingAnchor),
            suggestBox.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 2),
        ])
        suggestBoxH = suggestBox.heightAnchor.constraint(equalToConstant: 0)
        suggestBoxH.isActive = true

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
        setStatusText(Loc.notConnected)
        pickBtn.isHidden = true
        pickBtn.title = Loc.pickElement
        disconnectBtn.isHidden = true
        disconnectBtn.title = Loc.disconnect
        connectBtn.isHidden = false
        connectBtn.isEnabled = true
        connectBtn.title = Loc.connectToChrome
        styleTealButton(connectBtn, enabled: true)
        urlBg.isHidden = true; urlField.stringValue = ""
        hideSuggestions()
        previewSep.isHidden = true
        clearPickList()
        feedbackLabel.isHidden = true
        statusLabelTrailingConnected?.isActive = false
        statusLabelTrailingDisconnected?.isActive = true
    }

    private func showConnectingState(_ msg: String) {
        setStatusDot(.systemOrange)
        setStatusText(msg)
        urlBg.isHidden = true
        pickBtn.isHidden = true
        disconnectBtn.isHidden = true
        connectBtn.isHidden = false
        connectBtn.isEnabled = false
        styleTealButton(connectBtn, enabled: false)
        previewSep.isHidden = true
        statusLabelTrailingConnected?.isActive = false
        statusLabelTrailingDisconnected?.isActive = true
    }

    private func showConnectedState(hostname: String, navigating: Bool) {
        if navigating {
            setStatusDot(.systemOrange)
            setStatusText(Loc.navigateTo)
        } else {
            setStatusDot(Self.teal)
            setStatusText(hostname.isEmpty ? Loc.verbunden : hostname)
        }
        connectBtn.isHidden = true
        urlBg.isHidden = false
        pickBtn.isHidden = false
        pickBtn.isEnabled = !navigating
        styleTealButton(pickBtn, enabled: !navigating)
        disconnectBtn.isHidden = false
        previewSep.isHidden = false
        statusLabelTrailingDisconnected?.isActive = false
        statusLabelTrailingConnected?.isActive = true
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
        pollTimer?.invalidate(); pollTimer = nil
        tabSearchTimer?.invalidate(); tabSearchTimer = nil
        titlePollTimer?.invalidate(); titlePollTimer = nil
        pickBtn.title = Loc.pickElement
        showConnectingState(Loc.connecting)
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
        cdp.onDisconnected = nil
        pickBtn.title = Loc.pickElement
        let cleanup = "window.__qtPickerActive=false;[0,1,2,3,4,5,6,7,8,9].forEach(function(i){var e=document.querySelector('[data-qt-pick-'+i+']');if(e)e.removeAttribute('data-qt-pick-'+i);});document.querySelectorAll('*').forEach(function(el){el.style.outline='';el.style.outlineOffset='';});void 0;"
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
        // Clear saved target so next Connect() doesn't try to reconnect to the now-closed tab
        UserDefaults.standard.removeObject(forKey: "webPickerLastTargetId")
        showDisconnectedState()
    }

    /// Closes the WebSocket but keeps the Chrome tab alive for later reconnection.
    /// Called when the sidebar is hidden — tab ID is preserved in UserDefaults for next connect().
    func softDisconnect() {
        pollTimer?.invalidate(); pollTimer = nil
        tabSearchTimer?.invalidate(); tabSearchTimer = nil
        titlePollTimer?.invalidate(); titlePollTimer = nil
        isConnected = false
        cdp.onDisconnected = nil
        pickBtn.title = Loc.pickElement
        let cleanup = "window.__qtPickerActive=false;[0,1,2,3,4,5,6,7,8,9].forEach(function(i){var e=document.querySelector('[data-qt-pick-'+i+']');if(e)e.removeAttribute('data-qt-pick-'+i);});document.querySelectorAll('*').forEach(function(el){el.style.outline='';el.style.outlineOffset='';});void 0;"
        cdp.evaluate(cleanup) { [weak self] _ in self?.cdp.disconnect() }
        // NOTE: currentTargetId kept intact in UserDefaults so connect() can reconnect to same tab
        showDisconnectedState()
    }

    private func connectToTab() {
        let preferred = UserDefaults.standard.string(forKey: "webPickerLastTargetId")
        cdp.getActiveTabWS(preferredTargetId: preferred) { [weak self] wsURL in
            guard let self = self else { return }
            if let wsURL = wsURL {
                self.doConnect(to: wsURL)
            } else {
                self.showConnectingState(Loc.openingTab)
                self.cdp.createBlankTab { [weak self] newWS in
                    guard let self = self else { return }
                    if let newWS = newWS {
                        self.doConnect(to: newWS)
                    } else {
                        self.showDisconnectedState()
                        self.setStatusText(Loc.chromeNotReachable)
                    }
                }
            }
        }
    }

    /// Handles unexpected disconnection (WebSocket drop, tab closed externally).
    /// Does NOT send cleanup JS or close the tab — connection is already gone.
    private func handleUnexpectedDisconnect(message: String) {
        guard isConnected else { return }
        isConnected = false
        pollTimer?.invalidate(); pollTimer = nil
        titlePollTimer?.invalidate(); titlePollTimer = nil
        currentTargetId = nil
        cdp.disconnect()
        showDisconnectedState()
        setStatusText(message)
    }

    private func doConnect(to wsURL: String) {
        currentTargetId = URL(string: wsURL)?.lastPathComponent
        if let tid = currentTargetId {
            UserDefaults.standard.set(tid, forKey: "webPickerLastTargetId")
        }
        tabSearchTimer?.invalidate(); tabSearchTimer = nil
        cdp.onDisconnected = { [weak self] in
            self?.handleUnexpectedDisconnect(message: Loc.connectionLost)
        }
        cdp.connect(wsURL: wsURL) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.isConnected = true
                self.cdp.findManagedApp()
                if let tid = self.currentTargetId {
                    let h = Int(NSScreen.main?.frame.height ?? 900)
                    // Small delay so Chrome is fully ready to accept window bounds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.cdp.setChromeWindowBounds(width: 777, height: h, left: 0, top: 0, targetId: tid)
                    }
                }
                self.onConnected?()
                self.refreshTabTitle()
                self.startTitlePolling()
            } else {
                self.showDisconnectedState()
                self.setStatusText(Loc.connectionFailed)
                self.scheduleTabSearch()
            }
        }
    }

    private func refreshTabTitle() {
        guard let tid = currentTargetId else { return }
        cdp.getTabHostname(targetId: tid) { [weak self] hostname in
            guard let self = self, self.isConnected else { return }
            if let hostname = hostname {
                // hostname == "" means about:blank (still navigating), non-empty = real site
                self.showConnectedState(hostname: hostname, navigating: hostname.isEmpty)
            } else {
                // nil = tab not found in /json/list — tab was closed externally
                self.handleUnexpectedDisconnect(message: Loc.tabClosed)
            }
        }
    }

    private func startTitlePolling() {
        titlePollTimer?.invalidate()
        titlePollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshTabTitle()
        }
    }

    private func scheduleTabSearch() {
        tabSearchTimer?.invalidate()
        tabSearchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            self.connectToTab()
        }
    }

    // MARK: - Button actions

    @objc private func doConnectBtn() { connect() }
    @objc private func doDisconnect() { disconnect() }
    @objc private func doClose()       { onClose?() }
    @objc private func moveUpTapped()   { onMoveUp?() }
    @objc private func moveDownTapped() { onMoveDown?() }

    @objc private func openChromeInspect() {
        // Open chrome://inspect in the managed Chrome via CDP navigate, or fall back to NSWorkspace
        if isConnected, let tid = currentTargetId {
            cdp.activateTarget(targetId: tid) { [weak self] in
                _ = self?.cdp.managedApp?.activate(options: [])
            }
            cdp.evaluate("window.open('chrome://inspect','_blank');void 0;") { _ in }
        } else {
            NSWorkspace.shared.open(URL(string: "chrome://inspect")!)
        }
    }

    @objc private func openDebugJSON() {
        let port = ChromeCDPClient.debugPort
        NSWorkspace.shared.open(URL(string: "http://localhost:\(port)/json")!)
    }

    // MARK: - Picker

    @objc private func navigateURL() {
        let text = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        addToHistory(text)
        hideSuggestions()
        cdp.navigate(to: text)
        window?.makeFirstResponder(nil)
    }

    @objc private func startPicking() {
        pickBtn.title = Loc.waitingForClick; pickBtn.isEnabled = false
        styleTealButton(pickBtn, enabled: false)
        feedbackLabel.isHidden = true
        cdp.evaluate("var p=document.querySelector('[data-qt-picked]');if(p)p.removeAttribute('data-qt-picked');window.__qtPickedHTML=null;window.__qtPickerActive=false;void 0;") { _ in }
        let pickerJS = """
        (function() {
          if (window.__qtPickerActive) return 'already_active';
          window.__qtPickerActive = true; window.__qtPickedHTML = null;

          // CSS :hover works even when Chrome is NOT the focused app (browser tracks mouse for cursor).
          // This is the primary highlight mechanism — no Chrome activation needed.
          var style = document.createElement('style');
          style.id = '__qt_picker_style';
          style.textContent = '* { cursor: crosshair !important; } *:hover { outline: 2px solid #4ECDC4 !important; outline-offset: -2px !important; }';
          document.head.appendChild(style);

          // When Chrome HAS focus: JS mouseover upgrades to random per-element colors.
          var palette = ['#FF6B6B','#4ECDC4','#45B7D1','#96CEB4','#DDA0DD','#F7DC6F','#FF9F7F','#87CEEB','#BB8FCE','#82E0AA'];
          function randColor() { return palette[Math.floor(Math.random()*palette.length)]; }
          var last = null;
          function over(e) {
            if (!window.__qtPickerActive) return;
            if (last && last !== e.target) { last.style.outline=''; last.style.outlineOffset=''; }
            last = e.target;
            last.style.outline='2px solid '+randColor(); last.style.outlineOffset='-2px';
          }
          function out(e) { if(e.target===last){e.target.style.outline='';e.target.style.outlineOffset='';} }
          function pick(e) {
            e.preventDefault(); e.stopPropagation();
            if (last){last.style.outline='';last.style.outlineOffset='';}
            var s=document.getElementById('__qt_picker_style'); if(s)s.remove();
            var prev=document.querySelector('[data-qt-picked]');
            if(prev) prev.removeAttribute('data-qt-picked');
            e.target.setAttribute('data-qt-picked','1');
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
            guard let self = self else { return }
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.cdp.evaluate("typeof window.__qtPickedHTML!=='undefined'&&window.__qtPickedHTML!==null?window.__qtPickedHTML:null") { [weak self] result in
                    guard let self = self,
                          let inner = (result?["result"] as? [String: Any]),
                          let val = inner["value"] as? String, !val.isEmpty else { return }
                    self.pollTimer?.invalidate(); self.pollTimer = nil
                    self.onHTMLPicked(val)
                }
            }
        }
    }

    private func highlightPick(id: Int, hex: String) {
        let js = "var el=document.querySelector('[data-qt-pick-\(id)]');if(el){el.scrollIntoView({behavior:'smooth',block:'center'});el.style.outline='3px solid \(hex)';el.style.outlineOffset='-3px';}void 0;"
        cdp.evaluate(js) { _ in }
    }

    private func unhighlightPick(id: Int) {
        let js = "var el=document.querySelector('[data-qt-pick-\(id)]');if(el){el.style.outline='';el.style.outlineOffset='';}void 0;"
        cdp.evaluate(js) { _ in }
    }

    private func clearPickList() {
        picks.removeAll()
        nextPickId = 0
        picksStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        picksHeaderLabel.isHidden = true
        picksSep.isHidden = true
        clearPicksBtn.isHidden = true
    }

    @objc private func clearAllPicksAction() {
        // Reset browser: deactivate picker, remove style tag + inline outlines only
        // data-qt-pick-N attributes stay so hover-highlight keeps working
        let js = "window.__qtPickerActive=false;var s=document.getElementById('__qt_picker_style');if(s)s.remove();document.querySelectorAll('*').forEach(function(el){el.style.outline='';el.style.outlineOffset='';});void 0;"
        cdp.evaluate(js) { _ in }
        // Cancel active pick poll if running
        pollTimer?.invalidate(); pollTimer = nil
        if !pickBtn.isEnabled {
            pickBtn.title = Loc.pickElement; pickBtn.isEnabled = true
            styleTealButton(pickBtn, enabled: true)
        }
        // List stays — only browser marks are cleared
    }

    private func onHTMLPicked(_ html: String) {
        // FIFO: remove oldest if already at 5
        if picks.count >= 5, let oldest = picks.first {
            cdp.evaluate("var e=document.querySelector('[data-qt-pick-\(oldest.id)]');if(e)e.removeAttribute('data-qt-pick-\(oldest.id)');") { _ in }
            picks.removeFirst()
            picksStack.arrangedSubviews.first?.removeFromSuperview()
        }

        let id = nextPickId; nextPickId += 1
        let (color, hex) = Self.pickColors[id % Self.pickColors.count]
        picks.append(PickEntry(id: id, html: html, hex: hex, color: color))

        // Relabel data-qt-picked → data-qt-pick-N in browser
        cdp.evaluate("var e=document.querySelector('[data-qt-picked]');if(e){e.removeAttribute('data-qt-picked');e.setAttribute('data-qt-pick-\(id)','1');}") { _ in }

        // Add row to picks list
        let row = PickRowView(html: html, color: color)
        row.onHighlight   = { [weak self] in self?.highlightPick(id: id, hex: hex) }
        row.onUnhighlight = { [weak self] in self?.unhighlightPick(id: id) }
        row.onCopied      = { [weak self] in self?.showCopiedFeedback() }
        row.onRemove = { [weak self] in
            guard let self = self else { return }
            self.cdp.evaluate("var e=document.querySelector('[data-qt-pick-\(id)]');if(e)e.removeAttribute('data-qt-pick-\(id)');") { _ in }
            self.picks.removeAll { $0.id == id }
            row.removeFromSuperview()
        }
        picksStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: picksStack.widthAnchor).isActive = true

        // Show picks header if first pick
        if picks.count == 1 {
            picksHeaderLabel.isHidden = false
            picksSep.isHidden = false
            clearPicksBtn.isHidden = false
        }

        pickBtn.title = Loc.pickElement
        pickBtn.isEnabled = true
        styleTealButton(pickBtn, enabled: true)

        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand; vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap); vUp?.post(tap: .cghidEventTap)
        }
        showCopiedFeedback()
    }

    private func showCopiedFeedback() {
        feedbackLabel.stringValue = "✓ Copied!"
        feedbackLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.feedbackLabel.isHidden = true
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if (event.trackingArea?.userInfo?["btn"] as? String) == "disconnect" {
            disconnectBtn.contentTintColor = NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 1)
        }
    }
    override func mouseExited(with event: NSEvent) {
        if (event.trackingArea?.userInfo?["btn"] as? String) == "disconnect" {
            disconnectBtn.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        }
    }

    // MARK: - URL History

    private func loadHistory() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    private func addToHistory(_ rawURL: String) {
        var url = rawURL.trimmingCharacters(in: .whitespaces)
        if url.isEmpty { return }
        if !url.contains("://") {
            let isLocal = url.hasPrefix("localhost") || url.hasPrefix("127.0.0.1") || url.hasPrefix("0.0.0.0")
            url = (isLocal ? "http://" : "https://") + url
        }
        var h = loadHistory().filter { $0 != url }
        h.insert(url, at: 0)
        UserDefaults.standard.set(Array(h.prefix(Self.historyMax)), forKey: Self.historyKey)
    }

    private func updateSuggestions(query: String) {
        suggestBox.subviews.forEach { $0.removeFromSuperview() }
        let history = loadHistory()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [String] = q.isEmpty
            ? Array(history.prefix(5))
            : history.filter { $0.lowercased().contains(q) }.prefix(5).map { $0 }
        guard !filtered.isEmpty else { suggestBox.isHidden = true; return }

        let rowH: CGFloat = 22
        for (i, url) in filtered.enumerated() {
            let btn = NSButton(title: url, target: self, action: #selector(selectSuggestion(_:)))
            btn.isBordered = false
            btn.alignment = .left
            btn.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
            btn.contentTintColor = NSColor(calibratedWhite: 0.72, alpha: 1)
            btn.lineBreakMode = .byTruncatingMiddle
            btn.identifier = NSUserInterfaceItemIdentifier(rawValue: url)
            btn.translatesAutoresizingMaskIntoConstraints = false
            suggestBox.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.leadingAnchor.constraint(equalTo: suggestBox.leadingAnchor, constant: 4),
                btn.trailingAnchor.constraint(equalTo: suggestBox.trailingAnchor, constant: -4),
                btn.topAnchor.constraint(equalTo: suggestBox.topAnchor, constant: CGFloat(i) * rowH + 2),
                btn.heightAnchor.constraint(equalToConstant: rowH),
            ])
        }
        suggestBoxH.constant = CGFloat(filtered.count) * rowH + 4
        suggestBox.isHidden = false
    }

    private func hideSuggestions() {
        suggestBox.isHidden = true
        suggestBox.subviews.forEach { $0.removeFromSuperview() }
    }

    @objc private func selectSuggestion(_ sender: NSButton) {
        let url = sender.identifier?.rawValue ?? sender.title
        urlField.stringValue = url
        hideSuggestions()
        cdp.navigate(to: url)
        window?.makeFirstResponder(nil)
    }

    deinit {
        pollTimer?.invalidate()
        tabSearchTimer?.invalidate()
        titlePollTimer?.invalidate()
        cdp.disconnect()
    }

    override func rightMouseDown(with event: NSEvent) {
        showSidebarContextMenu(in: self, event: event)
    }
}

extension WebPickerSidebarView: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === urlField else { return }
        updateSuggestions(query: urlField.stringValue)
    }
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === urlField else { return }
        updateSuggestions(query: urlField.stringValue)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === urlField else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.hideSuggestions()
        }
    }
}

// MARK: - Split Container

class PassthroughBlurView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

class SplitContainer: NSView {
    var primaryView: TerminalView!
    var secondaryView: TerminalView?
    var isVerticalSplit = true  // vertical = side by side, horizontal = top/bottom
    var splitRatio: CGFloat = 0.5
    private let dividerThickness: CGFloat = 4
    private var dividerView: NSView?
    private var isDragging = false
    var onFocusChanged: ((TerminalView) -> Void)?
    private var primaryDimOverlay: PassthroughBlurView?
    private var secondaryDimOverlay: PassthroughBlurView?
    private(set) var activePaneIsPrimary = true

    init(frame: NSRect, primary: TerminalView) {
        self.primaryView = primary
        super.init(frame: frame)
        wantsLayer = true
        addSubview(primary)
        primary.frame = bounds
        primary.autoresizingMask = [.width, .height]
    }

    /// Placeholder init for editor tabs — no terminal view attached
    init(placeholderFrame: NSRect) {
        super.init(frame: placeholderFrame)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    var isSplit: Bool { secondaryView != nil }

    private func makeDimOverlay() -> PassthroughBlurView {
        let ov = PassthroughBlurView(frame: .zero)
        ov.blendingMode = .withinWindow
        ov.material = .hudWindow
        ov.state = .active
        ov.wantsLayer = true
        ov.alphaValue = 0.55
        ov.isHidden = true
        return ov
    }

    func setActivePane(primary: Bool) {
        activePaneIsPrimary = primary
        guard isSplit else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            primaryDimOverlay?.animator().isHidden = primary
            secondaryDimOverlay?.animator().isHidden = !primary
        }
    }

    func split(vertical: Bool, secondary: TerminalView) {
        guard secondaryView == nil else { return }
        isVerticalSplit = vertical
        secondaryView = secondary
        addSubview(secondary)

        // Restore saved ratio
        let key = vertical ? "splitRatioV" : "splitRatioH"
        let saved = UserDefaults.standard.double(forKey: key)
        if saved > 0.1 && saved < 0.9 { splitRatio = CGFloat(saved) }

        // Divider
        let dv = NSView()
        dv.wantsLayer = true
        dv.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        addSubview(dv)
        dividerView = dv

        // Dim overlays for inactive pane indicator
        let pOv = makeDimOverlay()
        addSubview(pOv)
        primaryDimOverlay = pOv

        let sOv = makeDimOverlay()
        addSubview(sOv)
        secondaryDimOverlay = sOv

        // Remove autoresizing — we manage frames manually
        primaryView.autoresizingMask = []
        secondary.autoresizingMask = []

        layoutSplit()

        // Secondary starts active, so dim primary
        activePaneIsPrimary = false
        primaryDimOverlay?.isHidden = false
        secondaryDimOverlay?.isHidden = true

        // Fade in secondary
        secondary.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            secondary.animator().alphaValue = 1
        })
    }

    func unsplit() -> TerminalView? {
        guard let sec = secondaryView else { return nil }
        secondaryView = nil
        dividerView?.removeFromSuperview()
        dividerView = nil
        primaryDimOverlay?.removeFromSuperview()
        primaryDimOverlay = nil
        secondaryDimOverlay?.removeFromSuperview()
        secondaryDimOverlay = nil
        activePaneIsPrimary = true

        // Animate secondary out
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            sec.animator().alphaValue = 0
        }, completionHandler: {
            sec.removeFromSuperview()
        })

        primaryView.autoresizingMask = [.width, .height]
        primaryView.frame = bounds
        return sec
    }

    func layoutSplit() {
        guard let sec = secondaryView, let dv = dividerView else { return }
        let b = bounds
        if isVerticalSplit {
            let splitX = b.width * splitRatio
            primaryView.frame = NSRect(x: 0, y: 0, width: splitX - dividerThickness / 2, height: b.height)
            dv.frame = NSRect(x: splitX - dividerThickness / 2, y: 0, width: dividerThickness, height: b.height)
            sec.frame = NSRect(x: splitX + dividerThickness / 2, y: 0,
                               width: b.width - splitX - dividerThickness / 2, height: b.height)
        } else {
            let splitY = b.height * splitRatio
            sec.frame = NSRect(x: 0, y: 0, width: b.width, height: splitY - dividerThickness / 2)
            dv.frame = NSRect(x: 0, y: splitY - dividerThickness / 2, width: b.width, height: dividerThickness)
            primaryView.frame = NSRect(x: 0, y: splitY + dividerThickness / 2,
                                        width: b.width, height: b.height - splitY - dividerThickness / 2)
        }
        // Position dim overlays to match pane frames
        primaryDimOverlay?.frame = primaryView.frame
        secondaryDimOverlay?.frame = sec.frame
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if isSplit {
            layoutSplit()
        } else {
            primaryView.frame = NSRect(origin: .zero, size: newSize)
        }
    }

    // Divider dragging
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if let dv = dividerView, dv.frame.insetBy(dx: -4, dy: -4).contains(loc) {
            isDragging = true
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { super.mouseDragged(with: event); return }
        let loc = convert(event.locationInWindow, from: nil)
        let b = bounds
        if isVerticalSplit {
            splitRatio = max(0.15, min(0.85, loc.x / b.width))
        } else {
            splitRatio = max(0.15, min(0.85, loc.y / b.height))
        }
        layoutSplit()
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            // Save ratio
            let key = isVerticalSplit ? "splitRatioV" : "splitRatioH"
            UserDefaults.standard.set(Double(splitRatio), forKey: key)
        } else {
            // Check which pane was clicked to focus it
            let loc = convert(event.locationInWindow, from: nil)
            if let sec = secondaryView {
                if sec.frame.contains(loc) {
                    window?.makeFirstResponder(sec)
                    setActivePane(primary: false)
                    onFocusChanged?(sec)
                } else if primaryView.frame.contains(loc) {
                    window?.makeFirstResponder(primaryView)
                    setActivePane(primary: true)
                    onFocusChanged?(primaryView)
                }
            }
            super.mouseUp(with: event)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let dv = dividerView {
            let cursor: NSCursor = isVerticalSplit ? .resizeLeftRight : .resizeUpDown
            addCursorRect(dv.frame.insetBy(dx: -2, dy: -2), cursor: cursor)
        }
    }
}

// MARK: - Help Viewer (Kino-Abspann)

class HelpViewerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class HelpViewer {
    private var window: HelpViewerWindow?
    private var displayLink: Timer?
    private var eventMonitor: Any?
    private var scrollMonitor: Any?
    private var currentSpeed: CGFloat = 0
    private static let baseSpeed: CGFloat = 0.3
    private static let damping: CGFloat = 0.04

    func showCommands(relativeTo parent: NSWindow, commands: [PaletteCommand]) {
        // COMMANDS.md laden und parsen
        let md = Self.findFile("COMMANDS.md")
        if !md.isEmpty {
            let lines = Self.renderMarkdown(md)
            showLines(lines, relativeTo: parent)
            return
        }
        // Fallback wenn keine Datei gefunden
        var l: [StyledLine] = []

        l.append(StyledLine(text: "quickTERMINAL", style: .title))
        l.append(StyledLine(text: "v\(kAppVersion)", style: .badge))
        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "─────────────────────────────────────────────", style: .separator))
        l.append(StyledLine(text: "", style: .normal))

        // Befehlspalette
        l.append(StyledLine(text: "BEFEHLSPALETTE", style: .heading))
        l.append(StyledLine(text: "  Double-tap [Ctrl] to open. Filter by first letter.", style: .alertNote))
        l.append(StyledLine(text: "", style: .normal))

        for cmd in commands {
            let icon: String
            switch cmd.title {
            case "Quit": icon = "\u{23FB}"       // ⏻
            case "New Tab": icon = "\u{2795}"    // ➕
            case "Close Tab": icon = "\u{2716}"  // ✖
            case "Settings": icon = "\u{2699}\u{FE0F}" // ⚙️
            case "Split Vertical": icon = "\u{2502}"   // │
            case "Split Horizontal": icon = "\u{2500}" // ─
            case "Reset Window": icon = "\u{21BA}"     // ↺
            case "Always on Top": icon = "\u{1F4CC}"   // 📌
            case "Auto-Dim": icon = "\u{1F505}"              // 🔅
            case "Clear": icon = "\u{1F9F9}"           // 🧹
            case "Hide": icon = "\u{1F441}"            // 👁
            case "Help": icon = "\u{2753}"             // ❓
            case "Commands": icon = "\u{1F4CB}"        // 📋
            default: icon = "\u{25B8}"                 // ▸
            }
            let shortcut = cmd.shortcut.isEmpty ? "" : "  \u{2022} [\(cmd.shortcut)]"
            l.append(StyledLine(text: "  \(icon)  \(cmd.title)\(shortcut)", style: .listItem))
        }

        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "─────────────────────────────────────────────", style: .separator))
        l.append(StyledLine(text: "", style: .normal))

        // Keyboard Shortcuts
        l.append(StyledLine(text: "KEYBOARD SHORTCUTS", style: .heading))
        l.append(StyledLine(text: "", style: .normal))

        l.append(StyledLine(text: "Window & Tabs", style: .subheading))
        let tabShortcuts: [(String, String)] = [
            ("[Ctrl] + [<]", "Toggle Window"),
            ("[⌘] [T]", "New Tab"),
            ("[⌘] [W]", "Close Tab"),
            ("[⌘] [←] / [→]", "Switch Tabs"),
            ("[⌘] [D]", "Split Vertical"),
            ("[⇧] [⌘] [D]", "Split Horizontal"),
            ("[Alt] + [Tab]", "Switch Split Pane"),
            ("[⌘] [K]", "Clear Scrollback"),
            ("[⌘] [C] / [V]", "Copy / Paste"),
            ("[⌘] [A]", "Select All"),
            ("Double [Ctrl]", "Command Palette"),
        ]
        for (key, desc) in tabShortcuts {
            let pad = String(repeating: " ", count: max(1, 22 - key.count))
            l.append(StyledLine(text: "  \(key)\(pad)\(desc)", style: .tableRow))
        }

        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "Terminal Navigation", style: .subheading))
        let navShortcuts: [(String, String)] = [
            ("[Alt] + [←] / [→]", "Word Back / Forward"),
            ("[Alt] + [Backspace]", "Delete Word"),
            ("[⌘] + [Backspace]", "Kill Line"),
            ("[Ctrl] + [C]", "SIGINT"),
            ("[Ctrl] + [Z]", "SIGTSTP"),
            ("[Ctrl] + [D]", "EOF"),
        ]
        for (key, desc) in navShortcuts {
            let pad = String(repeating: " ", count: max(1, 22 - key.count))
            l.append(StyledLine(text: "  \(key)\(pad)\(desc)", style: .tableRow))
        }

        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "Shells", style: .subheading))
        l.append(StyledLine(text: "  [⌘] [1]  zsh   [⌘] [2]  bash   [⌘] [3]  sh", style: .alertTip))

        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "─────────────────────────────────────────────", style: .separator))
        l.append(StyledLine(text: "", style: .normal))

        // Mouse
        l.append(StyledLine(text: "MOUSE", style: .heading))
        l.append(StyledLine(text: "", style: .normal))
        let mouse: [(String, String, String)] = [
            ("\u{1F5B1}", "Click", "Position Cursor"),
            ("\u{270B}", "Hold + Drag", "Select Text"),
            ("\u{1F4AC}", "Double-Click", "Select Word"),
            ("\u{1F517}", "[⌘] + Click", "Open Hyperlink"),
            ("\u{270C}\u{FE0F}", "[⌥] + Click", "Drag Window"),
            ("\u{1F5DE}", "Scroll Wheel", "Scroll Terminal"),
        ]
        for (icon, action, desc) in mouse {
            let pad = String(repeating: " ", count: max(1, 18 - action.count))
            l.append(StyledLine(text: "  \(icon)  \(action)\(pad)\(desc)", style: .tableRow))
        }

        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "─────────────────────────────────────────────", style: .separator))
        l.append(StyledLine(text: "", style: .normal))
        l.append(StyledLine(text: "  Selection auto-copies to clipboard.", style: .alertTip))
        l.append(StyledLine(text: "  Press [Esc] to dismiss palette.", style: .alertNote))
        l.append(StyledLine(text: "", style: .normal))

        showLines(l, relativeTo: parent)
    }

    func show(relativeTo parent: NSWindow) {
        let readme = Self.findReadme()
        guard !readme.isEmpty else { return }
        let lines = Self.renderMarkdown(readme)
        showLines(lines, relativeTo: parent)
    }

    func showChangelog(relativeTo parent: NSWindow) {
        let md = Self.findFile("CHANGELOG.md")
        guard !md.isEmpty else { return }
        showLines(Self.renderMarkdown(md), relativeTo: parent, winW: 720)
    }

    private func showLines(_ lines: [StyledLine], relativeTo parent: NSWindow, winW: CGFloat = 640) {
        if let existing = window, existing.isVisible { close(); return }

        let winH: CGFloat = 240
        let pad: CGFloat = 20
        let textW = winW - pad * 2

        let font      = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let boldFont  = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        let titleFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let h2Font    = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let minH: CGFloat = 15

        func attrsFor(_ style: LineStyle) -> [NSAttributedString.Key: Any] {
            switch style {
            case .title:          return [.font: titleFont, .foregroundColor: NSColor.white]
            case .heading:        return [.font: h2Font,    .foregroundColor: NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)]
            case .subheading:     return [.font: boldFont,  .foregroundColor: NSColor(calibratedRed: 0.6, green: 0.8, blue: 1.0, alpha: 1.0)]
            case .bold:           return [.font: boldFont,  .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0)]
            case .code:           return [.font: font,      .foregroundColor: NSColor(calibratedRed: 0.5, green: 0.75, blue: 0.45, alpha: 1.0)]
            case .separator:      return [.font: font,      .foregroundColor: NSColor(calibratedWhite: 0.2, alpha: 1.0)]
            case .tableRow:       return [.font: font,      .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0)]
            case .badge:          return [.font: boldFont,  .foregroundColor: NSColor(calibratedRed: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)]
            case .alertImportant: return [.font: boldFont,  .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.35, alpha: 1.0)]
            case .alertNote:      return [.font: font,      .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.6, blue: 1.0, alpha: 1.0)]
            case .alertTip:       return [.font: font,      .foregroundColor: NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.5, alpha: 1.0)]
            case .listItem:       return [.font: font,      .foregroundColor: NSColor(calibratedWhite: 0.6, alpha: 1.0)]
            case .tree:           return [.font: font,      .foregroundColor: NSColor(calibratedRed: 0.5, green: 0.65, blue: 0.8, alpha: 1.0)]
            case .normal:         return [.font: font,      .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0)]
            }
        }

        // Pre-pass: compute each line's actual wrapped height
        let lineHeights: [CGFloat] = lines.map { line in
            guard !line.text.isEmpty else { return minH }
            let as_ = NSAttributedString(string: line.text, attributes: attrsFor(line.style))
            let rect = as_.boundingRect(with: NSSize(width: textW, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
            return max(minH, ceil(rect.height) + 2)
        }
        let totalH = lineHeights.reduce(0, +) + 60

        let px = parent.frame.midX - winW / 2
        let py = parent.frame.midY - winH / 2
        let win = HelpViewerWindow(
            contentRect: NSRect(x: px, y: py, width: winW, height: winH),
            styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.hasShadow = true
        self.window = win

        // Dark Liquid Glass
        let glass = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 8
        glass.layer?.masksToBounds = true
        glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.03, alpha: 0.96).cgColor
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        win.contentView = glass

        let clip = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        glass.addSubview(clip)

        // Content startet oben — ASCII-Art sofort sichtbar
        let content = NSView(frame: NSRect(x: 0, y: -(totalH - winH), width: winW, height: totalH))
        content.wantsLayer = true
        clip.addSubview(content)

        var y = totalH - 30
        for (i, line) in lines.enumerated() {
            let h = lineHeights[i]
            y -= h
            let lbl = NSTextField(labelWithString: "")
            lbl.isEditable = false
            lbl.isBordered = false
            lbl.drawsBackground = false
            lbl.lineBreakMode = .byWordWrapping
            lbl.maximumNumberOfLines = 0
            lbl.attributedStringValue = NSAttributedString(string: line.text, attributes: attrsFor(line.style))
            lbl.frame = NSRect(x: pad, y: y, width: textW, height: h)
            content.addSubview(lbl)
        }

        // Fade-Masken oben und unten
        let fadeH: CGFloat = 50
        let topFade = CAGradientLayer()
        topFade.frame = CGRect(x: 0, y: Double(winH - fadeH), width: Double(winW), height: Double(fadeH))
        topFade.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
        topFade.startPoint = CGPoint(x: 0.5, y: 1.0)
        topFade.endPoint = CGPoint(x: 0.5, y: 0.0)
        clip.layer?.addSublayer(topFade)

        let bottomFade = CAGradientLayer()
        bottomFade.frame = CGRect(x: 0, y: 0, width: Double(winW), height: Double(fadeH))
        bottomFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor]
        bottomFade.startPoint = CGPoint(x: 0.5, y: 1.0)
        bottomFade.endPoint = CGPoint(x: 0.5, y: 0.0)
        clip.layer?.addSublayer(bottomFade)

        // Fenster sanft einblenden
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            win.animator().alphaValue = 1
        }

        // 3 Sekunden Pause, dann langsam scrollen
        let startY = content.frame.origin.y
        self.currentSpeed = Self.baseSpeed
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.window != nil else { return }
            self.displayLink = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                // Sanft zum Basistempo zurückpendeln
                self.currentSpeed += (Self.baseSpeed - self.currentSpeed) * Self.damping
                var f = content.frame
                f.origin.y += self.currentSpeed
                // Nicht über den Anfang zurückscrollen
                if f.origin.y < startY { f.origin.y = startY; self.currentSpeed = 0 }
                content.frame = f
                if f.origin.y >= 0 {
                    self.close()
                }
            }
        }

        // Mausrad beeinflusst Scroll-Geschwindigkeit
        self.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.window?.isVisible == true else { return event }
            // deltaY > 0 = hoch scrollen (schneller), deltaY < 0 = runter (langsamer/rückwärts)
            self.currentSpeed -= event.scrollingDeltaY * 0.15
            return event
        }

        // Escape/Click schließt
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 {
                self?.close(); return nil
            }
            if event.type == .leftMouseDown,
               let helpWin = self?.window,
               let eventWin = event.window, eventWin != helpWin {
                self?.close()
            }
            return event
        }
    }

    func close() {
        displayLink?.invalidate()
        displayLink = nil
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
        if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor); scrollMonitor = nil }
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
        window = nil
    }

    // MARK: - README parsing

    enum LineStyle {
        case title, heading, subheading, bold, code, separator, normal
        case tableRow, badge, alertImportant, alertNote, alertTip
        case listItem, tree
    }
    struct StyledLine { let text: String; let style: LineStyle }

    private static let emojiMap: [String: String] = [
        "art": "\u{1F3A8}", "pencil2": "\u{270F}\u{FE0F}", "flashlight": "\u{1F526}",
        "globe_with_meridians": "\u{1F310}", "triangular_ruler": "\u{1F4D0}",
        "mouse2": "\u{1F401}", "computer_mouse": "\u{1F5B1}", "eyes": "\u{1F440}",
        "clipboard": "\u{1F4CB}", "paperclip": "\u{1F4CE}", "link": "\u{1F517}",
        "framed_picture": "\u{1F5BC}", "keyboard": "\u{2328}\u{FE0F}", "zap": "\u{26A1}",
        "desktop_computer": "\u{1F5A5}", "scroll": "\u{1F4DC}",
        "left_right_arrow": "\u{2194}\u{FE0F}", "id": "\u{1FAAA}",
        "arrows_counterclockwise": "\u{1F504}", "gem": "\u{1F48E}",
        "rocket": "\u{1F680}", "crystal_ball": "\u{1F52E}",
        "arrow_up_small": "\u{1F53C}", "card_index_dividers": "\u{1F5C2}",
        "straight_ruler": "\u{1F4CF}", "mag": "\u{1F50D}", "gear": "\u{2699}\u{FE0F}",
        "floppy_disk": "\u{1F4BE}", "lock": "\u{1F512}", "pushpin": "\u{1F4CC}",
        "electric_plug": "\u{1F50C}",
        "stop_button": "\u{23F9}", "heavy_plus_sign": "\u{2795}",
        "heavy_multiplication_x": "\u{2716}", "arrow_right": "\u{27A1}",
        "arrow_down": "\u{2B07}", "broom": "\u{1F9F9}", "eye": "\u{1F441}",
        "question": "\u{2753}", "hand": "\u{270B}", "point_right": "\u{1F449}",
        "speech_balloon": "\u{1F4AC}", "trackball": "\u{1F5B2}",
    ]

    static func findFile(_ name: String) -> String {
        // Load from embedded binary section first
        let sectionMap = ["COMMANDS.md": "__commands", "CHANGELOG.md": "__changelog"]
        if let sect = sectionMap[name] {
            let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
            var size: UInt = 0
            if let ptr = getsectiondata(header, "__DATA", sect, &size), size > 0 {
                if let s = String(data: Data(bytes: ptr, count: Int(size)), encoding: .utf8), !s.isEmpty {
                    return s
                }
            }
        }
        // Fallback to file on disk
        let exe = ProcessInfo.processInfo.arguments[0]
        let exeDir = (exe as NSString).deletingLastPathComponent
        for path in [
            (exeDir as NSString).appendingPathComponent(name),
            (Bundle.main.bundlePath as NSString).deletingLastPathComponent + "/\(name)",
            FileManager.default.currentDirectoryPath + "/\(name)",
        ] {
            if let c = try? String(contentsOfFile: path, encoding: .utf8), !c.isEmpty { return c }
        }
        return ""
    }

    static func findReadme() -> String {
        // Load from embedded binary section first
        let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
        var size: UInt = 0
        if let ptr = getsectiondata(header, "__DATA", "__readme", &size), size > 0 {
            if let s = String(data: Data(bytes: ptr, count: Int(size)), encoding: .utf8), !s.isEmpty {
                return s
            }
        }
        return findFile("README.md")
    }

    private static func cleanInline(_ text: String) -> String {
        var s = text
        while let a = s.range(of: "<kbd>"), let b = s.range(of: "</kbd>") {
            let inner = s[a.upperBound..<b.lowerBound]
            s = s.replacingCharacters(in: a.lowerBound..<b.upperBound, with: "[\(inner)]")
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "`", with: "")
        if s.hasPrefix("*") && s.hasSuffix("*") && s.count > 2 {
            s = String(s.dropFirst().dropLast())
        }
        for (code, emoji) in emojiMap { s = s.replacingOccurrences(of: ":\(code):", with: emoji) }
        s = s.replacingOccurrences(of: ":[a-z_]+:", with: "", options: .regularExpression)
        return s
    }

    private static func parseBadge(_ line: String) -> String? {
        guard line.contains("img.shields.io/badge/"),
              let urlStart = line.range(of: "/badge/") else { return nil }
        var path = String(line[urlStart.upperBound...])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        if let p = path.firstIndex(of: ")") { path = String(path[..<p]) }
        path = path.replacingOccurrences(of: "%2B", with: "+")
            .replacingOccurrences(of: "%20", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let parts = path.components(separatedBy: "-")
        return parts.count >= 2 ? "\(parts[0]): \(parts[1])" : parts.first
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        guard line.hasPrefix("|") else { return nil }
        let cols = line.components(separatedBy: "|")
            .dropFirst().dropLast()
            .map { cleanInline($0.trimmingCharacters(in: .whitespaces)) }
        return cols.isEmpty ? nil : cols
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cleaned = line.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.isEmpty
    }

    private static func displayWidth(_ s: String) -> Int {
        var w = 0
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v >= 0x1F000 || (v >= 0x2600 && v <= 0x27BF) || (v >= 0x2B50 && v <= 0x2B55)
                || (v >= 0xFE00 && v <= 0xFE0F) { w += 2; continue }
            if v >= 0x1100 && v <= 0x115F { w += 2; continue } // CJK
            if v >= 0x2E80 && v <= 0x9FFF { w += 2; continue }
            if v >= 0xF900 && v <= 0xFAFF { w += 2; continue }
            w += 1
        }
        return w
    }

    private static func padToWidth(_ s: String, width: Int) -> String {
        let dw = displayWidth(s)
        let pad = max(0, width - dw)
        return s + String(repeating: " ", count: pad)
    }

    private static func flushTable(_ rows: inout [[String]], isHeader: inout [Bool], to result: inout [StyledLine]) {
        guard !rows.isEmpty else { return }
        let colCount = rows.map(\.count).max() ?? 0

        // Skip purely decorative columns (only emojis/symbols, max display width ≤ 2)
        var skipCols = Set<Int>()
        for ci in 0..<colCount {
            let maxW = rows.compactMap { ci < $0.count ? displayWidth($0[ci]) : nil }.max() ?? 0
            if maxW <= 2 { skipCols.insert(ci) }
        }
        let activeCols = (0..<colCount).filter { !skipCols.contains($0) }
        guard !activeCols.isEmpty else { rows.removeAll(); isHeader.removeAll(); return }

        // Max content width per active column
        var colWidths = [Int: Int]()
        for ci in activeCols {
            colWidths[ci] = rows.compactMap { ci < $0.count ? displayWidth($0[ci]) : nil }.max() ?? 0
        }
        let lastActive = activeCols.last!

        result.append(StyledLine(text: "", style: .normal))

        for (ri, row) in rows.enumerated() {
            var parts: [String] = []
            for ci in activeCols {
                let cell = ci < row.count ? row[ci] : ""
                // Pad all but last column so the │ separators align
                parts.append(ci == lastActive ? cell : padToWidth(cell, width: colWidths[ci] ?? 0))
            }
            let text = "  " + parts.joined(separator: "  │  ")
            let style: LineStyle = isHeader[ri] ? .subheading : .tableRow
            result.append(StyledLine(text: text, style: style))

            // Thin rule under the header row
            if isHeader[ri] {
                let ruleW = activeCols.dropLast().reduce(0) { $0 + (colWidths[$1] ?? 0) + 5 }
                           + (colWidths[lastActive] ?? 0)
                result.append(StyledLine(text: "  " + String(repeating: "─", count: ruleW + 2), style: .separator))
            }
        }

        result.append(StyledLine(text: "", style: .normal))
        rows.removeAll()
        isHeader.removeAll()
    }

    private static func parseHTMLTableCells(_ html: String) -> [String] {
        var cells: [String] = []
        var s = html
        while let tdStart = s.range(of: "<td") ?? s.range(of: "<th") {
            let isHeader = s[tdStart].first == "<" && s[s.index(after: tdStart.lowerBound)] == "t"
                && s[s.index(tdStart.lowerBound, offsetBy: 2)] == "h"
            // Find end of opening tag
            if let tagEnd = s[tdStart.upperBound...].range(of: ">") {
                let afterTag = tagEnd.upperBound
                // Find closing tag
                let closeTag = isHeader ? "</th>" : "</td>"
                if let close = s[afterTag...].range(of: closeTag) {
                    let content = String(s[afterTag..<close.lowerBound])
                    cells.append(cleanInline(content.trimmingCharacters(in: .whitespacesAndNewlines)))
                    s = String(s[close.upperBound...])
                } else {
                    let content = String(s[afterTag...])
                    cells.append(cleanInline(content.trimmingCharacters(in: .whitespacesAndNewlines)))
                    break
                }
            } else { break }
        }
        return cells
    }

    static func renderMarkdown(_ md: String) -> [StyledLine] {
        var result: [StyledLine] = []
        var inCodeBlock = false
        var alertType: LineStyle? = nil
        var tableRows: [[String]] = []
        var tableIsHeader: [Bool] = []
        var inHTMLTable = false
        var htmlRowBuffer = ""
        var htmlRowIsHeader = false

        for line in md.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Flush pending table if line is not a table row and not in HTML table
            if !trimmed.hasPrefix("|") && !inHTMLTable && !tableRows.isEmpty {
                flushTable(&tableRows, isHeader: &tableIsHeader, to: &result)
            }

            // HTML Table handling
            if trimmed.hasPrefix("<table") { inHTMLTable = true; continue }
            if trimmed.hasPrefix("</table") {
                inHTMLTable = false
                flushTable(&tableRows, isHeader: &tableIsHeader, to: &result)
                continue
            }
            if inHTMLTable {
                if trimmed.hasPrefix("<thead") || trimmed.hasPrefix("</thead") ||
                   trimmed.hasPrefix("<tbody") || trimmed.hasPrefix("</tbody") { continue }
                if trimmed.hasPrefix("<tr") {
                    htmlRowBuffer = ""
                    htmlRowIsHeader = false
                    continue
                }
                if trimmed.hasPrefix("</tr") {
                    let cells = parseHTMLTableCells(htmlRowBuffer)
                    if !cells.isEmpty {
                        let isFirst = tableRows.isEmpty
                        tableRows.append(cells)
                        tableIsHeader.append(isFirst || htmlRowIsHeader)
                    }
                    htmlRowBuffer = ""
                    continue
                }
                if trimmed.hasPrefix("<th") { htmlRowIsHeader = true }
                htmlRowBuffer += " " + trimmed
                continue
            }

            // Andere HTML-Tags überspringen
            if trimmed.hasPrefix("<div") || trimmed.hasPrefix("</div") { continue }
            if trimmed == "<br>" || trimmed == "<br/>" || trimmed == "<br />" { continue }

            // <details> / <summary>
            if trimmed.hasPrefix("<details") { continue }
            if trimmed.hasPrefix("</details") { continue }
            if trimmed.hasPrefix("<summary") {
                let title = cleanInline(trimmed)
                result.append(StyledLine(text: "", style: .normal))
                result.append(StyledLine(text: "\u{25BC} " + title, style: .subheading))
                continue
            }

            // Code-Blöcke
            if trimmed.hasPrefix("```") { inCodeBlock = !inCodeBlock; continue }
            if inCodeBlock {
                result.append(StyledLine(text: "  " + line, style: .code))
                continue
            }

            // Badges (shields.io)
            if trimmed.hasPrefix("![") {
                var badges: [String] = []
                var remaining = trimmed
                while remaining.hasPrefix("![") {
                    if let badge = parseBadge(remaining) { badges.append(badge) }
                    if let end = remaining.range(of: ")") {
                        remaining = String(remaining[end.upperBound...]).trimmingCharacters(in: .whitespaces)
                    } else { break }
                }
                if !badges.isEmpty {
                    result.append(StyledLine(text: badges.joined(separator: "  \u{2022}  "), style: .badge))
                }
                continue
            }

            // Alert-Boxen
            if trimmed.hasPrefix("> [!IMPORTANT]") { alertType = .alertImportant; continue }
            if trimmed.hasPrefix("> [!NOTE]") { alertType = .alertNote; continue }
            if trimmed.hasPrefix("> [!TIP]") { alertType = .alertTip; continue }
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst(trimmed.hasPrefix("> ") ? 2 : 1))
                if content.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if let alert = alertType {
                    result.append(StyledLine(text: "  " + cleanInline(content), style: alert))
                } else {
                    result.append(StyledLine(text: "  " + cleanInline(content), style: .bold))
                }
                continue
            }
            if alertType != nil { alertType = nil }

            // Headings
            if trimmed.hasPrefix("# ") {
                result.append(StyledLine(text: cleanInline(String(trimmed.dropFirst(2))), style: .title))
                continue
            }
            if trimmed.hasPrefix("## ") {
                result.append(StyledLine(text: "", style: .normal))
                result.append(StyledLine(text: cleanInline(String(trimmed.dropFirst(3))).uppercased(), style: .heading))
                continue
            }
            if trimmed.hasPrefix("### ") {
                result.append(StyledLine(text: "", style: .normal))
                result.append(StyledLine(text: cleanInline(String(trimmed.dropFirst(4))), style: .subheading))
                continue
            }

            // Trennlinien
            if trimmed.hasPrefix("---") {
                result.append(StyledLine(text: "─────────────────────────────────────────────", style: .separator))
                continue
            }

            // Tabellen — sammeln und am Ende ausgerichtet ausgeben
            if trimmed.hasPrefix("|") {
                if isTableSeparator(trimmed) { continue }
                if let cols = parseTableRow(trimmed) {
                    let isFirst = tableRows.isEmpty
                    tableRows.append(cols)
                    tableIsHeader.append(isFirst)
                }
                continue
            }

            // Listen
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(StyledLine(text: "  \u{2022} " + cleanInline(String(trimmed.dropFirst(2))), style: .listItem))
                continue
            }

            // Baum-Diagramm
            if trimmed.hasPrefix("│") || trimmed.hasPrefix("├") || trimmed.hasPrefix("└") || trimmed.hasPrefix("┌") {
                result.append(StyledLine(text: "  " + trimmed, style: .tree))
                continue
            }

            if trimmed.isEmpty { result.append(StyledLine(text: "", style: .normal)); continue }
            result.append(StyledLine(text: cleanInline(trimmed), style: .normal))
        }
        // Flush any remaining table
        if !tableRows.isEmpty {
            flushTable(&tableRows, isHeader: &tableIsHeader, to: &result)
        }
        return result
    }
}

// MARK: - Command Palette

struct PaletteCommand {
    let title: String
    let shortcut: String   // keyboard hint shown on right
    let action: () -> Void
}

class CommandPaletteView: NSView, NSTextFieldDelegate {
    private let searchField = NSTextField()
    let nameLabel = NSView()
    private let badgeContainer = NSView()
    private var commands: [PaletteCommand] = []
    private var filtered: [PaletteCommand] = []
    private var selectedIndex = 0
    private var badgeViews: [NSView] = []
    private var confirmAction: (() -> Void)?
    private var inputAction: ((String) -> Void)?
    private var marqueeLabel: NSTextField?
    private var marqueeTimer: Timer?
    private var marqueeOffset: CGFloat = 0
    private var marqueeTextWidth: CGFloat = 0
    private var marqueeFullText: String = ""
    static let paletteW: CGFloat = 260
    private static let inputH: CGFloat = 28
    private static let badgeH: CGFloat = 20
    private static let badgeGap: CGFloat = 5
    private static let maxBadges = 20
    private static let maxRows = 4
    private static let rowGap: CGFloat = 4

    // Dezente Farben für Badges
    private static let badgeColors: [NSColor] = [
        NSColor(calibratedRed: 0.45, green: 0.55, blue: 0.85, alpha: 0.2),
        NSColor(calibratedRed: 0.50, green: 0.75, blue: 0.50, alpha: 0.2),
        NSColor(calibratedRed: 0.80, green: 0.55, blue: 0.40, alpha: 0.2),
        NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.70, alpha: 0.2),
        NSColor(calibratedRed: 0.45, green: 0.70, blue: 0.70, alpha: 0.2),
        NSColor(calibratedRed: 0.75, green: 0.65, blue: 0.40, alpha: 0.2),
        NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.75, alpha: 0.2),
        NSColor(calibratedRed: 0.65, green: 0.50, blue: 0.50, alpha: 0.2),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.88).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.25, alpha: 1.0).cgColor

        searchField.placeholderString = ""
        searchField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        searchField.textColor = .white
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.cell?.focusRingType = .none
        (searchField.cell as? NSTextFieldCell)?.drawsBackground = false
        searchField.frame = NSRect(x: 10, y: 8, width: Self.paletteW - 20, height: Self.inputH - 12)
        addSubview(searchField)

        // quickBAR name label — lives outside palette, positioned below
        let labelW: CGFloat = Self.paletteW * 0.8
        let labelH: CGFloat = 20
        nameLabel.wantsLayer = true
        nameLabel.layer?.cornerRadius = 3
        nameLabel.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 0.63).cgColor
        nameLabel.frame = NSRect(x: 0, y: 0, width: labelW, height: labelH)

        let text = "q u i c k B A R"
        let tf = NSTextField(labelWithString: text)
        let baseFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let italicDesc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        tf.font = NSFont(descriptor: italicDesc, size: 10) ?? baseFont
        tf.textColor = NSColor.black
        tf.shadow = {
            let s = NSShadow()
            s.shadowOffset = NSSize(width: 0, height: -1)
            s.shadowBlurRadius = 0
            s.shadowColor = NSColor(calibratedWhite: 1.0, alpha: 0.17)
            return s
        }()
        tf.alignment = .center
        tf.frame = NSRect(x: 0, y: -3, width: labelW, height: labelH)
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.isSelectable = false
        nameLabel.addSubview(tf)

        // Badge container lives outside this view, directly on the window content view
        badgeContainer.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func setup(commands: [PaletteCommand]) {
        self.commands = commands
        self.filtered = []
        self.selectedIndex = 0
        searchField.stringValue = ""
    }

    func activate() {
        // Pre-configure field editor BEFORE it becomes first responder to prevent white flash
        if let editor = window?.fieldEditor(true, for: searchField) as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = NSColor(calibratedWhite: 0.25, alpha: 1.0)
        }
        window?.makeFirstResponder(searchField)
    }
    static func baseHeight() -> CGFloat { inputH }

    private func updateBadges() {
        badgeContainer.subviews.forEach { $0.removeFromSuperview() }
        badgeViews.removeAll()

        let visible = min(filtered.count, Self.maxBadges)
        if visible == 0 {
            badgeContainer.removeFromSuperview()
            positionSelf()
            return
        }

        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let padX: CGFloat = 10
        let maxLineW = Self.paletteW
        let borderGray = NSColor(calibratedWhite: 0.25, alpha: 1.0).cgColor

        // Measure badge widths
        var badgeWidths: [CGFloat] = []
        for i in 0..<visible {
            let textW = (filtered[i].title as NSString).size(withAttributes: [.font: font]).width
            badgeWidths.append(ceil(textW) + padX * 2)
        }

        // Flow-Layout: Zeilen aufteilen nach Spotlight-Breite
        var rows: [[Int]] = [[]]
        var rowW: CGFloat = 0
        for i in 0..<visible {
            let needed = badgeWidths[i] + (rows[rows.count - 1].isEmpty ? 0 : Self.badgeGap)
            if !rows[rows.count - 1].isEmpty && rowW + needed > maxLineW {
                if rows.count >= Self.maxRows { break }
                rows.append([])
                rowW = 0
            }
            rows[rows.count - 1].append(i)
            rowW += badgeWidths[i] + (rows[rows.count - 1].count > 1 ? Self.badgeGap : 0)
        }

        let totalH = Self.badgeH * CGFloat(rows.count) + Self.rowGap * CGFloat(rows.count - 1)
        guard let sv = superview else { return }
        let containerY = frame.maxY + 6
        badgeContainer.frame = NSRect(x: 0, y: containerY,
                                       width: sv.bounds.width, height: totalH)

        let textH = ceil(font.ascender - font.descender)
        let textY = round((Self.badgeH - textH) / 2)

        for (rowIdx, row) in rows.enumerated() {
            let lineW = row.map { badgeWidths[$0] }.reduce(0, +) + Self.badgeGap * CGFloat(max(row.count - 1, 0))
            var x = (sv.bounds.width - lineW) / 2
            let y = (Self.badgeH + Self.rowGap) * CGFloat(rowIdx)

            for i in row {
                let title = filtered[i].title
                let sel = i == selectedIndex
                let bw = badgeWidths[i]
                let colorIdx = title.hashValue & 0x7FFFFFFF
                let color = Self.badgeColors[colorIdx % Self.badgeColors.count]

                let badge = NSView(frame: NSRect(x: x, y: y, width: bw, height: Self.badgeH))
                badge.wantsLayer = true
                badge.layer?.cornerRadius = 4
                badge.layer?.borderWidth = 1

                if sel {
                    badge.layer?.backgroundColor = color.withAlphaComponent(0.45).cgColor
                    badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
                } else {
                    badge.layer?.backgroundColor = color.cgColor
                    badge.layer?.borderColor = borderGray
                }

                let lbl = NSTextField(labelWithString: title)
                lbl.font = font
                lbl.alignment = .center
                lbl.textColor = sel ? .white : NSColor(calibratedWhite: 0.72, alpha: 1.0)
                lbl.frame = NSRect(x: 0, y: textY, width: bw, height: textH)
                badge.addSubview(lbl)

                let tap = NSClickGestureRecognizer(target: self, action: #selector(badgeTapped(_:)))
                badge.addGestureRecognizer(tap)

                badgeContainer.addSubview(badge)
                badgeViews.append(badge)
                x += bw + Self.badgeGap
            }
        }

        if badgeContainer.superview == nil { sv.addSubview(badgeContainer) }
        badgeContainer.layer?.zPosition = CGFloat.greatestFiniteMagnitude
    }

    private func positionSelf() {
        guard let sv = superview else { return }
        frame = NSRect(x: (sv.bounds.width - Self.paletteW) / 2,
                       y: (sv.bounds.height - Self.inputH) / 2,
                       width: Self.paletteW, height: Self.inputH)
        repositionNameLabel()
        repositionBadges()
    }

    func repositionNameLabel() {
        guard let sv = superview else { return }
        if nameLabel.superview == nil { sv.addSubview(nameLabel) }
        nameLabel.alphaValue = alphaValue
        let nlW = nameLabel.frame.width
        let nlH = nameLabel.frame.height
        nameLabel.frame = NSRect(x: frame.midX - nlW / 2,
                                  y: frame.origin.y - nlH + 1,
                                  width: nlW, height: nlH)
        nameLabel.layer?.zPosition = CGFloat.greatestFiniteMagnitude
    }

    func repositionBadges() {
        guard badgeContainer.superview != nil, let sv = superview else { return }
        var f = badgeContainer.frame
        f.origin.y = frame.maxY + 6
        f.size.width = sv.bounds.width
        badgeContainer.frame = f
        var rows: [[NSView]] = [[]]
        var rowY: CGFloat = -1
        for badge in badgeViews {
            if rowY < 0 { rowY = badge.frame.origin.y }
            if badge.frame.origin.y != rowY {
                rows.append([])
                rowY = badge.frame.origin.y
            }
            rows[rows.count - 1].append(badge)
        }
        for row in rows {
            let lineW = row.map { $0.frame.width }.reduce(0, +) + Self.badgeGap * CGFloat(max(row.count - 1, 0))
            var x = (sv.bounds.width - lineW) / 2
            for badge in row {
                var bf = badge.frame
                bf.origin.x = x
                badge.frame = bf
                x += bf.width + Self.badgeGap
            }
        }
    }

    @objc private func badgeTapped(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view, let idx = badgeViews.firstIndex(of: view) else { return }
        if idx < filtered.count { filtered[idx].action(); if confirmAction == nil && inputAction == nil { dismiss() } }
    }

    func dismiss() {
        stopMarquee()
        let appDelegate = NSApp.delegate as? AppDelegate
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0
            self.badgeContainer.animator().alphaValue = 0
            self.nameLabel.animator().alphaValue = 0
        }, completionHandler: {
            self.badgeContainer.removeFromSuperview()
            self.nameLabel.removeFromSuperview()
            self.removeFromSuperview()
            appDelegate?.commandPalette = nil
            appDelegate?.activateAfterSnap()
        })
    }

    func showConfirm(prompt: String, action: @escaping () -> Void) {
        confirmAction = action
        filtered = []
        selectedIndex = 0
        updateBadges()
        searchField.stringValue = ""
        searchField.placeholderString = ""
        startMarquee(prompt)
    }

    func showInput(prompt: String, action: @escaping (String) -> Void) {
        inputAction = action
        filtered = []
        selectedIndex = 0
        updateBadges()
        searchField.stringValue = ""
        searchField.placeholderString = ""
        startMarquee(prompt)
    }

    private func startMarquee(_ text: String) {
        stopMarquee()
        marqueeFullText = text
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        marqueeTextWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let fieldW = searchField.frame.width

        // If text fits, just show as static placeholder
        if marqueeTextWidth <= fieldW {
            searchField.placeholderString = text
            return
        }

        let lbl = NSTextField(labelWithString: text)
        lbl.font = font
        lbl.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
        lbl.isEditable = false
        lbl.isBordered = false
        lbl.drawsBackground = false
        lbl.sizeToFit()

        // Clip container = searchField frame
        let clip = NSView(frame: searchField.frame)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        lbl.frame.origin = NSPoint(x: 0, y: 0)
        clip.addSubview(lbl)
        addSubview(clip)
        marqueeLabel = lbl

        marqueeOffset = 0
        let gap: CGFloat = 40
        let totalScroll = marqueeTextWidth + gap - fieldW
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, let lbl = self.marqueeLabel else { return }
            self.marqueeOffset += 0.6
            if self.marqueeOffset > totalScroll + gap {
                self.marqueeOffset = -fieldW * 0.3
            }
            lbl.frame.origin.x = -self.marqueeOffset
        }
    }

    private func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        marqueeLabel?.superview?.removeFromSuperview()
        marqueeLabel = nil
        marqueeFullText = ""
    }

    func controlTextDidChange(_ obj: Notification) {
        if marqueeLabel != nil { stopMarquee() }
        let q = searchField.stringValue.lowercased()
        if confirmAction != nil {
            let last = q.last
            if last == "y" {
                let action = confirmAction!
                confirmAction = nil
                searchField.placeholderString = ""
                action()
                dismiss()
            } else if last == "n" {
                confirmAction = nil
                searchField.placeholderString = ""
                dismiss()
            } else {
                searchField.stringValue = ""
            }
            return
        }
        if inputAction != nil { return }
        filtered = q.isEmpty ? [] : commands.filter { $0.title.lowercased().hasPrefix(q) }
        selectedIndex = 0
        updateBadges()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if confirmAction != nil {
            if event.keyCode == 53 { confirmAction = nil; searchField.placeholderString = ""; dismiss(); return true }
            return super.performKeyEquivalent(with: event)
        }
        if inputAction != nil {
            if event.keyCode == 53 { inputAction = nil; searchField.placeholderString = ""; dismiss(); return true }
            if event.keyCode == 36 || event.keyCode == 76 {
                let val = searchField.stringValue.trimmingCharacters(in: .whitespaces)
                if !val.isEmpty {
                    let action = inputAction!
                    inputAction = nil
                    searchField.placeholderString = ""
                    action(val)
                    dismiss()
                }
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
        switch event.keyCode {
        case 53: dismiss(); return true
        case 36, 76:
            if selectedIndex < filtered.count { filtered[selectedIndex].action(); if confirmAction == nil && inputAction == nil { dismiss() } }
            return true
        case 124: // Right arrow
            if !filtered.isEmpty && selectedIndex < min(filtered.count, Self.maxBadges) - 1 {
                selectedIndex += 1; updateBadges()
            }
            return true
        case 123: // Left arrow
            if selectedIndex > 0 { selectedIndex -= 1; updateBadges() }
            return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - Update Checker

struct GitHubRelease {
    let tagName: String
    let downloadURL: URL
    let checksumURL: URL?  // optional .sha256 sidecar for integrity verification
}

class UpdateChecker {
    private let allowedUpdateHosts = ["github.com", "objects.githubusercontent.com"]
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    func checkForUpdate(completion: @escaping (Result<GitHubRelease?, Error>) -> Void) {
        let url = URL(string: "https://api.github.com/repos/LEVOGNE/quickTerminal/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "UpdateChecker", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(httpResp.statusCode)"])))
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "UpdateChecker", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let firstAsset = assets.first(where: {
                      ($0["name"] as? String)?.hasSuffix(".zip") == true
                  }),
                  let urlStr = firstAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: urlStr)
            else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "UpdateChecker", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse release data from server"])))
                }
                return
            }

            // Look for a .sha256 sidecar asset (same name as zip + ".sha256")
            let zipName = firstAsset["name"] as? String ?? ""
            let sha256Asset = assets.first(where: { ($0["name"] as? String) == zipName + ".sha256" })
            let checksumURL = (sha256Asset?["browser_download_url"] as? String).flatMap { URL(string: $0) }

            if isNewerVersion(remote: tagName, local: kAppVersion) {
                DispatchQueue.main.async {
                    completion(.success(GitHubRelease(tagName: tagName, downloadURL: downloadURL, checksumURL: checksumURL)))
                }
            } else {
                DispatchQueue.main.async { completion(.success(nil)) }
            }
        }.resume()
    }

    func downloadAndInstall(release: GitHubRelease,
                            onProgress: @escaping (Double) -> Void,
                            onComplete: @escaping (Result<Void, Error>) -> Void) {
        // Require .app bundle for install — raw dev binaries can detect updates but not self-replace
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            onComplete(.failure(NSError(domain: "UpdateChecker", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Auto-install requires the .app bundle. Copy quickTerminal.app to /Applications first."])))
            return
        }
        // [P1] Verify HTTPS scheme — reject plain HTTP downloads
        guard release.downloadURL.scheme == "https" else {
            onComplete(.failure(NSError(domain: "UpdateChecker", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Download URL must use HTTPS"])))
            return
        }
        // [P0] Verify download URL is from a trusted GitHub host
        let host = release.downloadURL.host ?? ""
        guard allowedUpdateHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            onComplete(.failure(NSError(domain: "UpdateChecker", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Download URL from unexpected host: \(host)"])))
            return
        }
        let task = URLSession.shared.downloadTask(with: release.downloadURL) { [weak self] tmpURL, _, error in
            self?.progressObservation = nil
            if let error = error {
                DispatchQueue.main.async { onComplete(.failure(error)) }
                return
            }
            guard let tmpURL = tmpURL else {
                DispatchQueue.main.async {
                    onComplete(.failure(NSError(domain: "UpdateChecker", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: "Download failed"])))
                }
                return
            }
            // Copy to persistent temp location (URLSession tmp file gets deleted)
            let zipPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("quickTerminal_update_\(UUID().uuidString).zip")
            do {
                try? FileManager.default.removeItem(at: zipPath)
                try FileManager.default.copyItem(at: tmpURL, to: zipPath)
            } catch {
                DispatchQueue.main.async { onComplete(.failure(error)) }
                return
            }

            // [P0] If a checksum sidecar was provided, verify before install
            // [P2] Validate checksumURL with same HTTPS + host allowlist as downloadURL
            let trustedHosts = self?.allowedUpdateHosts ?? []
            let validChecksumURL: URL? = release.checksumURL.flatMap { url in
                let host = url.host ?? ""
                guard url.scheme == "https",
                      trustedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
                else { return nil }
                return url
            }
            if let checksumURL = validChecksumURL {
                self?.verifyChecksum(zipPath: zipPath, checksumURL: checksumURL) { matches in
                    guard matches else {
                        DispatchQueue.main.async {
                            onComplete(.failure(NSError(domain: "UpdateChecker", code: 15,
                                userInfo: [NSLocalizedDescriptionKey: "SHA256 checksum mismatch — download may be corrupt or tampered"])))
                        }
                        try? FileManager.default.removeItem(at: zipPath)
                        return
                    }
                    DispatchQueue.global(qos: .utility).async {
                        self?.installUpdate(from: zipPath, completion: onComplete)
                    }
                }
            } else {
                // No checksum file in release — proceed without hash verification
                DispatchQueue.global(qos: .utility).async {
                    self?.installUpdate(from: zipPath, completion: onComplete)
                }
            }
        }

        progressObservation = task.observe(\.countOfBytesReceived) { t, _ in
            guard t.countOfBytesExpectedToReceive > 0 else { return }
            let pct = Double(t.countOfBytesReceived) / Double(t.countOfBytesExpectedToReceive)
            DispatchQueue.main.async { onProgress(pct) }
        }

        downloadTask = task
        task.resume()
    }

    private func installUpdate(from zipPath: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        // Guard: semaphore below deadlocks if called from main — make it a hard crash instead of a silent hang
        precondition(!Thread.isMainThread, "installUpdate must not run on the main thread")
        // [P1] installUpdate runs on a background thread — dispatch all completion calls back to main
        let complete: (Result<Void, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory.appendingPathComponent("quickTerminal_extract_\(UUID().uuidString)")

        // 1. Extract with ditto
        let dittoProc = Process()
        dittoProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        dittoProc.arguments = ["-xk", zipPath.path, extractDir.path]
        do {
            try dittoProc.run()
            dittoProc.waitUntilExit()
        } catch {
            complete(.failure(NSError(domain: "UpdateChecker", code: 2,
                                     userInfo: [NSLocalizedDescriptionKey: "Failed to extract: \(error.localizedDescription)"])))
            return
        }
        guard dittoProc.terminationStatus == 0 else {
            complete(.failure(NSError(domain: "UpdateChecker", code: 3,
                                     userInfo: [NSLocalizedDescriptionKey: "ditto failed with exit code \(dittoProc.terminationStatus)"])))
            return
        }

        // 2. Find .app in extracted contents
        guard let appBundle = findAppBundle(in: extractDir) else {
            complete(.failure(NSError(domain: "UpdateChecker", code: 4,
                                     userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in archive"])))
            try? fm.removeItem(at: extractDir)
            return
        }

        // Verify executable exists
        let execPath = appBundle.appendingPathComponent("Contents/MacOS/quickTerminal")
        guard fm.isExecutableFile(atPath: execPath.path) else {
            complete(.failure(NSError(domain: "UpdateChecker", code: 5,
                                     userInfo: [NSLocalizedDescriptionKey: "Invalid app bundle — no executable"])))
            try? fm.removeItem(at: extractDir)
            return
        }

        // [P0] Verify bundle identifier matches current app
        let infoPlistURL = appBundle.appendingPathComponent("Contents/Info.plist")
        if let plist = NSDictionary(contentsOf: infoPlistURL),
           let newBundleId = plist["CFBundleIdentifier"] as? String,
           let currentBundleId = Bundle.main.bundleIdentifier,
           !currentBundleId.isEmpty, newBundleId != currentBundleId {
            complete(.failure(NSError(domain: "UpdateChecker", code: 9,
                                     userInfo: [NSLocalizedDescriptionKey: "Bundle identifier mismatch — aborting update"])))
            try? fm.removeItem(at: extractDir)
            return
        }

        // 3. Current app path
        let currentAppPath = Bundle.main.bundlePath
        let currentAppURL = URL(fileURLWithPath: currentAppPath)
        let parentDir = currentAppURL.deletingLastPathComponent()

        // Check write permission
        guard fm.isWritableFile(atPath: parentDir.path) else {
            complete(.failure(NSError(domain: "UpdateChecker", code: 6,
                                     userInfo: [NSLocalizedDescriptionKey: "No write permission at \(parentDir.path)"])))
            try? fm.removeItem(at: extractDir)
            return
        }

        // 4. Move old .app to temp (rollback backup)
        let backupPath = fm.temporaryDirectory.appendingPathComponent("quickTerminal_backup_\(UUID().uuidString).app")
        do {
            try fm.moveItem(at: currentAppURL, to: backupPath)
        } catch {
            complete(.failure(NSError(domain: "UpdateChecker", code: 7,
                                     userInfo: [NSLocalizedDescriptionKey: "Failed to move old app: \(error.localizedDescription)"])))
            try? fm.removeItem(at: extractDir)
            return
        }

        // 5. Copy new .app to original path
        do {
            try fm.copyItem(at: appBundle, to: currentAppURL)
        } catch {
            // Rollback
            try? fm.moveItem(at: backupPath, to: currentAppURL)
            complete(.failure(NSError(domain: "UpdateChecker", code: 8,
                                     userInfo: [NSLocalizedDescriptionKey: "Failed to install update, rolled back: \(error.localizedDescription)"])))
            try? fm.removeItem(at: extractDir)
            return
        }

        // 6. Remove quarantine
        let xattrProc = Process()
        xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProc.arguments = ["-cr", currentAppPath]
        try? xattrProc.run()
        xattrProc.waitUntilExit()

        // Partial cleanup — backup kept until relaunch succeeds (see below)
        try? fm.removeItem(at: extractDir)
        try? fm.removeItem(at: zipPath)

        // 7. Save session before relaunch (semaphore avoids main.sync deadlock risk)
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            if let delegate = NSApp.delegate as? AppDelegate { delegate.saveSession() }
            sema.signal()
        }
        sema.wait()

        complete(.success(()))

        // 9. Show SUCCESS toast for 3s, then relaunch + exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // [P2] For .app bundles: use `open` directly and verify exit code before
            //      deleting backup. `open` returns 0 quickly once the app is queued.
            if currentAppPath.hasSuffix(".app") {
                let openProc = Process()
                openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                openProc.arguments = [currentAppPath]
                do {
                    try openProc.run()
                    openProc.waitUntilExit()  // open exits quickly (≈ launch queued)
                    guard openProc.terminationStatus == 0 else {
                        // open returned non-zero — relaunch failed; show error so user isn't left hanging
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.showGenericToast(badge: "ERROR", text: "Relaunch failed — please restart manually",
                                                      badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0),
                                                      dismissAfter: 8.0)
                        }
                        return
                    }
                    try? fm.removeItem(at: backupPath)
                    exit(0)
                } catch {
                    // open() threw — relaunch failed; show error so user isn't left hanging
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.showGenericToast(badge: "ERROR", text: "Relaunch failed — please restart manually",
                                                  badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0),
                                                  dismissAfter: 8.0)
                    }
                }
            } else {
                // Dev binary: shell wrapper
                let shellProc = Process()
                shellProc.executableURL = URL(fileURLWithPath: "/bin/sh")
                shellProc.arguments = ["-c", "sleep 0.3; \"\(ProcessInfo.processInfo.arguments[0])\""]
                do {
                    try shellProc.run()
                    try? fm.removeItem(at: backupPath)
                    exit(0)
                } catch {
                    return
                }
            }
        }
    }

    /// Downloads the .sha256 sidecar and verifies the ZIP matches.
    /// Trust-anchor note: ZIP + SHA256 both come from the same GitHub release. A compromised
    /// GitHub account could manipulate both. The next hardening step is Apple code-signing
    /// (codesign --verify) or hosting the hash on a separate, independently controlled endpoint.
    private func verifyChecksum(zipPath: URL, checksumURL: URL, completion: @escaping (Bool) -> Void) {
        URLSession.shared.dataTask(with: checksumURL) { data, _, _ in
            guard let data = data,
                  let checksumStr = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  let expectedHash = checksumStr.components(separatedBy: CharacterSet.whitespaces).first,
                  !expectedHash.isEmpty
            else {
                completion(false)
                return
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
            proc.arguments = ["-a", "256", zipPath.path]
            let pipe = Pipe()
            proc.standardOutput = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { completion(false); return }
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                let actualHash = String(data: output, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: CharacterSet.whitespaces)
                    .first ?? ""
                completion(actualHash.lowercased() == expectedHash.lowercased())
            } catch {
                completion(false)
            }
        }.resume()
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles]) else { return nil }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "app" {
                let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if vals?.isDirectory == true { return fileURL }
            }
        }
        return nil
    }
}

// MARK: - Onboarding Panel

class OnboardingPanel: NSPanel {
    private var player: AVPlayer?
    private var playerView: AVPlayerView!
    private var endObserver: Any?

    static func showIfNeeded(relativeTo parentWindow: NSWindow? = nil) {
        guard !UserDefaults.standard.bool(forKey: "onboardingVideoShown") else { return }
        guard let url = Bundle.main.url(forResource: "quickTERMINAL", withExtension: "mp4") else { return }
        let panel = OnboardingPanel(url: url, relativeTo: parentWindow)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(url: URL, relativeTo parentWindow: NSWindow? = nil) {
        let w: CGFloat = 480
        let h: CGFloat = 300
        // Center on parent window if available, otherwise main screen
        let origin: NSPoint
        if let pw = parentWindow {
            let pf = pw.frame
            origin = NSPoint(x: pf.midX - w / 2, y: pf.midY - h / 2)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            origin = NSPoint(x: screen.midX - w / 2, y: screen.midY - h / 2)
        }
        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .modalPanel
        backgroundColor = .black
        isOpaque = true

        // Player
        player = AVPlayer(url: url)
        playerView = AVPlayerView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.autoresizingMask = [.width, .height]
        contentView?.addSubview(playerView)

        // Skip button (top-right)
        let skipBtn = NSButton(frame: NSRect(x: w - 68, y: h - 28, width: 60, height: 22))
        skipBtn.title = "✕ Skip"
        skipBtn.bezelStyle = .inline
        skipBtn.isBordered = false
        skipBtn.font = .systemFont(ofSize: 11)
        skipBtn.contentTintColor = NSColor(calibratedWhite: 0.6, alpha: 1.0)
        skipBtn.autoresizingMask = [.minXMargin, .minYMargin]
        skipBtn.target = self
        skipBtn.action = #selector(dismiss)
        contentView?.addSubview(skipBtn)

        // Auto-close when video ends
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in self?.dismiss() }

        player?.play()
    }

    @objc private func dismiss() {
        UserDefaults.standard.set(true, forKey: "onboardingVideoShown")
        player?.pause()
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        close()
        // Show terminal if not already visible
        if let delegate = NSApp.delegate as? AppDelegate, !delegate.window.isVisible {
            delegate.showWindowAnimated()
        }
    }

    deinit {
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - Text Editor

enum TabType { case terminal, editor }

// ── Syntax Highlighting ────────────────────────────────────────────────────

enum TokenType {
    case keyword, string, comment, number, operator_, type_, attribute, plain
}

struct SyntaxToken {
    let range: NSRange
    let type: TokenType
}

enum EditorLanguage: String {
    case swift, json, yaml, javascript, typescript, python
    case shell, markdown, html, css, go, rust, ruby, xml, plain
}

struct SyntaxHighlighter {

    // ── Language detection ─────────────────────────────────────────────────
    static func detectLanguage(from url: URL?) -> EditorLanguage {
        guard let ext = url?.pathExtension.lowercased() else { return .plain }
        switch ext {
        case "swift":               return .swift
        case "json":                return .json
        case "yaml", "yml":         return .yaml
        case "js", "mjs":           return .javascript
        case "ts", "tsx":           return .typescript
        case "py":                  return .python
        case "sh", "bash", "zsh":   return .shell
        case "md", "markdown":      return .markdown
        case "html", "htm":         return .html
        case "css", "scss", "less": return .css
        case "go":                  return .go
        case "rs":                  return .rust
        case "rb":                  return .ruby
        case "xml", "plist":        return .xml
        default:                    return .plain
        }
    }

    // ── Tokenize ───────────────────────────────────────────────────────────
    static func tokenize(source: String, language: EditorLanguage) -> [SyntaxToken] {
        switch language {
        case .swift:      return tokenizeSwift(source)
        case .json:       return tokenizeJSON(source)
        case .yaml:       return tokenizeYAML(source)
        case .javascript, .typescript: return tokenizeJS(source)
        case .python:     return tokenizePython(source)
        case .shell:      return tokenizeShell(source)
        case .markdown:   return tokenizeMarkdown(source)
        case .html:       return tokenizeHTML(source)
        case .css:        return tokenizeCSS(source)
        case .go:         return tokenizeGo(source)
        case .rust:       return tokenizeRust(source)
        case .ruby:       return tokenizeRuby(source)
        case .xml:        return tokenizeHTML(source)
        case .plain:      return []
        }
    }

    // ── Helper: cached NSRegularExpression ────────────────────────────────
    private static var rxCache: [String: NSRegularExpression] = [:]
    private static let rxCacheLock = NSLock()

    private static func cachedRegex(pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue):\(pattern)"
        rxCacheLock.lock()
        defer { rxCacheLock.unlock() }
        if let cached = rxCache[key] { return cached }
        guard let rx = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        rxCache[key] = rx
        return rx
    }

    // ── Helper: apply regex patterns ───────────────────────────────────────
    private static func tokens(source: String,
                                patterns: [(String, TokenType)],
                                options: NSRegularExpression.Options = []) -> [SyntaxToken] {
        var result: [SyntaxToken] = []
        let ns = source as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        for (pattern, type_) in patterns {
            guard let rx = cachedRegex(pattern: pattern, options: options) else { continue }
            let matches = rx.matches(in: source, range: fullRange)
            for m in matches {
                let r = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
                if r.location != NSNotFound { result.append(SyntaxToken(range: r, type: type_)) }
            }
        }
        result.sort { $0.range.location < $1.range.location }
        var clean: [SyntaxToken] = []
        var cursor = 0
        for tok in result {
            if tok.range.location >= cursor {
                clean.append(tok)
                cursor = tok.range.location + tok.range.length
            }
        }
        return clean
    }

    private static func tokenizeSwift(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(func|class|struct|enum|protocol|extension|var|let|if|else|guard|return|for|while|in|import|typealias|associatedtype|where|switch|case|default|break|continue|throw|throws|rethrows|try|catch|defer|do|init|deinit|subscript|override|final|static|mutating|nonmutating|open|public|internal|fileprivate|private|weak|unowned|lazy|indirect|as|is|nil|true|false|self|Self|super|any|some|async|await|actor|nonisolated|isolated)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("\"\"\"[\\s\\S]*?\"\"\"",              .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("#?\"(?:[^\"\\\\]|\\\\.)*\"",          .string),
            (kw,                                    .keyword),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("@\\w+",                               .attribute),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
            ("[+\\-*/=<>!&|^~%?:,;.()\\[\\]{}]+",  .operator_),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizeJSON(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("\"(?:[^\"\\\\]|\\\\.)*\"\\s*(?=:)",   .keyword),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("\\b(true|false|null)\\b",             .keyword),
            ("\\b-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\\b", .number),
            ("[{}\\[\\]:,]",                        .operator_),
        ])
    }

    private static func tokenizeYAML(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("^\\s*([\\w-]+)\\s*(?=:)",            .keyword),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            ("\\b(true|false|null|yes|no)\\b",     .keyword),
            ("\\b-?[0-9]+(?:\\.[0-9]+)?\\b",       .number),
            ("^---",                                .operator_),
        ], options: [.anchorsMatchLines])
    }

    private static func tokenizeJS(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(function|const|let|var|if|else|return|for|while|do|switch|case|break|continue|class|extends|new|this|import|export|default|from|async|await|try|catch|finally|throw|typeof|instanceof|in|of|null|undefined|true|false|void|delete|yield|super|static|get|set|type|interface|enum|implements|readonly|abstract|declare|module|namespace|keyof|as|is|any|never|unknown|infer)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("`[^`]*`",                             .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            (kw,                                    .keyword),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizePython(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(def|class|if|elif|else|for|while|in|return|import|from|as|with|try|except|finally|raise|pass|break|continue|lambda|yield|global|nonlocal|del|assert|not|and|or|is|None|True|False|async|await)\\b"
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("\"\"\"[\\s\\S]*?\"\"\"",              .string),
            ("'''[\\s\\S]*?'''",                    .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            (kw,                                    .keyword),
            ("@\\w+",                               .attribute),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizeShell(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(if|then|else|elif|fi|for|do|done|while|case|esac|in|function|return|export|local|source|echo|cd|ls|grep|awk|sed|cat|rm|cp|mv|mkdir|chmod|chown)\\b"
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'[^']*'",                             .string),
            (kw,                                    .keyword),
            ("\\$\\{[\\w@#?!*-]+\\}|\\$[\\w@#?!*]+",  .type_),
            ("\\b[0-9]+\\b",                        .number),
        ])
    }

    private static func tokenizeMarkdown(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("^#{1,6} [^\n]+",                      .keyword),
            ("`{3}[\\s\\S]*?`{3}",                  .string),
            ("`[^`]+`",                             .string),
            ("\\*\\*[^*]+\\*\\*",                   .type_),
            ("__[^_]+__",                           .type_),
            ("\\*[^*]+\\*",                         .comment),
            ("_[^_]+_",                             .comment),
            ("\\[[^\\]]+\\]\\([^)]+\\)",            .attribute),
            ("^[-*+] ",                             .operator_),
            ("^\\d+\\. ",                           .operator_),
        ], options: [.anchorsMatchLines])
    }

    private static func tokenizeHTML(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("<!--[\\s\\S]*?-->",                   .comment),
            ("<[/!]?[A-Za-z][A-Za-z0-9-]*",        .keyword),
            ("[A-Za-z-]+(?=\\s*=)",                 .type_),
            ("\"[^\"]*\"",                          .string),
            ("'[^']*'",                             .string),
            (">",                                   .keyword),
            ("&[A-Za-z0-9#]+;",                    .number),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizeCSS(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("[.#]?[A-Za-z][A-Za-z0-9_-]*\\s*(?=\\{)", .keyword),
            ("[A-Za-z-]+(?=\\s*:)",                 .type_),
            ("\"[^\"]*\"|'[^']*'",                  .string),
            ("#[0-9A-Fa-f]{3,8}\\b",               .number),
            ("\\b[0-9]+(?:\\.[0-9]+)?(?:px|em|rem|%|vh|vw|pt|s|ms)?\\b", .number),
            ("@[A-Za-z-]+",                         .attribute),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizeGo(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(func|var|const|type|struct|interface|map|chan|go|defer|select|case|default|break|continue|return|if|else|for|range|switch|import|package|fallthrough|goto|nil|true|false|iota|make|new|append|len|cap|close|delete|copy|panic|recover|print|println)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("`[^`]*`",                             .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            (kw,                                    .keyword),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizeRust(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(fn|let|mut|const|static|struct|enum|trait|impl|type|where|use|mod|pub|crate|super|self|Self|if|else|match|loop|for|while|in|return|break|continue|as|ref|move|async|await|dyn|extern|unsafe|true|false|None|Some|Ok|Err)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("r#{0,5}\"[\\s\\S]*?\"#{0,5}",        .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            (kw,                                    .keyword),
            ("#\\[.*?\\]",                          .attribute),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
            ("'[a-z_]+",                            .type_),
        ], options: [.dotMatchesLineSeparators])
    }

    private static func tokenizeRuby(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(def|class|module|if|elsif|else|unless|end|do|begin|rescue|ensure|raise|return|yield|require|include|extend|attr_reader|attr_writer|attr_accessor|puts|print|true|false|nil|self|super|and|or|not|in|then|case|when)\\b"
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            (kw,                                    .keyword),
            (":[A-Za-z_]\\w*",                     .type_),
            ("@{1,2}[A-Za-z_]\\w*",               .attribute),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ])
    }

    static func color(for type_: TokenType, dark: Bool) -> NSColor {
        switch type_ {
        case .keyword:    return dark ? NSColor(calibratedRed: 0.80, green: 0.45, blue: 0.90, alpha: 1) : NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.70, alpha: 1)
        case .string:     return dark ? NSColor(calibratedRed: 0.90, green: 0.65, blue: 0.35, alpha: 1) : NSColor(calibratedRed: 0.70, green: 0.30, blue: 0.10, alpha: 1)
        case .comment:    return dark ? NSColor(calibratedWhite: 0.45, alpha: 1) : NSColor(calibratedWhite: 0.55, alpha: 1)
        case .number:     return dark ? NSColor(calibratedRed: 0.65, green: 0.90, blue: 0.65, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.50, blue: 0.10, alpha: 1)
        case .type_:      return dark ? NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.95, alpha: 1) : NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.65, alpha: 1)
        case .attribute:  return dark ? NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.40, alpha: 1) : NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.05, alpha: 1)
        case .operator_:  return dark ? NSColor(calibratedWhite: 0.65, alpha: 1) : NSColor(calibratedWhite: 0.40, alpha: 1)
        case .plain:
            return dark ? NSColor(calibratedWhite: 0.90, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
        }
    }
}

// ── EditorTextStorage ──────────────────────────────────────────────────────

class EditorTextStorage: NSTextStorage {
    private var _backing = NSMutableAttributedString()
    var language: EditorLanguage = .plain
    var isDark: Bool = true

    override var string: String { _backing.string }

    override func attributes(at location: Int,
                              effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        return _backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        _backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range,
               changeInLength: str.utf16.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        _backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        super.processEditing()
        guard editedMask.contains(.editedCharacters) else { return }
        applyHighlighting()
    }

    func applyHighlighting() {
        let full = NSRange(location: 0, length: _backing.length)
        guard full.length > 0 else { return }
        let fg = isDark ? NSColor(calibratedWhite: 0.90, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
        beginEditing()
        _backing.setAttributes([.foregroundColor: fg], range: full)
        let tokens = SyntaxHighlighter.tokenize(source: _backing.string, language: language)
        for tok in tokens {
            guard tok.range.location + tok.range.length <= _backing.length else { continue }
            let c = SyntaxHighlighter.color(for: tok.type, dark: isDark)
            _backing.addAttribute(.foregroundColor, value: c, range: tok.range)
        }
        edited(.editedAttributes, range: full, changeInLength: 0)
        endEditing()
    }
}

// ── EditorLayoutManager ────────────────────────────────────────────────────

class EditorLayoutManager: NSLayoutManager {
    weak var gutterView: GutterView?

    override func processEditing(for textStorage: NSTextStorage,
                                  edited editMask: NSTextStorageEditActions,
                                  range newCharRange: NSRange,
                                  changeInLength delta: Int,
                                  invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask,
                              range: newCharRange, changeInLength: delta,
                              invalidatedRange: invalidatedCharRange)
        if let ev = gutterView?.superview as? EditorView, !ev.foldedLineStarts.isEmpty {
            DispatchQueue.main.async { [weak self, weak textStorage] in
                guard let self, let ts = textStorage else { return }
                self.hideFoldedGlyphs(foldedLineStarts: ev.foldedLineStarts, in: ts)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.gutterView?.needsDisplay = true
        }
    }

    // setNotShownAttribute: available macOS 10.0+
    // Hides glyphs for all folded ranges by iterating over each glyph index
    func hideFoldedGlyphs(foldedLineStarts: Set<Int>, in textStorage: NSTextStorage) {
        guard !foldedLineStarts.isEmpty else { return }
        let str = textStorage.string as NSString
        for lineStart in foldedLineStarts {
            // Find the range to hide (from line end to block end)
            let lineEndRange = str.range(of: "\n", options: [],
                range: NSRange(location: lineStart, length: str.length - lineStart))
            let lineEndChar = lineEndRange.location == NSNotFound ? str.length : lineEndRange.location
            if lineEndChar >= str.length { continue }
            // Find matching }
            var depth = 0
            var i = lineEndChar
            var blockEnd = str.length
            while i < str.length {
                let c = str.character(at: i)
                if c == 0x7B { depth += 1 }
                else if c == 0x7D {
                    depth -= 1
                    if depth <= 0 { blockEnd = i + 1; break }
                }
                i += 1
            }
            let hideRange = NSRange(location: lineEndChar, length: blockEnd - lineEndChar)
            let glyphRange = self.glyphRange(forCharacterRange: hideRange, actualCharacterRange: nil)
            if glyphRange.location != NSNotFound && glyphRange.length > 0 {
                for gi in glyphRange.location ..< NSMaxRange(glyphRange) {
                    self.setNotShownAttribute(true, forGlyphAt: gi)
                }
            }
        }
    }
}

// ── GutterView ─────────────────────────────────────────────────────────────

class GutterView: NSView {
    static let width: CGFloat = 52
    weak var textView: NSTextView?
    weak var layoutManager: EditorLayoutManager?
    var isDark: Bool = true

    private var bgColor:   NSColor { isDark ? NSColor(calibratedWhite: 0.09, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1) }
    private var numColor:  NSColor { isDark ? NSColor(calibratedWhite: 0.38, alpha: 1) : NSColor(calibratedWhite: 0.60, alpha: 1) }
    private var curColor:  NSColor { isDark ? NSColor(calibratedWhite: 0.75, alpha: 1) : NSColor(calibratedWhite: 0.25, alpha: 1) }
    private var borderCol: NSColor { isDark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.82, alpha: 1) }

    override func draw(_ dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = lm.textContainers.first,
              let tv = textView,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

        ctx.setFillColor(borderCol.cgColor)
        ctx.fill(NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height))

        let font = tv.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numColor]
        let curAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: curColor]

        let visibleRect = tv.visibleRect
        let insetY = tv.textContainerInset.height

        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let str = lm.textStorage?.string ?? ""
        var lineNum = 1
        if charRange.location > 0 {
            let before = (str as NSString).substring(to: charRange.location)
            lineNum = before.components(separatedBy: "\n").count
        }

        let cursorLine = currentLineNumber(in: tv)

        var glyphIdx = glyphRange.location
        while glyphIdx < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineGlyphRange)
            let y = lineRect.minY + insetY - visibleRect.minY

            let label = "\(lineNum)" as NSString
            let a = lineNum == cursorLine ? curAttrs : attrs
            let size = label.size(withAttributes: a)
            label.draw(at: NSPoint(x: bounds.width - size.width - 10, y: y), withAttributes: a)

            // Draw fold triangle if line contains a block opener
            if let ts = lm.textStorage {
                let lineCharRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                let lineStr = (ts.string as NSString).substring(with: lineCharRange)
                if lineStr.contains("{") {
                    let triX: CGFloat = 4
                    let triY: CGFloat = y + lineRect.height / 2 - 4
                    ctx.setFillColor(numColor.cgColor)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: triX, y: triY))
                    ctx.addLine(to: CGPoint(x: triX + 8, y: triY + 4))
                    ctx.addLine(to: CGPoint(x: triX, y: triY + 8))
                    ctx.closePath()
                    ctx.fillPath()
                }
            }

            lineNum += 1
            glyphIdx = NSMaxRange(lineGlyphRange)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let lm = layoutManager,
              let tc = lm.textContainers.first,
              let tv = textView,
              let ev = superview as? EditorView else { return }
        let pt = convert(event.locationInWindow, from: nil)
        // Only react to clicks in the triangle area (left 18px)
        guard pt.x < 18 else { return }
        let visibleRect = tv.visibleRect
        let insetY = tv.textContainerInset.height
        // Find which line was clicked
        let clickY = pt.y + visibleRect.minY - insetY
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        var glyphIdx = glyphRange.location
        while glyphIdx < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineGlyphRange)
            if clickY >= lineRect.minY && clickY < lineRect.maxY {
                let charRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                // Check this line has a {
                let lineStr = (lm.textStorage?.string as? NSString)?.substring(with: charRange) ?? ""
                if lineStr.contains("{") {
                    ev.toggleFold(atCharIndex: charRange.location)
                }
                return
            }
            glyphIdx = NSMaxRange(lineGlyphRange)
        }
    }

    private func currentLineNumber(in tv: NSTextView) -> Int {
        let loc = tv.selectedRange().location
        let str = tv.string as NSString
        var line = 1
        var i = 0
        while i < loc && i < str.length {
            if str.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }
}

// ── EditorFooter ───────────────────────────────────────────────────────────

class EditorFooter: NSView {
    static let height: CGFloat = 24
    private let infoLabel = NSTextField(labelWithString: "")
    private let encBtn    = NSButton()
    private let leBtn     = NSButton()
    var isDark: Bool = true {
        didSet { updateColors() }
    }
    var onEncodingClick:    (() -> Void)?
    var onLineEndingClick:  (() -> Void)?

    var line: Int = 1        { didSet { updateLabel() } }
    var column: Int = 1      { didSet { updateLabel() } }
    var encoding: String = "UTF-8"  { didSet { updateLabel() } }
    var lineEnding: String = "LF"   { didSet { updateLabel() } }
    var language: EditorLanguage = .plain { didSet { updateLabel() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        infoLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)

        for btn in [encBtn, leBtn] {
            btn.isBordered = false
            btn.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
        }
        encBtn.target = self; encBtn.action = #selector(clickEnc)
        leBtn.target  = self; leBtn.action  = #selector(clickLE)

        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            leBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            encBtn.trailingAnchor.constraint(equalTo: leBtn.leadingAnchor, constant: -12),
            encBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
        updateLabel()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        layer?.backgroundColor = (isDark ? NSColor(calibratedWhite: 0.09, alpha: 1)
                                         : NSColor(calibratedWhite: 0.93, alpha: 1)).cgColor
        let fg = isDark ? NSColor(calibratedWhite: 0.45, alpha: 1) : NSColor(calibratedWhite: 0.55, alpha: 1)
        infoLabel.textColor = fg
        encBtn.contentTintColor = fg
        leBtn.contentTintColor = fg
    }

    private func updateLabel() {
        let langName = language == .plain ? "Plain Text" : language.rawValue.capitalized
        infoLabel.stringValue = "Ln \(line), Col \(column)  ·  \(langName)"
        encBtn.title = encoding
        leBtn.title  = lineEnding
    }

    @objc private func clickEnc() { onEncodingClick?() }
    @objc private func clickLE()  { onLineEndingClick?() }
}

// ── EditorSearchPanel ──────────────────────────────────────────────────────

class EditorSearchPanel: NSView {
    static let height: CGFloat = 36
    private let findField     = NSTextField()
    private let replaceField  = NSTextField()
    private let closeBtn      = NSButton()
    private let nextBtn       = NSButton()
    private let prevBtn       = NSButton()
    private let replaceBtn    = NSButton()
    private let replaceAllBtn = NSButton()
    private let modeLabel     = NSTextField(labelWithString: "Find")
    var isReplaceMode = false { didSet { updateLayout() } }
    var isDark: Bool = true   { didSet { updateColors() } }

    var onFind:       ((String, Bool) -> Void)?
    var onReplace:    ((String, String) -> Void)?
    var onReplaceAll: ((String, String) -> Void)?
    var onClose:      (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        findField.placeholderString = "Suchen…"
        findField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        findField.translatesAutoresizingMaskIntoConstraints = false

        replaceField.placeholderString = "Ersetzen…"
        replaceField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.isHidden = true

        for (btn, title) in [(closeBtn, "✕"), (prevBtn, "↑"), (nextBtn, "↓"),
                              (replaceBtn, "Ersetzen"), (replaceAllBtn, "Alle")] {
            btn.title = title
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
        }
        replaceBtn.isHidden    = true
        replaceAllBtn.isHidden = true

        [findField, replaceField, modeLabel].forEach { addSubview($0) }
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        closeBtn.target = self; closeBtn.action = #selector(tapClose)
        nextBtn.target  = self; nextBtn.action  = #selector(tapNext)
        prevBtn.target  = self; prevBtn.action  = #selector(tapPrev)
        replaceBtn.target    = self; replaceBtn.action    = #selector(tapReplace)
        replaceAllBtn.target = self; replaceAllBtn.action = #selector(tapReplaceAll)

        NSLayoutConstraint.activate([
            closeBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            modeLabel.leadingAnchor.constraint(equalTo: closeBtn.trailingAnchor, constant: 8),
            modeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            findField.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            findField.widthAnchor.constraint(equalToConstant: 180),
            findField.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevBtn.leadingAnchor.constraint(equalTo: findField.trailingAnchor, constant: 4),
            prevBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextBtn.leadingAnchor.constraint(equalTo: prevBtn.trailingAnchor, constant: 4),
            nextBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceField.leadingAnchor.constraint(equalTo: nextBtn.trailingAnchor, constant: 8),
            replaceField.widthAnchor.constraint(equalToConstant: 160),
            replaceField.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceBtn.leadingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: 4),
            replaceBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceAllBtn.leadingAnchor.constraint(equalTo: replaceBtn.trailingAnchor, constant: 4),
            replaceAllBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    func focusFind() { window?.makeFirstResponder(findField) }

    private func updateLayout() {
        modeLabel.stringValue = isReplaceMode ? "Ersetzen" : "Suchen"
        replaceField.isHidden = !isReplaceMode
        replaceBtn.isHidden   = !isReplaceMode
        replaceAllBtn.isHidden = !isReplaceMode
    }

    private func updateColors() {
        layer?.backgroundColor = (isDark ? NSColor(calibratedWhite: 0.11, alpha: 0.97)
                                         : NSColor(calibratedWhite: 0.91, alpha: 0.97)).cgColor
        let fg = isDark ? NSColor(calibratedWhite: 0.80, alpha: 1) : NSColor(calibratedWhite: 0.20, alpha: 1)
        modeLabel.textColor = fg
        [closeBtn, nextBtn, prevBtn, replaceBtn, replaceAllBtn].forEach { $0.contentTintColor = fg }
    }

    @objc private func tapClose()      { onClose?() }
    @objc private func tapNext()       { onFind?(findField.stringValue, true) }
    @objc private func tapPrev()       { onFind?(findField.stringValue, false) }
    @objc private func tapReplace()    { onReplace?(findField.stringValue, replaceField.stringValue) }
    @objc private func tapReplaceAll() { onReplaceAll?(findField.stringValue, replaceField.stringValue) }
}

// ── EditorView ─────────────────────────────────────────────────────────────

class EditorView: NSView, NSTextViewDelegate {

    private let gutterView    = GutterView()
    private let scrollView    = NSScrollView()
    var textView: NSTextView!
    private let footer        = EditorFooter()
    private let searchPanel   = EditorSearchPanel()
    private var searchVisible = false

    private let storage       = EditorTextStorage()
    private let layoutMgr     = EditorLayoutManager()
    private let textContainer = NSTextContainer()

    var fileURL: URL? {
        didSet {
            storage.language = SyntaxHighlighter.detectLanguage(from: fileURL)
            footer.language  = storage.language
            storage.applyHighlighting()
        }
    }

    var isDirty: Bool = false {
        didSet { onDirtyChanged?(isDirty) }
    }
    var onDirtyChanged: ((Bool) -> Void)?

    var fileEncoding: String.Encoding = .utf8
    var lineEnding: String = "LF"

    var isDark: Bool = true {
        didSet { applyColors() }
    }

    var useTabs: Bool = true

    // ── Code folding state ────────────────────────────────────────────────
    private(set) var foldedLineStarts: Set<Int> = []  // char indices of folded line starts

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        storage.addLayoutManager(layoutMgr)
        layoutMgr.addTextContainer(textContainer)
        // Wire textView into the custom storage chain (must use this init)
        textView = NSTextView(frame: .zero, textContainer: textContainer)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        textView.isAutomaticLinkDetectionEnabled      = false
        textView.isRichText  = false
        textView.allowsUndo  = true
        textView.delegate    = self

        layoutMgr.gutterView = gutterView
        gutterView.textView  = textView
        gutterView.layoutManager = layoutMgr

        scrollView.documentView          = textView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask      = []
        scrollView.drawsBackground       = false

        searchPanel.isHidden = true
        searchPanel.onClose      = { [weak self] in self?.hideSearch() }
        searchPanel.onFind       = { [weak self] q, fwd in self?.findNext(query: q, forward: fwd) }
        searchPanel.onReplace    = { [weak self] q, r in self?.replaceOne(query: q, replacement: r) }
        searchPanel.onReplaceAll = { [weak self] q, r in self?.replaceAll(query: q, replacement: r) }

        footer.onEncodingClick   = { [weak self] in self?.showEncodingMenu() }
        footer.onLineEndingClick = { [weak self] in self?.showLineEndingMenu() }

        [gutterView, scrollView, footer, searchPanel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: GutterView.width),
            gutterView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: EditorFooter.height),

            searchPanel.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            searchPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchPanel.bottomAnchor.constraint(equalTo: footer.topAnchor),
            searchPanel.heightAnchor.constraint(equalToConstant: EditorSearchPanel.height),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)

        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    // ── Load / Save ────────────────────────────────────────────────────────
    func loadFile(url: URL) throws {
        var enc: String.Encoding = .utf8
        var content: String
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            content = s; enc = .utf8
        } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = s; enc = .isoLatin1
        } else {
            content = try String(contentsOf: url, encoding: .utf8)
        }
        fileEncoding = enc
        footer.encoding = enc == .utf8 ? "UTF-8" : "Latin-1"

        if content.contains("\r\n")      { lineEnding = "CRLF" }
        else if content.contains("\r")   { lineEnding = "CR"   }
        else                             { lineEnding = "LF"   }
        footer.lineEnding = lineEnding

        fileURL = url
        setContent(content)
        isDirty = false
    }

    func saveFile(to url: URL? = nil) throws {
        let target = url ?? fileURL
        guard let target else { return }
        var text = textView.string
        if lineEnding == "CRLF" { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        else if lineEnding == "CR" { text = text.replacingOccurrences(of: "\n", with: "\r") }
        try text.write(to: target, atomically: true, encoding: fileEncoding)
        fileURL = target
        isDirty = false
    }

    func setContent(_ text: String) {
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: text)
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        gutterView.needsDisplay = true
        updateFooterCursor()
    }

    // ── Colors ─────────────────────────────────────────────────────────────
    func applyColors() {
        let bg: NSColor = isDark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        let fg: NSColor = isDark ? NSColor(calibratedWhite: 0.90, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
        layer?.backgroundColor = bg.cgColor
        textView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = isDark ? .white : .black
        storage.isDark = isDark
        storage.applyHighlighting()
        gutterView.isDark = isDark
        gutterView.needsDisplay = true
        footer.isDark = isDark
        searchPanel.isDark = isDark
    }

    // ── NSTextViewDelegate ─────────────────────────────────────────────────
    func textDidChange(_ notification: Notification) {
        if !isDirty { isDirty = true }
        updateFooterCursor()
        gutterView.needsDisplay = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateFooterCursor()
        gutterView.needsDisplay = true
    }

    private func updateFooterCursor() {
        let sel  = textView.selectedRange()
        let str  = textView.string as NSString
        let line = str.substring(to: min(sel.location, str.length))
                      .components(separatedBy: "\n").count
        let beforeSel = str.substring(to: min(sel.location, str.length))
        let lastNL = (beforeSel as NSString).range(of: "\n", options: .backwards)
        let lineStart = lastNL.location == NSNotFound ? 0 : lastNL.location + 1
        let col = sel.location - lineStart + 1
        footer.line   = line
        footer.column = col
    }

    @objc private func scrollDidChange() {
        gutterView.needsDisplay = true
    }

    // ── Search ─────────────────────────────────────────────────────────────
    func showSearch(replace: Bool = false) {
        searchPanel.isReplaceMode = replace
        searchPanel.isHidden = false
        searchVisible = true
        searchPanel.focusFind()
    }

    func hideSearch() {
        searchPanel.isHidden = true
        searchVisible = false
        window?.makeFirstResponder(textView)
    }

    private func findNext(query: String, forward: Bool) {
        guard !query.isEmpty else { return }
        let text  = textView.string as NSString
        let sel   = textView.selectedRange()
        let start = forward ? NSMaxRange(sel) : max(0, sel.location - 1)
        let opts: NSString.CompareOptions = forward ? [] : .backwards
        let searchRange = forward
            ? NSRange(location: start, length: text.length - start)
            : NSRange(location: 0, length: start)
        var found = text.range(of: query, options: opts, range: searchRange)
        if found.location == NSNotFound {
            // wrap around
            found = text.range(of: query, options: opts,
                               range: NSRange(location: 0, length: text.length))
        }
        if found.location != NSNotFound {
            textView.setSelectedRange(found)
            textView.scrollRangeToVisible(found)
        }
    }

    private func replaceOne(query: String, replacement: String) {
        guard !query.isEmpty else { return }
        let sel     = textView.selectedRange()
        let current = (textView.string as NSString).substring(with: sel)
        if current == query {
            textView.insertText(replacement, replacementRange: sel)
        }
        findNext(query: query, forward: true)
    }

    private func replaceAll(query: String, replacement: String) {
        guard !query.isEmpty else { return }
        let new = textView.string.replacingOccurrences(of: query, with: replacement)
        if new != textView.string { setContent(new); isDirty = true }
    }

    // ── Encoding / Line ending menus ───────────────────────────────────────
    private func showEncodingMenu() {
        guard let win = window else { return }
        let menu = NSMenu()
        let encs: [(String, String.Encoding)] = [("UTF-8", .utf8), ("Latin-1", .isoLatin1), ("UTF-16", .utf16)]
        for (title, enc) in encs {
            let item = NSMenuItem(title: title, action: #selector(pickEncoding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: enc.rawValue)
            menu.addItem(item)
        }
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: win.convertPoint(fromScreen: loc), in: self)
    }

    @objc private func pickEncoding(_ item: NSMenuItem) {
        if let raw = (item.representedObject as? NSNumber)?.uintValue {
            fileEncoding = String.Encoding(rawValue: raw)
            footer.encoding = item.title
        }
    }

    private func showLineEndingMenu() {
        guard let win = window else { return }
        let menu = NSMenu()
        for le in ["LF", "CRLF", "CR"] {
            let item = NSMenuItem(title: le, action: #selector(pickLineEnding(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: win.convertPoint(fromScreen: loc), in: self)
    }

    @objc private func pickLineEnding(_ item: NSMenuItem) {
        lineEnding = item.title
        footer.lineEnding = lineEnding
    }

    // ── Tab key override ───────────────────────────────────────────────────
    func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTab(_:)) {
            let insert = useTabs ? "\t" : String(repeating: " ", count: 4)
            tv.insertText(insert, replacementRange: tv.selectedRange())
            return true
        }
        return false
    }

    // ── Multiple cursors: Option+click ─────────────────────────────────────
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else {
            super.mouseDown(with: event)
            return
        }
        let pt      = textView.convert(event.locationInWindow, from: nil)
        let frac    = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        frac.initialize(to: 0)
        defer { frac.deallocate() }
        let glyphIdx = layoutMgr.glyphIndex(for: pt, in: textContainer,
                                             fractionOfDistanceThroughGlyph: frac)
        let charIdx  = layoutMgr.characterIndexForGlyph(at: glyphIdx)
        var ranges   = textView.selectedRanges
        ranges.append(NSValue(range: NSRange(location: charIdx, length: 0)))
        textView.selectedRanges = ranges
    }

    // ── Accessors for folding ───────────────────────────────────────────────
    var editorGutterView: GutterView { gutterView }
    var editorLayoutManager: EditorLayoutManager { layoutMgr }

    // ── Code Folding ───────────────────────────────────────────────────────

    func toggleFold(atCharIndex lineStartChar: Int) {
        let str = textView.string as NSString
        guard lineStartChar < str.length else { return }

        // Find end of this line
        let lineEndRange = str.range(of: "\n",
            options: [],
            range: NSRange(location: lineStartChar, length: str.length - lineStartChar))
        let lineEndChar = lineEndRange.location == NSNotFound ? str.length : lineEndRange.location

        // Find block end (matching closing brace)
        let blockEndChar = findBlockEnd(from: lineEndChar, in: str)
        guard blockEndChar > lineEndChar else { return }
        let foldRange = NSRange(location: lineEndChar, length: blockEndChar - lineEndChar)

        if foldedLineStarts.contains(lineStartChar) {
            // Unfold: make glyphs visible again
            foldedLineStarts.remove(lineStartChar)
            layoutMgr.invalidateGlyphs(forCharacterRange: foldRange,
                                        changeInLength: 0, actualCharacterRange: nil)
            layoutMgr.invalidateLayout(forCharacterRange: foldRange, actualCharacterRange: nil)
        } else {
            // Fold: hide glyphs
            foldedLineStarts.insert(lineStartChar)
            layoutMgr.invalidateGlyphs(forCharacterRange: foldRange,
                                        changeInLength: 0, actualCharacterRange: nil)
            layoutMgr.invalidateLayout(forCharacterRange: foldRange, actualCharacterRange: nil)
        }
        gutterView.needsDisplay = true
    }

    private func findBlockEnd(from start: Int, in str: NSString) -> Int {
        var depth = 0
        var i = start
        var inString = false
        var inLineComment = false
        while i < str.length {
            let c = str.character(at: i)
            if inLineComment {
                if c == 0x0A { inLineComment = false }
            } else if inString {
                if c == 0x22 { inString = false }  // closing "
                else if c == 0x5C { i += 1 }       // skip escaped char
            } else {
                if c == 0x2F && i + 1 < str.length && str.character(at: i + 1) == 0x2F {
                    inLineComment = true
                } else if c == 0x22 {
                    inString = true
                } else if c == 0x7B {  // {
                    depth += 1
                } else if c == 0x7D {  // }
                    if depth > 0 {
                        depth -= 1
                        if depth == 0 { return i + 1 }
                    }
                }
            }
            i += 1
        }
        return str.length
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var termViews: [TerminalView?] = []   // nil for editor tabs
    var splitContainers: [SplitContainer] = []
    var activeTab = 0
    // Editor tab parallel arrays (indexed same as termViews/splitContainers)
    var tabTypes: [TabType] = []
    var tabEditorViews: [EditorView?] = []
    var tabEditorURLs: [URL?] = []
    var tabEditorDirty: [Bool] = []
    var statusItem: NSStatusItem!
    var globalClickMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
    var visualEffect: NSVisualEffectView!
    var isAnimating = false
    var pendingToggle = false           // queued toggle: execute one toggleWindow() after current animation
    var isWindowDetached = false        // free-floating mode (not anchored to tray icon)
    var lastHideTime: TimeInterval = 0  // suppress hover-activate right after hiding
    let updateChecker = UpdateChecker()
    var pendingRelease: GitHubRelease?
    var updateCheckTimer: Timer?

    /// True if any TerminalView (primary or split secondary) has an active drag session
    private var isAnyDragSessionActive: Bool {
        termViews.contains { $0?.isDragSessionActive == true } ||
        splitContainers.contains { $0.secondaryView?.isDragSessionActive == true }
    }

    /// The user's configured window opacity, falling back to 1.0
    private var effectiveOpacity: CGFloat {
        let base = CGFloat(UserDefaults.standard.double(forKey: "windowOpacity"))
        return base > 0.01 ? base : 1.0
    }

    /// Animate window to full (undimmed) opacity without allowing any frame drift
    private func restoreWindowOpacity() {
        let pinnedOrigin = window.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = effectiveOpacity
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            // Pin position: prevent any implicit frame drift caused by the alpha animation
            if self.window.frame.origin != pinnedOrigin {
                self.window.setFrameOrigin(pinnedOrigin)
            }
        })
    }
    var headerView: HeaderBarView!
    var footerView: FooterBarView!
    var footerTimer: Timer?
    private var windowMoveWorkItem: DispatchWorkItem?
    let arrowH: CGFloat = 10
    let arrowW: CGFloat = 20
    var tabColors: [NSColor] = []
    var tabCustomNames: [String?] = []
    var tabGitPositions: [GitPanelPosition] = []
    var tabGitPanels: [GitPanelView?] = []
    var tabGitDividers: [GitPanelDividerView?] = []
    var tabGitRatios: [CGFloat] = []       // active ratio used by current position
    var tabGitRatiosV: [CGFloat] = []      // saved vertical (right) ratio per tab
    var tabGitRatiosH: [CGFloat] = []      // saved horizontal (bottom) ratio per tab
    let gitDefaultRatioV: CGFloat = 0.35   // factory default: right panel
    let gitDefaultRatioH: CGFloat = 0.30   // factory default: bottom panel
    var settingsOverlay: SettingsOverlay?
    var commandPalette: CommandPaletteView?
    var webPickerSidebarView: WebPickerSidebarView?
    var webPickerRightDivider: GitPanelDividerView?
    var sshManagerView: SSHManagerView?
    // Multi-panel sidebar state (order = visual top→bottom)
    var sidebarOrder: [String] = ["git", "picker", "ssh"]
    var sidebarPanelHeights: [String: CGFloat] = ["git": 300, "picker": 320, "ssh": 260]
    var sidebarHDividers: [String: GitPanelDividerView] = [:]
    var helpViewer: HelpViewer?
    var perfOverlay: DiagnosticsOverlay?
    var parserOverlay: DiagnosticsOverlay?
    var usagePopover: AIUsagePopover?
    var usagePopoverMonitor: Any?
    var searchHighlights: [(row: Int, col: Int, len: Int)] = []
    var searchCurrentIndex: Int = -1
    var searchQuery: String = ""
    private var searchCleanupWork: DispatchWorkItem?
    var preFullscreenFrame: NSRect?
    var preHorizontFrame: NSRect?
    var preVerticalFrame: NSRect?
    private var lastCtrlPressTime: TimeInterval = 0
    private var ctrlWasDown = false
    private var localKeyMonitor: Any?

    func requestFullDiskAccessIfNeeded() {
        let key = "hasShownFDAPrompt"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        // Check if we have full disk access by probing a protected path
        let testPath = NSHomeDirectory() + "/Library/Mail"
        let hasAccess = FileManager.default.isReadableFile(atPath: testPath)
        if hasAccess { return }

        let alert = NSAlert()
        alert.messageText = Loc.fullDiskAccess
        alert.informativeText = Loc.fullDiskAccessMsg
        alert.alertStyle = .informational
        alert.addButton(withTitle: Loc.openSettings)
        alert.addButton(withTitle: Loc.later)
        alert.icon = NSApp.applicationIconImage

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings → Full Disk Access
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One-time prompt for Full Disk Access
        requestFullDiskAccessIfNeeded()

        // Register default settings (single source of truth in SettingsOverlay.defaultSettings)
        UserDefaults.standard.register(defaults: SettingsOverlay.defaultSettings)

        // Apply saved color theme
        let savedTheme = UserDefaults.standard.integer(forKey: "colorTheme")
        if savedTheme != 0 {
            applySetting(key: "colorTheme", value: savedTheme)
        }

        // Observe macOS appearance changes for System theme
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        // Menu bar icon — custom drawn >_ prompt
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
                // Exact reproduction of quickTERMINAL.svg
                // Content spans x:[2,22] y:[4,25.25] in design coords
                let sc: CGFloat = 18.0 / 21.25
                let ox: CGFloat = (18.0 - 20.0 * sc) / 2.0
                func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                    NSPoint(x: (x - 2.0) * sc + ox, y: (y - 4.0) * sc)
                }
                let lw: CGFloat = 1.5 * sc
                NSColor.black.setStroke()
                NSColor.black.setFill()

                // Rounded rectangle frame
                let frame = NSBezierPath()
                frame.move(to: p(2, 18))
                frame.line(to: p(2, 6))
                frame.curve(to: p(4, 4),
                            controlPoint1: p(2, 4.895),
                            controlPoint2: p(2.895, 4))
                frame.line(to: p(20, 4))
                frame.curve(to: p(22, 6),
                            controlPoint1: p(21.105, 4),
                            controlPoint2: p(22, 4.895))
                frame.line(to: p(22, 18))
                frame.curve(to: p(20, 20),
                            controlPoint1: p(22, 19.105),
                            controlPoint2: p(21.105, 20))
                frame.line(to: p(4, 20))
                frame.curve(to: p(2, 18),
                            controlPoint1: p(2.895, 20),
                            controlPoint2: p(2, 19.105))
                frame.close()
                frame.lineWidth = lw
                frame.lineCapStyle = .round
                frame.lineJoinStyle = .round
                frame.stroke()

                // Chevron: M6,8 L10,12 L6,16
                let chevron = NSBezierPath()
                chevron.move(to: p(6, 8))
                chevron.line(to: p(10, 12))
                chevron.line(to: p(6, 16))
                chevron.lineWidth = lw
                chevron.lineCapStyle = .round
                chevron.lineJoinStyle = .round
                chevron.stroke()

                // Underscore: M13,16 L18,16
                let underscore = NSBezierPath()
                underscore.move(to: p(13, 16))
                underscore.line(to: p(18, 16))
                underscore.lineWidth = lw
                underscore.lineCapStyle = .round
                underscore.stroke()

                // Large downward arrow (matrix-transformed filled triangle)
                let tri = NSBezierPath()
                tri.move(to: p(17.172, 20.002))
                tri.curve(to: p(16.928, 20.581),
                          controlPoint1: p(17.172, 20.215),
                          controlPoint2: p(17.091, 20.418))
                tri.line(to: p(12.579, 24.930))
                tri.curve(to: p(11.422, 24.930),
                          controlPoint1: p(12.259, 25.250),
                          controlPoint2: p(11.742, 25.250))
                tri.line(to: p(7.074, 20.581))
                tri.curve(to: p(6.830, 20.002),
                          controlPoint1: p(6.911, 20.418),
                          controlPoint2: p(6.830, 20.215))
                tri.line(to: p(17.172, 20.002))
                tri.close()
                tri.fill()

                return true
            }
            icon.isTemplate = true
            button.image = icon
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Window — positioned under tray icon, restore saved size
        let savedW = UserDefaults.standard.double(forKey: "windowWidth")
        let savedH = UserDefaults.standard.double(forKey: "windowHeight")
        let w: CGFloat = savedW > 100 ? CGFloat(savedW) : 860
        let h: CGFloat = savedH > 100 ? CGFloat(savedH) : 480
        let frame = NSRect(x: 0, y: 0, width: w, height: h)

        window = BorderlessWindow(contentRect: frame,
                                   styleMask: [.borderless, .miniaturizable],
                                   backing: .buffered, defer: false)
        window.delegate = self
        // Minimum size: header needs ~80px for buttons + at least 1 tab (~80px) + padding,
        // plus terminal needs at least ~20 columns to be usable
        window.minSize = NSSize(width: 320, height: 220)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        let alwaysTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        window.level = alwaysTop ? .floating : .normal
        let followSpaces = UserDefaults.standard.bool(forKey: "followAllSpaces")
        window.collectionBehavior = followSpaces ? [.canJoinAllSpaces] : [.moveToActiveSpace]
        window.appearance = NSAppearance(named: .darkAqua)  // always dark mode

        // Shape mask: rounded rect body + popover arrow at top center
        window.contentView?.wantsLayer = true
        updateWindowMask()

        // Frosted glass background
        visualEffect = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.alphaValue = CGFloat(UserDefaults.standard.double(forKey: "blurIntensity"))
        window.contentView?.addSubview(visualEffect)

        // Apply saved opacity
        window.alphaValue = CGFloat(UserDefaults.standard.double(forKey: "windowOpacity"))

        let bounds = window.contentView?.bounds ?? .zero
        let headerH = HeaderBarView.barHeight
        let footerH = FooterBarView.barHeight

        // Arrow tint — match header background so arrow doesn't look lighter
        let arrowTint = NSView(frame: NSRect(x: 0, y: bounds.height - arrowH,
                                              width: bounds.width, height: arrowH))
        arrowTint.wantsLayer = true
        arrowTint.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.3).cgColor
        arrowTint.autoresizingMask = [.width, .minYMargin]
        window.contentView?.addSubview(arrowTint)
        arrowTintView = arrowTint

        // Header bar at top (below arrow)
        headerView = HeaderBarView(frame: NSRect(x: 0, y: bounds.height - headerH - arrowH,
                                                  width: bounds.width, height: headerH))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.onTabClicked = { [weak self] index in self?.switchToTab(index) }
        headerView.onAddTab = { [weak self] in self?.addTab() }
        headerView.onAddEditorTab = { [weak self] in self?.newEditorTab() }
        headerView.onCloseTab = { [weak self] index in self?.closeTab(index: index) }
        headerView.onReorderTab = { [weak self] from, to in self?.reorderTab(from: from, to: to) }
        headerView.onTabRenamed = { [weak self] index, name in
            guard let self = self, index >= 0, index < self.tabCustomNames.count else { return }
            self.tabCustomNames[index] = name
            self.updateHeaderTabs()
            self.saveSession()
        }
        headerView.onSplitVertical = { [weak self] in self?.toggleSplit(vertical: true) }
        headerView.onSplitHorizontal = { [weak self] in self?.toggleSplit(vertical: false) }
        headerView.onGitToggle = { [weak self] in self?.toggleGitPanel() }
        headerView.onWebPickerToggle = { [weak self] in self?.toggleWebPicker() }
        headerView.onSSHToggle = { [weak self] in self?.toggleSSHManager() }
        headerView.onDoubleClick = { [weak self] in self?.toggleFullscreen() }

        window.contentView?.addSubview(headerView)

        // Footer bar at bottom
        footerView = FooterBarView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: footerH))
        footerView.autoresizingMask = [.width, .maxYMargin]
        footerView.onSwitchShell = { [weak self] index in
            guard let self = self, !self.splitContainers.isEmpty else { return }
            // Use focused pane in split mode
            let container = self.splitContainers[self.activeTab]
            let tv: TerminalView
            if container.isSplit && !container.activePaneIsPrimary,
               let sec = container.secondaryView {
                tv = sec
            } else {
                guard let primaryTV = self.termViews[self.activeTab] else { return }
                tv = primaryTV
            }
            switch index {
            case 0: tv.switchToShell1(nil)
            case 1: tv.switchToShell2(nil)
            case 2: tv.switchToShell3(nil)
            default: break
            }
            self.updateHeaderTabs()
            self.updateFooter()
        }
        footerView.onSettings = { [weak self] in self?.toggleSettings() }
        footerView.onNewTab = { [weak self] in self?.addTab() }
        footerView.onCloseTab = { [weak self] in self?.closeCurrentTab() }
        footerView.onSplitV = { [weak self] in self?.toggleSplit(vertical: true) }
        footerView.onSplitH = { [weak self] in self?.toggleSplit(vertical: false) }
        footerView.onToggleWindow = { [weak self] in self?.toggleWindow() }
        footerView.onSwitchSplitPane = { [weak self] in self?.switchSplitPane() }
        footerView.onPrevTab = { [weak self] in
            guard let self = self else { return }
            let prev = self.activeTab > 0 ? self.activeTab - 1 : self.splitContainers.count - 1
            self.switchToTab(prev)
        }
        footerView.onNextTab = { [weak self] in
            guard let self = self else { return }
            let next = self.activeTab < self.splitContainers.count - 1 ? self.activeTab + 1 : 0
            self.switchToTab(next)
        }
        window.contentView?.addSubview(footerView)

        // AI Usage — always start polling, badge visibility is separate
        footerView.onUsageBadgeClick = { [weak self] in self?.toggleUsagePopover() }
        AIUsageManager.shared.onUpdate = { [weak self] data in
            self?.footerView.usageBadge.update(data: data)
            self?.footerView.needsLayout = true
            self?.usagePopover?.update(data: data)
            self?.usagePopover?.setRefreshDone()
        }
        let showUsage = UserDefaults.standard.bool(forKey: "showAIUsage")
        footerView.usageBadge.isHidden = !showUsage
        // Load cached data immediately so badge/popover show last known state on startup
        AIUsageManager.shared.loadCachedData()
        if showUsage {
            let intervals: [TimeInterval] = [300, 600, 1800]
            let idx = UserDefaults.standard.integer(forKey: "aiUsageRefreshIndex")
            AIUsageManager.shared.startPolling(interval: intervals[min(idx, 2)])
        }

        // Version label — clickable HoverButton, shows full changelog on click
        let verBtn = HoverButton(
            title: "v\(kAppVersion)",
            fontSize: 9, weight: .light,
            normalColor: NSColor(calibratedWhite: 0.38, alpha: 1.0),
            hoverColor:  NSColor(calibratedWhite: 0.90, alpha: 1.0),
            hoverBg:     NSColor(calibratedWhite: 1.0, alpha: 0.10),
            cornerRadius: 4)
        verBtn.onClick = { [weak self] in
            guard let self = self else { return }
            if self.helpViewer == nil { self.helpViewer = HelpViewer() }
            self.helpViewer?.showChangelog(relativeTo: self.window)
        }
        let btnSize = verBtn.intrinsicContentSize
        verBtn.frame = NSRect(x: bounds.width - btnSize.width - 8, y: footerH + 1,
                              width: btnSize.width, height: btnSize.height)
        verBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        verBtn.layer?.zPosition = 1
        window.contentView?.addSubview(verBtn)

        // Restore previous session or create first tab
        if !restoreSession() {
            addTab()
        }

        // Update timer (every 2s) — refreshes footer + tab titles
        footerTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateFooter()
            self?.updateHeaderTabs()
            self?.updateGitPanelCwd()
        }
        updateFooter()

        // Auto-check for updates: 3s after launch, then every 72h
        scheduleUpdateCheck(initialDelay: 3.0)


        // Global hotkey: Ctrl+< to toggle window (Carbon API — works system-wide)
        // keyCode 50 = the < key (ISO keyboard, left of Y/Z)
        let hotKeyCallback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let delegate = NSApp.delegate as? AppDelegate else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { delegate.toggleWindow() }
            return noErr
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &eventType, nil, nil)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5154484B)  // "QTHK"
        hotKeyID.id = 1
        RegisterEventHotKey(50, UInt32(controlKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)

        // Double-Ctrl detection → Command Palette
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Show window on launch — defer one run-loop so statusItem.button.window is ready.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if UserDefaults.standard.bool(forKey: "windowDetached") {
                self.restoreDetachedWindowState()
            } else {
                self.showWindowAnimated()
            }
        }
        // Retry positioning after 150ms — the status-bar button reports a bogus
        // screenRect (0, -11) on the very first run-loop after launch. By 150ms
        // macOS has placed the button correctly, so positionWindowUnderTrayIcon
        // will now calculate the real position and snap the window into place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, !self.isWindowDetached, self.window.isVisible else { return }
            self.positionWindowUnderTrayIcon()
            self.updateWindowMask()
        }

        // First-launch onboarding video (plays once, never again)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            OnboardingPanel.showIfNeeded(relativeTo: self.window)
        }
    }

    func termFrame() -> NSRect {
        let bounds = window.contentView?.bounds ?? .zero
        let headerH = HeaderBarView.barHeight
        let footerH = FooterBarView.barHeight
        let effectiveArrowH: CGFloat = isWindowDetached ? 0 : arrowH
        return NSRect(x: 0, y: footerH, width: bounds.width,
                      height: bounds.height - headerH - footerH - effectiveArrowH)
    }

    @objc func systemAppearanceChanged() {
        if UserDefaults.standard.integer(forKey: "colorTheme") == 3 {
            applySetting(key: "colorTheme", value: 3)
            applySystemThemeAppearance(to: visualEffect)
        }
    }

    @objc func addTab() {
        let shells = ["/bin/zsh", "/bin/bash", "/bin/sh"]
        let idx = UserDefaults.standard.integer(forKey: "defaultShellIndex")
        let shell = idx >= 0 && idx < shells.count ? shells[idx] : "/bin/zsh"
        createTab(shell: shell, cwd: nil, colorHue: nil)
    }

    func createTab(shell: String, cwd: String?, colorHue: CGFloat?, tabId: String? = nil) {
        let tf = termFrame()
        let tv = TerminalView(frameRect: tf, shell: shell, cwd: cwd, historyId: tabId)
        tv.terminal.onTitleChange = { [weak self] title in
            self?.window.title = title
        }
        tv.onShellExit = { [weak self, weak tv] in
            guard let self = self, let tv = tv else { return }
            if let idx = self.termViews.firstIndex(where: { $0 === tv }) {
                if self.splitContainers.count > 1 {
                    self.closeTab(index: idx)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }

        let container = SplitContainer(frame: tf, primary: tv)
        container.autoresizingMask = [.width, .height]
        container.onFocusChanged = { [weak self] _ in self?.updateFooter() }

        // Use provided hue or generate random
        let hue = colorHue ?? CGFloat.random(in: 0...1)
        let tabColor = NSColor(calibratedHue: hue, saturation: 0.65, brightness: 0.85, alpha: 1.0)
        tabColors.append(tabColor)
        tabCustomNames.append(nil)
        tabGitPositions.append(.none)
        tabGitPanels.append(nil)
        tabGitDividers.append(nil)
        tabGitRatios.append(gitDefaultRatioH) // default to bottom
        tabGitRatiosV.append(gitDefaultRatioV)
        tabGitRatiosH.append(gitDefaultRatioH)

        // Hide current tab container + git panel/divider if exists
        if !splitContainers.isEmpty && activeTab < splitContainers.count {
            splitContainers[activeTab].isHidden = true
            if activeTab < tabGitPanels.count {
                tabGitPanels[activeTab]?.isHidden = true
                tabGitDividers[activeTab]?.isHidden = true
            }
        }

        termViews.append(tv)
        splitContainers.append(container)
        tabTypes.append(.terminal)
        tabEditorViews.append(nil)
        tabEditorURLs.append(nil)
        tabEditorDirty.append(false)
        activeTab = splitContainers.count - 1
        container.alphaValue = 0
        window.contentView?.addSubview(container)
        window.makeFirstResponder(tv)

        // Fade-in animation for new tab
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            container.animator().alphaValue = 1
        })

        headerView.setGitActive(false)
        updateSplitButtonState()
        updateHeaderTabs()
        updateFooter()
        // If a sidebar is open, resize new container to account for it
        layoutGitPanel()
        saveSession()
    }

    func closeTab(index: Int) {
        guard index >= 0 && index < splitContainers.count && splitContainers.count > 1 else { return }
        let container = splitContainers[index]
        termViews.remove(at: index)
        splitContainers.remove(at: index)
        // Clean up editor tab data
        if index < tabTypes.count {
            if tabTypes[index] == .editor {
                tabEditorViews[index]?.removeFromSuperview()
            }
            tabTypes.remove(at: index)
        }
        if index < tabEditorViews.count { tabEditorViews.remove(at: index) }
        if index < tabEditorURLs.count  { tabEditorURLs.remove(at: index)  }
        if index < tabEditorDirty.count { tabEditorDirty.remove(at: index) }
        if index < tabColors.count { tabColors.remove(at: index) }
        if index < tabCustomNames.count { tabCustomNames.remove(at: index) }
        if index < tabGitPanels.count {
            tabGitPanels[index]?.stopRefreshing()
            tabGitPanels[index]?.removeFromSuperview()
            tabGitDividers[index]?.removeFromSuperview()
            tabGitPanels.remove(at: index)
            tabGitDividers.remove(at: index)
            tabGitPositions.remove(at: index)
            tabGitRatios.remove(at: index)
            tabGitRatiosV.remove(at: index)
            tabGitRatiosH.remove(at: index)
        }

        // Adjust activeTab
        if activeTab >= splitContainers.count {
            activeTab = splitContainers.count - 1
        } else if activeTab > index {
            activeTab -= 1
        } else if activeTab == index {
            activeTab = min(index, splitContainers.count - 1)
        }

        // Show the new active tab container with fade-in
        for (i, sc) in splitContainers.enumerated() {
            if i == activeTab {
                sc.isHidden = false
                sc.alphaValue = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    sc.animator().alphaValue = 1
                })
            } else {
                sc.isHidden = true
            }
        }

        // Fade-out closed tab container then remove
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            container.animator().alphaValue = 0
        }, completionHandler: {
            container.removeFromSuperview()
        })

        if activeTab >= 0 && activeTab < splitContainers.count {
            if let ev = activeTab < tabEditorViews.count ? tabEditorViews[activeTab] : nil {
                window.makeFirstResponder(ev.textView)
            } else if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
                window.makeFirstResponder(tv)
            }
        }
        // Ensure new active tab's git panel is visible
        if activeTab < tabGitPanels.count {
            tabGitPanels[activeTab]?.isHidden = false
            tabGitDividers[activeTab]?.isHidden = false
        }
        headerView.setGitActive(activeTab < tabGitPositions.count && tabGitPositions[activeTab] != .none)
        layoutGitPanel()
        updateSplitButtonState()
        updateHeaderTabs()
        updateFooter()
        saveSession()
    }

    @objc func closeCurrentTab() {
        if splitContainers.count > 1 {
            closeTab(index: activeTab)
        } else {
            hideWindowAnimated()
        }
    }

    // ── Editor Tab Management ──────────────────────────────────────────────

    func createEditorTab(url: URL? = nil) {
        let tf = termFrame()
        let ev = EditorView(frame: tf)
        ev.autoresizingMask = [.width, .height]

        // Detect current dark/light mode
        let themeKey = UserDefaults.standard.integer(forKey: "colorTheme")
        let dark: Bool
        switch themeKey {
        case 1:  dark = false
        case 2:  dark = true   // OLED
        default: dark = NSApp.effectiveAppearance.name != .aqua
        }
        ev.isDark = dark
        ev.useTabs = UserDefaults.standard.bool(forKey: "editorUseTabs")

        ev.onDirtyChanged = { [weak self, weak ev] dirty in
            guard let self, let ev else { return }
            if let idx = self.tabEditorViews.firstIndex(where: { $0 === ev }) {
                if idx < self.tabEditorDirty.count { self.tabEditorDirty[idx] = dirty }
            }
            self.updateHeaderTabs()
        }

        if let url { try? ev.loadFile(url: url) }

        // Parallel arrays
        let hue = CGFloat.random(in: 0...1)
        tabColors.append(NSColor(calibratedHue: hue, saturation: 0.65, brightness: 0.85, alpha: 1.0))
        tabCustomNames.append(nil)
        tabGitPositions.append(.none)
        tabGitPanels.append(nil)
        tabGitDividers.append(nil)
        tabGitRatios.append(gitDefaultRatioH)
        tabGitRatiosV.append(gitDefaultRatioV)
        tabGitRatiosH.append(gitDefaultRatioH)

        // Hide current tab
        if !splitContainers.isEmpty && activeTab < splitContainers.count {
            splitContainers[activeTab].isHidden = true
            if activeTab < tabGitPanels.count {
                tabGitPanels[activeTab]?.isHidden = true
                tabGitDividers[activeTab]?.isHidden = true
            }
            if activeTab < tabEditorViews.count { tabEditorViews[activeTab]?.isHidden = true }
        }

        // Placeholder SplitContainer for editor tabs (no terminal)
        let placeholder = SplitContainer(placeholderFrame: tf)
        placeholder.autoresizingMask = [.width, .height]

        termViews.append(nil)
        splitContainers.append(placeholder)
        tabTypes.append(.editor)
        tabEditorViews.append(ev)
        tabEditorURLs.append(url)
        tabEditorDirty.append(false)

        activeTab = splitContainers.count - 1

        window.contentView?.addSubview(ev)
        ev.frame = tf
        ev.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ev.animator().alphaValue = 1
        })
        window.makeFirstResponder(ev.textView)

        headerView.setGitActive(false)
        updateHeaderTabs()
        updateFooter()
        saveSession()
    }

    @objc func openEditorTab() {
        let panel = NSOpenPanel()
        panel.canChooseFiles         = true
        panel.canChooseDirectories   = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self?.createEditorTab(url: url) }
        }
    }

    @objc func newEditorTab() {
        createEditorTab(url: nil)
    }

    func saveCurrentEditor() {
        guard activeTab < tabEditorViews.count,
              let ev = tabEditorViews[activeTab] else { return }
        if ev.fileURL != nil {
            try? ev.saveFile()
            updateHeaderTabs()
        } else {
            saveCurrentEditorAs()
        }
    }

    func saveCurrentEditorAs() {
        guard activeTab < tabEditorViews.count,
              let ev = tabEditorViews[activeTab] else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.txt"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            try? ev.saveFile(to: url)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.activeTab < self.tabEditorURLs.count {
                    self.tabEditorURLs[self.activeTab] = url
                }
                self.updateHeaderTabs()
            }
        }
    }

    func reorderTab(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0,
              from < splitContainers.count, to < splitContainers.count,
              from < tabColors.count, to < tabColors.count else { return }
        let tv = termViews.remove(at: from)
        termViews.insert(tv, at: to)
        let sc = splitContainers.remove(at: from)
        splitContainers.insert(sc, at: to)
        if from < tabTypes.count && to < tabTypes.count {
            let tt = tabTypes.remove(at: from)
            tabTypes.insert(tt, at: to)
        }
        if from < tabEditorViews.count && to < tabEditorViews.count {
            let ev = tabEditorViews.remove(at: from)
            tabEditorViews.insert(ev, at: to)
        }
        if from < tabEditorURLs.count && to < tabEditorURLs.count {
            let u = tabEditorURLs.remove(at: from)
            tabEditorURLs.insert(u, at: to)
        }
        if from < tabEditorDirty.count && to < tabEditorDirty.count {
            let d = tabEditorDirty.remove(at: from)
            tabEditorDirty.insert(d, at: to)
        }
        let color = tabColors.remove(at: from)
        tabColors.insert(color, at: to)
        if from < tabCustomNames.count && to < tabCustomNames.count {
            let name = tabCustomNames.remove(at: from)
            tabCustomNames.insert(name, at: to)
        }
        if from < tabGitPositions.count && to < tabGitPositions.count {
            let pos = tabGitPositions.remove(at: from)
            tabGitPositions.insert(pos, at: to)
            let panel = tabGitPanels.remove(at: from)
            tabGitPanels.insert(panel, at: to)
            let div = tabGitDividers.remove(at: from)
            tabGitDividers.insert(div, at: to)
            let ratio = tabGitRatios.remove(at: from)
            tabGitRatios.insert(ratio, at: to)
            let rv = tabGitRatiosV.remove(at: from)
            tabGitRatiosV.insert(rv, at: to)
            let rh = tabGitRatiosH.remove(at: from)
            tabGitRatiosH.insert(rh, at: to)
        }
        if activeTab == from {
            activeTab = to
        } else if from < activeTab && to >= activeTab {
            activeTab -= 1
        } else if from > activeTab && to <= activeTab {
            activeTab += 1
        }
        updateHeaderTabs()
        saveSession()
    }

    func switchSplitPane() {
        guard activeTab >= 0 && activeTab < splitContainers.count else { return }
        guard activeTab >= tabTypes.count || tabTypes[activeTab] == .terminal else { return }
        let container = splitContainers[activeTab]
        guard container.isSplit, let sec = container.secondaryView else { return }
        let newPrimary = !container.activePaneIsPrimary
        let target: TerminalView = newPrimary ? container.primaryView : sec
        window.makeFirstResponder(target)
        container.setActivePane(primary: newPrimary)
        container.onFocusChanged?(target)
    }

    func makeSecondaryExitHandler(container: SplitContainer, sec: TerminalView) -> () -> Void {
        return { [weak self, weak container, weak sec] in
            guard let self = self, let container = container, let sec = sec else { return }
            if let secView = container.secondaryView, secView === sec {
                _ = container.unsplit()
                self.window.makeFirstResponder(container.primaryView)
                self.updateFooter()
                self.updateSplitButtonState()
            }
        }
    }

    func toggleSplit(vertical: Bool) {
        guard activeTab >= 0 && activeTab < splitContainers.count else { return }
        guard activeTab >= tabTypes.count || tabTypes[activeTab] == .terminal else { return }
        let container = splitContainers[activeTab]

        if container.isSplit {
            let sameDirection = container.isVerticalSplit == vertical
            // Close current split
            if let sec = container.unsplit() {
                if sec.childPid > 0 { kill(sec.childPid, SIGHUP) }
            }
            window.makeFirstResponder(container.primaryView)
            updateFooter()
            if sameDirection {
                headerView.setSplitActive(vertical: vertical, active: false)
            }
            // If different direction requested, immediately open new split
            if !sameDirection {
                toggleSplit(vertical: vertical)
            }
        } else {
            // Create split
            let primary: TerminalView = container.primaryView
            let cwd = cwdForPid(primary.childPid)
            let tf = container.bounds
            let secFrame: NSRect
            if vertical {
                secFrame = NSRect(x: tf.width / 2, y: 0, width: tf.width / 2, height: tf.height)
            } else {
                secFrame = NSRect(x: 0, y: 0, width: tf.width, height: tf.height / 2)
            }
            let sec = TerminalView(frameRect: secFrame, shell: primary.currentShell, cwd: cwd)
            sec.onShellExit = makeSecondaryExitHandler(container: container, sec: sec)
            container.split(vertical: vertical, secondary: sec)
            window.makeFirstResponder(sec)
            updateFooter()
            headerView.setSplitActive(vertical: vertical, active: true)
        }
    }

    /// Syncs both split buttons to the current active tab's actual split state.
    func updateSplitButtonState() {
        guard activeTab >= 0 && activeTab < splitContainers.count else {
            headerView.resetSplitButtons(); return
        }
        let container = splitContainers[activeTab]
        if container.isSplit {
            headerView.setSplitActive(vertical: container.isVerticalSplit, active: true)
        } else {
            headerView.resetSplitButtons()
        }
    }

    func applySetting(key: String, value: Any) {
        switch key {
        case "windowOpacity":
            if let v = value as? CGFloat { window.alphaValue = v }
        case "blurIntensity":
            if let v = value as? CGFloat { visualEffect.alphaValue = v }
        case "terminalFontSize":
            guard let size = value as? CGFloat else { return }
            for tv in termViews { tv?.updateFontSize(size) }
            for sc in splitContainers {
                if let sec = sc.secondaryView { sec.updateFontSize(size) }
            }
        case "cursorBlink":
            let blink = UserDefaults.standard.bool(forKey: "cursorBlink")
            for tv in termViews { if let tv { tv.userCursorBlink = blink; tv.setNeedsDisplay(tv.bounds) } }
            for sc in splitContainers {
                if let sec = sc.secondaryView { sec.userCursorBlink = blink; sec.setNeedsDisplay(sec.bounds) }
            }
        case "cursorStyle":
            guard let style = value as? Int else { return }
            for tv in termViews { if let tv { tv.userCursorStyle = style; tv.setNeedsDisplay(tv.bounds) } }
            for sc in splitContainers {
                if let sec = sc.secondaryView { sec.userCursorStyle = style; sec.setNeedsDisplay(sec.bounds) }
            }
        case "alwaysOnTop":
            if let v = value as? Bool {
                window.level = v ? .floating : .normal
                if v {
                    // Auto-disable hide on deactivate — they conflict logically
                    UserDefaults.standard.set(false, forKey: "hideOnDeactivate")
                    if let overlay = settingsOverlay {
                        updateToggleInOverlay(overlay, key: "hideOnDeactivate", value: false)
                    }
                }
            }
        case "followAllSpaces":
            if let v = value as? Bool {
                window.collectionBehavior = v ? [.canJoinAllSpaces] : [.moveToActiveSpace]
            }
        case "autoDim":
            if let on = value as? Bool, !on, !window.isKeyWindow {
                restoreWindowOpacity()
            }
        case "hideOnClickOutside":
            guard let on = value as? Bool else { return }
            if on && globalClickMonitor == nil && window.isVisible {
                globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self = self, self.window.isVisible else { return }
                    if self.isAnyDragSessionActive { return }
                    // Don't hide when clicking on the menu bar
                    let clickLocation = event.locationInWindow
                    if let screen = NSScreen.screens.first(where: { NSMouseInRect(clickLocation, $0.frame, false) }) {
                        if clickLocation.y >= screen.visibleFrame.maxY { return }
                    }
                    self.hideWindowAnimated()
                }
            } else if !on, let monitor = globalClickMonitor {
                NSEvent.removeMonitor(monitor)
                globalClickMonitor = nil
            }
        case "hideOnDeactivate":
            guard let on = value as? Bool else { return }
            if on {
                // Auto-disable always on top — they conflict logically
                UserDefaults.standard.set(false, forKey: "alwaysOnTop")
                window.level = .normal
                // Update toggle in settings UI if visible
                if let overlay = settingsOverlay {
                    updateToggleInOverlay(overlay, key: "alwaysOnTop", value: false)
                }
            }
        case "autoStartEnabled":
            if let v = value as? Bool { SettingsOverlay.setAutoStart(v) }
        case "autoCheckUpdates":
            if let on = value as? Bool {
                if on {
                    scheduleUpdateCheck(initialDelay: 0)
                } else {
                    updateCheckTimer?.invalidate()
                    updateCheckTimer = nil
                }
            }
        case "editorUseTabs":
            let useTabs = UserDefaults.standard.bool(forKey: "editorUseTabs")
            for ev in tabEditorViews.compactMap({ $0 }) {
                ev.useTabs = useTabs
            }
        case "fontFamily":
            let size = CGFloat(UserDefaults.standard.double(forKey: "terminalFontSize"))
            for tv in termViews { tv?.updateFontSize(size) }
            for sc in splitContainers {
                if let sec = sc.secondaryView { sec.updateFontSize(size) }
            }
        case "promptTheme":
            let themeNames = ["default", "cyberpunk", "minimal", "powerline", "retro", "lambda", "starship"]
            guard let idx = value as? Int else { return }
            let themeName = idx < themeNames.count ? themeNames[idx] : "default"
            UserDefaults.standard.set(themeName, forKey: "promptTheme")
            let themeDir = TerminalView.shellConfigDir + "/themes"
            let allViews: [TerminalView] = termViews.compactMap { $0 } + splitContainers.compactMap { $0.secondaryView }
            for tv in allViews {
                tv.writePTY(Data([0x15]))  // Ctrl+U clear line
                tv.writePTY(" export QT_PROMPT_THEME='\(themeName)'; source '\(themeDir)/qt-theme-loader.sh'; clear\n")
            }
        case "colorTheme":
            let idx = value as? Int ?? 0
            let t: TerminalTheme
            switch idx {
            case 1:  t = .light
            case 2:  t = .oledBlack
            case 3:  t = resolveSystemTheme()
            default: t = .dark
            }
            applyTheme(t)
            visualEffect.material = t.visualMaterial
            // Force NSAppearance so material renders correctly regardless of system theme
            switch idx {
            case 1:  visualEffect.appearance = NSAppearance(named: .aqua)
            case 3:  applySystemThemeAppearance(to: visualEffect)
            default: visualEffect.appearance = NSAppearance(named: .darkAqua)
            }
            for tv in termViews { tv?.needsDisplay = true }
            for sc in splitContainers {
                if let sec = sc.secondaryView { sec.needsDisplay = true }
            }
        case "resetDefaults":
            // --- Full factory reset: delete ALL quickTerminal data from system ---
            let fm = FileManager.default
            let home = NSHomeDirectory()

            // A) Delete ~/.quickterminal/ directory (shell history files)
            try? fm.removeItem(atPath: home + "/.quickterminal")

            // B) Remove LaunchAgent via existing abstraction
            SettingsOverlay.setAutoStart(false)

            // C) Wipe ALL UserDefaults for this app (complete clean slate)
            if let bundleId = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
            } else {
                for key in UserDefaults.standard.dictionaryRepresentation().keys {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }

            // D) Delete caches & stray preference files
            let cachesDir = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?.path ?? (home + "/Library/Caches")
            let prefsDir  = home + "/Library/Preferences"
            let toDelete = [
                cachesDir + "/com.l3v0.quickterminal",   // app cache
                cachesDir + "/quickTerminal",              // standalone-binary cache
                prefsDir  + "/quickTerminal.plist",        // standalone-binary prefs
            ]
            for path in toDelete { try? fm.removeItem(atPath: path) }

            // E) Re-register defaults so the app works correctly this session
            for (k, v) in SettingsOverlay.defaultSettings {
                UserDefaults.standard.set(v, forKey: k)
            }

            // 1. Unsplit all tabs
            for sc in splitContainers {
                if let sec = sc.secondaryView {
                    if sec.childPid > 0 { kill(sec.childPid, SIGHUP) }
                    _ = sc.unsplit()
                }
            }

            // 2. Clear all histories
            for tv in termViews {
                tv?.clearScrollback(nil)
            }

            // 3. Close all tabs except the first, reset that one
            while splitContainers.count > 1 {
                let idx = splitContainers.count - 1
                let container = splitContainers[idx]
                if let tv = idx < termViews.count ? termViews[idx] : nil {
                    if tv.childPid > 0 { kill(tv.childPid, SIGHUP) }
                }
                termViews.remove(at: idx)
                splitContainers.remove(at: idx)
                if idx < tabTypes.count { tabTypes.remove(at: idx) }
                if idx < tabEditorViews.count { tabEditorViews[idx]?.removeFromSuperview(); tabEditorViews.remove(at: idx) }
                if idx < tabEditorURLs.count  { tabEditorURLs.remove(at: idx) }
                if idx < tabEditorDirty.count { tabEditorDirty.remove(at: idx) }
                if idx < tabColors.count { tabColors.remove(at: idx) }
                container.removeFromSuperview()
            }
            activeTab = 0
            if !splitContainers.isEmpty {
                splitContainers[0].isHidden = false
                splitContainers[0].alphaValue = 1
            }

            // 4. Restart shell in first tab
            if !termViews.isEmpty, let tv = termViews[0] {
                if tv.childPid > 0 { kill(tv.childPid, SIGHUP) }
                tv.switchShell("/bin/zsh")
            }

            // 5. Apply visual defaults
            window.alphaValue = 0.99
            visualEffect.alphaValue = 0.96
            window.level = .floating
            for tv in termViews { tv?.userCursorStyle = 0; tv?.updateFontSize(10.0) }

            // 6. Reset window size/position and center under tray icon
            let defaultSize = NSSize(width: 860, height: 480)
            var newFrame = window.frame
            newFrame.size = defaultSize
            // Center under tray icon
            if let button = statusItem.button, let btnWindow = button.window {
                let btnRect = button.convert(button.bounds, to: nil)
                let screenRect = btnWindow.convertToScreen(btnRect)
                newFrame.origin.x = screenRect.midX - defaultSize.width / 2
                newFrame.origin.y = screenRect.minY - 4 - defaultSize.height
            } else {
                newFrame.origin.x = window.frame.midX - defaultSize.width / 2
                newFrame.origin.y = window.frame.maxY - defaultSize.height
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                window.animator().setFrame(newFrame, display: true)
            }
            updateWindowMask()

            // 7. Re-enable click outside monitor
            if let monitor = globalClickMonitor {
                NSEvent.removeMonitor(monitor)
                globalClickMonitor = nil
            }
            if window.isVisible {
                globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self = self, self.window.isVisible else { return }
                    self.hideWindowAnimated()
                }
            }

            // 8. Update UI
            updateHeaderTabs()
            updateFooter()

            hideSettings()
        case "defaultShellIndex":
            break // read when creating new tab
        case "copyOnSelect":
            break // read in mouseUp
        case "showAIUsage":
            let on = value as? Bool ?? false
            footerView.usageBadge.isHidden = !on
            if on {
                let intervals: [TimeInterval] = [300, 600, 1800]
                let idx = UserDefaults.standard.integer(forKey: "aiUsageRefreshIndex")
                AIUsageManager.shared.startPolling(interval: intervals[min(idx, 2)])
            } else {
                AIUsageManager.shared.stopPolling()
                if let pop = usagePopover { pop.removeFromSuperview(); usagePopover = nil }
            }
            footerView.needsLayout = true
        case "aiUsageRefreshIndex":
            let intervals: [TimeInterval] = [300, 600, 1800]
            let idx = value as? Int ?? 1
            AIUsageManager.shared.updateInterval(intervals[min(idx, 2)])
        default: break
        }
    }

    private func updateToggleInOverlay(_ overlay: SettingsOverlay, key: String, value: Bool) {
        // Find toggle in overlay's content and update it
        overlay.updateToggle(forKey: key, value: value)
    }

    func toggleUsagePopover() {
        if let pop = usagePopover {
            pop.removeFromSuperview()
            usagePopover = nil
            if let m = usagePopoverMonitor { NSEvent.removeMonitor(m); usagePopoverMonitor = nil }
            return
        }
        guard let contentView = window.contentView else { return }
        let popW: CGFloat = 220
        let popH: CGFloat = 200
        let footerH = FooterBarView.barHeight
        let badge = footerView.usageBadge!
        let badgeMid = badge.convert(NSPoint(x: badge.bounds.midX, y: 0), to: contentView)

        let pop = AIUsagePopover(frame: NSRect(
            x: min(max(badgeMid.x - popW / 2, 8), contentView.bounds.width - popW - 8),
            y: footerH + 4,
            width: popW, height: popH))
        pop.update(data: AIUsageManager.shared.latestData)
        pop.onRefresh = { AIUsageManager.shared.fetchUsage() }
        contentView.addSubview(pop)
        usagePopover = pop

        // Dismiss on click outside popover
        usagePopoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let pop = self.usagePopover else { return event }
            let loc = pop.convert(event.locationInWindow, from: nil)
            // Also allow clicks on the badge itself (to toggle)
            let badgeLoc = self.footerView.usageBadge.convert(event.locationInWindow, from: nil)
            if !pop.bounds.contains(loc) && !self.footerView.usageBadge.bounds.contains(badgeLoc) {
                pop.removeFromSuperview()
                self.usagePopover = nil
                if let m = self.usagePopoverMonitor { NSEvent.removeMonitor(m); self.usagePopoverMonitor = nil }
            }
            return event
        }
    }

    func toggleSettings() {
        if settingsOverlay != nil {
            hideSettings()
        } else {
            showSettings()
        }
    }

    func showSettings() {
        guard settingsOverlay == nil else { return }

        // Reset gear hover state — overlay covers it so mouseExited won't fire
        footerView.gearBtn.resetGearToNormal()

        let bounds = window.contentView?.bounds ?? .zero
        let footerH = FooterBarView.barHeight
        let overlayH = (bounds.height - footerH - arrowH) * 2 / 3

        let overlay = SettingsOverlay(frame: NSRect(x: 0, y: footerH - overlayH,
                                                     width: bounds.width, height: overlayH))
        overlay.autoresizingMask = [.width]
        overlay.onClose = { [weak self] in self?.hideSettings() }
        overlay.onChanged = { [weak self] key, value in
            self?.applySetting(key: key, value: value)
        }
        overlay.alphaValue = 0  // Start invisible behind footer

        // Add overlay on top of everything, then re-add footer above it
        window.contentView?.addSubview(overlay)
        settingsOverlay = overlay
        let fv = footerView!
        fv.removeFromSuperview()
        window.contentView?.addSubview(fv)

        // Two-phase animation: slide up, fade in at halfway point
        let totalDuration: TimeInterval = 0.35
        let endY = footerH
        let midY = footerH - overlayH / 2 + overlayH  // halfway point

        // Phase 1: slide from hidden to halfway — still invisible
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = totalDuration * 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            overlay.animator().frame = NSRect(x: 0, y: midY - overlayH,
                                              width: bounds.width, height: overlayH)
        }, completionHandler: {
            // Phase 2: continue sliding + fade in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = totalDuration * 0.6
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                overlay.animator().frame = NSRect(x: 0, y: endY,
                                                  width: bounds.width, height: overlayH)
                overlay.animator().alphaValue = 1
            })
        })
    }

    func hideSettings() {
        guard let overlay = settingsOverlay else { return }

        // Reset gear button to normal state
        footerView.gearBtn.resetGearToNormal()

        let footerH = FooterBarView.barHeight
        let endY = footerH - overlay.frame.height

        // Fade out first half, then slide behind footer
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                overlay.animator().frame = NSRect(x: 0, y: endY,
                    width: overlay.frame.width, height: overlay.frame.height)
            }, completionHandler: {
                overlay.removeFromSuperview()
                self?.settingsOverlay = nil
            })
        })
    }

    func switchToTab(_ index: Int) {
        guard index >= 0 && index < splitContainers.count && index != activeTab else { return }
        let oldTab = activeTab
        let oldContainer = splitContainers[activeTab]
        activeTab = index
        let newContainer = splitContainers[activeTab]

        // Hide old tab's git panel
        if oldTab < tabGitPanels.count {
            tabGitPanels[oldTab]?.isHidden = true
            tabGitDividers[oldTab]?.isHidden = true
        }

        // Hide old editor view, show new one if applicable
        if oldTab < tabEditorViews.count { tabEditorViews[oldTab]?.isHidden = true }
        if activeTab < tabEditorViews.count { tabEditorViews[activeTab]?.isHidden = false }

        // Crossfade containers
        newContainer.isHidden = false
        newContainer.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            oldContainer.animator().alphaValue = 0
            newContainer.animator().alphaValue = 1
        }, completionHandler: {
            oldContainer.isHidden = true
            oldContainer.alphaValue = 1
        })

        // Show new tab's git panel
        if activeTab < tabGitPanels.count {
            tabGitPanels[activeTab]?.isHidden = false
            tabGitDividers[activeTab]?.isHidden = false
        }
        layoutGitPanel()
        headerView.setGitActive(activeTab < tabGitPositions.count && tabGitPositions[activeTab] != .none)
        updateSplitButtonState()

        if let ev = activeTab < tabEditorViews.count ? tabEditorViews[activeTab] : nil {
            window.makeFirstResponder(ev.textView)
        } else if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
            window.makeFirstResponder(tv)
        }
        clearSearchState()
        updateHeaderTabs()
        updateFooter()
    }

    func resizeWindowAnimated(to size: NSSize) {
        let midX = window.frame.midX
        let topY = window.frame.maxY          // anchor top edge, not bottom
        var f = window.frame
        f.size = size
        f.origin.x = midX - size.width / 2
        f.origin.y = topY - size.height       // keep top fixed
        if let screen = window.screen ?? NSScreen.main {
            let minY = screen.visibleFrame.minY
            if f.origin.y < minY { f.origin.y = minY }
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            window.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in
            self?.updateWindowMask()
        })
    }

    func updateHeaderTabs() {
        let home = NSHomeDirectory()
        let count = splitContainers.count
        let titles = (0..<count).map { i -> String in
            // Editor tab title
            if i < tabTypes.count && tabTypes[i] == .editor {
                let dirty = i < tabEditorDirty.count && tabEditorDirty[i]
                let name: String
                if let url = i < tabEditorURLs.count ? tabEditorURLs[i] : nil {
                    name = url.lastPathComponent
                } else {
                    name = "Untitled"
                }
                return dirty ? "● \(name)" : name
            }
            // Terminal tab title
            if let custom = i < tabCustomNames.count ? tabCustomNames[i] : nil { return custom }
            if let tv = i < termViews.count ? termViews[i] : nil {
                let pid = tv.childPid
                if pid > 0 {
                    let cwd = cwdForPid(pid)
                    if cwd == home { return "~" }
                    return (cwd as NSString).lastPathComponent
                }
            }
            return "~"
        }
        headerView.updateTabs(count: count, activeIndex: activeTab,
                              titles: titles, colors: tabColors)
    }

    func updateFooter() {
        guard !splitContainers.isEmpty && activeTab < splitContainers.count else { return }
        // Editor mode: hide terminal-specific footer content
        if activeTab < tabTypes.count && tabTypes[activeTab] == .editor {
            footerView.isHidden = true
            return
        }
        footerView.isHidden = false
        // Use the focused pane (may be secondary in split mode)
        let container = splitContainers[activeTab]
        let tv: TerminalView
        if container.isSplit && !container.activePaneIsPrimary,
           let sec = container.secondaryView {
            tv = sec
        } else {
            guard let primaryTV = activeTab < termViews.count ? termViews[activeTab] : nil else { return }
            tv = primaryTV
        }
        let pid = tv.childPid
        if pid > 0 {
            footerView.update(shell: tv.currentShell, pid: pid)
        }
    }

    @objc func toggleWebPicker() {
        if webPickerSidebarView != nil {
            hideWebPickerSidebar()
        } else {
            showWebPickerSidebar()
        }
    }

    private func showWebPickerSidebar() {
        guard activeTab >= 0, activeTab < splitContainers.count else { return }
        guard let superview = splitContainers[activeTab].superview else { return }

        let view = WebPickerSidebarView()
        view.onClose = { [weak self] in self?.toggleWebPicker() }
        view.onConnected = { [weak self] in self?.snapRightFull() }
        view.onMoveUp   = { [weak self] in self?.moveSidebarPanel("picker", direction: -1) }
        view.onMoveDown = { [weak self] in self?.moveSidebarPanel("picker", direction:  1) }
        view.alphaValue = 0
        superview.addSubview(view)
        webPickerSidebarView = view

        layoutGitPanel()
        headerView.setWebPickerActive(true)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            view.animator().alphaValue = 1
            webPickerRightDivider?.animator().alphaValue = 1
        })
        view.connect()
    }

    private func hideWebPickerSidebar() {
        webPickerSidebarView?.disconnect()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.webPickerSidebarView?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.webPickerSidebarView?.removeFromSuperview()
            self.webPickerSidebarView = nil
            self.headerView.setWebPickerActive(false)
            self.layoutGitPanel()
        })
    }

    func handleWebPickerDividerDrag(_ delta: CGFloat) {
        guard activeTab >= 0, activeTab < tabGitRatiosV.count else { return }
        let tf = termFrame()
        var ratio = tabGitRatiosV[activeTab]
        ratio += (-delta / tf.width)
        ratio = max(0.15, min(0.55, ratio))
        tabGitRatiosV[activeTab] = ratio
        layoutGitPanel()
    }

    func handleSidebarHDividerDrag(topId: String, botId: String, delta: CGFloat) {
        var topH = sidebarPanelHeights[topId] ?? 260
        var botH = sidebarPanelHeights[botId] ?? 260
        let sum = topH + botH
        topH -= delta
        topH = max(80, min(sum - 80, topH))
        botH = sum - topH
        sidebarPanelHeights[topId] = topH
        sidebarPanelHeights[botId] = botH
        layoutGitPanel()
        if activeTab < splitContainers.count { splitContainers[activeTab].layoutSplit() }
    }

    private func isActiveSidebarPanel(_ id: String) -> Bool {
        switch id {
        case "git":    return activeTab < tabGitPositions.count && tabGitPositions[activeTab] == .right
        case "picker": return webPickerSidebarView != nil
        case "ssh":    return sshManagerView != nil
        default:       return false
        }
    }

    func moveSidebarPanel(_ id: String, direction: Int) {
        let active = sidebarOrder.filter { isActiveSidebarPanel($0) }
        guard let idx = active.firstIndex(of: id) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < active.count else { return }
        let neighborId = active[newIdx]
        guard let si = sidebarOrder.firstIndex(of: id),
              let sj = sidebarOrder.firstIndex(of: neighborId) else { return }
        sidebarOrder.swapAt(si, sj)
        layoutGitPanel()
    }

    func updateSidebarMoveButtons() {
        let active = sidebarOrder.filter { isActiveSidebarPanel($0) }
        let count = active.count
        for (i, sid) in active.enumerated() {
            let canUp   = count > 1 && i > 0
            let canDown = count > 1 && i < count - 1
            switch sid {
            case "git":
                if activeTab < tabGitPanels.count {
                    tabGitPanels[activeTab]?.setMoveButtonsEnabled(up: canUp, down: canDown)
                }
            case "picker": webPickerSidebarView?.setMoveButtonsEnabled(up: canUp, down: canDown)
            case "ssh":    sshManagerView?.setMoveButtonsEnabled(up: canUp, down: canDown)
            default: break
            }
        }
        // Hide buttons when panel is alone
        if count < 2 {
            if activeTab < tabGitPanels.count { tabGitPanels[activeTab]?.setMoveButtonsEnabled(up: false, down: false) }
            webPickerSidebarView?.setMoveButtonsEnabled(up: false, down: false)
            sshManagerView?.setMoveButtonsEnabled(up: false, down: false)
        }
    }

    // MARK: - SSH Manager

    func previewTheme(_ idx: Int) {
        let t: TerminalTheme
        switch idx {
        case 1:  t = .light
        case 2:  t = .oledBlack
        case 3:  t = resolveSystemTheme()
        default: t = .dark
        }
        applyTheme(t)
        visualEffect.material = t.visualMaterial
        switch idx {
        case 1:  visualEffect.appearance = NSAppearance(named: .aqua)
        case 3:  applySystemThemeAppearance(to: visualEffect)
        default: visualEffect.appearance = NSAppearance(named: .darkAqua)
        }
        for tv in termViews { tv?.needsDisplay = true }
        for sc in splitContainers {
            if let sec = sc.secondaryView { sec.needsDisplay = true }
        }
    }

    @objc func toggleSSHManager() {
        if sshManagerView != nil {
            hideSSHManager()
        } else {
            showSSHManager()
        }
    }

    private func showSSHManager() {
        guard activeTab >= 0, activeTab < splitContainers.count else { return }
        guard let superview = splitContainers[activeTab].superview else { return }

        let view = SSHManagerView()
        view.alphaValue = 0
        view.onClose   = { [weak self] in self?.hideSSHManager() }
        view.onMoveUp   = { [weak self] in self?.moveSidebarPanel("ssh", direction: -1) }
        view.onMoveDown = { [weak self] in self?.moveSidebarPanel("ssh", direction:  1) }
        view.onConnect = { [weak self] profile in
            guard let self = self else { return }
            self.addTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let tv = self.activeTab < self.termViews.count ? self.termViews[self.activeTab] : nil {
                    tv.writePTY(profile.connectCommand + "\n")
                }
            }
        }
        superview.addSubview(view)
        sshManagerView = view

        layoutGitPanel()
        headerView.setSSHActive(true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            view.animator().alphaValue = 1
        }
    }

    private func hideSSHManager() {
        guard sshManagerView != nil else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.sshManagerView?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.sshManagerView?.removeFromSuperview()
            self.sshManagerView = nil
            self.headerView.setSSHActive(false)
            self.layoutGitPanel()
        })
    }

    // MARK: - Git Panel

    @objc func toggleGitPanel() {
        guard activeTab >= 0, activeTab < tabGitPositions.count else { return }
        let current = tabGitPositions[activeTab]

        // Save current ratio to the right slot before switching
        if current == .right { tabGitRatiosV[activeTab] = tabGitRatios[activeTab] }
        else if current == .bottom { tabGitRatiosH[activeTab] = tabGitRatios[activeTab] }

        let next: GitPanelPosition
        switch current {
        case .none:   next = .bottom
        case .bottom: next = .right
        case .right:  next = .none
        }
        tabGitPositions[activeTab] = next

        // Load ratio for the new position
        if next == .right { tabGitRatios[activeTab] = tabGitRatiosV[activeTab] }
        else if next == .bottom { tabGitRatios[activeTab] = tabGitRatiosH[activeTab] }

        if next == .none {
            // Remove git panel
            tabGitPanels[activeTab]?.stopRefreshing()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                self.tabGitPanels[self.activeTab]?.animator().alphaValue = 0
                self.tabGitDividers[self.activeTab]?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                self.tabGitPanels[self.activeTab]?.removeFromSuperview()
                self.tabGitDividers[self.activeTab]?.removeFromSuperview()
                self.tabGitPanels[self.activeTab] = nil
                self.tabGitDividers[self.activeTab] = nil
                self.layoutGitPanel()
            })
            headerView.setGitActive(false)
        } else {
            // Create or reuse panel
            if tabGitPanels[activeTab] == nil {
                let panel = GitPanelView(frame: .zero)
                panel.wantsLayer = true
                panel.alphaValue = 0
                panel.onMoveUp   = { [weak self] in self?.moveSidebarPanel("git", direction: -1) }
                panel.onMoveDown = { [weak self] in self?.moveSidebarPanel("git", direction:  1) }
                let container = splitContainers[activeTab]
                container.superview?.addSubview(panel)
                tabGitPanels[activeTab] = panel

                let divider = GitPanelDividerView()
                divider.isVertical = (tabGitPositions[activeTab] == .right)
                divider.onDrag = { [weak self] delta in self?.handleGitDividerDrag(delta) }
                container.superview?.addSubview(divider)
                tabGitDividers[activeTab] = divider
            }
            layoutGitPanel()

            // Start refreshing with current cwd
            let cwd: String
            if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
                cwd = cwdForPid(tv.childPid)
            } else {
                cwd = NSHomeDirectory()
            }
            tabGitPanels[activeTab]?.startRefreshing(cwd: cwd)

            // Fade in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.tabGitPanels[self.activeTab]?.animator().alphaValue = 1
                self.tabGitDividers[self.activeTab]?.animator().alphaValue = 1
            })
            headerView.setGitActive(true)
        }
    }

    func layoutGitPanel() {
        guard activeTab >= 0, activeTab < splitContainers.count else { return }
        let container = splitContainers[activeTab]
        let tf = termFrame()

        var pos      = activeTab < tabGitPositions.count ? tabGitPositions[activeTab] : .none
        let gitPanel = activeTab < tabGitPanels.count    ? tabGitPanels[activeTab]    : nil
        let gitDiv   = activeTab < tabGitDividers.count  ? tabGitDividers[activeTab]  : nil
        var ratio    = activeTab < tabGitRatios.count    ? tabGitRatios[activeTab]    : gitDefaultRatioH
        let divThick: CGFloat = 2                           // visual strip width (used for layout math)
        let divGrab  = GitPanelDividerView.grab             // extra grab pixels on each side of frame

        // Auto-promote git from bottom → right when other sidebar panels are open
        let hasOtherRightPanels = (webPickerSidebarView != nil) || (sshManagerView != nil)
        if pos == .bottom, gitPanel != nil, hasOtherRightPanels {
            tabGitPositions[activeTab] = .right
            pos   = .right
            ratio = activeTab < tabGitRatiosV.count ? tabGitRatiosV[activeTab] : gitDefaultRatioV
            gitDiv?.isVertical = true
        }

        // ── Collect active right panels in sidebarOrder (top→bottom) ──────────
        struct SidePanel { let id: String; let view: NSView }
        var rightPanels: [SidePanel] = []
        for sid in sidebarOrder {
            switch sid {
            case "git":
                if pos == .right, let gp = gitPanel { rightPanels.append(SidePanel(id: "git", view: gp)) }
            case "picker":
                if let pv = webPickerSidebarView    { rightPanels.append(SidePanel(id: "picker", view: pv)) }
            case "ssh":
                if let sv = sshManagerView          { rightPanels.append(SidePanel(id: "ssh", view: sv)) }
            default: break
            }
        }
        let hasRight = !rightPanels.isEmpty

        // ── Right column width ────────────────────────────────────────────────
        let rightRatio: CGFloat
        if pos == .right && gitPanel != nil {
            rightRatio = ratio
        } else if hasRight {
            rightRatio = activeTab < tabGitRatiosV.count ? tabGitRatiosV[activeTab] : gitDefaultRatioV
        } else {
            rightRatio = 0
        }
        let rightW   = hasRight ? tf.width * rightRatio : 0
        let termW    = tf.width - (hasRight ? rightW + divThick : 0)
        let sidebarX = tf.origin.x + termW + divThick

        // ── Bottom git (no effect on horizontal layout) ───────────────────────
        let hasBottom = pos == .bottom && gitPanel != nil
        let bottomH   = hasBottom ? tf.height * ratio : 0
        let bottomDiv: CGFloat = hasBottom ? divThick : 0
        let termH = tf.height - bottomH - bottomDiv
        let termY = tf.origin.y + bottomH + bottomDiv

        container.frame = NSRect(x: tf.origin.x, y: termY, width: termW, height: termH)

        if hasBottom {
            gitPanel?.isHorizontal = true
            gitDiv?.isVertical = false
            gitPanel?.frame = NSRect(x: tf.origin.x, y: tf.origin.y, width: termW, height: bottomH)
            // Divider frame: expand ±divGrab vertically so the full grab zone IS the frame
            gitDiv?.frame   = NSRect(x: tf.origin.x, y: tf.origin.y + bottomH - divGrab,
                                     width: termW, height: divThick + 2 * divGrab)
        }

        // ── Right sidebar vertical divider (lazy create/remove) ───────────────
        if hasRight {
            if pos == .right, let gd = gitDiv {
                gd.isVertical = true
                // Divider frame: expand ±divGrab horizontally so the full grab zone IS the frame
                gd.frame = NSRect(x: tf.origin.x + termW - divGrab, y: tf.origin.y,
                                  width: divThick + 2 * divGrab, height: tf.height)
                // gitDiv owns the vertical divider for all right panels — remove any stale picker divider
                if webPickerRightDivider != nil {
                    webPickerRightDivider?.removeFromSuperview()
                    webPickerRightDivider = nil
                }
            } else {
                // Lazy create when git is not on right
                if webPickerRightDivider == nil, let sv = rightPanels.first?.view.superview {
                    let d = GitPanelDividerView()
                    d.isVertical = true
                    d.onDrag = { [weak self] delta in self?.handleWebPickerDividerDrag(delta) }
                    sv.addSubview(d)
                    webPickerRightDivider = d
                }
                // Expanded frame: ±divGrab horizontally so the full grab zone IS the frame
                webPickerRightDivider?.frame = NSRect(x: tf.origin.x + termW - divGrab, y: tf.origin.y,
                                                      width: divThick + 2 * divGrab, height: tf.height)
            }
            if pos == .right { gitPanel?.isHorizontal = false }
        } else {
            // No right panels — remove picker's vertical divider
            webPickerRightDivider?.removeFromSuperview()
            webPickerRightDivider = nil
        }

        // ── Stack right panels top→bottom ─────────────────────────────────────
        if hasRight {
            let totalDivH   = CGFloat(rightPanels.count - 1) * divThick
            let availContent = tf.height - totalDivH

            // Scale stored heights to fill available space
            let rawH  = rightPanels.map { sidebarPanelHeights[$0.id] ?? 260 }
            let rawSum = rawH.reduce(0, +)
            let scale = rawSum > 0 ? availContent / rawSum : 1
            var heights = rawH.map { max(60, $0 * scale) }
            // Re-normalize after clamping
            let hSum = heights.reduce(0, +)
            if hSum > 0 { heights = heights.map { $0 * availContent / hSum } }

            // Place panels from top (tf.maxY) downward
            var curY = tf.origin.y + tf.height
            for i in 0..<rightPanels.count {
                let h = heights[i]
                curY -= h
                rightPanels[i].view.frame = NSRect(x: sidebarX, y: curY, width: rightW, height: h)

                if i < rightPanels.count - 1 {
                    curY -= divThick
                    let key = "\(rightPanels[i].id)-\(rightPanels[i+1].id)"
                    let div: GitPanelDividerView
                    if let existing = sidebarHDividers[key] {
                        div = existing
                    } else {
                        let d = GitPanelDividerView()
                        d.isVertical = false
                        let topId = rightPanels[i].id
                        let botId = rightPanels[i+1].id
                        d.onDrag = { [weak self] delta in
                            self?.handleSidebarHDividerDrag(topId: topId, botId: botId, delta: delta)
                        }
                        if let sv = rightPanels[i].view.superview { sv.addSubview(d) }
                        sidebarHDividers[key] = d
                        div = d
                    }
                    // Expanded frame: ±divGrab vertically so the full grab zone IS the frame
                    div.frame = NSRect(x: sidebarX, y: curY - divGrab,
                                       width: rightW, height: divThick + 2 * divGrab)
                }
            }

            // Remove orphaned horizontal dividers
            let activeKeys = Set((0..<rightPanels.count-1).map { "\(rightPanels[$0].id)-\(rightPanels[$0+1].id)" })
            let orphans = sidebarHDividers.keys.filter { !activeKeys.contains($0) }
            for key in orphans { sidebarHDividers.removeValue(forKey: key)?.removeFromSuperview() }
        } else {
            for div in sidebarHDividers.values { div.removeFromSuperview() }
            sidebarHDividers.removeAll()
        }

        updateSidebarMoveButtons()
    }

    func handleGitDividerDrag(_ delta: CGFloat) {
        guard activeTab >= 0, activeTab < tabGitPositions.count else { return }
        let pos = tabGitPositions[activeTab]
        let tf = termFrame()

        var ratio = activeTab < tabGitRatios.count ? tabGitRatios[activeTab] : gitDefaultRatioH
        switch pos {
        case .right:
            // Dragging left = delta negative = panel bigger
            ratio += (-delta / tf.width)
        case .bottom:
            // Dragging up = delta positive = panel bigger
            ratio += (delta / tf.height)
        case .none:
            return
        }
        ratio = max(0.15, min(0.65, ratio))
        tabGitRatios[activeTab] = ratio
        // Also save to the position-specific slot
        if pos == .right { tabGitRatiosV[activeTab] = ratio }
        else if pos == .bottom { tabGitRatiosH[activeTab] = ratio }
        layoutGitPanel()

        // Notify terminal to recalculate
        if activeTab < splitContainers.count {
            splitContainers[activeTab].layoutSplit()
        }
    }

    func updateGitPanelCwd() {
        guard activeTab >= 0, activeTab < tabGitPositions.count,
              tabGitPositions[activeTab] != .none,
              let panel = tabGitPanels[activeTab] else { return }
        let cwd: String
        if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
            cwd = cwdForPid(tv.childPid)
        } else {
            cwd = NSHomeDirectory()
        }
        panel.updateCwd(cwd)
    }

    @objc func statusItemClicked() {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            // Right click → localized context menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: Loc.showHide, action: #selector(toggleWindow), keyEquivalent: ""))
            let detachTitle = isWindowDetached ? Loc.reattachWindow : Loc.detachWindow
            let detachItem = NSMenuItem(title: detachTitle, action: #selector(toggleDetach), keyEquivalent: "")
            detachItem.state = isWindowDetached ? .on : .off
            menu.addItem(detachItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: Loc.newTab, action: #selector(addTab), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "zsh", action: #selector(menuSwitchZsh), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "bash", action: #selector(menuSwitchBash), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "sh", action: #selector(menuSwitchSh), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: Loc.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil  // reset so left click works again
        } else {
            toggleWindow()
        }
    }

    func positionWindowUnderTrayIcon() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let wSize = window.frame.size
        // Y is ALWAYS calculated from the tray icon — never from saved value.
        // Using a saved Y after resize causes a small rounding drift (~3px on Retina)
        // because the saved value and the tray calculation can disagree by 1-2 points.
        let y = round(screenRect.minY - 4 - wSize.height)
        // Sanity check: if the status-bar button hasn't been placed by macOS yet,
        // convertToScreen returns a bogus rect near (0, -11). A real menu-bar button
        // is always near the TOP of a screen so y must be positive.
        guard y > 0 else { return }
        // X uses saved value if available (respects user horizontal resize preference).
        let defaultX = round(screenRect.midX - wSize.width / 2)
        let x: CGFloat
        if UserDefaults.standard.object(forKey: "windowX") != nil {
            let sx = CGFloat(UserDefaults.standard.double(forKey: "windowX"))
            let testRect = NSRect(origin: NSPoint(x: sx, y: y), size: wSize)
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(testRect) }
            x = onScreen ? sx : defaultX
        } else {
            x = defaultX
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc func toggleWindow() {
        // If an animation is in progress, queue this toggle and let the completion handler execute it
        if isAnimating {
            pendingToggle = !pendingToggle
            return
        }
        pendingToggle = false  // clear any stale pending on fresh (non-animated) toggle

        // Detached: just show/hide at current position — never auto-reattach
        if isWindowDetached {
            if window.isVisible {
                hideWindowAnimated()
            } else {
                isAnimating = true
                window.alphaValue = 0
                let lvl = UserDefaults.standard.bool(forKey: "alwaysOnTop")
                    ? NSWindow.Level.floating : .normal
                window.level = lvl
                window.makeKeyAndOrderFront(nil)
                if #available(macOS 14.0, *) { NSApp.activate() }
                else { NSApp.activate(ignoringOtherApps: true) }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.window.animator().alphaValue = 1
                }, completionHandler: { [weak self] in
                    guard let self = self else { return }
                    self.isAnimating = false
                    if self.pendingToggle { self.pendingToggle = false; self.toggleWindow() }
                })
            }
            return
        }
        if window.isVisible {
            // Check if window is on a different space — if so, move it here and re-show
            if !window.isOnActiveSpace {
                window.orderOut(nil)
                window.alphaValue = 0
                isAnimating = false
                if let monitor = globalClickMonitor {
                    NSEvent.removeMonitor(monitor)
                    globalClickMonitor = nil
                }
                showWindowAnimated()
            } else {
                hideWindowAnimated()
            }
        } else {
            showWindowAnimated()
        }
    }

    @objc func toggleDetach() {
        if isWindowDetached {
            // ── Reattach: fade out → snap to tray → show from tray with arrow ─
            isWindowDetached = false
            UserDefaults.standard.set(false, forKey: "windowDetached")
            (window as? BorderlessWindow)?.isDetached = false
            window.styleMask.remove(.resizable)
            updateWindowMask()
            updateHeaderArrowLayout()
            let wasVisible = window.isVisible
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = wasVisible ? 0.15 : 0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                self.window.alphaValue = 1
                self.window.orderOut(nil)
                // Clear saved detached position so tray calculation is used
                UserDefaults.standard.removeObject(forKey: "windowX")
                UserDefaults.standard.removeObject(forKey: "windowY")
                self.positionWindowUnderTrayIcon()
                self.layoutGitPanel()
                self.showWindowAnimated()   // drop-down from tray with arrow
            })
        } else {
            // ── Detach: float window free at current position ─────────────────
            isWindowDetached = true
            UserDefaults.standard.set(true, forKey: "windowDetached")
            (window as? BorderlessWindow)?.isDetached = true
            window.styleMask.insert(.resizable)
            if !window.isVisible { window.makeKeyAndOrderFront(nil) }
            updateWindowMask()
            updateHeaderArrowLayout()
            layoutGitPanel()
        }
    }

    /// Called on launch when the window was in detached mode during the previous session.
    func restoreDetachedWindowState() {
        isWindowDetached = true
        (window as? BorderlessWindow)?.isDetached = true
        window.styleMask.insert(.resizable)
        updateWindowMask()
        updateHeaderArrowLayout()
        layoutGitPanel()

        // Restore saved position (X and Y both saved for detached windows)
        let savedX = UserDefaults.standard.double(forKey: "windowX")
        let savedY = UserDefaults.standard.double(forKey: "windowY")
        if savedX != 0 || savedY != 0 {
            let origin = NSPoint(x: CGFloat(savedX), y: CGFloat(savedY))
            let testRect = NSRect(origin: origin, size: window.frame.size)
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(testRect) }
            if onScreen { window.setFrameOrigin(origin) }
        }

        // Show immediately at restored position — no fade-in animation at startup.
        // A fade-in with alphaValue=0 + makeKeyAndOrderFront leaves window in an
        // "isVisible=true but alpha=0" state if anything blocks the animation,
        // causing the first tray-click to hide instead of show.
        let targetLevel = UserDefaults.standard.bool(forKey: "alwaysOnTop")
            ? NSWindow.Level.floating : .normal
        window.level = targetLevel
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
        if !splitContainers.isEmpty && activeTab < splitContainers.count {
            if let ev = activeTab < tabEditorViews.count ? tabEditorViews[activeTab] : nil {
                window.makeFirstResponder(ev.textView)
            } else if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
                window.makeFirstResponder(tv)
            }
        }
    }

    /// Hides/shows arrow tint and shifts headerView up when detached (no arrow = no gap).
    private func updateHeaderArrowLayout() {
        arrowTintView?.isHidden = isWindowDetached
        guard let hv = headerView, let cv = window.contentView else { return }
        let w = cv.bounds.width
        let headerH = HeaderBarView.barHeight
        let topOffset: CGFloat = isWindowDetached ? 0 : arrowH
        hv.frame = NSRect(x: 0, y: cv.bounds.height - headerH - topOffset,
                          width: w, height: headerH)
    }

    // MARK: Double-Ctrl → Command Palette

    func handleFlagsChanged(_ event: NSEvent) {
        let ctrlDown = event.modifierFlags.contains(.control)
        if ctrlDown && !ctrlWasDown {
            // Ctrl pressed — check for double-tap
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastCtrlPressTime < 0.35 {
                lastCtrlPressTime = 0
                toggleCommandPalette()
            } else {
                lastCtrlPressTime = now
            }
        }
        ctrlWasDown = ctrlDown
    }

    func paletteCommands() -> [PaletteCommand] {
        let ud = UserDefaults.standard
        let onOff: (String) -> String = { ud.bool(forKey: $0) ? "on" : "off" }
        let opacityPct = Int(ud.double(forKey: "windowOpacity") * 100)
        let blurPct = Int(ud.double(forKey: "blurIntensity") * 100)
        let fontSize = Int(ud.double(forKey: "terminalFontSize"))
        let themeNames = ["default", "cyberpunk", "minimal", "powerline", "retro", "lambda", "starship"]
        let themeIdx = ud.integer(forKey: "promptTheme") < themeNames.count ? ud.integer(forKey: "promptTheme") : 0
        let themeName = themeNames[themeIdx]
        let fontNames = TerminalView.availableFonts.map { $0.0 }
        let fontIdx = ud.integer(forKey: "fontFamily")
        let fontName = fontIdx < fontNames.count ? fontNames[fontIdx] : "System"
        let shellNames = ["zsh", "bash", "sh"]
        let shellIdx = ud.integer(forKey: "defaultShellIndex")
        let shellName = shellIdx < shellNames.count ? shellNames[shellIdx] : "zsh"

        return [
            PaletteCommand(title: "Quit", shortcut: "q") { NSApp.terminate(nil) },
            PaletteCommand(title: "New Tab", shortcut: "\u{2318}T") { [weak self] in self?.addTab() },
            PaletteCommand(title: "Close Tab", shortcut: "\u{2318}W") { [weak self] in self?.closeCurrentTab() },
            PaletteCommand(title: "Settings", shortcut: "") { [weak self] in self?.toggleSettings() },
            PaletteCommand(title: "Split Vertical", shortcut: "\u{2318}D") { [weak self] in self?.toggleSplit(vertical: true) },
            PaletteCommand(title: "Split Horizontal", shortcut: "\u{21E7}\u{2318}D") { [weak self] in self?.toggleSplit(vertical: false) },
            PaletteCommand(title: "Reset Window", shortcut: "") { [weak self] in self?.resetWindowSize() },
            PaletteCommand(title: "Always on Top (\(onOff("alwaysOnTop")))", shortcut: "") { [weak self] in self?.promptToggle("Always on Top", key: "alwaysOnTop") },
            PaletteCommand(title: "Auto-Dim (\(onOff("autoDim")))", shortcut: "") { [weak self] in self?.promptToggle("Auto-Dim", key: "autoDim") },
            PaletteCommand(title: "Clear", shortcut: "\u{2318}K") { [weak self] in
                guard let self = self, !self.splitContainers.isEmpty else { return }
                if let tv = self.activeTab < self.termViews.count ? self.termViews[self.activeTab] : nil {
                    tv.clearScrollback(nil)
                }
            },
            PaletteCommand(title: "Hide", shortcut: "Ctrl+<") { [weak self] in self?.toggleWindow() },
            PaletteCommand(title: "Help", shortcut: "?") { [weak self] in
                guard let self = self else { return }
                if self.helpViewer == nil { self.helpViewer = HelpViewer() }
                self.helpViewer?.show(relativeTo: self.window)
            },
            PaletteCommand(title: "Commands", shortcut: "") { [weak self] in
                guard let self = self else { return }
                if self.helpViewer == nil { self.helpViewer = HelpViewer() }
                self.helpViewer?.showCommands(relativeTo: self.window, commands: self.paletteCommands())
            },
            PaletteCommand(title: "Fullscreen", shortcut: "") { [weak self] in self?.toggleFullscreen() },
            PaletteCommand(title: "Horizont", shortcut: "") { [weak self] in self?.toggleHorizont() },
            PaletteCommand(title: "Defaultsize", shortcut: "") { [weak self] in self?.resetWindowSize() },
            PaletteCommand(title: "Vertical", shortcut: "") { [weak self] in self?.toggleVertical() },
            PaletteCommand(title: "Left", shortcut: "") { [weak self] in self?.snapLeft() },
            PaletteCommand(title: "Right", shortcut: "") { [weak self] in self?.snapRight() },
            PaletteCommand(title: "Cursor Block", shortcut: "") { [weak self] in self?.setCursorStyle(2) },
            PaletteCommand(title: "Cursor Beam", shortcut: "") { [weak self] in self?.setCursorStyle(1) },
            PaletteCommand(title: "Cursor Underline", shortcut: "") { [weak self] in self?.setCursorStyle(0) },
            PaletteCommand(title: "Cursor Blink (\(onOff("cursorBlink")))", shortcut: "") { [weak self] in self?.promptToggle("Cursor Blink", key: "cursorBlink") },
            PaletteCommand(title: "Resetsystem", shortcut: "") { [weak self] in self?.confirmResetSystem() },
            // Slider-Befehle
            PaletteCommand(title: "Opacity (\(opacityPct)%)", shortcut: "") { [weak self] in self?.promptSlider("Opacity", key: "windowOpacity", current: "\(opacityPct)%", min: 30, max: 100) },
            PaletteCommand(title: "Blur (\(blurPct)%)", shortcut: "") { [weak self] in self?.promptSlider("Blur", key: "blurIntensity", current: "\(blurPct)%", min: 0, max: 100) },
            PaletteCommand(title: "Fontsize (\(fontSize)pt)", shortcut: "") { [weak self] in self?.promptSlider("Fontsize", key: "terminalFontSize", current: "\(fontSize)pt", min: 8, max: 18) },
            // Auswahl-Befehle
            PaletteCommand(title: "Theme (\(themeName))", shortcut: "") { [weak self] in
                self?.promptChoice("Theme", key: "promptTheme", current: themeName, options: themeNames)
            },
            PaletteCommand(title: "Font (\(fontName))", shortcut: "") { [weak self] in
                self?.promptChoice("Font", key: "fontFamily", current: fontName, options: fontNames)
            },
            PaletteCommand(title: "Shell (\(shellName))", shortcut: "") { [weak self] in
                self?.promptChoice("Shell", key: "defaultShellIndex", current: shellName, options: shellNames)
            },
            // Toggle-Befehle
            PaletteCommand(title: "Syntax Highlighting (\(onOff("syntaxHighlighting")))", shortcut: "") { [weak self] in self?.promptToggle("Syntax Highlighting", key: "syntaxHighlighting") },
            PaletteCommand(title: "Copy on Select (\(onOff("copyOnSelect")))", shortcut: "") { [weak self] in self?.promptToggle("Copy on Select", key: "copyOnSelect") },
            PaletteCommand(title: "Hide on Click Outside (\(onOff("hideOnClickOutside")))", shortcut: "") { [weak self] in self?.promptToggle("Hide on Click Outside", key: "hideOnClickOutside") },
            PaletteCommand(title: "Hide on Deactivate (\(onOff("hideOnDeactivate")))", shortcut: "") { [weak self] in self?.promptToggle("Hide on Deactivate", key: "hideOnDeactivate") },
            PaletteCommand(title: "Launch at Login (\(onOff("autoStartEnabled")))", shortcut: "") { [weak self] in self?.promptToggle("Launch at Login", key: "autoStartEnabled") },
            // Diagnostics commands
            PaletteCommand(title: "Search", shortcut: "") { [weak self] in self?.startScrollbackSearch() },
            PaletteCommand(title: "Perf", shortcut: "") { [weak self] in self?.togglePerfOverlay() },
            PaletteCommand(title: "Parser", shortcut: "") { [weak self] in self?.toggleParserOverlay() },
            // Update commands
            PaletteCommand(title: "Check for Updates", shortcut: "") { [weak self] in self?.manualCheckForUpdate() },
            PaletteCommand(title: pendingRelease != nil ? "Install Update (\(pendingRelease!.tagName))" : "Install Update", shortcut: "") { [weak self] in
                guard let self = self, let release = self.pendingRelease else {
                    self?.showGenericToast(badge: "UPDATE", text: Loc.noUpdateAvailable, badgeColor: NSColor(calibratedWhite: 0.35, alpha: 1.0))
                    return
                }
                self.startUpdateDownload(release: release)
            },
            PaletteCommand(title: "Auto-Check Updates (\(onOff("autoCheckUpdates")))", shortcut: "") { [weak self] in self?.promptToggle("Auto-Check Updates", key: "autoCheckUpdates") },
            PaletteCommand(title: "WebPicker", shortcut: "") { [weak self] in self?.toggleWebPicker() },
            PaletteCommand(title: "Git", shortcut: "") { [weak self] in self?.toggleGitPanel() },
        ]
    }

    func toggleCommandPalette() {
        if let palette = commandPalette, palette.superview != nil {
            palette.dismiss()
            return
        }
        guard window.isVisible else { return }

        let cmds = paletteCommands()

        let bounds = window.contentView?.bounds ?? .zero
        let w = CommandPaletteView.paletteW
        let h = CommandPaletteView.baseHeight()
        let px = (bounds.width - w) / 2
        let py = (bounds.height - h) / 2

        let palette = CommandPaletteView(frame: NSRect(x: px, y: py, width: w, height: h))

        // Suppress ALL implicit layer animations and keep view hidden during setup
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        palette.isHidden = true
        palette.alphaValue = 0
        palette.setup(commands: cmds)
        window.contentView?.addSubview(palette)
        palette.layer?.zPosition = CGFloat.greatestFiniteMagnitude
        commandPalette = palette
        palette.repositionNameLabel()
        palette.nameLabel.alphaValue = 0

        // Pre-configure field editor while view is completely hidden
        palette.activate()
        CATransaction.commit()

        // Now unhide and fade in — field editor is already configured, no flash possible
        palette.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            palette.animator().alphaValue = 1
            palette.nameLabel.animator().alphaValue = 1
        }
    }

    // MARK: - Scrollback Search

    func startScrollbackSearch() {
        guard let palette = commandPalette else { return }
        palette.showInput(prompt: "Search scrollback...") { [weak self] query in
            self?.performScrollbackSearch(query)
        }
    }

    func performScrollbackSearch(_ query: String) {
        guard !splitContainers.isEmpty,
              let tv = activeTab < termViews.count ? termViews[activeTab] : nil else { return }
        let term = tv.terminal
        let q = query.lowercased()
        var highlights: [(row: Int, col: Int, len: Int)] = []

        // Search scrollback (negative row indices)
        for (si, line) in term.scrollback.enumerated() {
            let lineStr = String(line.map { Character($0.char) })
            searchLine(lineStr, query: q, len: query.count, row: -(term.scrollback.count - si), into: &highlights)
        }

        // Search visible grid
        for r in 0..<term.rows {
            let lineStr = String(term.grid[r].prefix(term.cols).map { Character($0.char) })
            searchLine(lineStr, query: q, len: query.count, row: r, into: &highlights)
        }

        if highlights.isEmpty {
            showSearchToast(query: query, current: 0, total: 0)
            return
        }

        searchHighlights = highlights
        searchQuery = query
        searchCurrentIndex = highlights.count - 1
        tv.needsDisplay = true

        showSearchToast(query: query, current: searchCurrentIndex + 1, total: highlights.count)
        scrollToSearchMatch(tv: tv, term: term)

        // Cancel previous cleanup, schedule new one
        searchCleanupWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.clearSearchState()
            tv.needsDisplay = true
        }
        searchCleanupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func searchLine(_ lineStr: String, query q: String, len: Int, row: Int, into highlights: inout [(row: Int, col: Int, len: Int)]) {
        let lower = lineStr.lowercased()
        var start = lower.startIndex
        while let range = lower.range(of: q, range: start..<lower.endIndex) {
            let col = lower.distance(from: lower.startIndex, to: range.lowerBound)
            highlights.append((row: row, col: col, len: len))
            start = range.upperBound
        }
    }

    func clearSearchState() {
        searchHighlights.removeAll()
        searchCurrentIndex = -1
        searchQuery = ""
        searchCleanupWork?.cancel()
        searchCleanupWork = nil
    }

    func scrollToSearchMatch(tv: TerminalView, term: Terminal) {
        guard searchCurrentIndex >= 0, searchCurrentIndex < searchHighlights.count else { return }
        let hl = searchHighlights[searchCurrentIndex]
        if hl.row < 0 {
            let scrollLines = term.scrollback.count + hl.row
            tv.smoothScrollY = CGFloat(max(0, scrollLines)) * tv.cellH
        } else {
            tv.smoothScrollY = 0
        }
        tv.needsDisplay = true
    }

    // MARK: - Diagnostics Overlays

    func togglePerfOverlay() { toggleDiagnosticsOverlay(mode: .perf) }
    func toggleParserOverlay() { toggleDiagnosticsOverlay(mode: .parser) }

    private func toggleDiagnosticsOverlay(mode: DiagnosticsOverlay.Mode) {
        let existing = mode == .perf ? perfOverlay : parserOverlay
        if let overlay = existing {
            overlay.stopUpdating()
            overlay.removeFromSuperview()
            if mode == .perf { perfOverlay = nil } else { parserOverlay = nil }
            return
        }
        guard !splitContainers.isEmpty,
              let tv = activeTab < termViews.count ? termViews[activeTab] : nil else { return }
        let bounds = window.contentView?.bounds ?? .zero
        let (w, h): (CGFloat, CGFloat) = mode == .perf ? (260, 180) : (280, 280)
        let overlay = DiagnosticsOverlay(frame: NSRect(x: bounds.width - w - 10, y: 40, width: w, height: h), mode: mode)
        overlay.autoresizingMask = [.minXMargin, .maxYMargin]
        overlay.terminalView = tv
        window.contentView?.addSubview(overlay)
        overlay.layer?.zPosition = 9999
        overlay.startUpdating()
        if mode == .perf { perfOverlay = overlay } else { parserOverlay = overlay }
    }

    // MARK: - Toast

    func showSearchToast(query: String, current: Int, total: Int) {
        guard let contentView = window.contentView else { return }
        contentView.subviews.filter { $0.identifier == NSUserInterfaceItemIdentifier("searchToast") }.forEach { $0.removeFromSuperview() }

        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        let toastH: CGFloat = 42
        let padOuter: CGFloat = 14
        let padInner: CGFloat = 11
        let badgePadX: CGFloat = 10
        let badgeH: CGFloat = 25
        let badgeR: CGFloat = 6

        let badgeStr: String
        let queryStr: String
        let badgeColor: NSColor
        if total == 0 {
            badgeStr = "0"
            queryStr = "no matches for \"\(query)\""
            badgeColor = NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0)
        } else {
            badgeStr = "\(current)/\(total)"
            queryStr = "\"\(query)\""
            badgeColor = NSColor(calibratedRed: 0.75, green: 0.52, blue: 0.08, alpha: 1.0)
        }

        // Measure text sizes with the same font for perfect alignment
        let badgeTextSz = (badgeStr as NSString).size(withAttributes: [.font: font])
        let queryTextSz = (queryStr as NSString).size(withAttributes: [.font: font])
        let badgeW = ceil(badgeTextSz.width) + badgePadX * 2
        let totalW = padOuter + badgeW + padInner + ceil(queryTextSz.width) + padOuter

        let toast = NSView(frame: NSRect(
            x: round((contentView.bounds.width - totalW) / 2),
            y: contentView.bounds.height - toastH - 48,
            width: totalW, height: toastH))
        toast.identifier = NSUserInterfaceItemIdentifier("searchToast")
        toast.wantsLayer = true
        toast.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.93).cgColor
        toast.layer?.cornerRadius = toastH / 2
        toast.layer?.borderWidth = 0.5
        toast.layer?.borderColor = NSColor(calibratedWhite: 0.28, alpha: 0.5).cgColor
        toast.layer?.zPosition = 99999

        // Badge — vertically centered in toast
        let badgeY = round((toastH - badgeH) / 2)
        let badge = NSView(frame: NSRect(x: padOuter, y: badgeY, width: badgeW, height: badgeH))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = badgeColor.cgColor
        badge.layer?.cornerRadius = badgeR

        let badgeLbl = NSTextField(labelWithString: badgeStr)
        badgeLbl.font = font
        badgeLbl.textColor = .white
        badgeLbl.alignment = .center
        badgeLbl.isBezeled = false
        badgeLbl.drawsBackground = false
        badgeLbl.isEditable = false
        let badgeLblH = ceil(badgeTextSz.height)
        badgeLbl.frame = NSRect(x: 0, y: round((badgeH - badgeLblH) / 2), width: badgeW, height: badgeLblH)
        badge.addSubview(badgeLbl)
        toast.addSubview(badge)

        // Query label — same font, baseline-aligned with badge text
        let queryLbl = NSTextField(labelWithString: queryStr)
        queryLbl.font = font
        queryLbl.textColor = NSColor(calibratedWhite: 0.62, alpha: 1.0)
        queryLbl.isBezeled = false
        queryLbl.drawsBackground = false
        queryLbl.isEditable = false
        let queryLblH = ceil(queryTextSz.height)
        queryLbl.frame = NSRect(
            x: padOuter + badgeW + padInner,
            y: round((toastH - queryLblH) / 2),
            width: ceil(queryTextSz.width), height: queryLblH)
        toast.addSubview(queryLbl)

        toast.alphaValue = 0
        contentView.addSubview(toast)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toast.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.removeFromSuperview()
            })
        }
    }

    // MARK: - Update Toasts

    func showGenericToast(badge badgeStr: String, text queryStr: String,
                          badgeColor: NSColor, dismissAfter: TimeInterval = 6.0,
                          identifier: String = "updateToast",
                          onClick: (() -> Void)? = nil) {
        guard let contentView = window.contentView else { return }
        contentView.subviews.filter { $0.identifier == NSUserInterfaceItemIdentifier(identifier) }.forEach { $0.removeFromSuperview() }

        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        let toastH: CGFloat = 42
        let padOuter: CGFloat = 14
        let padInner: CGFloat = 11
        let badgePadX: CGFloat = 10
        let badgeH: CGFloat = 25
        let badgeR: CGFloat = 6

        let badgeTextSz = (badgeStr as NSString).size(withAttributes: [.font: font])
        let queryTextSz = (queryStr as NSString).size(withAttributes: [.font: font])
        let badgeW = ceil(badgeTextSz.width) + badgePadX * 2
        let totalW = padOuter + badgeW + padInner + ceil(queryTextSz.width) + padOuter

        let toast: NSView
        if let action = onClick {
            let clickable = ClickableToastView(frame: NSRect(
                x: round((contentView.bounds.width - totalW) / 2),
                y: contentView.bounds.height - toastH - 48,
                width: totalW, height: toastH))
            clickable.onClick = action
            toast = clickable
        } else {
            toast = NSView(frame: NSRect(
                x: round((contentView.bounds.width - totalW) / 2),
                y: contentView.bounds.height - toastH - 48,
                width: totalW, height: toastH))
        }
        toast.identifier = NSUserInterfaceItemIdentifier(identifier)
        toast.wantsLayer = true
        toast.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.93).cgColor
        toast.layer?.cornerRadius = 6
        toast.layer?.borderWidth = 0.5
        toast.layer?.borderColor = NSColor(calibratedWhite: 0.28, alpha: 0.5).cgColor
        toast.layer?.zPosition = 99999

        let badgeY = round((toastH - badgeH) / 2)
        let bv = NSView(frame: NSRect(x: padOuter, y: badgeY, width: badgeW, height: badgeH))
        bv.wantsLayer = true
        bv.layer?.backgroundColor = badgeColor.cgColor
        bv.layer?.cornerRadius = badgeR

        let badgeLbl = NSTextField(labelWithString: badgeStr)
        badgeLbl.font = font
        badgeLbl.textColor = .white
        badgeLbl.alignment = .center
        badgeLbl.isBezeled = false
        badgeLbl.drawsBackground = false
        badgeLbl.isEditable = false
        let badgeLblH = ceil(badgeTextSz.height)
        badgeLbl.frame = NSRect(x: 0, y: round((badgeH - badgeLblH) / 2), width: badgeW, height: badgeLblH)
        bv.addSubview(badgeLbl)
        toast.addSubview(bv)

        let queryLbl = NSTextField(labelWithString: queryStr)
        queryLbl.font = font
        queryLbl.textColor = NSColor(calibratedWhite: 0.62, alpha: 1.0)
        queryLbl.isBezeled = false
        queryLbl.drawsBackground = false
        queryLbl.isEditable = false
        let queryLblH = ceil(queryTextSz.height)
        queryLbl.frame = NSRect(
            x: padOuter + badgeW + padInner,
            y: round((toastH - queryLblH) / 2),
            width: ceil(queryTextSz.width), height: queryLblH)
        toast.addSubview(queryLbl)

        toast.alphaValue = 0
        contentView.addSubview(toast)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toast.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.removeFromSuperview()
            })
        }
    }

    func showUpdateToast(version: String) {
        let v = version.hasPrefix("v") ? version : "v\(version)"
        showGenericToast(badge: "UPDATE", text: String(format: Loc.updateAvailable, v),
                         badgeColor: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.34, alpha: 1.0),
                         dismissAfter: 12.0, onClick: { [weak self] in
                             guard let self = self, let release = self.pendingRelease else { return }
                             self.startUpdateDownload(release: release)
                         })
    }

    func showDownloadProgressToast(percent: Double) {
        guard let contentView = window.contentView else { return }
        let identifier = "downloadProgressToast"

        // Dismiss any existing generic/update toasts first
        for id in ["updateToast", "searchToast"] {
            contentView.subviews.filter { $0.identifier == NSUserInterfaceItemIdentifier(id) }.forEach { $0.removeFromSuperview() }
        }
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        let toastH: CGFloat = 48
        let padOuter: CGFloat = 14
        let padInner: CGFloat = 11
        let badgePadX: CGFloat = 10
        let badgeH: CGFloat = 25
        let badgeR: CGFloat = 6
        let progressH: CGFloat = 4

        let pctStr = "\(Int(percent * 100))%"
        let msgStr = "Downloading update…"

        let badgeTextSz = (pctStr as NSString).size(withAttributes: [.font: font])
        let msgTextSz = (msgStr as NSString).size(withAttributes: [.font: font])
        let badgeW = ceil(badgeTextSz.width) + badgePadX * 2
        let totalW = padOuter + badgeW + padInner + ceil(msgTextSz.width) + padOuter

        // Reuse existing toast or create new
        let existing = contentView.subviews.first { $0.identifier == NSUserInterfaceItemIdentifier(identifier) }
        let toast: NSView
        if let existing = existing {
            toast = existing
            // Update badge text
            if let bv = toast.subviews.first, let lbl = bv.subviews.first as? NSTextField {
                lbl.stringValue = pctStr
            }
            // Update progress bar
            if let bar = toast.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("progressBar") }) {
                bar.frame.size.width = (toast.bounds.width - 2) * CGFloat(percent)
            }
            return
        }

        toast = NSView(frame: NSRect(
            x: round((contentView.bounds.width - totalW) / 2),
            y: contentView.bounds.height - toastH - 48,
            width: totalW, height: toastH))
        toast.identifier = NSUserInterfaceItemIdentifier(identifier)
        toast.wantsLayer = true
        toast.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.93).cgColor
        toast.layer?.cornerRadius = 6
        toast.layer?.borderWidth = 0.5
        toast.layer?.borderColor = NSColor(calibratedWhite: 0.28, alpha: 0.5).cgColor
        toast.layer?.zPosition = 99999

        let badgeY = round(((toastH - progressH) - badgeH) / 2)
        let bv = NSView(frame: NSRect(x: padOuter, y: badgeY, width: badgeW, height: badgeH))
        bv.wantsLayer = true
        bv.layer?.backgroundColor = NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.85, alpha: 1.0).cgColor
        bv.layer?.cornerRadius = badgeR

        let badgeLbl = NSTextField(labelWithString: pctStr)
        badgeLbl.font = font
        badgeLbl.textColor = .white
        badgeLbl.alignment = .center
        badgeLbl.isBezeled = false
        badgeLbl.drawsBackground = false
        badgeLbl.isEditable = false
        let badgeLblH = ceil(badgeTextSz.height)
        badgeLbl.frame = NSRect(x: 0, y: round((badgeH - badgeLblH) / 2), width: badgeW, height: badgeLblH)
        bv.addSubview(badgeLbl)
        toast.addSubview(bv)

        let msgLbl = NSTextField(labelWithString: msgStr)
        msgLbl.font = font
        msgLbl.textColor = NSColor(calibratedWhite: 0.62, alpha: 1.0)
        msgLbl.isBezeled = false
        msgLbl.drawsBackground = false
        msgLbl.isEditable = false
        let msgLblH = ceil(msgTextSz.height)
        msgLbl.frame = NSRect(
            x: padOuter + badgeW + padInner,
            y: round(((toastH - progressH) - msgLblH) / 2),
            width: ceil(msgTextSz.width), height: msgLblH)
        toast.addSubview(msgLbl)

        // Progress bar at bottom
        let progressBg = NSView(frame: NSRect(x: 1, y: 1, width: totalW - 2, height: progressH))
        progressBg.wantsLayer = true
        progressBg.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor
        progressBg.layer?.cornerRadius = progressH / 2
        toast.addSubview(progressBg)

        let progressBar = NSView(frame: NSRect(x: 1, y: 1, width: (totalW - 2) * CGFloat(percent), height: progressH))
        progressBar.identifier = NSUserInterfaceItemIdentifier("progressBar")
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.85, alpha: 1.0).cgColor
        progressBar.layer?.cornerRadius = progressH / 2
        toast.addSubview(progressBar)

        toast.alphaValue = 0
        contentView.addSubview(toast)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toast.animator().alphaValue = 1
        }
    }

    func dismissDownloadProgressToast() {
        guard let contentView = window.contentView else { return }
        if let toast = contentView.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("downloadProgressToast") }) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.removeFromSuperview()
            })
        }
    }

    func scheduleUpdateCheck(initialDelay: TimeInterval) {
        updateCheckTimer?.invalidate()
        guard UserDefaults.standard.bool(forKey: "autoCheckUpdates") else { return }
        // Note: .app guard intentionally removed — checking is harmless for any build type.
        // Install guard remains in downloadAndInstall (write permission check covers non-.app paths).

        let interval: TimeInterval = 72 * 60 * 60  // 72 hours

        // Initial check after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            self?.silentUpdateCheck()
        }

        // Repeating timer for long-running sessions
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.silentUpdateCheck()
        }
    }

    private func silentUpdateCheck() {
        guard UserDefaults.standard.bool(forKey: "autoCheckUpdates") else { return }
        updateChecker.checkForUpdate { [weak self] result in
            if case .success(let release) = result, let release = release {
                self?.pendingRelease = release
                self?.showUpdateToast(version: release.tagName)
            }
        }
    }

    func manualCheckForUpdate() {
        // Dev-build guard
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            showGenericToast(badge: "UPDATE", text: Loc.onlyWithAppBundle,
                             badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0))
            return
        }

        showGenericToast(badge: "UPDATE", text: Loc.checking,
                         badgeColor: NSColor(calibratedWhite: 0.35, alpha: 1.0), dismissAfter: 3.0)

        updateChecker.checkForUpdate { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let release):
                if let release = release {
                    self.pendingRelease = release
                    self.showUpdateToast(version: release.tagName)
                } else {
                    self.showGenericToast(badge: "UPDATE", text: String(format: Loc.alreadyUpToDate, kAppVersion),
                                          badgeColor: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.34, alpha: 1.0))
                }
            case .failure:
                self.showGenericToast(badge: "UPDATE", text: Loc.checkFailed,
                                      badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0))
            }
        }
    }

    func startUpdateDownload(release: GitHubRelease) {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            showGenericToast(badge: "UPDATE", text: Loc.onlyWithAppBundle,
                             badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0))
            return
        }
        showDownloadProgressToast(percent: 0)
        updateChecker.downloadAndInstall(release: release, onProgress: { [weak self] pct in
            self?.showDownloadProgressToast(percent: pct)
        }, onComplete: { [weak self] result in
            guard let self = self else { return }
            self.dismissDownloadProgressToast()
            switch result {
            case .success:
                // SUCCESS toast (matching dummy design)
                self.showGenericToast(badge: "SUCCESS", text: Loc.updateInstalled,
                                      badgeColor: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.34, alpha: 1.0),
                                      dismissAfter: 3.0)
                // Note: installUpdate already handles saveSession + relaunch + exit
            case .failure(let error):
                self.showGenericToast(badge: "ERROR", text: error.localizedDescription,
                                      badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0),
                                      dismissAfter: 8.0)
            }
        })
    }

    func resetWindowSize() {
        let defaultSize = NSSize(width: 860, height: 480)
        var newFrame = window.frame
        newFrame.size = defaultSize
        // Center under tray icon
        if let button = statusItem.button, let btnWindow = button.window {
            let btnRect = button.convert(button.bounds, to: nil)
            let screenRect = btnWindow.convertToScreen(btnRect)
            newFrame.origin.x = screenRect.midX - defaultSize.width / 2
            newFrame.origin.y = screenRect.minY - 4 - defaultSize.height
        } else {
            newFrame.origin.x = window.frame.midX - defaultSize.width / 2
            newFrame.origin.y = window.frame.maxY - defaultSize.height
        }
        clearSnapStates()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in self?.activateAfterSnap() })
        UserDefaults.standard.set(Double(defaultSize.width), forKey: "windowWidth")
        UserDefaults.standard.set(Double(defaultSize.height), forKey: "windowHeight")
        UserDefaults.standard.set(Double(newFrame.origin.x), forKey: "windowX")
        UserDefaults.standard.set(Double(newFrame.origin.y), forKey: "windowY")
    }

    func clearSnapStates() {
        preFullscreenFrame = nil
        preHorizontFrame = nil
        preVerticalFrame = nil
    }

    func activateAfterSnap() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !splitContainers.isEmpty {
            if let ev = activeTab < tabEditorViews.count ? tabEditorViews[activeTab] : nil {
                window.makeFirstResponder(ev.textView)
            } else if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
                window.makeFirstResponder(tv)
                tv.needsDisplay = true
            }
        }
    }

    func snapAnimate(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in self?.activateAfterSnap() })
    }

    func toggleFullscreen() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        if let saved = preFullscreenFrame {
            clearSnapStates()
            snapAnimate(to: saved)
        } else {
            let saved = window.frame
            clearSnapStates()
            preFullscreenFrame = saved
            snapAnimate(to: screen.visibleFrame)
        }
    }

    func toggleHorizont() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        if let saved = preHorizontFrame {
            clearSnapStates()
            snapAnimate(to: saved)
        } else {
            let saved = window.frame
            clearSnapStates()
            preHorizontFrame = saved
            var newFrame = window.frame
            newFrame.origin.x = screen.visibleFrame.origin.x
            newFrame.size.width = screen.visibleFrame.width
            snapAnimate(to: newFrame)
        }
    }

    func snapLeft() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        clearSnapStates()
        snapAnimate(to: NSRect(x: sf.origin.x, y: sf.origin.y + sf.height / 2, width: sf.width / 2, height: sf.height / 2))
    }

    func snapRight() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        clearSnapStates()
        snapAnimate(to: NSRect(x: sf.origin.x + sf.width / 2, y: sf.origin.y + sf.height / 2, width: sf.width / 2, height: sf.height / 2))
    }

    func snapRightFull() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        clearSnapStates()
        snapAnimate(to: NSRect(x: sf.origin.x + sf.width / 2, y: sf.origin.y, width: sf.width / 2, height: sf.height))
    }

    func toggleVertical() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        if let saved = preVerticalFrame {
            clearSnapStates()
            snapAnimate(to: saved)
        } else {
            let saved = window.frame
            clearSnapStates()
            preVerticalFrame = saved
            var newFrame = window.frame
            newFrame.origin.y = screen.visibleFrame.origin.y
            newFrame.size.height = screen.visibleFrame.height
            snapAnimate(to: newFrame)
        }
    }

    func setCursorStyle(_ style: Int) {
        UserDefaults.standard.set(style, forKey: "cursorStyle")
        for tv in termViews { if let tv { tv.userCursorStyle = style; tv.setNeedsDisplay(tv.bounds) } }
        for sc in splitContainers {
            if let sec = sc.secondaryView { sec.userCursorStyle = style; sec.setNeedsDisplay(sec.bounds) }
        }
    }

    func promptToggle(_ name: String, key: String) {
        guard let palette = commandPalette else { return }
        let current = UserDefaults.standard.bool(forKey: key) ? "on" : "off"
        palette.showInput(prompt: "\(name)? (\(current)) [on/off]") { [weak self] val in
            let lower = val.lowercased()
            guard lower == "on" || lower == "off" else { return }
            let v = lower == "on"
            UserDefaults.standard.set(v, forKey: key)
            self?.applySetting(key: key, value: v)
        }
    }


    func promptSlider(_ name: String, key: String, current: String, min: Int, max: Int) {
        guard let palette = commandPalette else { return }
        palette.showInput(prompt: "\(name)? (\(current)) [\(min)-\(max)]") { [weak self] val in
            let num = Int(val.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "pt", with: "")) ?? -1
            guard num >= min && num <= max else { return }
            let cgVal = CGFloat(num) / (key == "terminalFontSize" ? 1.0 : 100.0)
            UserDefaults.standard.set(Double(cgVal), forKey: key)
            self?.applySetting(key: key, value: cgVal)
        }
    }

    func promptChoice(_ name: String, key: String, current: String, options: [String]) {
        guard let palette = commandPalette else { return }
        let list = options.joined(separator: ", ")
        palette.showInput(prompt: "\(name)? (\(current)) [\(list)]") { [weak self] val in
            let lower = val.lowercased()
            guard let idx = options.firstIndex(where: { $0.lowercased() == lower }) else { return }
            UserDefaults.standard.set(idx, forKey: key)
            self?.applySetting(key: key, value: idx)
        }
    }

    func confirmResetSystem() {
        guard let palette = commandPalette else { return }
        palette.showConfirm(prompt: "Sure? (y/n)") { [weak self] in
            self?.applySetting(key: "resetDefaults", value: true)
        }
    }

    func showWindowAnimated() {
        guard !isAnimating else { return }
        isAnimating = true

        // Position + mask BEFORE making window invisible and ordering front.
        // Then re-position AFTER ordering to override any macOS screen-constraint
        // repositioning that can happen during makeKeyAndOrderFront.
        // The window is alpha=0 throughout so neither position is ever visible.
        positionWindowUnderTrayIcon()
        updateWindowMask()
        window.alphaValue = 0
        let targetLevel = UserDefaults.standard.bool(forKey: "alwaysOnTop")
            ? NSWindow.Level.floating : NSWindow.Level.normal
        window.level = targetLevel
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()  // Ensures window appears even when app is not active
        // Re-position after ordering: alpha=0 so windowDidMove guard (alpha>0) skips
        // saving, and we override any macOS screen-constraint repositioning cleanly.
        positionWindowUnderTrayIcon()

        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isAnimating = false
            if self.pendingToggle { self.pendingToggle = false; self.toggleWindow() }
        })

        if !splitContainers.isEmpty && activeTab < splitContainers.count {
            if let ev = activeTab < tabEditorViews.count ? tabEditorViews[activeTab] : nil {
                window.makeFirstResponder(ev.textView)
            } else if let tv = activeTab < termViews.count ? termViews[activeTab] : nil {
                window.makeFirstResponder(tv)
            }
        }

        // Monitor clicks outside to auto-close
        let hideOnClick = UserDefaults.standard.bool(forKey: "hideOnClickOutside")
        if hideOnClick {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, self.window.isVisible else { return }
                if self.isAnyDragSessionActive { return }
                let clickLocation = event.locationInWindow
                if let screen = NSScreen.screens.first(where: { NSMouseInRect(clickLocation, $0.frame, false) }) {
                    if clickLocation.y >= screen.visibleFrame.maxY { return }
                }
                self.hideWindowAnimated()
            }
        }
    }

    func hideWindowAnimated() {
        guard !isAnimating, window != nil, window.isVisible else { return }
        // Dismiss command palette instantly
        if let p = commandPalette, p.superview != nil { p.nameLabel.removeFromSuperview(); p.dismiss() }
        isAnimating = true
        lastHideTime = ProcessInfo.processInfo.systemUptime

        // Remove outside-click monitor
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }

        // Suppress terminal resize during animation to preserve grid content
        for tv in termViews { tv?.suppressResize = true }
        for sc in splitContainers { sc.secondaryView?.suppressResize = true }

        if isWindowDetached {
            // Detached window: plain fade-out — no frame change to avoid any position drift
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                for tv in self.termViews { tv?.suppressResize = false }
                for sc in self.splitContainers { sc.secondaryView?.suppressResize = false }
                self.window.orderOut(nil)
                self.isAnimating = false
                if self.pendingToggle { self.pendingToggle = false; self.toggleWindow() }
            })
            return
        }

        // Docked window: simple fade-out, no frame collapse
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            for tv in self.termViews { tv?.suppressResize = false }
            for sc in self.splitContainers { sc.secondaryView?.suppressResize = false }
            self.window.orderOut(nil)
            self.isAnimating = false
            if self.pendingToggle { self.pendingToggle = false; self.toggleWindow() }
        })
    }

    @objc func menuSwitchZsh()  {
        guard !splitContainers.isEmpty,
              let tv = activeTab < termViews.count ? termViews[activeTab] : nil else { return }
        tv.switchToShell1(nil)
        updateHeaderTabs(); updateFooter()
    }
    @objc func menuSwitchBash() {
        guard !splitContainers.isEmpty,
              let tv = activeTab < termViews.count ? termViews[activeTab] : nil else { return }
        tv.switchToShell2(nil)
        updateHeaderTabs(); updateFooter()
    }
    @objc func menuSwitchSh()   {
        guard !splitContainers.isEmpty,
              let tv = activeTab < termViews.count ? termViews[activeTab] : nil else { return }
        tv.switchToShell3(nil)
        updateHeaderTabs(); updateFooter()
    }

    @objc func switchToTab1() { if splitContainers.count > 0 { switchToTab(0) } }
    @objc func switchToTab2() { if splitContainers.count > 1 { switchToTab(1) } }
    @objc func switchToTab3() { if splitContainers.count > 2 { switchToTab(2) } }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Enforce minimum: at least enough for header buttons + 1 tab + usable terminal
        let minW = sender.minSize.width
        let minH = sender.minSize.height
        return NSSize(width: max(frameSize.width, minW), height: max(frameSize.height, minH))
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Redraw terminal to show cursor
        if activeTab < termViews.count { termViews[activeTab]?.needsDisplay = true }
        guard !isAnimating else { return }
        guard UserDefaults.standard.bool(forKey: "autoDim") else { return }
        restoreWindowOpacity()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Redraw terminal to hide cursor when window loses focus
        if activeTab < termViews.count { termViews[activeTab]?.needsDisplay = true }
        guard !isAnimating, window.isVisible else { return }
        guard UserDefaults.standard.bool(forKey: "autoDim") else { return }
        if isAnyDragSessionActive { return }
        let pinnedOrigin = window.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = effectiveOpacity * 0.55
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if self.window.frame.origin != pinnedOrigin {
                self.window.setFrameOrigin(pinnedOrigin)
            }
        })
    }

    func windowDidResize(_ notification: Notification) {
        updateWindowMask()
        centerCommandPalette()
        layoutGitPanel()
        guard !isAnimating, window.isVisible, window.alphaValue > 0 else { return }
        let frame = window.frame
        UserDefaults.standard.set(Double(frame.size.width), forKey: "windowWidth")
        UserDefaults.standard.set(Double(frame.size.height), forKey: "windowHeight")
        UserDefaults.standard.set(Double(frame.origin.x), forKey: "windowX")
        if isWindowDetached {
            // Detached: also save Y so position is fully restored on next launch.
            UserDefaults.standard.set(Double(frame.origin.y), forKey: "windowY")
        }
        // When docked, do NOT save Y — it is always derived from the tray icon.
        if !isWindowDetached { settingsOverlay?.updateResetButtonState() }
    }

    func centerCommandPalette() {
        guard let palette = commandPalette, palette.superview != nil else { return }
        let bounds = window.contentView?.bounds ?? .zero
        var f = palette.frame
        f.origin.x = (bounds.width - f.width) / 2
        f.origin.y = (bounds.height - f.height) / 2
        palette.frame = f
        palette.repositionNameLabel()
        palette.repositionBadges()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAnimating, window.isVisible, window.alphaValue > 0 else { return }
        windowMoveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let origin = self.window.frame.origin
            UserDefaults.standard.set(Double(origin.x), forKey: "windowX")
            if self.isWindowDetached {
                UserDefaults.standard.set(Double(origin.y), forKey: "windowY")
            }
            if !self.isWindowDetached { self.settingsOverlay?.updateResetButtonState() }
        }
        windowMoveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func updateWindowMask() {
        guard let cv = window?.contentView, let layer = cv.layer else { return }
        let b = cv.bounds
        let r: CGFloat = 12
        let effectiveArrowH: CGFloat = isWindowDetached ? 0 : arrowH
        let bodyH = b.height - effectiveArrowH

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0),
                     tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.addLine(to: CGPoint(x: b.width - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: b.width, y: 0),
                     tangent2End: CGPoint(x: b.width, y: r), radius: r)
        path.addLine(to: CGPoint(x: b.width, y: bodyH - r))
        path.addArc(tangent1End: CGPoint(x: b.width, y: bodyH),
                     tangent2End: CGPoint(x: b.width - r, y: bodyH), radius: r)

        if isWindowDetached {
            // Pure rounded rect — no arrow
            path.addLine(to: CGPoint(x: r, y: bodyH))
            path.addArc(tangent1End: CGPoint(x: 0, y: bodyH),
                         tangent2End: CGPoint(x: 0, y: bodyH - r), radius: r)
        } else {
            // Arrow anchored at tray icon screen position
            var ax = b.midX
            if let button = statusItem?.button, let btnWindow = button.window {
                let btnRect = button.convert(button.bounds, to: nil)
                let screenX = btnWindow.convertToScreen(btnRect).midX
                // Sanity-check: if the button hasn't been placed by macOS yet,
                // convertToScreen returns a bogus screenX near 0. A real menu-bar
                // button is always > 100pt from the left edge of any screen.
                if screenX > 100 {
                    ax = screenX - window.frame.origin.x
                    let pad = r + arrowW / 2 + 2
                    ax = max(pad, min(b.width - pad, ax))
                }
            }
            path.addLine(to: CGPoint(x: ax + arrowW / 2, y: bodyH))
            path.addLine(to: CGPoint(x: ax, y: b.height))
            path.addLine(to: CGPoint(x: ax - arrowW / 2, y: bodyH))
            path.addLine(to: CGPoint(x: r, y: bodyH))
            path.addArc(tangent1End: CGPoint(x: 0, y: bodyH),
                         tangent2End: CGPoint(x: 0, y: bodyH - r), radius: r)
        }
        path.closeSubpath()

        // Reuse mask layer — only update path
        if let existingMask = layer.mask as? CAShapeLayer {
            existingMask.path = path
        } else {
            let mask = CAShapeLayer()
            mask.path = path
            layer.mask = mask
        }

        // Reuse cached border layer
        if windowBorderLayer == nil {
            let border = CAShapeLayer()
            border.fillColor = nil
            border.strokeColor = Self.borderNormalColor
            border.lineWidth = 3
            layer.addSublayer(border)
            windowBorderLayer = border
        }
        if let border = windowBorderLayer {
            border.path = path
            border.frame = b
            border.zPosition = 9999
        }

        // Invalidate shadow so macOS recomputes it from the new mask shape.
        // Without this, the shadow lags behind the mask on first display after
        // a shape change and snaps when the mouse enters — visually looks like
        // the window shifted position.
        window?.invalidateShadow()
    }

    // Cached border layer + pre-allocated colors
    private var windowBorderLayer: CAShapeLayer?
    private var arrowTintView: NSView?
    private var isBorderHovered = false
    private static let borderNormalColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
    private static let borderHoverColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor

    func handleBorderHover(nearEdge: Bool) {
        guard let border = windowBorderLayer else { return }

        if nearEdge && !isBorderHovered {
            isBorderHovered = true
            border.strokeColor = Self.borderHoverColor
            let anim = CABasicAnimation(keyPath: "strokeColor")
            anim.fromValue = Self.borderNormalColor
            anim.toValue = Self.borderHoverColor
            anim.duration = 0.2
            border.add(anim, forKey: "borderGlow")
        } else if !nearEdge && isBorderHovered {
            isBorderHovered = false
            border.strokeColor = Self.borderNormalColor
            let anim = CABasicAnimation(keyPath: "strokeColor")
            anim.fromValue = Self.borderHoverColor
            anim.toValue = Self.borderNormalColor
            anim.duration = 0.3
            border.add(anim, forKey: "borderGlow")
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Always dismiss palette when app loses focus
        if let p = commandPalette, p.superview != nil { p.dismiss() }
        if isAnyDragSessionActive { return }
        let hideOnDeactivate = UserDefaults.standard.bool(forKey: "hideOnDeactivate")
        if hideOnDeactivate && window.isVisible {
            // Don't hide if the user clicked on the menu bar (other tray icons, menus, etc.)
            let mouseLocation = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
                if mouseLocation.y >= screen.visibleFrame.maxY {
                    return
                }
            }
            hideWindowAnimated()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // During termination, don't animate — just clean up
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        footerTimer?.invalidate()
        windowMoveWorkItem?.cancel()
        perfOverlay?.stopUpdating()
        parserOverlay?.stopUpdating()
        termViews.removeAll()
    }

    // MARK: - Session Persistence

    func saveSession() {
        var tabs: [[String: Any]] = []
        for (i, tv) in termViews.enumerated() {
            // Editor tab
            if i < tabTypes.count && tabTypes[i] == .editor {
                var t: [String: Any] = ["type": "editor"]
                if let url = i < tabEditorURLs.count ? tabEditorURLs[i] : nil {
                    t["editorURL"] = url.path
                }
                tabs.append(t)
                continue
            }
            // Skip nil terminal slots
            guard let tv = tv else { continue }
            var info: [String: Any] = [
                "shell": tv.currentShell,
                "cwd": cwdForPid(tv.childPid),
                "tabId": tv.tabId,
            ]
            if i < tabColors.count {
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                tabColors[i].getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                info["colorHue"] = Double(h)
            }
            if i < tabCustomNames.count, let customName = tabCustomNames[i] {
                info["customName"] = customName
            }
            // Save split state
            if i < splitContainers.count {
                let sc = splitContainers[i]
                if sc.isSplit, let sec = sc.secondaryView {
                    info["splitVertical"] = sc.isVerticalSplit
                    info["splitRatio"] = Double(sc.splitRatio)
                    info["splitShell"] = sec.currentShell
                    info["splitCwd"] = cwdForPid(sec.childPid)
                    info["splitTabId"] = sec.tabId
                }
            }
            // Save git panel state
            if i < tabGitPositions.count {
                let pos: String
                switch tabGitPositions[i] {
                case .none:   pos = "none"
                case .right:  pos = "right"
                case .bottom: pos = "bottom"
                }
                info["gitPosition"] = pos
                if i < tabGitRatios.count {
                    info["gitRatio"] = Double(tabGitRatios[i])
                }
                if i < tabGitRatiosV.count {
                    info["gitRatioV"] = Double(tabGitRatiosV[i])
                }
                if i < tabGitRatiosH.count {
                    info["gitRatioH"] = Double(tabGitRatiosH[i])
                }
            }
            tabs.append(info)
        }
        UserDefaults.standard.set(tabs, forKey: "sessionTabs")
        UserDefaults.standard.set(activeTab, forKey: "sessionActiveTab")

        // Save window geometry
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "windowFrame")

        // Save sidebar state
        UserDefaults.standard.set(webPickerSidebarView != nil, forKey: "webPickerOpen")
        UserDefaults.standard.set(sshManagerView != nil, forKey: "sshManagerOpen")
        UserDefaults.standard.set(sidebarOrder, forKey: "sidebarOrder")
        let sidebarHeights = sidebarPanelHeights.mapValues { Double($0) }
        UserDefaults.standard.set(sidebarHeights, forKey: "sidebarPanelHeights")

    }

    func restoreSession() -> Bool {
        guard let tabs = UserDefaults.standard.array(forKey: "sessionTabs") as? [[String: Any]],
              !tabs.isEmpty else { return false }
        let savedActive = UserDefaults.standard.integer(forKey: "sessionActiveTab")

        for tabInfo in tabs {
            // Restore editor tab
            if let type_ = tabInfo["type"] as? String, type_ == "editor" {
                let url = (tabInfo["editorURL"] as? String).map { URL(fileURLWithPath: $0) }
                createEditorTab(url: url)
                continue
            }
            let shell = tabInfo["shell"] as? String ?? "/bin/zsh"
            let cwd = tabInfo["cwd"] as? String
            let hue = tabInfo["colorHue"] as? Double
            let savedTabId = tabInfo["tabId"] as? String
            createTab(shell: shell, cwd: cwd, colorHue: hue.map { CGFloat($0) }, tabId: savedTabId)

            // Restore custom tab name
            if let customName = tabInfo["customName"] as? String {
                let idx = tabCustomNames.count - 1
                if idx >= 0 { tabCustomNames[idx] = customName }
            }

            // Restore git panel if saved
            if let gitPos = tabInfo["gitPosition"] as? String, gitPos != "none" {
                let idx = splitContainers.count - 1
                if idx >= 0, idx < tabGitPositions.count {
                    let pos: GitPanelPosition = gitPos == "bottom" ? .bottom : .right
                    tabGitPositions[idx] = pos
                    if let savedRatio = tabInfo["gitRatio"] as? Double {
                        tabGitRatios[idx] = CGFloat(savedRatio)
                    }
                    if let rv = tabInfo["gitRatioV"] as? Double {
                        tabGitRatiosV[idx] = CGFloat(rv)
                    }
                    if let rh = tabInfo["gitRatioH"] as? Double {
                        tabGitRatiosH[idx] = CGFloat(rh)
                    }
                    let panel = GitPanelView(frame: .zero)
                    panel.wantsLayer = true
                    let container = splitContainers[idx]
                    container.superview?.addSubview(panel)
                    tabGitPanels[idx] = panel

                    let divider = GitPanelDividerView()
                    divider.isVertical = (pos == .right)
                    divider.onDrag = { [weak self] delta in self?.handleGitDividerDrag(delta) }
                    container.superview?.addSubview(divider)
                    tabGitDividers[idx] = divider

                    let restoreCwd = tabInfo["cwd"] as? String ?? ""
                    panel.startRefreshing(cwd: restoreCwd)
                }
            }

            // Restore split if saved
            if let splitVertical = tabInfo["splitVertical"] as? Bool {
                let idx = splitContainers.count - 1
                let container = splitContainers[idx]
                let splitShell = tabInfo["splitShell"] as? String ?? shell
                let splitCwd = tabInfo["splitCwd"] as? String ?? cwd
                let splitTabId = tabInfo["splitTabId"] as? String
                let secFrame = container.bounds
                let sec = TerminalView(frameRect: secFrame, shell: splitShell, cwd: splitCwd, historyId: splitTabId)
                sec.onShellExit = makeSecondaryExitHandler(container: container, sec: sec)
                container.split(vertical: splitVertical, secondary: sec)
                // Restore session ratio after split() (which defaults to UserDefaults)
                if let ratio = tabInfo["splitRatio"] as? Double, ratio > 0.1, ratio < 0.9 {
                    container.splitRatio = CGFloat(ratio)
                    container.layoutSplit()
                }
                // Primary is active on restore
                container.setActivePane(primary: true)
            }
        }

        // Restore active tab
        let targetTab = min(savedActive, splitContainers.count - 1)
        if targetTab != activeTab && targetTab >= 0 {
            switchToTab(targetTab)
        }

        // Layout git panels after all tabs restored
        layoutGitPanel()
        if activeTab < tabGitPositions.count, tabGitPositions[activeTab] != .none {
            headerView.setGitActive(true)
        }

        // Restore window frame
        if let frameStr = UserDefaults.standard.string(forKey: "windowFrame") {
            let f = NSRectFromString(frameStr)
            if f.width >= 320, f.height >= 220,
               NSScreen.screens.contains(where: { $0.frame.intersects(f) }) {
                window.setFrame(f, display: false)
            }
        }

        // Restore sidebar panel order and heights
        if let order = UserDefaults.standard.array(forKey: "sidebarOrder") as? [String] {
            sidebarOrder = order
        }
        if let heights = UserDefaults.standard.dictionary(forKey: "sidebarPanelHeights") as? [String: Double] {
            for (k, v) in heights { sidebarPanelHeights[k] = CGFloat(v) }
        }

        // Restore open sidebar panels
        if UserDefaults.standard.bool(forKey: "webPickerOpen") { showWebPickerSidebar() }
        if UserDefaults.standard.bool(forKey: "sshManagerOpen") { showSSHManager() }

        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Main

// Single instance guard — use file lock to prevent multiple instances
let lockPath = NSTemporaryDirectory() + "quickTerminal.lock"
let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o600)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    // Another instance holds the lock — exit immediately
    if lockFD >= 0 { close(lockFD) }
    exit(0)
}
// Lock acquired — keep lockFD open for lifetime of process (auto-released on exit)

// MARK: - Crash Reporting

private func setupCrashReporting() {
    let logDir = NSHomeDirectory() + "/.quickterminal"
    mkdir(logDir, 0o755)

    NSSetUncaughtExceptionHandler { exception in
        let info = """
        === quickTerminal Crash Report ===
        Date: \(Date())
        Exception: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "unknown")
        Stack Trace:
        \(exception.callStackSymbols.joined(separator: "\n"))
        ===================================
        """
        let logDir = NSHomeDirectory() + "/.quickterminal"
        let logPath = logDir + "/crash.log"
        try? info.write(toFile: logPath, atomically: true, encoding: .utf8)
    }

    // POSIX signal handlers for fatal signals (async-signal-safe only)
    for sig: Int32 in [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP] {
        signal(sig) { sigNum in
            // Only use async-signal-safe functions: open, write, close, signal, raise
            let dir = NSHomeDirectory() + "/.quickterminal"
            let path = dir + "/crash.log"
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                var msg = "quickTerminal crashed with signal \(sigNum)\n"
                msg.withUTF8 { buf in _ = Darwin.write(fd, buf.baseAddress, buf.count) }
                close(fd)
            }
            signal(sigNum, SIG_DFL)
            raise(sigNum)
        }
    }
}

setupCrashReporting()

// Handle SIGTERM gracefully — session is auto-saved every 2s
signal(SIGTERM) { _ in
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no dock icon, tray only

// Menu bar
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "About quickTerminal", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(NSMenuItem(title: "Quit quickTerminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appMenuItem.submenu = appMenu

let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
editMenuItem.submenu = editMenu

let tabMenuItem = NSMenuItem()
mainMenu.addItem(tabMenuItem)
let tabMenu = NSMenu(title: "Tab")
tabMenu.addItem(NSMenuItem(title: "New Tab", action: #selector(AppDelegate.addTab), keyEquivalent: "t"))
tabMenu.addItem(NSMenuItem(title: "Close Tab", action: #selector(AppDelegate.closeCurrentTab), keyEquivalent: "w"))
tabMenu.addItem(NSMenuItem.separator())
tabMenu.addItem(NSMenuItem(title: "Tab 1", action: #selector(AppDelegate.switchToTab1), keyEquivalent: ""))
tabMenu.addItem(NSMenuItem(title: "Tab 2", action: #selector(AppDelegate.switchToTab2), keyEquivalent: ""))
tabMenu.addItem(NSMenuItem(title: "Tab 3", action: #selector(AppDelegate.switchToTab3), keyEquivalent: ""))
tabMenu.addItem(NSMenuItem.separator())
tabMenu.addItem(NSMenuItem(title: "Clear", action: #selector(TerminalView.clearScrollback(_:)), keyEquivalent: "k"))
tabMenuItem.submenu = tabMenu

app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate

if #available(macOS 14.0, *) {
    NSApp.activate()
} else {
    app.activate(ignoringOtherApps: true)
}

app.run()
