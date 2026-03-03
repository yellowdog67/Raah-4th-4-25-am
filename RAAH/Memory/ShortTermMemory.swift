import Foundation

/// Short-term memory: keeps the last 10 interactions for immediate conversation flow.
/// Uses local storage (UserDefaults-backed) for instant access — equivalent to Redis in the spec.
@Observable
final class ShortTermMemory {
    
    private let maxInteractions = 25
    private let storageKey: String

    var interactions: [Interaction] = []

    init(userId: UUID? = nil) {
        if let userId {
            self.storageKey = "raah_\(userId.uuidString.prefix(8))_short_term_memory"
        } else {
            self.storageKey = "raah_short_term_memory"
        }
        load()
    }
    
    func addInteraction(_ interaction: Interaction) {
        interactions.append(interaction)
        
        if interactions.count > maxInteractions {
            interactions.removeFirst(interactions.count - maxInteractions)
        }
        
        save()
    }
    
    func getRecentContext(count: Int = 20) -> [Interaction] {
        Array(interactions.suffix(count))
    }
    
    func clear() {
        interactions.removeAll()
        save()
    }
    
    var lastUserMessage: String? {
        interactions.last?.userMessage
    }
    
    var conversationSummary: String {
        interactions.suffix(5).map { interaction in
            "User: \(interaction.userMessage)\nAssistant: \(String(interaction.aiResponse.prefix(100)))"
        }.joined(separator: "\n---\n")
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let data = try? JSONEncoder().encode(interactions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Interaction].self, from: data) else { return }
        // Filter out interactions older than 24 hours — stale context confuses the AI
        let cutoff = Date().addingTimeInterval(-86400)
        interactions = saved.filter { $0.timestamp > cutoff }
        if interactions.count != saved.count {
            save() // Persist the cleanup
        }
    }
}
