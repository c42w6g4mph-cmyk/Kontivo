import XCTest
@testable import KontivoCore

final class WebImportTests: XCTestCase {
    static let backup = """
    {"app":"vertraege","version":2,"exported":"2026-10-01T10:00:00.000Z",
     "settings":{"home":"CHF","rates":{"EUR":0.95,"USD":0},"holders":["Sinan","Lara"],
       "senders":{"Sinan":{"first":"Sinan","last":"Beispiel","street":"Hauptstrasse 1","zip":"8280","city":"Kreuzlingen","country":""},
                  "Lara":{"first":"Lara","last":"Muster","street":"","zip":"","city":"","country":"","same":"Sinan"}},
       "sigs":{"Sinan":"data:image/jpeg;base64,/9j/4AAQSkZJRg=="},
       "catList":[{"n":"Wohnen","c":"#6B4E9E","i":"Wohnen"},{"n":"Versicherungen","c":"#0E5A5E","i":"Versicherung"},
                  {"n":"Streaming & Software","c":"#A93227","i":"Streaming & Software"},{"n":"Sonstiges","c":"#5F666E","i":"Sonstiges"}],
       "qIgn":{"c:k1:ref":1,"p:sunrise:logo":1,"h:Lara:sender":1,"c:gibtsnicht:holder":1},
       "sort":"cost","theme":"dark","lastHolders":["Lara"],"onboarded":1,"lastReview":"2026-07-01"},
     "contracts":{
       "k1":{"partner":"Sunrise","label":"Internet","cat":"Streaming & Software","amount":"49.90","cur":"CHF","cycle":"1","due":"2026-10-15",
             "notice":"60","noticeU":"d","cancTerm":"m","holders":["Sinan","Lara"],"cancF":"Online / Kundenkonto","web":"sunrise.ch","t":1759312800000},
       "k2":{"partner":"sunrise ","label":"Handy","cat":"Versicherungen","amount":30,"cur":"CHF","cycle":1,"due":"2026-10-20",
             "addr":"Sunrise GmbH\\nThurgauerstrasse 101B\\n8152 Glattpark","holders":["Lara"],"paused":true,"pausedAt":"2026-09-01","pausedUntil":"",
             "logoId":"abc123","logoBg":"#FFFFFF","extras":[{"date":"2026-12-01","amount":-15,"note":"Gutschrift"},{"date":"2026-12-02","amount":0}],
             "prices":[{"from":"2027-01-01","amount":"35"}],"docs":[{"id":"doc1","name":"Vertrag.pdf","type":"application/pdf"}]},
       "k3":{"partner":"Gemeinde","label":"Steuern Gemeinde","cat":"Steuern","amount":1000,"cycle":3,"due":"2026-11-30","holder":"Sinan","status":"cancelled","cancelledAt":"2026-09-30"}
     },
     "incomes":{"i1":{"name":"Firma AG","label":"Lohn Sinan","cat":"Lohn","amount":"5000","cur":"CHF","cycle":1,"due":"2026-10-25","holders":["Sinan"]},
                "i2":{"name":"Bonus","cat":"Bonus","amount":1000,"cycle":0,"due":"2026-12-20","holders":["Lara"]}},
     "files":{"abc123":{"type":"image/png","data":"iVBORw0KGgo="},"doc1":{"type":"application/pdf","data":"JVBERi0="}}
    }
    """

    func load() throws -> WebImportResult {
        try WebImport.importBackup(Data(WebImportTests.backup.utf8), today: Day(2026, 10, 3))
    }

    func testPersons() throws {
        let r = try load()
        let d = r.data
        XCTAssertEqual(d.persons.map { $0.name }, ["Sinan", "Lara"])
        let sinan = try XCTUnwrap(d.person(named: "Sinan"))
        let lara = try XCTUnwrap(d.person(named: "Lara"))
        XCTAssertEqual(lara.sameAddressAs, sinan.id)
        XCTAssertEqual(d.resolvedSender(lara.id).street, "Hauptstrasse 1")
        XCTAssertEqual(d.resolvedSender(lara.id).city, "Kreuzlingen")
        XCTAssertEqual(d.resolvedSender(lara.id).first, "Lara")
        XCTAssertTrue(d.resolvedSender(lara.id).isComplete)
        XCTAssertEqual(d.senderName(sinan.id), "Sinan Beispiel")
        let sig = try XCTUnwrap(sinan.signatureJPEG)
        XCTAssertEqual(Array(sig.prefix(2)), [0xFF, 0xD8])
        XCTAssertNil(lara.signatureJPEG)
    }

