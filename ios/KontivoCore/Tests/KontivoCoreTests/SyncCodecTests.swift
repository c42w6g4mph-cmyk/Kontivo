import XCTest
@testable import KontivoCore

/// iCloud-Sync: Schlüssel, Kodierung Entität ↔ Nutzlast, abgeglichene Einstellungen, Texte.
final class SyncCodecTests: XCTestCase {

    /// Beispieldaten mit allen Entitätsarten und möglichst vielen gefüllten Feldern
    static func sample() -> AppData {
        var d = AppData.initial(homeCurrency: .CHF)
        let ich = d.persons[0].id
        d.persons[0].sender = SenderAddress(first: "Sinan", last: "Muster", street: "Hauptstrasse 1", zip: "8280", city: "Kreuzlingen", country: "Schweiz")
        d.persons[0].signatureJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        d.persons[0].avatarID = "0123456789abcdef0123456789abcdef"
        let lara = Person(name: "Lara", sameAddressAs: ich)
        d.persons.append(lara)
        let partner = Partner(name: "Swisscom", web: "swisscom.ch", logoID: "abcdefabcdefabcdefabcdefabcdef01", logoBg: "#FFFFFF",
                              address: PostalAddress(company: "Swisscom (Schweiz) AG", street: "Alte Tiefenaustrasse 6", zip: "3048", city: "Worblaufen"))
        d.partners.append(partner)
        let tel = d.categories.first { $0.kind == .telecom }!.id
        d.categories.append(Category(name: "Haustiere", colorHex: "#2E6A4E", icon: "tag"))
        var c = Contract(label: "Mobile", partnerID: partner.id, categoryID: tel, amount: 49.9)
        c.cycle = 1
        c.due = Day(2026, 10, 15)
        c.start = Day(2024, 1, 1)
        c.end = Day(2027, 1, 1)
        c.notice = 2
        c.renewMonths = 12
        c.cancelTerm = .contractYear
        c.isRent = false
        c.customerNo = "K-1"
        c.contractNo = "V-2"
        c.holderIDs = [ich, lara.id]
        c.payMethod = "LSV"
        c.payAccount = "CH00 0000"
        c.cancelChannel = .letter
        c.cancelURL = "https://www.swisscom.ch"
        c.trial = Day(2026, 11, 1)
        c.tel = "0800 800 800"
        c.mail = "info@swisscom.ch"
        c.note = "Notiz mit «Anführungszeichen» und Umlauten äöü"
        c.colorHex = "#123456"
        c.prices = [PriceChange(from: Day(2026, 1, 1), amount: 54.9)]
        c.documents = [Attachment(id: "fedcbafedcbafedcbafedcbafedcba98", name: "Vertrag.pdf", type: "application/pdf")]
        c.extras = [ExtraPayment(date: Day(2026, 3, 1), amount: -10, note: "Gutschrift")]
        c.cancelPer = Day(2027, 1, 1)
        c.cancelledOn = Day(2026, 9, 1)
        c.pauses = [Pause(from: Day(2026, 5, 1), until: Day(2026, 6, 1)), Pause(from: Day(2026, 12, 1))]
        // Zeitpunkt mit Bruchteil einer Millisekunde (wie `Date()`)
        c.createdAt = Date(timeIntervalSince1970: 1_760_000_000.123_456)
        c.split = [SplitShare(personID: ich, percent: 60), SplitShare(personID: lara.id, percent: 40)]
        c.review = ContractReview(verdict: .keep, at: Day(2026, 9, 30))
        d.contracts.append(c)
        var inc = Income(name: "Arbeitgeber AG", label: "Lohn", kind: .lohn, amount: 6500, currency: .CHF, cycle: 1, due: Day(2026, 10, 25),
                         holderID: ich, prices: [PriceChange(from: Day(2026, 1, 1), amount: 6600)], note: "netto")
        inc.createdAt = Date(timeIntervalSince1970: 1_760_000_100.987_654)
        d.incomes.append(inc)
        d.settings.sort = .cost
        d.settings.qualityIgnored = ["c:x:holder"]
        d.settings.logoSkip = ["swisscom"]
        d.settings.bankIgn = ["netflix"]
        d.settings.bankAlias = ["spotify": BankAlias(n: "Spotify", c: "Abos & Medien")]
        d.settings.lastReview = Day(2026, 7, 1)
        d.settings.reviewSnooze = Day(2026, 10, 10)
        d.settings.lastHolderIDs = [ich]
        d.settings.theme = .dark
        d.settings.rates = ["EUR": 0.94]
        d.settings.rateDate = Day(2026, 10, 1)
        d.settings.onboarded = 3
        return d
    }

