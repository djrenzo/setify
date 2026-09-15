import SwiftUI

@MainActor
struct PrototypeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let vault: CredentialVault
    let atresVault: AtresCredentialVault
    let onSaved: @MainActor () async -> Void

    @State private var gmid = ""
    @State private var cookie = ""
    @State private var atresSession = ""
    @State private var revealsValues = false
    @State private var isSaving = false
    @State private var showsClearMediasetConfirmation = false
    @State private var showsClearAtresConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                explanationSection
                mediasetSection
                atresSection
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.cinemaAccent) }
                }
                clearSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.cinemaBackground)
            .navigationTitle("Sesiones de streaming")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await load() }
            .confirmationDialog(
                "¿Borrar la sesión de Mitele/Mediaset guardada?",
                isPresented: $showsClearMediasetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar sesión", role: .destructive) { Task { await clearMediaset() } }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog(
                "¿Borrar la sesión de Atresplayer guardada?",
                isPresented: $showsClearAtresConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar sesión", role: .destructive) { Task { await clearAtres() } }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .tint(Color.cinemaAccent)
    }

    private var explanationSection: some View {
        Section {
            Label("Solo se guardan en el llavero de este iPhone.", systemImage: "lock.shield.fill")
            Text("Pega los valores de una sesión propia. No se incluyen credenciales en el código ni se escriben en el registro.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Acceso privado")
        }
    }

    private var mediasetSection: some View {
        Section("Mitele / Mediaset") {
            CredentialField(title: "GMID", text: $gmid, isRevealed: revealsValues)
            CredentialField(title: "COOKIE", text: $cookie, isRevealed: revealsValues)
        }
    }

    private var atresSection: some View {
        Section {
            CredentialField(title: "A3PSID", text: $atresSession, isRevealed: revealsValues)
            Toggle("Mostrar valores", isOn: $revealsValues)
        } header: {
            Text("Atresplayer")
        } footer: {
            Text("Solo hace falta para algunos programas y series que piden cuenta registrada. El directo y la mayoría del catálogo funcionan sin ella.")
        }
    }

    private var clearSection: some View {
        Section {
            Button("Borrar sesión de Mitele/Mediaset", role: .destructive) {
                showsClearMediasetConfirmation = true
            }
            .disabled(gmid.isEmpty && cookie.isEmpty)
            Button("Borrar sesión de Atresplayer", role: .destructive) {
                showsClearAtresConfirmation = true
            }
            .disabled(atresSession.isEmpty)
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
        PrototypeCredentials(gmid: gmid, cookie: cookie).isValid || !trimmedAtresSession.isEmpty
    }

    private var trimmedAtresSession: String {
        atresSession.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async {
        do {
            let credentials = try await vault.credentials()
            gmid = credentials?.gmid ?? ""
            cookie = credentials?.cookie ?? ""
        } catch {
            errorMessage = "No se pudo leer el llavero de este dispositivo."
        }
        do {
            atresSession = try await atresVault.session() ?? ""
        } catch {
            errorMessage = "No se pudo leer el llavero de este dispositivo."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let mediasetCredentials = PrototypeCredentials(gmid: gmid, cookie: cookie)
            if mediasetCredentials.isValid {
                try await vault.save(mediasetCredentials)
            }
            if trimmedAtresSession.isEmpty {
                try await atresVault.clear()
            } else {
                try await atresVault.save(trimmedAtresSession)
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la sesión de forma segura."
        }
    }

    private func clearMediaset() async {
        do {
            try await vault.clear()
            gmid = ""
            cookie = ""
            await onSaved()
        } catch {
            errorMessage = "No se pudo borrar la sesión guardada."
        }
    }

    private func clearAtres() async {
        do {
            try await atresVault.clear()
            atresSession = ""
            await onSaved()
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