    func testCategories() throws {
        let d = try load().data
        let names = d.categories.map { $0.name }
        XCTAssertEqual(names, ["Wohnen", "Versicherungen", "Abos & Medien", "Sonstiges", "Steuern & Gebühren"])
        let vers = try XCTUnwrap(d.category(named: "Versicherungen"))
        XCTAssertNil(vers.kind)
        XCTAssertEqual(vers.icon, "Versicherung")
        XCTAssertEqual(d.category(named: "Abos & Medien")?.kind, .media)
        XCTAssertEqual(d.category(named: "Abos & Medien")?.icon, "Abos & Medien")
        XCTAssertEqual(d.category(named: "Steuern & Gebühren")?.kind, .taxes)
        XCTAssertEqual(d.category(named: "Sonstiges")?.kind, .other)
    }

    func testPartnersAndContracts() throws {
        let r = try load()
        let d = r.data
        XCTAssertEqual(d.partners.count, 2)
        let sunrise = try XCTUnwrap(d.partners.first { $0.name == "Sunrise" })
        XCTAssertEqual(sunrise.web, "sunrise.ch")
        XCTAssertEqual(sunrise.logoID, "abc123")
        XCTAssertEqual(sunrise.address.company, "Sunrise GmbH")
        XCTAssertEqual(sunrise.address.street, "Thurgauerstrasse 101B")
        XCTAssertEqual(sunrise.address.zip, "8152")
        XCTAssertEqual(sunrise.address.city, "Glattpark")

        let k1 = try XCTUnwrap(d.contract(r.contractIDs["k1"]))
        let k2 = try XCTUnwrap(d.contract(r.contractIDs["k2"]))
        let k3 = try XCTUnwrap(d.contract(r.contractIDs["k3"]))
        XCTAssertEqual(d.contracts.map { $0.id }, [k1.id, k2.id, k3.id])
        XCTAssertEqual(k1.partnerID, sunrise.id)
        XCTAssertEqual(k2.partnerID, sunrise.id)
        XCTAssertNil(k2.logoID)
        XCTAssertEqual(d.category(k1.categoryID)?.name, "Abos & Medien")
        XCTAssertEqual(d.category(k2.categoryID)?.name, "Versicherungen")
        XCTAssertEqual(k1.amount, 49.9, accuracy: 1e-9)
        XCTAssertEqual(k1.cycle, 1)
        XCTAssertEqual(k1.notice, 60)
        XCTAssertEqual(k1.noticeUnit, .days)
        XCTAssertEqual(k1.cancelTerm, .monthEnd)
        XCTAssertEqual(k1.cancelChannel, .online)
        XCTAssertEqual(k1.holderIDs, [r.personIDs["Sinan"]!, r.personIDs["Lara"]!])
        XCTAssertEqual(k1.createdAt.timeIntervalSince1970, 1_759_312_800, accuracy: 0.001)
        XCTAssertEqual(k2.pauses, [Pause(from: Day(2026, 9, 1), until: nil)])
        XCTAssertEqual(k2.extras.count, 1)
        XCTAssertEqual(k2.extras.first?.amount ?? 0, -15, accuracy: 1e-9)
        XCTAssertEqual(k2.prices, [PriceChange(from: Day(2027, 1, 1), amount: 35)])
        XCTAssertEqual(k2.documents, [Attachment(id: "doc1", name: "Vertrag.pdf", type: "application/pdf")])
        XCTAssertEqual(k3.holderIDs, [r.personIDs["Sinan"]!])
        XCTAssertEqual(k3.status, .cancelled)
        XCTAssertEqual(k3.cancelledAt, Day(2026, 9, 30))
        XCTAssertEqual(k3.cycle, 3)

        let calc = Calc(data: d, today: Day(2026, 10, 3))
        XCTAssertTrue(calc.isTax(k3))
        XCTAssertTrue(calc.isPaused(k2))
        XCTAssertEqual(calc.cancVia(k1), .online)
        XCTAssertEqual(calc.cancLink(k1), "https://sunrise.ch")
        XCTAssertEqual(calc.active.count, 2)
        XCTAssertEqual(calc.archived.count, 1)
        XCTAssertEqual(calc.running.count, 1)
    }

