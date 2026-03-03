import Foundation
import AVFoundation
import Combine

/// Manages a WebSocket connection to OpenAI's Realtime API for full-duplex voice conversation.
@Observable
final class OpenAIRealtimeService: NSObject {

    // MARK: - Public State

    var isConnected: Bool = false
    var voiceState: VoiceState = .idle
    var lastTranscript: String = ""
    var lastResponse: String = ""
    var error: String?

    // MARK: - Callbacks

    var onTranscriptUpdate: ((String) -> Void)?
    var onResponseUpdate: ((String) -> Void)?
    var onToolCall: ((String, String, [String: Any]) -> Void)?
    var onSessionCreated: (() -> Void)?
    var onResponseComplete: ((String) -> Void)?

    // MARK: - Private

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var currentSystemPrompt: String = ""
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    private var idleTimer: Task<Void, Never>?
    private let idlePauseDelay: TimeInterval = 10
    private var thinkingTimer: Task<Void, Never>?

    // --- Audio Capture (mic → OpenAI) ---
    private let captureEngine = AVAudioEngine()
    private var inputConverter: AVAudioConverter?
    /// True while AI is speaking — suppresses mic input to prevent echo feedback
    private var suppressMicInput = false

    // --- Audio Playback (OpenAI → speaker) ---
    private let playbackEngine = AVAudioEngine()
    private let playbackPlayer = AVAudioPlayerNode()
    /// EQ node used purely as a gain stage — no bands, just globalGain boost
    private let playbackBoost = AVAudioUnitEQ(numberOfBands: 0)
    private var playbackSetup = false
    private var hardwareSampleRate: Double = 48000
    private var hardwareChannels: Int = 1

    /// Tracks response_id to detect new responses and clear stale text
    private var currentResponseId: String = ""

    private let model = "gpt-realtime-mini"
    var voice: String = "ash"
    private var isConnecting = false

    /// OpenAI Realtime API audio format: 24 kHz, mono, PCM 16-bit
    private static let apiSampleRate: Double = 24000

    // MARK: - Connection

    func connect(systemPrompt: String) {
        guard !isConnected, !isConnecting else { return }

        guard APIKeys.isOpenAIConfigured else {
            error = "OpenAI API key not configured"
            voiceState = .error("Add your OpenAI API key in Settings")
            return
        }

        isConnecting = true
        currentSystemPrompt = systemPrompt
        reconnectAttempts = 0
        shouldReconnect = true
        connectInternal()
    }

    func disconnect() {
        shouldReconnect = false
        cleanupConnection()
        voiceState = .idle
    }

    private func connectInternal() {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(APIKeys.openAI)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessages()
    }

    private func cleanupConnection() {
        thinkingTimer?.cancel()
        thinkingTimer = nil
        idleTimer?.cancel()
        idleTimer = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        stopAudioCapture()
        teardownPlayback()
        isConnected = false
        isConnecting = false
        suppressMicInput = false
        currentResponseId = ""
    }

    private func handleUnexpectedDisconnect() {
        cleanupConnection()

        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
            if shouldReconnect {
                voiceState = .error("Connection lost. Tap to retry.")
            }
            shouldReconnect = false
            return
        }

        reconnectAttempts += 1
        voiceState = .reconnecting

