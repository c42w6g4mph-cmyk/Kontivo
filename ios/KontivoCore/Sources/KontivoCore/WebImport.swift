import Foundation

/// Datei aus einem Backup (Logo, Dokument, Bild).
public struct ImportedFile: Hashable, Sendable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// Ergebnis der Übernahme eines Web-Backups.
public struct WebImportResult: Sendable {
    public var data: AppData
    /// Dateien mit derselben ID wie in der Web-App
    public var files: [String: ImportedFile]
    /// Web-ID → neue UUID
    public var contractIDs: [String: UUID]
    public var incomeIDs: [String: UUID]
    /// Personenname → UUID
    public var personIDs: [String: UUID]
    /// Zeitpunkt des Backups (ISO-Text), falls vorhanden
    public var exported: String?
    /// Dateien, die nicht gelesen werden konnten
    public var failedFiles: Int
}

public enum WebImportError: Error, Equatable {
    /// Keine gültige JSON-Datei
    case invalidJSON
    /// JSON, aber kein Backup der Web-App (`app` ≠ "vertraege" oder `contracts` fehlt)
    case notAWebBackup
}

/// Web-Backup (`{app:"vertraege", version, exported, settings, contracts, incomes, files}`) → AppData.
public enum WebImport {
    /// Liest ein Backup der Web-App. Migrationen (migModel/migCats) laufen vor der Umwandlung.
    /// `today`: Tag des Imports (Pause ohne Beginn startet heute).
    public static func importBackup(_ json: Data, today: Day, now: Date = Date()) throws -> WebImportResult {
        guard let v = try? JSONParser.parse(json) else { throw WebImportError.invalidJSON }
        guard case .object(let o) = v, JS.str(o["app"]) == "vertraege", isObjectLike(o["contracts"]) else { throw WebImportError.notAWebBackup }
        return importObject(o, today: today, now: now)
    }

    /// Ist das ein Backup der Web-App?
    public static func isWebBackup(_ json: Data) -> Bool {
        guard let v = try? JSONParser.parse(json), case .object(let o) = v else { return false }
        return JS.str(o["app"]) == "vertraege" && isObjectLike(o["contracts"])
    }

    static func isObjectLike(_ v: JSValue?) -> Bool {
        guard let v = v else { return false }
        switch v {
        case .object, .array: return true
        default: return false
        }
    }

    // MARK: Ablauf

    static func importObject(_ o: JSObject, today: Day, now: Date) -> WebImportResult {
        // Settings in die Standardwerte mischen (Fix M3: nicht in die Werte des Geräts)
        var s = JSObject()
        s["home"] = .string("CHF")
        s["rates"] = .object(JSObject())
        s["holders"] = .array([.string("Ich")])
        if let so = JS.obj(o["settings"]) {
            for k in so.orderedKeys { s[k] = so[k] }
        }
        var contracts = JS.obj(o["contracts"]) ?? JSObject()
        var incomes = JS.obj(o["incomes"]) ?? JSObject()
        let filesObj = JS.obj(o["files"]) ?? JSObject()

        sanitize(&s, &contracts, &incomes)
        migModel(&s, &contracts, &incomes)
        // Wie Web `migCats`: alte Kategorienamen bei Datenversion < 2 (auch "1", 0 …), Symbol-Schlüssel immer
        if !(JS.num(s["dataVer"]) >= 2) { migCats(&s, &contracts) }
        migCatIcons(&s)

        let cKeys = contracts.orderedKeys
        let iKeys = incomes.orderedKeys
        let cObjs: [(String, JSObject)] = cKeys.compactMap { k in JS.obj(contracts[k]).map { (k, $0) } }
        let iObjs: [(String, JSObject)] = iKeys.compactMap { k in JS.obj(incomes[k]).map { (k, $0) } }

        // Dateien
        var files: [String: ImportedFile] = [:]
        var failed = 0
        for k in filesObj.orderedKeys {
            guard let f = JS.obj(filesObj[k]) else { failed += 1; continue }
            let b64 = JS.str(f["data"])
            // Wie Web (`!f.data` → fehlt): leere Datei zählt als nicht gelesen
            if b64.isEmpty { failed += 1; continue }
            if let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                files[k] = ImportedFile(type: JS.str(f["type"]), data: d)
            } else {
                failed += 1
            }
        }

