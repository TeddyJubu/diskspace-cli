import SwiftUI

// Shared palette used in the dashboard
extension Color {
    static let dsBackground = Color(red: 0.07, green: 0.09, blue: 0.12)
    static let dsCard       = Color(red: 0.12, green: 0.16, blue: 0.22)
    static let dsStroke     = Color.white.opacity(0.08)
    static let dsTextMuted  = Color.white.opacity(0.6)
    static let dsSky        = Color(red: 0.23, green: 0.67, blue: 0.96)
}

struct WidgetCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder var content: Content

    init(_ title: String, icon: String, iconColor: Color = .dsSky, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.dsCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.dsStroke, lineWidth: 1)
        )
    }
}

struct ProgressBar: View {
    var progress: Double // 0...1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Color.dsSky)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * progress)))
            }
        }
        .frame(height: 10)
    }
}
