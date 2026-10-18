import SwiftUI
import KontivoCore

// Sonderkündigung bei Preiserhöhung (Web v205–v209 `isKvg`/`skrRule`/`skrInfo`/`openSkr`, Stand v224):
// kurze Zeile im Detail («Sonderkündigung möglich · bis 30.11.») und Erklärblatt mit Einleitung, Eckdaten
// (Neuer Preis / Kündigen bis / Vertrag endet), «Gut zu wissen» und Grundlage. Regeln nach Land (Währung) und Kategorie.
//
// TODO core-API: Bereich core baut `Calc.specialCancel(_:)` / `SpecialCancelInfo` / `SpecialCancelSheet` (SpecialCancel.swift).
// Bei der Integration `CTSpecialCancel.info(calc, c)` → `calc.specialCancel(c)` und `CTSpecialCancel.sheet(…)` → Kern-Blatt
// ersetzen und diese lokale Logik löschen (Texte und Regeln sind 1:1 dieselben).

struct CTSkrRule {
    var until: Day?
    var untilMin = false
    var end: Day?
    var endMin = false
    var endText: String?
    var when: String?
    var source: String?
    var none = false
    var tips: [String]
}

struct CTSkrInfo {
    var from: Day
    var amount: Double
    var previous: Double
    var percent: Int
    var rule: CTSkrRule
    var head: String
    var tail: String
}

struct CTSkrRow: Identifiable {
    var key: String
    var value: String
    var sub: String
    var accent: Bool
    var id: String { key }
}

struct CTSkrSheetData {
    var title: String
    var intro: String
    var rows: [CTSkrRow]
    var tips: [String]
    var footer: String
}

