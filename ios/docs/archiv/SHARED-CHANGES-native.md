# Geteilte Änderungen – Bereich native

Stand 10.10.2026, Branch `w-native`. Alle übrigen Änderungen liegen in eigenen Dateien (`Kontivo/Native/*`, `Kontivo/Deadlines/*`, `Kontivo/Cancel/*`, `Kontivo/Shared/DocumentViewer.swift`, `KontivoCore/.../Reminders.swift` + `RemindersTests.swift`, `KontivoUITests/NativeUITests.swift`).

| Datei | Änderung | Warum |
|---|---|---|
| `Kontivo/App/KontivoApp.swift` | `init() { NativeBoot.start() }` | Empfänger für Mitteilungen muss vor dem Ende des App-Starts gesetzt sein, sonst geht das Tippen auf eine Erinnerung beim Kaltstart verloren. |
| `Kontivo/App/KontivoApp.swift` | `.kontivoNative()` direkt nach `RootView()` (vor `.environment(model)`, braucht das Modell) | Ein Aufruf für: Erinnerungen neu planen (Datenänderung, Tageswechsel, Rückkehr), Erinnerung öffnet Vertragsdetail, App-Sperre + Datenschutz-Abdeckung. |
| `Kontivo/More/MoreTab.swift` | eine Zeile `NativeMoreGroup()` nach `MoreDataGroup(flow:)` | Gruppe «Erinnerungen und Sicherheit» (Schalter Erinnerungen, «Tage vorher» 1/3/7/14/30, Schalter App-Sperre). Position frei verschiebbar. |
| `KontivoCore/.../Calc.swift` (`deadlineOverview`, Fall `.kept`) | Text «Behalten · läuft bis TT.MM.» statt «Behalten · nächste Frist …», wenn es keinen weiteren Termin gibt (`x.e == nil`) | Web v133 (`keptEnd`, Commit 08d11a2). Eine Zeile, kein neuer Enum-Fall. Test: `RemindersTests.testKeptNextDeadlineAndKeptEnd`. |
| `project.yml` | `NSFaceIDUsageDescription` | App-Sperre mit Face ID. `NSCalendarsWriteOnlyAccessUsageDescription` war schon da (Kalender fragt jetzt einmal nach Schreibzugriff). |
| `AppModel` | **keine Änderung**: Deep Link über `extension AppModel { func openContractFromReminder(_:) }` in `Native/ReminderScheduler.swift` (nutzt nur `tab`, `dismissAll`, `presentAfterDismiss`). | |

## Für den Bereich contracts (Vertragsdetail, Menü •••)
«In Kalender» im Menü ••• – öffentliche Hilfen in `Deadlines/DeadlineCalendar.swift`:
```swift
@State private var calendarFor: UUID?
// im Menü •••
if DeadlineCalendar.canAdd(c, calc: model.calc) {
    Button { calendarFor = c.id } label: { Label(DeadlineCalendar.menuTitle, systemImage: DeadlineCalendar.symbol) }
}
// an der Ansicht
.deadlineCalendar(contractID: $calendarFor)
```
Nimmt die nächste Frist des Vertrags (`Calc.reminderDeadline(for:)`: offenes Probeabo, sonst Kündigungsfrist, bei «Behalten» die nächste), fragt einmal nach Schreibzugriff und öffnet «Termin hinzufügen»; Toast «Termin im Kalender eingetragen».

## Geräte-Einstellungen (nicht im Backup, kein Datenmodell)
`UserDefaults` (`NativePrefs`): `kontivo.remind.on`, `kontivo.remind.days`, `kontivo.remind.asked`, `kontivo.lock.on`. In UI-Tests eigener, bei jedem Start leerer Speicher. Startargument `-uiNativeStub`: keine Systemabfragen (Berechtigung gilt als erteilt).

## Dokumentation (Vorschlag für den Integrator)
README «Vor einer Veröffentlichung noch offen»: Erinnerungen als Mitteilung und Face ID sind erledigt. ARCHITEKTUR «Web → iOS»: Kündigungsbrief hat «Per Mail senden» und «Drucken» jetzt auch direkt im Brief (ohne Vorschau).
