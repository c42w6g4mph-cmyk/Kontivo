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
- A10: WebLinks.googleImages statt mdGoogleImageURL

## Offen
- F12, F13, F14, F15, A10 Rest (Zwischenablage/Toast), Teil B (Backup im Hintergrund, ImageIO, PasteButton)