enum CTSpecialCancel {
    private static func rx(_ pattern: String, _ s: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func weekday(_ d: Day) -> Int {
        Calendar(identifier: .gregorian).component(.weekday, from: d.date()) - 1 // 0 = Sonntag wie JS getDay()
    }

    /// Web `isKvg`
    static func isKvg(_ c: Contract, calc: Calc, data: AppData) -> Bool {
        let t = [c.label, calc.partnerName(c), data.category(c.categoryID)?.name ?? ""].joined(separator: " ")
        return c.currency == .CHF && rx("krankenkass|krankenversich|grundversich|kvg", t) && !rx("zusatz|spital|vvg", t)
    }

    /// Web `skrRule(c, f)`
    static func rule(_ c: Contract, from f: Day, calc: Calc, data: AppData) -> CTSkrRule {
        let k = calc.categoryKind(c)
        let de = c.currency == .EUR
        let pn = calc.partnerName(c)
        let P = pn.isEmpty ? "dem Vertragspartner" : pn
        let dayB = f.addingDays(-1)
        let lp = [c.label, pn].joined(separator: " ")
        if isKvg(c, calc: calc, data: data) && f.month == 1 && f.day == 1 {
            var ku = Day(f.year, f.month - 1, 0)
            while weekday(ku) == 0 || weekday(ku) == 6 { ku = ku.addingDays(-1) }
            return CTSkrRule(until: ku, end: dayB, source: "Art. 7 Abs. 2 KVG", tips: [
                "Oft kündigt die neue Krankenkasse für dich: Du unterschreibst die vorbereitete Kündigung, sie leitet sie weiter. Kurz vor Ende November besser selbst kündigen.",
                "Die Kündigung muss bis dann bei " + P + " eintreffen – am besten eingeschrieben.",
                "Sie gilt erst, wenn die neue Krankenkasse deine Aufnahme bestätigt hat.",
            ])
        }
        if de && k == .energy && !rx("wasser", lp) {
            return CTSkrRule(until: dayB, end: dayB, source: "§ 41 Abs. 5 EnWG", tips: [
                "Ohne Kündigungsfrist – die Kündigung muss vor dem neuen Preis eintreffen.",
                "Kündige selbst, nicht über den neuen Anbieter.",
            ])
        }
        if de && k == .telecom {
            return CTSkrRule(until: f.addingMonths(1).addingDays(-1), untilMin: true, end: dayB, endMin: true, source: "§ 57 Abs. 1 TKG", tips: [
                "Genau gilt: 3 Monate nach Erhalt der Mitteilung. Das angezeigte Datum ist das früheste mögliche Ende dieser Frist.",
            ])
        }
        if de && calc.isRent(c) {
            return CTSkrRule(endText: "Ende des übernächsten Monats", when: "Ende des 2. Monats nach Erhalt der Mitteilung",
                             source: "§ 561 BGB", tips: ["Von Hand unterschreiben und eingeschrieben senden."])
        }
        if de && k == .insurance {
            return CTSkrRule(end: dayB, when: "1 Monat nach Erhalt der Mitteilung", source: "§ 40 VVG", tips: [
                "Die Frist läuft ab dem Tag, an dem der Brief bzw. die E-Mail bei dir eingetroffen ist.",
            ])
        }
        if !de && (k == .insurance || k == .health || rx("versicher|krankenkass", lp)) {
            return CTSkrRule(when: "siehe Mitteilung", none: true, tips: [
                "Bei Zusatz- und Sachversicherungen regeln die Versicherungsbedingungen (AVB) das Kündigungsrecht – meist auf den Tag der Erhöhung.",
                "Ohne Kündigung gilt die neue Prämie als angenommen.",
            ])
        }
        let tips = c.currency == .CHF
            ? ["In der Schweiz gibt es dafür kein allgemeines Gesetz. Ob und bis wann du kündigen kannst, steht in den AGB und oft in der Mitteilung."]
            : ["Es gibt kein allgemeines gesetzliches Sonderkündigungsrecht. Ob und bis wann du kündigen kannst, steht in den AGB und meist in der Mitteilung.",
               "Eine Erhöhung ohne gültige Preisklausel musst du nicht hinnehmen."]
        return CTSkrRule(when: "siehe Mitteilung", none: true, tips: tips)
    }

    /// Web: `!gone && !isFixed(c) ? skrInfo(c) : null` (gekündigt, «gekündigt per», abgelaufen oder nicht kündbar → keine Zeile)
    static func info(_ calc: Calc, data: AppData, _ c: Contract) -> CTSkrInfo? {
        let gone = c.status == .cancelled || c.cancelPer != nil || calc.endedByTerm(c)
        if gone || calc.isFixed(c) { return nil }
        let t = calc.today
        var list: [(f: Day, a: Double, prev: Double, up: Bool, pct: Int)] = []
        var prev = c.amount
        for p in calc.pricesOf(c) {
            let a = p.amount
            list.append((p.from, a, prev, prev > 0 && a > prev, prev > 0 ? Int(Format.jsRound((a / prev - 1) * 100)) : 0))
            prev = a
        }
        // neueste Erhöhung zuerst (angekündigte vor vergangenen)
        for x in list.reversed() where x.up {
            let r = rule(c, from: x.f, calc: calc, data: data)
            let end = r.until ?? x.f.addingDays(30)
            if end < t { continue }
            var tail: String
            if r.none {
                tail = "Kündigungsrecht prüfen"
            } else if let u = r.until {
                let dd = String(format: "%02d.%02d.", u.day, u.month) + (u.year != t.year ? String(String(u.year).suffix(2)) : "")
                tail = (r.untilMin ? "bis mind. " : "bis ") + dd
            } else {
                tail = "Frist ab Mitteilung"
            }
            return CTSkrInfo(from: x.f, amount: x.a, previous: x.prev, percent: x.pct, rule: r,
                             head: r.none ? "Preis erhöht" : "Sonderkündigung möglich", tail: tail)
        }
        return nil
    }

    /// Web `openSkr`
    static func sheet(_ x: CTSkrInfo, contract c: Contract, calc: Calc, data: AppData) -> CTSkrSheetData {
        let r = x.rule
        let t = calc.today
        let fut = x.from > t
        let pn = calc.partnerName(c)
        let P = pn.isEmpty ? data.title(of: c) : pn
        let cy = max(1, c.cycleForCalc)
        let cur = c.currency.rawValue
        let dm = (x.amount - x.previous) / Double(cy)
        var rows = [CTSkrRow(key: "Neuer Preis", value: Format.money(x.amount) + " " + cur,
                             sub: (fut ? "ab " : "seit ") + Format.fmtShort(x.from) + " · +\(x.percent) % (+" + Format.money(dm) + "/Mt.)",
                             accent: false)]
        if let u = r.until {
            let dn = t.days(to: u)
            rows.append(CTSkrRow(key: "Kündigen bis", value: (r.untilMin ? "mind. " : "") + Format.fmtShort(u),
                                 sub: (dn == 0 ? "heute" : "noch \(dn)" + (dn == 1 ? " Tag" : " Tage")) + (r.untilMin ? "" : " · Eingang zählt"),
                                 accent: true))
        } else {
            rows.append(CTSkrRow(key: "Kündigen bis", value: r.when ?? "", sub: "", accent: !r.none))
        }
        if let e = r.end {
            rows.append(CTSkrRow(key: "Vertrag endet", value: (r.endMin ? "frühestens " : "") + Format.fmtShort(e), sub: "", accent: false))
        } else if let et = r.endText {
            rows.append(CTSkrRow(key: "Vertrag endet", value: et, sub: "", accent: false))
        }
        let intro = r.none
            ? P + " erhöht den Preis. Ob du deshalb ausserordentlich kündigen darfst, regeln die Vertragsbedingungen."
            : "Weil " + P + " den Preis erhöht, darfst du ausserordentlich kündigen – auch wenn der Vertrag sonst noch weiterlaufen würde."
        let footer = (r.source.map { "Grundlage: " + $0 + " · " } ?? "") + "Massgebend sind dein Vertrag und die Mitteilung. Keine Rechtsberatung."
        return CTSkrSheetData(title: x.head, intro: intro, rows: rows, tips: r.tips, footer: footer)
    }
}

// MARK: - Zeile im Detail (Web `.skrl`: Fläche `--field`, Radius 12, 10/12, ⓘ 17 in Georgia, 13.5 px, › Messing)

struct CTSkrLine: View {
    let info: CTSkrInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) {
                Text("i")
                    .font(.custom("Georgia", size: 10.5).weight(.semibold).italic())
                    .foregroundStyle(KColor.ink2)
                    .frame(width: 17, height: 17)
                    .overlay(Circle().strokeBorder(KColor.ink2, lineWidth: 1))
                (Text(info.head).fontWeight(.semibold).foregroundColor(KColor.ink)
                 + Text(info.tail.isEmpty ? "" : " · " + info.tail).foregroundColor(KColor.ink2))
                    .font(.system(size: 13.5))
                    .lineSpacing(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("›")
                    .font(.system(size: 18))
                    .foregroundStyle(KColor.teal)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .accessibilityLabel(info.head + (info.tail.isEmpty ? "" : ", " + info.tail))
        .accessibilityHint("Erklärung öffnen")
        .accessibilityIdentifier("detail.skr")
    }
}

// MARK: - Erklärblatt (Web `openSkr` im Auswahlblatt `#sheetPick`)

struct CTSkrSheet: View {
    let data: CTSkrSheetData

