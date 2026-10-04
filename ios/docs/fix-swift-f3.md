# Fix-Stand swift-f3 (Kosten, Budget, Fristen, Kündigung)

Funde aus review/s3-kosten-fristen.md (A1–A12), s1 B-1 / L-2, s5 A3/A4/A5/A6/A7 (Bereich), Teil B Kostenjahr-Cache.

## Erledigt
- s1 B-1 / s3 A2: Budget-Vorjahresvergleich auch bei Einnahme ohne Beginn gesperrt (ExtKostenBudget.kbBudgetComparison, Test KostenBudgetTests)
- s5 A4: KBText.parseAmount → Format.parseNum; IncomeFormView nutzt Format.parseNum

- s3 A1: Personenfilter zurückgesetzt, wenn ≤ 1 Person Verträge hat (CostsTab.dropStalePerson + onChange); «×» auch bei nur Personenfilter
- s3 A11: Monatskarte – abgebrochene Geste setzt zurück (@GestureState), kein Wischen während Monatswechsel-Animation (KBShared)

## Offen
- s3 A3–A10, A12; s1 L-2 (UI-Teil); s5 A3, A5/A6, A7 (Cancel); Teil B Kostenjahr-Cache
