import Foundation
import CoreLocation
import SwiftUI

// MARK: - App Navigation

enum AppTab: Int, CaseIterable {
    case home = 0
    case explore = 1
    case profile = 2
    
    var icon: String {
        switch self {
        case .home: return "waveform.circle.fill"
        case .explore: return "safari.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
    
    var label: String {
        switch self {
        case .home: return "Home"
        case .explore: return "Explore"
        case .profile: return "You"
        }
    }
}

// MARK: - Accent Theme

enum AccentTheme: String, CaseIterable, Codable {
    case violetAura
    case papayaFlame
    case neonMint
    case blush
    case iceBlue
    
    var color: Color {
        switch self {
        case .violetAura: return Color(hex: "7C3AED")
        case .papayaFlame: return Color(hex: "FF6D00")
        case .neonMint: return Color(hex: "00D9A6")
        case .blush: return Color(hex: "FF4F8B")
        case .iceBlue: return Color(hex: "00C2FF")
        }
    }
    
    var gradient: [Color] {
        switch self {
        case .violetAura: return [Color(hex: "7C3AED"), Color(hex: "A78BFA"), Color(hex: "4F46E5")]
        case .papayaFlame: return [Color(hex: "FF6D00"), Color(hex: "FBBF24"), Color(hex: "F97316")]
        case .neonMint: return [Color(hex: "00D9A6"), Color(hex: "34D399"), Color(hex: "06B6D4")]
        case .blush: return [Color(hex: "FF4F8B"), Color(hex: "F472B6"), Color(hex: "E11D48")]
        case .iceBlue: return [Color(hex: "00C2FF"), Color(hex: "38BDF8"), Color(hex: "6366F1")]
        }
    }
    
    var displayName: String {
        switch self {
        case .violetAura: return "Violet Aura"
        case .papayaFlame: return "Papaya Flame"
        case .neonMint: return "Neon Mint"
        case .blush: return "Blush"
        case .iceBlue: return "Ice Blue"
        }
    }
}

// MARK: - AI Voice

enum AIVoice: String, CaseIterable, Codable {
    case alloy
    case ash
    case ballad
    case coral
    case echo
    case sage
    case shimmer
    case verse

    var displayName: String {
        rawValue.capitalized
    }

    var description: String {
        switch self {
        case .alloy: return "Neutral & balanced"
        case .ash: return "Warm & confident"
        case .ballad: return "Soft & melodic"
        case .coral: return "Clear & friendly"
        case .echo: return "Deep & resonant"
        case .sage: return "Calm & wise"
        case .shimmer: return "Bright & energetic"
        case .verse: return "Rich & expressive"
        }
    }
}

// MARK: - Orb Style

enum OrbStyle: String, CaseIterable, Codable {
    case fluid
    case crystal
    case pulseRing
    
    var displayName: String {
        switch self {
        case .fluid: return "Fluid Orb"
        case .crystal: return "Crystal Orb"
        case .pulseRing: return "Pulse Ring"
        }
    }
    
    var description: String {
        switch self {
        case .fluid: return "Organic, flowing gradients that morph and breathe"
        case .crystal: return "Geometric facets with sharp light refractions"
        case .pulseRing: return "Concentric rings that expand and contract"
        }
    }
}

// MARK: - Voice State

enum VoiceState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case reconnecting
    case paused
    case error(String)

    static func == (lhs: VoiceState, rhs: VoiceState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening),
             (.thinking, .thinking), (.speaking, .speaking),
             (.reconnecting, .reconnecting), (.paused, .paused):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var isActive: Bool {
        switch self {
        case .listening, .thinking, .speaking, .reconnecting: return true
        default: return false
        }
    }
}

// MARK: - Safety

enum SafetyLevel: String, Codable, Comparable {
    case safe
    case moderate
    case caution
    case danger
    
    var score: Int {
        switch self {
        case .safe: return 4
        case .moderate: return 3
        case .caution: return 2
        case .danger: return 1
        }
    }
    
    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.score < rhs.score
    }
    
    var color: Color {
        switch self {
        case .safe: return .green
        case .moderate: return .yellow
        case .caution: return .orange
        case .danger: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .moderate: return "exclamationmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.shield.fill"
        }
    }
    
    var label: String {
        switch self {
        case .safe: return "Safe Area"
        case .moderate: return "Moderate"
        case .caution: return "Stay Alert"
        case .danger: return "High Risk"
        }
    }
}

struct SafetyZone: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let radius: Double
    let level: SafetyLevel
    let alerts: [String]
    let lastUpdated: Date
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Points of Interest

