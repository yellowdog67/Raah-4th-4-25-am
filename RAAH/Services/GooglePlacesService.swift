import Foundation
import CoreLocation

/// Fetches nearby places from Google Places API (New).
/// Two modes:
///   1. fetchNearbyPlaces — ambient context: 2 parallel bucket calls (food + attractions) = up to 40 POIs
///   2. searchText — on-demand tool search: queries Google's 200M+ place database by text
final class GooglePlacesService {

    private let nearbyEndpoint = "https://places.googleapis.com/v1/places:searchNearby"
    private let textSearchEndpoint = "https://places.googleapis.com/v1/places:searchText"

    private let fieldMask = [
        "places.id",
        "places.displayName",
        "places.location",
        "places.primaryType",
        "places.rating",
        "places.userRatingCount",
        "places.priceLevel",
        "places.currentOpeningHours",
        "places.regularOpeningHours",
        "places.businessStatus",
        "places.editorialSummary",
        "places.formattedAddress",
        "places.internationalPhoneNumber",
        "places.websiteUri"
    ].joined(separator: ",")

    // Bucket 1 — food & drink (all primaryType subtypes Google recognises)
    private let foodTypes = [
        "restaurant", "fast_food_restaurant", "cafe", "coffee_shop",
        "bar", "bakery", "meal_takeaway", "meal_delivery",
        "pizza_restaurant", "hamburger_restaurant", "sandwich_shop",
        "ice_cream_shop", "juice_shop", "dessert_shop", "food_court",
        "brunch_restaurant", "breakfast_restaurant", "steak_house",
        "seafood_restaurant", "indian_restaurant", "chinese_restaurant",
        "italian_restaurant", "mexican_restaurant", "thai_restaurant",
        "japanese_restaurant", "american_restaurant"
    ]

    // Bucket 2 — attractions, services, nature, shopping
    private let attractionTypes = [
        "tourist_attraction", "museum", "art_gallery",
        "historical_landmark", "cultural_landmark", "amusement_park",
        "park", "national_park", "beach", "botanical_garden",
        "zoo", "aquarium", "movie_theater", "night_club",
        "lodging", "camping_cabin",
        "pharmacy", "atm", "bank", "hospital", "doctor",
        "convenience_store", "supermarket", "grocery_store",
        "shopping_mall", "department_store",
        "gas_station", "car_rental", "bus_station", "train_station",
        "airport", "subway_station"
    ]

    // MARK: - Ambient fetch (2 buckets in parallel → up to 40 POIs)

    func fetchNearbyPlaces(coordinate: CLLocationCoordinate2D, radiusMeters: Int = 1500) async -> [POI] {
        guard APIKeys.isGooglePlacesConfigured else { return [] }

        // Run both buckets simultaneously
        async let foodResults = fetchBucket(types: foodTypes, coordinate: coordinate, radiusMeters: radiusMeters)
        async let attractionResults = fetchBucket(types: attractionTypes, coordinate: coordinate, radiusMeters: radiusMeters)

        let food = await foodResults
        let attractions = await attractionResults

        // Merge — deduplicate by 30m proximity (prefer whichever came first)
        var merged = food
        for poi in attractions {
            let poiLoc = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let isDuplicate = merged.contains { existing in
                CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    .distance(from: poiLoc) < 30
            }
            if !isDuplicate { merged.append(poi) }
        }

        return merged.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    // MARK: - On-demand Text Search (queries Google's full database by text)

    /// Called by the `search_nearby` AI tool. Searches Google's 200M+ place database
    /// for a specific query near the user. Not cached — always live.
    func searchText(query: String, coordinate: CLLocationCoordinate2D, radiusMeters: Int = 5000) async -> [POI] {
        guard APIKeys.isGooglePlacesConfigured else { return [] }

        let body: [String: Any] = [
            "textQuery": query,
            "maxResultCount": 5,
            "locationBias": [
                "circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": Double(radiusMeters)
                ]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: textSearchEndpoint) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIKeys.googlePlaces, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = bodyData

        print("[GooglePlaces] 🔍 Text search: '\(query)'")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            print("[GooglePlaces] ❌ Network error for text search '\(query)'")
            return []
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[GooglePlaces] ❌ HTTP \(http.statusCode) for text search '\(query)': \(body.prefix(300))")
            return []
        }
        let results = parsePlacesResponse(data, userCoordinate: coordinate)
        print("[GooglePlaces] ✅ Text search '\(query)': \(results.count) results — \(results.prefix(3).map(\.name).joined(separator: ", "))")
        return results
    }

    // MARK: - Internal: single-bucket Nearby Search

