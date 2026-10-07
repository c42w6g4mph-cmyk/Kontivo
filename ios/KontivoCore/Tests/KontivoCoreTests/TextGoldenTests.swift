import XCTest
@testable import KontivoCore

/// Vergleicht Texte und Regeln mit golden_texts.json (aus der Web-App erzeugt mit tests/make_golden_texts.py):
/// Dringlichkeit, Tab «Fristen», CSV-Export (je Stichtag aus cases.json) sowie Datenqualität und Kündigungsschreiben
/// für das Test-Backup cases_texts.json.
final class TextGoldenTests: XCTestCase {
    func parse(_ name: String) throws -> JSObject {
        let v = try JSONParser.parse(GoldenTests.resource(name))
        guard case .object(let o) = v else { throw NSError(domain: "TextGoldenTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(name) unlesbar"]) }
        return o
    }

    func str(_ v: JSValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }

    func int(_ v: JSValue?) -> Int? {
        if case .number(let n)? = v { return Int(n) }
        return nil
    }

    func bool(_ v: JSValue?) -> Bool {
        if case .bool(let b)? = v { return b }
        return false
    }

    /// Fälle aus cases.json als Web-Backup (wie GoldenTests).
    func importCases(_ so: JSObject, today: Day) -> WebImportResult {
        var contracts = JSObject()
        for cs in JS.arr(so["cases"]).compactMap({ JS.obj($0) }) {
            var c = JSObject()
            c["cat"] = .string("Sonstiges")
            c["status"] = .string("active")
            if let co = JS.obj(cs["c"]) {
                for k in co.orderedKeys { c[k] = co[k] }
            }
            contracts[JS.str(cs["id"])] = .object(c)
        }
        var backup = JSObject()
        backup["app"] = .string("vertraege")
        backup["settings"] = so["settings"]
        backup["contracts"] = .object(contracts)
        backup["incomes"] = .object(JSObject())
        return WebImport.importObject(backup, today: today, now: Date())
    }

    func testCasesAgainstWeb() throws {
        let so = try parse("cases")
        let go = try parse("golden_texts")
        guard let results = JS.obj(go["results"]) else { return XCTFail("results fehlt") }
        var checked = 0
        for t in JS.arr(so["todays"]).map({ JS.str($0) }) {
            guard let today = Day(iso: t), let exp = JS.obj(results[t]) else {
                XCTFail("Stichtag \(t)")
                continue
            }
            let r = importCases(so, today: today)
            let calc = Calc(data: r.data, today: today)
            var webID: [UUID: String] = [:]
            for (k, v) in r.contractIDs { webID[v] = k }

            // Dringlichkeit
            let urg = JS.obj(exp["urgency"]) ?? JSObject()
            for id in urg.orderedKeys {
                guard let uid = r.contractIDs[id], let c = r.data.contract(uid), let e = JS.obj(urg[id]) else {
                    XCTFail("\(t) \(id) fehlt")
                    continue
                }
                let u = calc.urgency(c)
                XCTAssertEqual(u.level.rawValue, JS.str(e["lvl"]), "\(t) \(id) urgency.lvl")
                XCTAssertEqual(u.days, int(e["days"]), "\(t) \(id) urgency.days")
                XCTAssertEqual(u.date?.iso, str(e["date"]), "\(t) \(id) urgency.date")
                checked += 1
            }

            // Tab «Fristen» (Variante 1): Status, Liste nach Datum, Karte «Flexibel»
            let dl = JS.obj(exp["deadlines"]) ?? JSObject()
            let ov = calc.deadlineOverview()
            if let ws = JS.obj(dl["status"]) {
                XCTAssertEqual(ov.status?.kind.rawValue, JS.str(ws["kind"]), "\(t) Status Art")
                XCTAssertEqual(ov.status?.count, int(ws["count"]), "\(t) Status Zahl")
                XCTAssertEqual(ov.status?.title, JS.str(ws["title"]), "\(t) Status Titel")
                XCTAssertEqual(ov.status?.subtitle, JS.str(ws["sub"]), "\(t) Status Untertitel")
            } else {
                XCTAssertNil(ov.status, "\(t) kein Status")
            }
            let wi = JS.arr(dl["items"]).compactMap { JS.obj($0) }
            XCTAssertEqual(ov.items.map { webID[$0.contractID] ?? "?" }, wi.map { JS.str($0["id"]) }, "\(t) Liste (Reihenfolge)")
            for (x, e) in zip(ov.items, wi) {
                let m = "\(t) Liste \(JS.str(e["id"]))"
                XCTAssertEqual(x.sub, JS.str(e["sub"]), m + " Zeile")
                XCTAssertEqual(x.chip, JS.str(e["chip"]), m + " Chip")
                XCTAssertEqual(x.chipLevel.rawValue, JS.str(e["lvl"]), m + " Chip-Farbe")
                XCTAssertEqual(x.showActions, bool(e["acts"]), m + " Knöpfe")
                XCTAssertEqual(x.trial, bool(e["trial"]), m + " Probeabo")
                if x.showActions {
                    XCTAssertEqual(x.keepTitle, JS.str(e["keep"]), m + " Behalten")
                    XCTAssertEqual(x.cancelTitle, JS.str(e["kill"]), m + " Kündigen")
                }
            }
            if let wf = JS.obj(dl["flex"]) {
                XCTAssertEqual(ov.flexCountText, JS.str(wf["count"]), "\(t) Flexibel Anzahl")
                XCTAssertEqual(Calc.DeadlineOverview.flexSubtitle, JS.str(wf["sub"]), "\(t) Flexibel Untertitel")
                XCTAssertEqual(Calc.DeadlineOverview.flexNote, JS.str(wf["note"]), "\(t) Flexibel Hinweis")
                XCTAssertEqual(ov.flexStack.count, int(wf["stack"]), "\(t) Flexibel Logostapel")
                let rows = JS.arr(wf["rows"]).compactMap { JS.obj($0) }
                XCTAssertEqual(ov.flexible.map { webID[$0.contractID] ?? "?" }, rows.map { JS.str($0["id"]) }, "\(t) Flexibel (Reihenfolge)")
                for (x, e) in zip(ov.flexible, rows) {
                    XCTAssertEqual(x.sub, JS.str(e["sub"]), "\(t) Flexibel \(JS.str(e["id"])) Zeile")
                    XCTAssertEqual(x.chip, JS.str(e["chip"]), "\(t) Flexibel \(JS.str(e["id"])) Chip")
                }
            } else {
                XCTAssertTrue(ov.flexible.isEmpty, "\(t) kein Flexibel")
            }
            var folds: [(key: String, title: String, rows: [Calc.FoldRow])] = []
            if !ov.withoutNotice.isEmpty {
                folds.append(("none", Calc.DeadlineOverview.withoutNoticeTitle + " (\(ov.withoutNotice.count))" + Calc.DeadlineOverview.withoutNoticeExtra, ov.withoutNotice))
            }
            if !ov.unwatched.isEmpty { folds.append(("unw", Calc.DeadlineOverview.unwatchedTitle + " (\(ov.unwatched.count))", ov.unwatched)) }
            let wf = JS.arr(dl["folds"]).compactMap { JS.obj($0) }
            XCTAssertEqual(folds.map { $0.key }, wf.map { JS.str($0["key"]) }, "\(t) Klappgruppen")
            for (f, e) in zip(folds, wf) {
                XCTAssertEqual(f.title, JS.str(e["title"]), "\(t) Klappgruppe \(f.key)")
                let rows = JS.arr(e["rows"]).compactMap { JS.obj($0) }
                XCTAssertEqual(f.rows.map { webID[$0.contractID] ?? "?" }, rows.map { JS.str($0["id"]) }, "\(t) Klappgruppe \(f.key) Verträge")
                for (x, w) in zip(f.rows, rows) {
                    XCTAssertEqual(x.text, JS.str(w["text"]), "\(t) Klappgruppe \(f.key) \(JS.str(w["id"]))")
                }
            }

            // CSV-Export (zeilenweise, damit Abweichungen lesbar bleiben)
            let csvWeb = JS.str(exp["csv"])
            let csvApp = CSV.export(r.data, today: today)
            let lw = csvWeb.components(separatedBy: "\r\n")
            let la = csvApp.components(separatedBy: "\r\n")
            XCTAssertEqual(la.count, lw.count, "\(t) CSV Zeilen")
            for (i, (a, w)) in zip(la, lw).enumerated() {
                XCTAssertEqual(a, w, "\(t) CSV Zeile \(i)")
            }
        }
        XCTAssertEqual(checked, 100)
    }

    func testQualityAndLettersAgainstWeb() throws {
        var o = try parse("cases_texts")
        let go = try parse("golden_texts")
        guard let tx = JS.obj(go["texts"]), let q = JS.obj(tx["quality"]), let letters = JS.obj(tx["letters"]),
              let today = Day(iso: JS.str(o["today"])) else { return XCTFail("texts fehlt") }
        o["app"] = .string("vertraege")
        let r = WebImport.importObject(o, today: today, now: Date())
        let data = r.data
        let calc = Calc(data: data, today: today)
        var webC: [UUID: String] = [:]
        for (k, v) in r.contractIDs { webC[v] = k }
        var webI: [UUID: String] = [:]
        for (k, v) in r.incomeIDs { webI[v] = k }

        // Datenqualität
        let rep = Quality.report(data, today: today, hasFile: { _ in false })
        XCTAssertEqual(Quality.headline(rep)?.title, str(q["headline"]), "Kopf")
        XCTAssertEqual(Quality.headline(rep)?.text, str(q["text"]), "Kopf Text")
        XCTAssertEqual(Quality.footnote, str(q["footnote"]), "Fussnote")
        var rows: [(group: String, title: String, qf: String?, count: Int)] = []
        for g in Quality.checklist {
            for row in g.rows where row.field != "inc" || rep.incomeCount > 0 {
                let n = rep.select(g.group, field: row.field).count
                rows.append((g.title, row.title, n > 0 ? g.group.rawValue + ":" + row.field : nil, n))
            }
        }
        let wr = JS.arr(q["rows"]).compactMap { JS.obj($0) }
        XCTAssertEqual(rows.count, wr.count, "Checkliste Zeilen")
        for (a, w) in zip(rows, wr) {
            let m = "Checkliste \(a.title)"
            XCTAssertEqual(a.group, JS.str(w["group"]), m)
            XCTAssertEqual(a.title, JS.str(w["title"]), m)
            XCTAssertEqual(a.qf, str(w["qf"]), m)
            XCTAssertEqual(a.count, int(w["count"]), m + " Anzahl")
        }
        let inline: Set<String> = ["holder", "amount", "cat", "cycle", "due", "via", "ref", "link", "mail", "notice", "inc", "addr", "sender"]
        func webKey(_ i: QualityIssue) -> String {
            let mid: String
            switch i.subject {
            case .contract(let u): mid = webC[u] ?? u.uuidString
            case .income(let u): mid = webI[u] ?? u.uuidString
            case .partner(let u): mid = (data.partner(u)?.name ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            case .person(let u): mid = data.person(u)?.name ?? u.uuidString
            }
            return i.subject.code + ":" + mid + ":" + i.criterion.rawValue
        }
        let lists = JS.obj(q["lists"]) ?? JSObject()
        var total = 0
        for qf in lists.orderedKeys {
            let parts = qf.split(separator: ":").map(String.init)
            guard parts.count == 2, let g = QualityGroup(rawValue: parts[0]) else { continue }
            let f = parts[1]
            let mine = rep.select(g, field: f)
            let web = JS.arr(lists[qf]).compactMap { JS.obj($0) }
            XCTAssertEqual(mine.map(webKey), web.map { JS.str($0["key"]) }, "\(qf) Schlüssel")
            for (a, w) in zip(mine, web) {
                let small = (inline.contains(f) && f != "notice" && f != "inc") ? a.subtitle : [a.reason, a.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
                XCTAssertEqual(a.name, JS.str(w["name"]), "\(qf) \(JS.str(w["key"])) Name")
                XCTAssertEqual(small, JS.str(w["small"]), "\(qf) \(JS.str(w["key"])) Zusatz")
            }
            total += web.count
        }
        XCTAssertEqual(rep.totalCount, total, "Anzahl Punkte")

        // Kündigungsschreiben
        for id in letters.orderedKeys {
            guard let uid = r.contractIDs[id], let c = data.contract(uid), let w = JS.obj(letters[id]) else {
                XCTFail("Brief \(id) fehlt")
                continue
            }
            let p = Letter.parts(c, calc: calc)
            let sl = Letter.senderLine(p)
            XCTAssertEqual(sl.bold + sl.text, JS.str(w["sender"]), "\(id) Absender")
            XCTAssertEqual(p.to.joined(separator: "\n"), JS.str(w["to"]), "\(id) Empfänger")
            XCTAssertEqual(p.subject, JS.str(w["subject"]), "\(id) Betreff")
            XCTAssertEqual(p.bodyText, JS.str(w["body"]), "\(id) Text")
            XCTAssertEqual(Letter.hints(c, parts: p, calc: calc).joined(separator: " "), JS.str(w["hint"]), "\(id) Hinweise")
        }
    }
}