struct POI: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: POIType
    let latitude: Double
    let longitude: Double
    let tags: [String: String]
    let wikidataID: String?
    var wikipediaSummary: String?
    var distance: Double?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: POI, rhs: POI) -> Bool {
        lhs.id == rhs.id
    }
}

enum POIType: String, Codable {
    case heritage
    case architectural
    case museum
    case monument
    case streetFurniture
    case naturalFeature
    case religious
    case commercial
    // Utility & emergency
    case hospital
    case pharmacy
    case police
    case atm
    case fuel
    // Transport
    case busStop
    case trainStation
    case parking
    // Accommodation
    case hotel
    case unknown

    static func from(tags: [String: String]) -> POIType {
        if tags["heritage"] != nil { return .heritage }
        if tags["architectural_style"] != nil { return .architectural }
        if tags["tourism"] == "museum" { return .museum }
        if tags["historic"] == "monument" { return .monument }
        if tags["amenity"] == "place_of_worship" { return .religious }
        if tags["amenity"] == "hospital" || tags["amenity"] == "clinic" { return .hospital }
        if tags["amenity"] == "pharmacy" { return .pharmacy }
        if tags["amenity"] == "police" { return .police }
        if tags["amenity"] == "atm" || tags["amenity"] == "bank" { return .atm }
        if tags["amenity"] == "fuel" { return .fuel }
        if tags["amenity"] == "bus_station" || tags["highway"] == "bus_stop" || tags["public_transport"] == "stop_position" { return .busStop }
        if tags["railway"] == "station" || tags["railway"] == "halt" { return .trainStation }
        if tags["amenity"] == "parking" { return .parking }
        if tags["tourism"] == "hotel" || tags["tourism"] == "hostel" || tags["tourism"] == "guest_house" { return .hotel }
        if tags["street_furniture"] != nil { return .streetFurniture }
        if tags["natural"] != nil { return .naturalFeature }
        if tags["shop"] != nil || tags["amenity"] == "cafe" || tags["amenity"] == "restaurant" || tags["amenity"] == "fast_food" || tags["amenity"] == "bar" || tags["amenity"] == "pub" { return .commercial }
        return .unknown
    }
}

// MARK: - Memory & Interactions

struct Interaction: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let userMessage: String
    let aiResponse: String
    let location: LocationSnapshot?
    let contextPOIs: [String]
    
    init(userMessage: String, aiResponse: String, location: LocationSnapshot? = nil, contextPOIs: [String] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.userMessage = userMessage
        self.aiResponse = aiResponse
        self.location = location
        self.contextPOIs = contextPOIs
    }
}

struct LocationSnapshot: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

struct UserPreference: Identifiable, Codable {
    let id: UUID
    let category: PreferenceCategory
    let value: String
    let confidence: Double
    let extractedFrom: String
    let createdAt: Date
    
    init(category: PreferenceCategory, value: String, confidence: Double, extractedFrom: String) {
        self.id = UUID()
        self.category = category
        self.value = value
        self.confidence = confidence
        self.extractedFrom = extractedFrom
        self.createdAt = Date()
    }
}

enum PreferenceCategory: String, Codable, CaseIterable {
    case architecture
    case cuisine
    case nature
    case history
    case art
    case music
    case sport
    case culture
    case general
}

// MARK: - Exploration Journal

struct ExplorationLog: Identifiable, Codable {
    let id: UUID
    let date: Date
    var duration: TimeInterval
    let startLatitude: Double
    let startLongitude: Double
    var endLatitude: Double?
    var endLongitude: Double?
    var locationName: String?
    var poisVisited: [VisitedPOIEntry]
    var interactionCount: Int
    var weatherSummary: String?

    init(startLatitude: Double, startLongitude: Double, locationName: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.duration = 0
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.poisVisited = []
        self.interactionCount = 0
        self.locationName = locationName
    }
}

struct VisitedPOIEntry: Codable, Identifiable {
    var id: String { name }
    let name: String
    let type: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Dietary Restrictions

enum DietaryRestriction: String, CaseIterable {
    case vegetarian
    case vegan
    case halal
    case kosher
    case glutenFree

    var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .halal: return "Halal"
        case .kosher: return "Kosher"
        case .glutenFree: return "Gluten-free"
        }
    }

    var icon: String {
        switch self {
        case .vegetarian: return "🥬"
        case .vegan: return "🌱"
        case .halal: return "☪️"
        case .kosher: return "✡️"
        case .glutenFree: return "🌾"
        }
    }
}

