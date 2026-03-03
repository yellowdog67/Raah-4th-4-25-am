import Foundation
import HealthKit

@Observable
final class HealthKitManager {
    
    var currentHeartRate: Double?
    var isAuthorized: Bool = false
    var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    
    private let store = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let typesToRead: Set<HKObjectType> = [heartRateType]
        
        do {
            try await store.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            return true
        } catch {
            print("[HealthKit] Authorization failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func startHeartRateMonitoring() {
        guard isAvailable, isAuthorized else { return }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-60),
            end: nil,
            options: .strictStartDate
        )
        
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }
        
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }
        
        heartRateQuery = query
        store.execute(query)
    }
    
    func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            store.stop(query)
            heartRateQuery = nil
        }
    }
    
    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }
        
        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let value = latest.quantity.doubleValue(for: heartRateUnit)
        
        Task { @MainActor in
            self.currentHeartRate = value
        }
    }
}
