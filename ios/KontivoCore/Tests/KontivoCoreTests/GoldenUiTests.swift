import XCTest
@testable import KontivoCore

/// Tab «Fristen» gegen golden_ui.json (aus der Web-App v322 abgelesen mit main/tests/make_golden_ui.py): Haushalt aus
/// cases_budget.json plus alle Verträge aus cases.json, 7 Stichtage. Geprüft: Zahl am Tab, Kopf, alle Zeilen in Reihenfolge
/// (Gruppe, Titel, Unterzeile, Chip mit Stufe, Knöpfe).
final class GoldenUiTests: XCTestCase {
    struct Row: Equatable, CustomStringConvertible {
        var group, id, title, sub, chip, chipCls: String
        var acts: [String]
        var description: String { "[\(group)] \(id) «\(title)» «\(sub)» «\(chip)»(\(chipCls)) \(acts)" }
    }

    /// Daten wie make_golden_ui.py: Haushalt + Sonderfälle (Vertragspartner = Fall-ID, Bezeichnung = Notiz, max. 40 Zeichen).
    static func importData(today: Day) throws -> WebImportResult {
        guard case .object(let cb) = try JSONParser.parse(GoldenTests.resource("cases_budget")),
              case .object(let cs) = try JSONParser.parse(GoldenTests.resource("cases")) else { throw NSError(domain: "GoldenUiTests", code: 1) }
        var contracts = JS.obj(cb["contracts"]) ?? JSObject()
        for c in JS.arr(cs["cases"]).compactMap({ JS.obj($0) }) {
            let id = JS.str(c["id"])
            var o = JSObject()
            o["partner"] = .string(id)
            o["label"] = .string(String(JS.str(c["note"]).prefix(40)))
            o["cat"] = .string("Sonstiges")
            o["status"] = .string("active")
            if let co = JS.obj(c["c"]) { for k in co.orderedKeys { o[k] = co[k] } }
            contracts[id] = .object(o)
        }
        var settings = JS.obj(cb["settings"]) ?? JSObject()
        settings["lastReview"] = .string("2026-09-01")
        var backup = JSObject()
        backup["app"] = .string("vertraege")
        backup["settings"] = .object(settings)
        backup["contracts"] = .object(contracts)
        backup["incomes"] = cb["incomes"]
        backup["vars"] = cb["vars"]
        return WebImport.importObject(backup, today: today, now: Date())
    }

    func testDeadlinesTab() throws {
        guard case .object(let go) = try JSONParser.parse(GoldenTests.resource("golden_ui")), let results = JS.obj(go["results"]) else {
            XCTFail("golden_ui.json unlesbar")
            return
        }
        for t in results.orderedKeys {
            guard let today = Day(iso: t), let exp = JS.obj(results[t]), let term = JS.obj(exp["term"]) else { XCTFail(t); continue }
            let r = try GoldenUiTests.importData(today: today)
            let calc = Calc(data: r.data, today: today)
            var webID: [UUID: String] = [:]
            for (k, v) in r.contractIDs { webID[v] = k }
            let ov = calc.deadlineOverview()

            // Zahl am Tab
            let badge = JS.str(exp["badge"])
            XCTAssertEqual(ov.openCount == 0 ? "" : String(ov.openCount), badge, "\(t) Zahl am Tab")

            // Kopf
            if let st = JS.obj(term["stat"]) {
                XCTAssertEqual(ov.status?.kind.rawValue, JS.str(st["cls"]), "\(t) Kopf Stufe")
                XCTAssertEqual(ov.status?.count.map { String($0) } ?? "", JS.str(st["count"]), "\(t) Kopf Zahl")
                XCTAssertEqual(ov.status?.title, JS.str(st["title"]), "\(t) Kopf Titel")
                XCTAssertEqual(ov.status?.subtitle, JS.str(st["sub"]), "\(t) Kopf Untertitel")
            } else {
                XCTAssertNil(ov.status, "\(t) Kopf: Web ohne")
            }

            // Zeilen in Anzeigereihenfolge
            func title(_ id: UUID, _ partner: String) -> String {
                guard let c = r.data.contract(id) else { return "?" }
                return r.data.title(of: c) + (partner.isEmpty ? "" : " · " + partner)
            }
            var got: [Row] = []
            for x in ov.marked {
                got.append(Row(group: Calc.DeadlineOverview.markedTitle, id: webID[x.contractID] ?? "?", title: title(x.contractID, ""), sub: x.line,
                               chip: "", chipCls: "", acts: [x.keepTitle, x.cancelTitle]))
            }
            for x in ov.items {
                got.append(Row(group: Calc.DeadlineOverview.listTitle, id: webID[x.contractID] ?? "?", title: title(x.contractID, x.partner), sub: x.sub,
                               chip: x.chip, chipCls: x.chipLevel.rawValue, acts: x.showActions ? [x.keepTitle, x.cancelTitle] : []))
            }
            for x in ov.flexible {
                got.append(Row(group: Calc.DeadlineOverview.flexTitle, id: webID[x.contractID] ?? "?", title: title(x.contractID, x.partner), sub: x.sub,
                               chip: x.chip, chipCls: "", acts: []))
            }
            for x in ov.withoutNotice {
                got.append(Row(group: "Ohne Frist erfasst (\(ov.withoutNotice.count)) · ergänzen", id: webID[x.contractID] ?? "?", title: title(x.contractID, x.partner),
                               sub: x.text + " ›", chip: "", chipCls: "", acts: []))
            }
            for x in ov.unwatched {
                got.append(Row(group: "Nicht beobachtet (\(ov.unwatched.count))", id: webID[x.contractID] ?? "?", title: title(x.contractID, x.partner),
                               sub: x.text, chip: "", chipCls: "", acts: []))
            }
            let want = JS.arr(term["rows"]).compactMap { JS.obj($0) }.map {
                Row(group: JS.str($0["group"]), id: JS.str($0["id"]), title: JS.str($0["title"]), sub: JS.str($0["sub"]), chip: JS.str($0["chip"]),
                    chipCls: JS.str($0["chipCls"]), acts: JS.arr($0["acts"]).map { JS.str($0) })
            }
            XCTAssertEqual(got.count, want.count, "\(t) Anzahl Zeilen")
            for i in 0..<Swift.min(got.count, want.count) where got[i] != want[i] {
                XCTFail("\(t) Zeile \(i + 1):\n  Swift \(got[i])\n  Web   \(want[i])")
            }
        }
    }
}