    private func fetchBucket(types: [String], coordinate: CLLocationCoordinate2D, radiusMeters: Int) async -> [POI] {
        let body: [String: Any] = [
            "includedTypes": types,
            "maxResultCount": 20,
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": Double(radiusMeters)
                ]
            ],
            "rankPreference": "DISTANCE"
        ]

        let bucketLabel = types.first ?? "unknown"
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: nearbyEndpoint) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIKeys.googlePlaces, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            print("[GooglePlaces] ❌ Network error for bucket '\(bucketLabel)'")
            return []
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[GooglePlaces] ❌ HTTP \(http.statusCode) for bucket '\(bucketLabel)': \(body.prefix(300))")
            return []
        }

        let results = parsePlacesResponse(data, userCoordinate: coordinate)
        print("[GooglePlaces] ✅ Bucket '\(bucketLabel)': \(results.count) places — \(results.prefix(3).map(\.name).joined(separator: ", "))")
        return results
    }

    // MARK: - Parsing

    private func parsePlacesResponse(_ data: Data, userCoordinate: CLLocationCoordinate2D) -> [POI] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let places = json["places"] as? [[String: Any]] else { return [] }

        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)

        return places.compactMap { place -> POI? in
            guard let displayName = place["displayName"] as? [String: Any],
                  let name = displayName["text"] as? String, !name.isEmpty else { return nil }

            guard let location = place["location"] as? [String: Any],
                  let lat = location["latitude"] as? Double,
                  let lon = location["longitude"] as? Double else { return nil }

            let businessStatus = place["businessStatus"] as? String ?? "OPERATIONAL"
            guard businessStatus != "CLOSED_PERMANENTLY" else { return nil }

            let placeLocation = CLLocation(latitude: lat, longitude: lon)
            let distance = userLocation.distance(from: placeLocation)
            let id = place["id"] as? String ?? "gp-\(name.hashValue)"
            let primaryType = place["primaryType"] as? String ?? ""

            var tags: [String: String] = ["source": "google", "primary_type": primaryType]

            if let rating = place["rating"] as? Double {
                tags["rating"] = String(format: "%.1f", rating)
            }
            if let count = place["userRatingCount"] as? Int {
                tags["user_ratings_total"] = count >= 1000
                    ? String(format: "%.1fk", Double(count) / 1000.0)
                    : "\(count)"
            }

            if let price = place["priceLevel"] as? String {
                let symbol = priceLevelSymbol(price)
                if !symbol.isEmpty { tags["price_level"] = symbol }
            }

            if businessStatus == "CLOSED_TEMPORARILY" {
                tags["business_status"] = "temporarily_closed"
            }

            // currentOpeningHours is holiday-aware (preferred); regularOpeningHours is the fallback
            let currentHours = place["currentOpeningHours"] as? [String: Any]
            let regularHours = place["regularOpeningHours"] as? [String: Any]
            let hoursSource = currentHours ?? regularHours

            // openNow comes only from currentOpeningHours — it's real-time
            if let openNow = currentHours?["openNow"] as? Bool {
                tags["is_open_now"] = openNow ? "true" : "false"
            }

            if let hours = hoursSource {
                if let weekdays = hours["weekdayDescriptions"] as? [String], !weekdays.isEmpty {
                    let weekday = Calendar.current.component(.weekday, from: Date())
                    let index = (weekday + 5) % 7
                    if index < weekdays.count {
                        let line = weekdays[index]
                        if let colon = line.firstIndex(of: ":") {
                            let hoursOnly = String(line[line.index(after: colon)...])
                                .trimmingCharacters(in: .whitespaces)
                            tags["today_hours"] = hoursOnly
                            let parts = hoursOnly.components(separatedBy: " – ")
                            if parts.count == 2 {
                                tags["opens_at"] = parts[0].trimmingCharacters(in: .whitespaces)
                                tags["closes_at"] = parts[1].trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                    tags["opening_hours_full"] = weekdays.joined(separator: "; ")
                }
            }

            if let summary = place["editorialSummary"] as? [String: Any],
               let text = summary["text"] as? String, !text.isEmpty {
                tags["editorial_summary"] = text
            }

            if let address = place["formattedAddress"] as? String { tags["address"] = address }
            if let website = place["websiteUri"] as? String { tags["website"] = website }
            if let phone = place["internationalPhoneNumber"] as? String { tags["phone"] = phone }

            return POI(
                id: id,
                name: name,
                type: POIType.fromGoogleType(primaryType),
                latitude: lat,
                longitude: lon,
                tags: tags,
                wikidataID: nil,
                wikipediaSummary: nil,
                distance: distance
            )
        }
        .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    private func priceLevelSymbol(_ level: String) -> String {
        switch level {
        case "PRICE_LEVEL_FREE":           return "Free"
        case "PRICE_LEVEL_INEXPENSIVE":    return "₹"
        case "PRICE_LEVEL_MODERATE":       return "₹₹"
        case "PRICE_LEVEL_EXPENSIVE":      return "₹₹₹"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "₹₹₹₹"
        default:                           return ""
        }
    }
}
