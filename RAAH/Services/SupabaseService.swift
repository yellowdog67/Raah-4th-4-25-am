import Foundation

final class SupabaseService {
    
    private var baseURL: String { APIKeys.supabaseURL }
    private var anonKey: String { APIKeys.supabaseAnonKey }
    
    var isConfigured: Bool {
        APIKeys.isSupabaseConfigured
    }
    
    // MARK: - Preferences
    
    func storePreference(_ preference: UserPreference) async throws {
        guard isConfigured else { return }
        
        let body: [String: Any] = [
            "id": preference.id.uuidString,
            "category": preference.category.rawValue,
            "value": preference.value,
            "confidence": preference.confidence,
            "extracted_from": preference.extractedFrom,
            "created_at": ISO8601DateFormatter().string(from: preference.createdAt)
        ]
        
        try await postRequest(table: "user_preferences", body: body)
    }
    
    func fetchPreferences(category: PreferenceCategory? = nil) async throws -> [UserPreference] {
        guard isConfigured else { return [] }
        
        var path = "/rest/v1/user_preferences?select=*&order=created_at.desc&limit=50"
        if let category {
            path += "&category=eq.\(category.rawValue)"
        }
        
        let data = try await getRequest(path: path)
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return jsonArray.compactMap { json -> UserPreference? in
            guard let _ = json["id"] as? String,
                  let categoryRaw = json["category"] as? String,
                  let category = PreferenceCategory(rawValue: categoryRaw),
                  let value = json["value"] as? String,
                  let confidence = json["confidence"] as? Double,
                  let extractedFrom = json["extracted_from"] as? String,
                  let _ = json["created_at"] as? String else { return nil }
            
            return UserPreference(category: category, value: value, confidence: confidence, extractedFrom: extractedFrom)
        }
    }
    
    // MARK: - Semantic Search (pgvector)
    
    func semanticSearch(query: String, limit: Int = 5) async throws -> [UserPreference] {
        guard isConfigured else { return [] }
        
        let body: [String: Any] = [
            "query": query,
            "match_count": limit
        ]
        
        let data = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await functionRequest(name: "semantic-search", body: data)
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] else {
            return []
        }
        
        return jsonArray.compactMap { json -> UserPreference? in
            guard let categoryRaw = json["category"] as? String,
                  let category = PreferenceCategory(rawValue: categoryRaw),
                  let value = json["value"] as? String,
                  let confidence = json["confidence"] as? Double else { return nil }
            
            return UserPreference(category: category, value: value, confidence: confidence, extractedFrom: "semantic_search")
        }
    }
    
    // MARK: - Interactions Log
    
    func logInteraction(_ interaction: Interaction) async throws {
        guard isConfigured else { return }
        
        var body: [String: Any] = [
            "id": interaction.id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: interaction.timestamp),
            "user_message": interaction.userMessage,
            "ai_response": interaction.aiResponse,
            "context_pois": interaction.contextPOIs
        ]
        
        if let location = interaction.location {
            body["latitude"] = location.latitude
            body["longitude"] = location.longitude
        }
        
        try await postRequest(table: "interactions", body: body)
    }
    
    // MARK: - HTTP Helpers
    
    private func getRequest(path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.requestFailed
        }
        return data
    }
    
    private func postRequest(table: String, body: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)/rest/v1/\(table)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.requestFailed
        }
    }
    
    private func functionRequest(name: String, body: Data) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/functions/v1/\(name)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.requestFailed
        }
        return data
    }
    
    enum SupabaseError: LocalizedError {
        case invalidURL
        case requestFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Supabase URL"
            case .requestFailed: return "Supabase request failed"
            }
        }
    }
}
