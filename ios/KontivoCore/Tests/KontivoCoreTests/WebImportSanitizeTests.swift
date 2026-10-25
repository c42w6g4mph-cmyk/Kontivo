import XCTest
@testable import KontivoCore

/// Backup mit Grenzwerten wie die Web-App beim Einspielen bereinigt (golden_import.json aus `sanitizeImport`, ios/Tools/golden/make_golden_import.py):
/// Zyklus (einmalig nur bei Einnahmen), Beträge, Währung, Frist, Preise/Sonderzahlungen, Aufteilung, Logo (Datei-ID, rgb()-Hintergrund),
/// Dokumente, Farben, Personen, Kategorien ohne Namen, gelernte Korrekturen, variable Kosten (Web Bereinigung E, Gegenprüfung).
final class WebImportSanitizeTests: XCTestCase {
    func testSanitizeLikeWeb() throws {
        guard case .object(let go) = try JSONParser.parse(GoldenTests.resource("golden_import")),
              let backup = JS.obj(go["backup"]), let san = JS.obj(go["sanitized"]) else {
            XCTFail("golden_import.json unlesbar")
            return
        }
        let r = WebImport.importObject(backup, today: Day(2026, 10, 25), now: Date())
        let d = r.data
        // Verträge: gleiche Reihenfolge wie Web (neu vergebene Schlüssel stehen an derselben Stelle)
        let ec = JS.obj(san["contracts"]) ?? JSObject()
        XCTAssertEqual(d.contracts.count, ec.orderedKeys.count, "Anzahl Verträge")
        for (i, k) in ec.orderedKeys.enumerated() where i < d.contracts.count {
            guard let e = JS.obj(ec[k]) else { continue }
            let c = d.contracts[i]
            let m = "Vertrag \(JS.str(e["label"]))"
            XCTAssertEqual(c.label, JS.str(e["label"]), m)
            XCTAssertEqual(c.amount, JS.num(e["amount"]), accuracy: 0.0001, m + " Betrag")
            XCTAssertEqual(c.cycle, Int(JS.num(e["cycle"])), m + " Zyklus")
            XCTAssertEqual(c.currency.rawValue, JS.str(e["cur"]), m + " Währung")
            XCTAssertEqual(c.notice, e["notice"] == nil ? 0 : Int(JS.num(e["notice"])), m + " Frist")
            XCTAssertEqual(c.renewMonths, e["renew"] == nil ? 0 : Int(JS.num(e["renew"])), m + " Verlängerung")
            let logo = JS.str(e["logoId"])
            XCTAssertEqual(c.logoID ?? "", logo, m + " Logo")
            if !logo.isEmpty { XCTAssertEqual(c.logoBg ?? "", JS.str(e["logoBg"]), m + " Logo-Hintergrund") }
            XCTAssertEqual(c.colorHex ?? "", JS.str(e["color"]), m + " Farbe")
            XCTAssertEqual(c.documents.map { $0.id }, JS.arr(e["docs"]).compactMap { JS.obj($0) }.map { JS.str($0["id"]) }, m + " Dokumente")
            XCTAssertEqual(c.prices.map { $0.from.iso + "=" + String($0.amount) },
                           JS.arr(e["prices"]).compactMap { JS.obj($0) }.map { JS.str($0["from"]) + "=" + String(JS.num($0["amount"])) }, m + " Preise")
            XCTAssertEqual(c.extras.map { $0.date.iso + "=" + String($0.amount) + "|" + $0.note },
                           JS.arr(e["extras"]).compactMap { JS.obj($0) }.map { JS.str($0["date"]) + "=" + String(JS.num($0["amount"])) + "|" + JS.str($0["note"]) }, m + " Sonderzahlungen")
            let es = JS.obj(e["split"]) ?? JSObject()
            XCTAssertEqual(c.split.count, es.orderedKeys.count, m + " Aufteilung")
        }
        // Einnahmen: einmalig (0) bleibt, ungültiger Zyklus → monatlich, Logo mit rgb()
        let ei = JS.obj(san["incomes"]) ?? JSObject()
        XCTAssertEqual(d.incomes.count, ei.orderedKeys.count)
        for (i, k) in ei.orderedKeys.enumerated() where i < d.incomes.count {
            guard let e = JS.obj(ei[k]) else { continue }
            let x = d.incomes[i]
            XCTAssertEqual(x.cycle, Int(JS.num(e["cycle"])), "Einnahme \(x.name) Zyklus")
            XCTAssertEqual(x.amount, JS.num(e["amount"]), accuracy: 0.0001, "Einnahme \(x.name) Betrag")
            XCTAssertEqual(x.logoID ?? "", JS.str(e["logoId"]), "Einnahme \(x.name) Logo")
            XCTAssertEqual(x.logoBg ?? "", JS.str(e["logoBg"]), "Einnahme \(x.name) Logo-Hintergrund")
        }
        // Variable Kosten
        let ev = JS.obj(san["vars"]) ?? JSObject()
        XCTAssertEqual(d.variableCosts.count, ev.orderedKeys.count)
        for (i, k) in ev.orderedKeys.enumerated() where i < d.variableCosts.count {
            guard let e = JS.obj(ev[k]) else { continue }
            let v = d.variableCosts[i]
            XCTAssertEqual(v.label, JS.str(e["label"]), "Variabel Bezeichnung")
            XCTAssertEqual(v.amount, JS.num(e["amount"]), accuracy: 0.0001, "Variabel Betrag")
            XCTAssertEqual(v.currency.rawValue, JS.str(e["cur"]), "Variabel Währung")
            XCTAssertEqual(v.logoID ?? "", JS.str(e["logoId"]), "Variabel Logo")
            XCTAssertEqual(v.logoBg ?? "", JS.str(e["logoBg"]), "Variabel Logo-Hintergrund")
        }
        // Einstellungen: Personen, Kategorien ohne Namen weg, gelernte Korrekturen, Avatare
        let s = JS.obj(san["settings"]) ?? JSObject()
        XCTAssertEqual(d.persons.map { $0.name }, JS.arr(s["holders"]).map { JS.str($0) })
        let cats = JS.arr(s["catList"]).compactMap { JS.obj($0) }.map { JS.str($0["n"]) }
        for n in cats { XCTAssertNotNil(d.category(named: n), "Kategorie \(n)") }
        XCTAssertFalse(d.categories.contains { $0.name.isEmpty }, "keine Kategorie ohne Namen")
        XCTAssertEqual(d.settings.bankIgn, JS.arr(s["bankIgn"]).map { JS.str($0) })
        XCTAssertEqual(d.settings.bankAlias.keys.sorted(), (JS.obj(s["bankAlias"]) ?? JSObject()).orderedKeys.sorted())
        XCTAssertEqual(d.settings.bankAlias["k1"]?.n, "Muster AG")
    }
}
