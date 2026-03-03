import Foundation

/// Fetches summaries from Wikipedia/Wikivoyage for historical storytelling context.
final class WikipediaService {
    
    private let wikipediaEndpoint = "https://en.wikipedia.org/api/rest_v1/page/summary"
    private let wikivoyageEndpoint = "https://en.wikivoyage.org/api/rest_v1/page/summary"
    
    /// Fetch a Wikipedia summary for a POI using its wikidata ID or name
    func fetchSummary(for poi: POI) async -> String? {
        if let wikidataID = poi.wikidataID {
            if let summary = await fetchByWikidataID(wikidataID) {
                return summary
            }
        }
        
        if let summary = await fetchByTitle(poi.name, source: .wikipedia) {
            return summary
        }
        
        return await fetchByTitle(poi.name, source: .wikivoyage)
    }
    
    /// Fetch a city/area summary from Wikivoyage for storytelling
    func fetchAreaContext(placeName: String) async -> String? {
        if let result = await fetchByTitle(placeName, source: .wikivoyage) {
            return result
        }
        return await fetchByTitle(placeName, source: .wikipedia)
    }
    
    // MARK: - Private
    
    private enum Source {
        case wikipedia, wikivoyage
    }
    
    private func fetchByTitle(_ title: String, source: Source) async -> String? {
        let encoded = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        
        let baseURL = source == .wikipedia ? wikipediaEndpoint : wikivoyageEndpoint
        guard let url = URL(string: "\(baseURL)/\(encoded)") else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let extract = json["extract"] as? String else { return nil }
            
            let trimmed = trimToSentences(extract, maxSentences: 3)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
    
    private func fetchByWikidataID(_ id: String) async -> String? {
        let wikidataURL = "https://www.wikidata.org/wiki/Special:EntityData/\(id).json"
        guard let url = URL(string: wikidataURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entities = json["entities"] as? [String: Any],
                  let entity = entities[id] as? [String: Any],
                  let sitelinks = entity["sitelinks"] as? [String: Any],
                  let enwiki = sitelinks["enwiki"] as? [String: Any],
                  let title = enwiki["title"] as? String else { return nil }
            
            return await fetchByTitle(title, source: .wikipedia)
        } catch {
            return nil
        }
    }
    
    private func trimToSentences(_ text: String, maxSentences: Int) -> String {
        let sentences = text.components(separatedBy: ". ")
        let selected = sentences.prefix(maxSentences).joined(separator: ". ")
        return selected.hasSuffix(".") ? selected : selected + "."
    }
}
