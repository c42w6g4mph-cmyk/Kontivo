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
    /// Personenfilter im Budget = derselbe wie in Verträgen/Kosten (Web: state.bHolder ↔ state.flt.holder, seit 06.10.2026 ein Filter)
    var budgetPerson: UUID? {
        get { costFilter.person }
        set { costFilter.person = newValue }
    }
    /// Suche und Hero-Filter in «Verträge»
    var searchText = ""
    var heroFilter: HeroFilter?
    var showArchive = false

    /// Kündigung über Website/E-Mail gestartet: beim Zurückkehren fragen «Gekündigt?»
    var pendingCancel: PendingCancel?
    /// Sichtbare Rückfrage «Gekündigt?» (wird auf der obersten Ebene als Alert gezeigt, siehe CancelQuestionModifier)
    var cancelQuestion: PendingCancel?

    /// Allgemeine Rückfrage (`ask(...)`), wird wie «Gekündigt?» auf der obersten Ebene als Alert gezeigt
    var prompt: AppPrompt?

    /// Bildschirmfoto-Modus (Debug): Beispieldaten, nichts wird gespeichert, Dateien in einem eigenen Ordner
    var uiTestMode = false

    // MARK: Laden
    /// Speichern gesperrt: Daten wurden nicht sicher geladen (defekt, Vorversion, Gerät gesperrt) – bis der Nutzer bestätigt
    private(set) var saveBlocked = false
    /// data.json war beim Start nicht lesbar (z.B. Dateischutz) → beim Aktivieren erneut laden
    @ObservationIgnored private var loadDeferred = false
    /// Meldung zum Laden, wird beim ersten Aktivieren gezeigt
    @ObservationIgnored private var pendingLoadNotice: LoadNotice?

    // MARK: Heute
    /// Heutiges Datum (beobachtet): wird beim Aktivieren und um Mitternacht/bei Zeitänderung neu gesetzt
    private(set) var currentDay: Day
    /// Fester Stichtag (nur Bildschirmfoto-Modus/UI-Tests), sonst nil
    var todayOverride: Day?

    // MARK: Meldungen
    var toastText: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Wichtige Meldung (Speicherfehler) bis zu diesem Zeitpunkt nicht überschreiben (wie toastLock der Web-App)
    @ObservationIgnored private var toastLockUntil = Date.distantPast
    /// Speicherfehler schon gemeldet (erst nach erfolgreichem Speichern wieder melden)
    @ObservationIgnored private var saveErr = false

    // MARK: Fensterwechsel
    @ObservationIgnored private var dismissInFlight = false
    @ObservationIgnored private var afterDismissQueue: [() -> Void] = []
    @ObservationIgnored private var dismissFallback: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        #if DEBUG
        let uiTest = AppModel.isUITestLaunch
        #else
        let uiTest = false
        #endif
        let store: FileStore
        if uiTest {
            // UI-Tests/Bildschirmfotos: eigener, frischer Ordner – echte Daten und Dateien bleiben unberührt
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("KontivoUITest", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            store = FileStore(folder: dir)
        } else {
            store = FileStore()
        }
        self.files = store
        let t = Day.today(in: .current)
        self.currentDay = t
        self.selectedYear = t.year
        self.selectedMonth = t.month
        if uiTest {
            self.data = AppData.initial(homeCurrency: .CHF)
        } else {
            switch store.loadData() {
            case .missing:
                self.data = AppData.initial(homeCurrency: .CHF)
            case .loaded(let d, let fromPrevious, let broken):
                self.data = d
                if fromPrevious {
                    saveBlocked = true
                    pendingLoadNotice = .previous(brokenName: broken)
                }
            case .failed(let broken):
                self.data = AppData.initial(homeCurrency: .CHF)
                saveBlocked = true
                pendingLoadNotice = .failed(brokenName: broken)
            case .unavailable:
                self.data = AppData.initial(homeCurrency: .CHF)
                saveBlocked = true
                loadDeferred = true
            }
        }
        observeSystem()
        #if DEBUG
        if applyUITestArguments() { return }
        #endif
        // Unsicher geladen: keine Einführung, nichts speichern – erst Meldung bzw. erneutes Laden
        if saveBlocked { return }
        startOnboardingIfNeeded()
        scheduleFileCleanup()
    }

    /// Bestehende Daten: Einführung gilt als gesehen; ohne Daten startet die Einführung
    private func startOnboardingIfNeeded() {
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
    /// Heute (Stichtag im Test-Modus). Beobachtbar: Ansichten rechnen nach einem Tageswechsel neu.
    var today: Day { todayOverride ?? currentDay }
    var calc: Calc { Calc(data: data, today: today) }

    var preferredColorScheme: ColorScheme? {
        switch data.settings.theme {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    /// Darstellung für UIKit-Fenster (zuverlässiger Wechsel zurück auf «Automatisch», auch bei offenen Fenstern)
    var interfaceStyle: UIUserInterfaceStyle {
        switch data.settings.theme {
        case .light: return .light
        case .dark: return .dark
        default: return .unspecified
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

    /// Sofort speichern. false = nicht gespeichert (Fehler oder gesperrt, siehe `saveBlocked`).
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        if uiTestMode { return true }
        if saveBlocked { return false }
        if files.saveData(data) {
            saveErr = false
            return true
        }
        // Nur einmal melden (bis zum nächsten erfolgreichen Speichern), 5 s sichtbar und nicht überschreibbar
        if !saveErr {
            saveErr = true
            showToast("Speichern fehlgeschlagen – Gerätespeicher voll? Bitte ein Backup erstellen.", seconds: 5, lock: true)
        }
        return false
    }

    // MARK: Fenster
    /// Fenster öffnen.
    /// - Dasselbe Fenster bzw. derselbe Fenstertyp (Mail, Dokument, Brief, Formular …) nicht doppelt übereinander (Doppeltippen).
    /// - Läuft gerade ein Schliessen, wird das Fenster erst danach geöffnet (statt fester Wartezeiten).
    func present(_ sheet: AppSheet) {
        if dismissInFlight {
            afterDismissQueue.append { [weak self] in self?.present(sheet) }
            return
        }
        if let last = sheets.last {
            if last.id == sheet.id { return }
            if last.kind == sheet.kind && sheet.kind.singleOnTop { return }
        }
        sheets.append(sheet)
    }
    /// Fenster öffnen, sobald das laufende Schliessen fertig ist (sofort, wenn nichts schliesst).
    /// Typisch: `model.dismissAll(); model.presentAfterDismiss(.contractForm(.edit(id)))`
    func presentAfterDismiss(_ sheet: AppSheet) {
        afterDismiss { [weak self] in self?.present(sheet) }
    }
    /// Aktion ausführen, sobald das laufende Schliessen (Fenster oder Einführung) fertig ist; sofort, wenn nichts schliesst.
    func afterDismiss(_ action: @escaping () -> Void) {
        if dismissInFlight { afterDismissQueue.append(action) } else { action() }
    }
    /// Oberstes Fenster schliessen
    func dismissTop() {
        guard !sheets.isEmpty else { return }
        sheets.removeLast()
        beginDismiss()
    }
    /// Oberstes Fenster schliessen und danach `then` ausführen
    func dismissTop(then: @escaping () -> Void) {
        dismissTop()
        afterDismiss(then)
    }
    /// Fenster ab Ebene `level` schliessen (Wischen nach unten)
    func dismiss(level: Int) {
        guard level < sheets.count else { return }
        sheets.removeSubrange(level...)
        beginDismiss()
    }
    func dismissAll() {
        guard !sheets.isEmpty else { return }
        sheets.removeAll()
        beginDismiss()
    }
    /// Alle Fenster schliessen und danach `then` ausführen
    func dismissAll(then: @escaping () -> Void) {
        dismissAll()
        afterDismiss(then)
    }
    /// Einführung schliessen (optional danach `then`, z.B. ein Fenster öffnen)
    func closeOnboarding(then: (() -> Void)? = nil) {
        if onboarding != nil {
            onboarding = nil
            beginDismiss()
        }
        if let then { afterDismiss(then) }
    }

    func goTab(_ t: AppTab) { dismissAll(); tab = t }

    private func beginDismiss() {
        dismissInFlight = true
        dismissFallback?.cancel()
        // Sicherheitsnetz, falls SwiftUI kein onDismiss meldet (z.B. Fenster nie sichtbar geworden)
        dismissFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.finishDismiss()
        }
    }

    /// Von `SheetLevel` gemeldet: Fenster der Ebene `level` ist tatsächlich geschlossen.
    func sheetDidDismiss(level: Int) {
        // Nur die unterste geschlossene Ebene zählt (darüberliegende melden sich beim gemeinsamen Schliessen evtl. früher)
        guard level == sheets.count else { return }
        finishDismiss()
    }

    /// Von der Einführung (fullScreenCover) gemeldet: geschlossen.
    func onboardingDidDismiss() {
        finishDismiss()
    }

    private func finishDismiss() {
        dismissFallback?.cancel()
        dismissFallback = nil
        guard dismissInFlight else { return }
        dismissInFlight = false
        let q = afterDismissQueue
        afterDismissQueue = []
        for a in q { a() }
    }

    // MARK: Rückfrage
    /// Rückfrage mit OK- und Abbrechen-Knopf, auf der obersten Ebene (wie «Gekündigt?»).
    /// Wird erst gezeigt, wenn ein laufendes Schliessen fertig ist.
    func ask(title: String, message: String = "", ok: String, destructive: Bool = false,
             cancel: String = "Abbrechen", onCancel: (() -> Void)? = nil, action: @escaping () -> Void) {
        let p = AppPrompt(title: title, message: message, ok: ok, destructive: destructive,
                          cancel: cancel, action: action, onCancel: onCancel)
        afterDismiss { [weak self] in self?.prompt = p }
    }

    // MARK: Toast
    func toast(_ text: String, seconds: Double = 2.4) {
        showToast(text, seconds: seconds, lock: false)
    }

    private func showToast(_ text: String, seconds: Double, lock: Bool) {
        // Eine wichtige Meldung (Speicherfehler) bleibt 5 s stehen
        if !lock && Date() < toastLockUntil { return }
        if lock { toastLockUntil = Date().addingTimeInterval(seconds) }
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toastText = text }
        // VoiceOver liest die Meldung vor (sonst passiert z.B. beim Tippen auf «Sichern» scheinbar nichts)
        let announcement = NSAttributedString(string: text, attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.high])
        UIAccessibility.post(notification: .announcement, argument: announcement)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toastText = nil }
        }
    }

    // MARK: Lebenszyklus
    func sceneBecameActive() {
        refreshToday()
        if loadDeferred { retryDeferredLoad() }
        if let n = pendingLoadNotice {
            pendingLoadNotice = nil
            showLoadNotice(n)
        }
        cancelReturnCheck()
        Task { await RateService.refreshIfNeeded(self, force: false) }
    }

    /// Heute neu bestimmen (Tageswechsel, Zeitzone). Kosten/Budget gehen mit, wenn sie auf dem alten Monat standen.
    func refreshToday() {
        let t = Day.today(in: .current)
        guard t != currentDay else { return }
        let old = currentDay
        currentDay = t
        if todayOverride == nil && selectedYear == old.year && selectedMonth == old.month {
            selectedYear = t.year
            selectedMonth = t.month
        }
    }

    private func observeSystem() {
        let nc = NotificationCenter.default
        // Mitternacht, Zeitzonen- und Uhrzeitwechsel
        for name in [UIApplication.significantTimeChangeNotification, Notification.Name.NSCalendarDayChanged] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.refreshToday() }
            })
        }
        // Gerät entsperrt: zurückgestelltes Laden nachholen
        observers.append(nc.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.loadDeferred { self.retryDeferredLoad() }
            }
        })
    }

    // MARK: Sicheres Laden
    private func retryDeferredLoad() {
        switch files.loadData() {
        case .unavailable:
            return
        case .missing:
            loadDeferred = false
            saveBlocked = false
            startOnboardingIfNeeded()
        case .loaded(let d, let fromPrevious, let broken):
            loadDeferred = false
            data = d
            if fromPrevious {
                showLoadNotice(.previous(brokenName: broken))
            } else {
                saveBlocked = false
                startOnboardingIfNeeded()
                scheduleFileCleanup()
            }
        case .failed(let broken):
            loadDeferred = false
            showLoadNotice(.failed(brokenName: broken))
        }
    }

    private func showLoadNotice(_ n: LoadNotice) {
        switch n {
        case .previous(let broken):
            let file = broken.map { " Die beschädigte Datei bleibt als «\($0)» im App-Ordner erhalten." } ?? ""
            ask(title: "Daten wiederhergestellt",
                message: "Die gespeicherten Daten konnten nicht gelesen werden. Kontivo hat die zuvor gespeicherte Fassung geladen – die letzten Änderungen fehlen eventuell." + file,
                ok: "Verstanden", cancel: "Backup laden",
                onCancel: { [weak self] in
                    guard let self else { return }
                    self.confirmLoadedData()
                    MoreRequests.openBackupImport(self)
                },
                action: { [weak self] in self?.confirmLoadedData() })
        case .failed(let broken):
            let file = broken.map { " Die Datei bleibt als «\($0)» im App-Ordner erhalten." } ?? ""
            ask(title: "Daten konnten nicht gelesen werden",
                message: "Die gespeicherten Daten sind beschädigt und es gibt keine lesbare Vorversion." + file + " Spiel ein Backup ein oder beginne neu.",
                ok: "Backup laden", cancel: "Neu beginnen",
                onCancel: { [weak self] in
                    guard let self else { return }
                    self.saveBlocked = false
                    self.onboarding = .firstRun
                },
                action: { [weak self] in
                    guard let self else { return }
                    self.saveBlocked = false
                    MoreRequests.openBackupImport(self)
                })
        }
    }

    /// Nutzer hat die wiederhergestellten Daten bestätigt: Speichern wieder erlauben und sofort sichern
    private func confirmLoadedData() {
        saveBlocked = false
        saveNow()
        startOnboardingIfNeeded()
        scheduleFileCleanup()
    }

    // MARK: Verwaiste Dateien
    /// Einmal pro Tag (nach dem Start): Dateien löschen, die nirgends mehr referenziert werden und älter als 7 Tage sind.
    private func scheduleFileCleanup() {
        guard !uiTestMode, !saveBlocked else { return }
        let key = "kontivo.lastFileCleanup"
        let day = currentDay.iso
        if UserDefaults.standard.string(forKey: key) == day { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !self.saveBlocked, !self.uiTestMode else { return }
            UserDefaults.standard.set(day, forKey: key)
            self.files.collectGarbage(keeping: Set(self.data.referencedFileIDs), olderThanDays: 7)
        }
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

/// Meldung nach unsicherem Laden
private enum LoadNotice {
    case previous(brokenName: String?)
    case failed(brokenName: String?)
}

/// Allgemeine Rückfrage (siehe `AppModel.ask`)
struct AppPrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var ok: String
    var destructive: Bool
    var cancel: String
    var action: () -> Void
    var onCancel: (() -> Void)?
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
