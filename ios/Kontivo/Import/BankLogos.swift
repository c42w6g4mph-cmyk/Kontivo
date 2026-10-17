import SwiftUI
import KontivoCore

/// Logos zu den Vorschlägen im Hintergrund suchen (Web v177/v184/v188 `bkLogos`): startet schon in der Ladeanzeige, 2 gleichzeitig
/// (mehr führt bei den Gratis-Diensten zu Absagen). Genau wie beim einzelnen Vertrag: Katalog-Anbieter über das Website-Symbol,
/// sonst Suche mit dem Katalognamen, sonst Suche mit Vertragspartner (Bezeichnung als Ersatz). Nur Firmennamen gehen ins Netz.
/// Gefundenes Logo steht in der Liste – mit «übernehmen» bestätigt, im Formular änderbar.
@MainActor
enum BankLogos {
    /// Ein Eintrag der Warteschlange
    private enum Target {
        case item(String)
        case inc(String)
    }

    static func run(_ r: BankReview, model: AppModel, isCurrent: @escaping () -> Bool) async {
        var q: [Target] = []
        for it in r.items where !it.s.ignored && it.logo == nil && usable(name: it.ed.name, tpl: it.s.catalog) { q.append(.item(it.id)) }
        for it in r.inc where it.logo == nil && usable(name: it.ed.name, tpl: nil) { q.append(.inc(it.id)) }
        r.logoDone = 0
        r.logoTotal = q.count
        if q.isEmpty { return }
        #if DEBUG
        // UI-Tests und Bildschirmfotos ohne Netz-Zufall
        if model.uiTestMode {
            r.logoTotal = 0
            return
        }
        #endif
        if !(await NetCheck.isOnline()) {
            r.logoTotal = 0
            return
        }
        let box = Queue(q)
        async let a: Void = worker(box, r, model: model, isCurrent: isCurrent)
        async let b: Void = worker(box, r, model: model, isCurrent: isCurrent)
        _ = await (a, b)
    }

    /// Gemeinsame Warteschlange der beiden Arbeiter
    private final class Queue {
        let items: [Target]
        var next = 0
        init(_ items: [Target]) { self.items = items }
    }

    private static func worker(_ box: Queue, _ r: BankReview, model: AppModel, isCurrent: @escaping () -> Bool) async {
        while box.next < box.items.count && isCurrent() {
            let t = box.items[box.next]
            box.next += 1
            await one(t, r, model: model, isCurrent: isCurrent)
        }
    }

    private static func usable(name: String, tpl: CatalogEntry?) -> Bool {
        if Partners.lusable(name) { return true }
        guard let t = tpl else { return false }
        return !t.web.isEmpty || Partners.lusable(t.name)
    }

    private static func one(_ t: Target, _ r: BankReview, model: AppModel, isCurrent: () -> Bool) async {
        var name = "", label = "", cur = Currency.CHF
        var tpl: CatalogEntry?
        switch t {
        case .item(let id):
            guard let i = r.index(id) else { return }
            name = r.items[i].ed.name
            label = r.items[i].ed.label
            cur = Currency(rawValue: r.items[i].s.currency) ?? .CHF
            tpl = r.items[i].s.catalog
        case .inc(let id):
            guard let i = r.incIndex(id) else { return }
            name = r.inc[i].ed.name
            label = r.inc[i].ed.label
            cur = Currency(rawValue: r.inc[i].s.currency) ?? .CHF
        }
        var got: (id: String, bg: String)?
        if let t = tpl {
            if !t.web.isEmpty, let sc = await LogoFinder.siteCand(Partners.regDom(Format.domain(of: t.web)), score: 3) {
                got = await store(sc, model: model)
            }
            if got == nil && Partners.lusable(t.name), let a = await LogoFinder.autoLogo(name: t.name, currency: cur, alt: nil, web: t.web) {
                got = store(a.0, a.1, model: model)
            }
        }
        if got == nil, let a = await LogoFinder.autoLogo(name: name, currency: cur, alt: label, web: tpl?.web ?? "") {
            got = store(a.0, a.1, model: model)
        }
        if !isCurrent() {
            if let g = got { drop(g.id, model: model) }
            return
        }
        if let g = got {
            switch t {
            case .item(let id):
                if let i = r.index(id), r.items[i].logo == nil, r.items[i].over == nil { r.items[i].logo = BankLogo(id: g.id, bg: g.bg) }
            case .inc(let id):
                if let i = r.incIndex(id), r.inc[i].logo == nil, r.inc[i].over == nil { r.inc[i].logo = BankLogo(id: g.id, bg: g.bg) }
            }
        }
        r.logoDone += 1
    }

    /// Kandidat übernehmen und speichern (Web `takeLogo` mit `LOGO_TAKEN`: gleiche Adresse nur einmal laden)
    private static func store(_ c: LogoCandidate, model: AppModel) async -> (id: String, bg: String)? {
        if let hit = LogoCache.shared.storedLogo(c.url, model: model) { return hit }
        guard case .success(let img) = await LogoFinder.take(c) else { return nil }
        return store(c, img, model: model)
    }

    private static func store(_ c: LogoCandidate, _ img: LogoImage, model: AppModel) -> (id: String, bg: String)? {
        if let hit = LogoCache.shared.storedLogo(c.url, model: model) { return hit }
        guard let id = try? model.files.put(img.png, type: "image/png") else { return nil }
        let v = (id: id, bg: img.background)
        LogoCache.shared.setStored(c.url, v)
        return v
    }

    /// Logo-Datei löschen, wenn sie nirgends verwendet wird (Web `bkDropLogo`)
    static func drop(_ id: String, model: AppModel) {
        if model.data.referencedFileIDs.contains(id) { return }
        model.files.delete(id)
    }
}
