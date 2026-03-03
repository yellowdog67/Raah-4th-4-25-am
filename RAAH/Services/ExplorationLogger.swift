import Foundation
import CoreLocation

/// Manages exploration logs — auto-creates on voice session start,
/// finalizes on session end, persists as JSON in documents directory.
@Observable
final class ExplorationLogger {

    var logs: [ExplorationLog] = []
    var activeLog: ExplorationLog?

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("exploration_logs.json")
        load()
    }

    // MARK: - Session Lifecycle

    func startSession(coordinate: CLLocationCoordinate2D, locationName: String?) {
        activeLog = ExplorationLog(
            startLatitude: coordinate.latitude,
            startLongitude: coordinate.longitude,
            locationName: locationName
        )
    }

    func endSession(coordinate: CLLocationCoordinate2D, interactionCount: Int, weatherSummary: String?) {
        guard var log = activeLog else { return }
        log.duration = Date().timeIntervalSince(log.date)
        log.endLatitude = coordinate.latitude
        log.endLongitude = coordinate.longitude
        log.interactionCount = interactionCount
        log.weatherSummary = weatherSummary
        logs.insert(log, at: 0)
        activeLog = nil
        save()
    }

    func addVisitedPOI(name: String, type: String, coordinate: CLLocationCoordinate2D) {
        guard activeLog != nil else { return }
        let entry = VisitedPOIEntry(
            name: name,
            type: type,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Avoid duplicates
        if !activeLog!.poisVisited.contains(where: { $0.name == name }) {
            activeLog!.poisVisited.append(entry)
        }
    }

    func deleteLog(id: UUID) {
        logs.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([ExplorationLog].self, from: data) else { return }
        logs = saved
    }
}
