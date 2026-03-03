import Foundation
import CoreLocation

/// Fetches hyperlocal POI data from OpenStreetMap's Overpass API.
/// Targets heritage, architectural_style, street_furniture, and other niche tags.
final class OverpassService {
    
    private let endpoint = "https://overpass-api.de/api/interpreter"
    
    /// Fetches POIs within a radius of the given coordinate (default 800m for better food/place coverage)
    func fetchNearbyPOIs(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 800
    ) async throws -> [POI] {
        
        let query = buildOverpassQuery(
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            radius: radiusMeters
        )
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(endpoint)?data=\(encodedQuery)") else {
            throw OverpassError.invalidQuery
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OverpassError.requestFailed
        }
        
        return try parseOverpassResponse(data, userCoordinate: coordinate)
    }
    
    // MARK: - Query Builder
    
    private func buildOverpassQuery(lat: Double, lon: Double, radius: Int) -> String {
        """
        [out:json][timeout:10];
        (
          node["heritage"](around:\(radius),\(lat),\(lon));
          node["architectural_style"](around:\(radius),\(lat),\(lon));
          node["historic"](around:\(radius),\(lat),\(lon));
          node["tourism"~"museum|monument|artwork|attraction|hotel|hostel|guest_house"](around:\(radius),\(lat),\(lon));
          node["amenity"~"restaurant|cafe|fast_food|bar|pub"](around:\(radius),\(lat),\(lon));
          node["amenity"="place_of_worship"](around:\(radius),\(lat),\(lon));
          node["amenity"~"hospital|clinic|pharmacy|police|atm|bank|fuel|parking|bus_station"](around:\(radius),\(lat),\(lon));
          node["highway"="bus_stop"](around:\(radius),\(lat),\(lon));
          node["railway"~"station|halt"](around:\(radius),\(lat),\(lon));
          node["street_furniture"](around:\(radius),\(lat),\(lon));
          way["heritage"](around:\(radius),\(lat),\(lon));
          way["architectural_style"](around:\(radius),\(lat),\(lon));
          way["building"]["name"](around:\(radius),\(lat),\(lon));
          way["historic"](around:\(radius),\(lat),\(lon));
          way["amenity"~"restaurant|cafe|fast_food|hospital|pharmacy|police"](around:\(radius),\(lat),\(lon));
          way["tourism"~"hotel|hostel|guest_house"](around:\(radius),\(lat),\(lon));
        );
        out center body;
        """
    }
    
    // MARK: - Response Parser
    
    private func parseOverpassResponse(_ data: Data, userCoordinate: CLLocationCoordinate2D) throws -> [POI] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            throw OverpassError.parseError
        }
        
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        
        var pois: [POI] = []
        var seenNames = Set<String>()
        
        for element in elements {
            let id = element["id"] as? Int ?? 0
            let tags = element["tags"] as? [String: String] ?? [:]
            
            let name = tags["name"] ?? tags["historic"] ?? tags["tourism"] ?? tags["amenity"] ?? "Unknown"
            
            // Skip duplicates and unnamed POIs (allow unnamed for heritage, tourism, amenity)
            guard !seenNames.contains(name), name != "Unknown" || tags["heritage"] != nil || tags["tourism"] != nil || tags["amenity"] != nil else { continue }
            seenNames.insert(name)
            
            var lat: Double
            var lon: Double
            
            if let center = element["center"] as? [String: Double] {
                lat = center["lat"] ?? 0
                lon = center["lon"] ?? 0
            } else {
                lat = element["lat"] as? Double ?? 0
                lon = element["lon"] as? Double ?? 0
            }
            
            let poiLocation = CLLocation(latitude: lat, longitude: lon)
            let distance = userLocation.distance(from: poiLocation)
            
            let poi = POI(
                id: "\(id)",
                name: name,
                type: POIType.from(tags: tags),
                latitude: lat,
                longitude: lon,
                tags: tags,
                wikidataID: tags["wikidata"],
                wikipediaSummary: nil,
                distance: distance
            )
            pois.append(poi)
        }
        
        return pois.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
    
    enum OverpassError: LocalizedError {
        case invalidQuery
        case requestFailed
        case parseError
        
        var errorDescription: String? {
            switch self {
            case .invalidQuery: return "Invalid Overpass query"
            case .requestFailed: return "Overpass API request failed"
            case .parseError: return "Could not parse Overpass response"
            }
        }
    }
}