    var body: some View {
        CTPickSheet(title: data.title) {
            VStack(alignment: .leading, spacing: 0) {
                Text(data.intro)
                    .font(.system(size: 15))
                    .foregroundStyle(KColor.ink)
                    .lineSpacing(3.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 14)
                VStack(spacing: 0) {
                    ForEach(Array(data.rows.enumerated()), id: \.element.id) { i, r in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(r.key)
                                .font(.system(size: 15))
                                .foregroundStyle(KColor.ink2)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(r.value)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(r.accent ? KColor.teal : KColor.ink)
                                    .multilineTextAlignment(.trailing)
                                if !r.sub.isEmpty {
                                    Text(r.sub)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(KColor.ink2)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
                Text("Gut zu wissen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KColor.ink3)
                    .padding(.horizontal, 4)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(data.tips.enumerated()), id: \.offset) { i, s in
                        Text(s)
                            .font(.system(size: 14))
                            .foregroundStyle(KColor.ink2)
                            .lineSpacing(3.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 11)
                            .overlay(alignment: .top) {
                                if i > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
                Text(data.footer)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink3)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
            }
        }
        .accessibilityIdentifier("skr.sheet")
    }
}

/// Blatt-Inhalt als Identifiable (für .sheet(item:))
struct CTSkrSheetItem: Identifiable {
    let id = UUID()
    let data: CTSkrSheetData
}