        // Personen
        var names: [String] = []
        func addName(_ n: String) { if !n.isEmpty && !names.contains(n) { names.append(n) } }
        for h in JS.arr(s["holders"]) { addName(JS.str(h)) }
        for (_, c) in cObjs { for h in JS.arr(c["holders"]) { addName(JS.str(h)) } }
        for (_, c) in iObjs { for h in JS.arr(c["holders"]) { addName(JS.str(h)) } }
        let senders = JS.obj(s["senders"]) ?? JSObject()
        let sigs = JS.obj(s["sigs"]) ?? JSObject()
        let avatars = JS.obj(s["avatars"]) ?? JSObject()
        for k in senders.orderedKeys { addName(k) }
        for k in sigs.orderedKeys { addName(k) }
        for k in avatars.orderedKeys { addName(k) }
        if names.isEmpty { names = ["Ich"] }
        var personIDs: [String: UUID] = [:]
        for n in names { personIDs[n] = UUID() }
        var persons: [Person] = []
        for n in names {
            var p = Person(id: personIDs[n]!, name: n)
            if let r = JS.obj(senders[n]) {
                let t = { (k: String) in JS.str(r[k]).trimmingCharacters(in: .whitespacesAndNewlines) }
                p.sender = SenderAddress(first: t("first"), last: t("last"), street: t("street"), zip: t("zip"), city: t("city"), country: t("country"))
                let same = JS.str(r["same"])
                if !same.isEmpty && same != n, let sid = personIDs[same] { p.sameAddressAs = sid }
            }
            let sg = JS.str(sigs[n])
            if !sg.isEmpty { p.signatureJPEG = dataURLBytes(sg) }
            let av = JS.str(avatars[n])
            if !av.isEmpty { p.avatarID = av }
            persons.append(p)
        }

        // Kategorien
        var categories: [Category] = []
        func hasCat(_ n: String) -> Bool { categories.contains { $0.name == n } }
        func iconKey(_ i: String) -> String {
            (i == "tag" || Category.standardNames.contains(i) || IncomeKind(webName: i) != nil) ? i : "tag"
        }
        let catList = JS.arr(s["catList"]).compactMap { JS.obj($0) }
        // Fachschlüssel `k` (ursprünglicher Standardname) bleibt beim Umbenennen erhalten (Web `catKey`)
        let takenKeys = Set(catList.map { JS.str($0["k"]) }.filter { !$0.isEmpty })
        if !catList.isEmpty {
            for e in catList {
                let n = JS.str(e["n"])
                if n.isEmpty || hasCat(n) { continue }
                let col = JS.str(e["c"])
                categories.append(Category(name: n, colorHex: col.isEmpty ? (Category.standardColors[n] ?? Category.fallbackColor) : col,
                                           icon: iconKey(JS.str(e["i"])), kind: Category.importKind(name: n, key: JS.str(e["k"]), takenKeys: takenKeys)))
            }
        } else {
            categories = Category.standard()
            for x in JS.arr(s["cats"]).compactMap({ JS.obj($0) }) {
                let n = JS.str(x["n"])
                if n.isEmpty || Category.standardNames.contains(n) || hasCat(n) { continue }
                let col = JS.str(x["c"])
                categories.append(Category(name: n, colorHex: col.isEmpty ? (Category.standardColors[n] ?? Category.fallbackColor) : col,
                                           icon: "tag", kind: Category.defaultKind(forName: n)))
            }
        }
        for (_, c) in cObjs {
            let n = JS.str(c["cat"])
            if n.isEmpty || hasCat(n) { continue }
            categories.append(Category(name: n, colorHex: Category.standardColors[n] ?? Category.fallbackColor,
                                       icon: Category.standardNames.contains(n) ? n : "tag",
                                       kind: Category.importKind(name: n, key: "", takenKeys: takenKeys)))
        }
        if !categories.contains(where: { $0.kind == .other }) && !hasCat("Sonstiges") {
            categories.append(Category(name: "Sonstiges", colorHex: Category.standardColors["Sonstiges"] ?? Category.fallbackColor, icon: "Sonstiges", kind: .other))
        }

