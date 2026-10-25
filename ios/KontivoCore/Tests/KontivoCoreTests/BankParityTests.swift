import XCTest
@testable import KontivoCore

/// Kontoauszug-Import: Swift gegen Erwartungswerte aus der Web-App (BankFixtures/expected.json, erzeugt mit
/// BankFixtures/make_expected.py über window.KontivoBank, heute = 2026-10-08; Stand Web v330). Geprüft werden gelesene Buchungen,
/// Vorschläge (Name, Betrag, Rhythmus, Sicherheit, Kategorie, Katalog, Preisänderung …), Abgleich mit erfassten
/// Verträgen und Vorschlag → Vertrag, für alle Musterdateien, Grenzfälle und Mehrfach-Dateien.
final class BankParityTests: XCTestCase {
    typealias J = [String: Any]

    static let today = Day(2026, 10, 8)

    static let fixtures: URL? = Bundle.module.url(forResource: "BankFixtures", withExtension: nil)

    static let expected: J = {
        guard let dir = fixtures, let d = try? Data(contentsOf: dir.appendingPathComponent("expected.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? J else { return [:] }
        return o
    }()

    func fileData(_ rel: String) throws -> Data {
        let dir = try XCTUnwrap(BankParityTests.fixtures, "BankFixtures fehlt im Test-Bundle")
        return try Data(contentsOf: dir.appendingPathComponent(rel))
    }

    func appData(_ backup: String, alias: J = [:]) throws -> AppData {
        var d = try WebImport.importBackup(Data(backup.utf8), today: BankParityTests.today).data
        for (k, v) in alias {
            if let o = v as? J { d.settings.bankAlias[k] = BankAlias(n: o["n"] as? String ?? "", c: o["c"] as? String ?? "") }
        }
        return d
    }

    // MARK: Vergleich

    /// Unterschiede sammeln, am Ende eine Meldung je Datei.
    final class Diff {
        var errs: [String] = []
        let ctx: String
        init(_ ctx: String) { self.ctx = ctx }

        func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
            if a != b { errs.append("\(what): Swift «\(a)» ≠ Web «\(b)»") }
        }

        func num(_ a: Double, _ b: Any?, _ what: String) {
            let v = (b as? Double) ?? .nan
            if !(Swift.abs(a - v) < 0.0005) { errs.append("\(what): Swift \(a) ≠ Web \(String(describing: b))") }
        }

        func report(file: StaticString = #filePath, line: UInt = #line) {
            if !errs.isEmpty {
                XCTFail("\(ctx): \(errs.count) Abweichungen\n  " + errs.prefix(25).joined(separator: "\n  "), file: file, line: line)
            }
        }
    }

    static func str(_ v: Any?) -> String { v as? String ?? "" }
    static func dayStr(_ d: Day?) -> String { d?.iso ?? "" }

    static func compareRead(_ f: BankFile, _ e: J, _ D: Diff, tx: Bool) {
        D.eq(f.bank, BankParityTests.str(e["bank"]), "bank")
        D.eq(f.format, BankParityTests.str(e["fmt"]), "fmt")
        D.eq(f.tx.count, (e["n"] as? Int) ?? -1, "Anzahl Buchungen")
        D.eq(BankParityTests.dayStr(f.from), BankParityTests.str(e["from"]), "from")
        D.eq(BankParityTests.dayStr(f.to), BankParityTests.str(e["to"]), "to")
        D.eq(f.owner, BankParityTests.str(e["owner"]), "Kontoinhaber")
        guard tx, let et = e["tx"] as? [[Any]] else { return }
        for (i, t) in f.tx.enumerated() where i < et.count {
            let x = et[i]
            let p = "tx[\(i)] "
            D.eq(t.date.iso, BankParityTests.str(x[0]), p + "Datum")
            D.num(t.amount, x[1], p + "Betrag")
            D.eq(t.currency, BankParityTests.str(x[2]), p + "Währung")
            D.eq(t.name, BankParityTests.str(x[3]), p + "Name")
            D.eq(t.text, BankParityTests.str(x[4]), p + "Text")
            D.eq(t.type, BankParityTests.str(x[5]), p + "Typ")
            D.eq(t.kind.rawValue, BankParityTests.str(x[6]), p + "Art")
            D.eq(t.cred, BankParityTests.str(x[7]), p + "Gläubiger-ID")
            D.eq(t.mref, BankParityTests.str(x[8]), p + "Mandat")
        }
    }

    /// Einnahmen (Web v177 `bankFindInc`)
    func compareIncome(_ r: BankIncomeResult, _ e: J?, _ data: AppData, _ D: Diff) {
        guard let e = e else { return }
        let es = e["sugg"] as? [J] ?? []
        D.eq(r.items.map { $0.key }, es.map { BankParityTests.str($0["key"]) }, "Einnahmen (Schlüssel, Reihenfolge)")
        for (i, s) in r.items.enumerated() where i < es.count {
            let x = es[i]
            let p = "Einnahme «\(s.key)» "
            if s.key != BankParityTests.str(x["key"]) { continue }
            D.eq(s.name, BankParityTests.str(x["name"]), p + "Name")
            D.eq(s.label, BankParityTests.str(x["label"]), p + "Bezeichnung")
            D.eq(s.category, BankParityTests.str(x["cat"]), p + "Art")
            D.eq(s.currency, BankParityTests.str(x["cur"]), p + "Währung")
            D.num(s.amount, x["amount"], p + "Betrag")
            D.eq(s.cycle, (x["cycle"] as? Int) ?? -1, p + "Rhythmus")
            D.eq(s.due.iso, BankParityTests.str(x["due"]), p + "nächster Eingang")
            D.eq(s.count, (x["n"] as? Int) ?? -1, p + "Anzahl")
            D.eq(s.first.iso, BankParityTests.str(x["first"]), p + "erste")
            D.eq(s.last.iso, BankParityTests.str(x["last"]), p + "letzte")
            D.eq(s.dates.map { $0.iso }, (x["dates"] as? [String]) ?? [], p + "Daten")
            let ea = (x["amounts"] as? [Double]) ?? []
            D.eq(s.amounts.count, ea.count, p + "Beträge (Anzahl)")
            for (j, v) in s.amounts.enumerated() where j < ea.count { D.num(v, ea[j], p + "Betrag[\(j)]") }
            BankParityTests.compareUI(
                BankImport.chips(dates: s.dates, amounts: s.amounts, count: s.count, last: s.last, lowConfidence: s.confidence == .low, change: nil,
                                 varies: s.varies, cycle: s.cycle, currency: s.currency, amount: s.amount, income: true),
                BankImport.payRows(dates: s.dates, amounts: s.amounts, cycle: s.cycle, income: true), s.currency, x, p, D)
            D.num(s.lo, x["lo"], p + "tiefster")
            D.num(s.hi, x["hi"], p + "höchster")
            D.eq(s.varies, (x["varies"] as? Bool) ?? false, p + "schwankt")
            D.eq(s.skipped, (x["skipped"] as? Int) ?? -1, p + "nicht mitgerechnet")
            D.eq(s.raw, BankParityTests.str(x["raw"]), p + "raw")
            D.eq(s.text, BankParityTests.str(x["text"]), p + "Text")
            D.eq(s.confidence.rawValue, BankParityTests.str(x["conf"]), p + "Sicherheit")
            if x["once"] != nil { D.eq(s.once, (x["once"] as? Bool) ?? false, p + "einmal") }
            // Lohnverlauf (Web v272 bankPriceHist(s, true))
            if x.keys.contains("hist") {
                let h = BankImport.incomeHistory(dates: s.dates, amounts: s.amounts)
                if let eh = x["hist"] as? J {
                    D.num(h?.base ?? .nan, eh["base"], p + "Verlauf Anfang")
                    let ep = (eh["prices"] as? [J]) ?? []
                    D.eq(h?.prices.map { $0.from.iso } ?? ["–"], ep.map { BankParityTests.str($0["from"]) }, p + "Verlauf ab")
                    for (j, pc) in (h?.prices ?? []).enumerated() where j < ep.count { D.num(pc.amount, ep[j]["amount"], p + "Verlauf[\(j)]") }
                } else {
                    D.eq(h == nil, true, p + "kein Verlauf")
                }
            }
        }
        let ek = e["known"] as? [J] ?? []
        D.eq(r.known.map { $0.suggestion.key }, ek.map { BankParityTests.str($0["key"]) }, "Einnahmen bereits erfasst (Schlüssel)")
    }

    /// Plaketten und Zahlungsliste der Vorschlagsliste (Web v330 bkChips, bkPayList)
    static func compareUI(_ chips: [BankChip], _ pay: [BankPayRow], _ cur: String, _ x: J, _ p: String, _ D: Diff) {
        guard let u = x["ui"] as? J else { return }
        func n(_ t: String) -> String { t.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2212}", with: "−") }
        let ec = (u["chips"] as? [[String]]) ?? []
        let kind: (BankChip.Kind) -> String = { k in k == .payments ? "payments" : k == .price ? "price" : "plain" }
        D.eq(chips.map { n($0.text) + "|" + kind($0.kind) }, ec.map { n($0[0]) + "|" + $0[1] }, p + "Plaketten")
        let ep = (u["pay"] as? [[String]]) ?? []
        let cls: (BankPayRow) -> String = { r in r.amount == nil ? "od" : r.changed ? "ch" : r.odd ? "od" : "" }
        D.eq(pay.map { n($0.label) + "|" + n($0.value(cur)) + "|" + cls($0) }, ep.map { n($0[0]) + "|" + n($0[1]) + "|" + $0[2] }, p + "Zahlungsliste")
    }

    func compareFind(_ r: BankFindResult, _ e: J, _ data: AppData, _ D: Diff, contracts: Bool) {
        let es = e["sugg"] as? [J] ?? []
        D.eq(r.all.map { $0.key }, es.map { BankParityTests.str($0["key"]) }, "Vorschläge (Schlüssel, Reihenfolge)")
        for (i, s) in r.all.enumerated() where i < es.count {
            let x = es[i]
            let p = "«\(s.key)» "
            if s.key != BankParityTests.str(x["key"]) { continue }
            D.eq(s.name, BankParityTests.str(x["name"]), p + "Name")
            D.eq(s.raw, BankParityTests.str(x["raw"]), p + "raw")
            D.eq(s.text, BankParityTests.str(x["text"]), p + "Text")
            D.eq(s.currency, BankParityTests.str(x["cur"]), p + "Währung")
            D.num(s.amount, x["amount"], p + "Betrag")
            D.eq(s.cycle, (x["cycle"] as? Int) ?? -1, p + "Rhythmus")
            D.eq(s.due.iso, BankParityTests.str(x["due"]), p + "nächste Zahlung")
            D.eq(s.first.iso, BankParityTests.str(x["first"]), p + "erste")
            D.eq(s.last.iso, BankParityTests.str(x["last"]), p + "letzte")
            D.eq(s.count, (x["n"] as? Int) ?? -1, p + "Anzahl")
            D.eq(s.dates.map { $0.iso }, (x["dates"] as? [String]) ?? [], p + "Daten")
            let ea = (x["amounts"] as? [Double]) ?? []
            D.eq(s.amounts.count, ea.count, p + "Beträge (Anzahl)")
            for (j, v) in s.amounts.enumerated() where j < ea.count { D.num(v, ea[j], p + "Betrag[\(j)]") }
            D.eq(s.confidence.rawValue, BankParityTests.str(x["conf"]), p + "Sicherheit")
            D.eq(s.varies, (x["varies"] as? Bool) ?? false, p + "schwankt")
            BankParityTests.compareUI(
                BankImport.chips(dates: s.dates, amounts: s.amounts, count: s.count, last: s.last, lowConfidence: s.confidence == .low, change: s.change,
                                 varies: s.varies, cycle: s.cycle, currency: s.currency, amount: s.amount, income: false),
                BankImport.payRows(dates: s.dates, amounts: s.amounts, cycle: s.cycle, income: false), s.currency, x, p, D)
            if let ch = x["change"] as? J {
                D.eq(s.change?.from.iso ?? "", BankParityTests.str(ch["from"]), p + "Preisänderung ab")
                D.num(s.change?.prev ?? .nan, ch["prev"], p + "Preis bisher")
                D.num(s.change?.amount ?? .nan, ch["amount"], p + "Preis neu")
            } else {
                D.eq(s.change == nil, true, p + "keine Preisänderung")
            }
            D.eq(s.catalogName ?? "", BankParityTests.str(x["tpl"]), p + "Katalog")
            D.eq(s.category, BankParityTests.str(x["cat"]), p + "Kategorie")
            D.eq(s.kind.rawValue, BankParityTests.str(x["kind"]), p + "Art")
            D.eq(s.cred, BankParityTests.str(x["cred"]), p + "Gläubiger-ID")
            D.eq(s.mref, BankParityTests.str(x["mref"]), p + "Mandat")
            D.eq(s.ignored, (x["ignored"] as? Bool) ?? false, p + "ausgeblendet")
            let pm = r.prices.first { $0.suggestion.id == s.id }
            if let m = x["match"] as? J {
                D.eq(BankParityTests.str(m["kind"]), "price", p + "Treffer-Art (Web)")
                D.eq(pm.flatMap { data.contract($0.contractID) }.map { data.partnerName(of: $0) } ?? "", BankParityTests.str(m["partner"]), p + "Preisänderung Vertrag")
                D.num(pm?.amount ?? .nan, m["amount"], p + "Preisänderung Betrag")
                D.num(pm?.old ?? .nan, m["old"], p + "Preisänderung alt")
                D.eq(pm?.from.iso ?? "", BankParityTests.str(m["from"]), p + "Preisänderung ab")
            } else {
                D.eq(pm == nil, true, p + "kein Vertragstreffer")
            }
        }
        // gekündigt, aber weiter abgebucht (Web v272 `after`)
        if let ea = e["after"] as? [J] {
            D.eq(r.after.map { data.contract($0.contractID).map { data.partnerName(of: $0) } ?? "?" }, ea.map { BankParityTests.str($0["partner"]) }, "weiter abgebucht (Vertrag)")
            for (i, a) in r.after.enumerated() where i < ea.count {
                D.eq(a.count, (ea[i]["n"] as? Int) ?? -1, "weiter abgebucht[\(i)] Anzahl")
                D.eq(a.last.iso, BankParityTests.str(ea[i]["last"]), "weiter abgebucht[\(i)] letzte")
                D.num(a.amount, ea[i]["amount"], "weiter abgebucht[\(i)] Betrag")
                D.eq(a.currency, BankParityTests.str(ea[i]["cur"]), "weiter abgebucht[\(i)] Währung")
            }
        }
        let ek = e["known"] as? [J] ?? []
        D.eq(r.known.map { $0.suggestion.key }, ek.map { BankParityTests.str($0["key"]) }, "bereits erfasst (Schlüssel)")
        for (i, k) in r.known.enumerated() where i < ek.count {
            let x = ek[i]
            D.eq(k.suggestion.name, BankParityTests.str(x["name"]), "known[\(i)] Name")
            D.eq(data.contract(k.contractID).map { data.partnerName(of: $0) } ?? "", BankParityTests.str(x["partner"]), "known[\(i)] Vertrag")
            D.eq(k.loose, (x["loose"] as? Bool) ?? false, "known[\(i)] loose")
            D.num(k.suggestion.amount, x["amount"], "known[\(i)] Betrag")
        }
        guard contracts, let ec = e["contracts"] as? [J] else { return }
        D.eq(r.all.count, ec.count, "Verträge (Anzahl)")
        for (i, s) in r.all.enumerated() where i < ec.count {
            let x = ec[i]
            let p = "Vertrag «\(s.name)» "
            var d2 = data
            let id = BankImport.add(s, persons: ["Sinan"], to: &d2, today: BankParityTests.today)
            guard let c = d2.contract(id) else {
                D.errs.append(p + "nicht angelegt")
                continue
            }
            D.eq(d2.partnerName(of: c), BankParityTests.str(x["partner"]), p + "Vertragspartner")
            D.eq(c.label, BankParityTests.str(x["label"]), p + "Bezeichnung")
            D.eq(d2.category(c.categoryID)?.name ?? "", BankParityTests.str(x["cat"]), p + "Kategorie")
            D.num(c.amount, x["amount"], p + "Betrag")
            D.eq(c.currency.rawValue, BankParityTests.str(x["cur"]), p + "Währung")
            D.eq(c.cycle, (x["cycle"] as? Int) ?? -1, p + "Rhythmus")
            D.eq(c.due?.iso ?? "", BankParityTests.str(x["due"]), p + "nächste Zahlung")
            D.eq(c.notice, (x["notice"] as? Int) ?? -1, p + "Frist")
            D.eq(c.noticeUnit.rawValue, BankParityTests.str(x["noticeU"]), p + "Frist-Einheit")
            D.eq(c.cancelTerm.rawValue, BankParityTests.str(x["cancTerm"]), p + "kündbar per")
            D.eq(c.mandatory, (x["mand"] as? Bool) ?? false, p + "Pflicht")
            D.eq(c.cancelChannel?.webText ?? "", BankParityTests.str(x["cancF"]), p + "Kündigungsweg")
            D.eq(c.cancelURL, BankParityTests.str(x["cancUrl"]), p + "Kündigungslink")
            D.eq(c.tel, BankParityTests.str(x["tel"]), p + "Telefon")
            D.eq(c.mail, BankParityTests.str(x["mail"]), p + "E-Mail")
            D.eq(c.noCancel, (x["noCancel"] as? Bool) ?? false, p + "nicht kündbar")
            D.eq(d2.holderNames(of: c), (x["holders"] as? [String]) ?? [], p + "Personen")
            D.eq(d2.partner(c.partnerID)?.web ?? "", BankParityTests.str(x["web"]), p + "Website")
            D.eq(c.payMethod, BankParityTests.str(x["payM"]), p + "Zahlungsart")
            D.eq(c.customerNo, BankParityTests.str(x["custNo"]), p + "Kundennummer")
            D.eq(c.contractNo, BankParityTests.str(x["contrNo"]), p + "Vertragsnummer")
            D.eq(BankImport.label(s), BankParityTests.str(x["bkLabel"]), p + "Bezeichnung im Import (bankLabel)")
            let ep = (x["prices"] as? [J]) ?? []
            D.eq(c.prices.map { $0.from.iso }, ep.map { BankParityTests.str($0["from"]) }, p + "Preisverlauf ab")
            for (j, pc) in c.prices.enumerated() where j < ep.count { D.num(pc.amount, ep[j]["amount"], p + "Preisverlauf[\(j)]") }
        }
    }

    // MARK: Tests

    func testFixturesPresent() throws {
        XCTAssertNotNil(BankParityTests.fixtures, "BankFixtures fehlt im Test-Bundle")
        XCTAssertEqual(BankParityTests.str(BankParityTests.expected["today"]), "2026-10-08")
        XCTAssertGreaterThanOrEqual((BankParityTests.expected["files"] as? J)?.count ?? 0, 87)
    }

    /// Alle Muster- und nachgebauten Bankdateien: lesen, Vorschläge, Vorschlag → Vertrag (ohne erfasste Verträge).
    func testFilesEmptyState() throws {
        let files = try XCTUnwrap(BankParityTests.expected["files"] as? J)
        let data = try appData(BankParityTests.str(BankParityTests.expected["emptyBackup"]))
        for name in files.keys.sorted() {
            let D = Diff(name)
            guard let e = files[name] as? J else {
                XCTAssertThrowsError(try BankImport.read(fileData(name)), name)
                continue
            }
            do {
                let f = try BankImport.read(fileData(name))
                BankParityTests.compareRead(f, e, D, tx: true)
                compareFind(BankImport.find(f, data: data, today: BankParityTests.today), e["find"] as? J ?? [:], data, D, contracts: true)
                compareIncome(BankImport.findIncome(f, data: data, today: BankParityTests.today), (e["find"] as? J)?["inc"] as? J, data, D)
            } catch {
                D.errs.append("nicht gelesen: \(error)")
            }
            D.report()
        }
    }

    /// Gleiche Dateien gegen erfasste Verträge (CSS 389.60 → Preisänderung, Netflix 18.90 → bereits erfasst), wie main/tests/bank/check.py.
    func testFilesWithContracts() throws {
        let files = try XCTUnwrap(BankParityTests.expected["check"] as? J)
        let data = try appData(BankParityTests.str(BankParityTests.expected["checkBackup"]))
        XCTAssertEqual(data.contracts.count, 2)
        for name in files.keys.sorted() {
            guard let e = files[name] as? J else { continue }
            let D = Diff(name + " (mit Verträgen)")
            do {
                let f = try BankImport.read(fileData(name))
                compareFind(BankImport.find(f, data: data, today: BankParityTests.today), e["find"] as? J ?? [:], data, D, contracts: false)
                compareIncome(BankImport.findIncome(f, data: data, today: BankParityTests.today), (e["find"] as? J)?["inc"] as? J, data, D)
            } catch {
                D.errs.append("nicht gelesen: \(error)")
            }
            D.report()
        }
        // wie check.py: CSS → Preisänderung 389.60 → 412.30, Netflix → bereits erfasst
        let r = BankImport.find(try BankImport.read(fileData("samples/ch_postfinance.csv")), data: data, today: BankParityTests.today)
        let css = r.prices.first { $0.suggestion.name == "CSS" }
        XCTAssertEqual(css?.old ?? 0, 389.60, accuracy: 0.001)
        XCTAssertEqual(css?.amount ?? 0, 412.30, accuracy: 0.001)
        XCTAssertTrue(r.known.contains { data.contract($0.contractID).map { data.partnerName(of: $0) } == "Netflix" })
    }

    /// Grenzfälle aus main/tests/bank/edge_cases.json (mit Verträgen und gelernten Korrekturen) und zusätzliche Regeln.
    func testEdgeCases() throws {
        let exp = try XCTUnwrap(BankParityTests.expected["edge"] as? J)
        let inp = try XCTUnwrap(BankParityTests.expected["edgeInput"] as? J)
        XCTAssertGreaterThanOrEqual(exp.count, 27)
        for name in exp.keys.sorted() {
            let D = Diff("Grenzfall " + name)
            let i = try XCTUnwrap(inp[name] as? J)
            let data = try appData(BankParityTests.str(i["backup"]), alias: i["alias"] as? J ?? [:])
            let txt = BankParityTests.str(i["txt"])
            guard let e = exp[name] as? J else {
                XCTAssertThrowsError(try BankImport.read(Data(txt.utf8)), name)
                continue
            }
            do {
                let f = try BankImport.read(Data(txt.utf8))
                BankParityTests.compareRead(f, e, D, tx: false)
                compareFind(BankImport.find(f, data: data, today: BankParityTests.today), e["find"] as? J ?? [:], data, D, contracts: true)
                compareIncome(BankImport.findIncome(f, data: data, today: BankParityTests.today), (e["find"] as? J)?["inc"] as? J, data, D)
            } catch {
                D.errs.append("nicht gelesen: \(error)")
            }
            D.report()
        }
    }

    /// Mehrere Dateien: gleiche Datei doppelt zählt einmal, Konto + Kreditkarte ergänzen sich (wie main/tests/bank/multi.py).
    func testMultipleFiles() throws {
        let list = try XCTUnwrap(BankParityTests.expected["multi"] as? [J])
        let data = try appData(BankParityTests.str(BankParityTests.expected["emptyBackup"]))
        for m in list {
            let names = (m["files"] as? [String]) ?? []
            let D = Diff("Mehrere Dateien " + names.joined(separator: " + "))
            let e = try XCTUnwrap(m["result"] as? J)
            let files = try names.map { try BankImport.read(fileData($0)) }
            let f = BankImport.merge(files)
            BankParityTests.compareRead(f, e, D, tx: false)
            compareFind(BankImport.find(f, data: data, today: BankParityTests.today), e["find"] as? J ?? [:], data, D, contracts: false)
            compareIncome(BankImport.findIncome(f, data: data, today: BankParityTests.today), (e["find"] as? J)?["inc"] as? J, data, D)
            D.report()
        }
        // gleiche Datei doppelt = einmal
        let one = try BankImport.read(fileData("samples/ch_postfinance.csv"))
        XCTAssertEqual(BankImport.merge([one, one]).tx.count, one.tx.count)
    }

    /// Alle regulären Ausdrücke sind gültig (ICU).
    func testPatternsCompile() throws {
        // alle Ausdrücke einmal benutzen (statische Konstanten werden erst beim ersten Zugriff erzeugt)
        let files = try XCTUnwrap(BankParityTests.expected["files"] as? J)
        let data = try appData(BankParityTests.str(BankParityTests.expected["emptyBackup"]))
        for name in files.keys.sorted() {
            if let f = try? BankImport.read(fileData(name)) { _ = BankImport.find(f, data: data, today: BankParityTests.today) }
        }
        _ = BankImport.readStatementText("01.01.2026 Test 1.00", defaultCurrency: "CHF")
        _ = BankName.pretty("TEST AG")
        _ = BankName.desc("SQ *TEST 0800 123 456")
        XCTAssertEqual(BRX.failed, [])
    }
}
