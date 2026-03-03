# RAAH MVP Roadmap

## Gap Analysis: Documents vs What's Built

### What's Already Done (Solid Foundation)

| Feature | Doc Reference | Status |
|---------|--------------|--------|
| OpenAI Realtime API (full-duplex voice) | Doc 1 §V, Doc 2 §I | ✅ Built — WebSocket, audio capture/playback, barge-in |
| Overpass API (hyperlocal POIs) | Doc 1 §V, Doc 2 §I | ✅ Built — heritage, architecture, museums, restaurants, 800m radius |
| Wikipedia/Wikivoyage enrichment | Doc 2 §I | ✅ Built — Wikidata ID glue, top 5 POIs enriched |
| Context Pipeline (spatial awareness) | Doc 1 §V "Intelligence Layer" | ✅ Built — parallel fetch on 100m movement, system prompt injection |
| Snap & Ask (GPT-4o Vision) | Doc 1 §III "Multimodal Vision" | ⚠️ Partial — Vision API works, camera uses placeholder |
| Iterated Learning (Long-term memory) | Doc 1 §V, Doc 2 §I | ✅ Built — GPT extracts preferences, Supabase + pgvector, local fallback |
| Short-term memory | Doc 1 §V | ✅ Built — Last 10 interactions |
| Safety system | Doc 1 §II "Safety Barrier" | ✅ Built — Heuristic + GeoSure API, safety overlay sheet |
| Emergency contact / location sharing | Doc 1 §II | ✅ Built — SMS with Apple Maps link |
| India-specific (Mappls) | Doc 2 §III | ✅ Built — DigiPin, road alerts, geofenced activation |
| GetYourGuide affiliate | Doc 3 §II "B2B Affiliate" | ✅ Built — Purchase intent detection, ticket search |
| Weather (Open-Meteo) | Doc 1 §V | ✅ Built — Free, no key, injected into system prompt |
| HealthKit (heart rate → orb) | Doc 1 §I "physiological data" | ✅ Built — Apple Watch HR modulates orb breathing |
| Google Places (New) API | Doc 2 §I | ✅ Built — Ready, needs API key |
| Onboarding (name, interests, theme) | Doc 1 §VIII Phase 1 | ✅ Built — 5-page flow |
| Custom design system | N/A | ✅ Built — Glassmorphism, 5 themes, 3 orb styles |

**Bottom line: Core architecture is solid. Phase 1 and most of Phase 2 from Doc 1 are done. What's left is making it real, making it smart, and making it presentable.**

---

## The MVP Roadmap

### Sprint 1: "Make It Real"
**Goal: The core experience works end-to-end. Nothing is faked. The demo doesn't break.**

---

#### 1.1 — Onboarding requests real permissions
**Why:** Nothing works without this. No mic = no voice. No location = no POIs. First-run is completely broken right now.

**What:**
- Add individual "Allow" buttons on the permissions page (page 5) that trigger real system permission dialogs
- Location: `CLLocationManager.requestWhenInUseAuthorization()`
- Microphone: `AVAudioApplication.requestRecordPermission()`
- Camera: `AVCaptureDevice.requestAccess(for: .video)`
- HealthKit: `healthKit.requestAuthorization()` (already exists, just needs to be called here)
- Show real-time granted/denied state on each row (checkmark vs "Denied — open Settings")

**Files:** `Views/OnboardingView.swift`, `Services/LocationManager.swift`, `Services/AudioSessionManager.swift`
**Effort:** ~1 hour

---

#### 1.2 — Wire up real camera in Snap & Ask
**Why:** "Look at this" → AI identifies it is a magic demo moment. A gray rectangle kills the entire Snap & Ask pitch.

**What:**
- Replace the placeholder `captureImage()` with the already-built `CameraViewRepresentable`
- Show live camera preview as the default state (not the text instructions)
- Tap capture → freeze frame → send to GPT-4o Vision → show result with option to speak it
- Add camera permission check (request if not granted)

**Files:** `Views/SnapAndAskView.swift`
**Effort:** ~1-2 hours

---

