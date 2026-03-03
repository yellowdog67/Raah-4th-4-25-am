import SwiftUI
import MapKit

struct JournalView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if appState.explorationLogger.logs.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: RAAHTheme.Spacing.md) {
                        ForEach(appState.explorationLogger.logs) { log in
                            NavigationLink(value: log.id) {
                                journalCard(log)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, RAAHTheme.Spacing.lg)
                    .padding(.bottom, 40)
                }
            }
            .background {
                TimeOfDayPalette().backgroundGradient.ignoresSafeArea()
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { logID in
                if let log = appState.explorationLogger.logs.first(where: { $0.id == logID }) {
                    JournalDetailView(log: log)
                } else {
                    Text("Exploration log not found")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RAAHTheme.Spacing.md) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No explorations yet")
                .font(RAAHTheme.Typography.headline())
                .foregroundStyle(.secondary)
            Text("Start a voice session to begin logging your journey")
                .font(RAAHTheme.Typography.subheadline())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Card

    private func journalCard(_ log: ExplorationLog) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.locationName ?? "Unknown location")
                            .font(RAAHTheme.Typography.headline())
                            .foregroundStyle(.primary)
                        Text(log.date, style: .date)
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 16) {
                    statPill(icon: "clock", value: formatDuration(log.duration))
                    statPill(icon: "mappin", value: "\(log.poisVisited.count) places")
                    statPill(icon: "bubble.left", value: "\(log.interactionCount) chats")
                }

                if let weather = log.weatherSummary, !weather.isEmpty {
                    Text(weather)
                        .font(RAAHTheme.Typography.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(value)
                .font(RAAHTheme.Typography.caption(.medium))
        }
        .foregroundStyle(.secondary)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMin = minutes % 60
        return "\(hours)h \(remainingMin)m"
    }
}

// MARK: - Detail View

struct JournalDetailView: View {
    let log: ExplorationLog
    @Environment(AppState.self) private var appState
    @State private var shareImage: UIImage?
    @State private var showingShareSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: RAAHTheme.Spacing.lg) {
                // Map with pins
                if !log.poisVisited.isEmpty {
                    mapSection
                }

                // Info
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(icon: "calendar", label: "Date", value: log.date.formatted(date: .long, time: .shortened))
                        detailRow(icon: "clock", label: "Duration", value: formatDuration(log.duration))
                        detailRow(icon: "bubble.left", label: "Interactions", value: "\(log.interactionCount)")
                        if let weather = log.weatherSummary {
                            detailRow(icon: "cloud.sun", label: "Weather", value: weather)
                        }
                    }
                }

                // POIs visited
                if !log.poisVisited.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Places Visited")
                                .font(RAAHTheme.Typography.headline())
                            ForEach(log.poisVisited) { poi in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(appState.accentColor.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(poi.name)
                                            .font(RAAHTheme.Typography.body(.medium))
                                        Text(poi.type)
                                            .font(RAAHTheme.Typography.caption())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                // Share button
                GlassPillButton("Share Exploration", icon: "square.and.arrow.up", accentColor: appState.accentColor, isActive: true) {
                    HapticEngine.light()
                    shareImage = ShareCardRenderer.renderExplorationCard(log: log, accentColor: appState.accentColor)
                    if shareImage != nil {
                        appState.analytics.log(.share, properties: ["type": "exploration", "location": log.locationName ?? "unknown"])
                        showingShareSheet = true
                    }
                }
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
            .padding(.bottom, 40)
        }
        .background {
            TimeOfDayPalette().backgroundGradient.ignoresSafeArea()
        }
        .navigationTitle(log.locationName ?? "Exploration")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ShareSheetView(items: [shareImage])
            }
        }
    }

    private var mapSection: some View {
        let annotations = log.poisVisited.map { poi in
            JournalAnnotation(name: poi.name, coordinate: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude))
        }
        let center = CLLocationCoordinate2D(latitude: log.startLatitude, longitude: log.startLongitude)

        return Map(initialPosition: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        ))) {
            ForEach(annotations) { ann in
                Marker(ann.name, coordinate: ann.coordinate)
                    .tint(.orange)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: RAAHTheme.Radius.lg, style: .continuous))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(RAAHTheme.Typography.body())
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(RAAHTheme.Typography.body(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMin = minutes % 60
        return "\(hours)h \(remainingMin)m"
    }
}

struct JournalAnnotation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}
