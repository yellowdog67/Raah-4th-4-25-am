import SwiftUI
import MapKit
import Combine

struct NavigationMapView: View {
    @Environment(AppState.self) private var appState
    @State private var mapCamera: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            mapLayer

            VStack {
                topBar
                Spacer()
                bottomCard
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            centerOnUser()
        }
        .onReceive(appState.locationManager.locationUpdatePublisher.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)) { _ in
            followUser()
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $mapCamera) {
            // Blue route polyline
            if appState.routePolyline.count >= 2 {
                MapPolyline(coordinates: appState.routePolyline)
                    .stroke(.blue, lineWidth: 5)
            }

            // User location
            UserAnnotation()

            // Turn point markers
            ForEach(appState.navigationSteps) { step in
                Annotation("", coordinate: step.coordinate) {
                    turnMarker(step: step)
                }
            }

            // Destination pin
            if let dest = appState.navigationDestinationCoordinate {
                Annotation(appState.navigationDestination, coordinate: dest) {
                    destinationMarker
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

    // MARK: - Turn Markers

    private func turnMarker(step: DirectionsService.NavigationStep) -> some View {
        let isCurrent = step.index == (appState.currentStepIndex < appState.navigationSteps.count
            ? appState.navigationSteps[appState.currentStepIndex].index
            : -1)
        let isCompleted = appState.navigationSteps.firstIndex(where: { $0.id == step.id })
            .map { $0 < appState.currentStepIndex } ?? false

        return ZStack {
            Circle()
                .fill(isCompleted ? Color.green : (isCurrent ? Color.blue : Color.white))
                .frame(width: 14, height: 14)
            Circle()
                .strokeBorder(isCompleted ? Color.green : Color.blue, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
    }

    private var destinationMarker: some View {
        ZStack {
            Circle()
                .fill(Color.red.gradient)
                .frame(width: 32, height: 32)
                .shadow(color: .red.opacity(0.4), radius: 8)
            Image(systemName: "mappin")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                HapticEngine.light()
                appState.stopNavigation()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }

            Spacer()

            Button {
                HapticEngine.light()
                centerOnUser()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .safeAreaPadding(.top, 0)
    }

    // MARK: - Bottom Card

    private var bottomCard: some View {
        VStack(spacing: 12) {
            // Current step instruction
            if appState.currentStepIndex < appState.navigationSteps.count {
                let step = appState.navigationSteps[appState.currentStepIndex]
                HStack(spacing: 12) {
                    Image(systemName: directionIcon(for: step.instruction))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.blue)
                        .frame(width: 48, height: 48)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.instruction)
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(Int(step.distance))m")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(appState.currentStepIndex + 1)/\(appState.navigationSteps.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 48, height: 48)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("Arriving at \(appState.navigationDestination)")
                        .font(.system(size: 16, weight: .semibold))

                    Spacer()
                }
            }

            // Destination + ETA
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.secondary)
                Text(appState.navigationDestination)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    HapticEngine.medium()
                    appState.stopNavigation()
                } label: {
                    Text("End")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.red.opacity(0.1)))
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 32)
    }

    // MARK: - Helpers

    private func centerOnUser() {
        let loc = appState.locationManager.effectiveLocation.coordinate
        let heading = appState.locationManager.heading?.trueHeading ?? 0
        mapCamera = .camera(MapCamera(
            centerCoordinate: loc,
            distance: 500,
            heading: heading,
            pitch: 45
        ))
    }

    private func followUser() {
        let loc = appState.locationManager.effectiveLocation.coordinate
        let heading = appState.locationManager.heading?.trueHeading ?? 0
        withAnimation(.easeInOut(duration: 0.5)) {
            mapCamera = .camera(MapCamera(
                centerCoordinate: loc,
                distance: 500,
                heading: heading,
                pitch: 45
            ))
        }
    }

    private func directionIcon(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("right") { return "arrow.turn.up.right" }
        if lower.contains("u-turn") { return "arrow.uturn.down" }
        if lower.contains("roundabout") { return "arrow.triangle.2.circlepath" }
        if lower.contains("continue") || lower.contains("straight") { return "arrow.up" }
        if lower.contains("merge") { return "arrow.merge" }
        if lower.contains("fork") { return "tuningfork" }
        return "arrow.up"
    }
}