    func testIncomesSettingsFiles() throws {
        let r = try load()
        let d = r.data
        XCTAssertEqual(d.incomes.count, 2)
        let i1 = try XCTUnwrap(d.income(r.incomeIDs["i1"]))
        XCTAssertEqual(i1.holderID, r.personIDs["Sinan"])
        XCTAssertEqual(i1.amount, 5000, accuracy: 1e-9)
        XCTAssertEqual(i1.kind, .lohn)
        XCTAssertEqual(i1.title, "Lohn Sinan")
        let i2 = try XCTUnwrap(d.income(r.incomeIDs["i2"]))
        XCTAssertEqual(i2.cycle, 0)
        XCTAssertEqual(i2.kind, .bonus)
        XCTAssertEqual(i2.title, "Bonus")

        XCTAssertEqual(d.settings.homeCurrency, .CHF)
        XCTAssertEqual(d.settings.rates, ["EUR": 0.95])
        XCTAssertEqual(d.settings.sort, .cost)
        XCTAssertEqual(d.settings.theme, .dark)
        XCTAssertEqual(d.settings.onboarded, 1)
        XCTAssertEqual(d.settings.lastReview, Day(2026, 7, 1))
        XCTAssertEqual(d.settings.lastHolderIDs, [r.personIDs["Lara"]!])
        let sunrise = try XCTUnwrap(d.partners.first { $0.name == "Sunrise" })
        let ign = Set(d.settings.qualityIgnored)
        XCTAssertEqual(ign, Set(["c:" + r.contractIDs["k1"]!.uuidString + ":ref", "p:" + sunrise.id.uuidString + ":logo",
                                 "h:" + r.personIDs["Lara"]!.uuidString + ":sender"]))

        XCTAssertEqual(r.files.count, 2)
        XCTAssertEqual(r.files["abc123"]?.type, "image/png")
        XCTAssertEqual(Array(r.files["abc123"]?.data.prefix(4) ?? Data()), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(r.failedFiles, 0)
        XCTAssertEqual(r.exported, "2026-10-01T10:00:00.000Z")
        XCTAssertTrue(WebImport.isWebBackup(Data(WebImportTests.backup.utf8)))
    }

    func testMigrations() throws {
        let old = """
        {"app":"vertraege","settings":{"rate":0.96,"holders":["Anna"],"sender":"Anna Muster\\nBahnhofstr. 5\\nCH-8001 Zürich\\nSchweiz","sig":"data:image/jpeg;base64,/9j/","cats":[{"n":"Haustier","c":"#A93227"},{"n":"Energie","c":"#B0562A"}]},
         "contracts":{"a":{"partner":"EKZ","cat":"Energie","amount":80,"cycle":1,"due":"2026-10-30","holder":"Anna"},"b":{"label":"Hund","cat":"Haustier","amount":20,"due":"2026-10-30"}}}
        """
        let r = try WebImport.importBackup(Data(old.utf8), today: Day(2026, 10, 3))
        let d = r.data
        XCTAssertEqual(d.settings.rates["EUR"], 0.96)
        XCTAssertEqual(d.persons.map { $0.name }, ["Anna"])
        let anna = d.persons[0]
        XCTAssertEqual(anna.sender.first, "Anna")
        XCTAssertEqual(anna.sender.last, "Muster")
        XCTAssertEqual(anna.sender.street, "Bahnhofstr. 5")
        XCTAssertEqual(anna.sender.zip, "8001")
        XCTAssertEqual(anna.sender.city, "Zürich")
        XCTAssertEqual(anna.sender.country, "Schweiz")
        XCTAssertNotNil(anna.signatureJPEG)
        XCTAssertEqual(d.categories.count, 13)
        XCTAssertEqual(d.categories.last?.name, "Haustier")
        XCTAssertEqual(d.categories.last?.icon, "tag")
        let a = try XCTUnwrap(d.contract(r.contractIDs["a"]))
        XCTAssertEqual(d.category(a.categoryID)?.name, "Energie & Wasser")
        XCTAssertEqual(a.holderIDs, [anna.id])
        let b = try XCTUnwrap(d.contract(r.contractIDs["b"]))
        XCTAssertEqual(b.cycle, 1)
        XCTAssertNil(b.partnerID)
    }

    func testTextParsers() {
        let s = WebImport.senderParse("Sinan Beispiel\nHauptstrasse 1\n8280 Kreuzlingen")
        XCTAssertEqual(s, SenderAddress(first: "Sinan", last: "Beispiel", street: "Hauptstrasse 1", zip: "8280", city: "Kreuzlingen", country: ""))
        let a = WebImport.addrSplit("Muster GmbH\nKundendienst\nPostfach 12\nD-78462 Konstanz\nDeutschland")
        XCTAssertEqual(a, PostalAddress(company: "Muster GmbH", extra: "Kundendienst", street: "Postfach 12", zip: "D-78462", city: "Konstanz", country: "Deutschland"))
        let b = WebImport.addrSplit("Wincasa AG\n8000 Zürich", partnerName: "Wincasa AG")
        XCTAssertEqual(b.company, "Wincasa AG")
        XCTAssertEqual(b.street, "")
        let c = WebImport.addrSplit("Firma\nZusatz\nHauptstr. 1")
        XCTAssertEqual(c, PostalAddress(company: "Firma", extra: "Zusatz", street: "Hauptstr. 1"))
        XCTAssertEqual(PostalAddress(company: "A", street: "B 1", zip: "8000", city: "Zürich").lines, ["A", "B 1", "8000 Zürich"])
    }

    func testInvalid() {
        XCTAssertThrowsError(try WebImport.importBackup(Data("kein json".utf8), today: Day(2026, 10, 3))) { e in
            XCTAssertEqual(e as? WebImportError, .invalidJSON)
        }
        XCTAssertThrowsError(try WebImport.importBackup(Data("{\"app\":\"x\"}".utf8), today: Day(2026, 10, 3))) { e in
            XCTAssertEqual(e as? WebImportError, .notAWebBackup)
        }
    }

    func testBackupRoundTrip() throws {
        let r = try load()
        let json = try Backup.export(r.data, files: r.files, now: Date(timeIntervalSince1970: 1_790_000_000))
        let back = try Backup.read(json, today: Day(2026, 10, 3))
        XCTAssertEqual(back.source, .native)
        XCTAssertEqual(back.data, r.data)
        XCTAssertEqual(back.files, r.files)
        XCTAssertEqual(back.exported, Timestamp.isoString(Date(timeIntervalSince1970: 1_790_000_000)))
        let web = try Backup.read(Data(WebImportTests.backup.utf8), today: Day(2026, 10, 3))
        XCTAssertEqual(web.source, .web)
        XCTAssertEqual(web.data.contracts.count, 3)
        XCTAssertTrue(web.confirmText().hasPrefix("Backup vom "))
        XCTAssertTrue(web.confirmText().contains("mit 3 Verträgen und 2 Einnahmen sowie 2 Logos/Dokumenten."))
        XCTAssertThrowsError(try Backup.read(Data("{}".utf8), today: Day(2026, 10, 3)))
        XCTAssertEqual(Backup.fileName(today: Day(2026, 10, 3)), "kontivo-sicherung-2026-10-03.json")
        // Datei mit `data.json`-Format
        let enc = try r.data.encoded()
        XCTAssertEqual(try AppData.decode(enc), r.data)
    }

    /// W-1, W-2, W-4, W-5, W-6, BK-2, addrSplit wie Web.
    func testKeysGroupsSanitize() throws {
        let json = """
        {"app":"vertraege","settings":{"dataVer":2,"holders":["Sinan","Lara"],
           "catList":[{"n":"Abgaben","k":"Steuern & Gebühren","c":"red","i":"Steuern"},{"n":"Versicherungen","k":"Versicherung","c":"#0E5A5E","i":"Versicherung"},
                      {"n":"Daheim","k":"Wohnen","c":"#6B4E9E","i":"Wohnen"},{"n":"Wohnen","c":"#123456"},{"n":"Sonstiges","k":"Sonstiges"}],
           "sigs":{"Sinan":"data:image/gif;base64,R0lG","Lara":"data:image/png;base64,iVBORw0KGgo="},
           "avatars":{"Sinan":"nicht-hex","Lara":"0123456789abcdef0123456789abcdef"}},
         "contracts":{
           "a":{"partner":"Allianz Suisse","label":"Hausrat","cat":"Versicherungen","amount":30,"cycle":12,"due":"2027-01-01","addr":"Allianz Suisse\\nRichtiplatz 1\\n8304 Wallisellen","color":"javascript:x"},
           "b":{"partner":"Allianz","label":"Auto","cat":"Versicherungen","amount":50,"cycle":12,"due":"2027-01-01","addr":"Allianz\\nPostfach\\n8010 Zürich","logoBg":"#FFF"},
           "c":{"partner":"Gemeinde","label":"Steuern","cat":"Abgaben","amount":1000,"cycle":12,"due":"2027-03-31","notice":3,"cancTerm":"y"},
           "d":{"label":"Miete","cat":"Daheim","amount":1800,"cycle":1,"due":"2026-11-01","addr":"Bahnhofstrasse 5\\n8001 Zürich"},
           "e":{"cat":"Wohnen","amount":10,"cycle":1,"due":"2026-11-01","addr":"Postfach 3\\n8001 Zürich"},
           "f":{"partner":"EKZ","cat":"Energie","amount":80,"cycle":1,"due":"2026-10-30"}},
         "incomes":{"i1":{"name":"Vermietung","cat":"Vermietung","amount":1000,"cycle":1,"due":"2026-10-25","holders":["Sinan","Lara"],
                          "prices":[{"from":"2027-01-01","amount":1200}]}},
         "files":{"x1":{"type":"image/png","data":""},"x2":{"type":"image/png"}}}
        """
        let r = try WebImport.importBackup(Data(json.utf8), today: Day(2026, 10, 3))
        let d = r.data
        // W-1: Fachschlüssel k
        XCTAssertEqual(d.category(named: "Abgaben")?.kind, .taxes)
        XCTAssertEqual(d.category(named: "Versicherungen")?.kind, .insurance)
        XCTAssertEqual(d.category(named: "Daheim")?.kind, .housing)
        XCTAssertNil(d.category(named: "Wohnen")?.kind)
        XCTAssertEqual(d.category(named: "Sonstiges")?.kind, .other)
        let calc = Calc(data: d, today: Day(2026, 10, 3))
        let c = try XCTUnwrap(d.contract(r.contractIDs["c"]))
        XCTAssertTrue(calc.isTax(c))
        XCTAssertNil(calc.noticeDeadline(c))
        let a = try XCTUnwrap(d.contract(r.contractIDs["a"]))
        XCTAssertEqual(calc.cancVia(a), .post)
        // W-5: Farben, Unterschriften, Avatare geprüft
        XCTAssertEqual(d.category(named: "Abgaben")?.colorHex, Category.fallbackColor)
        XCTAssertNil(a.colorHex)
        XCTAssertNil(d.person(named: "Sinan")?.signatureJPEG)
        XCTAssertNotNil(d.person(named: "Lara")?.signatureJPEG)
        XCTAssertNil(d.person(named: "Sinan")?.avatarID)
        XCTAssertEqual(d.person(named: "Lara")?.avatarID, "0123456789abcdef0123456789abcdef")
        // W-2: ähnliche Namen bleiben getrennte Vertragspartner mit eigener Adresse
        let b = try XCTUnwrap(d.contract(r.contractIDs["b"]))
        XCTAssertNotEqual(a.partnerID, b.partnerID)
        XCTAssertEqual(d.partner(a.partnerID)?.address.city, "Wallisellen")
        let pb = try XCTUnwrap(d.partner(b.partnerID))
        XCTAssertEqual(pb.address.city, "Zürich")
        XCTAssertEqual(pb.address.company, "Allianz")
        XCTAssertEqual(pb.address.street, "Postfach")
        XCTAssertEqual(pb.logoBg, nil)
        XCTAssertEqual(Partners.duplicateSets(d, today: Day(2026, 10, 3)).count, 1)
        // Ohne Vertragspartner: Adresse bleibt erhalten (W-3); einzelne Zeile mit Ziffer ist die Strasse
        let dc = try XCTUnwrap(d.contract(r.contractIDs["d"]))
        XCTAssertEqual(d.partner(dc.partnerID)?.address.street, "Bahnhofstrasse 5")
        let ec = try XCTUnwrap(d.contract(r.contractIDs["e"]))
        XCTAssertEqual(d.partner(ec.partnerID)?.address.street, "Postfach 3")
        // W-4: Einnahme mit zwei Inhabern → je eine Hälfte
        XCTAssertEqual(d.incomes.count, 2)
        XCTAssertEqual(d.incomes.map { $0.amount }, [500, 500])
        XCTAssertEqual(Set(d.incomes.compactMap { $0.holderID }), Set([r.personIDs["Sinan"]!, r.personIDs["Lara"]!]))
        XCTAssertEqual(d.incomes[1].prices, [PriceChange(from: Day(2027, 1, 1), amount: 600)])
        XCTAssertEqual(d.incomes[0].id, r.incomeIDs["i1"])
        // BK-2: leere Dateien zählen als fehlend
        XCTAssertEqual(r.files.count, 0)
        XCTAssertEqual(r.failedFiles, 2)
        // W-6: Symbol-Schlüssel alter Namen immer umstellen, Namen nur bei Datenversion < 2
        XCTAssertEqual(d.category(named: "Abgaben")?.icon, "Steuern & Gebühren")
        let f = try XCTUnwrap(d.contract(r.contractIDs["f"]))
        XCTAssertEqual(d.category(f.categoryID)?.name, "Energie")
        let v1 = try WebImport.importBackup(Data(json.replacingOccurrences(of: "\"dataVer\":2", with: "\"dataVer\":\"1\"").utf8), today: Day(2026, 10, 3))
        let f1 = try XCTUnwrap(v1.data.contract(v1.contractIDs["f"]))
        XCTAssertEqual(v1.data.category(f1.categoryID)?.name, "Energie & Wasser")
        XCTAssertEqual(v1.data.category(f1.categoryID)?.kind, .energy)
    }

    func testAddrSplitLikeWeb() {
        let a = WebImport.addrSplit("Postfach\n8021 Zürich", partnerName: "Swisscom")
        XCTAssertEqual(a.company, "")
        XCTAssertEqual(a.street, "Postfach")
        let b = WebImport.addrSplit("Swisscom (Schweiz) AG\n3050 Bern", partnerName: "Swisscom")
        XCTAssertEqual(b.company, "Swisscom (Schweiz) AG")
        let c = WebImport.addrSplit("Kundendienst\n3050 Bern")
        XCTAssertEqual(c.street, "Kundendienst")
    }

    /// COD-1: ein defektes Element löscht nicht die ganze Liste; eine gar nicht lesbare Liste wirft.
    func testLossyDecoding() throws {
        var d = AppData.initial()
        d.contracts = [Contract(label: "A", amount: 10, prices: [PriceChange(from: Day(2027, 1, 1), amount: 12), PriceChange(from: Day(2028, 1, 1), amount: 14)]),
                       Contract(label: "B", amount: 20)]
        let enc = try d.encoded()
        var o = try XCTUnwrap(JSONSerialization.jsonObject(with: enc) as? [String: Any])
        var cs = try XCTUnwrap(o["contracts"] as? [Any])
        var c0 = try XCTUnwrap(cs[0] as? [String: Any])
        var ps = try XCTUnwrap(c0["prices"] as? [Any])
        ps[1] = ["from": "kaputt", "amount": 14]
        c0["prices"] = ps
        cs[0] = c0
        cs.append(5)
        o["contracts"] = cs
        let back = try AppData.decode(try JSONSerialization.data(withJSONObject: o))
        XCTAssertEqual(back.contracts.map { $0.label }, ["A", "B"])
        XCTAssertEqual(back.contracts[0].prices, [PriceChange(from: Day(2027, 1, 1), amount: 12)])
        XCTAssertEqual(back.categories.count, d.categories.count)
        o["contracts"] = "kein Array"
        XCTAssertThrowsError(try AppData.decode(try JSONSerialization.data(withJSONObject: o)))
        o["contracts"] = [1, 2]
        XCTAssertThrowsError(try AppData.decode(try JSONSerialization.data(withJSONObject: o)))
    }
}
