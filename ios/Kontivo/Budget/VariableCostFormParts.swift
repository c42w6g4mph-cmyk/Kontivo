import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

/// Bild- und Symbolauswahl im Formular der variablen Kosten (Web v231 `#vcIconWrap`, `.vicpanel`): Logo automatisch finden,
/// Einfügen, Hochladen, Google, Logo entfernen; darunter «Ohne Bild: Symbol» mit allen Symbolen (6 pro Zeile).
/// Symbol antippen setzt das Symbol, entfernt ein Logo und klappt zu.
struct KBVarIconPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Binding var draft: VariableCost
    /// Name für die Logo-Suche (Bezeichnung)
    let name: String
    let close: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var cropImage: KBCropImage?
    @State private var showLogoSearch = false
    @State private var webHint = false
    @State private var webWait = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { autoFind() } label: {
                Text("Logo automatisch finden")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Button { pasteLogo() } label: { KBLogoButtonLabel(title: "Einfügen") }
                    .buttonStyle(.plain)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    KBLogoButtonLabel(title: "Hochladen")
                }
                .buttonStyle(.plain)
                Button { googleSearch() } label: { KBLogoButtonLabel(title: "Google") }
                    .buttonStyle(.plain)
            }
            if webHint {
                (Text("So geht’s: ").bold()
                 + Text("In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
            }
            if draft.logoID != nil {
                Button {
                    draft.logoID = nil
                    draft.logoBg = nil
                } label: {
                    KBLogoButtonLabel(title: "Logo entfernen", destructive: true)
                }
                .buttonStyle(.plain)
            }
            Text("Ohne Bild: Symbol")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KColor.ink3)
                .padding(.top, 10)
                .padding(.horizontal, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(VarIcon.allCases, id: \.self) { ic in
                    let on = draft.icon == ic && draft.logoID == nil
                    Button {
                        draft.icon = ic
                        draft.logoID = nil
                        draft.logoBg = nil
                        close()
                    } label: {
                        MarkView(varIcon: ic, size: 38)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(on ? KColor.brass : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: ic.displayName))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("var.icon." + ic.rawValue)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
        .sheet(item: $cropImage) { ci in
            ImageCropSheet(image: ci.image, title: "Logo zuschneiden") { data, bg in
                applyLogo(data, bg)
                cropImage = nil
            }
            .environment(model)
        }
        .sheet(isPresented: $showLogoSearch) {
            LogoSearchSheet(name: name, currency: draft.currency, web: "") { data, bg in
                applyLogo(data, bg)
                showLogoSearch = false
            }
            .environment(model)
        }
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && webWait {
                webWait = false
                model.toast("Bild kopiert? Jetzt «Einfügen» tippen")
            }
        }
    }

    private func applyLogo(_ data: Data, _ bg: String) {
        guard let id = model.storeFile(data, type: "image/png") else { return }
        draft.logoID = id
        draft.logoBg = bg
    }

    private func autoFind() {
        if name.isEmpty {
            model.toast("Zuerst den Namen eintragen")
            return
        }
        webHint = false
        showLogoSearch = true
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
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
    private func pasteLogo() {
        webWait = false
        webHint = false
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image {
            cropImage = KBCropImage(image: img)
            return
        }
        var link: URL?
        if pb.hasURLs, let u = pb.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            link = u
        } else if pb.hasStrings, let s = pb.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  s.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil {
            link = URL(string: s)
        }
        guard let url = link else {
            model.toast("Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».")
            return
        }
        model.toast("Lade Bild…")
        Task { @MainActor in
            var img: UIImage?
            if let result = try? await URLSession.shared.data(from: url) { img = UIImage(data: result.0) }
            if let img {
                cropImage = KBCropImage(image: img)
            } else {
                model.toast("Bild-Link konnte nicht geladen werden")
            }
        }
    }

    private func googleSearch() {
        if name.isEmpty {
            model.toast("Zuerst den Namen eintragen")
            return
        }
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: name + " logo")]
        guard let url = comps?.url else { return }
        webHint = true
        webWait = true
        openURL(url)
    }
}

/// Kacheln «pro Monat | pro Jahr» (Web `vKzPaint`, `.fkz`): ohne gültigen Betrag «–»
struct KBVarFormTiles: View {
    let amount: Double?
    let currency: Currency

    var body: some View {
        HStack(spacing: 8) {
            tile("pro Monat", amount.map { Format.money($0, currency) })
            tile("pro Jahr", amount.map { Format.money0($0 * 12, currency) })
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("var.tiles")
    }

    private func tile(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label)
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .frame(height: 18)
            Group {
                if let v = value {
                    Text(verbatim: v).font(KFont.serif(22, .medium))
                        + Text(verbatim: " " + currency.rawValue).font(KFont.serif(13, .medium)).foregroundStyle(KColor.ink2)
                } else {
                    Text(verbatim: "–").font(KFont.serif(22, .medium))
                }
            }
            .tracking(-0.22)
            .foregroundStyle(KColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: 31.9)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
