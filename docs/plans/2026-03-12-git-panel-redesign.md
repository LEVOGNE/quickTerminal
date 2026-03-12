# Git Panel Redesign — Design Doc
Date: 2026-03-12

## Ziel
Das Git Panel komplett neu aufbauen: radikal vereinfacht, kein Fachjargon, für absolute Einsteiger benutzbar. Plus neue Features: Git-Init, GitHub-Repo erstellen, Auto-Auth via gh CLI.

## Was fliegt raus
- Commit-Graph
- Stash-Liste und Stash-Aktionen
- CI/CD-Workflows
- Git-Statistiken (Activity)
- Branch-Verwaltung (Liste, Switch, Delete, New Branch)
- Alle technischen Begriffe als Labels

## Neue Begriffe (Mapping)
| Alt (technisch) | Neu (einfach) |
|---|---|
| Commit | Speichern |
| Push | Hochladen |
| Pull | Aktualisieren |
| Stage All | (intern, kein Label) |
| Branch | (nur als Info-Badge) |
| Repository | Projekt |
| Remote | GitHub-Verbindung |

## 5 Panel-Zustände

### State 1: Kein Git-Repo
- Zeigt Ordnername
- Text: "Noch kein Projekt-Tracking"
- Button: "🚀 Mit Tracking starten" → `git init` → wechselt zu State 2

### State 2: Repo vorhanden, kein GitHub
- Header: Projektname + [branch] Badge
- Sektion "Geänderte Dateien" (wenn vorhanden)
- Commit-Bereich: Textfeld "Was hast du geändert?" + Button "💾 Alles speichern" (= git add -A + git commit)
- GitHub-Sektion: "Noch nicht mit GitHub verbunden" + Button "Mit GitHub verbinden"

### State 3: Repo + GitHub, alles sauber
- Header: Projektname + [branch] Badge
- Status: "✅ Alles gespeichert & hochgeladen"
- GitHub-Sektion: "@username — projektname  ✓ Alles auf dem Stand"

### State 4: Änderungen vorhanden + GitHub verbunden
- Header: Projektname + [branch] Badge
- Dateiliste mit Klick-Diff
- Commit-Bereich: Textfeld + [💾 Speichern] + [↑ Senden] Buttons
- GitHub-Sektion: Sync-Status + [Auf GitHub hochladen] wenn unpushed

### State 5: Push ohne Remote → Neuer Repo-Dialog
- Overlay/Inline-Dialog im Panel
- Felder: Name (vorausgefüllt mit Ordnername), Public/Private Toggle
- Button: "✔ Erstellen & Hochladen" → GitHub API: create repo + git remote add + git push -u
- Button: "Abbrechen"

## GitHub Auth
- Auto-detect via `gh auth token` (gh CLI, bereits implementiert)
- Fallback: Token-Eingabefeld + Link zu github.com/settings/tokens
- Nach erfolgreicher Auth: fetchUser() für @username

## GitHub Repo erstellen (API)
```
POST https://api.github.com/user/repos
{
  "name": "<ordnername>",
  "private": true/false,
  "auto_init": false
}
```
Danach: `git remote add origin https://github.com/<username>/<name>.git`
Dann: `git push -u origin <branch>`

## Datei-Diff
- Klick auf Datei → Diff aufklappen (wie bisher, aber vereinfacht)
- Labels: "Hinzugefügt" (grün), "Gelöscht" (rot), statt +/-

## Feedback
- Kurze Success/Error-Messages direkt unter Aktions-Buttons (4s auto-hide)
- Grün = Erfolg, Rot = Fehler, mit deutschem Text

## Technische Umsetzung
- Bestehende `GitPanelView` Klasse komplett neu aufbauen (alle setupLabels, refresh etc.)
- `GitHubClient` behalten + `createRepo()` Funktion ergänzen
- `runGit()` / `runGitAction()` Helper behalten
- Neue Methode: `gitInit()`
- Neue Methode: `createGitHubRepo(name:private:completion:)`
- `refreshTimer` (3s) bleibt
- Layout: Nur vertikaler Modus (kein horizontaler Bottom-Panel) — radikal vereinfacht
