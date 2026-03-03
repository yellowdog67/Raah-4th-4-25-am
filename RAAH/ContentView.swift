import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                ZStack(alignment: .bottom) {
                    TabView(selection: $state.selectedTab) {
                        HomeView()
                            .tag(AppTab.home)

                        ExploreMapView()
                            .tag(AppTab.explore)

                        SettingsView()
                            .tag(AppTab.profile)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    FloatingTabBar(
                        selectedTab: $state.selectedTab,
                        accentColor: appState.accentColor
                    )
                    .padding(.bottom, RAAHTheme.Spacing.sm)
                }
                .ignoresSafeArea(.keyboard)
                .onAppear {
                    appState.setupAfterOnboarding()
                }
                .onChange(of: appState.selectedTab) { _, newTab in
                    if newTab == .explore {
                        appState.locationManager.resumeHeading()
                    } else {
                        appState.locationManager.pauseHeading()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(RAAHTheme.Motion.smooth, value: appState.hasCompletedOnboarding)
        .fullScreenCover(isPresented: Binding(
            get: { appState.isNavigating },
            set: { if !$0 { appState.stopNavigation() } }
        )) {
            NavigationMapView()
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { state.showingSnapAndAsk && !appState.isNavigating },
            set: { state.showingSnapAndAsk = $0 }
        )) {
            SnapAndAskView()
        }
        .sheet(isPresented: Binding(
            get: { state.showingSafetyAlert && !appState.isNavigating },
            set: { state.showingSafetyAlert = $0 }
        )) {
            SafetyOverlaySheet(isPresented: $state.showingSafetyAlert)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: Binding(
            get: { state.showingUpgradePrompt && !appState.isNavigating },
            set: { state.showingUpgradePrompt = $0 }
        )) {
            PaywallView()
                .environment(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
