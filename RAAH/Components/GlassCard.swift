import SwiftUI

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content
    let padding: CGFloat
    let cornerRadius: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        padding: CGFloat = RAAHTheme.Spacing.md,
        cornerRadius: CGFloat = RAAHTheme.Radius.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(padding)
            .background {
                FrostedGlassBackground(cornerRadius: cornerRadius, tint: .clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(icon: String, size: CGFloat = 48, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Pill Button

struct GlassPillButton: View {
    let title: String
    let icon: String?
    let accentColor: Color
    let isActive: Bool
    let action: () -> Void
    
    init(
        _ title: String,
        icon: String? = nil,
        accentColor: Color = .white,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.isActive = isActive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(RAAHTheme.Typography.subheadline(.medium))
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(isActive ? AnyShapeStyle(accentColor) : AnyShapeStyle(.ultraThinMaterial))
            }
            .overlay {
                if !isActive {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Toggle Row

struct GlassToggleRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    @Binding var isOn: Bool
    
    init(_ title: String, subtitle: String? = nil, icon: String, iconColor: Color = .primary, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RAAHTheme.Typography.body(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(RAAHTheme.Typography.caption())
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(iconColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Glass Navigation Row

struct GlassNavRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let action: () -> Void
    
    init(_ title: String, subtitle: String? = nil, icon: String, iconColor: Color = .primary, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(RAAHTheme.Typography.body(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
