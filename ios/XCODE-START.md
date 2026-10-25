# Kontivo in Xcode starten (eigener Mac, ohne bezahltes Apple-Konto)

Stand: Branch `swift` (25.10.2026). Rechenkern nach Web v323; Oberfläche noch auf Stand Web v225 (Nachzug siehe Projekt-Dokument `kontivo-swift-nachzug`).

## Voraussetzungen
- Mac mit **Xcode 26.2** (so baut und testet auch die CI, siehe `.github/workflows/ios.yml`). Ältere Xcode-Versionen können am iOS-26-SDK scheitern.
- iPhone mit **iOS 17 oder neuer** und USB-Kabel (oder ein Simulator in Xcode).
- Eine Apple-ID. Das kostenlose «Personal Team» reicht.
- XcodeGen ist **nicht** nötig: das fertige Projekt `ios/Kontivo.xcodeproj` liegt im Repo.

## 1. Projekt herunterladen
- GitHub → Repo `Kontivo` → Branch **swift** wählen → **Code** → **Download ZIP**, entpacken.
- oder im Terminal: `git clone -b swift https://github.com/c42w6g4mph-cmyk/Kontivo.git`

## 2. Öffnen
`ios/Kontivo.xcodeproj` doppelklicken. Xcode lädt das lokale Paket `KontivoCore` selbst (kein Internet nötig).

## 3. Signieren
1. Links das Projekt «Kontivo» → Target **Kontivo** → Reiter **Signing & Capabilities**.
2. «Automatically manage signing» an, bei **Team** deine Apple-ID wählen («… (Personal Team)»; falls sie fehlt: Xcode → Settings → Accounts → «+»).
3. Dasselbe beim Target **KontivoUITests** (nur für Tests nötig).
4. Meldet Xcode «Bundle Identifier … is not available»: die Bundle-ID `ch.kontivo.app` ist schon vergeben. Dann eine eigene eintragen, z.B. `ch.deinname.kontivo` (und bei den UI-Tests `ch.deinname.kontivo.uitests`). Sonst nichts ändern.

## 4. Auf dem iPhone starten
1. iPhone per Kabel anschliessen, entsperren, «Diesem Computer vertrauen».
2. Am iPhone **Entwicklermodus** einschalten: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → an, iPhone startet neu, bestätigen.
3. Oben in Xcode als Ziel dein iPhone wählen, **Run** (▶ bzw. Cmd+R).
4. Beim ersten Start: Einstellungen → Allgemein → VPN & Geräteverwaltung → Entwicklerprofil (deine Apple-ID) → «Vertrauen».

## Tests
- **Cmd+U** führt die UI-Tests aus (am besten im Simulator «iPhone 17 Pro», dauert ca. 1 h).
- Kern-Tests ohne Simulator: im Terminal `cd ios/KontivoCore && swift test`.

## Bekannte Einschränkungen
- **iCloud-Sync und Push** brauchen das bezahlte Apple Developer Program. Im Standard-Build sind sie aus (`KONTIVO_ICLOUD: "NO"` in `ios/project.yml`): keine Berechtigungen (Entitlements), CloudKit wird nie angesprochen, die App läuft ohne Sync. Im Debug-Build steht unter Mehr → Daten der Hinweis «iCloud-Sync: in diesem Build aus». Einschalten: siehe `ios/README.md` «iCloud-Sync einschalten» (Datei `ios/Kontivo/Kontivo.entitlements`). Ein Widget gibt es in diesem Stand nicht.
- Mit dem Personal Team läuft die App **7 Tage**; danach in Xcode erneut auf Run tippen (Daten bleiben erhalten).
- Daten liegen nur auf dem Gerät (Backup über Mehr → Daten).

## Projekt neu erzeugen (optional)
`ios/project.yml` bleibt die Quelle. Nach neuen oder gelöschten Dateien: `brew install xcodegen`, dann `cd ios && xcodegen`.

## Bewusste Abweichungen zur Web-App
- Tab-Leiste, Fenster (Sheets), Menüs, Datums- und Fotoauswahl sind die nativen iOS-Bausteine.
- Einnahme bearbeiten: das Formular liegt über der Einnahme-Ansicht statt sie zu ersetzen (nach «Sichern» zeigt die Ansicht die neuen Werte).
- Symbole Büroklammer, Stift und Katalog im Vertragsbereich behalten die Strichstärke des Web-Kontexts (eigene `ic.ct.*`), alle anderen kommen aus den gemeinsamen Web-Symbolen.
- iCloud-Sync, App-Sperre (Face ID), Erinnerungen und Kalendereintrag nutzen iOS-Funktionen.
