import Foundation
import CoreLocation

/// Local-first analytics logger. Stores events as JSON for later aggregation.
/// Ready to wire to Mixpanel/Amplitude with a one-line integration.
@Observable
final class AnalyticsLogger {

    // MARK: - Event Types

    enum EventType: String, Codable {
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case poiViewed = "poi_viewed"
        case snapUsed = "snap_used"
        case proactiveNarration = "proactive_narration"
        case feedbackGiven = "feedback_given"
        case walkMeHomeActivated = "walk_me_home_activated"
        case walkMeHomeDeactivated = "walk_me_home_deactivated"
        case sosTriggered = "sos_triggered"
        case paywallShown = "paywall_shown"
        case paywallConverted = "paywall_converted"
        case share = "share"
        case appOpen = "app_open"
        case directionRequested = "direction_requested"
        case webSearchUsed = "web_search_used"
    }

    struct AnalyticsEvent: Codable, Identifiable {
        let id: UUID
        let type: EventType
        let timestamp: Date
        let properties: [String: String]

        init(type: EventType, properties: [String: String] = [:]) {
            self.id = UUID()
            self.type = type
            self.timestamp = Date()
            self.properties = properties
        }
    }

    // MARK: - State

    private(set) var events: [AnalyticsEvent] = []

    // MARK: - Computed Stats

    var sessionsThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return events.filter { $0.type == .sessionStart && $0.timestamp >= weekAgo }.count
    }

    var totalSessions: Int {
        events.filter { $0.type == .sessionStart }.count
    }

    var poisDiscovered: Int {
        Set(events.filter { $0.type == .poiViewed }.compactMap { $0.properties["name"] }).count
    }

    var totalMinutesExplored: Int {
        let durations = events.filter { $0.type == .sessionEnd }.compactMap { Int($0.properties["duration_seconds"] ?? "") }
        return durations.reduce(0, +) / 60
    }

    var snapsThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return events.filter { $0.type == .snapUsed && $0.timestamp >= weekAgo }.count
    }

    var averageSessionDuration: TimeInterval {
        let durations = events.filter { $0.type == .sessionEnd }.compactMap { Double($0.properties["duration_seconds"] ?? "") }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var mostViewedPOIType: String? {
        let types = events.filter { $0.type == .poiViewed }.compactMap { $0.properties["type"] }
        let counted = Dictionary(grouping: types) { $0 }.mapValues { $0.count }
        return counted.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Logging

    private var pendingWrites = 0

    func log(_ type: EventType, properties: [String: String] = [:]) {
        let event = AnalyticsEvent(type: type, properties: properties)
        events.append(event)
        pendingWrites += 1
        // Batch writes: persist every 5 events or on critical events
        let criticalEvents: Set<EventType> = [.sessionEnd, .paywallConverted, .sosTriggered]
        if pendingWrites >= 5 || criticalEvents.contains(type) {
            persist()
            pendingWrites = 0
        }
    }

    /// Force flush pending events to disk.
    func flush() {
        guard pendingWrites > 0 else { return }
        persist()
        pendingWrites = 0
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("raah_analytics.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AnalyticsEvent].self, from: data) else { return }
        events = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Prune events older than 90 days to keep file size reasonable.
    func pruneOldEvents() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let before = events.count
        events.removeAll { $0.timestamp < cutoff }
        if events.count != before { persist() }
    }
}
