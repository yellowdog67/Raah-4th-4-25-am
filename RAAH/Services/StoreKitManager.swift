import Foundation
import StoreKit

/// Manages RAAH Pro subscriptions via StoreKit 2.
@Observable
final class StoreKitManager {

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading: Bool = false
    var error: String?

    static let monthlyID = "com.raah.pro.monthly"
    static let yearlyID = "com.raah.pro.yearly"

    var isPro: Bool {
        !purchasedProductIDs.isEmpty
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyID }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyID }
    }

    private var updateListenerTask: Task<Void, Never>?

    init() {
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await updatePurchasedProducts() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        await MainActor.run { isLoading = true }
        do {
            let storeProducts = try await Product.products(for: [Self.monthlyID, Self.yearlyID])
            await MainActor.run {
                products = storeProducts.sorted { $0.price < $1.price }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to load products: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                return true

            case .userCancelled:
                return false

            case .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
            await MainActor.run {
                self.error = "Purchase failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        await updatePurchasedProducts()
    }

    // MARK: - Transaction Updates

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await self?.updatePurchasedProducts()
                    await transaction.finish()
                }
            }
        }
    }

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }

        await MainActor.run {
            purchasedProductIDs = purchased
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