// MARK: - User Profile

struct UserProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date

    /// Prefix for all UserDefaults keys belonging to this profile.
    var storagePrefix: String { "raah_\(id.uuidString.prefix(8))_" }

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
        self.createdAt = Date()
    }
}

// MARK: - Affiliate

struct AffiliateOffer: Identifiable, Codable {
    let id: String
    let poiName: String
    let title: String
    let price: String
    let currency: String
    let providerName: String
    let bookingURL: String
    let isSkipTheLine: Bool
    let rating: Double?
}

// MARK: - Opening Hours Checker

enum OpeningHoursChecker {

    private static let dayMap: [String: Int] = [
        "mo": 2, "tu": 3, "we": 4, "th": 5, "fr": 6, "sa": 7, "su": 1
    ]

    /// Returns a human-readable status like "OPEN NOW", "CLOSED — opens at 9 AM", "OPEN — closes at 5 PM".
    /// Returns nil if the format can't be parsed (AI gets raw hours string instead).
    static func status(hours: String, now: Date, timeZone: TimeZone) -> String? {
        let s = hours.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s == "24/7" { return "OPEN 24/7" }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        let nowMins = h * 60 + m
        let weekday = cal.component(.weekday, from: now) // 1=Sun ... 7=Sat

        let rules = s.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var anyRuleHadDaySpec = false

        for rule in rules {
            let lower = rule.lowercased()
            if lower == "off" || lower.contains("closed") || lower == "ph off" { continue }

            let (applies, timePart) = splitDayTime(rule: lower, weekday: weekday)

            // Track whether any rule used day prefixes (Mo-Fr, etc.)
            let ruleHasDaySpec = lower.components(separatedBy: " ").first.map { part in
                dayMap.keys.contains(where: { part.contains($0) })
            } ?? false
            if ruleHasDaySpec { anyRuleHadDaySpec = true }

            guard applies, let tp = timePart else { continue }

            let ranges = tp.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            for range in ranges {
                guard let (open, close) = parseTimeRange(range) else { continue }
                if nowMins >= open && nowMins < close {
                    let remaining = close - nowMins
                    return remaining <= 60
                        ? "OPEN — closes at \(fmtTime(close))"
                        : "OPEN NOW"
                } else if nowMins < open {
                    return "CLOSED — opens at \(fmtTime(open))"
                }
            }
            // Past all ranges for this matching rule
            return "CLOSED NOW"
        }

        // If rules had day specs but none matched today (e.g., "Mo-Fr" on Sunday)
        if anyRuleHadDaySpec { return "CLOSED TODAY" }

        return nil
    }

    private static func splitDayTime(rule: String, weekday: Int) -> (Bool, String?) {
        let parts = rule.components(separatedBy: " ").filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            // No day prefix — check if it's a bare time range
            if rule.contains(":") { return (true, rule) }
            return (false, nil)
        }
        let first = parts[0]
        if dayMap.keys.contains(where: { first.contains($0) }) {
            let timePart = parts.dropFirst().joined(separator: " ")
            return (dayMatches(spec: first, weekday: weekday), timePart)
        }
        // Not a day spec, treat whole thing as time
        if rule.contains(":") { return (true, rule) }
        return (false, nil)
    }

    private static func dayMatches(spec: String, weekday: Int) -> Bool {
        if spec.contains("-") {
            let rangeParts = spec.components(separatedBy: "-")
            guard rangeParts.count == 2,
                  let start = dayMap[String(rangeParts[0].prefix(2))],
                  let end = dayMap[String(rangeParts[1].prefix(2))] else { return false }
            return start <= end
                ? (weekday >= start && weekday <= end)
                : (weekday >= start || weekday <= end)
        }
        if spec.contains(",") {
            let days = spec.components(separatedBy: ",")
            return days.contains { dayMap[String($0.trimmingCharacters(in: .whitespaces).prefix(2))] == weekday }
        }
        return dayMap[String(spec.prefix(2))] == weekday
    }

    private static func parseTimeRange(_ s: String) -> (Int, Int)? {
        let parts = s.components(separatedBy: "-")
        guard parts.count == 2,
              let open = parseTime(parts[0]),
              let close = parseTime(parts[1]) else { return nil }
        return (open, close > open ? close : close + 24 * 60)
    }

    private static func parseTime(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.components(separatedBy: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return h * 60 + m
    }

    private static func fmtTime(_ totalMinutes: Int) -> String {
        let h = (totalMinutes / 60) % 24
        let m = totalMinutes % 60
        let period = h >= 12 ? "PM" : "AM"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return m == 0 ? "\(h12) \(period)" : "\(h12):\(String(format: "%02d", m)) \(period)"
    }
}