    // MARK: Schlüssel

    func testKeyRecordNames() {
        let u = UUID()
        let k = SyncKey(.contract, u)
        XCTAssertEqual(k.recordName, "contract." + u.uuidString)
        XCTAssertEqual(SyncKey(recordName: k.recordName), k)
        // Kleinschreibung wird vereinheitlicht
        XCTAssertEqual(SyncKey(recordName: "contract." + u.uuidString.lowercased()), k)
        XCTAssertEqual(SyncKey(recordName: "settings.main"), .settings)
        XCTAssertNil(SyncKey(recordName: "settings.other"))
        XCTAssertNil(SyncKey(recordName: "contract.123"))
        XCTAssertNil(SyncKey(recordName: "unknown." + u.uuidString))
        XCTAssertNil(SyncKey(recordName: "contract"))
        for kind in SyncKind.allCases where kind != .settings && kind != .file {
            let key = SyncKey(kind, u)
            XCTAssertEqual(SyncKey(recordName: key.recordName), key, kind.rawValue)
            XCTAssertEqual(key.uuid, u)
        }
        // Dateien: nur 32 Hex-Zeichen (kein fremder Pfad)
        XCTAssertNotNil(SyncKey.file("0123456789abcdef0123456789ABCDEF"))
        XCTAssertNil(SyncKey.file("../../Library/Preferences/x.plist"))
        XCTAssertNil(SyncKey.file("0123456789abcdef0123456789abcdeg"))
        XCTAssertNil(SyncKey(recordName: "file.123"))
        let f = SyncKey.file("0123456789abcdef0123456789abcdef")!
        XCTAssertEqual(SyncKey(recordName: f.recordName), f)
        XCTAssertNil(f.uuid)
        // Sortierung: Einstellungen, Stammdaten, Verträge, Einnahmen, Dateien
        let sorted = [f, SyncKey(.variable, u), SyncKey(.income, u), SyncKey(.contract, u), SyncKey(.person, u), .settings].sorted()
        XCTAssertEqual(sorted.map { $0.kind }, [.settings, .person, .contract, .income, .variable, .file])
        XCTAssertEqual(SyncKind.variable.recordType, "VariableCost")
        XCTAssertEqual(SyncKind.contract.recordType, "Contract")
    }

    // MARK: Kodierung

    func testRoundTripAllEntities() throws {
        let d = Self.sample()
        let keys = SyncCodec.keys(of: d)
        XCTAssertEqual(keys.count, 1 + 2 + 13 + 1 + 1 + 1)
        for key in keys {
            let payload = try XCTUnwrap(SyncCodec.payload(key, in: d, settingsBase: nil), key.recordName)
            let rec = SyncRecord(key: key, payload: payload, modifiedAt: Date())
            let e = try XCTUnwrap(SyncCodec.decodeEntity(rec), key.recordName)
            // Erneut kodiert: gleiche Bytes (stabile Prüfsumme über Rundläufe)
            let again = try XCTUnwrap(SyncCodec.payload(of: e))
            XCTAssertEqual(again, payload, key.recordName)
            switch e {
            case .person(let p): XCTAssertEqual(p, d.person(p.id))
            case .category(let c): XCTAssertEqual(c, d.category(c.id))
            case .partner(let p): XCTAssertEqual(p, d.partner(p.id))
            case .contract(let c):
                var expected = try XCTUnwrap(d.contract(c.id))
                XCTAssertEqual(c.createdAt.timeIntervalSince1970, expected.createdAt.timeIntervalSince1970, accuracy: 0.001)
                expected.createdAt = c.createdAt
                XCTAssertEqual(c, expected)
            case .income(let i):
                var expected = try XCTUnwrap(d.income(i.id))
                XCTAssertEqual(i.createdAt.timeIntervalSince1970, expected.createdAt.timeIntervalSince1970, accuracy: 0.001)
                expected.createdAt = i.createdAt
                XCTAssertEqual(i, expected)
            case .variable(let v):
                XCTAssertEqual(v.id, d.variableCost(v.id)?.id)
            case .settings(let s):
                XCTAssertEqual(s, SyncSettings(d))
            }
        }
    }

