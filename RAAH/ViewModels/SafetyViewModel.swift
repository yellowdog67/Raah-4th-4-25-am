import Foundation
import CoreLocation
import Combine
import UIKit

@Observable
final class SafetyViewModel {
    
    var currentSafetyLevel: SafetyLevel = .safe
    var alerts: [String] = []
    var isShareLocationActive: Bool = false
    var showingSafetySheet: Bool = false
    
    private let safetyService = SafetyScoreService()
    private var cancellables = Set<AnyCancellable>()
    private var monitoringTimer: Timer?
    
    // MARK: - Monitoring
    
    func startMonitoring(locationManager: LocationManager) {
        locationManager.significantMovementPublisher
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] location in
                Task { [weak self] in
                    await self?.evaluateLocation(location.coordinate)
                }
            }
            .store(in: &cancellables)
        
        // Periodic check every 5 minutes
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let coord = locationManager.currentLocation?.coordinate else { return }
            Task { [weak self] in
                await self?.evaluateLocation(coord)
            }
        }
    }
    
    func stopMonitoring() {
        cancellables.removeAll()
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    // MARK: - Evaluation
    
    private func evaluateLocation(_ coordinate: CLLocationCoordinate2D) async {
        let report = await safetyService.evaluateSafety(at: coordinate)
        
        let previousLevel = currentSafetyLevel
        currentSafetyLevel = report.level
        alerts = report.alerts + report.weatherWarnings
        
        // Proactive alert if safety drops
        if report.level < previousLevel && report.level <= .caution {
            showingSafetySheet = true
            HapticEngine.warning()
        }
    }
    
    // MARK: - Share Location
    
    func shareLocationWithEmergencyContact(
        location: CLLocationCoordinate2D,
        contactName: String,
        contactPhone: String,
        userName: String = "",
        locationName: String? = nil
    ) {
        isShareLocationActive = true
        let mapsURL = "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)"
        let address = locationName ?? "\(String(format: "%.5f", location.latitude)), \(String(format: "%.5f", location.longitude))"
        let name = userName.isEmpty ? "Someone" : userName
        let message = "SOS\n\(name) needs a safety check. please make sure im safe.\n📍 \(address)\n🗺 \(mapsURL)"
        let smsURL = "sms:\(contactPhone)?body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: smsURL) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
    }
    
    func stopSharingLocation() {
        isShareLocationActive = false
    }
}
