import Foundation
import CoreLocation
import Combine

/// Orchestrates the Context Fetcher pipeline.
/// When the user moves > 100m, fetches Overpass + Wikipedia data simultaneously,
/// evaluates safety, checks for affiliate opportunities, and compiles a SpatialContext
/// that gets injected into the OpenAI Realtime system prompt.
@Observable
final class ContextPipeline {
    
    var currentContext: SpatialContext?
    var isLoading: Bool = false
    var nearbyPOIs: [POI] = []
    var onContextRefreshed: (() -> Void)?
    
    private let overpass = OverpassService()
    private let wikipedia = WikipediaService()
    private let safety = SafetyScoreService()
    private let weatherService = WeatherService()
    private let affiliate = AffiliateService()
    private let mappls = MapplsService()
    private let validator = ContextValidator()
    private let cache = SpatialCache.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Bind to LocationManager's significant movement publisher
    func bind(to locationManager: LocationManager) {
        locationManager.significantMovementPublisher
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] location in
                Task { [weak self] in
                    await self?.fetchContext(
                        for: location,
                        isInIndia: locationManager.isInIndia
                    )
                }
            }
            .store(in: &cancellables)
    }
    
    /// Main pipeline: triggered on significant movement
    func fetchContext(for location: CLLocation, isInIndia: Bool) async {
        await MainActor.run { isLoading = true }

        let coordinate = location.coordinate

        // === Cache-first: check local cache, then fetch what's missing in parallel ===

        let cachedPOIs = cache.cachedPOIs(coordinate: coordinate)
        let cachedWeather = cache.cachedWeather(coordinate: coordinate)
        let cachedForecast = cache.cachedForecast(coordinate: coordinate)
        let cachedGeo = cache.cachedGeocode(coordinate: coordinate)

        // Always fetch: safety (changes often), timezone (derived live), India data
        async let safetyResult = safety.evaluateSafety(at: coordinate)
        async let timezoneResult = weatherService.fetchTimezone(coordinate: coordinate)
        async let indiaData: MapplsService.IndiaLocalData? = isInIndia
            ? mappls.fetchIndiaLocalData(coordinate: coordinate)
            : nil

        // Fetch cache misses in parallel
        async let fetchedPOIs = cachedPOIs == nil ? (try? overpass.fetchNearbyPOIs(coordinate: coordinate)) : nil
        async let fetchedWeather = cachedWeather == nil ? weatherService.fetchCurrentWeatherSummary(coordinate: coordinate) : nil
        async let fetchedForecast = cachedForecast == nil ? weatherService.fetchWeeklyForecast(coordinate: coordinate) : nil
        async let fetchedGeo = cachedGeo == nil ? ReverseGeocoder.reverseGeocode(coordinate: coordinate) : (nil, nil)

        // Resolve POIs
        var pois: [POI]
        if let cached = cachedPOIs {
            pois = cached
            print("[Cache] HIT pois (\(pois.count))")
        } else {
            pois = (await fetchedPOIs) ?? []
            if !pois.isEmpty { cache.cachePOIs(pois, coordinate: coordinate) }
            print("[Cache] MISS pois — fetched \(pois.count)")
        }

        let safetyReport = await safetyResult

        // Resolve weather
        let currentWeather: String
        if let cached = cachedWeather {
            currentWeather = cached
            print("[Cache] HIT weather")
        } else {
            let fetched = (await fetchedWeather) ?? "Weather unavailable."
            currentWeather = fetched
            if fetched != "Weather unavailable." { cache.cacheWeather(fetched, coordinate: coordinate) }
            print("[Cache] MISS weather")
        }

        // Resolve forecast
        let forecast: String
        if let cached = cachedForecast {
            forecast = cached
            print("[Cache] HIT forecast")
        } else {
            let fetched = (await fetchedForecast) ?? ""
            forecast = fetched
            if !fetched.isEmpty { cache.cacheForecast(fetched, coordinate: coordinate) }
            print("[Cache] MISS forecast")
        }

        let (tz, localTime) = await timezoneResult

        // Resolve geocode
        let locationName: String?
        let countryCode: String?
        if let cached = cachedGeo {
            locationName = cached.locationName
            countryCode = cached.countryCode
            print("[Cache] HIT geocode")
        } else {
            let (geoName, geoCode) = await fetchedGeo
            locationName = geoName
            countryCode = geoCode
            if geoName != nil {
                cache.cacheGeocode(SpatialCache.GeocodeCacheEntry(locationName: geoName, countryCode: geoCode), coordinate: coordinate)
            }
            print("[Cache] MISS geocode")
        }

        let indiaResult = await indiaData

        print("[Cache] Hit rate: \(Int(cache.hitRate * 100))% (\(cache.hits) hits, \(cache.misses) misses)")
        
        // Demo fallback: if we're near Goa and have very few POIs, add demo places so "nearest burger/food" always works
        if pois.count < 4 && isNearGoa(coordinate) {
            pois = demoGoaPOIs(userCoordinate: coordinate) + pois
            pois.sort { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
        }
        
        // Enrich top 5 POIs with Wikipedia summaries (parallel), keep the rest
        let topPOIs = Array(pois.prefix(5))
        let remainingPOIs = pois.count > 5 ? Array(pois.suffix(from: 5)) : []
        let enrichedTop = await enrichWithWikipedia(pois: topPOIs)
        pois = enrichedTop + remainingPOIs

        await MainActor.run { nearbyPOIs = pois }
        
        // Check affiliate offers for museums/landmarks
        var offers: [AffiliateOffer] = []
        if APIKeys.isGetYourGuideConfigured {
            let museums = pois.filter { $0.type == .museum || $0.type == .monument }
            for museum in museums.prefix(2) {
                let museumOffers = await affiliate.searchOffers(
                    placeName: museum.name,
                    coordinate: museum.coordinate
                )
                offers.append(contentsOf: museumOffers)
            }
        }
        
        // Emergency numbers from country code
        let emergencyNumbers = countryCode.flatMap { EmergencyNumbers.lookup(countryCode: $0) }

        // India-specific data
        let digiPin = indiaResult?.digiPin
        let roadAlerts = indiaResult?.nearbyAlerts.map { "\($0.type.rawValue): \($0.description) (\(Int($0.distance))m)" }

        var context = SpatialContext(
            pois: pois,
            safetyLevel: safetyReport.level,
            safetyAlerts: safetyReport.alerts,
            nearbyOffers: offers,
            weatherWarning: safetyReport.weatherWarnings.first,
            currentWeatherSummary: currentWeather,
            weeklyForecast: forecast.isEmpty ? nil : forecast,
            isInIndia: isInIndia,
            locationName: locationName,
            countryCode: countryCode,
            timezone: tz,
            localTime: localTime,
            emergencyNumbers: emergencyNumbers,
            indiaDigiPin: digiPin,
            indiaRoadAlerts: roadAlerts
        )

        // Validate completeness and auto-repair any gaps
        let (repairedContext, report) = await validator.validateAndRepair(
            context: context,
            coordinate: coordinate
        )
        context = repairedContext

        if !report.gaps.isEmpty {
            let unrepaired = report.gaps.filter { !report.repaired.contains($0) }
            if !unrepaired.isEmpty {
                print("[ContextPipeline] Unresolved context gaps: \(unrepaired.joined(separator: ", "))")
            }
        }

        await MainActor.run {
            currentContext = context
            isLoading = false
            onContextRefreshed?()
        }
    }
    
    // MARK: - Wikipedia Enrichment
    
    private func isNearGoa(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        return lat >= 15.2 && lat <= 15.6 && lon >= 73.7 && lon <= 74.0
    }
    
    /// Demo POIs for Goa so "nearest burger/food" always has an answer when OSM returns little.
    private func demoGoaPOIs(userCoordinate: CLLocationCoordinate2D) -> [POI] {
        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let places: [(name: String, lat: Double, lon: Double, type: POIType)] = [
            ("Cafe Bodega", 15.3920, 73.8795, .commercial),
            ("Burger Factory", 15.3950, 73.8810, .commercial),
            ("Martin's Corner", 15.3880, 73.8780, .commercial),
            ("Fisherman's Wharf", 15.3900, 73.8820, .commercial),
            ("Cafe Chocolatti", 15.3940, 73.8770, .commercial),
            ("Pizza Express", 15.3890, 73.8805, .commercial)
        ]
        return places.enumerated().map { i, p in
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            let dist = user.distance(from: loc)
            return POI(
                id: "demo-\(i)",
                name: p.name,
                type: p.type,
                latitude: p.lat,
                longitude: p.lon,
                tags: ["amenity": "restaurant"],
                wikidataID: nil,
                wikipediaSummary: nil,
                distance: dist
            )
        }
    }
    
    private func enrichWithWikipedia(pois: [POI]) async -> [POI] {
        await withTaskGroup(of: POI.self) { group in
            for poi in pois {
                group.addTask { [wikipedia, cache] in
                    var enriched = poi
                    // Check wiki cache first
                    if let cached = cache.cachedWikipediaSummary(poiID: poi.id) {
                        enriched.wikipediaSummary = cached
                    } else {
                        let summary = await wikipedia.fetchSummary(for: poi)
                        enriched.wikipediaSummary = summary
                        if let summary { cache.cacheWikipediaSummary(summary, poiID: poi.id) }
                    }
                    return enriched
                }
            }

            var results: [POI] = []
            for await poi in group {
                results.append(poi)
            }
            return results.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
        }
    }
    
    // MARK: - System Prompt Generation
    
    func buildSystemPrompt(
        userName: String,
        preferences: [UserPreference],
        shortTermHistory: [Interaction],
        dietaryRestrictions: String = "",
        isNavigating: Bool = false,
        navigationDestination: String = "",
        navigationCurrentStep: String? = nil,
        navigationStepNumber: Int = 0,
        navigationTotalSteps: Int = 0
    ) -> String {
        var prompt = """
        You are RAAH — an AI companion for the physical world. You speak like an informed, \
        curious friend. Keep responses SHORT (2–3 sentences max) unless the user asks for more.
        
        The user's name is \(userName). Address them by name occasionally.
        
        WHAT YOU CAN ALWAYS DO:
        - LOCATION: You know the user's city, country, and timezone from "USER LOCATION" below. \
        Use this for questions about currency, language, tipping, customs, water safety, power adapters, etc. \
        You can always say what city and country the user is in.
        - TIME: Use the local time provided. Factor it into "is it open now?", "is it too late to visit?", etc.
        - WEATHER: Use "CURRENT WEATHER" for today. Use "7-DAY FORECAST" for upcoming days \
        (e.g. "when should I watch sunset", "will it rain tomorrow", "best day for outdoor plans"). \
        Pick the clearest day with latest sunset for sunset questions. Never refuse weather questions.
        - EMERGENCY: If the user asks about emergency numbers, police, ambulance — use "EMERGENCY NUMBERS" below.
        - NEAREST PLACE: Use "NEARBY POINTS OF INTEREST" list. Pick the closest match. \
        Walk time is shown next to distance. Say: "The nearest [thing] is [name], about [X] min walk." \
        If it has opening hours, mention them. If nothing matches, say: "I don't see that nearby — check the Explore map."
        - TICKETS & TOURS: If "SKIP-THE-LINE TICKETS" are listed, mention them when the user asks about \
        visiting a museum or landmark. Say the price and offer to help book.
        - GENERAL KNOWLEDGE: Use your training data for questions about the user's current country/city — \
        currency, language, customs, tipping, dress codes, water safety, SIM cards, etc. \
        You know where they are, so answer confidently.

        RULES:
        - Keep answers brief (2-3 sentences) unless asked for more.
        - Do NOT make up place names or distances — only use the POI list.
        - For food: use POIs tagged as commercial. Check cuisine tags and opening hours if available.
        - For "is it open?": compare opening hours with the local time.
        - DIRECTIONS: When the user asks for directions, navigation, or "how to get to" ANY place — \
        you MUST call the get_directions tool. NEVER give step-by-step directions from your own knowledge. \
        NEVER list walking/driving steps yourself. Only the tool can start navigation.

        WEATHER-AWARE RULES:
        - If raining or storming: suggest indoor activities, warn against viewpoints and open areas.
        - If visibility is low or overcast: do NOT recommend sunset/sunrise viewpoints.
        - If temperature > 38°C: suggest shaded venues, AC restaurants, water stops.
        - If sunset is within 60 minutes and user is near a viewpoint: proactively mention it.
        - Always factor weather into food suggestions (hot soup on cold days, cold drinks on hot days).

        TEMPORAL AWARENESS — MANDATORY (NEVER VIOLATE):
        - CLOSED PLACES: NEVER recommend a place marked [CLOSED NOW] or [CLOSED — opens at X]. \
        Say it's closed and when it opens, then suggest an OPEN alternative nearby.
        - CLOSES SOON: If a place is marked [OPEN — closes at X], warn the user so they can hurry or pick elsewhere.
        - FUTURE OPENINGS: If a place opens more than 2 hours from now, do NOT suggest it unless the user asks.
        - NO FOOD SPAM: Check "RECENT ACTIVITY" below. If the user discussed food/dining less than 90 minutes ago, \
        do NOT proactively suggest restaurants or food. Only if they explicitly ask.
        - NO REPETITION: Don't suggest the same activity category the user just did. \
        Museum 30 min ago → suggest a cafe or walk, not another museum. Just ate → suggest sightseeing, not more food.
        - TIME-OF-DAY RULES (based on local time from "USER LOCATION"):
          Before 7 AM: only suggest early-open places (cafes, bakeries, walks). No museums or shops.
          7–11 AM: breakfast spots, morning walks, temples, early sightseeing.
          11 AM–2 PM: lunch spots, indoor activities if hot, sightseeing.
          2–5 PM: afternoon cafes, museums, shopping, lighter activities.
          5–7 PM: sunset viewpoints (if clear weather), evening walks, pre-dinner drinks.
          After 7 PM: dinner, evening markets, nightlife. No outdoor sightseeing.
          After 10 PM: only late-night options. Be safety-conscious. Suggest heading back.
        - Every POI has an open/closed status tag. ALWAYS check it before recommending ANY place.
        """
        
        // Safety tool rule — always injected so AI knows to act
        prompt += """


        SAFETY RULE (mandatory):
        If the user says ANYTHING suggesting they feel unsafe, scared, threatened, or anxious — \
        phrases like "I feel unsafe", "I'm scared", "something doesn't feel right", "I need help", \
        "I'm being followed", "this feels dangerous", "I don't feel safe" — \
        IMMEDIATELY call the share_live_location tool. Do NOT ask for confirmation. Do NOT hesitate. \
        Their safety is the absolute priority.
        """

        // Safety overlay tone
        if let context = currentContext, context.safetyLevel < .safe {
            prompt += """


            SAFETY MODE ACTIVE:
            The user is in a \(context.safetyLevel.label) area. Switch to "watchful companion" tone. \
            Be more attentive. Mention safety tips naturally, not alarmingly.
            """
        }
        
        // Dietary restrictions
        if !dietaryRestrictions.isEmpty {
            prompt += """


            DIETARY RESTRICTIONS: \(dietaryRestrictions). NEVER suggest food or restaurants that violate these restrictions.
            """
        }

        // User preferences
        if !preferences.isEmpty {
            let prefStrings = preferences.prefix(10).map { "- \($0.category.rawValue): \($0.value)" }
            prompt += """
            
            
            USER PREFERENCES (use these to filter and prioritize what you mention):
            \(prefStrings.joined(separator: "\n"))
            """
        }
        
        // Recent conversation context — with timestamps so AI knows recency
        let now = Date()
        if !shortTermHistory.isEmpty {
            let recent = shortTermHistory.suffix(8).map { interaction -> String in
                let minutesAgo = max(1, Int(now.timeIntervalSince(interaction.timestamp) / 60))
                let timeLabel: String
                if minutesAgo < 2 { timeLabel = "just now" }
                else if minutesAgo < 60 { timeLabel = "\(minutesAgo) min ago" }
                else { timeLabel = "\(minutesAgo / 60)h ago" }
                return "[\(timeLabel)] User: \(interaction.userMessage)\nRAAH: \(interaction.aiResponse)"
            }
            prompt += """


            RECENT CONVERSATION (timestamps show when each happened — use for temporal awareness):
            \(recent.joined(separator: "\n---\n"))
            """
        }

        // Activity recency — detect what the user recently engaged with
        let activityRecency = Self.detectRecentActivities(from: shortTermHistory, now: now)
        if !activityRecency.isEmpty {
            prompt += "\n\n" + activityRecency
        }

        // Spatial context — with live time for opening hours checks
        if let context = currentContext {
            let tz: TimeZone
            if let tzName = context.timezone, let resolved = TimeZone(identifier: tzName) {
                tz = resolved
            } else {
                tz = .current
            }
            prompt += "\n\n" + context.systemPromptFragment(now: now, timeZone: tz)
        }

        // Navigation mode
        if isNavigating && !navigationDestination.isEmpty {
            prompt += """


            STEP-BY-STEP NAVIGATION MODE ACTIVE — destination: \(navigationDestination).
            You are guiding the user turn by turn like Google Maps. RULES:
            - Say ONLY the CURRENT DIRECTION below. Nothing else. No future steps. No route summary.
            - One sentence, conversational, like a friend. Example: "Turn left here onto MG Road, then walk about 200 meters."
            - If the user asks "how much further?" — say remaining steps and rough distance, NOT the full route.
            - Do NOT repeat a direction you already gave unless the user asks.
            """

            if let step = navigationCurrentStep {
                prompt += """

                CURRENT DIRECTION (step \(navigationStepNumber) of \(navigationTotalSteps)): \(step)
                ^ Tell the user THIS and only this.
                """
            }
        }

        return prompt
    }

    // MARK: - Activity Recency Detection

    /// Scans recent interactions to detect what categories of activity the user recently engaged with.
    /// Used by temporal awareness rules to prevent repetitive suggestions.
    private static func detectRecentActivities(from history: [Interaction], now: Date) -> String {
        var food: Int?
        var sightseeing: Int?
        var shopping: Int?

        for interaction in history.reversed() {
            let mins = Int(now.timeIntervalSince(interaction.timestamp) / 60)
            if mins > 180 { break } // Only care about last 3 hours

            let text = (interaction.userMessage + " " + interaction.aiResponse).lowercased()

            if food == nil {
                let foodWords = ["restaurant", "cafe", "food", "eat", "dinner", "lunch", "breakfast",
                                 "burger", "pizza", "coffee", "snack", "meal", "cuisine", "hungry",
                                 "thali", "biryani", "dosa", "naan", "curry", "drinks", "bar", "pub"]
                if foodWords.contains(where: { text.contains($0) }) { food = mins }
            }
            if sightseeing == nil {
                let sightWords = ["museum", "gallery", "monument", "heritage", "temple", "church",
                                  "fort", "palace", "ruins", "statue", "viewpoint", "basilica", "mosque"]
                if sightWords.contains(where: { text.contains($0) }) { sightseeing = mins }
            }
            if shopping == nil {
                let shopWords = ["shop", "store", "market", "buy", "purchase", "mall", "souvenir"]
                if shopWords.contains(where: { text.contains($0) }) { shopping = mins }
            }

            // Early exit if all found
            if food != nil && sightseeing != nil && shopping != nil { break }
        }

        var lines: [String] = []
        if let t = food { lines.append("- Food/dining: discussed \(t) min ago\(t < 90 ? " — DO NOT proactively suggest food" : "")") }
        if let t = sightseeing { lines.append("- Sightseeing/culture: discussed \(t) min ago\(t < 45 ? " — suggest something different" : "")") }
        if let t = shopping { lines.append("- Shopping: discussed \(t) min ago\(t < 45 ? " — suggest something different" : "")") }

        return lines.isEmpty ? "" : "RECENT ACTIVITY (use this to avoid repetitive suggestions):\n" + lines.joined(separator: "\n")
    }
}
