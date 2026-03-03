import Foundation
import CoreLocation

/// Fetches current weather from Open-Meteo (free, no API key) for the system prompt.
final class WeatherService {

    // Cached formatters (DateFormatter is expensive to create)
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()
    private static let isoFallbackFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let localTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a, EEE"; return f
    }()
    
    /// Returns a rich summary for the AI including sunrise/sunset/visibility.
    func fetchCurrentWeatherSummary(coordinate: CLLocationCoordinate2D) async -> String {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,visibility&daily=sunrise,sunset&timezone=auto&forecast_days=1"

        guard let url = URL(string: urlString) else { return "Weather unavailable." }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any] else { return "Weather unavailable." }

            let temp = current["temperature_2m"] as? Double ?? 0
            let humidity = (current["relative_humidity_2m"] as? Double) ?? Double(current["relative_humidity_2m"] as? Int ?? 0)
            let code = current["weather_code"] as? Int ?? 0
            let windSpeed = current["wind_speed_10m"] as? Double ?? 0
            let visibility = current["visibility"] as? Double ?? 0

            let condition = conditionFromCode(code)
            var summary = "\(Int(temp))°C, \(condition), humidity \(Int(humidity))%, wind \(Int(windSpeed)) km/h"

            if visibility < 10000 {
                summary += ", visibility \(Int(visibility / 1000)) km"
            }

            // Parse sunrise/sunset from daily data
            if let daily = json["daily"] as? [String: Any],
               let sunrises = daily["sunrise"] as? [String], let sunrise = sunrises.first,
               let sunsets = daily["sunset"] as? [String], let sunset = sunsets.first {
                let sunriseTime = formatTimeFromISO(sunrise)
                let sunsetTime = formatTimeFromISO(sunset)
                summary += ". Sunrise: \(sunriseTime), Sunset: \(sunsetTime)"
            }

            summary += "."
            return summary
        } catch {
            return "Weather unavailable."
        }
    }

    /// Returns a 7-day daily forecast so the AI can answer "when should I watch sunset this week?" etc.
    func fetchWeeklyForecast(coordinate: CLLocationCoordinate2D) async -> String {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max&timezone=auto&forecast_days=7"

        guard let url = URL(string: urlString) else { return "" }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let dates = daily["time"] as? [String],
                  let codes = daily["weather_code"] as? [Int],
                  let maxTemps = daily["temperature_2m_max"] as? [Double],
                  let minTemps = daily["temperature_2m_min"] as? [Double],
                  let sunrises = daily["sunrise"] as? [String],
                  let sunsets = daily["sunset"] as? [String] else { return "" }

            let precipChances = daily["precipitation_probability_max"] as? [Int] ?? Array(repeating: 0, count: dates.count)

            var lines: [String] = []
            for i in 0..<min(dates.count, 7) {
                let dayLabel: String
                if let date = Self.dayFormatter.date(from: dates[i]) {
                    dayLabel = Self.displayFormatter.string(from: date)
                } else {
                    dayLabel = dates[i]
                }
                let condition = conditionFromCode(codes[i])
                let sunriseTime = formatTimeFromISO(sunrises[i])
                let sunsetTime = formatTimeFromISO(sunsets[i])
                let rain = precipChances[i]
                lines.append("- \(dayLabel): \(condition), \(Int(minTemps[i]))–\(Int(maxTemps[i]))°C, rain \(rain)%, sunrise \(sunriseTime), sunset \(sunsetTime)")
            }

            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    /// Fetches timezone identifier and current local time from Open-Meteo.
    func fetchTimezone(coordinate: CLLocationCoordinate2D) async -> (timezone: String?, localTime: String?) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=temperature_2m&timezone=auto&forecast_days=1"
        guard let url = URL(string: urlString) else { return (nil, nil) }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
            let tz = json["timezone"] as? String
            // Compute local time from the timezone
            var localTime: String?
            if let tzName = tz, let timeZone = TimeZone(identifier: tzName) {
                let f = Self.localTimeFormatter
                f.timeZone = timeZone
                localTime = f.string(from: Date())
            }
            return (tz, localTime)
        } catch {
            return (nil, nil)
        }
    }

    /// Extracts "6:30 AM" from "2026-03-01T06:30"
    private func formatTimeFromISO(_ isoString: String) -> String {
        if let date = Self.isoFormatter.date(from: isoString) {
            return Self.timeFormatter.string(from: date)
        }
        if let date = Self.isoFallbackFormatter.date(from: isoString) {
            return Self.timeFormatter.string(from: date)
        }
        return isoString
    }
    
    private func conditionFromCode(_ code: Int) -> String {
        switch code {
        case 0: return "clear sky"
        case 1, 2, 3: return "partly cloudy"
        case 45, 48: return "foggy"
        case 51, 53, 55: return "drizzle"
        case 61, 63, 65: return "rain"
        case 71, 73, 75: return "snow"
        case 80, 81, 82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95, 96, 99: return "thunderstorm"
        default: return "variable"
        }
    }
}
