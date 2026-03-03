import SwiftUI

@main
struct RAAHApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(appState.accentColor)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // raah://poi/Temple%20Name  →  switch to explore tab
        guard url.scheme == "raah" else { return }

        switch url.host {
        case "poi":
            // Navigate to explore tab — the POI name is in the path
            appState.selectedTab = .explore
        default:
            break
        }
    }
}
