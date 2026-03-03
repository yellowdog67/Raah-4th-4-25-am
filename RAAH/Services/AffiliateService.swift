import Foundation
import CoreLocation

/// Checks GetYourGuide/Viator for skip-the-line tickets when user shows purchase intent.
/// Only surfaces offers organically — never unsolicited.
final class AffiliateService {
    
    func searchOffers(
        placeName: String,
        coordinate: CLLocationCoordinate2D? = nil
    ) async -> [AffiliateOffer] {
        
        // Try GetYourGuide first, then Viator
        if APIKeys.isGetYourGuideConfigured {
            let offers = await searchGetYourGuide(placeName: placeName, coordinate: coordinate)
            if !offers.isEmpty { return offers }
        }
        
        return []
    }
    
    // MARK: - GetYourGuide
    
    private func searchGetYourGuide(
        placeName: String,
        coordinate: CLLocationCoordinate2D?
    ) async -> [AffiliateOffer] {
        
        var urlComponents = URLComponents(string: "https://api.getyourguide.com/1/tours")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: placeName),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "currency", value: "USD")
        ]
        
        if let coord = coordinate {
            queryItems.append(URLQueryItem(name: "lat", value: "\(coord.latitude)"))
            queryItems.append(URLQueryItem(name: "lng", value: "\(coord.longitude)"))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(APIKeys.getYourGuideAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue(APIKeys.getYourGuidePartnerID, forHTTPHeaderField: "X-Partner-Id")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["data"] as? [[String: Any]] else { return [] }
            
            return results.compactMap { item -> AffiliateOffer? in
                guard let id = item["tour_id"] as? Int,
                      let title = item["title"] as? String,
                      let price = item["price"] as? [String: Any],
                      let amount = price["amount"] as? Double,
                      let currency = price["currency"] as? String else { return nil }
                
                let isSkipLine = title.lowercased().contains("skip") ||
                                 title.lowercased().contains("fast track") ||
                                 title.lowercased().contains("priority")
                
                return AffiliateOffer(
                    id: "\(id)",
                    poiName: placeName,
                    title: title,
                    price: String(format: "%.2f", amount),
                    currency: currency,
                    providerName: "GetYourGuide",
                    bookingURL: "https://www.getyourguide.com/activity/\(id)",
                    isSkipTheLine: isSkipLine,
                    rating: item["overall_rating"] as? Double
                )
            }
        } catch {
            return []
        }
    }
    
    // MARK: - Intent Detection
    
    /// Determines if the user's message indicates purchase intent
    static func detectsPurchaseIntent(in message: String) -> Bool {
        let intentPhrases = [
            "how much", "what's the price", "cost", "ticket",
            "i'd love to go", "let's go in", "can i visit",
            "want to visit", "how do i get in", "entry fee",
            "skip the line", "book", "reserve", "buy ticket"
        ]
        
        let lower = message.lowercased()
        return intentPhrases.contains { lower.contains($0) }
    }
}
