# Kontivo für iPhone und iPad (SwiftUI)

Native Version der Web-App Kontivo, 1:1 nachgebaut. Stand: 10.10.2026 (Web v142); Kern (KontivoCore) 11.10.2026 auf Web v160 – Oberfläche folgt. iCloud-Sync eingebaut (11.10.2026), im Build ausgeschaltet bis zum Apple Developer Program.

## Stand
- **Kern (KontivoCore):** Datenmodell, Rechenkern, Datenqualität, Kündigungsschreiben, Katalog, Import/Export, Fachaktionen. 46 automatische Tests, darunter der Abgleich mit der Web-App (`tests/golden.json`: 4 Stichtage × 25 Verträge × 17 Werte, 100 % gleich).
- **App:** alle Bereiche der Web-App (Verträge, Kosten, Budget, Fristen, Mehr, Verwalten mit Vollständigkeit, Kündigung mit Brief/PDF/Unterschrift, Einführung mit Intro, Kontoauszug-Import, Backup/CSV).
- **Kontoauszug:** Erkennung 1:1 wie Web, geprüft gegen Erwartungswerte aus der Web-App (84 Bankdateien, 37 Grenzfälle, 3 Kombinationen).
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

## iCloud-Sync
Die Daten liegen zusätzlich in deiner privaten iCloud und sind auf iPhone und iPad mit derselben Apple-ID gleich – wie bei anderen Apps (Notizen, Erinnerungen). Bedienung: Mehr → Daten → Schalter «iCloud-Sync» (Standard an, sobald ein iCloud-Konto angemeldet ist).

- **Abgeglichen:** Verträge, Einnahmen, Personen (inkl. Absender, Unterschrift, Bild), Kategorien samt Reihenfolge, Vertragspartner, Logos/Dokumente/Bilder, Hauptwährung, Sortierung, ignorierte Hinweise, «Ohne Logo», gelernte Kontoauszug-Korrekturen, Quartals-Check.
- **Pro Gerät:** Darstellung (hell/dunkel), Wechselkurse (lädt jedes Gerät selbst), Erinnerungen, App-Sperre, Einführung.
- **Sicher:** private CloudKit-Datenbank des Nutzers (Zone «Kontivo»). Die Vertragsdaten liegen Ende-zu-Ende verschlüsselt in den Datensätzen (`encryptedValues`), Logos/Dokumente als iCloud-Anhang (verschlüsselt gespeichert, Ende-zu-Ende mit Apples «Erweitertem Datenschutz»). Kein Server von Kontivo, kein Teilen mit anderen.
- **Erstes Einschalten:** iCloud leer → alles wird hochgeladen. Neues Gerät ohne eigene Daten → übernimmt die iCloud-Daten (Einführung schliesst sich, Meldung «Deine Daten aus iCloud sind da»). Beide Geräte mit Daten → zusammengeführt; Standardkategorien, «Ich» und gleichnamige Personen, Kategorien und Vertragspartner werden zu einem Eintrag.
- **Gleichzeitig geändert:** Pro Eintrag gewinnt die neuere Änderung, Einstellungen Feld für Feld. Eine noch nicht gesendete Änderung gewinnt gegen eine Löschung auf einem anderen Gerät (kein Datenverlust).
- **Wann:** Abruf beim Öffnen und bei jedem Wechsel in die App, Senden kurz nach jeder Änderung, mit Push sofort. Offline wird gesammelt und später gesendet.
- **Ausschalten:** Daten bleiben auf dem Gerät. Wahlweise «Ausschalten und aus iCloud löschen» (eigene Rückfrage); andere Geräte schalten den Abgleich dann aus und behalten ihre Daten.
- **Konto:** Abgemeldet → Abgleich ruht, Daten bleiben. Anderes iCloud-Konto → angehalten, erst nach Rückfrage «Mit diesem iCloud-Konto abgleichen …» zusammengeführt.
- «Alle Daten löschen» und «Backup laden» wirken bei eingeschaltetem Sync auch in iCloud und auf den anderen Geräten (steht in der Rückfrage).

### iCloud-Sync einschalten (braucht das Apple Developer Program)
Mit dem kostenlosen Personal Team lassen sich iCloud und Push nicht signieren. Deshalb ist der Sync im Build ausgeschaltet; der Code wird trotzdem immer gebaut und getestet. Im Debug-Build steht unter Mehr → Daten die graue Zeile «iCloud-Sync: in diesem Build aus (Apple Developer Program nötig)».
1. Apple Developer Program abschliessen (developer.apple.com/programs). In Xcode → Settings → Accounts die Apple-ID auswählen und «Download Manual Profiles» bzw. neu anmelden – das Team heisst danach nicht mehr «(Personal Team)».
2. In `ios/project.yml` die Zeile `KONTIVO_ICLOUD: "NO"` in `KONTIVO_ICLOUD: "YES"` ändern. Das schaltet Berechtigungen (`Kontivo/Kontivo.entitlements`: iCloud mit CloudKit, Push) und den Sync in der App gemeinsam ein.
3. Im Terminal `cd Kontivo/ios`, dann `xcodegen` und `open Kontivo.xcodeproj`.
4. Target «Kontivo» → Signing & Capabilities → Team = dein bezahltes Team. Unter «iCloud» muss CloudKit mit dem Container `iCloud.ch.kontivo.app` angehakt sein; ist er rot, auf ↻ bzw. «+» tippen, damit Xcode ihn anlegt. Container-Namen sind weltweit eindeutig: Ist er vergeben, die Bundle-ID ändern – der Container heisst automatisch `iCloud.<Bundle-ID>`.
5. Auf iPhone und iPad installieren (beide mit derselben Apple-ID und eingeschaltetem iCloud). Mehr → Daten zeigt «Auf allen deinen Geräten aktuell · zuletzt …».
6. **Vor TestFlight/App Store:** Im CloudKit Dashboard (icloud.developer.apple.com) den Container wählen → «Schema» → «Deploy Schema Changes…» nach **Production** übernehmen. Die Datensatztypen (Settings, Person, Category, Partner, Contract, Income, File) entstehen beim ersten Abgleich aus einem Debug-Build in «Development»; ohne Übernahme funktioniert der Sync in TestFlight und im App Store nicht. Beim Export setzt Xcode Push und iCloud automatisch auf «Production».

