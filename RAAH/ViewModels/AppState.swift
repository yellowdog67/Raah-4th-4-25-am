import SwiftUI
import CoreLocation
import Combine

/// Central app state — owns all shared managers and persisted preferences.
@Observable
final class AppState {
    
    // MARK: - Profile

    let currentProfileId: UUID

    var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: profileKey("user_name")) }
    }
    var accentTheme: AccentTheme {
        didSet { UserDefaults.standard.set(accentTheme.rawValue, forKey: profileKey("accent_theme")) }
    }
    var orbStyle: OrbStyle {
        didSet { UserDefaults.standard.set(orbStyle.rawValue, forKey: profileKey("orb_style")) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: profileKey("onboarded")) }
    }
    var emergencyContactName: String {
        didSet { UserDefaults.standard.set(emergencyContactName, forKey: profileKey("emergency_name")) }
    }
    var emergencyContactPhone: String {
        didSet { UserDefaults.standard.set(emergencyContactPhone, forKey: profileKey("emergency_phone")) }
    }
    var safetyOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(safetyOverlayEnabled, forKey: profileKey("safety_enabled")) }
    }
    var dietaryRestrictions: String {
        didSet { UserDefaults.standard.set(dietaryRestrictions, forKey: profileKey("dietary")) }
    }
    var selectedVoice: AIVoice {
        didSet {
            UserDefaults.standard.set(selectedVoice.rawValue, forKey: profileKey("voice"))
            realtimeService.voice = selectedVoice.rawValue
            if realtimeService.isConnected {
                realtimeService.updateSystemPrompt(buildCurrentSystemPrompt())
            }
        }
    }

    func profileKey(_ base: String) -> String {
        "raah_\(currentProfileId.uuidString.prefix(8))_\(base)"
    }
    
    // MARK: - Navigation
    
    var selectedTab: AppTab = .home
    var showingSafetyAlert: Bool = false
    var showingSnapAndAsk: Bool = false
    var showingUpgradePrompt: Bool = false
    
    // MARK: - Shared Services
    
    let locationManager = LocationManager()
    let audioSession = AudioSessionManager()
    let healthKit = HealthKitManager()
    let contextPipeline = ContextPipeline()
    let shortTermMemory: ShortTermMemory
    let longTermMemory: LongTermMemoryManager
    let realtimeService = OpenAIRealtimeService()
    let explorationLogger = ExplorationLogger()
    let usageTracker = UsageTracker()
    let analytics = AnalyticsLogger()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Conversation Tracking

    private var pendingUserMessage: String = ""

    // MARK: - Proactive Narration

    private var mentionedPOIs: Set<String> = []
    private var lastProactiveNarrationTime: Date?
    private let proactiveNarrationCooldown: TimeInterval = 120
    private let proactiveNarrationRadius: Double = 80

    // MARK: - Post-Activity Feedback

    /// Tracks POIs the user may be visiting: poiID → (name, type, coordinate, firstSeen)
    private var dwellTracker: [String: DwellEntry] = [:]
    /// POIs the user has visited (stayed 10+ min) and moved away from
    private var visitedPOIs: Set<String> = []
    private var lastFeedbackRequestTime: Date?
    private let feedbackCooldown: TimeInterval = 900 // 15 min
    private let dwellThreshold: TimeInterval = 600   // 10 min
    private let dwellRadius: Double = 150             // meters
    private let departureRadius: Double = 300         // meters

    struct DwellEntry {
        let name: String
        let type: POIType
        let coordinate: CLLocationCoordinate2D
        let firstSeen: Date
        var feedbackGiven: Bool = false
    }

    // MARK: - Live Navigation

    var isNavigating: Bool = false
    var navigationSteps: [DirectionsService.NavigationStep] = []
    var currentStepIndex: Int = 0
    var navigationDestination: String = ""
    var routePolyline: [CLLocationCoordinate2D] = [] // full route for map overlay
    var navigationDestinationCoordinate: CLLocationCoordinate2D?
    private let waypointRadius: Double = 25 // meters — proximity to waypoint to trigger
    private let arrivalThreshold: Double = 25 // meters — consider arrived at destination
    private let minWalkDistance: Double = 25 // meters — absolute minimum walk before any trigger
    private var stepAnnouncedLocation: CLLocation? // where user was when current step was announced

    // MARK: - Usage Warning

    private var hasWarnedUsageLimit = false

    private func checkVoiceUsageWarning() {
        guard realtimeService.isConnected, !usageTracker.isProUser else { return }

        if !usageTracker.canUseVoice {
            endVoiceSession()
            showingUpgradePrompt = true
            return
        }

        if usageTracker.shouldWarnVoiceLimit && !hasWarnedUsageLimit {
            hasWarnedUsageLimit = true
            realtimeService.sendTextMessage(
                "Mention briefly to the user that they have about \(usageTracker.voiceMinutesRemaining) minutes remaining on their free tier today. Keep it casual — don't alarm them."
            )
        }
    }

    // MARK: - Quick SOS

    var isSOSCountdownActive: Bool = false
    var sosCountdownSeconds: Int = 3
    private var sosCountdownTask: Task<Void, Never>?

    func triggerSOS() {
        guard !emergencyContactPhone.isEmpty else { return }
        guard !isSOSCountdownActive else { return }

        analytics.log(.sosTriggered)
        isSOSCountdownActive = true
        sosCountdownSeconds = 3

        // Haptic burst: 3x heavy
        HapticEngine.heavy()
        HapticEngine.heavy()
        HapticEngine.heavy()

        sosCountdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for i in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else {
                    self.isSOSCountdownActive = false
                    return
                }
                self.sosCountdownSeconds = i
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    self.isSOSCountdownActive = false
                    return
                }
            }
            self.sendSOSMessage()
            self.isSOSCountdownActive = false
        }
    }

    func cancelSOS() {
        sosCountdownTask?.cancel()
        sosCountdownTask = nil
        isSOSCountdownActive = false
    }

    private func sendSOSMessage() {
        sendSafetySMS(reason: "triggered an emergency SOS alert")

        if realtimeService.isConnected {
            realtimeService.sendTextMessage(
                "Emergency SOS SMS has been sent to \(emergencyContactName.isEmpty ? "the emergency contact" : emergencyContactName). " +
                "Tell the user: 'SOS sent to \(emergencyContactName.isEmpty ? "your contact" : emergencyContactName). Help is on the way.'"
            )
        }

        HapticEngine.error()
    }

    /// Single unified function that sends every safety SMS.
    /// Format: "SOS\n[name] [reason]. please make sure im safe.\n📍 [address]\n🗺 [maps link]"
    func sendSafetySMS(reason: String) {
        guard !emergencyContactPhone.isEmpty else { return }
        let coord = locationManager.effectiveLocation.coordinate
        let mapsURL = "https://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)"
        let address = contextPipeline.currentContext?.locationName
            ?? "\(String(format: "%.5f", coord.latitude)), \(String(format: "%.5f", coord.longitude))"
        let name = userName.isEmpty ? "Someone" : userName
        let body = "SOS\n\(name) \(reason). please make sure im safe.\n📍 \(address)\n🗺 \(mapsURL)"
        let smsURL = "sms:\(emergencyContactPhone)?body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: smsURL) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Walk Me Home

    var isWalkMeHomeActive: Bool = false
    private var walkMeHomeTimer: Task<Void, Never>?
    private var missedCheckIns: Int = 0
    private var lastCheckInResponseTime: Date?
    private let checkInInterval: TimeInterval = 180 // 3 minutes
    private let maxMissedCheckIns = 2

    // MARK: - Computed

    var accentColor: Color { accentTheme.color }
    
    // MARK: - Init
    
    init() {
        let defaults = UserDefaults.standard

        // Resolve active profile (migrates old flat keys on first run)
        let profileId = Self.resolveProfileId()
        self.currentProfileId = profileId
        let p = "raah_\(profileId.uuidString.prefix(8))_"

        // Profile-scoped memory
        self.shortTermMemory = ShortTermMemory(userId: profileId)
        self.longTermMemory = LongTermMemoryManager(userId: profileId)

        // Profile-scoped preferences
        self.userName = defaults.string(forKey: "\(p)user_name") ?? ""
        self.accentTheme = AccentTheme(rawValue: defaults.string(forKey: "\(p)accent_theme") ?? "") ?? .violetAura
        self.orbStyle = OrbStyle(rawValue: defaults.string(forKey: "\(p)orb_style") ?? "") ?? .fluid
        self.hasCompletedOnboarding = defaults.bool(forKey: "\(p)onboarded")
        self.emergencyContactName = defaults.string(forKey: "\(p)emergency_name") ?? ""
        self.emergencyContactPhone = defaults.string(forKey: "\(p)emergency_phone") ?? ""
        self.safetyOverlayEnabled = defaults.object(forKey: "\(p)safety_enabled") as? Bool ?? true
        self.dietaryRestrictions = defaults.string(forKey: "\(p)dietary") ?? ""
        let voice = AIVoice(rawValue: defaults.string(forKey: "\(p)voice") ?? "") ?? .ash
        self.selectedVoice = voice
        self.realtimeService.voice = voice.rawValue
    }

    /// Resolves the active profile ID, migrating legacy flat keys on first run.
    private static func resolveProfileId() -> UUID {
        let defaults = UserDefaults.standard

        // Already have an active profile
        if let str = defaults.string(forKey: "raah_active_profile_id"),
           let id = UUID(uuidString: str) {
            return id
        }

        // First run or migration from pre-profile version
        let id = UUID()
        let prefix = "raah_\(id.uuidString.prefix(8))_"

        // Migrate existing flat keys → profile-prefixed keys
        let migrations: [(old: String, suffix: String)] = [
            ("raah_user_name", "user_name"),
            ("raah_accent_theme", "accent_theme"),
            ("raah_orb_style", "orb_style"),
            ("raah_onboarded", "onboarded"),
            ("raah_emergency_name", "emergency_name"),
            ("raah_emergency_phone", "emergency_phone"),
            ("raah_safety_enabled", "safety_enabled"),
            ("raah_dietary", "dietary"),
            ("raah_short_term_memory", "short_term_memory"),
            ("raah_long_term_preferences", "long_term_preferences"),
        ]

        for (old, suffix) in migrations {
            if let value = defaults.object(forKey: old) {
                defaults.set(value, forKey: "\(prefix)\(suffix)")
            }
        }

        // Store profile creation timestamp
        defaults.set(Date().timeIntervalSince1970, forKey: "\(prefix)created_at")
        defaults.set(id.uuidString, forKey: "raah_active_profile_id")
        return id
    }

    /// When the profile was created (nil for migrated profiles with no timestamp).
    var profileCreatedAt: Date? {
        let ts = UserDefaults.standard.double(forKey: profileKey("created_at"))
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
    
    // MARK: - Setup

    private var hasSetup = false

    func setupAfterOnboarding() {
        guard !hasSetup else { return }
        hasSetup = true

        locationManager.requestPermission()
        contextPipeline.bind(to: locationManager)
        analytics.log(.appOpen)
        analytics.pruneOldEvents()

        // If we already have a location (e.g. simulator), fetch context now
        if locationManager.hasRealLocation {
            refreshContext()
        }

        // Subscribe to first real GPS fix — triggers initial context fetch on real device
        locationManager.firstLocationPublisher
            .sink { [weak self] _ in
                self?.refreshContext()
            }
            .store(in: &cancellables)

        // Subscribe to frequent location updates for navigation step tracking
        locationManager.locationUpdatePublisher
            .throttle(for: .seconds(3), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.checkNavigationProgress()
            }
            .store(in: &cancellables)

        // Handle audio route changes (AirPods connect/disconnect mid-session)
        audioSession.onRouteChanged = { [weak self] in
            guard let self, self.realtimeService.isConnected else { return }
            self.realtimeService.handleAudioRouteChange()
        }

        contextPipeline.onContextRefreshed = { [weak self] in
            guard let self else { return }
            // Update system prompt if voice session is active
            pushSystemPrompt()
            checkForProactiveNarration()
            trackNearbyDwell()
            checkForFeedbackOpportunity()
            checkVoiceUsageWarning()
            checkNavigationProgress()
        }
        
        if healthKit.isAvailable {
            Task {
                _ = await healthKit.requestAuthorization()
                healthKit.startHeartRateMonitoring()
            }
        }
        
        Task {
            await longTermMemory.syncFromCloud()
        }
    }
    
    // MARK: - Voice Session
    
    func startVoiceSession() {
        // Check free tier limit first, before any side effects
        guard usageTracker.canUseVoice else {
            showingUpgradePrompt = true
            return
        }

        guard APIKeys.isOpenAIConfigured else {
            realtimeService.voiceState = .error("Add your OpenAI API key in Settings")
            return
        }

        // Check mic permission — must be async
        Task { @MainActor in
            let micGranted = await audioSession.requestMicPermission()
            guard micGranted else {
                realtimeService.voiceState = .error("Microphone access required. Enable in Settings.")
                return
            }

            do {
                try audioSession.configureForVoiceChat()
            } catch {
                realtimeService.voiceState = .error("Audio setup failed: \(error.localizedDescription)")
                return
            }

            let systemPrompt = buildCurrentSystemPrompt()

            locationManager.setHighAccuracy()

            // Clear stale state from previous session
            realtimeService.lastTranscript = ""
            realtimeService.lastResponse = ""
            hasWarnedUsageLimit = false

            // Start usage tracking
            usageTracker.startVoiceTracking()

            // Start exploration log
            explorationLogger.startSession(
                coordinate: locationManager.effectiveLocation.coordinate,
                locationName: contextPipeline.currentContext?.locationName
            )

            analytics.log(.sessionStart, properties: [
                "location": contextPipeline.currentContext?.locationName ?? "unknown"
            ])

            realtimeService.connect(systemPrompt: systemPrompt)

            realtimeService.onSessionCreated = { [weak self] in
                self?.realtimeService.startAudioCapture()
            }

            realtimeService.onTranscriptUpdate = { [weak self] transcript in
                guard let self else { return }
                // Save user's message for pairing with AI response
                self.pendingUserMessage = transcript
                // Track response time for Walk Me Home check-ins
                self.lastCheckInResponseTime = Date()
                if self.isWalkMeHomeActive { self.missedCheckIns = 0 }
                // Check voice usage limits on each interaction
                self.checkVoiceUsageWarning()
            }

            realtimeService.onResponseUpdate = { _ in }

            realtimeService.onResponseComplete = { [weak self] response in
                guard let self, !self.pendingUserMessage.isEmpty else { return }
                let interaction = Interaction(
                    userMessage: self.pendingUserMessage,
                    aiResponse: response,
                    location: LocationSnapshot(
                        latitude: self.locationManager.effectiveLocation.coordinate.latitude,
                        longitude: self.locationManager.effectiveLocation.coordinate.longitude,
                        timestamp: Date()
                    ),
                    contextPOIs: self.contextPipeline.nearbyPOIs.prefix(3).map(\.name)
                )
                self.shortTermMemory.addInteraction(interaction)
                self.pendingUserMessage = ""
            }

            realtimeService.onToolCall = { [weak self] name, callId, args in
                self?.handleToolCall(name: name, callId: callId, args: args)
            }
        }
    }
    
    func endVoiceSession() {
        // Stop active navigation
        if isNavigating { stopNavigation() }
        // Deactivate Walk Me Home if active
        if isWalkMeHomeActive { deactivateWalkMeHome() }
        // Clear any safety overlay that might have appeared during the session
        showingSafetyAlert = false

        realtimeService.stopAudioCapture()
        realtimeService.disconnect()
        audioSession.deactivate()
        locationManager.setLowAccuracy()
        let sessionElapsed = usageTracker.stopVoiceTracking()

        // Finalize exploration log
        explorationLogger.endSession(
            coordinate: locationManager.effectiveLocation.coordinate,
            interactionCount: shortTermMemory.interactions.count,
            weatherSummary: contextPipeline.currentContext?.currentWeatherSummary
        )

        analytics.log(.sessionEnd, properties: [
            "duration_seconds": "\(Int(sessionElapsed))",
            "interactions": "\(shortTermMemory.interactions.count)"
        ])
        analytics.flush()

        // Clear session-scoped tracking state
        mentionedPOIs.removeAll()
        dwellTracker.removeAll()
        visitedPOIs.removeAll()
        lastProactiveNarrationTime = nil
        lastFeedbackRequestTime = nil

        // Extract long-term preferences from this session
        Task {
            await longTermMemory.extractPreferences(from: shortTermMemory.interactions)
        }
    }
    
    // MARK: - Context Updates
    
    func refreshContext() {
        let location = locationManager.effectiveLocation
        Task {
            await contextPipeline.fetchContext(
                for: location,
                isInIndia: locationManager.isInIndia
            )
            
            pushSystemPrompt()
        }
    }

    // MARK: - Proactive Narration

    private func checkForProactiveNarration() {
        guard realtimeService.isConnected,
              realtimeService.voiceState == .idle || realtimeService.voiceState == .paused else { return }

        // Rate limit: max 1 per 2 minutes
        if let lastTime = lastProactiveNarrationTime,
           Date().timeIntervalSince(lastTime) < proactiveNarrationCooldown {
            return
        }

        let pois = contextPipeline.nearbyPOIs
        let preferences = longTermMemory.getPreferencesForPrompt()

        let notableTypes: Set<POIType> = [.heritage, .museum, .monument, .architectural, .religious, .naturalFeature]

        let candidates = pois.filter { poi in
            guard !mentionedPOIs.contains(poi.id) else { return false }
            guard let distance = poi.distance, distance <= proactiveNarrationRadius else { return false }
            return notableTypes.contains(poi.type)
        }

        guard !candidates.isEmpty else { return }

        // Score: preference_match × 0.6 + proximity × 0.4
        let scored = candidates.map { poi -> (POI, Double) in
            let prefScore = preferenceMatchScore(poi: poi, preferences: preferences)
            let proxScore = max(0, 1.0 - ((poi.distance ?? 80) / 80.0))
            return (poi, prefScore * 0.6 + proxScore * 0.4)
        }.sorted { $0.1 > $1.1 }

        guard let (bestPOI, _) = scored.first else { return }

        var narration = "Notice that nearby? That's \(bestPOI.name), a \(bestPOI.type.rawValue) site."
        if let summary = bestPOI.wikipediaSummary, !summary.isEmpty {
            narration += " \(summary)"
        }
        if let distance = bestPOI.distance {
            narration += " About \(Int(distance)) meters from you."
        }

        if realtimeService.voiceState == .paused {
            realtimeService.resumeAudioCapture()
        }
        realtimeService.sendTextMessage(
            "Proactively and naturally mention this to the user as if you just noticed it: \(narration)"
        )

        mentionedPOIs.insert(bestPOI.id)
        lastProactiveNarrationTime = Date()
        analytics.log(.proactiveNarration, properties: [
            "poi_name": bestPOI.name,
            "poi_type": bestPOI.type.rawValue
        ])

        // Log visited POI in exploration journal
        explorationLogger.addVisitedPOI(
            name: bestPOI.name,
            type: bestPOI.type.rawValue,
            coordinate: CLLocationCoordinate2D(latitude: bestPOI.latitude, longitude: bestPOI.longitude)
        )

        // Start tracking dwell time for feedback
        if dwellTracker[bestPOI.id] == nil {
            dwellTracker[bestPOI.id] = DwellEntry(
                name: bestPOI.name,
                type: bestPOI.type,
                coordinate: CLLocationCoordinate2D(latitude: bestPOI.latitude, longitude: bestPOI.longitude),
                firstSeen: Date()
            )
        }
    }

    private func preferenceMatchScore(poi: POI, preferences: [UserPreference]) -> Double {
        let typeToCategory: [POIType: PreferenceCategory] = [
            .heritage: .history,
            .architectural: .architecture,
            .museum: .art,
            .monument: .history,
            .religious: .culture,
            .naturalFeature: .nature,
            .commercial: .cuisine
        ]

        guard let matchCategory = typeToCategory[poi.type] else { return 0.3 }
        let matching = preferences.filter { $0.category == matchCategory }
        return matching.map(\.confidence).max() ?? 0.3
    }

    // MARK: - Post-Activity Feedback

    /// Track any notable POIs the user is near (within 150m) for dwell time
    private func trackNearbyDwell() {
        let notableTypes: Set<POIType> = [.heritage, .museum, .monument, .architectural, .religious, .naturalFeature]
        let userLocation = locationManager.effectiveLocation

        for poi in contextPipeline.nearbyPOIs where notableTypes.contains(poi.type) {
            guard dwellTracker[poi.id] == nil, !visitedPOIs.contains(poi.id) else { continue }
            let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            if userLocation.distance(from: poiLocation) <= dwellRadius {
                dwellTracker[poi.id] = DwellEntry(
                    name: poi.name,
                    type: poi.type,
                    coordinate: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
                    firstSeen: Date()
                )
            }
        }
    }

    private func checkForFeedbackOpportunity() {
        guard realtimeService.isConnected,
              realtimeService.voiceState == .idle || realtimeService.voiceState == .paused else { return }

        // Rate limit
        if let lastTime = lastFeedbackRequestTime,
           Date().timeIntervalSince(lastTime) < feedbackCooldown {
            return
        }

        let userLocation = locationManager.effectiveLocation

        for (poiID, entry) in dwellTracker {
            guard !entry.feedbackGiven, !visitedPOIs.contains(poiID) else { continue }

            let poiLocation = CLLocation(latitude: entry.coordinate.latitude, longitude: entry.coordinate.longitude)
            let distance = userLocation.distance(from: poiLocation)
            let dwellTime = Date().timeIntervalSince(entry.firstSeen)

            // User stayed near POI for 10+ min and has now moved away 300m+
            if dwellTime >= dwellThreshold && distance >= departureRadius {
                visitedPOIs.insert(poiID)
                dwellTracker.removeValue(forKey: poiID)

                // Resume audio if paused so user can hear the question
                if realtimeService.voiceState == .paused {
                    realtimeService.resumeAudioCapture()
                }

                realtimeService.sendTextMessage(
                    "The user just left \(entry.name) (a \(entry.type.rawValue) site) where they spent about \(Int(dwellTime / 60)) minutes. " +
                    "Casually ask how it was — e.g. 'So, how was \(entry.name)? Worth the visit?' " +
                    "Keep it natural and brief. Use their response to learn their preferences."
                )
                lastFeedbackRequestTime = Date()
                analytics.log(.feedbackGiven, properties: [
                    "poi_name": entry.name,
                    "dwell_minutes": "\(Int(dwellTime / 60))"
                ])
                return // Only one per cycle
            }
        }
    }

    // MARK: - Tool Call Handling
    
    private func handleToolCall(name: String, callId: String, args: [String: Any]) {
        switch name {
        case "check_safety_score":
            Task {
                let safety = SafetyScoreService()
                var resultText = "Safety check unavailable."
                if let lat = args["latitude"] as? Double,
                   let lon = args["longitude"] as? Double {
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let report = await safety.evaluateSafety(at: coord)
                    resultText = "Safety level: \(report.level.label). Alerts: \(report.alerts.joined(separator: ", "))."
                    if report.level < .safe && !realtimeService.isConnected {
                        showingSafetyAlert = true
                    }
                }
                realtimeService.sendToolResult(callId: callId, result: resultText)
            }

        case "find_tickets":
            Task {
                var resultText = "No tickets found."
                if let placeName = args["place_name"] as? String {
                    let affiliate = AffiliateService()
                    let offers = await affiliate.searchOffers(placeName: placeName)
                    if let best = offers.first {
                        resultText = "Found: \(best.title) for \(best.currency) \(best.price). Booking: \(best.bookingURL)"
                    }
                }
                realtimeService.sendToolResult(callId: callId, result: resultText)
            }

        case "get_directions":
            Task {
                let directions = DirectionsService()
                let destName = args["destination_name"] as? String ?? "destination"
                let destLat = args["destination_lat"] as? Double ?? 0
                let destLon = args["destination_lon"] as? Double ?? 0
                let origin = locationManager.effectiveLocation.coordinate
                let dest = CLLocationCoordinate2D(latitude: destLat, longitude: destLon)
                let locationName = contextPipeline.currentContext?.locationName ?? ""

                // Try structured directions — walking first, retry once if first attempt fails
                print("[Nav] Requesting directions to \(destName) from (\(origin.latitude), \(origin.longitude))")
                var structured = await directions.getDirectionsWithSteps(
                    from: origin, to: dest,
                    destinationName: destName, locationName: locationName
                )
                if structured == nil {
                    print("[Nav] First attempt failed, retrying...")
                    try? await Task.sleep(for: .seconds(1))
                    structured = await directions.getDirectionsWithSteps(
                        from: origin, to: dest,
                        destinationName: destName, locationName: locationName
                    )
                }

                if let structured {
                    print("[Nav] Got \(structured.steps.count) steps, starting navigation")
                    // Start live step-by-step navigation
                    self.startNavigation(
                        steps: structured.steps,
                        destination: destName,
                        destinationCoordinate: dest,
                        polyline: structured.polyline
                    )
                    print("[Nav] Navigation started: \(self.navigationSteps.count) steps after filtering, isNavigating=\(self.isNavigating)")
                    self.analytics.log(.directionRequested, properties: ["destination": destName, "mode": "navigation"])
                    let firstStep = self.navigationSteps.first
                    let firstInstruction = firstStep.map { "\($0.instruction) for about \(Int($0.distance)) meters" } ?? "Start walking"
                    realtimeService.sendToolResult(
                        callId: callId,
                        result: "Navigation to \(destName) (~\(structured.estimatedMinutes) min walk). " +
                        "Tell the user: \(firstInstruction). " +
                        "That's it — I'll tell you the next turn when they get there."
                    )
                } else {
                    print("[Nav] FAILED — no structured directions after 2 attempts")
                    // Truly failed — give distance only. MUST NOT let the AI make up directions.
                    let distKm = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                        .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) / 1000
                    self.analytics.log(.directionRequested, properties: ["destination": destName, "mode": "fallback"])
                    realtimeService.sendToolResult(
                        callId: callId,
                        result: "\(destName) is about \(String(format: "%.1f", distKm)) km away. " +
                        "Turn-by-turn directions are unavailable right now. " +
                        "Tell the user to open Apple Maps for navigation. " +
                        "DO NOT provide step-by-step directions yourself — you don't have the route data."
                    )
                }
            }

        case "search_local_knowledge":
            Task {
                let webSearch = WebSearchService()
                let query = args["query"] as? String ?? ""
                let locationName = args["location_name"] as? String
                    ?? contextPipeline.currentContext?.locationName
                    ?? "nearby"
                let result = await webSearch.searchLocal(query: query, locationName: locationName)
                self.analytics.log(.webSearchUsed, properties: ["query": query])
                realtimeService.sendToolResult(callId: callId, result: result)
            }

        case "activate_walk_me_home":
            activateWalkMeHome()
            realtimeService.sendToolResult(callId: callId, result: "Walk Me Home mode activated. Check-ins will happen every 3 minutes.")

        case "deactivate_walk_me_home":
            deactivateWalkMeHome()
            realtimeService.sendToolResult(callId: callId, result: "Walk Me Home mode deactivated. Glad you're safe!")

        case "share_live_location":
            sendSafetySMS(reason: "feels unsafe and needs a safety check")
            HapticEngine.warning()
            realtimeService.sendToolResult(callId: callId, result: "SOS SMS sent to emergency contact with current location and address.")

        default:
            realtimeService.sendToolResult(callId: callId, result: "Unknown tool.")
        }
    }

    // MARK: - Walk Me Home

    func activateWalkMeHome() {
        guard !isWalkMeHomeActive else { return }
        analytics.log(.walkMeHomeActivated)
        isWalkMeHomeActive = true
        missedCheckIns = 0
        lastCheckInResponseTime = Date()

        // Share location with emergency contact
        if !emergencyContactPhone.isEmpty {
            sendSafetySMS(reason: "has started Walk Me Home and is being tracked")
        }

        // Start voice session if not already active
        if !realtimeService.isConnected {
            startVoiceSession()
        }

        // Inject watchful companion prompt
        updateWalkMeHomePrompt()

        // Start check-in timer
        startCheckInTimer()

        HapticEngine.success()
    }

    func deactivateWalkMeHome() {
        guard isWalkMeHomeActive else { return }
        analytics.log(.walkMeHomeDeactivated)
        isWalkMeHomeActive = false
        walkMeHomeTimer?.cancel()
        walkMeHomeTimer = nil
        missedCheckIns = 0

        // Restore normal system prompt
        pushSystemPrompt()

        HapticEngine.success()
    }

    private func updateWalkMeHomePrompt() {
        guard realtimeService.isConnected else { return }
        var prompt = buildCurrentSystemPrompt(
        )
        prompt += """


        WALK ME HOME MODE ACTIVE:
        You are now in "watchful companion" mode. The user is walking somewhere and wants \
        company for safety. Be warmer, more conversational, and keep talking to maintain presence. \
        Check in naturally every few minutes — "Still doing okay?" / "How's the walk going?" \
        If the user says "I'm home" or "I made it" or similar, call the deactivate_walk_me_home tool. \
        Keep the tone calm and reassuring, not alarming. You are a friend walking them home.
        """
        realtimeService.updateSystemPrompt(prompt)
    }

    private func startCheckInTimer() {
        walkMeHomeTimer?.cancel()
        walkMeHomeTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.checkInInterval ?? 180))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.performCheckIn()
                }
            }
        }
    }

    private func performCheckIn() {
        guard isWalkMeHomeActive, realtimeService.isConnected else { return }

        // Check if user responded since last check-in
        let timeSinceResponse = Date().timeIntervalSince(lastCheckInResponseTime ?? Date.distantPast)
        if timeSinceResponse > checkInInterval {
            missedCheckIns += 1
        } else {
            missedCheckIns = 0
        }

        if missedCheckIns >= maxMissedCheckIns {
            // 2 consecutive missed check-ins → send emergency SMS
            sendEmergencySMS()
            return
        }

        // Resume audio if paused
        if realtimeService.voiceState == .paused {
            realtimeService.resumeAudioCapture()
        }

        // Ask AI to check in
        realtimeService.sendTextMessage(
            "Check in with the user naturally. They've been walking for a while. " +
            "Say something brief and reassuring like 'Still doing okay?' or 'How's the walk going?' " +
            "Keep it casual and warm."
        )
    }

    private func sendEmergencySMS() {
        guard !emergencyContactPhone.isEmpty else { return }
        sendSafetySMS(reason: "hasn't responded for 6+ minutes during Walk Me Home")
        HapticEngine.error()
        if realtimeService.isConnected {
            realtimeService.sendTextMessage(
                "ALERT: The user has not responded to 2 consecutive check-ins. An emergency SMS has been sent to \(emergencyContactName.isEmpty ? "their emergency contact" : emergencyContactName). " +
                "Tell the user: 'I haven't heard from you in a while, so I've sent an SOS to \(emergencyContactName.isEmpty ? "your emergency contact" : emergencyContactName). If you're okay, just say so.'"
            )
        }
    }

    // MARK: - Live Navigation

    /// Build the full system prompt including current navigation state.
    /// Single source of truth — every prompt push goes through here.
    private func buildCurrentSystemPrompt() -> String {
        let currentStep: String?
        let stepNumber: Int
        if isNavigating, currentStepIndex < navigationSteps.count {
            let step = navigationSteps[currentStepIndex]
            currentStep = "\(step.instruction) — about \(Int(step.distance)) meters"
            stepNumber = currentStepIndex + 1
        } else {
            currentStep = nil
            stepNumber = 0
        }

        return contextPipeline.buildSystemPrompt(
            userName: userName,
            preferences: longTermMemory.getPreferencesForPrompt(),
            shortTermHistory: shortTermMemory.getRecentContext(),
            dietaryRestrictions: dietaryRestrictions,
            isNavigating: isNavigating,
            navigationDestination: navigationDestination,
            navigationCurrentStep: currentStep,
            navigationStepNumber: stepNumber,
            navigationTotalSteps: navigationSteps.count
        )
    }

    /// Build and push the system prompt to the AI session.
    private func pushSystemPrompt() {
        guard realtimeService.isConnected else { return }
        realtimeService.updateSystemPrompt(buildCurrentSystemPrompt())
    }

    func startNavigation(steps: [DirectionsService.NavigationStep], destination: String, destinationCoordinate: CLLocationCoordinate2D, polyline: [CLLocationCoordinate2D] = []) {
        guard !steps.isEmpty else { return }
        let filtered = steps.filter { $0.distance > 5 }
        navigationSteps = filtered.isEmpty ? steps : filtered
        navigationDestination = destination
        navigationDestinationCoordinate = destinationCoordinate
        routePolyline = polyline
        currentStepIndex = 0
        isNavigating = true

        // Record where the user is RIGHT NOW — step 0 was just announced here.
        stepAnnouncedLocation = locationManager.effectiveLocation

        locationManager.setNavigationAccuracy()
        locationManager.resumeHeading()
        pushSystemPrompt()
    }

    func stopNavigation() {
        isNavigating = false
        navigationSteps = []
        currentStepIndex = 0
        navigationDestination = ""
        navigationDestinationCoordinate = nil
        routePolyline = []
        stepAnnouncedLocation = nil

        // Restore normal accuracy
        if realtimeService.isConnected {
            locationManager.setHighAccuracy()
        } else {
            locationManager.setLowAccuracy()
        }
    }

    /// Relative direction hint using compass heading.
    private func headingHint(to coordinate: CLLocationCoordinate2D) -> String {
        let userCoord = locationManager.effectiveLocation.coordinate
        let bearing = DirectionsService.bearing(from: userCoord, to: coordinate)
        guard let heading = locationManager.heading, heading.trueHeading >= 0 else { return "" }
        return " It's \(DirectionsService.relativeDirection(bearing: bearing, heading: heading.trueHeading))."
    }

    /// Called every 3 seconds. Completely silent unless:
    /// 1. User has WALKED at least half the current step's distance (min 25m) from where the step was announced
    /// 2. User is within 25m of the waypoint
    /// Both must be true. This prevents GPS jitter from ever causing a false advance.
    func checkNavigationProgress() {
        guard isNavigating, !navigationSteps.isEmpty, realtimeService.isConnected else { return }
        guard let announcedLoc = stepAnnouncedLocation else { return }

        let userLocation = locationManager.effectiveLocation
        let distanceWalked = userLocation.distance(from: announcedLoc)

        // --- All steps completed, check arrival at destination ---
        if currentStepIndex >= navigationSteps.count {
            // Must have walked at least 25m from last step announcement to avoid jitter trigger
            guard distanceWalked >= minWalkDistance else { return }
            guard let lastStep = navigationSteps.last else { return }
            let destCoord = lastStep.coordinate
            let destDist = userLocation.distance(from: CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude))
            if destDist < arrivalThreshold {
                if realtimeService.voiceState == .paused {
                    realtimeService.resumeAudioCapture()
                }
                realtimeService.requestResponse(
                    instructions: "The user arrived at \(navigationDestination). Say: 'You made it to \(navigationDestination)!' One sentence."
                )
                stopNavigation()
            }
            return
        }

        let currentStep = navigationSteps[currentStepIndex]

        // --- CONDITION 1: Must have actually walked ---
        // Require at least 50% of the step's distance OR 25m, whichever is greater.
        // GPS jitter is ±15m so standing still never reaches 25m.
        let requiredWalk = max(currentStep.distance * 0.5, minWalkDistance)
        guard distanceWalked >= requiredWalk else { return }

        // --- CONDITION 2: Must be near the waypoint ---
        let waypointLoc = CLLocation(latitude: currentStep.coordinate.latitude, longitude: currentStep.coordinate.longitude)
        let waypointDist = userLocation.distance(from: waypointLoc)
        guard waypointDist < waypointRadius else { return }

        // --- BOTH conditions met → advance step ---
        print("[Nav] Advancing: walked \(Int(distanceWalked))m (needed \(Int(requiredWalk))m), waypoint \(Int(waypointDist))m away (need <\(Int(waypointRadius))m)")
        currentStepIndex += 1
        stepAnnouncedLocation = userLocation // reset for next step
        HapticEngine.light()

        // Don't interrupt if user is speaking or AI is already talking
        guard realtimeService.voiceState == .idle || realtimeService.voiceState == .paused else { return }

        if realtimeService.voiceState == .paused {
            realtimeService.resumeAudioCapture()
        }

        if currentStepIndex < navigationSteps.count {
            let nextStep = navigationSteps[currentStepIndex]
            let hint = headingHint(to: nextStep.coordinate)
            pushSystemPrompt()
            realtimeService.requestResponse(
                instructions: "The user reached the turn. Say their next direction: \"\(nextStep.instruction), about \(Int(nextStep.distance)) meters.\(hint)\" One sentence. Nothing else."
            )
        } else {
            pushSystemPrompt()
            realtimeService.requestResponse(
                instructions: "\(navigationDestination) should be right here. Say: 'You're at \(navigationDestination)!' One sentence."
            )
        }
    }
}
