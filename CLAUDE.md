# RAAH — Instructions for Claude

## Communication Style
**Be brutally honest. No flattery, no validation, no "great idea!" padding. If something is a bad idea, say so directly and explain why. If code is bad, say it's bad. Never be biased — help build the best possible app. The user values directness over comfort.**

## What You're Building
RAAH is a voice-first AI travel companion for iOS. The user walks around a city, taps an animated orb, and has a real-time voice conversation with an AI that's spatially aware — it knows nearby landmarks, restaurants, weather, and safety conditions. Think: a knowledgeable local friend in your ear.

## Golden Rules

1. **Never add third-party dependencies.** Everything is native: URLSession, MapKit, AVFoundation, HealthKit. No SPM packages, no CocoaPods, no Alamofire, no Kingfisher. If you need something, build it with Apple frameworks.

2. **Use @Observable, not ObservableObject.** This is an iOS 17+ app. All state classes use `@Observable`. Views access state with `@Environment(AppState.self)`. For bindings, use `@Bindable var state = appState` inside the view body.

3. **AppState is the single source of truth.** It's injected at the root via `.environment(appState)`. It owns every service and manager. Don't create new singletons or global state — hang new state off AppState.

4. **Follow the design system.** Never use raw spacing, font sizes, or corner radii. Always use:
   - `RAAHTheme.Spacing.*` (xxxs through xxxl)
   - `RAAHTheme.Radius.*` (sm, md, lg, xl, pill)
   - `RAAHTheme.Typography.*` (largeTitle, title, headline, body, caption, etc.)
   - `RAAHTheme.Motion.*` (snappy, smooth, gentle, breathe, pulse)
   - `HapticEngine.*` for all haptic feedback

5. **Use the glass components.** UI should feel like frosted glass. Use `GlassCard`, `GlassIconButton`, `GlassPillButton`, `GlassToggleRow`, `GlassNavRow`, `GlassSheet`, `FrostedGlassBackground`, `.ultraThinMaterial`. Don't make new card/button styles — extend these.

6. **Dark mode first.** The app forces `.preferredColorScheme(.dark)`. Design accordingly. `TimeOfDayPalette` handles day/night color shifts automatically.

7. **Keep the accent color dynamic.** The user picks their theme (violetAura, papayaFlame, neonMint, blush, iceBlue). Always use `appState.accentColor` or `appState.accentTheme.color/gradient` — never hardcode accent colors.

8. **JSON parsing uses JSONSerialization**, not Codable structs for API responses. Keep this consistent. Model structs (POI, Interaction, etc.) are Codable for local persistence, but API response parsing is manual.

9. **All network calls use async/await.** Combine is only used for the location publisher binding in ContextPipeline. Don't introduce new Combine publishers for network requests.

10. **Don't break the context pipeline.** The flow is: user moves 100m → ContextPipeline fetches POIs + safety + weather in parallel → enriches top 5 POIs with Wikipedia → builds SpatialContext → injects into OpenAI system prompt. If you add new context sources, plug them into `ContextPipeline.fetchContext()`.

## How to Add Things

### New View
- Create in `Views/` folder
- Access state: `@Environment(AppState.self) private var appState`
- Use `GlassCard` for content sections, `RAAHTheme` for all styling
- Add haptics on user interactions: `HapticEngine.light()` for taps, `.medium()` for important actions, `.heavy()` for primary actions

### New Service
- Create in `Services/` folder
- Make it a plain `final class` (not @Observable, unless it has UI-facing state)
- Add it as a `let` property on `AppState`
- Check API key availability with `APIKeys.isXConfigured` before making calls
- Fail gracefully — return empty/nil, don't throw to the UI

### New Data Model
- Add to `Models/Models.swift` — that file holds all types
- Mark it `Codable` if it needs persistence
- Mark it `Identifiable` if it appears in SwiftUI lists/ForEach

### New API Integration
- Add the key to `APIKeys.swift` with a static property + validation computed property
- Add a status row in `SettingsView.apiKeysSection`
- Always make the feature work without the key (graceful degradation)

### New Tool Call (for the AI)
- Add the tool definition to `OpenAIRealtimeService.toolDefinitions`
- Handle it in `AppState.handleToolCall(name:args:)`
- Keep tool descriptions short — the Realtime API has limited context

### New Orb Style
- Add a case to `OrbStyle` enum in `Models.swift`
- Create the view in `OrbView.swift` following the pattern of FluidOrbView/CrystalOrbView/PulseRingOrbView
- Add to the `switch` in `OrbView.body`
- Must accept: `accentTheme`, `voiceState`, `heartRate`, `size`
- Green glow when `voiceState == .listening` (mic is active)

## File Map (what's where)

| Need to change... | Go to... |
|---|---|
| App entry point, root environment | `RAAHApp.swift` |
| Tab routing, onboarding gate | `ContentView.swift` |
| All shared state, voice session logic, tool call handling | `ViewModels/AppState.swift` |
| Data types (POI, Interaction, SafetyLevel, etc.) | `Models/Models.swift` |
| API keys and validation | `Config/APIKeys.swift` |
| Main voice/orb screen | `Views/HomeView.swift` |
| Map with POI markers | `Views/ExploreMapView.swift` |
| First-run setup flow | `Views/OnboardingView.swift` |
| User settings & API key entry | `Views/SettingsView.swift` |
| Camera → AI image analysis | `Views/SnapAndAskView.swift` |
| Safety alert UI | `Views/SafetyOverlaySheet.swift` |
| The animated orb (3 styles) | `Components/OrbView.swift` |
| Glass cards, buttons, toggles | `Components/GlassCard.swift` |
| Spacing, typography, colors, animations | `Design/Theme.swift` |
| Glass backgrounds, sheets, shimmer | `Design/LiquidGlass.swift` |
| WebSocket voice connection | `Services/OpenAIRealtimeService.swift` |
| Spatial context orchestration | `Services/ContextPipeline.swift` |
| POI fetching (OpenStreetMap) | `Services/OverpassService.swift` |
| POI enrichment (Wikipedia) | `Services/WikipediaService.swift` |
| Weather data | `Services/WeatherService.swift` |
| Area safety scoring | `Services/SafetyScoreService.swift` |
| GPS + movement detection | `Services/LocationManager.swift` |
| Preference learning from conversations | `Memory/LongTermMemory.swift` |
| Recent conversation buffer | `Memory/ShortTermMemory.swift` |

## Common Pitfalls

- **Don't use `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject`** — this app uses the iOS 17 Observation framework exclusively.
- **Don't use `.task { }` for one-shot fetches that need cancellation** — use `Task { }` inside callbacks so you control the lifecycle.
- **The Overpass API has rate limits** — don't reduce the 100m movement threshold or the 2-second debounce.
- **OpenAI Realtime API uses PCM16 at 24kHz** — don't change the audio format constants.
- **Default location is Goa, India (15.391736, 73.880064)** with demo restaurant POIs so the app works in Simulator without setting a custom location. Don't remove this fallback.
- **The `ContextPipeline.buildSystemPrompt()` has carefully worded instructions** telling the AI to use ONLY the provided POI list for "nearest X" questions. Don't weaken these constraints or the AI will hallucinate place names.

## Build & Run
```bash
cd /Users/aakarshasawa/Desktop/RAAH
xcodebuild -project RAAH.xcodeproj -scheme RAAH \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
```
Builds clean with zero errors. The project at `/Users/aakarshasawa/Desktop/RAAH/` is the real one — ignore the partial copy at `/Users/aakarshasawa/Desktop/r a a h/RAAH/`.
