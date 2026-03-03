import Foundation

/// Long-term memory: extracts and stores user preferences from conversations.
/// Uses GPT-4o-mini to identify taste patterns, then persists to Supabase (pgvector).
/// On future sessions, proactively retrieves preferences to personalize the AI.
@Observable
final class LongTermMemoryManager {
    
    var preferences: [UserPreference] = []

    private let supabase = SupabaseService()
    private let localStorageKey: String

    init(userId: UUID? = nil) {
        if let userId {
            self.localStorageKey = "raah_\(userId.uuidString.prefix(8))_long_term_preferences"
        } else {
            self.localStorageKey = "raah_long_term_preferences"
        }
        loadLocal()
    }
    
    // MARK: - Extract Preferences from Conversation
    
    /// Runs after a session ends. Analyzes recent interactions to extract taste patterns.
    func extractPreferences(from interactions: [Interaction]) async {
        guard APIKeys.isOpenAIConfigured else { return }
        
        let conversationText = interactions.map { interaction in
            "User: \(interaction.userMessage)\nAssistant: \(interaction.aiResponse)"
        }.joined(separator: "\n---\n")
        
        let extractionPrompt = """
        Analyze this conversation between a travel AI and a user. Extract any user preferences \
        about architecture, cuisine, nature, history, art, music, sport, culture, or general interests.
        
        Return a JSON array of objects with:
        - "category": one of [architecture, cuisine, nature, history, art, music, sport, culture, general]
        - "value": a concise preference statement (e.g., "Loves Art Deco buildings")
        - "confidence": 0.0 to 1.0
        
        If no clear preferences are found, return an empty array [].
        Only extract preferences the user explicitly or strongly implied.
        
        Conversation:
        \(conversationText)
        """
        
        do {
            let extracted = try await callExtractionAPI(prompt: extractionPrompt)
            
            for pref in extracted {
                if !isDuplicate(pref) {
                    preferences.append(pref)
                    
                    if supabase.isConfigured {
                        try? await supabase.storePreference(pref)
                    }
                }
            }
            
            saveLocal()
        } catch {
            print("[LongTermMemory] Extraction failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Retrieve Preferences for Context
    
    func getPreferencesForPrompt() -> [UserPreference] {
        Array(preferences.sorted { $0.confidence > $1.confidence }.prefix(10))
    }
    
    func getPreferences(for category: PreferenceCategory) -> [UserPreference] {
        preferences.filter { $0.category == category }
    }
    
    /// Semantic search through Supabase pgvector for relevant preferences
    func searchRelevantPreferences(context: String) async -> [UserPreference] {
        guard supabase.isConfigured else {
            return preferences.prefix(5).map { $0 }
        }
        
        do {
            return try await supabase.semanticSearch(query: context, limit: 5)
        } catch {
            return preferences.prefix(5).map { $0 }
        }
    }
    
    // MARK: - Sync with Supabase
    
    func syncFromCloud() async {
        guard supabase.isConfigured else { return }
        
        do {
            let cloudPrefs = try await supabase.fetchPreferences()
            for pref in cloudPrefs {
                if !isDuplicate(pref) {
                    preferences.append(pref)
                }
            }
            saveLocal()
        } catch {
            print("[LongTermMemory] Cloud sync failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private
    
    private func isDuplicate(_ newPref: UserPreference) -> Bool {
        preferences.contains { existing in
            existing.category == newPref.category &&
            existing.value.lowercased() == newPref.value.lowercased()
        }
    }
    
    private func callExtractionAPI(prompt: String) async throws -> [UserPreference] {
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You extract user preferences from conversations. Always respond with valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APIKeys.openAI)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8) else {
            return []
        }
        
        // Parse the JSON response which might be {"preferences": [...]} or just [...]
        if let wrapper = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
           let prefsArray = wrapper["preferences"] as? [[String: Any]] {
            return parsePreferences(prefsArray)
        }
        
        if let prefsArray = try? JSONSerialization.jsonObject(with: contentData) as? [[String: Any]] {
            return parsePreferences(prefsArray)
        }
        
        return []
    }
    
    private func parsePreferences(_ array: [[String: Any]]) -> [UserPreference] {
        array.compactMap { item -> UserPreference? in
            guard let categoryRaw = item["category"] as? String,
                  let category = PreferenceCategory(rawValue: categoryRaw),
                  let value = item["value"] as? String else { return nil }
            
            let confidence = item["confidence"] as? Double ?? 0.5
            return UserPreference(category: category, value: value, confidence: confidence, extractedFrom: "conversation_extraction")
        }
    }
    
    // MARK: - Local Storage
    
    func saveLocal() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: localStorageKey)
        }
    }
    
    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let saved = try? JSONDecoder().decode([UserPreference].self, from: data) else { return }
        preferences = saved
    }
}
