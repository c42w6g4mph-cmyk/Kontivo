# Fix-Stand Bereich f4 (Verwalten, Mehr, Einführung) – Branch swift-f4

## Erledigt
- F11/A4: mdParseNum entfernt → Format.parseNum (Datenqualität Betrag Vertrag/Einnahme)
- Teil B: Fachaktionen (mdSet…, MDTermChoice, mdContracts, mdPerMonth, mdSetContractAddress) nach KontivoCore/ExtManage.swift, Tests ManageMutationTests.swift
- F4: Editor Frist/Laufzeit – noticeVal-Prüfung, Vertragsende leer bis gewählt, Vorbelegung fix bei Verlängerung, Toast «jederzeit», Optionstext
- F1: Hinweistext «Alle übertragen» wie Web (gemeinsame Einträge gehören danach nur noch «An»)
- A12: «Fertig» über der Zifferntastatur (Datenqualität-Liste)
- F2: Absender – ungültiges «gleich wie» wird beim Speichern entfernt
- F7: Sammelsuche – nav.pop nur, wenn Ergebnisseite oben liegt
- F8: Offline-Prüfung (NetCheck in LogoSearchSheet.swift) für Logo-Suche und «Alle suchen»
- F9: Zusammenführen-Hinweis wörtlich wie Web
- F10: Umbenennen-Rückfrage (Vertragspartner, Inhaber) auf Fenster-Ebene (ManageNav.renameAsk), «Fertig» sichert zuerst
- Teil B: Eingaben beim Wechsel in den Hintergrund sichern (ManageNav.flush + saveNow)
- A10: WebLinks.googleImages statt mdGoogleImageURL; ImageImport (Shared/ImageCropSheet.swift) für Fotos/Dateien/Einfügen
- F12: Datenschutztext an tatsächliche Abrufe angepasst
- F13: Einführung-Tabseiten bei grosser Schrift scrollbar, Bildschirmfoto ausgeblendet
- F14: Zuschneiden nach Dateiauswahl verzögert, Datei im Hintergrund gelesen
- Teil B: ImageIO-Verkleinerung, PasteButton (keine Einfügen-Rückfrage), Backup-Export: Dateien im Hintergrund lesen + Fortschritt; Restore mit Fortschritt/Yield
- F15: Speicherfehler wird nicht von Erfolgsmeldung überschrieben (MoreDataFlow.saveOK)

- UI-Test MoreUITests.testVertragspartnerUmbenennenRueckfrageBeimZurueck (F10)
- CI voll grün (core/app/ui) auf a3f0743

## Bewusst nicht in f4 (fremde Dateien)
- F3, F6 (Kern, Bereich f1); F5 Fusszeile in Quality.swift (Kern, nicht in der Dateiliste von f4)
- F1 Verhalten transferAll (Kern, Bereich f1) – nur Hinweistext hier
- Restore schreibt Dateien weiter auf dem MainActor (mit Fortschritt/Yield): FileStore (App/) hat kein put ohne Meta-Schreiben
- A10 Rest: Toast-Kopie in LogoSearchSheet (braucht Toast-Fenster im App-Bereich), topViewController doppelt (CancelLogic), Google-Links/Zwischenablage in Contracts/Budget auf WebLinks/ImageImport umstellen

## Offen
- nichts
