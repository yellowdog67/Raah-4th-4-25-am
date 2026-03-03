import SwiftUI
import MapKit

struct ExploreMapView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ExploreViewModel()
    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var showingMapOptions: Bool = false
    @State private var shareImage: UIImage?
    @State private var showingShareSheet: Bool = false
    @State private var hasInitializedCamera: Bool = false

    var body: some View {
        ZStack {
            // Map
            mapLayer

            // Overlay controls
            VStack {
                topControls
                Spacer()
                if let poi = viewModel.selectedPOI {
                    poiDetailCard(poi)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(RAAHTheme.Motion.smooth, value: viewModel.selectedPOI?.id)
        }
        .sheet(isPresented: $showingMapOptions) {
            mapOptionsSheet
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ShareSheetView(items: [shareImage])
            }
        }
        .onAppear {
            centerOnCurrentLocation()
        }
        .onChange(of: appState.locationManager.hasRealLocation) { _, hasReal in
            // Re-center when first real GPS fix arrives
            if hasReal {
                centerOnCurrentLocation()
            }
        }
    }

    /// Center map on our known location (GPS or fallback)
    private func centerOnCurrentLocation() {
        let loc = appState.locationManager.effectiveLocation.coordinate
        mapCamera = .region(MKCoordinateRegion(
            center: loc,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        ))
    }
    
    private var mapOptionsSheet: some View {
        NavigationStack {
            List {
                Button {
                    HapticEngine.light()
                    centerOnCurrentLocation()
                    showingMapOptions = false
                } label: {
                    Label("Center on my location", systemImage: "location.fill")
                }
            }
            .navigationTitle("Map options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingMapOptions = false
                    }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
    
    // MARK: - Map
    
    private var mapLayer: some View {
        Map(position: $mapCamera) {
            UserAnnotation()
            
            ForEach(appState.contextPipeline.nearbyPOIs) { poi in
                Annotation(poi.name, coordinate: poi.coordinate) {
                    poiMarker(poi)
                        .onTapGesture {
                            HapticEngine.light()
                            viewModel.selectPOI(poi)
                        }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea()
    }
    
    private func poiMarker(_ poi: POI) -> some View {
        ZStack {
            Circle()
                .fill(appState.accentColor.gradient)
                .frame(width: 32, height: 32)
                .shadow(color: appState.accentColor.opacity(0.4), radius: 8)
            
            Image(systemName: iconForPOIType(poi.type))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    
    private func iconForPOIType(_ type: POIType) -> String {
        switch type {
        case .heritage: return "building.columns.fill"
        case .architectural: return "building.2.fill"
        case .museum: return "building.fill"
        case .monument: return "star.fill"
        case .streetFurniture: return "mappin.circle.fill"
        case .naturalFeature: return "leaf.fill"
        case .religious: return "moon.stars.fill"
        case .commercial: return "cup.and.saucer.fill"
        case .hospital: return "cross.circle.fill"
        case .pharmacy: return "pills.fill"
        case .police: return "shield.fill"
        case .atm: return "banknote.fill"
        case .fuel: return "fuelpump.fill"
        case .busStop: return "bus.fill"
        case .trainStation: return "tram.fill"
        case .parking: return "p.circle.fill"
        case .hotel: return "bed.double.fill"
        case .unknown: return "mappin"
        }
    }
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack {
            // Map options
            GlassIconButton(icon: "line.3.horizontal.decrease.circle") {
                HapticEngine.light()
                showingMapOptions = true
            }
            
            Spacer()
            
            // Re-center on user
            GlassIconButton(icon: "location.fill") {
                HapticEngine.light()
                centerOnCurrentLocation()
            }
        }
        .padding(.horizontal, RAAHTheme.Spacing.lg)
        .padding(.top, RAAHTheme.Spacing.xxl + 20)
    }
    
    // MARK: - POI Detail Card
    
    private func poiDetailCard(_ poi: POI) -> some View {
        GlassCard(padding: RAAHTheme.Spacing.lg, cornerRadius: RAAHTheme.Radius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(poi.name)
                            .font(RAAHTheme.Typography.title2())
                        
                        HStack(spacing: 6) {
                            Image(systemName: iconForPOIType(poi.type))
                                .font(.system(size: 12))
                                .foregroundStyle(appState.accentColor)
                            Text(poi.type.rawValue.capitalized)
                                .font(RAAHTheme.Typography.caption(.medium))
                                .foregroundStyle(.secondary)
                            
                            if let dist = poi.distance {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("\(Int(dist))m away")
                                    .font(RAAHTheme.Typography.caption())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.selectedPOI = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                
                if let summary = poi.wikipediaSummary {
                    Text(summary)
                        .font(RAAHTheme.Typography.subheadline())
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                
                HStack(spacing: 12) {
                    GlassPillButton("Ask RAAH", icon: "waveform", accentColor: appState.accentColor, isActive: true) {
                        HapticEngine.medium()
                        askAboutPOI(poi)
                    }

                    GlassPillButton("Directions", icon: "arrow.triangle.turn.up.right.diamond.fill") {
                        openInMaps(poi)
                    }

                    GlassPillButton("Share", icon: "square.and.arrow.up") {
                        HapticEngine.light()
                        sharePOI(poi)
                    }
                }
            }
        }
        .padding(.horizontal, RAAHTheme.Spacing.lg)
        .padding(.bottom, RAAHTheme.Spacing.xl)
    }
    
    // MARK: - Actions
    
    private func askAboutPOI(_ poi: POI) {
        appState.selectedTab = .home
        if appState.realtimeService.isConnected {
            appState.realtimeService.sendTextMessage("Tell me about \(poi.name)")
        }
    }
    
    private func openInMaps(_ poi: POI) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: poi.coordinate))
        mapItem.name = poi.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func sharePOI(_ poi: POI) {
        shareImage = ShareCardRenderer.renderPOICard(
            name: poi.name,
            type: poi.type.rawValue,
            summary: poi.wikipediaSummary,
            accentColor: appState.accentColor
        )
        if shareImage != nil {
            appState.analytics.log(.share, properties: ["type": "poi", "name": poi.name])
            showingShareSheet = true
        }
    }
}
