import AVFoundation
import Combine

@Observable
final class AudioSessionManager {

    var isAudioRouteExternal: Bool = false
    var currentRouteName: String = "Speaker"
    var micPermissionGranted: Bool = false

    /// Fires when audio route changes (AirPods connected/disconnected, etc.)
    /// The Bool indicates if a voice-relevant route change happened that needs engine restart.
    var onRouteChanged: (() -> Void)?

    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        setupObservers()
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func requestMicPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermissionGranted = granted
        return granted
    }

    func configureForVoiceChat() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
            .allowBluetooth,        // HFP — AirPods mic + speaker (bidirectional)
            .allowBluetoothA2DP,    // A2DP — high quality output for BT speakers
            .defaultToSpeaker,      // Use speaker (not earpiece) when no BT connected
            .allowAirPlay
        ])
        try session.setActive(true)
        updateRouteInfo()
    }

    func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .allowAirPlay
        ])
        try session.setActive(true)
        updateRouteInfo()
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setupObservers() {
        // Route change: AirPods connected/disconnected, headphones plugged/unplugged
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.updateRouteInfo()

            // Determine if this is a meaningful route change that needs engine restart
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }

            switch changeReason {
            case .newDeviceAvailable,      // AirPods connected
                 .oldDeviceUnavailable,    // AirPods disconnected
                 .override,                // System forced route change
                 .categoryChange:          // Audio category changed
                self.onRouteChanged?()
            default:
                break
            }
        }

        // Audio interruption: phone call, Siri, alarm
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if type == AVAudioSession.InterruptionType.ended.rawValue {
                // Interruption ended (e.g. phone call finished) — restart audio
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.onRouteChanged?()
            }
        }

        updateRouteInfo()
    }

    private func updateRouteInfo() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let output = route.outputs.first

        isAudioRouteExternal = output?.portType != .builtInSpeaker && output?.portType != .builtInReceiver
        currentRouteName = output?.portName ?? "Speaker"
    }
}