### Auf echten Geräten prüfen (nur mit bezahltem Konto möglich)
Die CI prüft den Kern (u.a. Simulation zweier Geräte mit einem Server im Speicher, zufällige Änderungen, Konflikte, Löschen, Dateien) und dass die App mit dem CloudKit-Code baut. Nicht automatisch prüfbar sind die echte CKSyncEngine (Ereignisse, Push, Kontingent, Verschlüsselung, Konto-Wechsel). Checkliste:
1. iPhone mit Daten: Schalter an → «Auf allen deinen Geräten aktuell».
2. iPad frisch installieren: Einführung schliesst sich, Meldung, alle Daten da, keine doppelten Kategorien oder «Ich».
3. Vertrag auf dem iPhone ändern → iPad zeigt die Änderung (sofort per Push oder beim Öffnen). Ebenso Logo setzen, Kategorie verschieben, Einnahme löschen.
4. iPad im Flugmodus ändern, iPhone ändert anderes; Flugmodus aus → beide gleich.
5. Ausschalten mit «Aus iCloud löschen» auf dem iPhone → iPad meldet es, Schalter aus, Daten bleiben.
6. In den iPhone-Einstellungen von iCloud abmelden → «Nicht bei iCloud angemeldet», Daten bleiben.

### Grenzen
- Konflikte entscheidet die Uhrzeit der Geräte: Bei falsch gestellter Uhr kann eine ältere Änderung gewinnen.
- Ändert ein Gerät mit einer älteren App-Version einen Eintrag, gehen Felder einer neueren Version verloren – Geräte aktuell halten.
- Der Text «Datenschutz» unter Mehr → Rechtliches erwähnt iCloud noch nicht (vor der Veröffentlichung ergänzen).

## Daten aus der Web-App übernehmen
Web-App: Mehr → Daten → «Backup erstellen» → Datei in iCloud Drive sichern.
iPhone-App: Mehr → Daten → «Backup laden» → Datei wählen. Verträge, Einnahmen, Personen, Absender, Unterschriften, Kategorien, Logos und Dokumente werden übernommen.

## Aufbau
- `ARCHITEKTUR.md` – verbindliche Architektur, Datenmodell, Web → iOS
- `APP-BAUSTEINE.md` – Grundgerüst und gemeinsame Bausteine
- `docs/inventar/` – Verhalten der Web-App je Bereich (alle Texte wörtlich), Grundlage des Nachbaus
- `KontivoCore/` – Swift Package ohne Oberfläche (`swift test` läuft auch ohne Simulator)
- `Kontivo/` – App (SwiftUI), je Bereich ein Ordner
- `KontivoCore/Sources/KontivoCore/Sync/` (Regeln, ohne CloudKit, getestet) und `Kontivo/Sync/` (CKSyncEngine) – iCloud-Sync, siehe ARCHITEKTUR «iCloud-Sync»
- `project.yml` – Projektbeschreibung für XcodeGen

## Bewusst anders als die Web-App (native Möglichkeiten)
- Kündigungsbrief: eigene Knöpfe «Per Mail senden» (PDF als Anhang), «Drucken», «Teilen» statt nur Teilen-Menü
- Kalender: «In Kalender» per langem Drücken auf eine Frist und im Vertragsdetail (Menü •••), Erinnerung 7 Tage und 1 Tag vorher
- Mitteilungen vor Fristende (Mehr → Erinnerungen und Sicherheit, «Tage vorher» 1/3/7/14/30), Tippen öffnet den Vertrag
- App-Sperre mit Face ID bzw. Gerätecode, Abdeckung im App-Umschalter
- Kontoauszug auch als PDF oder Foto/Scan (Texterkennung mit Apple Vision, nur auf dem Gerät)
- Unterschrift mit PencilKit (Apple Pencil auf dem iPad)
- Wischen und langes Drücken auf Vertragskarten (Pausieren, Duplizieren, Kündigen)
- Datenmodell mit IDs statt Namen (Umbenennen von Personen, Kategorien und Vertragspartnern ist sicher), mehrere Pausen pro Vertrag, Schalter «Mietvertrag»
- Datum im Schweizer Format, Beträge je Währung wie Web (EUR 1.234,50 · CHF 1’234.50)

## Vor einer Veröffentlichung noch offen
- Auf iPhone und iPad testen (Gesten, Kalender, Mail, Drucken, Kamera/Dateien, Backup-Import einer echten Web-Sicherung)
- App-Icon in 1024 px aus der Originalgrafik (derzeit aus 512 px hochgerechnet)
- Datenschutzerklärung für den App Store, Hinweis, dass Backups Unterschriften enthalten
- iCloud-Sync mit bezahltem Apple-Konto einschalten und auf iPhone/iPad prüfen (siehe «iCloud-Sync»), CloudKit-Schema nach Production übernehmen, Datenschutztext um iCloud ergänzen
- Danach: Widget «Nächste Frist»