    func testDigestStableAcrossDataJSONRoundTrip() throws {
        // data.json (KontivoJSON) und zurück: Prüfsummen bleiben gleich, sonst gäbe es nach jedem Start Scheinänderungen
        let d = Self.sample()
        let reloaded = try AppData.decode(d.encoded())
        for key in SyncCodec.keys(of: d) {
            let a = try XCTUnwrap(SyncCodec.payload(key, in: d, settingsBase: nil))
            let b = try XCTUnwrap(SyncCodec.payload(key, in: reloaded, settingsBase: nil))
            XCTAssertEqual(SyncCodec.digest(a), SyncCodec.digest(b), key.recordName)
        }
        XCTAssertNotEqual(SyncCodec.digest(Data("a".utf8)), SyncCodec.digest(Data("b".utf8)))
        XCTAssertEqual(SyncCodec.digest(Data()), "cbf29ce484222325")
    }

    func testDecodeRejectsWrongIDAndGarbage() throws {
        let d = Self.sample()
        let c = d.contracts[0]
        let payload = try XCTUnwrap(SyncCodec.payload(SyncKey(.contract, c.id), in: d, settingsBase: nil))
        // Nutzlast passt nicht zum Schlüssel
        XCTAssertNil(SyncCodec.decodeEntity(SyncRecord(key: SyncKey(.contract, UUID()), payload: payload, modifiedAt: Date())))
        XCTAssertNil(SyncCodec.decodeEntity(SyncRecord(key: SyncKey(.contract, c.id), payload: Data("kaputt".utf8), modifiedAt: Date())))
        XCTAssertNil(SyncCodec.decodeEntity(SyncRecord(key: SyncKey.file("0123456789abcdef0123456789abcdef")!, payload: Data(), modifiedAt: Date())))
        // Unbekannte Felder einer späteren Version stören nicht
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        obj["neuesFeld"] = "x"
        let newer = try JSONSerialization.data(withJSONObject: obj)
        guard case .contract(let back)? = SyncCodec.decodeEntity(SyncRecord(key: SyncKey(.contract, c.id), payload: newer, modifiedAt: Date())) else {
            return XCTFail("Vertrag nicht gelesen")
        }
        XCTAssertEqual(back.label, c.label)
    }

    // MARK: Einstellungen

    func testSettingsOnlySyncedFields() {
        let a = Self.sample()
        var b = a
        b.settings.theme = .light
        b.settings.rates = [:]
        b.settings.rateDate = nil
        b.settings.rateSource = "ECB"
        b.settings.onboarded = 0
        XCTAssertEqual(SyncSettings(a), SyncSettings(b), "Darstellung, Kurse, Einführung werden nicht abgeglichen")
        b.settings.homeCurrency = .EUR
        XCTAssertNotEqual(SyncSettings(a), SyncSettings(b))

        var s = Settings(homeCurrency: .EUR, theme: .dark, onboarded: 1)
        s.rates = ["EUR": 0.9]
        SyncSettings(a).apply(to: &s)
        XCTAssertEqual(s.homeCurrency, .CHF)
        XCTAssertEqual(s.sort, .cost)
        XCTAssertEqual(s.qualityIgnored, ["c:x:holder"])
        XCTAssertEqual(s.logoSkip, ["swisscom"])
        XCTAssertEqual(s.bankIgn, ["netflix"])
        XCTAssertEqual(s.bankAlias["spotify"], BankAlias(n: "Spotify", c: "Abos & Medien"))
        XCTAssertEqual(s.lastReview, Day(2026, 7, 1))
        XCTAssertEqual(s.reviewSnooze, Day(2026, 10, 10))
        XCTAssertEqual(s.lastHolderIDs, a.settings.lastHolderIDs)
        XCTAssertEqual(s.theme, .dark, "Darstellung bleibt")
        XCTAssertEqual(s.onboarded, 1, "Einführung bleibt")
        XCTAssertEqual(s.rates, ["EUR": 0.9], "Kurse bleiben")
    }

