import SwiftUI

@MainActor
struct PrototypeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let vault: CredentialVault
    let onSaved: @MainActor () async -> Void

    @State private var gmid = ""
    @State private var cookie = ""
    @State private var revealsValues = false
    @State private var isSaving = false
    @State private var showsClearConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                explanationSection
                valuesSection
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.cinemaAccent) }
                }
                clearSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.cinemaBackground)
            .navigationTitle("Sesión del prototipo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await load() }
            .confirmationDialog(
                "¿Borrar la sesión guardada?",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar sesión", role: .destructive) { Task { await clear() } }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .tint(Color.cinemaAccent)
    }

    private var explanationSection: some View {
        Section {
            Label("Solo se guardan en el llavero de este iPhone.", systemImage: "lock.shield.fill")
            Text("Pega los valores GMID y COOKIE de una sesión propia. No se incluyen credenciales en el código ni se escriben en el registro.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Acceso privado")
        }
    }

    private var valuesSection: some View {
        Section("Valores de sesión") {
            CredentialField(title: "GMID", text: $gmid, isRevealed: revealsValues)
            CredentialField(title: "COOKIE", text: $cookie, isRevealed: revealsValues)
            Toggle("Mostrar valores", isOn: $revealsValues)
        }
    }

    private var clearSection: some View {
        Section {
            Button("Borrar sesión guardada", role: .destructive) {
                showsClearConfirmation = true
            }
            .disabled(gmid.isEmpty && cookie.isEmpty)
        } footer: {
            Text("Los valores capturados caducan y pueden dejar de funcionar sin aviso.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cerrar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Guardar") { Task { await save() } }
                .disabled(!canSave || isSaving)
        }
    }

    private var canSave: Bool {
        PrototypeCredentials(gmid: gmid, cookie: cookie).isValid
    }

    private func load() async {
        do {
            let credentials = try await vault.credentials()
            gmid = credentials?.gmid ?? ""
            cookie = credentials?.cookie ?? ""
        } catch {
            errorMessage = "No se pudo leer el llavero de este dispositivo."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await vault.save(PrototypeCredentials(gmid: gmid, cookie: cookie))
            await onSaved()
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la sesión de forma segura."
        }
    }

    private func clear() async {
        do {
            try await vault.clear()
            gmid = ""
            cookie = ""
            await onSaved()
            dismiss()
        } catch {
            errorMessage = "No se pudo borrar la sesión guardada."
        }
    }
}

private struct CredentialField: View {
    let title: String
    @Binding var text: String
    let isRevealed: Bool

    var body: some View {
        Group {
            if isRevealed {
                TextField(title, text: $text, axis: .vertical)
                    .lineLimit(2...6)
            } else {
                SecureField(title, text: $text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(.body, design: .monospaced))
        .privacySensitive()
    }
}

