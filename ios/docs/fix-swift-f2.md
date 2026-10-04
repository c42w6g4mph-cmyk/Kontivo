# Fix-Liste Branch swift-f2 (Grundgerüst und Verträge)

Quelle: Prüfberichte s2-app-vertraege.md (alle Funde) und s5-architektur.md (A1, A2, A3, A5/A6, A7 Grundgerüst, A8, A11, A12, A13, A19) + PrivacyInfo.xcprivacy.

## Erledigt
- s5 A2 / s2 A22: NSPhotoLibraryAddUsageDescription (project.yml)
- s5 A3: Kamera, Face ID, Kalender-Vollzugriff entfernt (project.yml)
- s5 A12: Startbildschirm LaunchBackground (Papierfarbe); CTKeyboardDone → Design/KeyboardDone.swift (`.kKeyboardDone()`)
- PrivacyInfo.xcprivacy (UserDefaults CA92.1, FileTimestamp C617.1, kein Tracking)
- s5 A1 / s2 A16: sicheres Laden (FileStore.LoadResult, data.broken-…, data.prev.json, saveBlocked bis Bestätigung, Nachladen bei Dateischutz)
- s2 A17: Speicherfehler einmalig, 5 s gesperrt; saveNow() -> Bool
- s5 A19 / s2 A19: Toast per UIAccessibility-Ankündigung
- s5 A8 / s2 A18: currentDay beobachtet (aktiv, Mitternacht, significantTimeChange)
- s5 A11: UI-Test-Modus eigener Ordner, selectedYear/Month vom Stichtag, Test-currentYear = 2026
- s5 A5/A6: present() mit Typ-Schutz und Warteschlange, presentAfterDismiss/afterDismiss/dismissAll(then:)/closeOnboarding, onDismiss in SheetLevel
- s5 A7 (Grundgerüst): model.ask(...) + PromptModifier
- s5 A13: verwaiste Dateien einmal pro Tag (>7 Tage)
- s2 A23: Darstellung über UIWindow.overrideUserInterfaceStyle
- APP-BAUSTEINE.md: neue APIs dokumentiert

## Offen
- s2: A1–A15, A20, A21 (Verträge)
- CI grün (ohne [noui])
