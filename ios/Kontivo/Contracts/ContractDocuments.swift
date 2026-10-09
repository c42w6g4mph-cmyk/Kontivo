import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import KontivoCore

// Dokumente am Vertrag (Web 6e77e47, ff66728, cab3f89, a6e48d9, 6979920):
// Formular: Chip neben dem Logo mit Panel (Liste mit Öffnen/Entfernen, «Datei anhängen»).
// Detail (reine Ansicht): runder Knopf rechts im Kopf, Liste mit «Öffnen» und «Datei anhängen», ohne Löschen.

enum CTFormDocs {
    /// Typ aus der Endung (guessType)
    static func guessType(_ ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    /// Datei aus dem Dateien-Dialog lesen → (Daten, Name, Typ); nil = Fehler
    static func read(_ result: Result<URL, Error>) -> (data: Data, name: String, type: String)? {
        guard case .success(let url) = result else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)?.preferredMIMEType ?? guessType(ext)
        return (data, url.lastPathComponent, type)
    }

    /// Foto als JPEG laden
    static func photoJPEG(_ item: PhotosPickerItem) async -> Data? {
        guard let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return nil }
        return img.jpegData(compressionQuality: 0.85)
    }

    @MainActor
    static func importFile(_ result: Result<URL, Error>, form: CTFormState, model: AppModel) {
        if case .failure = result {
            model.toast("Upload fehlgeschlagen")
            return
        }
        guard let f = read(result) else {
            model.toast("Upload fehlgeschlagen")
            return
        }
        form.attach(f.data, name: f.name, type: f.type, model: model)
    }

    @MainActor
    static func loadPhoto(_ item: PhotosPickerItem, form: CTFormState, model: AppModel) {
        let today = model.today
        Task { @MainActor in
            let jpg = await photoJPEG(item)
            form.docPhoto = nil
            guard let jpg else {
                model.toast("Upload fehlgeschlagen")
                return
            }
            form.attach(jpg, name: "Foto " + Format.fmtShort(today) + ".jpg", type: "image/jpeg", model: model)
        }
    }
}

/// Chip «Dokument anhängen» bzw. «n Dokumente» neben dem Logo (Web #fDocsChip)
struct CTFormDocsChip: View {
    @Bindable var form: CTFormState

    var body: some View {
        let n = form.documents.count
        let on = form.docsOpen
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                form.docsOpen.toggle()
                if form.docsOpen { form.logoOpen = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperclip").font(.footnote.weight(.semibold))
                Text(n > 0 ? Format.count(n, "Dokument", "Dokumente") : "Dokument anhängen")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Color.white : KColor.teal)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(on ? KColor.teal : KColor.teal.opacity(0.13)))
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("form.docsChip")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Panel unter Logo/Chip (Web #oDocs): Liste (Öffnen, Entfernen), «Datei anhängen · PDF oder Bild», Foto, Hinweis
struct CTFormDocsPanel: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        ForEach(form.documents) { d in
            HStack(spacing: 10) {
                Button {
                    model.present(.document(DocumentRef(fileID: d.id, type: d.type, title: d.name, fileName: d.name)))
                } label: {
                    Label {
                        Text(d.name).foregroundStyle(KColor.ink).lineLimit(1)
                    } icon: {
                        Image(systemName: CTText.isPDF(d) ? "doc.richtext" : "photo")
                            .foregroundStyle(KColor.teal)
                    }
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 8)
                Button {
                    form.documents.removeAll { $0.id == d.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KColor.ink3)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Entfernen")
            }
        }
        Button {
            form.showFileImporter = true
        } label: {
            Label("Datei anhängen · PDF oder Bild", systemImage: "paperclip")
        }
        .accessibilityIdentifier("form.docAttach")
        PhotosPicker(selection: $form.docPhoto, matching: .images) {
            Label("Foto anhängen", systemImage: "photo.on.rectangle")
        }
        Text("Zum Beispiel Vertrag, Police oder Rechnung. Bleibt auf diesem Gerät.")
            .font(.footnote)
            .foregroundStyle(KColor.ink2)
    }
}

// MARK: - Detail

/// Runder Dokumente-Knopf rechts im Detailkopf (Web .ddoc): 44 pt Kreis + «Anhängen» bzw. «n Dateien», gefüllt bei Dokumenten
struct CTDetailDocsButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(count > 0 ? KColor.teal : KColor.teal.opacity(0.13))
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(count > 0 ? Color.white : KColor.teal)
                }
                .frame(width: 44, height: 44)
                Text(count > 0 ? Format.count(count, "Datei", "Dateien") : "Anhängen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KColor.teal)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? Format.count(count, "Dokument", "Dokumente") + " anzeigen" : "Dokument anhängen")
        .accessibilityIdentifier("detail.docs")
    }
}

