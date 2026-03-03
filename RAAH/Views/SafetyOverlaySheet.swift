import SwiftUI
import CoreLocation

struct SafetyOverlaySheet: View {
    @Environment(AppState.self) private var appState
    @State private var safetyVM = SafetyViewModel()
    @Binding var isPresented: Bool
    
    var body: some View {
        GlassSheet(maxHeight: 480) {
            VStack(spacing: RAAHTheme.Spacing.lg) {
                safetyLevelHeader
                
                if !safetyVM.alerts.isEmpty {
                    alertsList
                }
                
                actionButtons
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
        }
        .onAppear {
            evaluateCurrent()
        }
    }
    
    private var safetyLevelHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(safetyVM.currentSafetyLevel.color.opacity(0.15))
                    .frame(width: 72, height: 72)
                
                Image(systemName: safetyVM.currentSafetyLevel.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(safetyVM.currentSafetyLevel.color)
            }
            
            Text(safetyVM.currentSafetyLevel.label)
                .font(RAAHTheme.Typography.title2())
            
            Text(descriptionForLevel(safetyVM.currentSafetyLevel))
                .font(RAAHTheme.Typography.subheadline())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func descriptionForLevel(_ level: SafetyLevel) -> String {
        switch level {
        case .safe: return "This area has good safety ratings. Enjoy your exploration!"
        case .moderate: return "Exercise normal caution in this area."
        case .caution: return "Stay alert. Consider sharing your location with a trusted contact."
        case .danger: return "High-risk area. We recommend sharing your live location and staying in well-lit areas."
        }
    }
    
    private var alertsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE ALERTS")
                .font(RAAHTheme.Typography.caption(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.5)
            
            ForEach(safetyVM.alerts, id: \.self) { alert in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    
                    Text(alert)
                        .font(RAAHTheme.Typography.subheadline())
                        .foregroundStyle(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: RAAHTheme.Radius.sm, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Walk Me Home button
            Button {
                HapticEngine.heavy()
                if appState.isWalkMeHomeActive {
                    appState.deactivateWalkMeHome()
                } else {
                    appState.activateWalkMeHome()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appState.isWalkMeHomeActive ? "figure.walk.circle.fill" : "figure.walk")
                    Text(appState.isWalkMeHomeActive ? "Walk Me Home Active" : "Walk Me Home")
                }
                .font(RAAHTheme.Typography.headline())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(appState.isWalkMeHomeActive ? Color.green.gradient : appState.accentColor.gradient)
                }
            }
            .buttonStyle(.plain)

            if safetyVM.currentSafetyLevel < .safe {
                Button {
                    HapticEngine.medium()
                    shareLocation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                        Text(safetyVM.isShareLocationActive ? "Sharing Location..." : "Share Live Location")
                    }
                    .font(RAAHTheme.Typography.headline())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Capsule()
                            .fill(safetyVM.isShareLocationActive ? Color.green.gradient : Color.orange.gradient)
                    }
                }
                .buttonStyle(.plain)
            }

            // Quick SOS
            if !appState.emergencyContactPhone.isEmpty {
                Button {
                    HapticEngine.error()
                    appState.triggerSOS()
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sos")
                        Text("Quick SOS")
                    }
                    .font(RAAHTheme.Typography.headline())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Capsule()
                            .fill(Color.red.gradient)
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                isPresented = false
            } label: {
                Text("Dismiss")
                    .font(RAAHTheme.Typography.subheadline(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func evaluateCurrent() {
        let coord = appState.locationManager.effectiveLocation.coordinate
        Task {
            let service = SafetyScoreService()
            let report = await service.evaluateSafety(at: coord)
            safetyVM.currentSafetyLevel = report.level
            safetyVM.alerts = report.alerts + report.weatherWarnings
        }
    }
    
    private func shareLocation() {
        let coord = appState.locationManager.effectiveLocation.coordinate
        safetyVM.shareLocationWithEmergencyContact(
            location: coord,
            contactName: appState.emergencyContactName,
            contactPhone: appState.emergencyContactPhone,
            userName: appState.userName,
            locationName: appState.contextPipeline.currentContext?.locationName
        )
    }
}
