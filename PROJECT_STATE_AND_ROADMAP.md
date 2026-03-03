# RAAH — Project State & Roadmap

You're starting with no context. This doc explains **what the app is**, **what’s already done**, **what’s broken or missing**, and **what to do next**.

---

## 1. What RAAH Is (and what you’ve understood)

**RAAH** is an **iOS voice-first AI travel companion**:

- **Voice:** User talks to an orb; the app uses **OpenAI Realtime API** (voice in/out). User speaks → AI replies by voice.
- **Location-aware:** Uses the device’s location (or a default in Simulator) to fetch **nearby places (POIs)**, **weather**, and **safety** and feed that into the AI so it can say things like “nearest burger place is X, 200m away” and “it’s 28°C, partly cloudy.”
- **Design:** “Liquid glass” style, orb in the center, tabs: **Home** (orb + voice), **Explore** (map + POIs), **You** (Settings).
- **Goal:** Accurate, reliable answers about **location**, **weather**, **nearest food/places**, and **directions** — no fake data, no “I cannot do it” when the data exists.

You want it to be **accurate**, **reliable**, and **production-ready** — real location data, real POIs, real weather, and no rage-quit-level gaps.

---

## 2. What Has Been Done (current codebase)

### 2.1 App shell and UX

- **RAAHApp.swift** — App entry, `AppState` in environment.
- **ContentView** — Shows onboarding until complete, then main app (tabs + sheets for Snap & Ask, Safety).
- **Tabs:** Home (orb + voice), Explore (map), You (Settings).
- **Onboarding** — Name, interests, accent/orb style, permissions (location, mic, camera, health).
- **Design system** — `RAAHTheme`, `LiquidGlass`, `GlassCard`, `FloatingTabBar`, `OrbView` (fluid/crystal/pulse styles), haptics.
- **Orb feedback** — Orb turns **green** when the mic is listening (input active).

### 2.2 Voice (OpenAI Realtime)

- **OpenAIRealtimeService** — WebSocket to OpenAI Realtime API, PCM16 audio in/out.
- **Microphone** — Captures audio, sends to API.
- **Playback** — Response audio is played via a separate `AVAudioEngine` + `AVAudioPlayerNode` (24 kHz mono).
- **API key** — Stored in **UserDefaults**; user pastes it in **You → API CONNECTIONS** (no code edit needed).
- **Model** — `gpt-4o-mini-realtime` (cheaper, still voice-capable).
- **System prompt** — Built by `ContextPipeline.buildSystemPrompt(...)` and includes: user name, weather, POIs, safety, preferences, recent convo. Instructions tell the AI to use **CURRENT WEATHER** for weather and **NEARBY POINTS OF INTEREST** for “nearest X” and directions.

### 2.3 Location and context pipeline

- **LocationManager** — CoreLocation, `currentLocation`, `effectiveLocation` (falls back to **Goa 15.39, 73.88** when there’s no GPS, e.g. Simulator). Fires `significantMovementPublisher` when user moves >100 m.
- **ContextPipeline** — Single place that gathers context and builds the prompt:
  - **OverpassService** — OpenStreetMap Overpass API: fetches POIs (heritage, tourism, **restaurant/cafe/fast_food**, etc.) in 800 m radius.
  - **WeatherService** — Open-Meteo (free): current temp, condition, humidity → string like “28°C, partly cloudy…” injected into prompt.
  - **SafetyScoreService** — Safety level + weather alerts (Open-Meteo for warnings; GeoSure if key set).
  - **WikipediaService** — Enriches top POIs with Wikipedia/Wikivoyage summaries.
  - **MapplsService** — India: DigiPin, road alerts (needs Mappls keys); **no nearby places search** implemented yet.
  - **Demo POIs** — If near Goa and Overpass returns **&lt; 4 POIs**, the code **adds hardcoded demo places** (e.g. “Burger Factory”, “Martin’s Corner”). You’ve said you **don’t** want this; you want **real location data only**.
