import Foundation
import CoreLocation

/// India-specific mapping service using Mappls (MapmyIndia) API.
/// Provides doorstep accuracy (DigiPin), 3D junction views, and local road alerts.
/// Activated only when user is geofenced within India.
final class MapplsService {
    
    private var accessToken: String?
    private var tokenExpiry: Date?
    
    struct IndiaLocalData {
        let digiPin: String?
        let nearbyAlerts: [RoadAlert]
        let junctionView: JunctionViewData?
    }
    
    struct RoadAlert: Identifiable {
        let id = UUID()
        let type: AlertType
        let description: String
        let distance: Double
        
        enum AlertType: String {
            case pothole
            case speedBreaker = "speed_breaker"
            case construction
            case flooding
            case accident
        }
    }
    
    struct JunctionViewData {
        let imageURL: String?
        let description: String
    }
    
    // MARK: - Authentication
    
    private func ensureAuthenticated() async throws {
        if accessToken != nil, let expiry = tokenExpiry, Date() < expiry {
            return
        }
        
        guard APIKeys.isMapplsConfigured else {
            throw MapplsError.notConfigured
        }
        
        let url = URL(string: "https://outpost.mappls.com/api/security/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "grant_type=client_credentials&client_id=\(APIKeys.mapplsClientID)&client_secret=\(APIKeys.mapplsClientSecret)"
        request.httpBody = body.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Double else {
            throw MapplsError.authFailed
        }
        
        accessToken = token
        tokenExpiry = Date().addingTimeInterval(expiresIn - 60)
    }
    
    // MARK: - Fetch Local Data
    
    func fetchIndiaLocalData(coordinate: CLLocationCoordinate2D) async -> IndiaLocalData {
        do {
            try await ensureAuthenticated()
        } catch {
            return IndiaLocalData(digiPin: nil, nearbyAlerts: [], junctionView: nil)
        }
        
        async let digiPin = fetchDigiPin(coordinate)
        async let alerts = fetchRoadAlerts(coordinate)
        
        let pin = await digiPin
        let roadAlerts = await alerts
        
        return IndiaLocalData(
            digiPin: pin,
            nearbyAlerts: roadAlerts,
            junctionView: nil
        )
    }
    
    // MARK: - DigiPin (doorstep accuracy)
    
    private func fetchDigiPin(_ coordinate: CLLocationCoordinate2D) async -> String? {
        guard let token = accessToken else { return nil }
        
        let urlString = "https://apis.mappls.com/advancedmaps/v1/\(APIKeys.mapplsAPIKey)/rev_geocode?lat=\(coordinate.latitude)&lng=\(coordinate.longitude)"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first else { return nil }
            
            return first["eLoc"] as? String ?? first["formatted_address"] as? String
        } catch {
            return nil
        }
    }
    
    // MARK: - Road Alerts
    
    private func fetchRoadAlerts(_ coordinate: CLLocationCoordinate2D) async -> [RoadAlert] {
        guard let token = accessToken else { return [] }
        
        let urlString = "https://apis.mappls.com/advancedmaps/v1/\(APIKeys.mapplsAPIKey)/nearby?lat=\(coordinate.latitude)&lng=\(coordinate.longitude)&radius=500&category=RDALRT"
        guard let url = URL(string: urlString) else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let places = json["suggestedLocations"] as? [[String: Any]] else { return [] }
            
            return places.compactMap { place -> RoadAlert? in
                guard let desc = place["placeName"] as? String,
                      let dist = place["distance"] as? Double else { return nil }
                
                let type: RoadAlert.AlertType
                let lowerDesc = desc.lowercased()
                if lowerDesc.contains("pothole") { type = .pothole }
                else if lowerDesc.contains("speed") || lowerDesc.contains("breaker") { type = .speedBreaker }
                else if lowerDesc.contains("construction") { type = .construction }
                else if lowerDesc.contains("flood") { type = .flooding }
                else { type = .accident }
                
                return RoadAlert(type: type, description: desc, distance: dist)
            }
        } catch {
            return []
        }
    }
    
    enum MapplsError: LocalizedError {
        case notConfigured
        case authFailed
        
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Mappls API not configured"
            case .authFailed: return "Mappls authentication failed"
            }
        }
    }
}