        // Vertragspartner: Gruppen nach Name ohne Gross/Klein (wie Web `partnerGroups`); ähnliche Namen (gleicher pkey)
        // bleiben getrennt und erscheinen nur als Dublette (Zusammenführen ist eine bewusste Aktion)
        struct PGroup {
            var key: String
            var names: [String] = []
            var counts: [String: Int] = [:]
            var members: [JSObject] = []
        }
        var groups: [PGroup] = []
        var contractGroup: [String: Int] = [:]
        for (k, c) in cObjs {
            guard let pn = partnerName(c) else { continue }
            let key = pn.trimmingCharacters(in: .whitespaces).lowercased()
            var gi = groups.firstIndex { $0.key == key }
            if gi == nil {
                groups.append(PGroup(key: key))
                gi = groups.count - 1
            }
            let i = gi!
            if groups[i].counts[pn] == nil { groups[i].names.append(pn) }
            groups[i].counts[pn, default: 0] += 1
            groups[i].members.append(c)
            contractGroup[k] = i
        }
        var partners: [Partner] = []
        var partnerByLower: [String: UUID] = [:]
        for g in groups {
            var best = g.names[0]
            for n in g.names where (g.counts[n] ?? 0) > (g.counts[best] ?? 0) { best = n }
            var p = Partner(name: best)
            p.web = g.members.map { JS.str($0["web"]).trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
            let withLogo = g.members.filter { !JS.str($0["logoId"]).isEmpty }
            let lc = withLogo.first { files[JS.str($0["logoId"])] != nil } ?? withLogo.first
            if let lc = lc {
                p.logoID = JS.str(lc["logoId"])
                let bg = JS.str(lc["logoBg"])
                p.logoBg = bg.isEmpty ? nil : bg
            }
            if let addr = g.members.map({ JS.str($0["addr"]) }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                p.address = addrSplit(addr, partnerName: best)
            }
            partners.append(p)
            for n in g.names { partnerByLower[n.trimmingCharacters(in: .whitespaces).lowercased()] = p.id }
        }

        // Verträge
        var contractIDs: [String: UUID] = [:]
        var contractsOut: [Contract] = []
        for (k, c) in cObjs {
            let id = UUID()
            contractIDs[k] = id
            var x = Contract(id: id)
            x.label = JS.str(c["label"])
            if let gi = contractGroup[k] { x.partnerID = partners[gi].id }
            let cat = JS.str(c["cat"])
            if !cat.isEmpty { x.categoryID = categories.first { $0.name == cat }?.id }
            x.amount = JS.finiteOr(c["amount"], 0)
            x.currency = Currency(rawValue: JS.str(c["cur"])) ?? .CHF
            x.cycle = webCycle(c["cycle"])
            x.due = Day(iso: JS.str(c["due"]))
            x.start = Day(iso: JS.str(c["start"]))
            x.end = Day(iso: JS.str(c["end"]))
            x.notice = JS.intOr(c["notice"], 0)
            x.noticeUnit = NoticeUnit(rawValue: JS.str(c["noticeU"])) ?? .months
            x.renewMonths = JS.intOr(c["renew"], 0)
            x.cancelTerm = CancelTerm(rawValue: JS.str(c["cancTerm"])) ?? .anytime
            x.mandatory = JS.truthy(c["mand"])
            x.noWatch = JS.truthy(c["noWatch"])
            x.customerNo = JS.str(c["custNo"])
            x.contractNo = JS.str(c["contrNo"])
            var hs: [UUID] = []
            for h in JS.arr(c["holders"]) { if let pid = personIDs[JS.str(h)], !hs.contains(pid) { hs.append(pid) } }
            x.holderIDs = hs
            // Aufteilung {Inhabername: Prozent} → Personen-IDs; unvollständig → gleich
            if let spo = JS.obj(c["split"]), hs.count >= 2 {
                var sp: [SplitShare] = []
                for h in JS.arr(c["holders"]) {
                    let name = JS.str(h)
                    if let pid = personIDs[name], !sp.contains(where: { $0.personID == pid }) { sp.append(SplitShare(personID: pid, percent: JS.intOr(spo[name], -1))) }
                }
                x.split = sp.count == hs.count && sp.allSatisfy({ $0.percent >= 0 }) ? AppData.normalizedSplit(sp, holders: hs) : []
            }
            if let rv = JS.obj(c["review"]), let d = Day(iso: JS.str(rv["at"])), let v = ReviewVerdict(rawValue: JS.str(rv["v"])) {
                x.review = ContractReview(verdict: v, at: d)
            }
            x.payMethod = JS.str(c["payM"])
            x.payAccount = JS.str(c["payA"])
            x.cancelChannel = CancelChannel(webText: JS.str(c["cancF"]))
            x.cancelURL = JS.str(c["cancUrl"])
            x.trial = Day(iso: JS.str(c["trial"]))
            x.trialKept = Day(iso: JS.str(c["trialKept"]))
            x.tel = JS.str(c["tel"])
            x.mail = JS.str(c["mail"])
            x.note = JS.str(c["note"])
            let col = JS.str(c["color"])
            x.colorHex = col.isEmpty ? nil : col
            if x.partnerID == nil {
                let l = JS.str(c["logoId"])
                if !l.isEmpty {
                    x.logoID = l
                    let bg = JS.str(c["logoBg"])
                    x.logoBg = bg.isEmpty ? nil : bg
                }
            }
            x.prices = prices(c["prices"])
            x.documents = JS.arr(c["docs"]).compactMap { JS.obj($0) }.compactMap { d -> Attachment? in
                let did = JS.str(d["id"])
                return did.isEmpty ? nil : Attachment(id: did, name: JS.str(d["name"]), type: JS.str(d["type"]))
            }
            x.extras = JS.arr(c["extras"]).compactMap { JS.obj($0) }.compactMap { e -> ExtraPayment? in
                guard let d = Day(iso: JS.str(e["date"])) else { return nil }
                let a = JS.num(e["amount"])
                if !a.isFinite || a == 0 { return nil }
                return ExtraPayment(date: d, amount: a, note: JS.str(e["note"]))
            }
            x.status = JS.str(c["status"]) == "cancelled" ? .cancelled : .active
            x.cancelledAt = Day(iso: JS.str(c["cancelledAt"]))
            x.cancelPer = Day(iso: JS.str(c["cancelPer"]))
            x.cancelledOn = Day(iso: JS.str(c["cancelledOn"]))
            x.keptFor = Day(iso: JS.str(c["keptFor"]))
            if JS.truthy(c["paused"]) {
                x.pauses = [Pause(from: Day(iso: JS.str(c["pausedAt"])) ?? today, until: Day(iso: JS.str(c["pausedUntil"])))]
            }
            x.createdAt = createdAt(c["t"])
            contractsOut.append(x)
        }

        // Einnahmen
        var incomeIDs: [String: UUID] = [:]
        var incomesOut: [Income] = []
        for (k, c) in iObjs {
            let id = UUID()
            incomeIDs[k] = id
            var x = Income(id: id)
            x.name = JS.str(c["name"])
            x.label = JS.str(c["label"])
            x.kind = IncomeKind(webName: JS.str(c["cat"])) ?? .lohn
            x.amount = JS.finiteOr(c["amount"], 0)
            x.currency = Currency(rawValue: JS.str(c["cur"])) ?? .CHF
            x.cycle = webCycle(c["cycle"])
            x.due = Day(iso: JS.str(c["due"]))
            x.start = Day(iso: JS.str(c["start"]))
            x.end = Day(iso: JS.str(c["end"]))
            var ih: [UUID] = []
            for h in JS.arr(c["holders"]) { if let pid = personIDs[JS.str(h)], !ih.contains(pid) { ih.append(pid) } }
            x.holderID = ih.first
            x.prices = prices(c["prices"])
            x.note = JS.str(c["note"])
            let l = JS.str(c["logoId"])
            if !l.isEmpty {
                x.logoID = l
                let bg = JS.str(c["logoBg"])
                x.logoBg = bg.isEmpty ? nil : bg
            }
            let col = JS.str(c["color"])
            x.colorHex = col.isEmpty ? nil : col
            x.createdAt = createdAt(c["t"])
            if ih.count > 1 {
                // Mehrere Inhaber (alte Daten): Web rechnet je Inhaber 1/n – hier je Inhaber eine Einnahme mit Betrag/n
                let n = Double(ih.count)
                for (j, h) in ih.enumerated() {
                    var y = x
                    if j > 0 { y.id = UUID() }
                    y.holderID = h
                    y.amount = x.amount / n
                    y.prices = x.prices.map { PriceChange(from: $0.from, amount: $0.amount / n) }
                    incomesOut.append(y)
                }
            } else {
                incomesOut.append(x)
            }
        }

        // Einstellungen
        var st = Settings()
        st.homeCurrency = Currency(rawValue: JS.str(s["home"])) ?? .CHF
        var rates: [String: Double] = [:]
        if let r = JS.obj(s["rates"]) {
            for k in r.orderedKeys {
                let v = JS.num(r[k])
                if v.isFinite && v > 0 { rates[k] = v }
            }
        }
        st.rates = rates
        st.rateDate = Day(iso: JS.str(s["rateDate"]))
        st.rateChecked = Day(iso: JS.str(s["rateChecked"]))
        st.rateSource = JS.str(s["rateSrc"])
        let th = JS.str(s["theme"])
        st.theme = th == "light" ? .light : (th == "dark" ? .dark : .auto)
        st.sort = ContractSort(webValue: JS.str(s["sort"]))
        st.onboarded = JS.intOr(s["onboarded"], 0)
        st.lastHolderIDs = JS.arr(s["lastHolders"]).compactMap { personIDs[JS.str($0)] }
        var ign: [String] = []
        if let q = JS.obj(s["qIgn"]) {
            for k in q.orderedKeys where JS.truthy(q[k]) {
                if let nk = mapQualityKey(k, contracts: contractIDs, incomes: incomeIDs, partners: partnerByLower, persons: personIDs), !ign.contains(nk) {
                    ign.append(nk)
                }
            }
        }
        st.qualityIgnored = ign
        st.lastReview = Day(iso: JS.str(s["lastReview"]))
        st.reviewSnooze = Day(iso: JS.str(s["reviewSnooze"]))
        st.dataVersion = Settings.currentDataVersion

        let data = AppData(settings: st, persons: persons, categories: categories, partners: partners, contracts: contractsOut, incomes: incomesOut)
        let exp = JS.str(o["exported"])
        return WebImportResult(data: data, files: files, contractIDs: contractIDs, incomeIDs: incomeIDs, personIDs: personIDs,
                               exported: exp.isEmpty ? nil : exp, failedFiles: failed)
    }

