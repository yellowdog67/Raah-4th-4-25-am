import SwiftUI

// MARK: - RAAH Design System

struct RAAHTheme {
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Radius
    
    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let pill: CGFloat = 100
    }
    
    // MARK: - Typography
    
    enum Typography {
        static func largeTitle(_ weight: Font.Weight = .bold) -> Font {
            .system(size: 34, weight: weight, design: .rounded)
        }
        static func title(_ weight: Font.Weight = .semibold) -> Font {
            .system(size: 28, weight: weight, design: .rounded)
        }
        static func title2(_ weight: Font.Weight = .semibold) -> Font {
            .system(size: 22, weight: weight, design: .rounded)
        }
        static func headline(_ weight: Font.Weight = .semibold) -> Font {
            .system(size: 17, weight: weight, design: .rounded)
        }
        static func body(_ weight: Font.Weight = .regular) -> Font {
            .system(size: 17, weight: weight, design: .default)
        }
        static func callout(_ weight: Font.Weight = .regular) -> Font {
            .system(size: 16, weight: weight, design: .default)
        }
        static func subheadline(_ weight: Font.Weight = .regular) -> Font {
            .system(size: 15, weight: weight, design: .default)
        }
        static func footnote(_ weight: Font.Weight = .regular) -> Font {
            .system(size: 13, weight: weight, design: .default)
        }
        static func caption(_ weight: Font.Weight = .regular) -> Font {
            .system(size: 11, weight: weight, design: .default)
        }
    }
    
    // MARK: - Surface Colors
    
    enum Surface {
        static let primary = Color(UIColor.systemBackground)
        static let secondary = Color(UIColor.secondarySystemBackground)
        static let tertiary = Color(UIColor.tertiarySystemBackground)
        
        static let glassDark = Color.white.opacity(0.06)
        static let glassLight = Color.white.opacity(0.12)
        static let glassBorder = Color.white.opacity(0.15)
        static let glassBorderLight = Color.white.opacity(0.08)
    }
    
    // MARK: - Text Colors
    
    enum TextColor {
        static let primary = Color(UIColor.label)
        static let secondary = Color(UIColor.secondaryLabel)
        static let tertiary = Color(UIColor.tertiaryLabel)
        static let onAccent = Color.white
    }
    
    // MARK: - Animations
    
    enum Motion {
        static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.8)
        static let smooth = Animation.spring(response: 0.6, dampingFraction: 0.82)
        static let gentle = Animation.spring(response: 0.8, dampingFraction: 0.78)
        static let breathe = Animation.easeInOut(duration: 3.0)
        static let pulse = Animation.easeInOut(duration: 1.0)
        static let orbMorph = Animation.easeInOut(duration: 4.0)
    }
    
    // MARK: - Shadows
    
    enum Shadow {
        static func glow(color: Color, radius: CGFloat = 20) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
        }
        
        static let soft = (color: Color.black.opacity(0.15), radius: CGFloat(16), y: CGFloat(8))
        static let medium = (color: Color.black.opacity(0.25), radius: CGFloat(24), y: CGFloat(12))
    }
    
    // MARK: - Orb Dimensions
    
    enum Orb {
        static let sizeSmall: CGFloat = 100
        static let sizeMedium: CGFloat = 160
        static let sizeLarge: CGFloat = 210
    }
}

// MARK: - Time-of-Day Color Shifts

struct TimeOfDayPalette {
    let isDaytime: Bool
    
    init() {
        let hour = Calendar.current.component(.hour, from: Date())
        self.isDaytime = (6...18).contains(hour)
    }
    
    var orbBase: [Color] {
        if isDaytime {
            return [Color(hex: "FFF7ED"), Color(hex: "FEF3C7"), Color(hex: "FDE68A")]
        } else {
            return [Color(hex: "1E1B4B"), Color(hex: "312E81"), Color(hex: "4338CA")]
        }
    }
    
    var backgroundGradient: LinearGradient {
        if isDaytime {
            return LinearGradient(
                colors: [Color(hex: "FAFAF9"), Color(hex: "F5F5F4")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: "09090B"), Color(hex: "18181B")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var surfaceMaterial: Material {
        isDaytime ? .ultraThinMaterial : .ultraThinMaterial
    }
}

// MARK: - View Extensions

extension View {
    func raahShadow() -> some View {
        self.shadow(
            color: RAAHTheme.Shadow.soft.color,
            radius: RAAHTheme.Shadow.soft.radius,
            x: 0,
            y: RAAHTheme.Shadow.soft.y
        )
    }
    
    func accentGlow(_ color: Color, intensity: CGFloat = 0.3) -> some View {
        self.shadow(color: color.opacity(intensity), radius: 20, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.5), radius: 40, x: 0, y: 0)
    }
}
