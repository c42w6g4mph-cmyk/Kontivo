# Fix-Stand swift-f3 (Kosten, Budget, Fristen, Kündigung)

Funde aus review/s3-kosten-fristen.md (A1–A12), s1 B-1 / L-2, s5 A3/A4/A5/A6/A7 (Bereich), Teil B Kostenjahr-Cache.

## Erledigt
- s1 B-1 / s3 A2: Budget-Vorjahresvergleich auch bei Einnahme ohne Beginn gesperrt (ExtKostenBudget.kbBudgetComparison, Test KostenBudgetTests)
- s5 A4: KBText.parseAmount → Format.parseNum; IncomeFormView nutzt Format.parseNum

- s3 A1: Personenfilter zurückgesetzt, wenn ≤ 1 Person Verträge hat (CostsTab.dropStalePerson + onChange); «×» auch bei nur Personenfilter
- s3 A11: Monatskarte – abgebrochene Geste setzt zurück (@GestureState), kein Wischen während Monatswechsel-Animation (KBShared)

- s3 A3: Rückfrage «Anschrift zu lang» (> 6 Zeilen) vor «Absender unvollständig» (LetterView.proceed)
- s3 A4: Referenzzeilen im PDF umbrochen (LetterPDF)
- s3 A5: nachgetragene Nummern als Referenz in den Text, Felder leeren, «Fehlt noch» ausblenden (LetterView.createPDF)
- s3 A6: «Per Einschreiben» aus der Kündigungsweg-Auswahl entfernt (Web openCancViaPick hat nur 3 Wege)
- s3 A7: Unterschrift-Fenster nicht wegwischbar (interactiveDismissDisabled), «Übernehmen» gegen Doppeltippen
- s3 A8: gezeichnete Unterschrift #1b1e23, Breite 2.4 (Web sigCv)
- s3 A9/A10/A12, s5 A5/A6 (Bereich): Fensterwechsel gekapselt in Cancel/CancelWindowFlow.swift (afterDismiss mit Zustandsprüfung,
  dismiss(ifTop:), present(over:), presentClosingOthers); Doppeltippen gesperrt in Kündigungsweg, Brief «PDF», Viewer Mail/E-Mail-Text,
  Mail-Fenster schliessen, Einnahme sichern/löschen
- s5 A7 (Teil Cancel): CancelFlowUI.ask nur noch über CancelWindowFlow.ask
- s5 A3: keine Kalender-Berechtigungsabfrage mehr (DeadlineCalendar.prepare synchron)
- s1 L-2: kein UI-Anteil nötig – Hinweis «Absender gekürzt» kommt über Letter.hints (Kern, Bereich f1) und wird im Brief schon angezeigt

## Offen
- Teil B Kostenjahr-Cache; Einnahmen-Formular Tastatur «Fertig» (s5 A12, optional)
