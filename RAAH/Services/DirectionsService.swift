import Foundation
import MapKit

/// Directions provider: OSRM (walking, free, global) → MKDirections (fallback).
/// Returns structured steps for live turn-by-turn navigation.
final class DirectionsService {

    /// A single navigation step with location for proximity tracking.
    struct NavigationStep: Identifiable {
        let id = UUID()
        let index: Int
        let instruction: String
        let distance: Double // meters
        let coordinate: CLLocationCoordinate2D // waypoint — endpoint of this step
    }

    /// Result of a directions request.
    struct DirectionsResult {
        let summary: String
        let steps: [NavigationStep]
        let destinationName: String
        let destinationCoordinate: CLLocationCoordinate2D
        let totalDistance: Double // meters
        let estimatedMinutes: Int
        let polyline: [CLLocationCoordinate2D] // full route geometry for map overlay
    }

    /// Get walking directions with structured steps.
    /// Tries OSRM first (works globally, proper pedestrian routing), then MKDirections as fallback.
    func getDirectionsWithSteps(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        locationName: String
    ) async -> DirectionsResult? {
        // OSRM — free, global, pedestrian-optimized
        if let result = await fetchOSRMDirections(from: origin, to: destination, destinationName: destinationName) {
            print("[Directions] OSRM success: \(result.steps.count) steps, \(Int(result.totalDistance))m")
            return result
        }
        print("[Directions] OSRM failed, trying MKDirections walking...")

        // MKDirections walking fallback
        if let result = await fetchMKDirections(from: origin, to: destination, type: .walking, destinationName: destinationName) {
            return result
        }
        print("[Directions] MKDirections walking failed, trying transit...")

        // MKDirections transit last resort
        if let result = await fetchMKDirections(from: origin, to: destination, type: .transit, destinationName: destinationName) {
            return result
        }

        print("[Directions] All providers failed")
        return nil
    }

    /// Text-only directions fallback (used when structured directions unavailable).
    func getDirections(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        locationName: String
    ) async -> String {
        if let result = await getDirectionsWithSteps(from: origin, to: destination, destinationName: destinationName, locationName: locationName) {
            return result.summary + mapsHandoffNote(destinationName: destinationName, coordinate: destination)
        }

        let distKm = distanceBetween(origin, destination) / 1000
        return "Couldn't find directions to \(destinationName) (\(String(format: "%.1f", distKm)) km away). " +
            "Try opening Apple Maps." +
            mapsHandoffNote(destinationName: destinationName, coordinate: destination)
    }

    /// Open destination in Apple Maps
    @MainActor
    static func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    // MARK: - OSRM (Primary — free, global, pedestrian)