    /// Name des Vertragspartners eines Web-Vertrags. Ohne Vertragspartner, aber mit Adresse oder Website:
    /// Firma aus der Adresse, sonst Bezeichnung bzw. Domain (damit Adresse und Website nicht verloren gehen).
    static func partnerName(_ c: JSObject) -> String? {
        let pn = JS.str(c["partner"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !pn.isEmpty { return pn }
        let label = JS.str(c["label"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = JS.str(c["addr"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !addr.isEmpty {
            // Eine einzelne Zeile ohne Ziffer vor «PLZ Ort» gilt hier als Firma (es gibt keinen Namen zum Vergleich)
            let L = lines(addr)
            let firm = addrSplit(addr, partnerName: L.first).company
            if !firm.isEmpty { return firm }
            if !label.isEmpty { return label }
            // Ohne Bezeichnung: erste Adresszeile, damit die Adresse nicht verloren geht
            return L.first
        }
        let web = JS.str(c["web"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !web.isEmpty {
            if !label.isEmpty { return label }
            let d = Format.domain(of: web)
            return d.isEmpty ? nil : d
        }
        return nil
    }

    /// Turnus: 0 bzw. "0" = einmalig, sonst `+x||1`.
    static func webCycle(_ v: JSValue?) -> Int {
        if let v = v {
            if case .number(let n) = v, n == 0 { return 0 }
            if case .string(let t) = v, t == "0" { return 0 }
        }
        return JS.intOr(v, 1)
    }

    static func prices(_ v: JSValue?) -> [PriceChange] {
        JS.arr(v).compactMap { JS.obj($0) }.compactMap { p -> PriceChange? in
            guard let d = Day(iso: JS.str(p["from"])) else { return nil }
            let a = JS.num(p["amount"])
            return a.isFinite ? PriceChange(from: d, amount: a) : nil
        }
    }

    static func createdAt(_ v: JSValue?) -> Date {
        let t = JS.num(v)
        return (t.isFinite && t > 0) ? Date(timeIntervalSince1970: t / 1000) : Date(timeIntervalSince1970: 0)
    }

    /// Bytes einer Data-URL («data:image/jpeg;base64,…»).
    public static func dataURLBytes(_ url: String) -> Data? {
        guard let comma = url.firstIndex(of: ",") else { return Data(base64Encoded: url, options: .ignoreUnknownCharacters) }
        return Data(base64Encoded: String(url[url.index(after: comma)...]), options: .ignoreUnknownCharacters)
    }

    /// Ignorieren-Schlüssel der Web-App auf neue IDs abbilden («c:<webId>:feld» → «c:<UUID>:feld» …).
    static func mapQualityKey(_ k: String, contracts: [String: UUID], incomes: [String: UUID], partners: [String: UUID], persons: [String: UUID]) -> String? {
        guard let first = k.firstIndex(of: ":"), let last = k.lastIndex(of: ":"), first < last else { return nil }
        let kind = String(k[k.startIndex..<first])
        let mid = String(k[k.index(after: first)..<last])
        let field = String(k[k.index(after: last)...])
        var id: UUID?
        switch kind {
        case "c": id = contracts[mid]
        case "i": id = incomes[mid]
        case "p": id = partners[mid]
        case "h": id = persons[mid]
        default: id = nil
        }
        guard let u = id else { return nil }
        return kind + ":" + u.uuidString + ":" + field
    }

    // MARK: Migrationen (migModel, migCats)

    static func migModel(_ s: inout JSObject, _ contracts: inout JSObject, _ incomes: inout JSObject) {
        if s["rate"] != nil {
            var rates = JS.obj(s["rates"]) ?? JSObject()
            let eur = JS.num(rates["EUR"])
            let rate = JS.num(s["rate"])
            if !(eur > 0) && rate > 0 { rates["EUR"] = .number(rate) }
            s["rates"] = .object(rates)
            s["rate"] = nil
        }
        func fixHolder(_ m: inout JSObject) {
            for k in m.orderedKeys {
                guard var c = JS.obj(m[k]), c["holder"] != nil else { continue }
                if JS.arr(c["holders"]).isEmpty && JS.truthy(c["holder"]) { c["holders"] = .array([c["holder"]!]) }
                c["holder"] = nil
                m[k] = .object(c)
            }
        }
        fixHolder(&contracts)
        fixHolder(&incomes)
        if s["sender"] != nil {
            if !JS.truthy(s["senderF"]) { s["senderF"] = .object(senderObject(senderParse(JS.str(s["sender"])))) }
            s["sender"] = nil
        }
        if JS.truthy(s["senderF"]) || JS.truthy(s["sig"]) {
            var hl = JS.arr(s["holders"]).map { JS.str($0) }
            if hl.isEmpty { hl = ["Ich"] }
            var fn = ""
            if let sf = JS.obj(s["senderF"]) { fn = JS.str(sf["first"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let h0 = hl.first { !fn.isEmpty && $0.lowercased() == fn } ?? hl[0]
            if JS.truthy(s["senderF"]) {
                var sa = JS.obj(s["senders"]) ?? JSObject()
                if !JS.truthy(sa[h0]) { sa[h0] = s["senderF"] }
                s["senders"] = .object(sa)
                s["senderF"] = nil
            }
            if JS.truthy(s["sig"]) {
                var sg = JS.obj(s["sigs"]) ?? JSObject()
                if !JS.truthy(sg[h0]) { sg[h0] = s["sig"] }
                s["sigs"] = .object(sg)
                s["sig"] = nil
            }
        }
    }

    static func migCats(_ s: inout JSObject, _ contracts: inout JSObject) {
        let mig = Category.legacyNames
        for k in contracts.orderedKeys {
            guard var c = JS.obj(contracts[k]) else { continue }
            if let n = mig[JS.str(c["cat"])] {
                c["cat"] = .string(n)
                contracts[k] = .object(c)
            }
        }
        if case .array(let list)? = s["catList"] {
            var seen = Set<String>()
            var out: [JSValue] = []
            for item in list {
                guard var x = JS.obj(item) else { out.append(item); continue }
                if let nn = mig[JS.str(x["n"])] { x["n"] = .string(nn) }
                let key = JS.str(x["n"])
                if seen.contains(key) { continue }
                seen.insert(key)
                // stabiler Schlüssel k = ursprünglicher Standardname
                if JS.str(x["k"]).isEmpty && Category.standardNames.contains(key) { x["k"] = .string(key) }
                out.append(.object(x))
            }
            s["catList"] = .array(out)
        }
        if case .array(let cats)? = s["cats"] {
            s["cats"] = .array(cats.filter { v in
                guard let x = JS.obj(v) else { return true }
                return mig[JS.str(x["n"])] == nil
            })
        }
    }

    /// Symbol-Schlüssel alter Kategorienamen (bei jedem Laden, unabhängig von der Datenversion).
    static func migCatIcons(_ s: inout JSObject) {
        guard case .array(let list)? = s["catList"] else { return }
        let mig = Category.legacyNames
        s["catList"] = .array(list.map { item in
            guard var x = JS.obj(item), let ni = mig[JS.str(x["i"])] else { return item }
            x["i"] = .string(ni)
            return .object(x)
        })
    }

    /// Wie Web `sanitizeImport`: ungültige Farben, Unterschriften (keine JPEG/PNG-Data-URL) und Avatar-IDs (keine 32-stellige Hex-ID) verwerfen.
    static func sanitize(_ s: inout JSObject, _ contracts: inout JSObject, _ incomes: inout JSObject) {
        func badCol(_ v: JSValue?) -> Bool {
            guard let v = v else { return false }
            if case .null = v { return false }
            if case .string(let t) = v, t.isEmpty { return false }
            return !RX.test("^#[0-9A-Fa-f]{3,8}$", JS.str(v))
        }
        func fixColors(_ m: inout JSObject) {
            for k in m.orderedKeys {
                guard var c = JS.obj(m[k]) else { continue }
                var ch = false
                for f in ["color", "logoBg"] where badCol(c[f]) {
                    c[f] = nil
                    ch = true
                }
                if ch { m[k] = .object(c) }
            }
        }
        fixColors(&contracts)
        fixColors(&incomes)
        let sigRX = "^data:image/(jpeg|png);base64,[A-Za-z0-9+/]*={0,2}$"
        if var sg = JS.obj(s["sigs"]), case .object = s["sigs"]! {
            for h in sg.orderedKeys where !RX.test(sigRX, JS.str(sg[h])) { sg[h] = nil }
            s["sigs"] = .object(sg)
        } else {
            s["sigs"] = nil
        }
        if s["sig"] != nil && !RX.test(sigRX, JS.str(s["sig"])) { s["sig"] = nil }
        if case .array(let list)? = s["catList"] {
            s["catList"] = .array(list.compactMap { item -> JSValue? in
                guard case .object(var x) = item else { return nil }
                if badCol(x["c"]) { x["c"] = nil }
                return .object(x)
            })
        }
        if var av = JS.obj(s["avatars"]), case .object = s["avatars"]! {
            for h in av.orderedKeys where !RX.test("^[0-9a-fA-F]{32}$", JS.str(av[h])) { av[h] = nil }
            s["avatars"] = .object(av)
        } else {
            s["avatars"] = nil
        }
    }

    static func senderObject(_ a: SenderAddress) -> JSObject {
        var o = JSObject()
        o["first"] = .string(a.first)
        o["last"] = .string(a.last)
        o["street"] = .string(a.street)
        o["zip"] = .string(a.zip)
        o["city"] = .string(a.city)
        o["country"] = .string(a.country)
        return o
    }

    // MARK: Freitext-Adressen

    static let zipLine = "^(?:[A-Z]{1,2}-?)?\\d{4,5}\\s+\\S"

    static func lines(_ t: String) -> [String] {
        t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Absender aus Freitext (`senderParse`): Zeile 1 Name (letztes Wort Nachname), Zeile mit «PLZ Ort» erkannt.
    public static func senderParse(_ t: String) -> SenderAddress {
        var o = SenderAddress()
        let L = lines(t)
        let zi = L.firstIndex { RX.test(zipLine, $0) } ?? -1
        if !L.isEmpty && zi != 0 {
            var w = L[0].split(whereSeparator: { $0.isWhitespace }).map(String.init)
            o.last = w.count > 1 ? w.removeLast() : ""
            o.first = w.joined(separator: " ")
        }
        if zi >= 0 {
            if let m = RX.match("^(?:[A-Z]{1,2}-?)?(\\d{4,5})\\s+(.+)$", L[zi]) {
                o.zip = m[1] ?? ""
                o.city = m[2] ?? ""
            }
            o.street = zi > 1 ? L[1..<zi].joined(separator: ", ") : ""
            o.country = L.count > zi + 1 ? L[(zi + 1)...].joined(separator: ", ") : ""
        } else {
            o.street = L.count > 1 ? L[1...].joined(separator: ", ") : ""
        }
        return o
    }

    /// Adresse aus Freitext (`addrSplit`) mit den Korrekturen aus Fund N8: Länderpräfix der PLZ bleibt («D-78462»),
    /// ohne PLZ-Zeile Firma = erste, Strasse = letzte Zeile, Zusatz dazwischen; eine einzelne Zeile vor der PLZ ohne Ziffer,
    /// die dem Vertragspartner ähnelt, ist die Firma (sonst die Strasse).
    public static func addrSplit(_ t: String, partnerName: String? = nil) -> PostalAddress {
        var o = PostalAddress()
        let L = lines(t)
        guard let zi = L.firstIndex(where: { RX.test(zipLine, $0) }) else {
            o.company = L.first ?? ""
            if L.count >= 2 {
                o.street = L[L.count - 1]
                if L.count > 2 { o.extra = L[1..<(L.count - 1)].joined(separator: ", ") }
            }
            return o
        }
        if let m = RX.match("^((?:[A-Z]{1,2}-?)?)(\\d{4,5})\\s+(.+)$", L[zi]) {
            o.zip = (m[1] ?? "") + (m[2] ?? "")
            o.city = m[3] ?? ""
        }
        o.country = L.count > zi + 1 ? L[(zi + 1)...].joined(separator: ", ") : ""
        var pre = Array(L[0..<zi])
        // Wie Web: eine einzelne Zeile ohne Ziffer, die dem Vertragspartner entspricht (lnorm-Enthaltensein), ist die Firma; sonst Strasse
        if pre.count == 1 {
            let line = pre[0]
            let hasDigit = line.contains { $0.isNumber }
            let nn = Partners.lnorm(partnerName ?? "")
            let ln0 = Partners.lnorm(line)
            if !hasDigit && !nn.isEmpty && !ln0.isEmpty && (ln0.contains(nn) || nn.contains(ln0)) {
                o.company = line
                return o
            }
        }
        if !pre.isEmpty { o.street = pre.removeLast() }
        if !pre.isEmpty { o.company = pre.removeFirst() }
        o.extra = pre.joined(separator: ", ")
        return o
    }
}

// MARK: - JSON mit Schlüsselreihenfolge und JS-Umwandlungen

/// JS-Objekt: Schlüssel in Einfügereihenfolge (`orderedKeys` wie `Object.keys`).
struct JSObject {
    private(set) var keys: [String] = []
    private var values: [String: JSValue] = [:]

    subscript(key: String) -> JSValue? {
        get { values[key] }
        set {
            if let v = newValue {
                if values[key] == nil { keys.append(key) }
                values[key] = v
            } else if values[key] != nil {
                values[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Wie `Object.keys`: ganzzahlige Schlüssel aufsteigend zuerst, dann die übrigen in Einfügereihenfolge.
    var orderedKeys: [String] {
        let ints = keys.filter { JSObject.isIndex($0) }.sorted { (UInt64($0) ?? 0) < (UInt64($1) ?? 0) }
        let rest = keys.filter { !JSObject.isIndex($0) }
        return ints + rest
    }

    static func isIndex(_ k: String) -> Bool {
        guard !k.isEmpty, k.count <= 10, k.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        if k.count > 1 && k.hasPrefix("0") { return false }
        return (UInt64(k) ?? UInt64.max) < 4_294_967_295
    }
}

enum JSValue {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSValue])
    case object(JSObject)
}

/// Umwandlungen wie in JavaScript.
enum JS {
    /// Wahrheitswert
    static func truthy(_ v: JSValue?) -> Bool {
        guard let v = v else { return false }
        switch v {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// Unäres Plus (`+x`): undefined → NaN, null → 0, "" → 0, ungültig → NaN.
    static func num(_ v: JSValue?) -> Double {
        guard let v = v else { return .nan }
        switch v {
        case .null: return 0
        case .bool(let b): return b ? 1 : 0
        case .number(let n): return n
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }
            if t == "Infinity" || t == "+Infinity" { return .infinity }
            if t == "-Infinity" { return -.infinity }
            let lower = t.lowercased()
            if lower.contains("inf") || lower.contains("nan") || lower.hasPrefix("0x") || lower.hasPrefix("-0x") || lower.hasPrefix("+0x") { return .nan }
            return Double(t) ?? .nan
        case .array(let a):
            if a.isEmpty { return 0 }
            if a.count == 1 { return num(a[0]) }
            return .nan
        case .object: return .nan
        }
    }

    /// `+x||def` als Ganzzahl (abgeschnitten).
    static func intOr(_ v: JSValue?, _ def: Int) -> Int {
        let n = num(v)
        if n.isNaN || n == 0 || !n.isFinite || Swift.abs(n) > 1e9 { return def }
        return Int(n)
    }

    /// `+x||def` als Zahl.
    static func finiteOr(_ v: JSValue?, _ def: Double) -> Double {
        let n = num(v)
        return (n.isFinite && n != 0) ? n : def
    }

    /// `String(x||"")`
    static func str(_ v: JSValue?) -> String {
        guard let v = v, truthy(v) else { return "" }
        switch v {
        case .string(let s): return s
        case .number(let n): return numberString(n)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return a.map { x -> String in
            if case .null = x { return "" }
            return str(x)
        }.joined(separator: ",")
        case .object: return "[object Object]"
        case .null: return ""
        }
    }

    /// Zahl als Text wie JS (ganze Zahlen ohne «.0»).
    static func numberString(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n == n.rounded(.towardZero) && Swift.abs(n) < 1e15 { return String(Int64(n)) }
        return "\(n)"
    }

    static func arr(_ v: JSValue?) -> [JSValue] {
        if case .array(let a)? = v { return a }
        return []
    }

    static func obj(_ v: JSValue?) -> JSObject? {
        guard let v = v else { return nil }
        switch v {
        case .object(let o): return o
        case .array(let a):
            var o = JSObject()
            for (i, x) in a.enumerated() { o[String(i)] = x }
            return o
        default: return nil
        }
    }
}

/// Kleiner JSON-Leser, der die Schlüsselreihenfolge erhält.
struct JSONParser {
    struct ParseError: Error {}

    private let b: [UInt8]
    private var i = 0

    private init(_ data: Data) {
        b = [UInt8](data)
        if b.count >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF { i = 3 }
    }

    static func parse(_ data: Data) throws -> JSValue {
        var p = JSONParser(data)
        p.skipWS()
        let v = try p.value()
        p.skipWS()
        if p.i != p.b.count { throw ParseError() }
        return v
    }

    private mutating func skipWS() {
        while i < b.count && (b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09) { i += 1 }
    }

    private mutating func value() throws -> JSValue {
        skipWS()
        guard i < b.count else { throw ParseError() }
        switch b[i] {
        case 0x7B: return .object(try object())
        case 0x5B: return .array(try array())
        case 0x22: return .string(try string())
        case 0x74:
            try literal("true")
            return .bool(true)
        case 0x66:
            try literal("false")
            return .bool(false)
        case 0x6E:
            try literal("null")
            return .null
        default:
            return .number(try number())
        }
    }

    private mutating func literal(_ s: String) throws {
        let u = Array(s.utf8)
        guard i + u.count <= b.count, Array(b[i..<(i + u.count)]) == u else { throw ParseError() }
        i += u.count
    }

    private mutating func object() throws -> JSObject {
        var o = JSObject()
        i += 1
        skipWS()
        if i < b.count && b[i] == 0x7D {
            i += 1
            return o
        }
        while true {
            skipWS()
            guard i < b.count, b[i] == 0x22 else { throw ParseError() }
            let k = try string()
            skipWS()
            guard i < b.count, b[i] == 0x3A else { throw ParseError() }
            i += 1
            let v = try value()
            o[k] = v
            skipWS()
            guard i < b.count else { throw ParseError() }
            if b[i] == 0x2C {
                i += 1
                continue
            }
            if b[i] == 0x7D {
                i += 1
                return o
            }
            throw ParseError()
        }
    }

    private mutating func array() throws -> [JSValue] {
        var a: [JSValue] = []
        i += 1
        skipWS()
        if i < b.count && b[i] == 0x5D {
            i += 1
            return a
        }
        while true {
            a.append(try value())
            skipWS()
            guard i < b.count else { throw ParseError() }
            if b[i] == 0x2C {
                i += 1
                continue
            }
            if b[i] == 0x5D {
                i += 1
                return a
            }
            throw ParseError()
        }
    }

    private mutating func hex4() throws -> UInt32 {
        guard i + 4 <= b.count else { throw ParseError() }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let c = b[i]
            var d: UInt32
            switch c {
            case 0x30...0x39: d = UInt32(c - 0x30)
            case 0x41...0x46: d = UInt32(c - 0x41 + 10)
            case 0x61...0x66: d = UInt32(c - 0x61 + 10)
            default: throw ParseError()
            }
            v = v * 16 + d
            i += 1
        }
        return v
    }

    private mutating func string() throws -> String {
        i += 1
        var buf: [UInt8] = []
        while true {
            guard i < b.count else { throw ParseError() }
            let c = b[i]
            if c == 0x22 {
                i += 1
                break
            }
            if c == 0x5C {
                i += 1
                guard i < b.count else { throw ParseError() }
                let e = b[i]
                i += 1
                switch e {
                case 0x22: buf.append(0x22)
                case 0x5C: buf.append(0x5C)
                case 0x2F: buf.append(0x2F)
                case 0x62: buf.append(0x08)
                case 0x66: buf.append(0x0C)
                case 0x6E: buf.append(0x0A)
                case 0x72: buf.append(0x0D)
                case 0x74: buf.append(0x09)
                case 0x75:
                    var cp = try hex4()
                    if cp >= 0xD800 && cp <= 0xDBFF {
                        if i + 6 <= b.count && b[i] == 0x5C && b[i + 1] == 0x75 {
                            let save = i
                            i += 2
                            let lo = try hex4()
                            if lo >= 0xDC00 && lo <= 0xDFFF {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                            } else {
                                i = save
                                cp = 0xFFFD
                            }
                        } else {
                            cp = 0xFFFD
                        }
                    } else if cp >= 0xDC00 && cp <= 0xDFFF {
                        cp = 0xFFFD
                    }
                    let ch: String = Unicode.Scalar(cp).map { String(Character($0)) } ?? "\u{FFFD}"
                    buf.append(contentsOf: Array(ch.utf8))
                default:
                    throw ParseError()
                }
                continue
            }
            buf.append(c)
            i += 1
        }
        return String(decoding: buf, as: UTF8.self)
    }

    private mutating func number() throws -> Double {
        let start = i
        while i < b.count {
            let c = b[i]
            if (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E || c == 0x65 || c == 0x45 {
                i += 1
            } else {
                break
            }
        }
        guard i > start, let v = Double(String(decoding: b[start..<i], as: UTF8.self)) else { throw ParseError() }
        return v
    }
}
