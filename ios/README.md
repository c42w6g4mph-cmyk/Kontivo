# Kontivo für iPhone und iPad (SwiftUI)

Native Version der Web-App Kontivo, 1:1 nachgebaut. Stand: 03.10.2026.

## Stand
- **Kern (KontivoCore):** Datenmodell, Rechenkern, Datenqualität, Kündigungsschreiben, Katalog, Import/Export, Fachaktionen. 46 automatische Tests, darunter der Abgleich mit der Web-App (`tests/golden.json`: 4 Stichtage × 25 Verträge × 17 Werte, 100 % gleich).
- **App:** alle Bereiche der Web-App (Verträge, Kosten, Budget, Fristen, Mehr, Verwalten, Kündigung mit Brief/PDF/Unterschrift, Einführung, Backup/CSV).
- **Geprüft:** Jede Änderung wird auf einem Mac von GitHub gebaut (Xcode 26.2), getestet und im Simulator fotografiert (iPhone 17 Pro hell/dunkel, iPad Pro 13″). Auf einem echten Gerät lief die App noch nicht.

## Mit dem Mac loslegen
1. **Xcode** aus dem Mac App Store installieren und einmal öffnen.
2. **Terminal** öffnen und einmalig XcodeGen installieren (erzeugt das Xcode-Projekt aus `project.yml`):
   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install xcodegen
   ```
3. Projekt holen und erzeugen:
   ```
   git clone -b swift https://github.com/c42w6g4mph-cmyk/Kontivo.git
   cd Kontivo/ios
   xcodegen
   open Kontivo.xcodeproj
   ```
4. In Xcode oben als Ziel einen Simulator (z.B. iPhone 17 Pro) wählen und ▶︎ drücken.

Nach jedem `git pull` mit neuen Dateien einmal `xcodegen` laufen lassen.

## Auf dem eigenen iPhone testen
1. Xcode → Settings → Accounts → mit der Apple-ID anmelden.
2. Im Projekt: Target «Kontivo» → Signing & Capabilities → Team = deine Apple-ID (Personal Team). Falls die Bundle-ID schon vergeben ist: `ch.kontivo.app` z.B. in `ch.kontivo.sinan` ändern.
3. iPhone per Kabel verbinden, auf dem iPhone «Entwicklermodus» einschalten (Einstellungen → Datenschutz & Sicherheit), dem Mac vertrauen.
4. In Xcode das iPhone als Ziel wählen und ▶︎ drücken. Beim ersten Start auf dem iPhone unter Einstellungen → Allgemein → VPN & Geräteverwaltung dem Entwickler vertrauen.

Mit dem kostenlosen Personal Team läuft die App 7 Tage, danach einfach wieder aus Xcode starten. Für TestFlight und den App Store braucht es das Apple Developer Program (kostenpflichtig, jährlich).

## Daten aus der Web-App übernehmen
Web-App: Mehr → Daten → «Backup erstellen» → Datei in iCloud Drive sichern.
iPhone-App: Mehr → Daten → «Backup laden» → Datei wählen. Verträge, Einnahmen, Personen, Absender, Unterschriften, Kategorien, Logos und Dokumente werden übernommen.

## Aufbau
- `ARCHITEKTUR.md` – verbindliche Architektur, Datenmodell, Web → iOS
- `APP-BAUSTEINE.md` – Grundgerüst und gemeinsame Bausteine
- `docs/inventar/` – Verhalten der Web-App je Bereich (alle Texte wörtlich), Grundlage des Nachbaus
- `KontivoCore/` – Swift Package ohne Oberfläche (`swift test` läuft auch ohne Simulator)
- `Kontivo/` – App (SwiftUI), je Bereich ein Ordner
- `project.yml` – Projektbeschreibung für XcodeGen

## Bewusst anders als die Web-App (native Möglichkeiten)
- Kündigungsbrief: eigene Knöpfe «Per Mail senden» (PDF als Anhang), «Drucken», «Teilen» statt nur Teilen-Menü
- Kalender: Kalender-Symbol auf den Fristen-Karten öffnet direkt «Termin hinzufügen» (Erinnerung 7 Tage und 1 Tag vorher)
- Unterschrift mit PencilKit (Apple Pencil auf dem iPad)
- Wischen und langes Drücken auf Vertragskarten (Pausieren, Duplizieren, Kündigen)
- Datenmodell mit IDs statt Namen (Umbenennen von Personen, Kategorien und Vertragspartnern ist sicher), mehrere Pausen pro Vertrag, Schalter «Mietvertrag»
- Datum und Zahlen immer im Schweizer Format (wie Web)

## Vor einer Veröffentlichung noch offen
- Auf iPhone und iPad testen (Gesten, Kalender, Mail, Drucken, Kamera/Dateien, Backup-Import einer echten Web-Sicherung)
- App-Icon in 1024 px aus der Originalgrafik (derzeit aus 512 px hochgerechnet)
- Datenschutzerklärung für den App Store, Hinweis, dass Backups Unterschriften enthalten
- Danach (nur nativ möglich): Erinnerungen als Mitteilung vor Fristende, iCloud-Sync, Face ID, Widgets, Dokument-Scan
