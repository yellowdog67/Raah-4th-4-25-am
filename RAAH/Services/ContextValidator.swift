import Foundation
import CoreLocation

/// Defines a category of data RAAH needs to answer user questions.
/// Each requirement knows how to check if it's satisfied and how to repair itself.
struct ContextRequirement {
    let id: String
    let label: String
    /// Example user questions this requirement enables.
    let sampleQueries: [String]
    /// Returns true if the current SpatialContext already satisfies this requirement.
    let isSatisfied: (SpatialContext) -> Bool
    /// Async repair: fetches the missing data and returns an updated context.
    /// Returns nil if repair is not possible.
    let repair: ((SpatialContext, CLLocationCoordinate2D) async -> SpatialContext?)?
}

/// Validates that a SpatialContext has enough data to handle the full range of user questions.
/// Runs after every context build. Logs gaps and auto-repairs what it can.
final class ContextValidator {

    private let weatherService = WeatherService()

    // MARK: - Requirements Registry

    /// Every data category RAAH should support. Add new ones here — they self-test and self-heal.
    lazy var requirements: [ContextRequirement] = [
        ContextRequirement(
            id: "location_name",
            label: "Location name (city/country)",
            sampleQueries: ["What city am I in?", "What country is this?", "What currency do they use here?", "What language do they speak?"],
            isSatisfied: { ctx in
                guard let loc = ctx.locationName, !loc.isEmpty else { return false }
                return true
            },
            repair: { ctx, coord in
                let (name, code) = await ReverseGeocoder.reverseGeocode(coordinate: coord)
                guard let name, !name.isEmpty else { return nil }
                var updated = ctx.replacing(locationName: name, countryCode: code)
                // Also fill emergency numbers if we got a country code
                if let code, updated.emergencyNumbers == nil {
                    let numbers = EmergencyNumbers.lookup(countryCode: code)
                    updated = updated.replacing(emergencyNumbers: numbers)
                }
                return updated
            }
        ),
        ContextRequirement(
            id: "timezone",
            label: "Local time and timezone",
            sampleQueries: ["What time is it here?", "What timezone am I in?", "Is it too late to visit?"],
            isSatisfied: { ctx in
                guard let tz = ctx.timezone, !tz.isEmpty else { return false }
                return true
            },
            repair: { ctx, coord in
                let (tz, localTime) = await WeatherService().fetchTimezone(coordinate: coord)
                guard let tz, !tz.isEmpty else { return nil }
                return ctx.replacing(timezone: tz, localTime: localTime)
            }
        ),
        ContextRequirement(
            id: "emergency_numbers",
            label: "Emergency numbers",
            sampleQueries: ["What's the emergency number?", "How do I call an ambulance?", "What's the police number here?"],
            isSatisfied: { ctx in
                guard let e = ctx.emergencyNumbers, !e.isEmpty else { return false }
                return true
            },
            repair: { ctx, coord in
                // Need country code — try reverse geocoding
                if let code = ctx.countryCode {
                    let numbers = EmergencyNumbers.lookup(countryCode: code)
                    return numbers != nil ? ctx.replacing(emergencyNumbers: numbers) : nil
                }
                let (_, code) = await ReverseGeocoder.reverseGeocode(coordinate: coord)
                guard let code else { return nil }
                let numbers = EmergencyNumbers.lookup(countryCode: code)
                return numbers != nil ? ctx.replacing(countryCode: code, emergencyNumbers: numbers) : nil
            }
        ),
        ContextRequirement(
            id: "current_weather",
            label: "Current weather",
            sampleQueries: ["What's the weather?", "Is it hot outside?", "How's the humidity?"],
            isSatisfied: { ctx in
                guard let w = ctx.currentWeatherSummary, !w.isEmpty, w != "Weather unavailable." else { return false }
                return true
            },
            repair: { [weatherService] ctx, coord in
                let summary = await weatherService.fetchCurrentWeatherSummary(coordinate: coord)
                guard !summary.isEmpty, summary != "Weather unavailable." else { return nil }
                return ctx.replacing(currentWeatherSummary: summary)
            }
        ),
        ContextRequirement(
            id: "weekly_forecast",
            label: "7-day forecast",
            sampleQueries: ["When should I watch sunset this week?", "Will it rain tomorrow?", "Best day for outdoor plans?"],
            isSatisfied: { ctx in
                guard let f = ctx.weeklyForecast, !f.isEmpty else { return false }
                return true
            },
            repair: { [weatherService] ctx, coord in
                let forecast = await weatherService.fetchWeeklyForecast(coordinate: coord)
                guard !forecast.isEmpty else { return nil }
                return ctx.replacing(weeklyForecast: forecast)
            }
        ),
        ContextRequirement(
            id: "sunrise_sunset",
            label: "Sunrise & sunset times",
            sampleQueries: ["When is sunset today?", "What time is sunrise?"],
            isSatisfied: { ctx in
                guard let w = ctx.currentWeatherSummary else { return false }
                return w.contains("Sunrise:") && w.contains("Sunset:")
            },
            repair: { [weatherService] ctx, coord in
                let summary = await weatherService.fetchCurrentWeatherSummary(coordinate: coord)
                guard summary.contains("Sunrise:") else { return nil }
                return ctx.replacing(currentWeatherSummary: summary)
            }
        ),
        ContextRequirement(
            id: "nearby_pois",
            label: "Nearby places",
            sampleQueries: ["Where's the nearest restaurant?", "Any museums nearby?", "Find me a coffee shop"],
            isSatisfied: { ctx in !ctx.pois.isEmpty },
            repair: nil
        ),
        ContextRequirement(
            id: "utility_pois",
            label: "Utility POIs (hospital, ATM, pharmacy, police)",
            sampleQueries: ["Where's the nearest ATM?", "I need a pharmacy", "Find me a hospital"],
            isSatisfied: { ctx in
                let utilityTypes: Set<POIType> = [.hospital, .pharmacy, .police, .atm, .fuel]
                return ctx.pois.contains { utilityTypes.contains($0.type) }
            },
            repair: nil // Covered by expanded Overpass query
        ),
        ContextRequirement(
            id: "transport_pois",
            label: "Transport POIs (bus stop, train station)",
            sampleQueries: ["Where's the nearest bus stop?", "How do I get to the train station?"],
            isSatisfied: { ctx in
                let transportTypes: Set<POIType> = [.busStop, .trainStation]
                return ctx.pois.contains { transportTypes.contains($0.type) }
            },
            repair: nil // Covered by expanded Overpass query
        ),
        ContextRequirement(
            id: "poi_enrichment",
            label: "Wikipedia context for top POIs",
            sampleQueries: ["Tell me about that church", "What's the history of this place?"],
            isSatisfied: { ctx in
                let top3 = ctx.pois.prefix(3)
                guard !top3.isEmpty else { return true }
                return top3.contains { $0.wikipediaSummary != nil }
            },
            repair: nil
        ),
        ContextRequirement(
            id: "affiliate_offers",
            label: "Ticket/tour offers in prompt",
            sampleQueries: ["Can I skip the line at this museum?", "Are there any tours I can book?"],
            isSatisfied: { ctx in
                // Either no museums nearby (nothing to offer) or offers are present
                let hasMuseums = ctx.pois.contains { $0.type == .museum || $0.type == .monument }
                return !hasMuseums || !ctx.nearbyOffers.isEmpty
            },
            repair: nil
        ),
        ContextRequirement(
            id: "safety_assessed",
            label: "Safety assessment",
            sampleQueries: ["Is this area safe?", "Should I be careful here?"],
            isSatisfied: { _ in true },
            repair: nil
        )
    ]

