import SwiftUI
import KontivoCore

// Gemeinsame Bausteine des Zeitstrahls im Betragsbereich (Web v314–v320 `tlPaint`, `priceRowsHtml`, `newRowBind`), verwendet im
// Vertragsformular (Karte «Kosten») und im Einnahmen-Formular (Karte «Betrag»). Rechnung im Kern (`PriceTimelineRules`).

/// Punkt im Zeitstrahl (Web `.tld`): normal (Rand Tinte 3), aktuell (Messing mit Hof), geplant (gestrichelt Warnfarbe),
/// neu (gestrichelt Akzent)
enum CTTimelineDot {
    case normal, current, future, new
}

/// Zeile im Zeitstrahl: links 28 pt mit senkrechter Linie (x 10, 2 pt) und Punkt (12 pt), daneben der Inhalt.
/// `on` = Zeitstrahl sichtbar (ab 1 Preisänderung); `top`/`bottom`: Linie beginnt bzw. endet in der Zeilenmitte.
struct CTTimelineRow<Content: View>: View {
    let on: Bool
    var top = false
    var bottom = false
    var dot: CTTimelineDot = .normal
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            if on {
                GeometryReader { g in
                    let h = g.size.height
                    let y0: CGFloat = top ? h / 2 : 0
                    let y1: CGFloat = bottom ? h / 2 : h
                    Rectangle().fill(KColor.line)
                        .frame(width: 2, height: Swift.max(0, y1 - y0))
                        .position(x: 11, y: (y0 + y1) / 2)
                    dotView.position(x: 11, y: h / 2)
                }
                .frame(width: 28)
                .accessibilityHidden(true)
            }
            content
        }
        .frame(minHeight: 47)
    }

    @ViewBuilder private var dotView: some View {
        switch dot {
        case .normal:
            Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.ink3, lineWidth: 2.5)).frame(width: 12, height: 12)
        case .current:
            Circle().fill(KColor.brass).frame(width: 12, height: 12)
                .background(Circle().fill(KColor.brass.opacity(0.22)).frame(width: 20, height: 20))
        case .future:
            Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.warn, style: StrokeStyle(lineWidth: 2.5, dash: [2.5, 2]))).frame(width: 12, height: 12)
        case .new:
            Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.teal, style: StrokeStyle(lineWidth: 2.5, dash: [2.5, 2]))).frame(width: 12, height: 12)
        }
    }
}

/// Datum als Text, darüber unsichtbar das kompakte Datumsfeld (Web `.pdl` mit `input.pdi`): Antippen öffnet den Kalender
struct CTTimelineDateLabel<Label: View>: View {
    let day: Day
    var identifier = ""
    let onPick: (Day) -> Void
    @ViewBuilder let label: Label

    var body: some View {
        label
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                DatePicker("Gültig ab", selection: Binding(get: { day.date() }, set: { onPick(Day(date: $0)) }), displayedComponents: .date)
                    .labelsHidden()
                    .colorMultiply(.clear)
                    .opacity(0.011)
                    .accessibilityLabel("Gültig ab")
                    .accessibilityIdentifier(identifier)
            }
    }
}

/// Beschriftung einer Stufe: «ab TT.MM.JJ» (fett, wenn aktuell), darunter «aktuell · +10 %» mit farbiger Prozentangabe
/// (Web `.tls` + `.tlp`; bei Einnahmen ist mehr grün)
struct CTTimelineStepLabel: View {
    let row: PriceTimelineRow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.dateText)
                .font(.system(size: 15, weight: row.isCurrent ? .bold : .regular))
                .foregroundStyle(KColor.ink)
                .monospacedDigit()
                .lineLimit(1)
            if !row.subText.isEmpty {
                sub
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var sub: Text {
        var t = Text(row.status)
        if let pc = row.pctText {
            let c = row.pctTone == .up ? KColor.warn : (row.pctTone == .down ? KColor.ok : KColor.ink3)
            let p = Text(pc).foregroundColor(c).fontWeight(.semibold)
            t = row.status.isEmpty ? p : t + Text(" · ") + p
        }
        return t
    }
}

/// Beschriftung der neuen Zeile: «ab TT.MM.JJ» bzw. «Datum» in Akzentfarbe, darunter «neu» (Web `#pFromT`)
struct CTTimelineNewLabel: View {
    let from: Day?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(from.map { "ab " + Format.fmtShort($0) } ?? "Datum")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KColor.teal)
                .monospacedDigit()
            Text("neu")
                .font(.system(size: 12))
                .foregroundStyle(KColor.ink3)
        }
        .padding(.vertical, 4)
    }
}

/// Beschriftung der Startzeile: «Betrag» bzw. «Betrag netto»; mit Änderungen «ab TT.MM.JJ» und «Anfangspreis»/«Anfangsbetrag»
struct CTTimelineStartLabel: View {
    let timeline: PriceTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(timeline.startLabel)
                .font(.system(size: 15, weight: timeline.startIsCurrent ? .bold : .regular))
                .foregroundStyle(timeline.on ? KColor.ink : KColor.ink2)
                .monospacedDigit()
                .lineLimit(1)
            if !timeline.startSub.isEmpty {
                Text(timeline.startSub)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink3)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Betragsfeld rechts (Web `.pai`, Spalte 7.4em): Messing 16/500, rechtsbündig, Ziffernblock
struct CTTimelineAmountField: View {
    @Binding var text: String
    var placeholder = "Betrag"
    let a11y: String
    let identifier: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(KColor.ink3))
            .font(.system(size: 16, weight: .medium))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(KColor.teal)
            .frame(width: 118)
            .accessibilityLabel(a11y)
            .accessibilityIdentifier(identifier)
    }
}
