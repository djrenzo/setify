import SwiftUI

extension Color {
    static let cinemaBackground = Color(red: 9 / 255, green: 10 / 255, blue: 13 / 255)
    static let cinemaSurface = Color(red: 24 / 255, green: 26 / 255, blue: 32 / 255)
    static let cinemaSurfaceRaised = Color(red: 43 / 255, green: 46 / 255, blue: 56 / 255)
    static let cinemaAccent = Color(red: 255 / 255, green: 77 / 255, blue: 95 / 255)

    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0xFF4D5F
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

struct CinemaCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cinemaSurface)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
    }
}

extension View {
    func cinemaCard() -> some View {
        modifier(CinemaCardModifier())
    }
}
