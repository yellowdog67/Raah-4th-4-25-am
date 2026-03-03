import Foundation
import CoreLocation

/// Fetches nearby places from Google Places API (New) for accurate POI data.
/// Requires Places API (New) enabled and API key in APIKeys.googlePlaces.
final class GooglePlacesService {
    
    private let endpoint = "https://places.googleapis.com/v1/places:searchNearby"
    
    /// Fetches nearby restaurants, cafes, and food places; returns POIs sorted by distance.
    func fetchNearbyPlaces(coordinate: CLLocationCoordinate2D, radiusMeters: Int = 800) async throws -> [POI] {
        guard APIKeys.isGooglePlacesConfigured else { return [] }
        
        let body: [String: Any] = [
            "includedTypes": ["restaurant", "cafe", "meal_takeaway", "meal_delivery", "food"],
            "maxResultCount": 20,
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": Double(radiusMeters)
                ]
            ],
            "rankPreference": "DISTANCE"
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: endpoint) else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIKeys.googlePlaces, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.displayName,places.location,places.id", forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        
        return parsePlacesResponse(data, userCoordinate: coordinate)
    }
    
    private func parsePlacesResponse(_ data: Data, userCoordinate: CLLocationCoordinate2D) -> [POI] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let places = json["places"] as? [[String: Any]] else { return [] }
        
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        
        return places.compactMap { place -> POI? in
            let name: String
            if let displayName = place["displayName"] as? [String: Any], let text = displayName["text"] as? String {
                name = text
            } else if let n = place["name"] as? String {
                name = n.replacingOccurrences(of: "places/", with: "")
            } else {
                return nil
            }
            guard !name.isEmpty else { return nil }
            
            var lat: Double = 0, lon: Double = 0
            if let location = place["location"] as? [String: Any] {
                lat = location["latitude"] as? Double ?? 0
                lon = location["longitude"] as? Double ?? 0
            }
            
            let poiLocation = CLLocation(latitude: lat, longitude: lon)
            let distance = userLocation.distance(from: poiLocation)
            
            let id = place["id"] as? String ?? "gp-\(name.hashValue)"
            
            return POI(
                id: id,
                name: name,
                type: .commercial,
                latitude: lat,
                longitude: lon,
                tags: [:],
                wikidataID: nil,
                wikipediaSummary: nil,
                distance: distance
            )
        }.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
}
