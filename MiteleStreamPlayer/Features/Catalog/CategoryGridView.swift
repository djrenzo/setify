import SwiftUI

struct CategoryGridView: View {
    let onSelect: (CatalogCategory) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Explorar").font(.title3.bold())
                Text("Series, programas y películas a la carta").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CatalogCategory.allCases) { category in
                    CategoryTile(category: category) { onSelect(category) }
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct CategoryTile: View {
    let category: CatalogCategory
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.cinemaAccent)
                    Spacer()
                    vodPill
                }
                Spacer(minLength: 18)
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .cinemaCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title), contenido a la carta")
    }

    private var vodPill: some View {
        Text("VOD")
            .font(.caption2.bold())
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(Color.cinemaAccent.opacity(0.85), in: .capsule)
    }
}