// MARK: - Context Payload

struct SpatialContext {
    let pois: [POI]
    let safetyLevel: SafetyLevel
    let safetyAlerts: [String]
    let nearbyOffers: [AffiliateOffer]
    let weatherWarning: String?
    let currentWeatherSummary: String?
    let weeklyForecast: String?
    let isInIndia: Bool
    // Location awareness
    let locationName: String?      // e.g. "Panaji, Goa, India"
    let countryCode: String?       // e.g. "IN"
    let timezone: String?          // e.g. "Asia/Kolkata"
    let localTime: String?         // e.g. "3:45 PM"
    // Emergency
    let emergencyNumbers: String?  // e.g. "Police: 100, Ambulance: 102, Fire: 101"
    // India-specific
    let indiaDigiPin: String?
    let indiaRoadAlerts: [String]?

    func systemPromptFragment(now: Date, timeZone: TimeZone) -> String {
        var parts: [String] = []

        // Fresh local time — computed live, never stale
        let timeFmt = DateFormatter()
        timeFmt.timeZone = timeZone
        timeFmt.dateFormat = "h:mm a, EEEE"
        let freshTime = timeFmt.string(from: now)

        // Location + live time
        if let loc = locationName, !loc.isEmpty {
            var locLine = "USER LOCATION: \(loc)"
            if let tz = timezone { locLine += " (timezone: \(tz))" }
            locLine += ". Local time: \(freshTime)"
            parts.append(locLine)
        } else {
            parts.append("CURRENT TIME: \(freshTime)")
        }

        if let emergency = emergencyNumbers, !emergency.isEmpty {
            parts.append("EMERGENCY NUMBERS: \(emergency)")
        }

        if let weather = currentWeatherSummary, !weather.isEmpty {
            parts.append("CURRENT WEATHER: \(weather)")
        }

        if let forecast = weeklyForecast, !forecast.isEmpty {
            parts.append("7-DAY FORECAST (use for questions about upcoming days, best day for sunset, rain tomorrow, etc.):\n\(forecast)")
        }

        if !pois.isEmpty {
            let poiDescriptions = pois.prefix(15).map { poi in
                var desc = "- \(poi.name) (\(poi.type.rawValue))"
                if let hours = poi.tags["opening_hours"], !hours.isEmpty {
                    if let status = OpeningHoursChecker.status(hours: hours, now: now, timeZone: timeZone) {
                        desc += " [\(status)]"
                    } else {
                        desc += " [hours: \(hours)]"
                    }
                }
                if let cuisine = poi.tags["cuisine"], !cuisine.isEmpty {
                    desc += " [cuisine: \(cuisine)]"
                }
                if let summary = poi.wikipediaSummary {
                    let truncated = summary.count > 100 ? String(summary.prefix(100)) + "..." : summary
                    desc += ": \(truncated)"
                }
                if let dist = poi.distance {
                    let walkMin = max(1, Int(dist / 80.0))
                    desc += " [\(Int(dist))m, ~\(walkMin) min walk]"
                }
                return desc
            }
            parts.append("NEARBY POINTS OF INTEREST:\n\(poiDescriptions.joined(separator: "\n"))")
        }

        if !nearbyOffers.isEmpty {
            let offerDescs = nearbyOffers.prefix(3).map {
                "- \($0.title) (\($0.currency) \($0.price)) — \($0.providerName)"
            }
            parts.append("SKIP-THE-LINE TICKETS & TOURS:\n\(offerDescs.joined(separator: "\n"))")
        }

        if safetyLevel < .safe {
            parts.append("SAFETY NOTICE: Current area safety level is \(safetyLevel.label). Alerts: \(safetyAlerts.joined(separator: ", "))")
        }

        if let weather = weatherWarning {
            parts.append("WEATHER WARNING: \(weather)")
        }

        if let digiPin = indiaDigiPin, !digiPin.isEmpty {
            parts.append("INDIA DIGIPIN (exact address code): \(digiPin)")
        }
        if let alerts = indiaRoadAlerts, !alerts.isEmpty {
            parts.append("ROAD ALERTS NEARBY: \(alerts.joined(separator: "; "))")
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Onboarding

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let permissionType: PermissionType?
}

enum PermissionType {
    case location
    case microphone
    case camera
    case health
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
