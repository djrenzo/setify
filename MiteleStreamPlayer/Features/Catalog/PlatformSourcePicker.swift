import SwiftUI

enum PlatformSource: String, CaseIterable, Identifiable {
    case mitele = "Mitele"
    case atresplayer = "Atresplayer"

    var id: Self { self }
}

struct PlatformSourcePicker: View {
    @Binding var selection: PlatformSource

    var body: some View {
        Picker("Plataforma", selection: $selection) {
            ForEach(PlatformSource.allCases) { source in
                Text(source.rawValue).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityLabel("Plataforma de contenido")
    }
}
