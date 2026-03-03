import Foundation

/// Wraps the Brave Search API for local knowledge queries.
/// Free tier: 2,000 queries/month, no credit card.
final class WebSearchService {

    private let session = URLSession.shared

    struct SearchResult {
        let title: String
        let snippet: String
        let url: String
    }

    /// Search Brave for local recommendations. Returns top results as text.
    func search(query: String, count: Int = 3) async -> [SearchResult] {
        guard APIKeys.isBraveConfigured else { return [] }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "text_decorations", value: "false"),
            URLQueryItem(name: "search_lang", value: "en")
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(APIKeys.braveSearch, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let web = json["web"] as? [String: Any],
                  let results = web["results"] as? [[String: Any]] else { return [] }

            return results.prefix(count).compactMap { item in
                guard let title = item["title"] as? String,
                      let url = item["url"] as? String else { return nil }
                let snippet = (item["description"] as? String) ?? ""
                return SearchResult(title: title, snippet: snippet, url: url)
            }
        } catch {
            print("[WebSearch] Error: \(error.localizedDescription)")
            return []
        }
    }

    /// Build a local-knowledge query from user intent + location.
    func searchLocal(query: String, locationName: String) async -> String {
        guard APIKeys.isBraveConfigured else {
            return "Web search is not configured. Answer based on your training data about \(locationName) instead."
        }
        let fullQuery = "\(query) \(locationName) site:reddit.com OR site:tripadvisor.com OR site:google.com/maps"
        let results = await search(query: fullQuery)

        if results.isEmpty {
            return "No web results found for \"\(query)\" near \(locationName). Try answering from your knowledge about the area."
        }

        var text = "Web search results for \"\(query)\" near \(locationName):\n"
        for (i, r) in results.enumerated() {
            text += "\(i + 1). \(r.title): \(r.snippet)\n"
        }
        return text
    }
}
