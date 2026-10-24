import XCTest
@testable import KontivoCore

/// Web-Backup mit den Feldern bis Web v322 (main/docs/datenmodell.md): variable Kosten, Kostenart, Sortierungen, Brieffenster,
/// letzter Kontoauszug, Kontoauszug-Korrekturen, Gläubiger-ID/Mandat.
final class WebImportV322Tests: XCTestCase {
    let backup = """
    {"app":"vertraege","version":2,
     "settings":{"home":"CHF","holders":["Sinan","Lara"],"kArt":"all","bArt":"none","sortI":"cost","sortV":"name","ltWin":"r",
       "bankLast":{"from":"2025-10-01","to":"2026-09-30","at":"2026-10-22","n":2,"ok":1},
       "bankIgn":["coop|12.50",7],"bankAlias":{"swisscom|59":{"n":"  Swisscom AG ","c":"Mobilfunk & Internet"},"x":{"n":""}}},
     "contracts":{"a1":{"partner":"CSS","label":"KK","cat":"Versicherung","amount":412.35,"cur":"CHF","cycle":1,"due":"2026-01-01",
       "holders":["Sinan"],"cred":"CH12ZZZ00000000001","mref":"M-77","status":"active"}},
     "incomes":{},
     "vars":{"v1":{"label":"Lebensmittel","ic":"essen","amount":900,"cur":"CHF","holders":["Sinan","Lara"],"start":"","end":"","t":1},
             "v2":{"label":"","ic":"unbekannt","amount":-5,"cur":"XYZ","holders":["Mia"],"start":"2026-03-01","end":"kein Datum","t":2}}}
    """

    func testImport() throws {
        let r = try WebImport.importBackup(Data(backup.utf8), today: Day(2026, 10, 24))
        let st = r.data.settings
        XCTAssertEqual(st.costKind, .all)
        XCTAssertEqual(st.budgetKind, .none)
        XCTAssertEqual(st.incomeSort, "cost")
        XCTAssertEqual(st.variableSort, "name")
        XCTAssertTrue(st.letterWindowRight)
        XCTAssertEqual(st.lastBankImport, BankImportInfo(from: Day(2025, 10, 1), to: Day(2026, 9, 30), at: Day(2026, 10, 22), files: 2))
        XCTAssertEqual(st.bankIgn, ["coop|12.50"])
        XCTAssertEqual(st.bankAlias["swisscom|59"], BankAlias(n: "Swisscom AG", c: "Mobilfunk & Internet"))
        XCTAssertNil(st.bankAlias["x"])
        XCTAssertEqual(r.data.contracts.first?.creditorID, "CH12ZZZ00000000001")
        XCTAssertEqual(r.data.contracts.first?.mandateRef, "M-77")
        // Variable Kosten: Personen aus vars kommen dazu, ungültige Werte wie Web sanitizeImport
        XCTAssertEqual(r.data.variableCosts.count, 2)
        let v1 = r.data.variableCosts[0], v2 = r.data.variableCosts[1]
        XCTAssertEqual(v1.icon, .essen)
        XCTAssertEqual(v1.holderIDs.count, 2)
        XCTAssertEqual(v2.icon, .sonst)
        XCTAssertEqual(v2.title, "Sonstiges")
        XCTAssertEqual(v2.amount, 0)
        XCTAssertEqual(v2.currency, .CHF)
        XCTAssertEqual(v2.start, Day(2026, 3, 1))
        XCTAssertNil(v2.end)
        XCTAssertNotNil(r.personIDs["Mia"])
        XCTAssertEqual(v2.holderIDs, [r.personIDs["Mia"]!])
    }

    func testBankLastWithoutOkIsDropped() throws {
        let b = backup.replacingOccurrences(of: "\"n\":2,\"ok\":1", with: "\"n\":2")
        let r = try WebImport.importBackup(Data(b.utf8), today: Day(2026, 10, 24))
        XCTAssertNil(r.data.settings.lastBankImport)
    }
}