/// Liste der Dokumente aus dem Detail (Web openDocsPick): «Öffnen ›», «Datei anhängen» speichert direkt am Vertrag.
/// Kein Löschen (nur unter «Bearbeiten»).
struct CTDetailDocsSheet: View {
    let contractID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var photo: PhotosPickerItem?
    /// Betrachter über dieser Liste (lokal, weil die Liste selbst ein lokales Fenster des Details ist)
    @State private var openDoc: DocumentRef?

    var body: some View {
        let docs = model.data.contract(contractID)?.documents ?? []
        NavigationStack {
            List {
                Section {
                    if docs.isEmpty {
                        Text("Noch keine Dokumente, zum Beispiel Vertrag, Police oder Rechnung.")
                            .font(.subheadline)
                            .foregroundStyle(KColor.ink2)
                    }
                    ForEach(docs) { d in
                        Button {
                            openDoc = DocumentRef(fileID: d.id, type: d.type, title: d.name, fileName: d.name)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: CTText.isPDF(d) ? "doc.richtext" : "photo")
                                    .foregroundStyle(KColor.teal)
                                Text(d.name).foregroundStyle(KColor.ink).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("Öffnen ›").font(.subheadline).foregroundStyle(KColor.teal)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } footer: {
                    Text("Dateien bleiben auf diesem Gerät." + (docs.isEmpty ? "" : " Löschen unter «Bearbeiten»."))
                }
                .listRowBackground(KColor.surface)
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Datei anhängen · PDF oder Bild", systemImage: "paperclip")
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("detail.docAttach")
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Foto anhängen", systemImage: "photo.on.rectangle")
                    }
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .navigationTitle("Dokumente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .sheet(item: $openDoc) { ref in
            DocumentViewer(ref: ref)
                .environment(model)
                .environment(\.locale, Locale(identifier: "de_CH"))
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .png, .jpeg, .webP, .heic, .image]) { result in
            guard let f = CTFormDocs.read(result) else {
                model.toast("Upload fehlgeschlagen")
                return
            }
            attach(f.data, name: f.name, type: f.type)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            let today = model.today
            Task { @MainActor in
                let jpg = await CTFormDocs.photoJPEG(item)
                photo = nil
                guard let jpg else {
                    model.toast("Upload fehlgeschlagen")
                    return
                }
                attach(jpg, name: "Foto " + Format.fmtShort(today) + ".jpg", type: "image/jpeg")
            }
        }
    }

    private func attach(_ data: Data, name: String, type: String) {
        guard let id = model.storeFile(data, type: type) else { return }
        let a = Attachment(id: id, name: name, type: type)
        let cid = contractID
        if model.update({ d in d.ctAttachDocument(a, to: cid) }) {
            model.toast("Angehängt")
        }
    }
}

extension AppData {
    /// Dokument direkt am Vertrag anhängen (aus dem Detail, ohne Bearbeiten)
    mutating func ctAttachDocument(_ a: Attachment, to id: UUID) {
        guard let i = contracts.firstIndex(where: { $0.id == id }) else { return }
        contracts[i].documents.append(a)
    }
}
