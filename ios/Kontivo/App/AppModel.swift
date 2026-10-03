import SwiftUI
import Observation
import KontivoCore

/// Zentraler App-Zustand. Hält die Daten (AppData), speichert sie lokal und steuert Fenster (Sheets) und Meldungen (Toast).
/// Ansichten ändern Daten nur über `update { … }` bzw. die Fachaktionen aus KontivoCore (Mutations).
@MainActor
@Observable
final class AppModel {
    // MARK: Daten
    var data: AppData
    let files: FileStore

    // MARK: Navigation
    var tab: AppTab = .contracts
    /// Gestapelte Fenster: [0] liegt über der Hauptansicht, [1] über [0] usw.
    var sheets: [AppSheet] = []
    /// Einführung (nil = nicht sichtbar)
    var onboarding: OnboardingMode?

    // MARK: Gemeinsamer Ansichtszustand (wie state.* in der Web-App)
    /// Filter für Verträge-Liste und Kosten (Kategorie, Vertragspartner, Person)
    var costFilter = Calc.CostFilter()
    /// Gewählter Monat/Jahr in Kosten und Budget
    var selectedYear: Int
    var selectedMonth: Int   // 1–12
    /// Personenfilter im Budget
    var budgetPerson: UUID?
    /// Suche und Hero-Filter in «Verträge»
    var searchText = ""
    var heroFilter: HeroFilter?
    var showArchive = false

    /// Kündigung über Website/E-Mail gestartet: beim Zurückkehren fragen «Gekündigt?»
    var pendingCancel: PendingCancel?
    /// Sichtbare Rückfrage «Gekündigt?» (wird auf der obersten Ebene als Alert gezeigt, siehe CancelQuestionModifier)
    var cancelQuestion: PendingCancel?

    /// Bildschirmfoto-Modus (Debug): Beispieldaten, nichts wird gespeichert
    var uiTestMode = false

    // MARK: Meldungen
    var toastText: String?
    private var toastTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init() {
        let store = FileStore()
        self.files = store
        let t = Day.today(in: .current)
        self.selectedYear = t.year
        self.selectedMonth = t.month
        if let loaded = store.loadData() {
            self.data = loaded
        } else {
            self.data = AppData.initial(homeCurrency: .CHF)
        }
        #if DEBUG
        if applyUITestArguments() { return }
        #endif
        // Bestehende Daten: Einführung gilt als gesehen; ohne Daten startet die Einführung
        if data.settings.onboarded == 0 {
            if !data.contracts.isEmpty || !data.incomes.isEmpty {
                data.settings.onboarded = 1
                saveNow()
            } else {
                onboarding = .firstRun
            }
        }
    }

    // MARK: Abgeleitet
    /// Fester Stichtag (nur Bildschirmfoto-Modus), sonst heute
    var todayOverride: Day?
    var today: Day { todayOverride ?? Day.today(in: .current) }
    var calc: Calc { Calc(data: data, today: today) }

    var preferredColorScheme: ColorScheme? {
        switch data.settings.theme {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    // MARK: Ändern und Speichern
    /// Führt eine Änderung aus, speichert und zeigt Fehler als Toast. Gibt true zurück, wenn es geklappt hat.
    @discardableResult
    func update(_ body: (inout AppData) throws -> Void) -> Bool {
        var copy = data
        do {
            try body(&copy)
            data = copy
            scheduleSave()
            return true
        } catch let e as MutationError {
            toast(e.message)
            return false
        } catch {
            toast("Das hat nicht geklappt")
            return false
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        if uiTestMode { return }
        if !files.saveData(data) {
            toast("Speichern fehlgeschlagen – Gerätespeicher voll? Bitte ein Backup erstellen.")
        }
    }

    // MARK: Fenster
    /// Fenster öffnen. Dasselbe Fenster nicht doppelt übereinander (z.B. doppeltes Antippen).
    func present(_ sheet: AppSheet) {
        if sheets.last?.id == sheet.id { return }
        sheets.append(sheet)
    }
    /// Oberstes Fenster schliessen
    func dismissTop() { if !sheets.isEmpty { sheets.removeLast() } }
    /// Fenster ab Ebene `level` schliessen (Wischen nach unten)
    func dismiss(level: Int) { if level < sheets.count { sheets.removeSubrange(level...) } }
    func dismissAll() { sheets.removeAll() }

    func goTab(_ t: AppTab) { dismissAll(); tab = t }

    // MARK: Toast
    func toast(_ text: String, seconds: Double = 2.4) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toastText = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toastText = nil }
        }
    }

    // MARK: Lebenszyklus
    func sceneBecameActive() {
        cancelReturnCheck()
        Task { await RateService.refreshIfNeeded(self, force: false) }
    }

    // MARK: Dateien (Logos, Dokumente, Bilder)
    func image(_ id: String?) -> UIImage? { files.image(id) }

    /// Datei speichern; bei Fehler Toast und nil
    func storeFile(_ data: Data, type: String) -> String? {
        do { return try files.put(data, type: type) } catch {
            toast("Speichern nicht möglich")
            return nil
        }
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case contracts, costs, budget, deadlines, more
}

enum OnboardingMode: String, Identifiable {
    case firstRun, tour
    var id: String { rawValue }
}

enum HeroFilter: String, Hashable {
    case active = "act", paused, future = "fut"
}

struct PendingCancel: Hashable {
    var contractID: UUID
    var trial: Bool
    /// Wurde die App seither verlassen (Website/Mail geöffnet)?
    var leftApp: Bool = false
}
