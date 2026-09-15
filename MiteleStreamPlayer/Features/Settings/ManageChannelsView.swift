import SwiftUI

@MainActor
struct ManageChannelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ChannelStore

    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.channels) { channel in
                        ChannelManagementRow(channel: channel, store: store)
                    }
                    .onDelete { offsets in Task { await store.delete(at: offsets) } }
                    .onMove { offsets, destination in
                        Task { await store.move(from: offsets, to: destination) }
                    }
                } footer: {
                    Text("Los canales activos aparecen en Directo en este mismo orden.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cinemaBackground)
            .navigationTitle("Gestionar canales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAdding) {
                AddChannelView { channel in await store.add(channel) }
            }
        }
        .tint(Color.cinemaAccent)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cerrar") { dismiss() }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            EditButton()
            Button { isAdding = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Añadir canal")
        }
    }
}

private struct ChannelManagementRow: View {
    let channel: Channel
    let store: ChannelStore

    var body: some View {
        HStack {
            Image(systemName: channel.iconSymbolName)
                .font(.body.weight(.bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(hex: channel.tintHex), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.body.weight(.medium))
                Text(channel.source.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Activo", isOn: enabledBinding)
                .labelsHidden()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { channel.isEnabled },
            set: { enabled in Task { await store.setEnabled(enabled, for: channel.id) } }
        )
    }
}

@MainActor
private struct AddChannelView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: @MainActor (Channel) async -> Void

    @State private var name = ""
    @State private var shortName = ""
    @State private var source = Channel.Source.mediaset
    @State private var slug = ""
    @State private var urlText = ""
    @State private var headerProfile = Channel.HeaderProfile.rtve
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Identidad") {
                    TextField("Nombre", text: $name)
                    TextField("Siglas", text: $shortName).textInputAutocapitalization(.characters)
                }
                sourceSection
                Section {
                    Label("La dirección debe usar HTTPS.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuevo canal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .tint(Color.cinemaAccent)
    }

    private var sourceSection: some View {
        Section("Señal") {
            Picker("Tipo", selection: $source) {
                ForEach(Channel.Source.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if source == .mediaset {
                TextField("Slug, por ejemplo telecinco", text: $slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else if source == .atresplayer {
                TextField("Id de canal de Atresplayer", text: $slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField("URL HLS", text: $urlText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Cabeceras", selection: $headerProfile) {
                    ForEach(Channel.HeaderProfile.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Añadir") { Task { await save() } }
                .disabled(!isValid || isSaving)
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !shortName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if source == .mediaset || source == .atresplayer {
            return !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return URL(string: urlText)?.scheme == "https"
    }

    private func save() async {
        isSaving = true
        let usesSlug = source == .mediaset || source == .atresplayer
        let channel = Channel(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            shortName: String(shortName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4)),
            source: source,
            slug: usesSlug ? slug.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            directURL: source == .direct ? URL(string: urlText) : nil,
            headerProfile: source == .mediaset ? .mediaset : (source == .atresplayer ? .atresplayer : headerProfile),
            isEnabled: true,
            tintHex: "FF4D5F"
        )
        await onSave(channel)
        dismiss()
    }
}