    // MARK: - Validate & Repair

    struct ValidationReport {
        let gaps: [String]
        let gapLabels: [String]
        let repaired: [String]
    }

    func validateAndRepair(
        context: SpatialContext,
        coordinate: CLLocationCoordinate2D
    ) async -> (SpatialContext, ValidationReport) {
        var current = context
        var gaps: [String] = []
        var gapLabels: [String] = []
        var repaired: [String] = []

        for req in requirements {
            if !req.isSatisfied(current) {
                gaps.append(req.id)
                gapLabels.append(req.label)

                if let repairFn = req.repair {
                    if let fixed = await repairFn(current, coordinate) {
                        current = fixed
                        repaired.append(req.id)
                        print("[ContextValidator] Auto-repaired: \(req.label)")
                    } else {
                        print("[ContextValidator] Gap (repair failed): \(req.label) — e.g. \"\(req.sampleQueries.first ?? "")\"")
                    }
                } else {
                    print("[ContextValidator] Gap (no repair): \(req.label) — e.g. \"\(req.sampleQueries.first ?? "")\"")
                }
            }
        }

        return (current, ValidationReport(gaps: gaps, gapLabels: gapLabels, repaired: repaired))
    }
}

// MARK: - Reverse Geocoder (uses Apple's CLGeocoder — free, no API key)

enum ReverseGeocoder {
    static func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> (name: String?, countryCode: String?) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let place = placemarks.first else { return (nil, nil) }
            var parts: [String] = []
            if let subLocality = place.subLocality { parts.append(subLocality) }
            if let locality = place.locality { parts.append(locality) }
            if let adminArea = place.administrativeArea, adminArea != place.locality { parts.append(adminArea) }
            if let country = place.country { parts.append(country) }
            let name = parts.isEmpty ? nil : parts.joined(separator: ", ")
            return (name, place.isoCountryCode)
        } catch {
            print("[ReverseGeocoder] Failed: \(error.localizedDescription)")
            return (nil, nil)
        }
    }
}

// MARK: - Emergency Numbers (static lookup by ISO country code)

