import Foundation
import CloudKit
import UIKit
import Observation
import KontivoCore

/// iCloud-Sync der App: verbindet `AppModel` (data.json bleibt die lokale Wahrheit) über den Kern `SyncCore` mit der
/// `CKSyncEngine` (private Datenbank, Zone «Kontivo»).
///
/// - Lokale Änderungen erkennt der Kern beim Speichern durch Vergleich alter/neuer Stand (`localDataSaved`).
/// - Entfernte Änderungen werden über denselben Weg gespeichert (`AppModel.syncReplace`), ohne erneut als lokale Änderung
///   zu gelten. Vorher werden offene lokale Änderungen gesichert und erfasst (`AppModel.syncFlush`).
/// - Abruf beim Start und bei jedem Aktivieren, Senden kurz nach jeder Änderung; mit Push (remote-notification) zusätzlich
///   sofort.
/// - Ohne iCloud-Berechtigung im Build, im Bildschirmfoto-/UI-Test-Modus und solange die Daten unsicher geladen sind,
///   passiert hier nichts (kein CloudKit-Aufruf).
@MainActor
@Observable
final class SyncController {
    /// Zustand für «Mehr → Daten»
    private(set) var status: SyncStatus
    /// Letzter erfolgreicher Abgleich
    private(set) var lastSync: Date?
    /// Wahl des Nutzers (Spiegel von `SyncConfig.userEnabled`, beobachtbar)
    private(set) var userEnabled: Bool

    private let disabled: Bool
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var core = SyncCore()
    /// Stand der letzten Erfassung (Vergleich je Entität beim nächsten Speichern)
    @ObservationIgnored private var base: AppData?
    /// sync-state geladen, lokale Änderungen werden erfasst
    @ObservationIgnored private var loaded = false
    /// data.json konnte nicht geschrieben werden: Zustand erst wieder sichern, wenn die Daten gesichert sind
    @ObservationIgnored private var dataBehind = false
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var bridge: SyncEngineBridge?
    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var generation = 0
    /// Engine-Zustand während des ersten Einrichtens (erst danach gespeichert)
    @ObservationIgnored private var initialEngineState: Data?
    /// Neues iCloud-Konto, das auf die Bestätigung des Nutzers wartet
    @ObservationIgnored private var pendingAccount: String?
    @ObservationIgnored private var accountObserver: NSObjectProtocol?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var connecting = false
    @ObservationIgnored private var fetchHadError = false
    @ObservationIgnored private var quotaFull = false
    @ObservationIgnored private var lastActivation = Date.distantPast
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryDelay: Double = 15
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var triedMissingFiles = Set<String>()
    /// Zuletzt gesendete Nutzlast je Datensatzname (Bestätigung ohne Rücklesen, auch bei Nutzlast als Anhang)
    @ObservationIgnored private var sentPayloads: [String: Data] = [:]
    /// Prüfung nach «zoneNotFound» läuft
    @ObservationIgnored private var checkingZone = false

    /// `disabled`: Bildschirmfoto-/UI-Test-Modus – nie aktiv
    init(disabled: Bool = false) {
        self.disabled = disabled
        let on = SyncConfig.buildEnabled && !disabled && SyncConfig.userEnabled
        userEnabled = on
        if !SyncConfig.buildEnabled {
            status = .unavailableBuild
        } else {
            status = on ? .waiting : .off
        }
    }

    // MARK: Für die Oberfläche

    /// Kann dieser Build iCloud?
    var buildEnabled: Bool { SyncConfig.buildEnabled }

    /// Läuft der Abgleich (Rückfragen «auch in iCloud und auf deinen anderen Geräten»)?
    var isActive: Bool { buildEnabled && !disabled && userEnabled && engine != nil && status.isRunning }

    /// Schalter: an, wenn gewählt und ein iCloud-Konto da ist
    var isOn: Bool { userEnabled && status != .noAccount && status != .restricted }

