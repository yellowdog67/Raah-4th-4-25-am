import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let accentColor: Color
    
    @Namespace private var tabAnimation
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.3),
                                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
        }
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 60)
    }
    
    private func tabItem(_ tab: AppTab) -> some View {
        Button {
            withAnimation(RAAHTheme.Motion.snappy) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if selectedTab == tab {
                        Capsule()
                            .fill(accentColor.opacity(0.2))
                            .matchedGeometryEffect(id: "tab_bg", in: tabAnimation)
                    }
                    
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? accentColor : .secondary)
                }
                .frame(height: 32)
                
                Text(tab.label)
                    .font(RAAHTheme.Typography.caption(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