- **SpatialContext** — Holds: `pois`, `safetyLevel`, `weatherWarning`, **`currentWeatherSummary`**, `nearbyOffers`, `isInIndia`. Its `systemPromptFragment` feeds the AI (weather + POI list + safety).
- **refreshContext()** — Called on main screen `onAppear` so context (and thus POIs/weather) loads at launch.

### 2.4 Google Places (implemented but not used)

- **GooglePlacesService.swift** — Implemented: calls **Places API (New)** `searchNearby` (restaurant, cafe, meal_takeaway, food) in 800 m, parses to `[POI]`.
- **Not wired:** `ContextPipeline` never calls it. So **Google Places is not used**; only Overpass (and demo POIs) feed the AI today.

### 2.5 Map and directions

- **ExploreMapView** — MapKit map, user location, POI markers from `contextPipeline.nearbyPOIs`. Tapping a POI shows a card with “Directions” that opens **Apple Maps** to that coordinate.
- **Map options** — Filter button opens a sheet with “Center on my location”. If no real GPS, map centers on Goa.

### 2.6 Other services (present, optional)

- **SupabaseService** — Long-term memory (preferences); needs Supabase URL + anon key.
- **AffiliateService** — GetYourGuide for tickets; needs partner ID + API key.
- **OpenAIVisionService** — GPT-4o Vision for “Snap & Ask”.
- **SnapAndAskView** — Placeholder capture + Vision call; real camera can be wired later.

### 2.7 Settings (You tab)

- **API CONNECTIONS** — OpenAI key (UserDefaults), status for OpenAI / Supabase / Google Places / Mappls / GetYourGuide / GeoSure. Text says weather uses Open-Meteo and location uses OSM + demo; suggests adding Google/Mappls for better accuracy.
- **Simulator tip** — When running in Simulator, a blue card explains how to set **Features → Location → Custom Location** (Goa is already the app default when GPS is nil).

---

## 3. What’s Wrong / What Needs to Be Done

### 3.1 Accuracy and “no demo data”

- **Demo POIs** — Pipeline still injects fake Goa places when Overpass returns few results. You want **no manual/demo POIs**; only real data.
- **Google Places not used** — Service exists but pipeline doesn’t call it. So we’re not using your best source for accurate restaurants/cafes.
- **Mappls** — Only used for DigiPin/road alerts in India, not for **nearby places**. For India, Mappls nearby search would improve accuracy.

**Needed:**

1. **Remove** demo POI logic from `ContextPipeline` (no `isNearGoa`, no `demoGoaPOIs`).
2. **Use Google Places** when `APIKeys.isGooglePlacesConfigured`: call `GooglePlacesService.fetchNearbyPlaces`, merge with Overpass (dedupe by name/position), sort by distance. Prefer or combine so the AI gets real restaurants/cafes.
3. **Optionally:** Add Mappls nearby places (Search/Nearby API) when in India and Mappls is configured; merge those POIs too so India has accurate local results.

### 3.2 Location behavior

- **effectiveLocation** — Today it **always** falls back to Goa when `currentLocation == nil` (both Simulator and device). On a **real device** with GPS, `currentLocation` will be set and used; on Simulator with no location set, you get Goa. So “location” is real when GPS is available; otherwise it’s a fixed default. If you want device to never use a default, we can change `effectiveLocation` so it only returns `currentLocation` on device (and leave Simulator with default for testing).

### 3.3 “I cannot do it” / weather

- **Weather** — Already fetched (Open-Meteo) and put in the prompt as **CURRENT WEATHER**. The system prompt tells the AI to use it and not refuse weather questions. If the model still says “I cannot,” we can tighten the prompt further (e.g. “You MUST answer weather from CURRENT WEATHER; never say you cannot.”).
- **Other refusals** — Prompt allows general knowledge for non-POI questions; POI answers must come from the POI list. If the list is empty or weak (e.g. Overpass only), the AI has little to say. Fixing POI sources (Google + optional Mappls) will reduce those cases.

### 3.4 Navigation / directions

- **Directions** — Today: user taps POI on Explore map → “Directions” → Apple Maps opens to that coordinate. No turn-by-turn inside the app. For “better navigation” we could:
  - Keep current (open in Apple Maps), and/or
  - Add **Google Directions** or **Mappls Directions** to get a route URL and open that (e.g. in Google Maps or Apple Maps). That’s a separate integration once POIs are solid.