    private func fetchOSRMDirections(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String
    ) async -> DirectionsResult? {
        // OSRM API: /route/v1/foot/lon1,lat1;lon2,lat2?steps=true&overview=full
        let urlString = "https://router.project-osrm.org/route/v1/foot/" +
            "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)" +
            "?steps=true&overview=full&geometries=geojson"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[OSRM] HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? String, code == "Ok",
                  let routes = json["routes"] as? [[String: Any]],
                  let route = routes.first,
                  let legs = route["legs"] as? [[String: Any]],
                  let leg = legs.first,
                  let osrmSteps = leg["steps"] as? [[String: Any]] else {
                print("[OSRM] Invalid response format")
                return nil
            }

            let totalDistance = route["distance"] as? Double ?? 0
            let totalDuration = route["duration"] as? Double ?? 0
            let estimatedMinutes = max(1, Int(totalDuration / 60))

            var steps: [NavigationStep] = []
            var summaryText = "Walking to \(destinationName) (\(String(format: "%.1f", totalDistance / 1000)) km, ~\(estimatedMinutes) min):\n"
            var stepIndex = 0

            for osrmStep in osrmSteps {
                guard let maneuver = osrmStep["maneuver"] as? [String: Any],
                      let maneuverType = maneuver["type"] as? String else { continue }

                // Skip "depart" and "arrive" — they're not real navigation instructions
                if maneuverType == "depart" || maneuverType == "arrive" { continue }

                let distance = osrmStep["distance"] as? Double ?? 0
                let streetName = osrmStep["name"] as? String ?? ""
                let modifier = maneuver["modifier"] as? String

                // Build human-readable instruction
                let instruction = buildOSRMInstruction(type: maneuverType, modifier: modifier, streetName: streetName)
                guard !instruction.isEmpty else { continue }

                // Waypoint: use the maneuver location (where the turn happens)
                guard let location = maneuver["location"] as? [Double], location.count == 2 else { continue }
                let coord = CLLocationCoordinate2D(latitude: location[1], longitude: location[0])

                stepIndex += 1
                summaryText += "\(stepIndex). \(instruction) (\(Int(distance))m)\n"

                steps.append(NavigationStep(
                    index: stepIndex,
                    instruction: instruction,
                    distance: distance,
                    coordinate: coord
                ))
            }

            guard !steps.isEmpty else {
                print("[OSRM] No usable steps")
                return nil
            }

            // Parse route geometry for map overlay
            var polyline: [CLLocationCoordinate2D] = []
            if let geometry = route["geometry"] as? [String: Any],
               let coords = geometry["coordinates"] as? [[Double]] {
                polyline = coords.compactMap { pair in
                    guard pair.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
            }

            return DirectionsResult(
                summary: summaryText,
                steps: steps,
                destinationName: destinationName,
                destinationCoordinate: destination,
                totalDistance: totalDistance,
                estimatedMinutes: estimatedMinutes,
                polyline: polyline
            )
        } catch {
            print("[OSRM] Network error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Convert OSRM maneuver type+modifier into a natural instruction.
    private func buildOSRMInstruction(type: String, modifier: String?, streetName: String) -> String {
        let street = streetName.isEmpty ? "" : " onto \(streetName)"

        switch type {
        case "turn":
            guard let mod = modifier else { return "Turn\(street)" }
            switch mod {
            case "left": return "Turn left\(street)"
            case "right": return "Turn right\(street)"
            case "slight left": return "Bear left\(street)"
            case "slight right": return "Bear right\(street)"
            case "sharp left": return "Sharp left\(street)"
            case "sharp right": return "Sharp right\(street)"
            case "uturn": return "Make a U-turn\(street)"
            case "straight": return "Continue straight\(street)"
            default: return "Turn \(mod)\(street)"
            }

        case "new name":
            return "Continue\(street)"

        case "end of road":
            if let mod = modifier {
                return "At the end of the road, turn \(mod)\(street)"
            }
            return "At the end of the road, continue\(street)"

        case "continue":
            if let mod = modifier, mod != "straight" {
                return "Keep \(mod)\(street)"
            }
            return "Continue straight\(street)"

        case "merge":
            return "Merge\(street)"

        case "fork":
            if let mod = modifier {
                return "At the fork, keep \(mod)\(street)"
            }
            return "At the fork, continue\(street)"

        case "roundabout", "rotary":
            if let mod = modifier {
                // OSRM gives exit number in modifier for roundabouts
                return "At the roundabout, take the \(mod) exit\(street)"
            }
            return "Go through the roundabout\(street)"

        case "roundabout turn":
            if let mod = modifier {
                return "Turn \(mod)\(street)"
            }
            return "Continue\(street)"

        case "notification":
            return "" // Skip notifications

        default:
            if let mod = modifier {
                return "\(type.capitalized) \(mod)\(street)"
            }
            return street.isEmpty ? "" : "Continue\(street)"
        }
    }

    // MARK: - MKDirections (Fallback)

    private func fetchMKDirections(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        type: MKDirectionsTransportType,
        destinationName: String
    ) async -> DirectionsResult? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = type
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else {
                print("[MKDirections] \(type == .transit ? "Transit" : "Walking") returned no routes")
                return nil
            }

            let modeLabel = type == .transit ? "Transit" : "Walking"
            print("[MKDirections] \(modeLabel) success: \(route.steps.filter { !$0.instructions.isEmpty }.count) steps, \(Int(route.distance))m")
            let travelMinutes = Int(route.expectedTravelTime / 60)

            var summaryText = "\(modeLabel) to \(destinationName) (\(String(format: "%.1f", route.distance / 1000)) km, ~\(travelMinutes) min):\n"

            var steps: [NavigationStep] = []
            var stepIndex = 0

            for step in route.steps where !step.instructions.isEmpty {
                stepIndex += 1
                summaryText += "\(stepIndex). \(step.instructions) (\(Int(step.distance))m)\n"

                let pointCount = step.polyline.pointCount
                let mapPoint = step.polyline.points()[max(0, pointCount - 1)]

                steps.append(NavigationStep(
                    index: stepIndex,
                    instruction: step.instructions,
                    distance: step.distance,
                    coordinate: mapPoint.coordinate
                ))
            }

            // Extract polyline from MKRoute
            var polylineCoords: [CLLocationCoordinate2D] = []
            let points = route.polyline.points()
            for i in 0..<route.polyline.pointCount {
                polylineCoords.append(points[i].coordinate)
            }

            return DirectionsResult(
                summary: summaryText,
                steps: steps,
                destinationName: destinationName,
                destinationCoordinate: destination,
                totalDistance: route.distance,
                estimatedMinutes: travelMinutes,
                polyline: polylineCoords
            )
        } catch {
            print("[MKDirections] \(type == .transit ? "Transit" : "Walking") error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func mapsHandoffNote(destinationName: String, coordinate: CLLocationCoordinate2D) -> String {
        "\n[User can open Apple Maps for navigation to \(destinationName).]"
    }

    private func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // MARK: - Heading Utilities (used by AppState for relative directions)

    /// Compute bearing from one coordinate to another (in degrees, 0-360).
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Convert a bearing relative to user's heading into a natural direction word.
    static func relativeDirection(bearing: Double, heading: Double) -> String {
        let relative = (bearing - heading + 360).truncatingRemainder(dividingBy: 360)
        switch relative {
        case 0..<30, 330..<360: return "straight ahead"
        case 30..<75: return "slightly to your right"
        case 75..<120: return "to your right"
        case 120..<165: return "behind you to the right"
        case 165..<195: return "behind you"
        case 195..<240: return "behind you to the left"
        case 240..<285: return "to your left"
        case 285..<330: return "slightly to your left"
        default: return "nearby"
        }
    }
}