    /// Schalter bedienbar (ohne iCloud-Konto nicht)
    var canToggle: Bool { !disabled && status != .noAccount && status != .restricted }

    // MARK: Start

    /// Starten, sobald die Daten sicher geladen sind. `localDataUnsafe`: Vorversion geladen, Datei defekt oder neu begonnen –
    /// dann gewinnt bei gleicher ID iCloud, und nichts wird als Löschung gesendet.
    func start(_ model: AppModel, localDataUnsafe: Bool = false) {
        guard SyncConfig.buildEnabled, !disabled, !model.uiTestMode else { return }
        self.model = model
        guard SyncConfig.userEnabled else {
            status = .off
            return
        }
        if model.saveBlocked {
            status = .waiting
            return
        }
        guard loadLedger() else {
            status = .waiting
            return
        }
        let data = model.data
        if localDataUnsafe || core.looksLikeLostData(data) {
            // Nicht als Löschungen senden: neu einrichten, iCloud gewinnt bei gleicher ID
            stopEngine()
            core.restartInitial(localIsStale: data)
        }
        // Änderungen seit dem letzten Lauf (Absturz zwischen Speichern und Erfassen, Sync war aus)
        core.captureLocalChanges(data, previous: nil, now: Date())
        core.captureFiles(data, isPresent: { model.files.has($0) })
        base = data
        persist(saved: true)
        observeAccountChanges()
        if engine == nil { Task { await self.connect() } }
    }

    /// sync-state lesen (einmal). false = noch nicht lesbar (Gerät gesperrt).
    private func loadLedger() -> Bool {
        if loaded { return true }
        guard let model else { return false }
        switch model.files.loadSyncState() {
        case .unavailable:
            return false
        case .missing:
            core = SyncCore()
        case .loaded(let raw):
            if let l = try? PropertyListDecoder().decode(SyncLedger.self, from: raw) {
                core = SyncCore(ledger: l)
            } else {
                // Zustand defekt: neu einrichten, iCloud gewinnt bei gleicher ID
                core = SyncCore()
                core.restartInitial(localIsStale: model.data)
            }
        }
        loaded = true
        lastSync = core.ledger.lastSync
        return true
    }

    /// Konto prüfen und die Engine starten
    private func connect() async {
        guard engine == nil, !connecting, SyncConfig.userEnabled, loaded, let model, !model.saveBlocked else { return }
        connecting = true
        defer { connecting = false }
        let container = self.container ?? CKContainer(identifier: SyncConfig.containerID)
        self.container = container
        if status != .syncing { status = .starting }
        let account: CKAccountStatus
        do {
            account = try await container.accountStatus()
        } catch {
            status = .offline
            scheduleRetry()
            return
        }
        guard engine == nil, SyncConfig.userEnabled else { return }
        switch account {
        case .available:
            break
        case .noAccount:
            status = .noAccount
            return
        case .couldNotDetermine, .temporarilyUnavailable:
            // Vorübergehend (z.B. offline, Konto wird geprüft): später erneut
            status = .offline
            scheduleRetry()
            return
        case .restricted:
            status = .restricted
            return
        @unknown default:
            status = .noAccount
            return
        }
        let user: String
        do {
            user = try await container.userRecordID().recordName
        } catch {
            guard engine == nil, SyncConfig.userEnabled else { return }
            if core.ledger.initialDone && core.ledger.engineState != nil && core.ledger.accountName != nil {
                // Konto nicht abrufbar (offline): die Engine kennt das Konto aus ihrem Zustand und meldet einen Wechsel selbst
                makeEngine(container)
            } else {
                status = .offline
                scheduleRetry()
            }
            return
        }
        guard engine == nil, SyncConfig.userEnabled else { return }
        if let known = core.ledger.accountName, known != user {
            // Anderes Konto als beim letzten Abgleich: nicht still mischen
            pendingAccount = user
            status = .accountChanged
            return
        }
        if core.ledger.accountName == nil {
            core.ledger.accountName = user
            persist(saved: true)
        }
        makeEngine(container)
    }

