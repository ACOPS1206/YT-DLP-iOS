import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            GeometryReader { proxy in
                Ellipse()
                    .fill(.primary.opacity(scheme == .dark ? 0.055 : 0.045))
                    .frame(width: proxy.size.width * 1.4, height: 400)
                    .rotationEffect(.degrees(-25))
                    .offset(x: -100, y: 70)
                    .blur(radius: 50)
            }
        }
        .ignoresSafeArea()
    }
}

struct ContentCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
}

struct FormatChoice: View {
    let format: SaveFormat
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: format.symbol).font(.title3)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? .primary : .tertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.title).font(.headline)
                    Text(format.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.primary.opacity(0.08)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 24))
        .accessibilityLabel("\(format.title), \(format.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