#### 1.3 — Voice session error recovery
**Why:** Walking around = cell tower handoffs, Wi-Fi→cellular switches, brief dead zones. One WebSocket drop during a demo and it's over.

**What:**
- Detect WebSocket disconnection via the `URLSessionWebSocketDelegate` close handler
- Auto-reconnect with exponential backoff: 1s → 2s → 4s, max 3 attempts
- Add `VoiceState.reconnecting` case — orb pulses amber, label shows "Reconnecting..."
- If all retries fail, orb shows "Tap to retry"
- Preserve `currentSystemPrompt` across reconnects so context isn't lost

**Files:** `Services/OpenAIRealtimeService.swift`, `Models/Models.swift` (VoiceState enum), `Views/HomeView.swift`
**Effort:** ~2 hours

---

#### 1.4 — Proactive narration system
**Why:** This IS the product. Doc 1's entire thesis is the AI "proactively weaving a narrative based on movement." Without this, RAAH is just another voice chatbot. With it, RAAH is a companion that points things out as you walk.

**What:**
- When `ContextPipeline` refreshes after movement, compare new POIs against a `mentionedPOIs` set
- If a new POI is within 80m, is notable (heritage, museum, monument, architectural), and hasn't been mentioned → trigger proactive narration
- Rank candidates by: `(preference_match_score × 0.6) + (proximity_score × 0.4)` — so a heritage building the user cares about beats a random restaurant that's closer
- Only fire when `voiceState == .idle` (never interrupt user or AI mid-sentence)
- Inject via `conversation.item.create` with a message like: "Notice that building ahead? That's [name]. [wikipedia_summary]"
- Add POI to `mentionedPOIs` set to prevent repeats
- Rate limit: max 1 proactive narration per 2 minutes (don't be annoying)

**Files:** `ViewModels/AppState.swift`, `Services/ContextPipeline.swift`, `Services/OpenAIRealtimeService.swift`, `Memory/ShortTermMemory.swift`
**Effort:** ~3-4 hours

---

#### 1.5 — Weather-aware suggestions + sunrise/sunset
**Why:** Essentially free to implement. Prevents embarrassing suggestions like "go watch the sunset" when it's pouring rain. Enables golden hour alerts.

**What:**
- Add `sunrise`, `sunset` to the Open-Meteo fetch in `WeatherService` (the API supports `daily=sunrise,sunset`)
- Include sunrise/sunset times in the weather summary string injected into the system prompt
- Add these rules to `ContextPipeline.buildSystemPrompt()`:
  ```
  WEATHER-AWARE RULES:
  - If raining/storming: suggest indoor activities, warn against viewpoints and open areas.
  - If visibility is low or overcast: don't recommend sunset/sunrise viewpoints.
  - If temperature > 38°C: suggest shaded venues, AC restaurants, water stops.
  - If sunset is within 60 minutes and user is near a viewpoint: proactively mention it.
  - Always factor weather into food suggestions (hot soup on cold days, cold drinks on hot days).
  ```

**Files:** `Services/WeatherService.swift`, `Services/ContextPipeline.swift`
**Effort:** ~30 minutes

---

#### 1.6 — Dietary preferences in onboarding
**Why:** 20 minutes of work that prevents the AI from recommending a steak house to a vegetarian. Table stakes for a food-aware travel app.

**What:**
- Add a dietary section to the interests page (page 3) in onboarding: Vegetarian, Vegan, Halal, Kosher, Gluten-free, No restrictions
- Store as a `UserPreference` with category `.cuisine` and high confidence (0.9)
- Add to system prompt: "DIETARY RESTRICTIONS: [user's restrictions]. NEVER suggest food that violates these."

**Files:** `Views/OnboardingView.swift`, `Models/Models.swift` (add dietary options), `Services/ContextPipeline.swift`
**Effort:** ~30 minutes

---

### Sprint 2: "Make It Smart"
**Goal: The app is fast, cheap to run, knows things nobody else knows, and remembers everything.**

---

#### 2.1 — Tiered caching layer
**Why:** Currently every context fetch hits Overpass + Wikipedia fresh. Slow, expensive, and stupid — 80% of POI data in a city is static. Walking back through an area you visited 10 minutes ago shouldn't re-fetch everything.

**What:**
- New `SpatialCache` service using local JSON files in the app's caches directory
- Cache Overpass POI results by geohash (precision 6 ≈ 1.2km grid). TTL: 7 days.
- Cache Wikipedia summaries by POI ID. TTL: 30 days.
- Cache weather by coordinate (rounded to 2 decimal places). TTL: 1 hour.
- `ContextPipeline` checks cache first, only hits network on cache miss or expiry
- Log cache hit/miss ratio for debugging

**Files:** New `Services/SpatialCache.swift`, modify `Services/ContextPipeline.swift`
**Effort:** ~2-3 hours

---

#### 2.2 — Web search tool call for niche finds
**Why:** "Where's the best samosa near me?" — Overpass and Wikipedia can't answer this. The knowledge lives on Reddit, TripAdvisor, food blogs. This is what makes RAAH feel like a real local friend, not a Wikipedia reader.

**What:**
- Integrate Brave Search API (free tier: 2,000 queries/month, no credit card needed) as a new tool call
- Add `search_local_knowledge` tool to `OpenAIRealtimeService.toolDefinitions`:
  ```
  "Search the web for local recommendations, hidden gems, or niche finds.
   Use when user asks for 'best X', 'hidden gem', 'local favorite', etc."
  Parameters: query (string), location_name (string)
  ```
- Handler in `AppState.handleToolCall`: constructs search query like `"best samosa [location_name] site:reddit.com OR site:tripadvisor.com"`, calls Brave Search, returns top 3 results as text
- New `Services/WebSearchService.swift` wrapping the Brave Search API
- AI summarizes results conversationally: "Locals on Reddit swear by Sharma's Samosa Stall on MG Road, about 300 meters from here."

**Files:** New `Services/WebSearchService.swift`, modify `Services/OpenAIRealtimeService.swift`, `ViewModels/AppState.swift`, `Config/APIKeys.swift`
**Effort:** ~2-3 hours

---

#### 2.3 — Transit directions (hybrid: MapKit → web search → Apple Maps)
**Why:** "How do I get to India Gate from here?" should give actual metro/bus instructions, not a vague "take the metro." But no single API works everywhere — MapKit transit has great data in major cities, returns nothing in smaller ones.

**What:**
- Add `get_directions` tool to the Realtime service:
  ```
  "Get directions from user's current location to a destination.
   Returns step-by-step transit/walking instructions."
  Parameters: destination_name (string), destination_lat (number), destination_lon (number)
  ```
- **Three-tier handler logic:**
  1. **Try MKDirections .transit first** — free, instant, structured. If it returns a route, parse into human-readable steps: "Walk 5 min to Rajiv Chowk → Take Blue Line (3 stops) → Walk 8 min south"
  2. **If MKDirections returns no transit route** → fall back to web search (task 2.2's `WebSearchService`) with query `"transit directions from [current area] to [destination] metro bus"`. Picks up local knowledge from transit sites, Reddit, forums — often includes platform numbers, exit gates, etc.
  3. **Always offer** `open_in_maps` — sends an `MKMapItem.openInMaps()` call so user gets real turn-by-turn in Apple Maps as the final handoff.
- Fallback to walking directions via MKDirections `.walking` if both transit and web search fail

**Files:** New `Services/DirectionsService.swift`, modify `Services/OpenAIRealtimeService.swift`, `ViewModels/AppState.swift`
**Effort:** ~2 hours

---

#### 2.4 — Post-activity feedback system
**Why:** Inferred preferences from conversation have 0.5-0.7 confidence. Explicit feedback after visiting a place gives 0.9+ confidence. "Did you like Se Cathedral?" → "Loved it, the Portuguese architecture was stunning" → now RAAH knows to prioritize Portuguese colonial architecture with high certainty.

**What:**
- Track "dwell time" near mentioned POIs: if user stays within 150m of a POI the AI mentioned for 10+ minutes, mark it as "visited"
- After the user moves away from a visited POI (>300m), the AI asks for feedback on its next idle moment: "So how was [POI name]? Worth the visit?"
- Parse the response and store as a high-confidence UserPreference (0.9) via LongTermMemory
- Track visited POIs in a `visitedPOIs` dictionary: `[poiID: (arrivalTime, feedbackGiven)]`
- Max 1 feedback request per 15 minutes (don't nag)

**Files:** `ViewModels/AppState.swift`, `Services/ContextPipeline.swift`, `Memory/LongTermMemory.swift`, `Memory/ShortTermMemory.swift`
**Effort:** ~2-3 hours

---

#### 2.5 — Inference cost throttling
**Why:** $9/hour/user on the Realtime API. If the user is silently walking and not talking, the audio tap is still streaming silence to OpenAI and burning input tokens. Pausing during idle saves 60-70% of costs.

**What:**
- After 10 seconds of `voiceState == .idle` (no speech detected), pause the audio input tap and send `input_audio_buffer.clear`
- Resume instantly when: (a) user taps mic button, or (b) proactive narration triggers, or (c) server VAD detects sound on a low-power pre-check
- Track cumulative session minutes in UserDefaults (for usage tracking in Sprint 3)
- Show a subtle "Paused — tap to talk" indicator so user knows the mic isn't hot

**Files:** `Services/OpenAIRealtimeService.swift`, `ViewModels/AppState.swift`, `Views/HomeView.swift`
**Effort:** ~2 hours

---

#### 2.6 — Battery optimization
**Why:** A travel app that kills your battery in 2 hours is a travel app people uninstall.

**What:**
- Adaptive location accuracy:
  - No active voice session: `kCLLocationAccuracyHundredMeters`, `distanceFilter = 50`
  - Active voice session: `kCLLocationAccuracyBest`, `distanceFilter = 10`
- Pause heading updates when not on Explore tab
- Add methods `LocationManager.setHighAccuracy()` / `setLowAccuracy()` called by AppState on session start/end

**Files:** `Services/LocationManager.swift`, `ViewModels/AppState.swift`
**Effort:** ~1 hour

---

#### 2.7 — Exploration history / trip journal
**Why:** Shows depth beyond voice. Proves the "Spatial Preference Graph" concept. Great for demo screenshots. Users can look back at what they discovered.

**What:**
- New `ExplorationLog` model: id, date, duration, startCoordinate, endCoordinate, poisVisited (array of POI names + types), interactionCount, weatherSummary
- Auto-create when voice session starts, finalize (save duration, final POIs) on session end
- Persist as JSON array in local file storage
- New `JournalView`: list of past explorations as glass cards with date, area name (reverse geocoded), POI count, duration
- Tap a card → detail view with POI list and map pins
- Add a "Journal" section accessible from Settings view (or replace the profile tab content)

**Files:** New model in `Models/Models.swift`, new `Views/JournalView.swift`, new `Services/ExplorationLogger.swift`, modify `Views/SettingsView.swift`
**Effort:** ~3-4 hours

---

### Sprint 3: "Make It Safe & Monetizable"
**Goal: Safety features that define the brand. Business layer that impresses VCs.**

---

#### 3.1 — "Walk Me Home" mode
**Why:** 54.6% of solo travelers are female. 70% cite safety as their #1 concern. This single feature could define RAAH's brand. Nobody else has this. It's the demo moment that makes investors lean forward.

**What:**
- Activation: voice command ("walk me home") or button in safety overlay
- AI switches to "watchful companion" system prompt — warmer tone, more conversational, keeps talking to maintain presence
- Check-in every 3 minutes: "Still doing okay?" / "Almost there, 5 more minutes"
- Silence detection: if user doesn't respond to 2 consecutive check-ins (6+ minutes of silence), auto-send SMS to emergency contact: "RAAH Alert: [User] hasn't responded during Walk Me Home mode. Last known location: [Maps link]"
- Visual indicator: safety shield icon pulses green on home screen, orb has a subtle green ring
- Auto-deactivates when user says "I'm home" or manually toggles off
- Share live location with emergency contact on activation (reuse existing SMS logic)

**Files:** `ViewModels/AppState.swift`, `ViewModels/SafetyViewModel.swift`, `Services/ContextPipeline.swift` (system prompt), `Views/HomeView.swift`, `Views/SafetyOverlaySheet.swift`
**Effort:** ~3-4 hours

---

#### 3.2 — Quick SOS
**Why:** Table stakes for a safety-focused travel app. If something goes wrong, there needs to be a way to alert someone in under 2 seconds without fumbling through menus.

**What:**
- Triple-tap the orb → immediately sends emergency SMS to saved contact with current location
- Also available as a dedicated button in the safety overlay sheet
- Haptic burst (3x heavy) on activation so user feels the confirmation
- Message: "SOS from RAAH: [User] triggered an emergency alert. Location: [Apple Maps link]. Time: [now]"
- 3-second countdown with cancel option to prevent accidental triggers
- If voice session is active, AI says "Emergency alert sent to [contact name]"

**Files:** `ViewModels/SafetyViewModel.swift`, `Views/HomeView.swift` (gesture recognizer), `Components/OrbView.swift`
**Effort:** ~1-2 hours

---

#### 3.3 — Usage tracking + free tier limits
**Why:** VCs want to see you understand unit economics. A 30 min/day free tier shows you've thought about the $9/hour inference cost problem.

**What:**
- `UsageTracker` service: tracks daily voice minutes, daily Snap & Ask count, reset at midnight
- Free tier limits: 30 min/day voice, 5 Snap & Ask/day, journal shows last 3 days only
- When limit approached (5 min remaining): AI mentions "You have 5 minutes left today"
- When limit hit: show upgrade prompt sheet (glass card, not aggressive)
- Persist in UserDefaults with date-stamped keys

**Files:** New `Services/UsageTracker.swift`, modify `ViewModels/AppState.swift`, `Views/HomeView.swift`, `Views/SnapAndAskView.swift`
**Effort:** ~2 hours

---

#### 3.4 — Paywall UI + StoreKit 2
**Why:** Completes the business model. Even if you don't launch with payments, having a functioning paywall shows the app is built for revenue.

**What:**
- "RAAH Pro" upgrade sheet with glassmorphism design
- Features listed: unlimited voice, unlimited Snap & Ask, full journal history, priority support
- Two options: $12.99/month or $99/year (save 36%)
- StoreKit 2 integration: Product loading, purchase flow, receipt validation
- Pro status persisted locally + verified via StoreKit
- Pro badge in Settings profile section

**Files:** New `Views/PaywallView.swift`, new `Services/StoreKitManager.swift`, modify `ViewModels/AppState.swift`
**Effort:** ~3-4 hours

---

#### 3.5 — Basic analytics events
**Why:** When a VC asks "what's your average session length?" you need an answer backed by data, not a guess.

**What:**
- Local event logger (JSON file in documents directory)
- Events: `session_start`, `session_end` (with duration), `poi_viewed`, `snap_used`, `proactive_narration_triggered`, `feedback_given`, `walk_me_home_activated`, `sos_triggered`, `paywall_shown`, `paywall_converted`, `share_tapped`
- Summary computed property: average session duration, sessions per day, most viewed POI types
- Visible in Settings as "Your Stats" section (sessions this week, POIs discovered, minutes explored)
- Later: wire to Mixpanel/Amplitude with one-line integration

**Files:** New `Services/AnalyticsLogger.swift`, modify `ViewModels/AppState.swift`, `Views/SettingsView.swift`
**Effort:** ~2 hours

---

#### 3.6 — Share & social hooks
**Why:** Zero organic growth without sharing. If someone discovers something cool with RAAH and can't share it, that's a missed acquisition opportunity.

**What:**
- "Share" button on POI detail cards in Explore view
- Generates a share card: POI name, type icon, Wikipedia summary snippet, "Discovered with RAAH" branding
- Uses `ImageRenderer` (iOS 16+) to create a shareable image from a SwiftUI view
- Standard `ShareLink` / `UIActivityViewController` for sharing
- "Share my exploration" from journal → summary card with POI count, duration, area name
- Deep link URL scheme: `raah://poi/{id}` — registers in Info.plist, handled in RAAHApp

**Files:** New share card view component, modify `Views/ExploreMapView.swift`, `Views/JournalView.swift`, `RAAHApp.swift`, `Info.plist`
**Effort:** ~3 hours

---

## Implementation Order

```
SPRINT 1 — "Make It Real" (~9 hours)
  1.1  Onboarding permissions           ~1 hr     — nothing works without this
  1.5  Weather-aware + sunrise/sunset    ~30 min   — free win, system prompt only
  1.6  Dietary preferences              ~30 min   — free win, onboarding tweak
  1.2  Real camera for Snap & Ask       ~1-2 hr   — magic demo moment
  1.3  Voice error recovery             ~2 hr     — demo reliability
  1.4  Proactive narration              ~3-4 hr   — THE differentiator

SPRINT 2 — "Make It Smart" (~16 hours)
  2.1  Caching layer                    ~2-3 hr   — speed + cost
  2.6  Battery optimization             ~1 hr     — quick win
  2.5  Inference throttling             ~2 hr     — cost savings
  2.2  Web search (niche finds)         ~2-3 hr   — "best samosa" moments
  2.3  Transit directions               ~2 hr     — practical utility
  2.4  Post-activity feedback           ~2-3 hr   — preference building
  2.7  Exploration journal              ~3-4 hr   — depth + demo wow

SPRINT 3 — "Safe & Monetizable" (~14 hours)
  3.1  Walk Me Home mode                ~3-4 hr   — brand-defining safety
  3.2  Quick SOS                        ~1-2 hr   — safety table stakes
  3.3  Usage tracking + limits          ~2 hr     — unit economics proof
  3.4  Paywall UI + StoreKit            ~3-4 hr   — revenue infrastructure
  3.5  Analytics events                 ~2 hr     — data for VC pitch
  3.6  Share & social                   ~3 hr     — growth loop
```

**Total: ~39 hours of focused implementation for a complete, presentable, monetization-ready MVP with safety features that define the brand.**

---

## What This Gets You

After all 3 sprints, RAAH is:

1. **Real** — actual camera, actual permissions, voice that survives network drops
2. **Proactive** — spontaneously points out interesting things as you walk, weighted by your preferences
3. **Smart about context** — knows the weather, sunset time, transit routes, and the best samosa spot according to Reddit
4. **Safe** — Walk Me Home mode, Quick SOS, weather warnings, safety monitoring
5. **Efficient** — caches data, throttles idle inference, adapts battery usage
6. **Monetizable** — freemium paywall, usage tracking, analytics
7. **Shareable** — discovery cards, journal summaries, deep links
8. **Learnable** — asks for feedback after visits, builds high-confidence taste profiles

This covers all three analysis documents:
- Doc 1's vision of the "Cognitive Spatial Layer" and "Informed Friend" persona
- Doc 2's data strategy (caching, hybrid brain, India-specific stack)
- Doc 3's unit economics (inference throttling, tiered pricing, LTV:CAC metrics)

---

## What's Explicitly NOT in MVP (and why)

| Feature | Why Not |
|---------|---------|
| ElevenLabs premium voices | OpenAI Realtime voice is good enough. Adds latency + complexity for marginal quality. |
| Runner/cyclist mode | Niche use case. Nail the walking explorer first. |
| Audio advertising | Needs advertiser partnerships. Can't demo without real ad inventory. |
| B2B tourism board licensing | Sales cycle is months. Not an MVP feature. |
| GDPR/DPDP consent management | Important for launch, not for MVP demo. |
| Regional languages (Hindi, etc.) | Sarvam-M integration is a separate project. English-first MVP. |
| Apple Watch app | Scope creep. Phone is the product. |
| Offline maps / full offline mode | Complex. Demo will have internet. Build post-MVP. |
| AR overlays | Months of ARKit work. Not the differentiator. |
| Social feed / user-generated content | Needs backend, moderation, trust & safety. Post-MVP. |
| Reddit/YouTube raw scraping | Legally gray, technically fragile. Web search API achieves the same result legally. |
