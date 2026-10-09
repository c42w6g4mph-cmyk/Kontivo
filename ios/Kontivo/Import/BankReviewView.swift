import SwiftUI
import KontivoCore

/// Vorschläge prüfen (Web `paintBank`): Checkliste mit Bearbeiten in der Zeile.
/// Abschnitte: Preisänderung, Neu gefunden, Vielleicht (mit Hinweis), «Bereits erfasst» eingeklappt, ausgeblendete Vorschläge.
struct BankReviewView: View {
    @Bindable var review: BankReview
    let onDone: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Text(review.header)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .accessibilityIdentifier("bankHeader")
                }
                if !review.prices.isEmpty {
                    Section {
                        ForEach(review.prices) { p in priceRow(p) }
                    } header: { head("Preisänderung", review.prices.count) }
                }
                if !review.sure.isEmpty {
                    Section {
                        ForEach(review.sure, id: \.self) { i in row(review.rows[i]) }
                    } header: { head("Neu gefunden", review.sure.count) }
                }
                if !review.maybe.isEmpty {
                    Section {
                        ForEach(review.maybe, id: \.self) { i in row(review.rows[i]) }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            head("Vielleicht", review.maybe.count)
                            Text("Erst 1–2 Zahlungen im Auszug. Rhythmus bitte prüfen.")
                                .font(.footnote)
                                .foregroundStyle(KColor.ink2)
                                .textCase(nil)
                        }
                    }
                }
                if review.isEmpty { emptySection }
                knownSection
                if review.ignoredCount > 0 {
                    Section {
                        Button(review.showIgnored ? "Ausgeblendete verbergen"
                               : (review.ignoredCount == 1 ? "1 ausgeblendeter Vorschlag zeigen" : "\(review.ignoredCount) ausgeblendete Vorschläge zeigen")) {
                            withAnimation { review.showIgnored.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .listRowBackground(Color.clear)
                    }
                }
                Section {
                    Text(review.privacy)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink3)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .kKeyboardDone()
            .onChange(of: review.open) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    // MARK: Bausteine

    private func head(_ title: String, _ n: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(n)")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(KColor.ink2)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onDone) {
                Text(review.footerTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(KColor.teal)
            .disabled(review.selectedCount == 0 && review.selectedPrices == 0)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .accessibilityIdentifier("bankApply")
        }
        .background(KColor.surface)
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 6) {
                Text("Keine neuen Fixkosten gefunden").font(.headline)
                Text(review.result.known.isEmpty
                     ? "Wiederkehrende Zahlungen werden erst erkannt, wenn sie mindestens zweimal im Auszug stehen. Am besten einen Auszug über 6–12 Monate exportieren."
                     : "Alle wiederkehrenden Zahlungen sind schon erfasst.")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var knownSection: some View {
        let known = review.result.known
        if !known.isEmpty {
            Section {
                Button {
                    withAnimation { review.showKnown.toggle() }
                } label: {
                    Text(review.showKnown ? "Bereits erfasste ausblenden"
                         : (known.count == 1 ? "1 bereits erfasster Vertrag zeigen" : "\(known.count) bereits erfasste Verträge zeigen"))
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("bankKnownToggle")
                if review.showKnown {
                    ForEach(known.indices, id: \.self) { i in knownRow(known[i]) }
                }
            } header: {
                if review.showKnown { head("Bereits erfasst", known.count) }
            }
        }
    }

    // MARK: Zeilen

    private func check(_ on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if on {
                    Circle().fill(KColor.teal)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(KColor.ink3, lineWidth: 1.6)
                }
            }
            .frame(width: 26, height: 26)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityValue(on ? "ausgewählt" : "nicht ausgewählt")
    }

    private func row(_ r: BankReview.Row) -> some View {
        let isOpen = review.open == r.id
        let cat = model.data.category(r.ed.categoryID) ?? model.data.otherCategory
        let partner = Partners.find(r.ed.name, in: model.data)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                check(r.on, label: r.ed.name + " übernehmen") { review.toggle(r.id) }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { review.open = isOpen ? nil : r.id }
                } label: {
                    HStack(spacing: 11) {
                        MarkView(logoID: partner?.logoID, logoBg: partner?.logoBg, colorHex: cat?.colorHex ?? KCategory.fallbackColor,
                                 symbol: KIcon.symbol(for: cat), size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.ed.name).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink).lineLimit(1)
                            Text(review.sub(r)).font(.caption).foregroundStyle(KColor.ink2).lineLimit(isOpen ? 3 : 1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Format.money(r.ed.amount)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(KColor.ink)
                            Text(r.s.currency).font(.caption).foregroundStyle(KColor.ink2)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen ? "Zuklappen" : "Bearbeiten")
                .accessibilityIdentifier("bankRow-" + r.s.name)
            }
            if isOpen {
                BankRowEditor(review: review, rowID: r.id)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .id(r.id)
        .listRowBackground(isOpen ? KColor.field : KColor.surface)
    }

    private func priceRow(_ p: BankReview.PriceRow) -> some View {
        let c = UUID(uuidString: p.m.contractID).flatMap { model.data.contract($0) }
        let old = c.map { model.calc.curPrice($0) } ?? p.m.suggestion.amount
        let name = c.map { n in model.data.partnerName(of: n).isEmpty ? model.data.title(of: n) : model.data.partnerName(of: n) } ?? p.m.suggestion.name
        let cur = c?.currency.rawValue ?? p.m.suggestion.currency
        return HStack(spacing: 10) {
            check(p.on, label: "Neuen Preis für \(name) übernehmen") { review.togglePrice(p.id) }
            if let c { MarkView(contract: c, data: model.data, size: 36) }
            VStack(alignment: .leading, spacing: 1) {
                Text(name + (p.m.amount > old ? " ist teurer" : " ist günstiger"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink)
                Text(Format.money(old) + " → " + Format.money(p.m.amount) + " " + cur + " ab " + BankReview.day(p.m.from))
                    .font(.caption).foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func knownRow(_ k: BankKnown) -> some View {
        if let id = UUID(uuidString: k.contractID), let c = model.data.contract(id) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(KColor.ok.opacity(0.16))
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(KColor.ok)
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                MarkView(contract: c, data: model.data, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    let pn = model.data.partnerName(of: c)
                    Text(pn.isEmpty ? model.data.title(of: c) : pn).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink2).lineLimit(1)
                    Text((Format.cycleText(c.cycle) ?? "") + " · unverändert").font(.caption).foregroundStyle(KColor.ink2)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.money(model.calc.curPrice(c))).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(KColor.ink2)
                    Text(c.currency.rawValue).font(.caption).foregroundStyle(KColor.ink2)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Editor in der Zeile (Web `bkEditor`)

struct BankRowEditor: View {
    @Bindable var review: BankReview
    let rowID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if let i = review.index(rowID) {
            let r = review.rows[i]
            VStack(alignment: .leading, spacing: 10) {
                field("Vertragspartner") {
                    TextField("Vertragspartner", text: Binding(get: { review.rows[i].ed.name },
                                                              set: { v in review.edit(rowID) { $0.name = v } }))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("bankName")
                }
                HStack(alignment: .top, spacing: 10) {
                    field("Betrag (\(r.s.currency))") {
                        TextField("0.00", text: Binding(get: { review.rows[i].ed.amountText },
                                                        set: { v in review.setAmountText(rowID, v) }))
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                    }
                    field("Rhythmus") {
                        Picker("Rhythmus", selection: Binding(get: { review.rows[i].ed.cycle },
                                                              set: { v in review.edit(rowID) { $0.cycle = v } })) {
                            ForEach(cycles(r.ed.cycle), id: \.self) { c in
                                Text(Format.cycleText(c) ?? "alle \(c) Monate").tag(c)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    field("Kategorie") {
                        Picker("Kategorie", selection: Binding(get: { review.rows[i].ed.categoryID },
                                                               set: { v in review.edit(rowID) { $0.categoryID = v } })) {
                            ForEach(model.data.categories) { c in
                                Text(c.name).tag(Optional(c.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    field("Nächste Zahlung") {
                        DatePicker("Nächste Zahlung", selection: Binding(get: { review.rows[i].ed.due.date() },
                                                                       set: { v in review.edit(rowID) { $0.due = Day(date: v) } }),
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                if model.data.persons.count > 1 { personSegment(i) }
                if let ch = r.s.change {
                    note("Preis bisher \(Format.money(ch.prev)), seit \(BankReview.day(ch.from)) \(Format.money(ch.amount)) \(r.s.currency). Beides kommt in den Preisverlauf.")
                }
                proof(r.s)
                if let t = r.s.catalogName {
                    note("Kündigungsfrist und Kontaktdaten aus dem Katalog («\(t)»).")
                } else {
                    note("Kündigungsfrist ergänzt du danach im Vertrag.")
                }
                HStack {
                    Button("Nie mehr vorschlagen") { review.ignore(rowID, model: model) }
                        .font(.subheadline)
                        .foregroundStyle(KColor.alert)
                        .buttonStyle(.plain)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { review.open = nil }
                    } label: {
                        Text("Fertig")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KColor.paper)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.ink))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bankRowDone")
                }
                .padding(.top, 2)
            }
            .padding(.bottom, 6)
        }
    }

    private func cycles(_ cur: Int) -> [Int] {
        var c = Format.cycleOptions
        if !c.contains(cur) { c.append(cur) }
        return c
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(KColor.ink2)
            content()
                .padding(.horizontal, 10)
                .frame(minHeight: 40, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(KColor.ink2).fixedSize(horizontal: false, vertical: true)
    }

    /// Person: jede Person einzeln oder «Beide»/«Alle» (Web `.hseg`)
    private func personSegment(_ i: Int) -> some View {
        let persons = model.data.persons
        let sel = review.rows[i].ed.holderIDs
        let all = persons.allSatisfy { sel.contains($0.id) }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Person").font(.caption.weight(.medium)).foregroundStyle(KColor.ink2)
            HStack(spacing: 2) {
                ForEach(persons) { p in
                    segButton(p.name, on: !all && sel.count == 1 && sel[0] == p.id) {
                        review.edit(rowID) { $0.holderIDs = [p.id] }
                    }
                }
                segButton(persons.count == 2 ? "Beide" : "Alle", on: all) {
                    review.edit(rowID) { $0.holderIDs = persons.map { $0.id } }
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
        }
    }

    private func segButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? KColor.paper : KColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? KColor.ink : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// «Im Auszug»: Originalname, Text, letzte Buchungen, Zahlungsart
    private func proof(_ s: BankSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Im Auszug").font(.caption).textCase(.uppercase).tracking(0.5).foregroundStyle(KColor.ink3)
            Text("«" + String((s.raw.isEmpty ? s.name : s.raw).prefix(60)) + "»")
                .font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink)
            ForEach(review.proofLines(s), id: \.self) { l in
                Text(l).font(.caption).foregroundStyle(KColor.ink2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.surface))
        .accessibilityElement(children: .combine)
    }
}