        isConnecting = true
        let delay = pow(2.0, Double(reconnectAttempts - 1))
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard shouldReconnect else { return }
            connectInternal()
        }
    }

    // MARK: - Session Configuration

    func updateSystemPrompt(_ prompt: String) {
        currentSystemPrompt = prompt
        guard isConnected else { return }

        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "instructions": prompt,
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ],
                "tools": toolDefinitions
            ]
        ]

        sendJSON(sessionUpdate)
    }

    // MARK: - Audio Capture (Mic)

    func startAudioCapture() {
        do {
            let inputNode = captureEngine.inputNode
            let micFormat = inputNode.outputFormat(forBus: 0)

            guard micFormat.channelCount > 0, micFormat.sampleRate > 0 else {
                voiceState = .error("Mic not available. Restart the app.")
                return
            }

            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Self.apiSampleRate,
                channels: 1,
                interleaved: true
            )!

            inputConverter = AVAudioConverter(from: micFormat, to: targetFormat)

            inputNode.installTap(onBus: 0, bufferSize: 2400, format: micFormat) { [weak self] buffer, _ in
                guard let self else { return }
                // ECHO PREVENTION: don't send mic audio while AI is speaking
                guard !self.suppressMicInput else { return }
                guard let converter = self.inputConverter else { return }
                self.processInputBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }

            captureEngine.prepare()
            try captureEngine.start()
            voiceState = .listening
            startIdleTimer()
        } catch {
            self.error = "Audio capture failed: \(error.localizedDescription)"
            voiceState = .error("Mic unavailable. Check permissions.")
        }
    }

    func stopAudioCapture() {
        cancelIdleTimer()
        if captureEngine.isRunning {
            captureEngine.inputNode.removeTap(onBus: 0)
            captureEngine.stop()
        }
        suppressMicInput = false
        if voiceState == .listening || voiceState == .paused {
            voiceState = .idle
        }
    }

    func pauseAudioCapture() {
        guard captureEngine.isRunning else { return }
        captureEngine.inputNode.removeTap(onBus: 0)
        captureEngine.stop()
        sendJSON(["type": "input_audio_buffer.clear"])
        voiceState = .paused
    }

    func resumeAudioCapture() {
        guard isConnected, voiceState == .paused else { return }
        startAudioCapture()
        startIdleTimer()
    }

    /// Restart both audio engines after a route change (AirPods connected/disconnected).
    /// Tears down and rebuilds so new hardware formats are picked up.
    func handleAudioRouteChange() {
        guard isConnected else { return }

        let wasListening = captureEngine.isRunning
        let wasSpeaking = voiceState == .speaking

        // Tear down capture
        if captureEngine.isRunning {
            captureEngine.inputNode.removeTap(onBus: 0)
            captureEngine.stop()
        }
        inputConverter = nil

        // Tear down playback — must fully reset to pick up new hardware format
        playbackPlayer.stop()
        if playbackEngine.isRunning {
            playbackEngine.stop()
        }
        // Detach and re-attach so the connection uses the new format
        if playbackSetup {
            playbackEngine.disconnectNodeOutput(playbackPlayer)
            playbackEngine.detach(playbackPlayer)
        }
        playbackSetup = false

        // Small delay for the audio session to settle after route change
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run {
                // Restart capture if it was running
                if wasListening || wasSpeaking {
                    self.startAudioCapture()
                }
                // Playback will auto-setup on next audio chunk via setupPlaybackIfNeeded()
            }
        }
    }

    // MARK: - Audio Playback (Speaker)
    // No AVAudioConverter — manual int16→float32 + sample rate conversion.
    // AVAudioConverter accumulates state between calls and corrupts output on small chunks.

    private func setupPlaybackIfNeeded() {
        guard !playbackSetup else { return }
        playbackSetup = true

        playbackEngine.attach(playbackPlayer)
        playbackEngine.attach(playbackBoost)

        // +20 dB hardware-level gain — applied before system volume, survives voiceChat AGC
        playbackBoost.globalGain = 20.0

        // Use the hardware's native format — never force a foreign format
        let hwFormat = playbackEngine.mainMixerNode.outputFormat(forBus: 0)
        hardwareSampleRate = hwFormat.sampleRate
        hardwareChannels = max(1, Int(hwFormat.channelCount))

        // player → boost → mixer
        playbackEngine.connect(playbackPlayer, to: playbackBoost, format: hwFormat)
        playbackEngine.connect(playbackBoost, to: playbackEngine.mainMixerNode, format: hwFormat)

        do {
            playbackEngine.prepare()
            try playbackEngine.start()
            playbackPlayer.play()
        } catch {
            print("[RealtimeAPI] Playback engine failed: \(error)")
            self.error = "Audio playback failed"
        }
    }

    private func teardownPlayback() {
        playbackPlayer.stop()
        if playbackEngine.isRunning {
            playbackEngine.stop()
        }
        playbackSetup = false
    }

    /// Convert 24kHz int16 mono → hardware format (usually 48kHz float32 stereo)
    /// Done manually to avoid AVAudioConverter state corruption on small streaming chunks.
    private func playAudioData(_ data: Data) {
        setupPlaybackIfNeeded()

        let hwFormat = playbackEngine.mainMixerNode.outputFormat(forBus: 0)
        let apiFrameCount = data.count / 2 // 2 bytes per int16 sample
        guard apiFrameCount > 0 else { return }

        let ratio = hardwareSampleRate / Self.apiSampleRate
        let hwFrameCount = Int(Double(apiFrameCount) * ratio)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: hwFormat, frameCapacity: AVAudioFrameCount(hwFrameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(hwFrameCount)

        data.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            let srcCount = int16Ptr.count

            for ch in 0..<hardwareChannels {
                guard let channelData = buffer.floatChannelData?[ch] else { continue }
                for i in 0..<hwFrameCount {
                    let srcIndex = min(Int(Double(i) / ratio), srcCount - 1)
                    channelData[i] = Float(int16Ptr[srcIndex]) / 32768.0
                }
            }
        }

        // Restart playback engine if it stopped
        if !playbackEngine.isRunning {
            do {
                try playbackEngine.start()
                playbackPlayer.play()
            } catch {
                print("[RealtimeAPI] Playback restart failed: \(error)")
                return
            }
        }

        playbackPlayer.scheduleBuffer(buffer)
    }

    // MARK: - Timers

    private func startIdleTimer() {
        cancelIdleTimer()
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.idlePauseDelay ?? 10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.voiceState == .idle || self.voiceState == .listening else { return }
                self.pauseAudioCapture()
            }
        }
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    private func startThinkingTimeout() {
        thinkingTimer?.cancel()
        thinkingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.voiceState == .thinking else { return }
                self.voiceState = .idle
                self.suppressMicInput = false
                self.startIdleTimer()
            }
        }
    }

    private func cancelThinkingTimeout() {
        thinkingTimer?.cancel()
        thinkingTimer = nil
    }

    // MARK: - Audio Processing (Mic → API)

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return }

        let channelData = convertedBuffer.int16ChannelData![0]
        let data = Data(bytes: channelData, count: Int(convertedBuffer.frameLength) * 2)

        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
    }

    // MARK: - Message Handling

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleServerEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleServerEvent(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()

            case .failure(let error):
                print("[RealtimeAPI] WebSocket receive error: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.handleUnexpectedDisconnect()
                }
            }
        }
    }

    private func handleServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "session.created":
                isConnected = true
                isConnecting = false
                reconnectAttempts = 0
                updateSystemPrompt(currentSystemPrompt)
                onSessionCreated?()

            case "input_audio_buffer.speech_started":
                cancelIdleTimer()
                cancelThinkingTimeout()
                voiceState = .listening

            case "input_audio_buffer.speech_stopped":
                voiceState = .thinking
                startThinkingTimeout()

            case "conversation.item.input_audio_transcription.completed":
                if let transcript = json["transcript"] as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.lastTranscript = transcript
                        self?.onTranscriptUpdate?(transcript)
                    }
                }

            case "response.audio.delta":
                cancelThinkingTimeout()
                // Mute mic while AI speaks — prevents echo from retriggering VAD
                suppressMicInput = true
                voiceState = .speaking
                if let audioDelta = json["delta"] as? String,
                   let audioData = Data(base64Encoded: audioDelta) {
                    playAudioData(audioData)
                }

            case "response.audio_transcript.delta":
                if let delta = json["delta"] as? String {
                    let responseId = json["response_id"] as? String ?? ""
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if responseId != self.currentResponseId {
                            self.currentResponseId = responseId
                            self.lastResponse = ""
                        }
                        self.lastResponse += delta
                        self.onResponseUpdate?(self.lastResponse)
                    }
                }

            case "response.audio_transcript.done":
                // Don't overwrite — the streamed deltas match what the user heard.
                // Whisper's corrected transcript can differ, causing visible text jumps.
                break

            case "response.done":
                cancelThinkingTimeout()
                suppressMicInput = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.voiceState = .idle
                    if !self.lastResponse.isEmpty {
                        self.onResponseComplete?(self.lastResponse)
                    }
                }
                startIdleTimer()

            case "response.cancelled":
                cancelThinkingTimeout()
                suppressMicInput = false
                voiceState = .idle
                startIdleTimer()

            case "response.function_call_arguments.done":
                cancelThinkingTimeout()
                suppressMicInput = false
                voiceState = .idle
                handleToolCallResponse(json)
                startIdleTimer()

            case "error":
                cancelThinkingTimeout()
                suppressMicInput = false
                isConnecting = false
                if let errorInfo = json["error"] as? [String: Any],
                   let message = errorInfo["message"] as? String {
                    error = message
                    voiceState = .error(message)
                } else {
                    voiceState = .error("Unknown API error")
                }

            default:
                break
            }
        }
    }

    // MARK: - Tool Calls

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "type": "function",
                "name": "check_safety_score",
                "description": "Check the safety score of the user's current location",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "latitude": ["type": "number"],
                        "longitude": ["type": "number"]
                    ],
                    "required": ["latitude", "longitude"]
                ]
            ],
            [
                "type": "function",
                "name": "find_tickets",
                "description": "Search for skip-the-line tickets for a museum or landmark when the user expresses interest in visiting",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "place_name": ["type": "string"],
                        "latitude": ["type": "number"],
                        "longitude": ["type": "number"]
                    ],
                    "required": ["place_name"]
                ]
            ],
            [
                "type": "function",
                "name": "activate_walk_me_home",
                "description": "Activate Walk Me Home mode when the user says 'walk me home', 'I feel unsafe', 'can you stay with me', or similar safety-related requests. Enables check-ins every 3 minutes and shares location with emergency contact.",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "type": "function",
                "name": "deactivate_walk_me_home",
                "description": "Deactivate Walk Me Home mode when the user says 'I'm home', 'I made it', 'I'm safe now', or similar. Only call this when Walk Me Home is currently active.",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "type": "function",
                "name": "share_live_location",
                "description": "Send an SOS SMS to the user's emergency contact with their current location and address. CALL THIS IMMEDIATELY — without asking — when the user says anything like 'I feel unsafe', 'I'm scared', 'something doesn't feel right', 'I need help', 'this is dangerous', 'I'm being followed', or any expression of fear or threat.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "reason": ["type": "string"]
                    ]
                ]
            ],
            [
                "type": "function",
                "name": "get_directions",
                "description": "Start turn-by-turn navigation to a destination. Returns ONLY the first direction — the system will feed you each subsequent step as the user walks. NEVER give your own directions.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "destination_name": [
                            "type": "string",
                            "description": "Name of the destination, e.g. 'India Gate' or 'Basilica of Bom Jesus'"
                        ],
                        "destination_lat": [
                            "type": "number",
                            "description": "Latitude of the destination"
                        ],
                        "destination_lon": [
                            "type": "number",
                            "description": "Longitude of the destination"
                        ]
                    ],
                    "required": ["destination_name", "destination_lat", "destination_lon"]
                ]
            ],
            [
                "type": "function",
                "name": "search_local_knowledge",
                "description": "Search the web for local recommendations, hidden gems, or niche finds. Use when the user asks for 'best X', 'hidden gem', 'local favorite', food recommendations by cuisine, or anything not answered by the nearby POI list.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The search query, e.g. 'best samosa', 'hidden gem cafe', 'local craft beer'"
                        ],
                        "location_name": [
                            "type": "string",
                            "description": "The city or area name for geo-context, e.g. 'Goa' or 'South Delhi'"
                        ]
                    ],
                    "required": ["query", "location_name"]
                ]
            ]
        ]
    }

    private func handleToolCallResponse(_ json: [String: Any]) {
        guard let callId = json["call_id"] as? String,
              let name = json["name"] as? String,
              let argsString = json["arguments"] as? String,
              let argsData = argsString.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else { return }

        onToolCall?(name, callId, args)
    }

    func sendToolResult(callId: String, result: String) {
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": result
            ]
        ])
        sendJSON(["type": "response.create"])
    }

    // MARK: - Utility

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(string)) { error in
            if let error {
                print("[RealtimeAPI] Send error: \(error.localizedDescription)")
            }
        }
    }

    /// Trigger a response without adding a conversation item.
    /// Pass `instructions` to tell the model exactly what to say for this response.
    /// No conversation item created — zero accumulation.
    func requestResponse(instructions: String? = nil) {
        if let instructions {
            sendJSON([
                "type": "response.create",
                "response": [
                    "instructions": instructions
                ]
            ])
        } else {
            sendJSON(["type": "response.create"])
        }
    }

    func sendTextMessage(_ text: String) {
        if voiceState == .paused {
            resumeAudioCapture()
        }
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text]
                ]
            ]
        ])
        sendJSON(["type": "response.create"])
    }
}

// MARK: - URLSessionWebSocketDelegate

extension OpenAIRealtimeService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // isConnected is set on "session.created" event, not here.
        // Setting it here creates a race where code tries to send
        // messages before the session is configured.
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            handleUnexpectedDisconnect()
        }
    }
}
