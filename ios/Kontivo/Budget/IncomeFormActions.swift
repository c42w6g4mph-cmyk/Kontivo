import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

// Einnahmen-Formular: Zuordnung und Aktionen (Sichern, Löschen, Logo)

extension KBIncomeForm {
    // MARK: Zuordnung

    var assignmentCard: some View {
        KBFormCard {
            Menu {
                Picker("Art", selection: $draft.kind) {
                    ForEach(IncomeKind.allCases, id: \.self) { k in
                        Label { Text(k.displayName) } icon: { KIcon.image(KIcon.symbol(forKey: k.icon)) }.tag(k)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 10) {
                    Text("Art")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: CategoryPalette.display(draft.kind.colorHex, key: draft.kind.displayName)))
                        .frame(width: 28, height: 28)
                        .overlay(KIcon.view(KIcon.symbol(forKey: draft.kind.icon), 15)
                            .foregroundStyle(.white))
                        .accessibilityHidden(true)
                    Text(verbatim: draft.kind.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(KColor.teal)
                        .lineLimit(1)
                    Text(verbatim: "›")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink)
                }
                .padding(.vertical, 4)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Art")
            .accessibilityValue(Text(verbatim: draft.kind.displayName))
            .accessibilityIdentifier("income.kind")
            if !model.data.persons.isEmpty {
                KBRowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Empfänger – genau eine Person")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                        .frame(minHeight: 21.75)
                    KBChipFlow(spacing: 6) {
                        ForEach(model.data.persons) { p in
                            KBInkChip(title: p.name, isOn: draft.holderID == p.id) { draft.holderID = p.id }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Aktionen

    var logoName: String {
        let n = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? draft.label.trimmingCharacters(in: .whitespacesAndNewlines) : n
    }

    var deleteName: String { original.label.isEmpty ? original.name : original.label }

    /// Neue Änderung mit Betrag (das Datum ist vorbelegt und zählt allein nicht)
    var subTyped: Bool {
        !priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isDirty: Bool {
        draft != original || amountText != originalAmountText || (subOpen && subTyped)
    }

    func cancel() {
        if isDirty {
            confirmDiscard = true
        } else {
            close()
        }
    }

    /// Fenster genau einmal schliessen.
    func close() {
        guard !closed else { return }
        closed = true
        model.dismissTop()
    }

    /// Fehlende Angabe (Web v218 `goMiss`): Meldung, Fokus/Datumsauswahl, ins Feld scrollen, Zeile 1.8 s markieren
    func goMiss(_ key: String, _ msg: String) {
        model.toast(msg)
        switch key {
        case "label": focus = .label
        case "amount": focus = .amount
        case "priceAmount": focus = .priceAmount
        default:
            focus = nil
            withAnimation(.easeInOut(duration: 0.2)) { dateOpen = key }
        }
        miss = key
        missTick += 1
        let tick = missTick
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if missTick == tick { miss = nil }
        }
    }

    func save() {
        guard !closed else { return }
        // eingetippte, nicht hinzugefügte Änderung übernehmen (Web v143); misslingt das, bleibt das Formular offen.
        // Bewusst strenger als Web `iSave` (dort wird eine halb ausgefüllte Änderung still verworfen): nichts geht verloren.
        for d in Array(priceRowTexts.keys) { commitRow(d) }
        if subOpen && subTyped && !addPrice() { return }
        let hasTitle = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasTitle else {
            goMiss("label", "Bezeichnung fehlt")
            return
        }
        guard let a = Format.parseAmount(amountText), a >= 0 else {
            goMiss("amount", amountText.trimmingCharacters(in: .whitespaces).isEmpty ? "Betrag fehlt" : "Betrag prüfen")
            return
        }
        var d = draft
        d.amount = a
        if bankSuggestion {
            BankFormBridge.shared.incomeDone(d)
            close()
            return
        }
        let today = model.today
        let wasNew = isNew
        let ok = model.update { data in
            _ = try data.saveIncome(d, today: today)
        }
        if ok {
            close()
            model.toast(wasNew ? "Einnahme erfasst" : "Aktualisiert")
        }
    }

    /// Löschen schliesst auch die Einnahme-Ansicht darunter (Web `closeSheets`)
    func delete() {
        guard !closed else { return }
        closed = true
        let id = draft.id
        model.update { data in data.deleteIncome(id) }
        let n = model.sheets.count
        if n >= 2, model.sheets[n - 2] == .incomeDetail(id) {
            model.dismiss(level: n - 2)
        } else {
            model.dismissTop()
        }
        model.toast("Gelöscht")
    }

    /// «Änderung hinzufügen» (Web `iPAdd`): gleiches Datum ersetzt; true = übernommen
    @discardableResult
    func addPrice() -> Bool {
        guard let f = priceFrom else {
            goMiss("priceFrom", "Datum fehlt")
            return false
        }
        guard let a = Format.parseAmount(priceAmountText), a >= 0 else {
            goMiss("priceAmount", priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty ? "Betrag fehlt" : "Betrag prüfen")
            return false
        }
        draft.prices.removeAll { $0.from == f }
        draft.prices.append(PriceChange(from: f, amount: Format.round2(a)))
        draft.prices.sort { $0.from < $1.from }
        priceFrom = nil
        priceAmountText = ""
        subOpen = false
        return true
    }

    /// Neue Zeile verwerfen (Wischen «Verwerfen», Web `iPCancel`)
    func cancelSub() {
        priceFrom = nil
        priceAmountText = ""
        subOpen = false
    }

    func removePrice(_ from: Day) {
        draft.prices.removeAll { $0.from == from }
        priceRowTexts[from] = nil
    }

    func applyLogo(_ data: Data, _ bg: String) {
        guard let id = model.storeFile(data, type: "image/png") else { return }
        draft.logoID = id
        draft.logoBg = bg
    }

    func autoFind() {
        if logoName.isEmpty {
            model.toast("Zuerst den Namen eintragen")
            return
        }
        webHint = false
        showLogoSearch = true
    }

    func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            let data = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            if let d = data, let img = UIImage(data: d) {
                cropImage = KBCropImage(image: img)
            } else {
                model.toast("Bild konnte nicht geladen werden")
            }
        }
    }

    /// Bild (oder Bild-Link) aus der Zwischenablage → Zuschneiden
    func pasteLogo() {
        webWait = false
        webHint = false
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image {
            cropImage = KBCropImage(image: img)
            return
        }
        if pb.hasURLs, let u = pb.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            loadImage(from: u)
            return
        }
        if pb.hasStrings, let s = pb.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           s.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil, let u = URL(string: s) {
            loadImage(from: u)
            return
        }
        model.toast("Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».")
    }

    func loadImage(from url: URL) {
        model.toast("Lade Bild…")
        Task { @MainActor in
            var img: UIImage?
            if let result = try? await URLSession.shared.data(from: url) {
                img = UIImage(data: result.0)
            }
            if let img {
                cropImage = KBCropImage(image: img)
            } else {
                model.toast("Bild-Link konnte nicht geladen werden")
            }
        }
    }

    /// Google-Bildersuche öffnen; danach Bild kopieren und «Einfügen» tippen
    func googleSearch() {
        let n = logoName
        if n.isEmpty {
            model.toast("Zuerst den Firmennamen eintragen")
            return
        }
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: n + " logo")]
        guard let url = comps?.url else { return }
        webHint = true
        webWait = true
        openURL(url)
    }
}
