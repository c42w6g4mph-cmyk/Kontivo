import SwiftUI
import KontivoCore

/// Auswahl vor dem Fixkosten-Bericht (Web v220 `openRepOpts`): Hinweis, Personen (ab 2 Personen), Schalter «Kunden- und
/// Vertragsnummern», «PDF erstellen», «Schliessen». Zugang: «Mehr» → Bericht und Teilen-Symbol im Tab «Kosten» (übernimmt den
/// Personenfilter). Danach öffnet sich das PDF in der Dokumentansicht (Teilen, Sichern, Drucken).
struct FixReportOptionsSheet: View {
    @Environment(AppModel.self) private var model
    let initialPerson: UUID?
    let fromCosts: Bool
    /// Web `repOpt`: Auswahl bleibt während der Sitzung erhalten
    @MainActor static var lastPerson: UUID?
    @MainActor static var lastIDs = true

    @State private var person: UUID?
    @State private var ids = true
    @State private var busy = false

    init(initialPerson: UUID?, fromCosts: Bool) {
        self.initialPerson = initialPerson
        self.fromCosts = fromCosts
        _person = State(initialValue: initialPerson)
        _ids = State(initialValue: FixReportOptionsSheet.lastIDs)
    }

    var body: some View {
        let persons = model.data.persons
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("Fixkosten-Bericht")
                        .font(KFont.title(22))
                        .tracking(-0.264)
                        .foregroundStyle(KColor.ink)
                        .padding(.top, 2)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    KBRoundButton(edge: .clear, fill: KColor.sunken, action: { model.dismissTop() }) {
                        Text(verbatim: "×").font(.system(size: 20))
                    }
                    .accessibilityLabel("Schliessen")
                    .padding(.top, -16)
                    .padding(.trailing, -12)
                }
                .padding(.bottom, 3)
                Text(verbatim: Calc.reportIntro)
                    .font(.system(size: 12.5))
                    .lineSpacing(12.5 * 0.35)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.top, 9)
                    .padding(.bottom, 12)
                if persons.count > 1 {
                    segment(persons)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                }
                Toggle(isOn: $ids) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kunden- und Vertragsnummern")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(KColor.ink)
                        Text("Beim Weitergeben an Dritte ausschalten")
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink2)
                    }
                }
                .tint(KColor.tealFill)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
                .padding(.bottom, 12)
                .accessibilityIdentifier("report.ids")
                Button {
                    create()
                } label: {
                    Text("PDF erstellen")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10 + KBM.pad(19.575, 13.5))
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("report.create")
                Button {
                    model.dismissTop()
                } label: {
                    Text("Schliessen")
                        .font(.system(size: 14))
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13 + KBM.pad(20.3, 14))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(.horizontal, KBM.side)
            .padding(.top, 30)
            .padding(.bottom, 18)
        }
        .background(KColor.paper.ignoresSafeArea())
        .presentationDetents([.height(persons.count > 1 ? 420 : 370), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // aus «Kosten»: aktiver Personenfilter; aus «Mehr»: letzte Auswahl
            person = fromCosts ? initialPerson : FixReportOptionsSheet.lastPerson
            if let p = person, model.data.person(p) == nil { person = nil }
        }
    }

    /// Web `.seg2`: versenkte Fläche, gewählter Teil weiss mit Schatten
    private func segment(_ persons: [Person]) -> some View {
        HStack(spacing: 0) {
            segButton("Alle", on: person == nil) { person = nil }
            ForEach(persons) { p in
                segButton(p.name, on: person == p.id) { person = p.id }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personen")
    }

    private func segButton(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: t)
                .font(.system(size: 14, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? KColor.ink : KColor.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7 + KBM.pad(20.3, 14))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? KColor.surface : .clear)
                    .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func create() {
        guard !busy else { return }
        busy = true
        FixReportOptionsSheet.lastPerson = person
        FixReportOptionsSheet.lastIDs = ids
        let calc = model.calc
        let r = calc.fixReport(person: person, showIDs: ids)
        let data = calc.data
        let pdf = FixReportPDF.render(r, calc: calc) { data.categoryDisplayColor(named: $0) }
        let ref = DocumentRef(fileID: nil, data: pdf, type: "application/pdf", title: "Fixkosten-Bericht", fileName: r.fileName)
        let m = model
        m.dismissTop { m.present(.document(ref)) }
    }
}

/// Gruppe «Bericht» oben in «Mehr» (Web v220 `.sgroup` «Bericht»): Zeile «Fixkosten-Bericht» öffnet die Auswahl.
struct MoreReportGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MoreGroup(title: "Bericht") {
            MoreRow(title: "Fixkosten-Bericht", subtitle: "PDF zum Teilen, Ablegen oder Drucken", first: true) {
                if !model.calc.reportAvailable {
                    model.toast(Calc.reportUnavailableText)
                    return
                }
                model.present(.fixReport(person: nil, fromCosts: false))
            }
            .accessibilityIdentifier("more.report")
        }
    }
}
