import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var storeKit = StoreKitManager()

    var body: some View {
        ZStack {
            TimeOfDayPalette().backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: RAAHTheme.Spacing.lg) {
                    header
                    featuresList
                    pricingCards
                    restoreButton
                }
                .padding(.horizontal, RAAHTheme.Spacing.lg)
                .padding(.vertical, RAAHTheme.Spacing.xl)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .padding()
        }
        .onAppear { appState.analytics.log(.paywallShown) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(appState.accentColor)

            Text("RAAH Pro")
                .font(RAAHTheme.Typography.largeTitle())
                .foregroundStyle(.primary)

            Text("Unlimited exploration, no limits")
                .font(RAAHTheme.Typography.subheadline())
                .foregroundStyle(.secondary)
        }
        .padding(.top, RAAHTheme.Spacing.lg)
    }

    // MARK: - Features

    private var featuresList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "mic.fill", text: "Unlimited voice conversations", color: appState.accentColor)
                featureRow(icon: "camera.fill", text: "Unlimited Snap & Ask", color: .orange)
                featureRow(icon: "book.fill", text: "Full exploration journal history", color: .blue)
                featureRow(icon: "bolt.fill", text: "Priority response times", color: .yellow)
                featureRow(icon: "figure.walk", text: "Walk Me Home — unlimited", color: .green)
            }
        }
    }

    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28)

            Text(text)
                .font(RAAHTheme.Typography.body())
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Pricing

    private var pricingCards: some View {
        VStack(spacing: 12) {
            if let yearly = storeKit.yearlyProduct {
                pricingButton(
                    product: yearly,
                    label: "Yearly",
                    sublabel: "Save 36%",
                    isRecommended: true
                )
            } else {
                pricingButton(
                    label: "Yearly — $99.99/year",
                    sublabel: "Save 36%",
                    isRecommended: true
                ) {
                    // Fallback when products not loaded from App Store
                }
            }

            if let monthly = storeKit.monthlyProduct {
                pricingButton(
                    product: monthly,
                    label: "Monthly",
                    sublabel: nil,
                    isRecommended: false
                )
            } else {
                pricingButton(
                    label: "Monthly — $12.99/month",
                    sublabel: nil,
                    isRecommended: false
                ) {
                    // Fallback
                }
            }
        }
    }

    private func pricingButton(
        product: Product,
        label: String,
        sublabel: String?,
        isRecommended: Bool
    ) -> some View {
        Button {
            purchase(product)
        } label: {
            pricingContent(
                label: "\(label) — \(product.displayPrice)/\(product.subscription?.subscriptionPeriod.unit == .year ? "year" : "month")",
                sublabel: sublabel,
                isRecommended: isRecommended
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    private func pricingButton(
        label: String,
        sublabel: String?,
        isRecommended: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            pricingContent(label: label, sublabel: sublabel, isRecommended: isRecommended)
        }
        .buttonStyle(.plain)
    }

    private func pricingContent(label: String, sublabel: String?, isRecommended: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(RAAHTheme.Typography.headline())
                    .foregroundStyle(isRecommended ? .white : .primary)
                if let sublabel {
                    Text(sublabel)
                        .font(RAAHTheme.Typography.caption(.medium))
                        .foregroundStyle(isRecommended ? .white.opacity(0.8) : .secondary)
                }
            }
            Spacer()
            if isPurchasing {
                ProgressView()
                    .tint(isRecommended ? .white : appState.accentColor)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isRecommended ? Color.white.opacity(0.7) : Color.secondary.opacity(0.5))
            }
        }
        .padding(RAAHTheme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: RAAHTheme.Radius.lg, style: .continuous)
                .fill(isRecommended ? AnyShapeStyle(appState.accentColor.gradient) : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay {
            if !isRecommended {
                RoundedRectangle(cornerRadius: RAAHTheme.Radius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            }
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await storeKit.restorePurchases()
                if storeKit.isPro {
                    appState.usageTracker.markPro(true)
                    dismiss()
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(RAAHTheme.Typography.subheadline(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func purchase(_ product: Product) {
        isPurchasing = true
        Task {
            let success = await storeKit.purchase(product)
            isPurchasing = false
            if success {
                appState.analytics.log(.paywallConverted, properties: ["product": product.id])
                appState.usageTracker.markPro(true)
                dismiss()
            }
        }
    }
}