### 3.5 Optional / polish

- **Supabase** — For long-term memory; needs project + anon key and `setup.sql` run.
- **Snap & Ask** — Replace placeholder capture with real camera if you want it for demo.
- **In-app API key fields** — Google Places and Mappls are still in `Config/APIKeys.swift` only. We could add in-app fields (like OpenAI) so users don’t edit code.

---

## 4. Roadmap (what to do and in what order)

### Phase 1 — Accurate POIs, no demo (do first)

1. **Remove demo POIs**  
   In `ContextPipeline.fetchContext`: delete `isNearGoa`, `demoGoaPOIs`, and the block that appends demo POIs when `pois.count < 4`.

2. **Wire Google Places into the pipeline**  
   - In `fetchContext`, if `APIKeys.isGooglePlacesConfigured`, call `GooglePlacesService().fetchNearbyPlaces(coordinate)` (e.g. 800 m).  
   - Merge with Overpass POIs: combine lists, dedupe by name or lat/lon (e.g. same name within 50 m = same place), sort by distance.  
   - Use merged list for `nearbyPOIs` and for building `SpatialContext`.  
   - So: with a **Google Places API key** (Places API (New) enabled), the app uses **real** nearby restaurants/cafes/food.

3. **Document keys**  
   In Settings or a short README: “For accurate nearby places, add **Google Places API key** (Places API (New)) in Config/APIKeys.swift → `googlePlaces`.”

### Phase 2 — India accuracy (if you care about India)

4. **Mappls nearby places**  
   - In `MapplsService`, add e.g. `fetchNearbyPlaces(coordinate, category: String?)` calling Mappls Search Nearby API (`refLocation`, optional category for food).  
   - In `ContextPipeline`, when `isInIndia && APIKeys.isMapplsConfigured`, call it and merge POIs with Overpass + Google (dedupe, sort by distance).  
   - Requires Mappls API key (and correct auth for Search API).

### Phase 3 — Robustness and clarity

5. **Prompt tweak**  
   - Reiterate: “Use CURRENT WEATHER for any weather question; never say you cannot.”  
   - Reiterate: “For nearest place/food, use only NEARBY POINTS OF INTEREST; if the list is empty, say you don’t have nearby data right now.”

6. **Location logic (optional)**  
   - On device: use only `currentLocation` (no default) so the app doesn’t pretend a fixed place when GPS is off.  
   - Keep default (e.g. Goa) only for Simulator so demos still work.

7. **Directions (optional)**  
   - Add Google Directions (or Mappls) to build a route URL and open it (e.g. “Open in Maps”) for the selected POI. Improves “want directions?” flow.

### Phase 4 — Nice-to-haves

8. **In-app API keys**  
   Store Google Places and Mappls keys in UserDefaults (or keychain) and read in `APIKeys`, same pattern as OpenAI, so users don’t edit code.

9. **Supabase + setup.sql**  
   If you want long-term memory, configure project and run the provided SQL.

10. **Snap & Ask**  
    Replace placeholder image capture with real camera and optional permission handling.

---

## 5. Summary

- **Understood:** RAAH is a voice-first, location-aware travel companion; you want it **accurate**, **no demo POIs**, and **reliable** (weather, nearest places, directions).
- **Done:** App shell, voice (Realtime + playback), location + context pipeline, Overpass + weather + safety, map + directions to Apple Maps, Google Places **service** (not wired), Settings, onboarding.
- **Gaps:** Demo POIs still in use; Google Places not used; Mappls not used for nearby places; optional: in-app keys, directions API, Supabase, Snap & Ask camera.
- **Roadmap:**  
  - **First:** Remove demo POIs and wire Google Places into the pipeline so POIs are real and accurate when the key is set.  
  - **Then:** Optionally add Mappls nearby for India, then prompt/location/directions and the rest.

If you tell me “start with Phase 1,” I’ll implement: remove demo POIs and wire Google Places into `ContextPipeline` (merge with Overpass, dedupe, sort), and keep the rest of the behavior unchanged.
