import Foundation
import CoreLocation

/// Continuously monitors user location against safety data.
/// If GeoSure API key is provided, uses their scores. Otherwise falls back to heuristic scoring.
final class SafetyScoreService {
    
    struct SafetyReport {
        let level: SafetyLevel
        let alerts: [String]
        let weatherWarnings: [String]
        let recommendation: String?
    }
    
    // MARK: - Public API
    
    func evaluateSafety(at coordinate: CLLocationCoordinate2D) async -> SafetyReport {
        if APIKeys.isGeoSureConfigured {
            return await fetchGeoSureScore(coordinate)
        }
        return await heuristicSafetyScore(coordinate)
    }
    
    func fetchWeatherAlerts(at coordinate: CLLocationCoordinate2D) async -> [String] {
        // Uses the free Open-Meteo API for weather warnings
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=weather_code&daily=weather_code&timezone=auto&forecast_days=1"
        
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let weatherCode = current["weather_code"] as? Int else { return [] }
            
            return weatherCodeToAlerts(weatherCode)
        } catch {
            return []
        }
    }
    
    // MARK: - GeoSure API
    
    private func fetchGeoSureScore(_ coordinate: CLLocationCoordinate2D) async -> SafetyReport {
        let urlString = "https://api.geosureglobal.com/score?lat=\(coordinate.latitude)&lng=\(coordinate.longitude)"
        guard let url = URL(string: urlString) else {
            return SafetyReport(level: .moderate, alerts: [], weatherWarnings: [], recommendation: nil)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(APIKeys.geoSure)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let overallScore = json["overall"] as? Double else {
                return SafetyReport(level: .moderate, alerts: [], weatherWarnings: [], recommendation: nil)
            }
            
            let level: SafetyLevel
            switch overallScore {
            case 70...: level = .safe
            case 50..<70: level = .moderate
            case 30..<50: level = .caution
            default: level = .danger
            }
            
            var alerts: [String] = []
            if let components = json["components"] as? [String: Double] {
                if let nightSafety = components["nighttime"], nightSafety < 40 {
                    alerts.append("Lower safety scores at night in this area")
                }
                if let theft = components["theft"], theft < 40 {
                    alerts.append("Elevated pickpocket risk reported")
                }
                if let women = components["women_safety"], women < 40 {
                    alerts.append("Exercise extra caution — lower women's safety rating")
                }
            }
            
            let weatherAlerts = await fetchWeatherAlerts(at: coordinate)
            
            return SafetyReport(
                level: level,
                alerts: alerts,
                weatherWarnings: weatherAlerts,
                recommendation: level < .safe ? "Consider sharing your live location with a trusted contact." : nil
            )
        } catch {
            return await heuristicSafetyScore(coordinate)
        }
    }
    
    // MARK: - Heuristic Fallback
    
    private func heuristicSafetyScore(_ coordinate: CLLocationCoordinate2D) async -> SafetyReport {
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour < 6 || hour > 21
        
        var alerts: [String] = []
        var level: SafetyLevel = .safe
        
        if isNight {
            level = .moderate
            alerts.append("It's late — stay aware of your surroundings")
        }
        
        let weatherAlerts = await fetchWeatherAlerts(at: coordinate)
        if !weatherAlerts.isEmpty {
            if level == .safe { level = .moderate }
            alerts.append(contentsOf: weatherAlerts)
        }
        
        return SafetyReport(
            level: level,
            alerts: alerts,
            weatherWarnings: weatherAlerts,
            recommendation: isNight ? "Consider sharing your live location with a trusted contact." : nil
        )
    }
    
    // MARK: - Weather Code Mapping
    
    private func weatherCodeToAlerts(_ code: Int) -> [String] {
        switch code {
        case 95, 96, 99: return ["Thunderstorm activity in the area"]
        case 71...77: return ["Snowfall conditions — roads may be slippery"]
        case 80...82: return ["Heavy rain showers — seek shelter if needed"]
        case 85, 86: return ["Heavy snow showers in the area"]
        case 65, 67: return ["Heavy rain — consider indoor activities"]
        case 56, 57: return ["Freezing drizzle — watch your step"]
        default: return []
        }
    }
}
