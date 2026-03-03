import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    
    @State private var showingTranscript: Bool = false

    private var isSessionActive: Bool {
        appState.realtimeService.isConnected
    }
    
    private let timeOfDay = TimeOfDayPalette()
    
    var body: some View {
        ZStack {
            // Adaptive background
            backgroundLayer
            
            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.horizontal, RAAHTheme.Spacing.lg)
                    .padding(.top, RAAHTheme.Spacing.sm)

                Spacer(minLength: 0)

                // The Orb — center of everything
                orbSection

                Spacer(minLength: 0)

                // Context strip — only when transcript is hidden (can't fit both)
                if !appState.contextPipeline.nearbyPOIs.isEmpty && !showingTranscript {
                    contextStrip
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Transcript — compact card above buttons
                if showingTranscript {
                    transcriptCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, RAAHTheme.Spacing.lg)
                        .padding(.bottom, RAAHTheme.Spacing.xs)
                }

                // Action buttons
                actionButtons
                    .padding(.horizontal, RAAHTheme.Spacing.lg)
                    .padding(.bottom, RAAHTheme.Spacing.md)
            }
            
            // Safety alert overlay
            if appState.showingSafetyAlert {
                safetyBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // SOS countdown overlay
            if appState.isSOSCountdownActive {
                sosCountdownOverlay
                    .transition(.opacity)
            }
        }
        .animation(RAAHTheme.Motion.smooth, value: showingTranscript)
        .animation(RAAHTheme.Motion.smooth, value: appState.showingSafetyAlert)
        .animation(RAAHTheme.Motion.snappy, value: appState.isSOSCountdownActive)
        .onChange(of: appState.realtimeService.voiceState) { _, newState in
            if case .error = newState {
                showingTranscript = false
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundLayer: some View {
        ZStack {
            timeOfDay.backgroundGradient
                .ignoresSafeArea()
            
            // Subtle accent glow behind orb
            if isSessionActive {
                Circle()
                    .fill(appState.accentColor.opacity(appState.realtimeService.voiceState == .paused ? 0.03 : 0.08))
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(y: -50)
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(RAAHTheme.Typography.footnote(.medium))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                
                Text(appState.userName.isEmpty ? "Explorer" : appState.userName)
                    .font(RAAHTheme.Typography.title2())
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, RAAHTheme.Spacing.sm)
            .padding(.vertical, RAAHTheme.Spacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous))
            
            Spacer()
            
            HStack(spacing: 12) {
                // Audio route indicator
                if appState.audioSession.isAudioRouteExternal {
                    HStack(spacing: 4) {
                        Image(systemName: "airpodspro")
                            .font(.system(size: 12))
                        Text(appState.audioSession.currentRouteName)
                            .font(RAAHTheme.Typography.caption(.medium))
                    }
                    .foregroundStyle(appState.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(appState.accentColor.opacity(0.15))
                    }
                }
                
                // Walk Me Home indicator
                if appState.isWalkMeHomeActive {
                    walkMeHomeIndicator
                }

                // Navigation indicator
                if appState.isNavigating {
                    navigationIndicator
                }

                // Safety indicator
                if appState.safetyOverlayEnabled {
                    safetyIndicator
                }
            }
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }
    
    @State private var walkMeHomePulse = false

    private var walkMeHomeIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk")
                .font(.system(size: 12, weight: .semibold))
            Text("Walking")
                .font(RAAHTheme.Typography.caption(.semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.green.opacity(walkMeHomePulse ? 0.2 : 0.1))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                walkMeHomePulse = true
            }
        }
        .onTapGesture {
            appState.deactivateWalkMeHome()
        }
    }

    private var navigationIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("Navigating to \(appState.navigationDestination)")
                    .font(RAAHTheme.Typography.caption(.semibold))
                Text("Step \(appState.currentStepIndex + 1) of \(appState.navigationSteps.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue.opacity(0.8))
            }
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.blue.opacity(0.15))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.blue.opacity(0.4), lineWidth: 1)
        }
        .onTapGesture {
            appState.stopNavigation()
        }
    }

    private var safetyIndicator: some View {
        let level = appState.contextPipeline.currentContext?.safetyLevel ?? .safe
        return Image(systemName: level.icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(level.color)
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Circle()
                    .strokeBorder(level.color.opacity(0.3), lineWidth: 0.5)
            }
    }
    
    // MARK: - Orb Section
    
    private var orbSection: some View {
        VStack(spacing: RAAHTheme.Spacing.lg) {
            OrbView(
                style: appState.orbStyle,
                accentTheme: appState.accentTheme,
                voiceState: appState.realtimeService.voiceState,
                heartRate: appState.healthKit.currentHeartRate,
                size: isSessionActive ? RAAHTheme.Orb.sizeLarge : RAAHTheme.Orb.sizeMedium
            )
            .onTapGesture(count: 3) {
                appState.triggerSOS()
            }
            .onTapGesture {
                HapticEngine.medium()
                if appState.realtimeService.voiceState == .paused {
                    appState.realtimeService.resumeAudioCapture()
                } else {
                    toggleSession()
                }
            }
            .animation(RAAHTheme.Motion.smooth, value: isSessionActive)
            
            // Voice state label
            voiceStateLabel

            // Quick voice selector — only when idle and transcript is not open
            if !isSessionActive && !showingTranscript {
                voiceSelector
            }
        }
    }
    
    private var voiceStateLabel: some View {
        Group {
            switch appState.realtimeService.voiceState {
            case .paused:
                Text("Paused — tap to talk")
                    .font(RAAHTheme.Typography.subheadline(.medium))
                    .foregroundStyle(.secondary)
            case .idle:
                if isSessionActive {
                    Text("Listening...")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap the orb to start")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(.tertiary)
                }
            case .listening:
                HStack(spacing: 8) {
                    WaveformView(isActive: true, color: appState.accentColor)
                    Text("Listening")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(appState.accentColor)
                }
            case .thinking:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(appState.accentColor)
                    Text("Thinking...")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(.secondary)
                }
            case .speaking:
                HStack(spacing: 8) {
                    WaveformView(isActive: true, color: appState.accentColor)
                    Text("Speaking")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(appState.accentColor)
                }
            case .reconnecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.orange)
                    Text("Reconnecting...")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(.orange)
                }
            case .error(let msg):
                Text(msg)
                    .font(RAAHTheme.Typography.caption(.medium))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .animation(RAAHTheme.Motion.snappy, value: appState.realtimeService.voiceState)
    }
    
    // MARK: - Voice Selector

    private var voiceSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AIVoice.allCases, id: \.rawValue) { voice in
                    voiceChip(voice)
                }
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
        }
    }

    private func voiceChip(_ voice: AIVoice) -> some View {
        let selected = appState.selectedVoice == voice
        let bgColor: Color = selected ? appState.accentColor.opacity(0.15) : .white.opacity(0.06)
        let borderColor: Color = selected ? appState.accentColor.opacity(0.5) : .white.opacity(0.1)
        return Button {
            HapticEngine.selection()
            appState.selectedVoice = voice
        } label: {
            VStack(spacing: 3) {
                Text(voice.displayName)
                    .font(RAAHTheme.Typography.caption(.semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                Text(voice.description)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(bgColor))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Strip
    
    private var contextStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appState.contextPipeline.nearbyPOIs.prefix(5)) { poi in
                    poiChip(poi)
                }
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
        }
        .padding(.bottom, RAAHTheme.Spacing.sm)
    }
    
    private func poiChip(_ poi: POI) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.accentColor.opacity(0.3))
                .frame(width: 6, height: 6)
            
            Text(poi.name)
                .font(RAAHTheme.Typography.caption(.medium))
                .lineLimit(1)
            
            if let dist = poi.distance {
                Text("\(Int(dist))m")
                    .font(RAAHTheme.Typography.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
    }
    
    // MARK: - Transcript Card

    private var transcriptCard: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if !appState.realtimeService.lastTranscript.isEmpty {
                        Label {
                            Text(appState.realtimeService.lastTranscript)
                                .font(RAAHTheme.Typography.subheadline())
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Text("You")
                                .font(RAAHTheme.Typography.caption(.semibold))
                                .foregroundStyle(appState.accentColor)
                                .frame(width: 34, alignment: .leading)
                        }
                    }

                    if !appState.realtimeService.lastResponse.isEmpty {
                        Label {
                            Text(appState.realtimeService.lastResponse)
                                .font(RAAHTheme.Typography.subheadline())
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .id("responseBottom")
                        } icon: {
                            Text("AI")
                                .font(RAAHTheme.Typography.caption(.semibold))
                                .foregroundStyle(appState.accentColor)
                                .frame(width: 34, alignment: .leading)
                        }
                    }
                }
                .padding(RAAHTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .onChange(of: appState.realtimeService.lastResponse) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("responseBottom", anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Snap & Ask
            GlassIconButton(icon: "camera.fill") {
                HapticEngine.light()
                appState.showingSnapAndAsk = true
            }
            
            // Toggle session
            Button {
                HapticEngine.heavy()
                toggleSession()
            } label: {
                Image(systemName: isSessionActive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background {
                        Circle()
                            .fill(
                                isSessionActive
                                    ? AnyShapeStyle(Color.red.gradient)
                                    : AnyShapeStyle(appState.accentColor.gradient)
                            )
                    }
                    .shadow(color: (isSessionActive ? Color.red : appState.accentColor).opacity(0.4), radius: 16, y: 4)
            }
            .buttonStyle(.plain)
            
            // Toggle transcript
            GlassIconButton(icon: showingTranscript ? "text.bubble.fill" : "text.bubble") {
                HapticEngine.light()
                showingTranscript.toggle()
            }
        }
    }
    
    // MARK: - Safety Banner
    
    private var safetyBanner: some View {
        VStack {
            GlassCard(padding: RAAHTheme.Spacing.md) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safety Alert")
                            .font(RAAHTheme.Typography.headline())
                        Text("You've entered an area with lower safety ratings")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        appState.showingSafetyAlert = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
            .padding(.top, RAAHTheme.Spacing.sm)
            
            Spacer()
        }
    }
    
    // MARK: - SOS Countdown

    private var sosCountdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "sos")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.red)

                Text("Sending SOS in \(appState.sosCountdownSeconds)...")
                    .font(RAAHTheme.Typography.title2())
                    .foregroundStyle(.white)

                Button {
                    appState.cancelSOS()
                } label: {
                    Text("Cancel")
                        .font(RAAHTheme.Typography.headline())
                        .foregroundStyle(.white)
                        .frame(width: 160)
                        .padding(.vertical, 14)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions
    
    private func toggleSession() {
        if isSessionActive {
            appState.endVoiceSession()
            showingTranscript = false
        } else {
            appState.startVoiceSession()
            showingTranscript = true
        }
    }
}
