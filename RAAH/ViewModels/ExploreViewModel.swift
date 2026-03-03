import SwiftUI
import MapKit
import Combine

@Observable
final class ExploreViewModel {
    
    var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var selectedPOI: POI?
    var mapStyle: MapStyleOption = .standard
    var showingPOIDetail: Bool = false
    var isFollowingUser: Bool = true
    
    enum MapStyleOption: String, CaseIterable {
        case standard = "Standard"
        case satellite = "Satellite"
        case hybrid = "Hybrid"
    }
    
    func centerOnUser(location: CLLocationCoordinate2D) {
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
    }
    
    func selectPOI(_ poi: POI) {
        selectedPOI = poi
        showingPOIDetail = true
        
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: poi.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
        }
    }
}
