import Foundation

/// Tracks daily usage for free tier limits.
/// Free tier: 30 min/day voice, 5 Snap & Ask/day.
/// Resets at midnight local time.
@Observable
final class UsageTracker {

    var dailyVoiceSeconds: TimeInterval = 0
    var dailySnapCount: Int = 0
    var isProUser: Bool = true // TODO: revert — testing bypass, all users get unlimited access

    // Limits
    static let freeVoiceLimitSeconds: TimeInterval = 1800 // 30 min
    static let freeSnapLimit: Int = 5
    static let warningThresholdSeconds: TimeInterval = 300 // 5 min remaining

    private var sessionStartTime: Date?
    private var trackingDate: String = ""
    private let defaults = UserDefaults.standard

    init() {
        loadToday()
    }

    // MARK: - Voice Session Tracking

    func startVoiceTracking() {
        sessionStartTime = Date()
    }

    @discardableResult
    func stopVoiceTracking() -> TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        dailyVoiceSeconds += elapsed
        sessionStartTime = nil
        saveToday()
        return elapsed
    }

    /// Current total including live session
    var currentVoiceSeconds: TimeInterval {
        var total = dailyVoiceSeconds
        if let start = sessionStartTime {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    // MARK: - Snap & Ask Tracking

    func recordSnap() {
        dailySnapCount += 1
        saveToday()
    }

    // MARK: - Limit Checks

    var canUseVoice: Bool {
        isProUser || currentVoiceSeconds < Self.freeVoiceLimitSeconds
    }

    var canUseSnap: Bool {
        isProUser || dailySnapCount < Self.freeSnapLimit
    }

    var voiceMinutesRemaining: Int {
        let remaining = max(0, Self.freeVoiceLimitSeconds - currentVoiceSeconds)
        return Int(remaining / 60)
    }

    var shouldWarnVoiceLimit: Bool {
        !isProUser && (Self.freeVoiceLimitSeconds - currentVoiceSeconds) <= Self.warningThresholdSeconds && (Self.freeVoiceLimitSeconds - currentVoiceSeconds) > 0
    }

    var voiceUsageText: String {
        let used = Int(currentVoiceSeconds / 60)
        let limit = Int(Self.freeVoiceLimitSeconds / 60)
        return "\(used)/\(limit) min"
    }

    var snapUsageText: String {
        "\(dailySnapCount)/\(Self.freeSnapLimit)"
    }

    // MARK: - Persistence

    private var todayKey: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    private func loadToday() {
        let key = todayKey
        if trackingDate != key {
            // New day — reset
            trackingDate = key
            dailyVoiceSeconds = defaults.double(forKey: "raah_usage_voice_\(key)")
            dailySnapCount = defaults.integer(forKey: "raah_usage_snap_\(key)")
            // isProUser = defaults.bool(forKey: "raah_is_pro") // TODO: revert — testing bypass
        }
    }

    private func saveToday() {
        let key = todayKey
        if trackingDate != key {
            // Midnight rollover
            trackingDate = key
            dailyVoiceSeconds = 0
            dailySnapCount = 0
        }
        defaults.set(dailyVoiceSeconds, forKey: "raah_usage_voice_\(key)")
        defaults.set(dailySnapCount, forKey: "raah_usage_snap_\(key)")
    }

    func markPro(_ isPro: Bool) {
        isProUser = isPro
        defaults.set(isPro, forKey: "raah_is_pro")
    }
}
