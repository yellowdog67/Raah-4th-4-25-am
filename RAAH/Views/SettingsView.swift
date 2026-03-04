import SwiftUI
import CoreLocation

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingJournal = false
    @State private var showingPOIList = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: RAAHTheme.Spacing.lg) {
                header
                simulatorLocationTip
                profileSection
                dietarySection
                budgetSection
                journalSection
                appearanceSection
                safetySection
                memorySection
                statsSection
                aboutSection
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .background {
            TimeOfDayPalette().backgroundGradient.ignoresSafeArea()
        }
    }
    
    // MARK: - Header
    
    private var simulatorLocationTip: some View {
        Group {
            #if targetEnvironment(simulator)
            GlassCard(padding: RAAHTheme.Spacing.sm) {
                HStack(spacing: 10) {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simulator: change location")
                            .font(RAAHTheme.Typography.caption(.semibold))
                        Text("Menu bar → Features → Location → Custom Location. Enter e.g. 28.6139, 77.2090")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            #else
            EmptyView()
            #endif
        }
    }
    
    private var header: some View {
        HStack {
            Text("Settings")
                .font(RAAHTheme.Typography.largeTitle())
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            Spacer()
        }
        .padding(.horizontal, RAAHTheme.Spacing.xs)
        .padding(.vertical, RAAHTheme.Spacing.sm)
        .padding(.top, RAAHTheme.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous))
    }
    
    // MARK: - Profile
    
    private var profileSection: some View {
        @Bindable var state = appState
        return GlassCard {
            VStack(spacing: 16) {
                sectionTitle("PROFILE")
                
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(appState.accentColor.gradient)
                            .frame(width: 52, height: 52)
                        Text(String(appState.userName.prefix(1)).uppercased())
                            .font(RAAHTheme.Typography.title2(.bold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("Your name", text: $state.userName)
                                .font(RAAHTheme.Typography.headline())
                            if appState.usageTracker.isProUser {
                                Text("PRO")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(appState.accentColor.gradient))
                            }
                        }

                        Text("\(appState.longTermMemory.preferences.count) learned preferences")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)

                        if let created = appState.profileCreatedAt {
                            Text("Member since \(created.formatted(.dateTime.month(.wide).year()))")
                                .font(RAAHTheme.Typography.caption())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Appearance
    
    private var appearanceSection: some View {
        GlassCard {
            VStack(spacing: 16) {
                sectionTitle("APPEARANCE")
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accent Color")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                    
                    HStack(spacing: 14) {
                        ForEach(AccentTheme.allCases, id: \.rawValue) { theme in
                            Button {
                                HapticEngine.selection()
                                appState.accentTheme = theme
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(theme.color.gradient)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if appState.accentTheme == theme {
                                                Circle()
                                                    .strokeBorder(.white, lineWidth: 2)
                                            }
                                        }
                                        .shadow(color: theme.color.opacity(appState.accentTheme == theme ? 0.4 : 0), radius: 8)
                                    
                                    Text(theme.displayName)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(appState.accentTheme == theme ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Voice")
                        .font(RAAHTheme.Typography.subheadline(.medium))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(AIVoice.allCases, id: \.rawValue) { voice in
                            let selected = appState.selectedVoice == voice
                            Button {
                                HapticEngine.selection()
                                appState.selectedVoice = voice
                            } label: {
                                VStack(spacing: 3) {
                                    Text(voice.displayName)
                                        .font(RAAHTheme.Typography.body(.medium))
                                        .foregroundStyle(selected ? .primary : .secondary)
                                    Text(voice.description)
                                        .font(RAAHTheme.Typography.caption())
                                        .foregroundStyle(selected ? AnyShapeStyle(appState.accentColor) : AnyShapeStyle(.tertiary))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: RAAHTheme.Radius.sm, style: .continuous)
                                        .fill(selected ? appState.accentColor.opacity(0.15) : Color.white.opacity(0.06))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: RAAHTheme.Radius.sm, style: .continuous)
                                        .strokeBorder(selected ? appState.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Orb Style")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                    
                    ForEach(OrbStyle.allCases, id: \.rawValue) { style in
                        Button {
                            HapticEngine.selection()
                            appState.orbStyle = style
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: appState.orbStyle == style ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(appState.orbStyle == style ? appState.accentColor : .secondary)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(style.displayName)
                                        .font(RAAHTheme.Typography.body(.medium))
                                        .foregroundStyle(.primary)
                                    Text(style.description)
                                        .font(RAAHTheme.Typography.caption())
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Safety
    
    private var safetySection: some View {
        @Bindable var state = appState
        return GlassCard {
            VStack(spacing: 16) {
                sectionTitle("SAFETY")

                GlassToggleRow(
                    "Safety Overlay",
                    subtitle: "Monitor area safety continuously",
                    icon: "shield.checkered",
                    iconColor: .green,
                    isOn: $state.safetyOverlayEnabled
                )

                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Emergency Contact")
                        .font(RAAHTheme.Typography.subheadline(.medium))

                    TextField("Contact name", text: $state.emergencyContactName)
                        .font(RAAHTheme.Typography.body())
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: RAAHTheme.Radius.sm, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }

                    TextField("Phone number", text: $state.emergencyContactPhone)
                        .font(RAAHTheme.Typography.body())
                        .keyboardType(.phonePad)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: RAAHTheme.Radius.sm, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }
                }
            }
        }
    }
    
    // MARK: - Memory
    
    private var journalSection: some View {
        GlassCard {
            VStack(spacing: 16) {
                sectionTitle("JOURNAL")

                GlassNavRow(
                    "Exploration History",
                    subtitle: "\(appState.explorationLogger.logs.count) explorations",
                    icon: "book.fill",
                    iconColor: appState.accentColor
                ) {
                    showingJournal = true
                }
            }
        }
        .sheet(isPresented: $showingJournal) {
            JournalView()
                .environment(appState)
        }
    }

    private var memorySection: some View {
        GlassCard {
            VStack(spacing: 16) {
                sectionTitle("MEMORY")

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nearby places")
                            .font(RAAHTheme.Typography.body(.medium))
                        Text("\(appState.contextPipeline.nearbyPOIs.count) POIs in AI context")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View") {
                        showingPOIList = true
                    }
                    .font(RAAHTheme.Typography.caption(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                    Button("Refresh") {
                        SpatialCache.shared.clearAll()
                        appState.refreshContext()
                        HapticEngine.medium()
                    }
                    .font(RAAHTheme.Typography.caption(.medium))
                    .foregroundStyle(appState.accentColor)
                }

                if showingPOIList && !appState.contextPipeline.nearbyPOIs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.contextPipeline.nearbyPOIs.prefix(30)) { poi in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(poi.tags["source"] == "google" ? Color.blue : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(poi.name)
                                    .font(RAAHTheme.Typography.caption(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let dist = poi.distance {
                                    Text("\(Int(dist))m")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.blue).frame(width: 6, height: 6)
                                Text("Google").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("Overpass").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: RAAHTheme.Radius.sm)
                            .fill(Color.white.opacity(0.05))
                    }
                }

                Divider().opacity(0.2)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Short-term")
                            .font(RAAHTheme.Typography.body(.medium))
                        Text("\(appState.shortTermMemory.interactions.count) / 10 interactions")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear") {
                        appState.shortTermMemory.clear()
                        HapticEngine.light()
                    }
                    .font(RAAHTheme.Typography.caption(.medium))
                    .foregroundStyle(.red)
                }
                
                Divider().opacity(0.2)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Long-term preferences")
                            .font(RAAHTheme.Typography.body(.medium))
                        Text("\(appState.longTermMemory.preferences.count) learned tastes")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                if !appState.longTermMemory.preferences.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appState.longTermMemory.preferences.prefix(8)) { pref in
                                Text(pref.value)
                                    .font(RAAHTheme.Typography.caption())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        Capsule()
                                            .fill(appState.accentColor.opacity(0.15))
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Stats

    private var statsSection: some View {
        GlassCard {
            VStack(spacing: 16) {
                sectionTitle("YOUR STATS")

                HStack(spacing: 0) {
                    statBox(value: "\(appState.analytics.sessionsThisWeek)", label: "Sessions\nthis week")
                    Spacer()
                    statBox(value: "\(appState.analytics.poisDiscovered)", label: "POIs\ndiscovered")
                    Spacer()
                    statBox(value: "\(appState.analytics.totalMinutesExplored)", label: "Minutes\nexplored")
                    Spacer()
                    statBox(value: "\(appState.analytics.snapsThisWeek)", label: "Snaps\nthis week")
                }

                if let topType = appState.analytics.mostViewedPOIType {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 12))
                        Text("Most explored: \(topType)")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(RAAHTheme.Typography.title2(.bold))
                .foregroundStyle(appState.accentColor)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - About

    private var aboutSection: some View {
        GlassCard {
            VStack(spacing: 12) {
                sectionTitle("ABOUT")
                
                HStack {
                    Text("RAAH")
                        .font(RAAHTheme.Typography.headline())
                    Spacer()
                    Text("v1.0.0")
                        .font(RAAHTheme.Typography.caption())
                        .foregroundStyle(.secondary)
                }
                
                Text("Your AI companion for the physical world. Turning every walk into a conversation worth having.")
                    .font(RAAHTheme.Typography.caption())
                    .foregroundStyle(.secondary)

            }
        }
    }
    
    // MARK: - Dietary

    private var dietarySection: some View {
        GlassCard {
            VStack(spacing: 16) {
                sectionTitle("DIETARY PREFERENCES")

                let selected = Set(
                    appState.dietaryRestrictions
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(DietaryRestriction.allCases, id: \.rawValue) { restriction in
                        let isOn = selected.contains(restriction.displayName)
                        Button {
                            toggleDietary(restriction)
                        } label: {
                            HStack(spacing: 6) {
                                Text(restriction.icon)
                                    .font(.system(size: 14))
                                Text(restriction.displayName)
                                    .font(RAAHTheme.Typography.caption(.medium))
                                    .foregroundStyle(isOn ? .primary : .secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(isOn ? appState.accentColor.opacity(0.2) : Color.white.opacity(0.06))
                            }
                            .overlay {
                                Capsule().strokeBorder(isOn ? appState.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !appState.dietaryRestrictions.isEmpty {
                    Text("AI will respect these when recommending food")
                        .font(RAAHTheme.Typography.caption())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Budget

    private let budgetOptions: [(label: String, value: String, icon: String, hint: String)] = [
        ("Any", "", "💰", "No preference"),
        ("Budget", "₹ (budget/cheap)", "₹", "Street food & cheap eats"),
        ("Moderate", "₹₹ (moderate)", "₹₹", "Mid-range restaurants"),
        ("Upscale", "₹₹₹+ (upscale/fine dining)", "₹₹₹", "Fine dining & premium"),
    ]

    private var budgetSection: some View {
        GlassCard {
            VStack(spacing: 16) {
                sectionTitle("BUDGET PREFERENCE")

                HStack(spacing: 10) {
                    ForEach(budgetOptions, id: \.value) { opt in
                        let isSelected = appState.budgetPreference == opt.value
                        Button {
                            appState.budgetPreference = opt.value
                            HapticEngine.selection()
                        } label: {
                            VStack(spacing: 4) {
                                Text(opt.icon)
                                    .font(.system(size: 16))
                                Text(opt.label)
                                    .font(RAAHTheme.Typography.caption(.medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md)
                                    .fill(isSelected ? appState.accentColor.opacity(0.2) : Color.white.opacity(0.06))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: RAAHTheme.Radius.md)
                                    .strokeBorder(isSelected ? appState.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("AI will filter recommendations by price tier")
                    .font(RAAHTheme.Typography.caption())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func toggleDietary(_ restriction: DietaryRestriction) {
        var current = Set(
            appState.dietaryRestrictions
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        if current.contains(restriction.displayName) {
            current.remove(restriction.displayName)
        } else {
            current.insert(restriction.displayName)
        }
        appState.dietaryRestrictions = current.sorted().joined(separator: ", ")
        HapticEngine.selection()
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(RAAHTheme.Typography.caption(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Spacer()
        }
    }
}