    private func makeEngine(_ container: CKContainer) {
        generation += 1
        let bridge = SyncEngineBridge(controller: self, generation: generation)
        var state: CKSyncEngine.State.Serialization?
        if core.ledger.initialDone, let raw = core.ledger.engineState {
            state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: raw)
        }
        var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: bridge)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.bridge = bridge
        self.engine = engine
        initialEngineState = nil
        fetchHadError = false
        syncing = false
        retryDelay = 15
        if state == nil {
            // Zone anlegen (schadet nicht, wenn es sie schon gibt)
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncConfig.zoneID))])
        }
        if core.ledger.initialDone { pushToEngine(core.pendingKeys) }
        UIApplication.shared.registerForRemoteNotifications()
        Task { await self.syncNow() }
    }

    private func stopEngine() {
        generation += 1
        let old = engine
        engine = nil
        bridge = nil
        syncing = false
        initialEngineState = nil
        sendTask?.cancel()
        retryTask?.cancel()
        if let old { Task { await old.cancelOperations() } }
    }

    // MARK: Abgleichen

    /// Abrufen, beim ersten Mal einrichten, dann senden.
    func syncNow() async {
        guard let engine, !syncing else { return }
        let gen = generation
        syncing = true
        status = .syncing
        do {
            try await engine.fetchChanges()
            guard gen == generation else { return }
            if !core.ledger.initialDone {
                guard finishInitial() else {
                    syncing = false
                    status = .failed
                    scheduleRetry()
                    return
                }
            }
            try await engine.sendChanges()
            guard gen == generation else { return }
            syncing = false
            markSynced()
        } catch {
            guard gen == generation else { return }
            syncing = false
            if let ck = error as? CKError, ck.code == .partialFailure {
                markSynced()
            } else {
                status = classify(error)
                scheduleRetry()
            }
        }
    }

    private func markSynced() {
        let now = Date()
        lastSync = now
        core.ledger.lastSync = now
        persist(saved: true)
        status = quotaFull ? .quotaFull : .upToDate
        retryDelay = 15
    }

    private func classify(_ error: Error) -> SyncStatus {
        guard let ck = error as? CKError else { return .failed }
        switch ck.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .offline
        case .quotaExceeded:
            return .quotaFull
        case .notAuthenticated:
            return .noAccount
        default:
            return .failed
        }
    }

    /// Erneut versuchen (wachsender Abstand, nur im Vordergrund)
    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 300)
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
            if self.engine == nil { await self.connect() } else { await self.syncNow() }
        }
    }

    /// Kurz nach einer lokalen Änderung senden (die Engine plant zusätzlich selbst)
    private func scheduleSend() {
        guard engine != nil else { return }
        sendTask?.cancel()
        let gen = generation
        sendTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, gen == self.generation, let engine = self.engine, !self.syncing else { return }
            do {
                try await engine.sendChanges()
                if gen == self.generation { self.markSynced() }
            } catch {
                guard gen == self.generation else { return }
                if let ck = error as? CKError, ck.code == .partialFailure { return }
                self.status = self.classify(error)
            }
        }
    }

    // MARK: Lebenszyklus

    /// App aktiv: abrufen und senden (höchstens alle 5 s); Start nachholen, wenn er noch aussteht.
    func sceneBecameActive() {
        guard SyncConfig.buildEnabled, !disabled, SyncConfig.userEnabled, let model else { return }
        if !loaded {
            start(model)
            return
        }
        if engine == nil {
            if status != .accountChanged { Task { await self.connect() } }
            return
        }
        guard Date().timeIntervalSince(lastActivation) > 5 else { return }
        lastActivation = Date()
        // Ausstehendes, das die Engine verworfen hat (unbekannte Fehler, Speicher voll), erneut anmelden
        if core.ledger.initialDone { pushToEngine(core.pendingKeys) }
        Task { await self.syncNow() }
    }

    private func observeAccountChanges() {
        guard accountObserver == nil else { return }
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.accountDidChange() }
        }
    }

    private func accountDidChange() {
        guard SyncConfig.userEnabled, loaded, engine == nil, status != .accountChanged else { return }
        Task { await self.connect() }
    }

    // MARK: Lokale Änderungen

    /// Von `AppModel.saveNow`: lokale Änderungen erfassen und zum Senden anmelden. `persisted` = data.json geschrieben.
    func localDataSaved(_ data: AppData, persisted: Bool) {
        guard loaded, let model else { return }
        let keys = core.captureLocalChanges(data, previous: base, now: Date())
        let fileKeys = core.captureFiles(data, isPresent: { model.files.has($0) })
        base = data
        if persisted { dataBehind = false }
        persist(saved: persisted)
        if !keys.isEmpty || !fileKeys.isEmpty { pushToEngine(keys + fileKeys) }
    }

    /// Nach dem Aufräumen verwaister Dateien: auch in iCloud löschen
    func filesChanged() {
        guard loaded, let model else { return }
        let keys = core.captureFiles(model.data, isPresent: { model.files.has($0) })
        persist(saved: true)
        pushToEngine(keys)
    }

    /// data.json ist (wieder) auf dem aktuellen Stand geschrieben: Zustand sichern
    func dataWritten() {
        guard loaded else { return }
        dataBehind = false
        persist(saved: true)
    }

    // MARK: Zustand sichern

    /// sync-state schreiben – nie vor data.json (sonst gingen nach einem Absturz Änderungen verloren).
    private func persist(saved: Bool) {
        guard loaded, let model else { return }
        if !saved { dataBehind = true }
        if dataBehind { return }
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        guard let raw = try? enc.encode(core.ledger) else { return }
        model.files.saveSyncState(raw)
    }

    // MARK: Ausstehendes an die Engine

    private func pushToEngine(_ keys: [SyncKey]) {
        guard let engine, core.ledger.initialDone, !keys.isEmpty else { return }
        var existing = Set<String>()
        for c in engine.state.pendingRecordZoneChanges {
            if let t = SyncController.tag(c) { existing.insert(t) }
        }
        var add: [CKSyncEngine.PendingRecordZoneChange] = []
        var remove: [CKSyncEngine.PendingRecordZoneChange] = []
        for key in Set(keys) {
            let id = SyncRecordMapper.recordID(key)
            let save = "s:" + key.recordName
            let del = "d:" + key.recordName
            switch core.pending(key) {
            case .save?:
                if !existing.contains(save) { add.append(.saveRecord(id)) }
                if existing.contains(del) { remove.append(.deleteRecord(id)) }
            case .delete?:
                if !existing.contains(del) { add.append(.deleteRecord(id)) }
                if existing.contains(save) { remove.append(.saveRecord(id)) }
            case nil:
                if existing.contains(save) { remove.append(.saveRecord(id)) }
                if existing.contains(del) { remove.append(.deleteRecord(id)) }
            }
        }
        if !remove.isEmpty { engine.state.remove(pendingRecordZoneChanges: remove) }
        if !add.isEmpty {
            engine.state.add(pendingRecordZoneChanges: add)
            scheduleSend()
        }
    }

    /// «s:<Name>» bzw. «d:<Name>» einer ausstehenden Änderung
    private static func tag(_ c: CKSyncEngine.PendingRecordZoneChange) -> String? {
        switch c {
        case .saveRecord(let id): return "s:" + id.recordName
        case .deleteRecord(let id): return "d:" + id.recordName
        @unknown default: return nil
        }
    }

    /// Nächster Stapel zum Senden (aus den ausstehenden Änderungen der Engine, Inhalt aus den aktuellen Daten)
    func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine, generation gen: Int) -> CKSyncEngine.RecordZoneChangeBatch? {
        guard gen == generation, engine === self.engine, let model, core.ledger.initialDone else { return nil }
        let scope = context.options.scope
        let changes = engine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []
        var drop: [CKSyncEngine.PendingRecordZoneChange] = []
        var bytes = 0
        var fileCount = 0
        for change in changes {
            if saves.count + deletes.count >= 150 || bytes > 1_500_000 { break }
            switch change {
            case .saveRecord(let id):
                guard let key = SyncRecordMapper.key(id) else {
                    drop.append(change)
                    continue
                }
                switch core.outgoing(key, data: model.data) {
                case .save(let rec)?:
                    saves.append(SyncRecordMapper.record(for: rec, id: id, systemFields: core.ledger.systemFields[id.recordName]))
                    sentPayloads[id.recordName] = rec.payload
                    bytes += min(rec.payload.count, SyncRecordMapper.inlineLimit)
                case .saveFile(let fid)?:
                    guard model.files.has(fid) else {
                        drop.append(change)
                        continue
                    }
                    if fileCount >= 5 { continue }
                    fileCount += 1
                    saves.append(SyncRecordMapper.fileRecord(id: id, url: model.files.url(fid), type: model.files.type(fid),
                                                             systemFields: core.ledger.systemFields[id.recordName]))
                default:
                    drop.append(change)
                }
            case .deleteRecord(let id):
                guard let key = SyncRecordMapper.key(id), core.pending(key) == .delete else {
                    drop.append(change)
                    continue
                }
                deletes.append(id)
            @unknown default:
                continue
            }
        }
        if !drop.isEmpty { engine.state.remove(pendingRecordZoneChanges: drop) }
        if saves.isEmpty && deletes.isEmpty { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: saves, recordIDsToDelete: deletes, atomicByZone: false)
    }

    // MARK: Ereignisse

    func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine, generation gen: Int) {
        guard gen == generation, engine === self.engine else { return }
        switch event {
        case .stateUpdate(let e):
            let raw = try? JSONEncoder().encode(e.stateSerialization)
            if core.ledger.initialDone {
                core.ledger.engineState = raw
                persist(saved: true)
            } else {
                initialEngineState = raw
            }
        case .accountChange(let e):
            accountChanged(e.changeType)
        case .fetchedDatabaseChanges(let e):
            fetchedDatabaseChanges(e)
        case .fetchedRecordZoneChanges(let e):
            fetchedRecords(e)
        case .sentDatabaseChanges(let e):
            sentDatabaseChanges(e)
        case .sentRecordZoneChanges(let e):
            sentRecords(e)
        case .willFetchChanges:
            fetchHadError = false
        case .didFetchRecordZoneChanges(let e):
            if e.zoneID == SyncConfig.zoneID, e.error != nil { fetchHadError = true }
        case .didFetchChanges:
            didFetch()
        default:
            break
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case .signIn(let user):
            if let known = core.ledger.accountName, known != user.recordName {
                pendingAccount = user.recordName
                pause(.accountChanged)
            } else if core.ledger.accountName == nil {
                core.ledger.accountName = user.recordName
                persist(saved: true)
            }
        case .signOut:
            // Abgemeldet: Abgleich aus, lokale Daten bleiben
            pause(.noAccount)
        case .switchAccounts(_, let user):
            pendingAccount = user.recordName
            pause(.accountChanged)
        @unknown default:
            break
        }
    }

    /// Engine anhalten, Server-Wissen verwerfen (lokale Daten bleiben)
    private func pause(_ s: SyncStatus) {
        stopEngine()
        core.resetServerState()
        persist(saved: true)
        status = s
    }

    private func fetchedDatabaseChanges(_ e: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for d in e.deletions where d.zoneID == SyncConfig.zoneID {
            switch d.reason {
            case .encryptedDataReset:
                // Schlüssel zurückgesetzt: Zone neu anlegen, alles neu hochladen
                zoneMissing()
            default:
                // Auf einem anderen Gerät «Auch aus iCloud löschen» oder in den iCloud-Einstellungen gelöscht
                deletedElsewhere()
            }
            return
        }
    }

    private func deletedElsewhere() {
        SyncConfig.userEnabled = false
        userEnabled = false
        pause(.deletedElsewhere)
        model?.toast(SyncTexts.deletedElsewhereToast, seconds: 4)
    }

    private func zoneMissing() {
        guard let model, let engine else { return }
        let keys = core.zoneMissing(model.data, isPresent: { model.files.has($0) }, now: Date())
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncConfig.zoneID))])
        persist(saved: true)
        pushToEngine(keys)
    }

    private func fetchedRecords(_ e: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        guard let model else { return }
        var records: [SyncRecord] = []
        var deletions: [SyncKey] = []
        var fields: [String: Data] = [:]
        var stored: [String] = []
        for m in e.modifications {
            let r = m.record
            guard let key = SyncRecordMapper.key(r.recordID) else { continue }
            if key.kind == .file {
                if storeFile(r, id: key.id) {
                    stored.append(key.id)
                    fields[key.recordName] = SyncRecordMapper.systemFields(r)
                }
                continue
            }
            guard let rec = SyncRecordMapper.syncRecord(from: r, key: key) else { continue }
            records.append(rec)
            fields[key.recordName] = SyncRecordMapper.systemFields(r)
        }
        for del in e.deletions {
            if let key = SyncRecordMapper.key(del.recordID) { deletions.append(key) }
        }
        if records.isEmpty && deletions.isEmpty && fields.isEmpty { return }
        model.syncFlush()
        var working = model.data
        let res = core.applyRemote(records: records, deletions: deletions, systemFields: fields, storedFiles: stored,
                                   data: &working, isPresent: { model.files.has($0) }, now: Date())
        var saved = true
        if res.changed { saved = model.syncReplace(working); if saved { dataBehind = false } }
        base = model.data
        persist(saved: saved)
        pushToEngine(res.resend)
    }

    /// Abruf vollständig: Doppelte zusammenführen, Mindestbestand, fehlende Dateien holen
    private func didFetch() {
        guard let model, core.ledger.initialDone else { return }
        if fetchHadError {
            fetchHadError = false
            return
        }
        model.syncFlush()
        var working = model.data
        let r = core.finishFetch(&working, isPresent: { model.files.has($0) }, now: Date())
        var saved = true
        if r.changed { saved = model.syncReplace(working); if saved { dataBehind = false } }
        base = model.data
        lastSync = core.ledger.lastSync
        persist(saved: saved)
        pushToEngine(r.resend)
        if !syncing { status = quotaFull ? .quotaFull : .upToDate }
        downloadMissingFiles()
    }

    /// Erstes Einrichten nach dem ersten vollständigen Abruf. false = Abruf unvollständig, später erneut.
    private func finishInitial() -> Bool {
        guard let model else { return false }
        if fetchHadError {
            fetchHadError = false
            return false
        }
        model.syncFlush()
        let firstRun = model.onboarding == .firstRun
        var working = model.data
        let r = core.finishFetch(&working, isPresent: { model.files.has($0) }, now: Date())
        if let s = initialEngineState { core.ledger.engineState = s }
        initialEngineState = nil
        let saved = r.changed ? model.syncReplace(working) : true
        if r.changed && saved { dataBehind = false }
        base = model.data
        lastSync = core.ledger.lastSync
        persist(saved: saved)
        pushToEngine(core.pendingKeys)
        downloadMissingFiles()
        if r.adopted && (!working.contracts.isEmpty || !working.incomes.isEmpty) {
            model.syncAdoptedICloudData(endOnboarding: firstRun)
        }
        return true
    }

    private func sentDatabaseChanges(_ e: CKSyncEngine.Event.SentDatabaseChanges) {
        for f in e.failedZoneSaves where f.zone.zoneID == SyncConfig.zoneID {
            if f.error.code == .quotaExceeded {
                quotaFull = true
                status = .quotaFull
            }
        }
    }

    private func sentRecords(_ e: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let model else { return }
        var resend: [SyncKey] = []
        var missingZone = false
        var working: AppData?
        var anySaved = false
        for r in e.savedRecords {
            guard let key = SyncRecordMapper.key(r.recordID) else { continue }
            anySaved = true
            let payload = key.kind == .file ? nil : (sentPayloads.removeValue(forKey: key.recordName) ?? SyncRecordMapper.payload(of: r))
            if key.kind != .file { SyncRecordMapper.removeTempFile(name: key.recordName) }
            if core.didSave(key, payload: payload, systemFields: SyncRecordMapper.systemFields(r)) { resend.append(key) }
        }
        for f in e.failedRecordSaves {
            guard let key = SyncRecordMapper.key(f.record.recordID) else { continue }
            switch f.error.code {
            case .serverRecordChanged:
                guard let server = f.error.serverRecord else {
                    resend.append(key)
                    continue
                }
                let fields = SyncRecordMapper.systemFields(server)
                let rec: SyncRecord?
                if key.kind == .file {
                    rec = SyncRecord(key: key, payload: Data(), modifiedAt: Date())
                } else {
                    rec = SyncRecordMapper.syncRecord(from: server, key: key)
                }
                guard let serverRec = rec else {
                    // Server-Fassung unlesbar: mit den neuen Systemfeldern überschreiben
                    core.ledger.systemFields[key.recordName] = fields
                    resend.append(key)
                    continue
                }
                if working == nil {
                    model.syncFlush()
                    working = model.data
                }
                var w = working ?? model.data
                if core.resolveConflict(server: serverRec, systemFields: fields, data: &w, now: Date()) { resend.append(key) }
                working = w
            case .zoneNotFound:
                missingZone = true
            case .userDeletedZone:
                deletedElsewhere()
                return
            case .unknownItem:
                core.recordMissingOnServer(key)
                resend.append(key)
            case .quotaExceeded:
                // Bleibt ausstehend; erneut beim nächsten Aktivieren
                quotaFull = true
                status = .quotaFull
            default:
                // Netz, Last, Anmeldung: die Engine versucht es selbst erneut; Übriges beim nächsten Aktivieren
                break
            }
        }
        for id in e.deletedRecordIDs {
            guard let key = SyncRecordMapper.key(id) else { continue }
            if core.didDelete(key) { resend.append(key) }
        }
        for (id, error) in e.failedRecordDeletes {
            guard let key = SyncRecordMapper.key(id) else { continue }
            switch error.code {
            case .unknownItem, .zoneNotFound:
                if core.didDelete(key) { resend.append(key) }
            default:
                break
            }
        }
        if anySaved && quotaFull && e.failedRecordSaves.allSatisfy({ $0.error.code != .quotaExceeded }) {
            quotaFull = false
        }
        var saved = true
        if let w = working, w != model.data { saved = model.syncReplace(w); if saved { dataBehind = false } }
        base = model.data
        persist(saved: saved)
        pushToEngine(resend)
        if missingZone { zoneNotFoundOnSend() }
    }

    /// Zone fehlt beim Senden: erst die Datenbankänderungen abrufen. Hat ein anderes Gerät sie gelöscht («Aus iCloud
    /// löschen»), meldet das der Abruf (`deletedElsewhere`, hier aus) – dann nichts neu hochladen. Sonst Zone neu anlegen.
    private func zoneNotFoundOnSend() {
        guard let engine, !checkingZone else { return }
        checkingZone = true
        let gen = generation
        Task { @MainActor [weak self] in
            var fetched = true
            do { try await engine.fetchChanges() } catch { fetched = false }
            guard let self else { return }
            self.checkingZone = false
            guard gen == self.generation, self.engine === engine, SyncConfig.userEnabled else { return }
            if !fetched {
                // Unklar (offline): beim nächsten Abgleich erneut
                self.scheduleRetry()
                return
            }
            self.zoneMissing()
        }
    }

    // MARK: Dateien

    /// Datei aus einem Datensatz speichern (gleiche ID). true = vorhanden.
    private func storeFile(_ r: CKRecord, id: String) -> Bool {
        guard let model, SyncKey.isFileID(id) else { return false }
        if model.files.has(id) { return true }
        guard let f = SyncRecordMapper.file(of: r) else { return false }
        return (try? model.files.put(f.data, type: f.type, id: id)) != nil
    }

    /// Referenzierte, lokal fehlende Dateien gezielt holen (je Datei einmal pro App-Lauf)
    private func downloadMissingFiles() {
        guard let model, let container, engine != nil else { return }
        let missing = model.data.referencedFileIDs.filter { SyncKey.isFileID($0) && !model.files.has($0) && !triedMissingFiles.contains($0) }
        guard !missing.isEmpty else { return }
        triedMissingFiles.formUnion(missing)
        let ids = missing.prefix(100).compactMap { SyncKey.file($0).map { SyncRecordMapper.recordID($0) } }
        let gen = generation
        Task { @MainActor [weak self] in
            guard let results = try? await container.privateCloudDatabase.records(for: ids) else { return }
            guard let self, gen == self.generation, let model = self.model else { return }
            var stored: [String] = []
            var fields: [String: Data] = [:]
            for (rid, result) in results {
                guard case .success(let r) = result, let key = SyncRecordMapper.key(rid), key.kind == .file else { continue }
                if self.storeFile(r, id: key.id) {
                    stored.append(key.id)
                    fields[key.recordName] = SyncRecordMapper.systemFields(r)
                }
            }
            guard !stored.isEmpty else { return }
            var working = model.data
            _ = self.core.applyRemote(records: [], deletions: [], systemFields: fields, storedFiles: stored, data: &working,
                                      isPresent: { model.files.has($0) }, now: Date())
            self.persist(saved: true)
            model.filesDidArrive()
        }
    }

    // MARK: Ein-/Ausschalten, Konto

    /// Schalter an
    func turnOn() {
        guard SyncConfig.buildEnabled, !disabled else { return }
        SyncConfig.userEnabled = true
        userEnabled = true
        status = .starting
        if let model { start(model) }
    }

    /// Schalter aus: Abgleich beenden, Daten bleiben auf diesem Gerät. `deleteFromICloud`: auch die Zone in iCloud löschen.
    func turnOff(deleteFromICloud: Bool) async {
        guard SyncConfig.buildEnabled, !disabled else { return }
        SyncConfig.userEnabled = false
        userEnabled = false
        pendingAccount = nil
        stopEngine()
        if loadLedger() {
            core.resetServerState()
            persist(saved: true)
        }
        loaded = false
        base = nil
        status = .off
        guard deleteFromICloud else {
            model?.toast(SyncTexts.offToast)
            return
        }
        let container = self.container ?? CKContainer(identifier: SyncConfig.containerID)
        self.container = container
        do {
            let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [SyncConfig.zoneID])
            if case .failure(let error)? = result.deleteResults[SyncConfig.zoneID] {
                if (error as? CKError)?.code != .zoneNotFound { throw error }
            }
            model?.toast(SyncTexts.deletedToast)
        } catch {
            if (error as? CKError)?.code == .zoneNotFound {
                model?.toast(SyncTexts.deletedToast)
            } else {
                model?.toast(SyncTexts.deleteFailedToast, seconds: 4)
            }
        }
    }

    /// Nutzer bestätigt: mit dem jetzt angemeldeten (anderen) iCloud-Konto zusammenführen
    func adoptCurrentAccount() {
        guard let account = pendingAccount, loaded else { return }
        core.resetServerState()
        core.ledger.accountName = account
        pendingAccount = nil
        persist(saved: true)
        status = .starting
        Task { await self.connect() }
    }
}
