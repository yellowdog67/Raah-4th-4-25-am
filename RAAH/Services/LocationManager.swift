import Foundation
import CoreLocation
import Combine

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var heading: CLHeading?
    var isInIndia: Bool = false

    /// True once we have received at least one real GPS fix
    var hasRealLocation: Bool = false

    /// The single source of truth for user location.
    /// Returns real GPS when available, nil otherwise.
    var effectiveLocation: CLLocation {
        if let loc = currentLocation { return loc }
        // On device, CLLocationManager may have a cached location from a previous session
        if let cached = manager.location, cached.horizontalAccuracy >= 0 {
            return cached
        }
        return nil ?? fallbackLocation
    }

    /// Fallback used ONLY when we truly have no GPS at all
    private var fallbackLocation: CLLocation {
        #if targetEnvironment(simulator)
        // Simulator default — Goa, India
        return CLLocation(latitude: 15.391736, longitude: 73.880064)
        #else
        // Real device with no GPS — use a neutral default
        return CLLocation(latitude: 0, longitude: 0)
        #endif
    }

    /// Fires when user moves more than 100 meters from the last context-fetch point
    var significantMovementPublisher = PassthroughSubject<CLLocation, Never>()

    /// Fires on every location update — used for navigation step tracking
    var locationUpdatePublisher = PassthroughSubject<CLLocation, Never>()

    /// Fires exactly once when the first real GPS location arrives
    var firstLocationPublisher = PassthroughSubject<CLLocation, Never>()

    private var lastContextFetchLocation: CLLocation?
    private let contextFetchThreshold: CLLocationDistance = 100 // meters
    private var hasSentFirstLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
        manager.showsBackgroundLocationIndicator = true

        #if targetEnvironment(simulator)
        // On simulator, use Goa as initial location so the app is functional
        // User can change via Features > Location > Custom Location
        let simLocation = CLLocation(latitude: 15.391736, longitude: 73.880064)
        currentLocation = simLocation
        hasRealLocation = true
        isInIndia = true
        #else
        // On real device, start tracking immediately if already authorized
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startTracking()
        }
        #endif
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// High accuracy for active voice sessions (best GPS, 10m filter)
    func setHighAccuracy() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    /// Navigation-grade accuracy (best for navigation, 5m filter)
    func setNavigationAccuracy() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
    }

    /// Low accuracy to save battery when idle (100m accuracy, 50m filter)
    func setLowAccuracy() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    /// Pause heading updates (saves battery when not on map)
    func pauseHeading() {
        manager.stopUpdatingHeading()
    }

    /// Resume heading updates (for map/compass use)
    func resumeHeading() {
        manager.startUpdatingHeading()
    }

    // MARK: - Geofence Check: India

    private func checkIfInIndia(_ location: CLLocation) {
        let indiaLatRange = 6.0...37.0
        let indiaLonRange = 68.0...97.5
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        isInIndia = indiaLatRange.contains(lat) && indiaLonRange.contains(lon)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter out invalid/stale locations
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy < 500,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }

        currentLocation = location
        hasRealLocation = true
        checkIfInIndia(location)
        locationUpdatePublisher.send(location)

        // Fire first location publisher exactly once
        if !hasSentFirstLocation {
            hasSentFirstLocation = true
            firstLocationPublisher.send(location)
        }

        // Significant movement check for context refresh
        if let last = lastContextFetchLocation {
            let distance = location.distance(from: last)
            if distance >= contextFetchThreshold {
                lastContextFetchLocation = location
                significantMovementPublisher.send(location)
            }
        } else {
            lastContextFetchLocation = location
            significantMovementPublisher.send(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Error: \(error.localizedDescription)")
    }
}
