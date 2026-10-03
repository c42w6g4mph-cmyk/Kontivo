import SwiftUI
import Charts
import KontivoCore

/// Preisverlauf als Stufendiagramm (priceChart): bis heute durchgezogen, danach gestrichelt; nur bei ≥ 1 Preisstufe.
struct CTPriceChart: View {
    let contract: Contract
    let today: Day

    var body: some View {
        if let m = CTPriceChartModel(contract: contract, today: today) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.headLeft)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    Text(m.headRight)
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(m.diff > 0 ? KColor.warn : (m.diff < 0 ? KColor.ok : KColor.ink))
                }
                chart(m)
                    .frame(height: 96)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(m.accessibility)
        }
    }

    private func chart(_ m: CTPriceChartModel) -> some View {
        Chart {
            ForEach(m.past) { p in
                AreaMark(x: .value("Datum", p.date), yStart: .value("Basis", m.yMin), yEnd: .value("Preis", p.value))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(KColor.teal.opacity(0.12))
            }
            RuleMark(y: .value("Basis", m.yMin))
                .foregroundStyle(KColor.line)
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(m.past) { p in
                LineMark(x: .value("Datum", p.date), y: .value("Preis", p.value), series: .value("Linie", "bisher"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(KColor.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(m.future) { p in
                LineMark(x: .value("Datum", p.date), y: .value("Preis", p.value), series: .value("Linie", "geplant"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(KColor.teal.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            }
            ForEach(m.dots) { d in
                PointMark(x: .value("Datum", d.date), y: .value("Preis", d.value))
                    .symbol {
                        CTPriceDot(kind: d.kind)
                    }
            }
            PointMark(x: .value("Datum", m.startDate), y: .value("Preis", m.base))
                .opacity(0)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text(Format.money(m.base))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink2)
                }
            PointMark(x: .value("Datum", m.endDate), y: .value("Preis", m.last))
                .opacity(0)
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text(Format.money(m.last))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink2)
                }
        }
        .chartXScale(domain: m.startDate...m.endDate)
        .chartYScale(domain: m.yMin...m.yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                axisLabels(m, proxy: proxy, geo: geo)
            }
        }
        .padding(.bottom, 16)
    }

    /// Beschriftung unten: links Jahr bzw. «Anfang», rechts «heute» bzw. Jahr, mittig «heute», wenn Platz
    private func axisLabels(_ m: CTPriceChartModel, proxy: ChartProxy, geo: GeometryProxy) -> some View {
        let frame: CGRect = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
        let todayX: CGFloat? = m.showMidToday ? proxy.position(forX: m.todayDate).map { $0 + frame.minX } : nil
        let left = frame.minX
        let right = frame.maxX
        return ZStack(alignment: .topLeading) {
            Text(m.leftLabel)
                .position(x: left + 24, y: frame.maxY + 9)
            Text(m.rightLabel)
                .position(x: right - 20, y: frame.maxY + 9)
            if let x = todayX, x > left + 44, x < right - 58 {
                Text("heute")
                    .position(x: x, y: frame.maxY + 9)
            }
        }
        .font(.caption2)
        .foregroundStyle(KColor.ink3)
    }
}

/// Punkt an einer Preisstufe: Zukunft Warnfarbe, aktueller Preis gefüllt, Vergangenheit Rand
private struct CTPriceDot: View {
    let kind: CTPriceChartModel.DotKind
    var body: some View {
        switch kind {
        case .now:
            Circle().fill(KColor.teal).frame(width: 7, height: 7)
        case .past:
            Circle().fill(KColor.field).overlay(Circle().strokeBorder(KColor.teal, lineWidth: 1.5)).frame(width: 7, height: 7)
        case .future:
            Circle().fill(KColor.field).overlay(Circle().strokeBorder(KColor.warn, lineWidth: 1.5)).frame(width: 7, height: 7)
        }
    }
}

/// Rechenteil des Diagramms (wie priceChart der Web-App)
struct CTPriceChartModel {
    enum DotKind { case past, now, future }

    struct Point: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    struct Dot: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let kind: DotKind
    }

    var past: [Point] = []
    var future: [Point] = []
    var dots: [Dot] = []
    var startDate: Date
    var endDate: Date
    var todayDate: Date
    var yMin: Double
    var yMax: Double
    var base: Double
    var last: Double
    var diff: Double
    var headLeft: String
    var headRight: String
    var leftLabel: String
    var rightLabel: String
    var showMidToday: Bool
    var accessibility: String

    init?(contract c: Contract, today t: Day) {
        let ps = c.prices.filter { $0.amount.isFinite }.ctStableSorted { $0.from < $1.from }
        guard let first = ps.first, let lastP = ps.last else { return nil }
        let base = c.amount.isFinite ? c.amount : 0
        // Startdatum: Vertragsbeginn vor der ersten Stufe, sonst erste Stufe − max(180 Tage, 25 % der Spanne)
        var st: Day
        if let s = c.start, s < first.from {
            st = s
        } else {
            let span = max(180, Int((Double(first.from.days(to: lastP.from)) * 0.25).rounded(.down)))
            st = first.from.addingDays(-span)
        }
        let extra = max(60, Int((Double(st.days(to: lastP.from)) * 0.08).rounded(.down)))
        let endCand = lastP.from.addingDays(extra)
        let end = endCand > t ? endCand : t
        if st >= end { st = end.addingDays(-1) }

        // Werte (Anfang + Stufen)
        var values: [(Day, Double)] = [(st, base)]
        for p in ps { values.append((p.from, p.amount)) }
        var ni = 0
        for (i, v) in values.enumerated() where i > 0 && v.0 <= t { ni = i }
        let vs = values.map { $0.1 }
        var mn = vs.min() ?? 0
        var mx = vs.max() ?? 1
        if mx == mn { mx += 1; mn -= 1 }
        let pad = (mx - mn) * 0.18
        yMin = mn - pad
        yMax = mx + pad

        // Linie bis heute (durchgezogen), danach geplant (gestrichelt)
        let cut: Day = max(st, min(t, end))
        let hasFuture = ps.contains { $0.from > t }
        var pts: [(Day, Double)] = [(st, base)]
        for p in ps where p.from <= t { pts.append((p.from, p.amount)) }
        let curVal = pts.last?.1 ?? base
        var fut: [(Day, Double)] = []
        if hasFuture {
            pts.append((cut, curVal))
            fut.append((cut, curVal))
            for p in ps where p.from > t { fut.append((p.from, p.amount)) }
            fut.append((end, lastP.amount))
        } else {
            pts.append((end, curVal))
        }
        past = pts.enumerated().map { Point(id: $0.offset, date: $0.element.0.date(), value: $0.element.1) }
        future = fut.enumerated().map { Point(id: 1000 + $0.offset, date: $0.element.0.date(), value: $0.element.1) }
        var ds: [Dot] = []
        for (i, v) in values.enumerated() where i > 0 {
            let k: DotKind = v.0 > t ? .future : (i == ni ? .now : .past)
            ds.append(Dot(id: i, date: v.0.date(), value: v.1, kind: k))
        }
        dots = ds

        startDate = st.date()
        endDate = end.date()
        todayDate = t.date()
        self.base = base
        last = lastP.amount
        let planned = ni == 0
        let cur = planned ? first.amount : values[ni].1
        diff = cur - base
        let pct = base != 0 ? diff / base * 100 : 0
        let sign = diff > 0 ? "+" : (diff < 0 ? Format.minus : "±")
        headLeft = planned ? "Geplant ab " + Format.fmtD(first.from) : "Veränderung bis heute"
        headRight = sign + Format.money(abs(diff)) + " " + c.currency.rawValue
            + (base != 0 ? " (" + sign + Format.number(abs(pct), maxFractionDigits: 1) + " %)" : "")
        if let s = c.start, s < first.from {
            leftLabel = String(st.year)
        } else {
            leftLabel = "Anfang"
        }
        rightLabel = end == t ? "heute" : String(end.year)
        showMidToday = t > st && t < end
        accessibility = "Preisverlauf von " + Format.money(base) + " auf " + Format.money(lastP.amount) + " " + c.currency.rawValue
    }
}