    func testSettingsOrderKeepsKnownOrderWhileItemsMissing() {
        let ids = (0..<4).map { _ in UUID() }
        // Lokal fehlt ids[2] noch (nicht eingetroffen): bekannte Reihenfolge bleibt
        XCTAssertEqual(SyncSettings.order([ids[0], ids[1], ids[3]], base: ids), ids)
        // Lokal umsortiert: lokale Reihenfolge
        XCTAssertEqual(SyncSettings.order([ids[1], ids[0], ids[3]], base: ids), [ids[1], ids[0], ids[3]])
        // Lokal neu (nicht in der bekannten): lokale Reihenfolge
        let n = UUID()
        XCTAssertEqual(SyncSettings.order([ids[0], n], base: ids), [ids[0], n])
        XCTAssertEqual(SyncSettings.order([ids[0]], base: nil), [ids[0]])
    }

    func testSettingsDecodingLenient() throws {
        let s = try XCTUnwrap(SyncCodec.decode(SyncSettings.self, from: Data("{\"homeCurrency\":\"EUR\",\"zukunft\":1}".utf8)))
        XCTAssertEqual(s.homeCurrency, .EUR)
        XCTAssertEqual(s.sort, .category)
        XCTAssertTrue(s.categoryOrder.isEmpty)
    }

    // MARK: Zustand

    func testLedgerRoundTripPlistAndLenient() throws {
        var core = SyncCore()
        let d = Self.sample()
        core.captureLocalChanges(d, previous: nil, now: Date(timeIntervalSince1970: 1_760_000_000))
        core.ledger.systemFields["contract.x"] = Data([1, 2, 3])
        core.ledger.serverFiles = ["0123456789abcdef0123456789abcdef"]
        core.ledger.engineState = Data("{}".utf8)
        core.ledger.accountName = "_abc"
        core.ledger.aliases = ["category.A": "category.B"]
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        let raw = try enc.encode(core.ledger)
        let back = try PropertyListDecoder().decode(SyncLedger.self, from: raw)
        XCTAssertEqual(back, core.ledger)
        // Fehlende Felder → Standard
        let empty = try JSONDecoder().decode(SyncLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, SyncLedger())
    }

    // MARK: Texte

    func testStatusTexts() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 15, minute: 0))!
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 14, minute: 32))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9, minute: 5))!
        let older = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9, minute: 5))!
        XCTAssertEqual(SyncTexts.status(.upToDate, lastSync: today, now: now, calendar: cal), "Auf allen deinen Geräten aktuell · zuletzt 14:32")
        XCTAssertEqual(SyncTexts.status(.upToDate, lastSync: yesterday, now: now, calendar: cal), "Auf allen deinen Geräten aktuell · zuletzt gestern 09:05")
        XCTAssertEqual(SyncTexts.status(.upToDate, lastSync: older, now: now, calendar: cal), "Auf allen deinen Geräten aktuell · zuletzt 3.10.2026")
        XCTAssertEqual(SyncTexts.status(.upToDate, lastSync: nil), "Auf allen deinen Geräten aktuell")
        XCTAssertEqual(SyncTexts.status(.syncing, lastSync: nil), "Wird abgeglichen …")
        XCTAssertEqual(SyncTexts.status(.noAccount, lastSync: nil), "Nicht bei iCloud angemeldet")
        XCTAssertEqual(SyncTexts.status(.quotaFull, lastSync: nil), "iCloud-Speicher voll")
        XCTAssertEqual(SyncTexts.status(.offline, lastSync: nil), "Offline – wird später abgeglichen")
        XCTAssertEqual(SyncTexts.status(.unavailableBuild, lastSync: nil), "iCloud-Sync: in diesem Build aus (Apple Developer Program nötig)")
        // Schweizer Rechtschreibung, «Vertragspartner» nie «Partner»
        let all = [SyncTexts.explanation, SyncTexts.offMessage, SyncTexts.deleteMessage, SyncTexts.accountMessage, SyncTexts.wipeNote,
                   SyncTexts.replaceNote, SyncTexts.adoptedToast, SyncTexts.deletedElsewhereToast]
        for t in all {
            XCTAssertFalse(t.contains("ß"), t)
            XCTAssertFalse(t.contains("Partner"), t)
        }
        XCTAssertTrue(SyncStatus.upToDate.isRunning)
        XCTAssertFalse(SyncStatus.off.isRunning)
        XCTAssertFalse(SyncStatus.noAccount.isRunning)
    }
}
