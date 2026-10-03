import SwiftUI
import KontivoCore

struct AddressCandidate: Identifiable, Hashable {
    var id = UUID()
    /// Zeilen: Firma, Strasse, PLZ Ort, ggf. Land
    var lines: [String]
    /// Quelle, z.B. «Wikidata» oder «OpenStreetMap»
    var source: String
}

/// Adresssuche für Vertragspartner (Wikidata + OpenStreetMap/Nominatim wie findAddresses in der Web-App).
/// Beide Quellen laufen parallel mit Zeitlimit; Ergebnis bis zu 5 Kandidaten ohne Doppel. Nur Vorschläge.
enum AddressSearch {
    /// Nominatim verlangt eine Kennung der App (keine Standard-Kennung einer Bibliothek).
    static let userAgent = "Kontivo/1.0 (iOS-App; Vertragsverwaltung)"
    private static let wikidataBase = "https://www.wikidata.org/w/api.php"
    private static let nominatimBase = "https://nominatim.openstreetmap.org/search"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
        return URLSession(configuration: cfg)
    }()

    static func find(name: String, domain: String, currency: Currency) async -> [AddressCandidate] {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return [] }
        let cc = currency == .EUR ? "de,at,ch" : "ch,de,at"
        async let wd = wikidata(name: n, domain: domain.trimmingCharacters(in: .whitespaces))
        async let osm = nominatim(name: n, countries: cc)
        let all = await wd + osm
        var seen = Set<String>()
        var out: [AddressCandidate] = []
        for c in all {
            let key = c.lines.dropFirst().joined(separator: "|").lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(c)
        }
        return Array(out.prefix(5))
    }

    // MARK: Netzwerk

    private static func url(_ base: String, _ items: [(String, String)]) -> URL? {
        var comps = URLComponents(string: base)
        comps?.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        // «+» würde sonst als Leerzeichen gelesen
        if let q = comps?.percentEncodedQuery { comps?.percentEncodedQuery = q.replacingOccurrences(of: "+", with: "%2B") }
        return comps?.url
    }

    private static func json(_ url: URL?) async -> Any? {
        guard let url else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    // MARK: Wikidata (Sitz: P6375 Strasse, P281 PLZ, P159 Sitz → Ort)

    /// Werte einer Eigenschaft ohne Rang «deprecated» (`wclaims`): Entität → «Q…», sonst Rohwert (Text oder Objekt).
    private static func claims(_ entity: [String: Any], _ prop: String) -> [Any] {
        guard let cl = entity["claims"] as? [String: Any], let arr = cl[prop] as? [[String: Any]] else { return [] }
        var out: [Any] = []
        for c in arr {
            if (c["rank"] as? String) == "deprecated" { continue }
            guard let snak = c["mainsnak"] as? [String: Any], let dv = snak["datavalue"] as? [String: Any], let v = dv["value"] else { continue }
            if let o = v as? [String: Any], let id = o["id"] as? String {
                out.append(id)
            } else if let s = v as? String {
                if !s.isEmpty { out.append(s) }
            } else {
                out.append(v)
            }
        }
        return out
    }

    private static func label(_ entity: [String: Any]?) -> String? {
        guard let labels = entity?["labels"] as? [String: Any] else { return nil }
        for lang in ["de", "en"] {
            if let l = labels[lang] as? [String: Any], let v = l["value"] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    private static func wikidata(name: String, domain: String) async -> [AddressCandidate] {
        let search = await json(url(wikidataBase, [("format", "json"), ("origin", "*"), ("action", "wbsearchentities"), ("type", "item"),
                                                  ("limit", "6"), ("language", "de"), ("uselang", "de"), ("search", name)]))
        guard let s = search as? [String: Any], let hits = s["search"] as? [[String: Any]] else { return [] }
        let ids = hits.compactMap { $0["id"] as? String }
        if ids.isEmpty { return [] }
        let ents = await json(url(wikidataBase, [("format", "json"), ("origin", "*"), ("action", "wbgetentities"), ("props", "claims|labels"),
                                                ("languages", "de|en"), ("ids", ids.joined(separator: "|"))]))
        guard let e = ents as? [String: Any], let entities = e["entities"] as? [String: Any] else { return [] }
        let wantDom = domain.isEmpty ? "" : Partners.regDom(domain)

        struct Hit { var label: String; var street: String; var zip: String; var hq: String }
        var hits2: [Hit] = []
        for id in ids {
            guard let en = entities[id] as? [String: Any] else { continue }
            let sites = claims(en, "P856").compactMap { $0 as? String }.map { Format.domain(of: $0) }.filter { !$0.isEmpty }
            if !wantDom.isEmpty && !sites.isEmpty && !sites.contains(where: { Partners.regDom($0) == wantDom }) { continue }
            let streets: [String] = claims(en, "P6375").compactMap { v in
                if let o = v as? [String: Any], let t = o["text"] as? String { return t }
                return v as? String
            }
            guard let street = streets.first(where: { !$0.isEmpty }) else { continue }
            let zip = claims(en, "P281").compactMap { $0 as? String }.first ?? ""
            let hq = claims(en, "P159").first as? String ?? ""
            hits2.append(Hit(label: label(en) ?? name, street: street, zip: zip, hq: hq))
        }
        if hits2.isEmpty { return [] }
        var cities: [String: String] = [:]
        let hqIDs = Array(Set(hits2.map { $0.hq }.filter { $0.hasPrefix("Q") }))
        if !hqIDs.isEmpty {
            let l = await json(url(wikidataBase, [("format", "json"), ("origin", "*"), ("action", "wbgetentities"), ("props", "labels"),
                                                 ("languages", "de|en"), ("ids", hqIDs.joined(separator: "|"))]))
            if let lo = l as? [String: Any], let le = lo["entities"] as? [String: Any] {
                for q in hqIDs { if let v = label(le[q] as? [String: Any]) { cities[q] = v } }
            }
        }
        return hits2.map { h in
            let zipCity = [h.zip, cities[h.hq] ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            return AddressCandidate(lines: [h.label, h.street, zipCity].filter { !$0.isEmpty }, source: "Wikidata")
        }
    }

    // MARK: OpenStreetMap / Nominatim (Firmenstandorte mit Namensabgleich)

    private static func nominatim(name: String, countries: String) async -> [AddressCandidate] {
        let r = await json(url(nominatimBase, [("format", "jsonv2"), ("addressdetails", "1"), ("limit", "6"), ("accept-language", "de"),
                                              ("countrycodes", countries), ("q", name)]))
        guard let arr = r as? [[String: Any]] else { return [] }
        let want = Partners.ltok(name)
        var out: [AddressCandidate] = []
        for h in arr {
            let a = h["address"] as? [String: Any] ?? [:]
            func s(_ k: String) -> String { (a[k] as? String) ?? "" }
            var nm = (h["name"] as? String) ?? ""
            if nm.isEmpty { nm = s("office") }
            if nm.isEmpty { nm = s("shop") }
            if nm.isEmpty { nm = s("amenity") }
            if nm.isEmpty || !Partners.nameHas(want, nm) { continue }
            let street = [s("road"), s("house_number")].filter { !$0.isEmpty }.joined(separator: " ")
            var city = s("city")
            if city.isEmpty { city = s("town") }
            if city.isEmpty { city = s("village") }
            if city.isEmpty { city = s("municipality") }
            let zip = s("postcode")
            if street.isEmpty || zip.isEmpty { continue }
            let type = (h["type"] as? String) ?? ""
            out.append(AddressCandidate(lines: [nm, street, zip + " " + city], source: "OpenStreetMap" + (type.isEmpty ? "" : " · " + type)))
        }
        return out
    }
}

/// Auswahlliste der gefundenen Adressen («Adresse wählen»). Tippen übernimmt und schliesst.
struct AddressPickSheet: View {
    let candidates: [AddressCandidate]
    let onPick: (AddressCandidate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { c in
                        Button {
                            onPick(c)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(c.lines.enumerated()), id: \.offset) { item in
                                    Text(item.element)
                                        .font(item.offset == 0 ? .body.weight(.semibold) : .body)
                                        .foregroundStyle(KColor.ink)
                                }
                                Text(c.source)
                                    .font(.caption)
                                    .italic()
                                    .foregroundStyle(KColor.ink2)
                                    .padding(.top, 2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Quellen: Wikidata und OpenStreetMap, ohne Gewähr. Bei mehreren Standorten den Hauptsitz oder Kundendienst wählen.")
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper.ignoresSafeArea())
            .navigationTitle("Adresse wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