enum EmergencyNumbers {
    private static let table: [String: String] = [
        "IN": "Police: 100, Ambulance: 102, Fire: 101, Women helpline: 1091",
        "US": "911 (police, fire, ambulance)",
        "GB": "999 or 112 (police, fire, ambulance)",
        "FR": "Police: 17, Ambulance: 15, Fire: 18, EU emergency: 112",
        "DE": "Police: 110, Fire/Ambulance: 112",
        "IT": "Police: 113, Ambulance: 118, Fire: 115, EU emergency: 112",
        "ES": "112 (police, fire, ambulance)",
        "PT": "112 (police, fire, ambulance)",
        "NL": "112 (police, fire, ambulance)",
        "BE": "112 (police, fire, ambulance)",
        "CH": "Police: 117, Ambulance: 144, Fire: 118",
        "AT": "Police: 133, Ambulance: 144, Fire: 122, EU emergency: 112",
        "GR": "112 (police, fire, ambulance)",
        "TR": "Police: 155, Ambulance: 112, Fire: 110",
        "TH": "Police: 191, Ambulance: 1669, Fire: 199, Tourist police: 1155",
        "JP": "Police: 110, Fire/Ambulance: 119",
        "KR": "Police: 112, Fire/Ambulance: 119",
        "CN": "Police: 110, Ambulance: 120, Fire: 119",
        "AU": "000 (police, fire, ambulance)",
        "NZ": "111 (police, fire, ambulance)",
        "CA": "911 (police, fire, ambulance)",
        "MX": "911 (police, fire, ambulance)",
        "BR": "Police: 190, Ambulance: 192, Fire: 193",
        "ZA": "Police: 10111, Ambulance: 10177",
        "AE": "Police: 999, Ambulance: 998, Fire: 997",
        "SG": "Police: 999, Ambulance: 995",
        "MY": "Police: 999, Ambulance: 999, Fire: 994",
        "ID": "Police: 110, Ambulance: 118, Fire: 113",
        "VN": "Police: 113, Ambulance: 115, Fire: 114",
        "PH": "911 (police, fire, ambulance)",
        "EG": "Police: 122, Ambulance: 123, Fire: 180",
        "MA": "Police: 19, Ambulance: 15, Fire: 15",
        "KE": "999 (police, fire, ambulance)",
        "LK": "Police: 119, Ambulance: 110",
        "NP": "Police: 100, Ambulance: 102",
        "PE": "Police: 105, Fire: 116, Ambulance: 117",
        "CO": "123 (police, fire, ambulance)",
        "AR": "Police: 101, Ambulance: 107, Fire: 100",
        "CL": "Police: 133, Ambulance: 131, Fire: 132",
        "HR": "112 (police, fire, ambulance)",
        "CZ": "112 (police, fire, ambulance)",
        "PL": "Police: 997, Ambulance: 999, Fire: 998, EU emergency: 112",
        "HU": "112 (police, fire, ambulance)",
        "RO": "112 (police, fire, ambulance)",
        "SE": "112 (police, fire, ambulance)",
        "NO": "Police: 112, Ambulance: 113, Fire: 110",
        "DK": "112 (police, fire, ambulance)",
        "FI": "112 (police, fire, ambulance)",
        "IE": "112 or 999 (police, fire, ambulance)",
        "IL": "Police: 100, Ambulance: 101, Fire: 102"
    ]

    static func lookup(countryCode: String) -> String? {
        table[countryCode.uppercased()]
    }
}

// MARK: - SpatialContext Immutable Update Helpers

extension SpatialContext {
    func replacing(
        pois: [POI]? = nil,
        safetyLevel: SafetyLevel? = nil,
        safetyAlerts: [String]? = nil,
        nearbyOffers: [AffiliateOffer]? = nil,
        weatherWarning: String?? = nil,
        currentWeatherSummary: String?? = nil,
        weeklyForecast: String?? = nil,
        isInIndia: Bool? = nil,
        locationName: String?? = nil,
        countryCode: String?? = nil,
        timezone: String?? = nil,
        localTime: String?? = nil,
        emergencyNumbers: String?? = nil,
        indiaDigiPin: String?? = nil,
        indiaRoadAlerts: [String]?? = nil
    ) -> SpatialContext {
        SpatialContext(
            pois: pois ?? self.pois,
            safetyLevel: safetyLevel ?? self.safetyLevel,
            safetyAlerts: safetyAlerts ?? self.safetyAlerts,
            nearbyOffers: nearbyOffers ?? self.nearbyOffers,
            weatherWarning: weatherWarning ?? self.weatherWarning,
            currentWeatherSummary: currentWeatherSummary ?? self.currentWeatherSummary,
            weeklyForecast: weeklyForecast ?? self.weeklyForecast,
            isInIndia: isInIndia ?? self.isInIndia,
            locationName: locationName ?? self.locationName,
            countryCode: countryCode ?? self.countryCode,
            timezone: timezone ?? self.timezone,
            localTime: localTime ?? self.localTime,
            emergencyNumbers: emergencyNumbers ?? self.emergencyNumbers,
            indiaDigiPin: indiaDigiPin ?? self.indiaDigiPin,
            indiaRoadAlerts: indiaRoadAlerts ?? self.indiaRoadAlerts
        )
    }
}
