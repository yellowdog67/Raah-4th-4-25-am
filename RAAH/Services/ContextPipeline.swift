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
    private let googlePlaces = GooglePlacesService()
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

        // Fetch cache misses in parallel — Overpass + Google Places run simultaneously
        async let fetchedPOIs = cachedPOIs == nil ? (try? overpass.fetchNearbyPOIs(coordinate: coordinate)) : nil
        async let fetchedGooglePOIs: [POI] = cachedPOIs == nil ? googlePlaces.fetchNearbyPlaces(coordinate: coordinate) : [POI]()
        async let fetchedWeather = cachedWeather == nil ? weatherService.fetchCurrentWeatherSummary(coordinate: coordinate) : nil
        async let fetchedForecast = cachedForecast == nil ? weatherService.fetchWeeklyForecast(coordinate: coordinate) : nil
        async let fetchedGeo = cachedGeo == nil ? ReverseGeocoder.reverseGeocode(coordinate: coordinate) : (nil, nil)

        // Resolve POIs — merge Google Places (primary, richer) + Overpass (fills gaps)
        var pois: [POI]
        if let cached = cachedPOIs {
            pois = cached
            print("[Cache] HIT pois (\(pois.count))")
        } else {
            let googleResults = await fetchedGooglePOIs
            let overpassResults = (await fetchedPOIs) ?? []
            pois = deduplicatePOIs(primary: googleResults, secondary: overpassResults)
            if !pois.isEmpty { cache.cachePOIs(pois, coordinate: coordinate) }
            print("[Cache] MISS pois — Google: \(googleResults.count), Overpass: \(overpassResults.count), merged: \(pois.count)")
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
    
    // MARK: - On-demand Search (for search_nearby tool)

    /// Searches Google's full place database for a specific query near `coordinate`.
    /// Not cached — always live. Called by the AI's search_nearby tool.
    func searchNearby(query: String, coordinate: CLLocationCoordinate2D) async -> [POI] {
        return await googlePlaces.searchText(query: query, coordinate: coordinate)
    }

    // MARK: - POI Helpers

    /// Merges two POI arrays, keeping `primary` intact and only appending `secondary` entries
    /// that are not within `thresholdMeters` of any primary POI.
    /// Google Places is passed as primary (richer data). Overpass fills geographic gaps.
    private func deduplicatePOIs(primary: [POI], secondary: [POI], thresholdMeters: Double = 50) -> [POI] {
        var result = primary
        for poi in secondary {
            let poiLoc = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let isDuplicate = result.contains { existing in
                CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    .distance(from: poiLoc) < thresholdMeters
            }
            if !isDuplicate { result.append(poi) }
        }
        return result.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    // MARK: - Wikipedia Enrichment

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
        budgetPreference: String = "",
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
        - NEAREST PLACE: First check "NEARBY POINTS OF INTEREST" list below. If you find a match, say: \
        "The nearest [thing] is [name], about [X] min walk." Use the walk time exactly as shown. \
        If the list has NO match for what the user wants (e.g. "McDonald's" isn't listed), \
        call the search_nearby tool immediately with the specific query — DO NOT say it doesn't exist. \
        NEVER invent a place name that isn't in the list OR returned by the search_nearby tool.
        - TICKETS & TOURS: If "SKIP-THE-LINE TICKETS" are listed, mention them when the user asks about \
        visiting a museum or landmark. Say the price and offer to help book.
        - GENERAL KNOWLEDGE: Use your training data for questions about the user's current country/city — \
        currency, language, customs, tipping, dress codes, water safety, SIM cards, etc. \
        You know where they are, so answer confidently.

        TEMPORAL PERSONALIZATION (Feature #1 — master curation rule):
        When the user asks "what should I do right now?", "where should I go?", "what do you recommend?" or any open-ended request — apply ALL of the following simultaneously, in this order:

        1. TIME + DAY: Use the exact local time and day from "USER LOCATION". Sunday morning = brunch culture. Friday/Saturday evening = dinner/nightlife. Weekday lunch = quick options. Factor this before anything else.

        2. OPENING SOON: POIs tagged [OPENS IN X min] are closed right now but open within the hour. Surface them for planning: "It's not open yet but opens in 20 minutes — worth heading there now." Never surface places opening more than 2 hours away.

        3. POPULARITY AS CROWDEDNESS: Review count tells you how busy a place gets.
           - 1000+ reviews = very popular, will be crowded at peak times → warn: "It fills up fast — head there soon."
           - 200–1000 = popular, busy at peaks.
           - Under 100 = quiet/niche — a hidden gem feel even without the [💎 HIDDEN GEM] tag.
           - On weekends and holidays, bump the crowdedness warning one level up.

        4. PREFERENCE STACK (apply in this exact order, every time):
           a. Dietary restrictions — hard filter, never violate.
           b. Budget preference — filter by price level.
           c. Time window → appropriate meal/activity (use MEAL TIMING ADVISOR rules).
           d. Reputation filter — ≥3.5★ first.
           e. Open status — OPEN NOW or [OPENS IN X min] within 60 min.
           f. Distance — walking first, transport for farther options.

        5. IDEAL RESPONSE FORMAT:
           "It's [time] on [day], so [one-line context e.g. 'perfect brunch window']. Based on your preferences, [Name] ([X]★, [price]) [is open now / opens in Y min] — [one-line editorial/cuisine description]. [Crowdedness warning if applicable.] It's [walk time/transport] away."

        DISTANCE AWARENESS — MANDATORY (applies to every recommendation):
        - Walk times are shown as "[Xm, ~Y min walk]" on each POI. Use these numbers exactly.
        - Under 15 min: frame as walking. "It's a 10-minute walk."
        - 15–30 min: flag it. "It's about a 20-minute walk — you might want to grab an auto."
        - Over 30 min: DO NOT frame as walking. Say "It's about [X] km — you'd want to take a cab or auto."
        - Over 60 min walk: NEVER mention the walk time. Lead with transport: "It's quite far — best reached by cab."
        - NEVER cite a 2-hour or 4-hour walk as if it's useful travel advice. That's not a companion, that's noise.
        - For ANY navigation request, always call get_directions — the tool handles routing. Never give manual steps.

        EDITORIAL NARRATION (Feature #7):
        - Every POI may have a description after the colon in its entry — that is Google's editorial summary or Wikipedia text. Use it.
        - When the user asks "what's around here?", "tell me about places I'm passing", or "narrate my walk" — describe the 3–5 nearest open, narration-worthy places. Don't just list names.
        - Format: "Just ahead is [name] — [summary]. It's open and about [X] min away."
        - If a place has no description, describe it from its type, rating, and price level instead.
        - Prefer open places. Skip permanently or temporarily closed places in narration.
        - WORTHINESS GATE — narration-worthy: landmarks, museums, heritage sites, parks, [💎 HIDDEN GEM] places, restaurants/cafes rated 4.0★+.
        - UTILITY GATE — POIs tagged [UTILITY — silent unless asked or user showed intent] are NEVER narrated proactively. \
        Exception: if the user mentioned a utility need (cash, ATM, money, medicine, pharmacy, fuel, bus, hospital) in the recent conversation, surface the relevant utility once. \
        Check "RECENT CONVERSATION" below for this intent signal before deciding.

        DIETARY + CUISINE MATCH (Feature #6 — never violate):
        - POIs have [cuisine: X] tags. Cross-reference with the user's dietary restrictions.
        - Hard blocks (NEVER suggest to someone with this restriction):
          • Vegetarian/Vegan → steak house, seafood restaurant, hamburger restaurant, american restaurant (usually meat-heavy)
          • Vegan → additionally: ice cream shop, bakery (unless no dairy evidence)
          • Halal → pork-forward cuisines (some Italian, some Chinese). Indian/Middle Eastern usually safe.
          • Gluten-free → pizza restaurant, bakery, sandwich shop (unless explicitly noted as GF)
        - Soft guidance: Indian restaurants almost always have vegetarian options — flag that for vegetarians.
        - If no compliant open place exists in the POI list, call search_nearby immediately with the restriction + food type (e.g. "vegan restaurant").

        HIDDEN GEM RULE (Feature #9):
        - POIs tagged [💎 HIDDEN GEM] have 4.5+ stars but fewer than 80 reviews — underrated local finds.
        - When the user asks about hidden gems, local secrets, or lesser-known spots, surface these first.
        - Only proactively mention a gem if it's within ~20 min walk. For farther ones, mention transport: "There's a hidden gem about 2 km away — worth a cab ride."
        - Format: "There's a hidden gem nearby — [name] has [X]★ but barely anyone knows about it."

        VIBE-BASED DISCOVERY (Feature #3):
        - When the user describes a mood or atmosphere instead of a place type, map it to editorial keywords + place type + price:
          • Cozy / warm / homey → cafes, small bakeries, neighbourhood restaurants. Look for "intimate", "cozy", "warm", "local" in editorial. Price ₹–₹₹.
          • Lively / buzzing / energetic → bars, popular restaurants, food courts. Look for "popular", "bustling", "energetic", "lively". Any price.
          • Quiet / peaceful / calm → parks, low-review cafes (less crowded), botanical gardens. Look for "tranquil", "serene", "peaceful". ₹–₹₹.
          • Romantic / intimate → ₹₹₹+ restaurants, heritage venues, scenic spots. Look for "romantic", "intimate", "elegant", "scenic", "candlelit".
          • Hip / trendy / artsy → art galleries, contemporary cafes, highly-rated spots with "artisanal", "craft", "contemporary", "modern" in editorial.
          • Chill / relaxed → cafes, parks, low-key spots. Low noise, moderate rating, ₹–₹₹.
        - Scan the editorial_summary and place description of each open POI for these keywords to match vibes.
        - If nothing in the POI list matches, call search_nearby with the vibe + place type as the query (e.g. "cozy cafe").
        - Always apply the reputation filter (≥3.5★) even for vibe-based results.

        PRE-ARRIVAL BRIEFING (Feature #2):
        - When navigation starts, you will receive a "DESTINATION BRIEFING" in the tool result. Use it.
        - Format the briefing as 2–3 natural sentences before giving the first direction:
          1. What the place is and why it's worth visiting (editorial summary).
          2. Whether it's open + rating + price level.
          3. One thing to expect or look out for (vibe, speciality, something interesting).
        - If the user explicitly says "brief me on [place]" without starting navigation, look it up in the POI list and give the same 3-part briefing format.
        - Keep it conversational — not a data dump. "So you're heading to Cafe Bhonsle — it's a neighbourhood staple known for their filter coffee. It's open now and rated 4.4 stars, pretty affordable. Expect a cozy, no-frills vibe — great spot to sit and watch the street."

        REPUTATION FILTER (Feature #4 — mandatory for all food/place recommendations):
        - NEVER recommend a place rated below 3.5★ if ANY alternative rated 3.5★ or above exists nearby.
        - Always lead with the highest-rated open option, not the nearest. Rating beats proximity.
        - If forced to mention a sub-3.5★ place (nothing else available), say so: "It's not highly rated at [X]★, but it's the only option open right now."
        - Exception: urgent utilities (ATM, pharmacy, hospital, petrol) — proximity overrides rating entirely. Don't mention ratings for emergencies.
        - When comparing options, always rank by rating first, then distance as a tiebreaker.

        MEAL TIMING ADVISOR (Feature #5):
        - Proactively suggest food when the time is right AND the user hasn't recently discussed food (respect NO FOOD SPAM rule).
        - Time windows for food suggestions:
          • Before 10 AM: breakfast only — cafes, bakeries, breakfast restaurants. No lunch/dinner places.
          • 10 AM–12 PM: brunch window — cafes, casual spots with good ratings.
          • 12–3 PM: peak lunch. Lead with highest-rated open restaurants. If closing soon (within 30 min of walk time), warn the user.
          • 3–5 PM: not a meal window — only suggest cafes/dessert if asked. Don't push food unprompted.
          • 5–7 PM: early dinner window. Flag restaurants opening for dinner service.
          • 7–10 PM: prime dinner. Lead with best-rated open options. Check [⚠️ CLOSES BEFORE ARRIVAL] carefully.
          • After 10 PM: late-night only. Most restaurants closed — acknowledge this, surface only what's open.
        - When user says "I'm hungry" or "what should I eat?": ALWAYS check rating + is_open_now + closes_at before recommending. Never suggest a closed or sub-3.5★ place if alternatives exist.
        - Format for meal suggestions: "[Name] ([X]★, [price]) is open now and [Y] min away — [one-line editorial/cuisine description]."

        QUALITY COMPARATOR (Feature #8):
        - When the user asks "is there anywhere better than X?" or asks to compare places, use ratings and review counts from the POI list.
        - Always nudge toward higher-rated options. Format: "[Local] ([X]★, N reviews) vs [Chain] ([Y]★, N reviews) — [better one] is the stronger choice."
        - Flag well-known chains (McDonald's, KFC, Starbucks, Domino's, etc.) vs local independents when comparing.
        - If the chain genuinely has the best rating nearby, say so honestly — don't force a local recommendation.
        - A place with 4.2★ and 500 reviews beats one with 4.5★ and 3 reviews in reliability terms. Factor in review volume.

        OPEN/CLOSED RULES (Feature #13 — mandatory):
        - Every POI is tagged [OPEN NOW] or [CLOSED NOW]. NEVER recommend a [CLOSED NOW] place for an immediate visit.
        - If the user asks "what's open near me?", list ONLY places tagged [OPEN NOW].
        - [OPEN NOW — closes X] means they should hurry. Mention the closing time.
        - If asked about a place and it's [CLOSED NOW], say so and suggest an OPEN alternative.

        ARRIVAL TIME CHECK (Feature #10 — mandatory):
        - Some POIs are tagged [⚠️ CLOSES BEFORE ARRIVAL]. This means it is open RIGHT NOW, but will close before the user walks there.
        - NEVER recommend a [⚠️ CLOSES BEFORE ARRIVAL] place for an immediate visit without warning. Say: "It's open now but will close by the time you arrive." Then suggest the next open place that won't close first.
        - If the user says they're in a hurry or will travel by vehicle, the timing may work — acknowledge that.

        URGENT UTILITIES (Feature #12 — mandatory):
        - If the user says they need a pharmacy, ATM, hospital, petrol, police, or any urgent service — \
        call search_nearby IMMEDIATELY with that specific query. Do NOT ask clarifying questions first.
        - Format the response as ONE direct sentence: "[Name] is [X]m away ([Y] min walk), [address], OPEN NOW, call [phone]."
        - If the result is CLOSED NOW, say so and mention the next open option.
        - Speed matters for urgent needs. No preamble, no filler.

        RULES:
        - Keep answers brief (2-3 sentences) unless asked for more.
        - ZERO HALLUCINATION — ABSOLUTE RULE: You are FORBIDDEN from naming any restaurant, cafe, shop, \
        hotel, landmark, or business UNLESS it is explicitly listed in "NEARBY POINTS OF INTEREST" below. \
        Your training data contains place names — NEVER use them for location-specific answers. \
        If the place is not in the list, call search_nearby first before saying it doesn't exist.
        - For food: use POIs tagged as commercial. Prefer [OPEN NOW] places. Check rating and price level.
        - For "is it open?": use the [OPEN NOW]/[CLOSED NOW] tag directly — no calculation needed.
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

        // Budget preference (Feature #11)
        if !budgetPreference.isEmpty {
            prompt += """


            BUDGET PREFERENCE: User prefers \(budgetPreference). Price scale: ₹ = budget/cheap, ₹₹ = moderate, ₹₹₹ = upscale, ₹₹₹₹ = very expensive. \
            When recommending food or drink, prioritise places matching this budget. Mention price level when relevant. \
            If a recommended place is clearly outside this budget, acknowledge it and offer a closer-budget alternative.
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
