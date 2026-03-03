import SwiftUI
import MapKit

// MARK: - POI Share Card

/// A branded share card for a POI, rendered to image via ImageRenderer.
struct POIShareCard: View {
    let name: String
    let type: String
    let summary: String?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: iconForType(type))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(type.capitalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
            }

            HStack {
                Spacer()
                Text("Discovered with RAAH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(20)
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                }
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "historical": return "building.columns"
        case "religious": return "star.circle"
        case "cultural": return "theatermasks"
        case "food": return "fork.knife"
        case "nature": return "leaf"
        case "viewpoint": return "binoculars"
        case "market": return "bag"
        default: return "mappin.circle"
        }
    }
}

// MARK: - Exploration Share Card

/// A branded share card for a journal exploration session.
struct ExplorationShareCard: View {
    let locationName: String
    let date: Date
    let duration: TimeInterval
    let poiCount: Int
    let interactionCount: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(locationName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(date.formatted(date: .long, time: .omitted))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "map.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(accentColor)
            }

            HStack(spacing: 20) {
                shareStat(value: formatDuration(duration), label: "Duration")
                shareStat(value: "\(poiCount)", label: "Places")
                shareStat(value: "\(interactionCount)", label: "Chats")
            }

            HStack {
                Spacer()
                Text("Explored with RAAH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(20)
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                }
        }
    }

    private func shareStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Rendering Helpers

enum ShareCardRenderer {

    @MainActor
    static func renderPOICard(name: String, type: String, summary: String?, accentColor: Color) -> UIImage? {
        let card = POIShareCard(name: name, type: type, summary: summary, accentColor: accentColor)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    @MainActor
    static func renderExplorationCard(log: ExplorationLog, accentColor: Color) -> UIImage? {
        let card = ExplorationShareCard(
            locationName: log.locationName ?? "Exploration",
            date: log.date,
            duration: log.duration,
            poiCount: log.poisVisited.count,
            interactionCount: log.interactionCount,
            accentColor: accentColor
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
