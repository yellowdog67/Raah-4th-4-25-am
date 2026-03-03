import SwiftUI

// MARK: - Liquid Glass View Modifier

struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let borderOpacity: Double
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderOpacity),
                                Color.white.opacity(borderOpacity * 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Frosted Glass Background

struct FrostedGlassBackground: View {
    let cornerRadius: CGFloat
    let tint: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.05))
            
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4),
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

// MARK: - Adaptive Glass Sheet

struct GlassSheet<Content: View>: View {
    let content: Content
    let maxHeight: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(maxHeight: CGFloat = .infinity, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.maxHeight = maxHeight
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            content
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.xl, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.xl, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.03)
                            : Color.white.opacity(0.5)
                    )
                
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.xl, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3),
                        lineWidth: 0.5
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RAAHTheme.Radius.xl, style: .continuous))
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    let speed: Double
    
    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.1),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = RAAHTheme.Radius.lg,
        opacity: Double = 1.0,
        borderOpacity: Double = 0.15
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            opacity: opacity,
            borderOpacity: borderOpacity
        ))
    }
    
    func shimmer(speed: Double = 2.0) -> some View {
        modifier(ShimmerEffect(speed: speed))
    }
}
