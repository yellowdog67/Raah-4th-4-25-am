import SwiftUI
import AVFoundation
import CoreLocation

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    
    @State private var currentPage = 0
    @State private var userName: String = ""
    @State private var selectedInterests: Set<PreferenceCategory> = []
    @State private var selectedTheme: AccentTheme = .violetAura
    @State private var selectedOrb: OrbStyle = .fluid
    @State private var micGranted = false
    @State private var micRequested = false
    @State private var cameraGranted = false
    @State private var cameraRequested = false
    @State private var selectedDietary: Set<DietaryRestriction> = []

    private let totalPages = 5
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Subtle animated gradient
            Circle()
                .fill(selectedTheme.color.opacity(0.15))
                .frame(width: 500, height: 500)
                .blur(radius: 100)
                .offset(y: -100)
            
            VStack(spacing: 0) {
                // Progress dots
                progressDots
                    .padding(.top, RAAHTheme.Spacing.lg)
                
                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    interestsPage.tag(2)
                    themePage.tag(3)
                    permissionsPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(RAAHTheme.Motion.smooth, value: currentPage)
                
                // Bottom button
                bottomButton
                    .padding(.horizontal, RAAHTheme.Spacing.xl)
                    .padding(.bottom, RAAHTheme.Spacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Progress Dots
    
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i <= currentPage ? selectedTheme.color : Color.white.opacity(0.2))
                    .frame(width: i == currentPage ? 24 : 8, height: 8)
                    .animation(RAAHTheme.Motion.snappy, value: currentPage)
            }
        }
    }
    
    // MARK: - Page 1: Welcome
    
    private var welcomePage: some View {
        VStack(spacing: RAAHTheme.Spacing.xl) {
            Spacer()
            
            OrbView(
                style: .fluid,
                accentTheme: selectedTheme,
                voiceState: .idle,
                heartRate: nil,
                size: 180
            )
            
            VStack(spacing: RAAHTheme.Spacing.sm) {
                Text("RAAH")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .tracking(4)
                
                Text("Your voice in the world")
                    .font(RAAHTheme.Typography.title2(.regular))
                    .foregroundStyle(.secondary)
            }
            
            Text("An AI companion that turns every walk\ninto a conversation worth having.")
                .font(RAAHTheme.Typography.body())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RAAHTheme.Spacing.xl)
            
            Spacer()
        }
    }
    
    // MARK: - Page 2: Name
    
    private var namePage: some View {
        VStack(spacing: RAAHTheme.Spacing.xl) {
            Spacer()
            
            VStack(spacing: RAAHTheme.Spacing.sm) {
                Text("What should I\ncall you?")
                    .font(RAAHTheme.Typography.largeTitle())
                    .multilineTextAlignment(.center)
                
                Text("Your AI friend needs a name for you")
                    .font(RAAHTheme.Typography.body())
                    .foregroundStyle(.secondary)
            }
            
            TextField("Your name", text: $userName)
                .font(RAAHTheme.Typography.title2(.medium))
                .multilineTextAlignment(.center)
                .padding(.vertical, RAAHTheme.Spacing.md)
                .padding(.horizontal, RAAHTheme.Spacing.xl)
                .background {
                    RoundedRectangle(cornerRadius: RAAHTheme.Radius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .padding(.horizontal, RAAHTheme.Spacing.xxl)
            
            Spacer()
        }
    }
    
    // MARK: - Page 3: Interests
    
    private var interestsPage: some View {
        ScrollView {
            VStack(spacing: RAAHTheme.Spacing.xl) {
                VStack(spacing: RAAHTheme.Spacing.sm) {
                    Text("What excites you?")
                        .font(RAAHTheme.Typography.largeTitle())

                    Text("I'll tailor what I notice to your tastes")
                        .font(RAAHTheme.Typography.body())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, RAAHTheme.Spacing.xxl)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PreferenceCategory.allCases, id: \.rawValue) { category in
                        interestChip(category)
                    }
                }
                .padding(.horizontal, RAAHTheme.Spacing.lg)

                // Dietary preferences
                VStack(spacing: RAAHTheme.Spacing.sm) {
                    Text("Any dietary needs?")
                        .font(RAAHTheme.Typography.headline())

                    Text("So I never suggest the wrong food")
                        .font(RAAHTheme.Typography.caption())
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(DietaryRestriction.allCases, id: \.rawValue) { diet in
                        dietaryChip(diet)
                    }
                }
                .padding(.horizontal, RAAHTheme.Spacing.lg)
                .padding(.bottom, RAAHTheme.Spacing.xl)
            }
        }
    }
    
    private func interestChip(_ category: PreferenceCategory) -> some View {
        let isSelected = selectedInterests.contains(category)
        return Button {
            HapticEngine.selection()
            if isSelected {
                selectedInterests.remove(category)
            } else {
                selectedInterests.insert(category)
            }
        } label: {
            HStack {
                Text(iconFor(category))
                Text(category.rawValue.capitalized)
                    .font(RAAHTheme.Typography.subheadline(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .fill(isSelected ? selectedTheme.color.opacity(0.2) : Color.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? selectedTheme.color.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            }
            .foregroundStyle(isSelected ? selectedTheme.color : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    private func iconFor(_ category: PreferenceCategory) -> String {
        switch category {
        case .architecture: return "🏛"
        case .cuisine: return "🍜"
        case .nature: return "🌿"
        case .history: return "📜"
        case .art: return "🎨"
        case .music: return "🎵"
        case .sport: return "⚡"
        case .culture: return "🌍"
        case .general: return "✨"
        }
    }
    
    private func dietaryChip(_ diet: DietaryRestriction) -> some View {
        let isSelected = selectedDietary.contains(diet)
        return Button {
            HapticEngine.selection()
            if isSelected {
                selectedDietary.remove(diet)
            } else {
                selectedDietary.insert(diet)
            }
        } label: {
            HStack {
                Text(diet.icon)
                Text(diet.displayName)
                    .font(RAAHTheme.Typography.subheadline(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .fill(isSelected ? selectedTheme.color.opacity(0.2) : Color.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? selectedTheme.color.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            }
            .foregroundStyle(isSelected ? selectedTheme.color : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 4: Theme Picker
    
    private var themePage: some View {
        ScrollView {
            VStack(spacing: RAAHTheme.Spacing.xl) {
                VStack(spacing: RAAHTheme.Spacing.sm) {
                    Text("Make it yours")
                        .font(RAAHTheme.Typography.largeTitle())
                    
                    Text("Pick your vibe")
                        .font(RAAHTheme.Typography.body())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, RAAHTheme.Spacing.xl)
                
                // Accent colors
                VStack(alignment: .leading, spacing: 12) {
                    Text("ACCENT COLOR")
                        .font(RAAHTheme.Typography.caption(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                    
                    HStack(spacing: 16) {
                        ForEach(AccentTheme.allCases, id: \.rawValue) { theme in
                            accentColorButton(theme)
                        }
                    }
                }
                .padding(.horizontal, RAAHTheme.Spacing.lg)
                
                // Orb style
                VStack(alignment: .leading, spacing: 12) {
                    Text("ORB STYLE")
                        .font(RAAHTheme.Typography.caption(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                    
                    ForEach(OrbStyle.allCases, id: \.rawValue) { style in
                        orbStyleCard(style)
                    }
                }
                .padding(.horizontal, RAAHTheme.Spacing.lg)
                
                // Preview
                OrbView(
                    style: selectedOrb,
                    accentTheme: selectedTheme,
                    voiceState: .idle,
                    heartRate: nil,
                    size: 120
                )
                .padding(.top, RAAHTheme.Spacing.md)
            }
        }
    }
    
    private func accentColorButton(_ theme: AccentTheme) -> some View {
        Button {
            HapticEngine.selection()
            selectedTheme = theme
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.color.gradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if selectedTheme == theme {
                            Circle()
                                .strokeBorder(.white, lineWidth: 2.5)
                        }
                    }
                    .shadow(color: theme.color.opacity(0.4), radius: selectedTheme == theme ? 10 : 0)
                
                Text(theme.displayName)
                    .font(RAAHTheme.Typography.caption())
                    .foregroundStyle(selectedTheme == theme ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func orbStyleCard(_ style: OrbStyle) -> some View {
        Button {
            HapticEngine.selection()
            selectedOrb = style
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selectedOrb == style ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selectedOrb == style ? selectedTheme.color : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.displayName)
                        .font(RAAHTheme.Typography.body(.medium))
                        .foregroundStyle(.primary)
                    Text(style.description)
                        .font(RAAHTheme.Typography.caption())
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .fill(selectedOrb == style ? selectedTheme.color.opacity(0.1) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        selectedOrb == style ? selectedTheme.color.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Page 5: Permissions

    private var permissionsPage: some View {
        VStack(spacing: RAAHTheme.Spacing.xl) {
            Spacer()

            VStack(spacing: RAAHTheme.Spacing.sm) {
                Text("Almost there")
                    .font(RAAHTheme.Typography.largeTitle())

                Text("RAAH needs a few permissions\nto be your best companion")
                    .font(RAAHTheme.Typography.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                permissionRow(
                    icon: "location.fill",
                    title: "Location",
                    subtitle: "To know what's around you",
                    color: .blue,
                    granted: locationPermissionGranted,
                    denied: appState.locationManager.authorizationStatus == .denied
                ) {
                    appState.locationManager.requestPermission()
                }

                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "To hear your voice",
                    color: selectedTheme.color,
                    granted: micGranted,
                    denied: micRequested && !micGranted
                ) {
                    Task {
                        let granted = await appState.audioSession.requestMicPermission()
                        micGranted = granted
                        micRequested = true
                    }
                }

                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "For Snap & Ask",
                    color: .orange,
                    granted: cameraGranted,
                    denied: cameraRequested && !cameraGranted
                ) {
                    Task {
                        let granted = await withCheckedContinuation { continuation in
                            AVCaptureDevice.requestAccess(for: .video) { granted in
                                continuation.resume(returning: granted)
                            }
                        }
                        cameraGranted = granted
                        cameraRequested = true
                    }
                }

                permissionRow(
                    icon: "heart.fill",
                    title: "Health",
                    subtitle: "Heart rate for the orb (optional)",
                    color: .red,
                    granted: appState.healthKit.isAuthorized,
                    denied: false
                ) {
                    guard appState.healthKit.isAvailable else { return }
                    Task {
                        _ = await appState.healthKit.requestAuthorization()
                    }
                }
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)

            Text("You can change these anytime in Settings")
                .font(RAAHTheme.Typography.caption())
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .onAppear { checkPermissionStatuses() }
    }

    private var locationPermissionGranted: Bool {
        let s = appState.locationManager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    private func checkPermissionStatuses() {
        let micPerm = AVAudioApplication.shared.recordPermission
        micGranted = micPerm == .granted
        micRequested = micPerm != .undetermined

        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraGranted = camStatus == .authorized
        cameraRequested = camStatus != .notDetermined
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        granted: Bool,
        denied: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(granted ? .green : color)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill((granted ? Color.green : color).opacity(0.15))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RAAHTheme.Typography.body(.medium))
                Text(subtitle)
                    .font(RAAHTheme.Typography.caption())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
            } else if denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Settings")
                        .font(RAAHTheme.Typography.caption(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(Color.orange.opacity(0.15))
                        }
                }
            } else {
                Button {
                    HapticEngine.light()
                    action()
                } label: {
                    Text("Allow")
                        .font(RAAHTheme.Typography.caption(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(color.opacity(0.15))
                        }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                .fill(granted ? Color.green.opacity(0.04) : Color.white.opacity(0.04))
        }
    }
    
    // MARK: - Bottom Button
    
    private var bottomButton: some View {
        Button {
            HapticEngine.medium()
            if currentPage < totalPages - 1 {
                withAnimation { currentPage += 1 }
            } else {
                completeOnboarding()
            }
        } label: {
            Text(currentPage == totalPages - 1 ? "Let's explore" : "Continue")
                .font(RAAHTheme.Typography.headline())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background {
                    Capsule()
                        .fill(selectedTheme.color.gradient)
                }
                .shadow(color: selectedTheme.color.opacity(0.3), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .opacity(currentPage == 1 && userName.isEmpty ? 0.5 : 1.0)
        .disabled(currentPage == 1 && userName.isEmpty)
    }
    
    // MARK: - Actions
    
    private func completeOnboarding() {
        appState.userName = userName
        appState.accentTheme = selectedTheme
        appState.orbStyle = selectedOrb
        appState.hasCompletedOnboarding = true

        // Store interest preferences
        for interest in selectedInterests {
            let pref = UserPreference(
                category: interest,
                value: "User selected \(interest.rawValue) as an interest during onboarding",
                confidence: 0.8,
                extractedFrom: "onboarding"
            )
            appState.longTermMemory.preferences.append(pref)
        }

        // Store dietary restrictions
        if !selectedDietary.isEmpty {
            let dietaryString = selectedDietary.map(\.displayName).joined(separator: ", ")
            appState.dietaryRestrictions = dietaryString

            let pref = UserPreference(
                category: .cuisine,
                value: "Dietary restrictions: \(dietaryString)",
                confidence: 0.9,
                extractedFrom: "onboarding"
            )
            appState.longTermMemory.preferences.append(pref)
        }

        // Persist to disk immediately so preferences survive app close before first voice session
        appState.longTermMemory.saveLocal()
    }
}
