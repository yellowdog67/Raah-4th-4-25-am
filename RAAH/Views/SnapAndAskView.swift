import SwiftUI
import AVFoundation

struct SnapAndAskView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var capturedImage: UIImage?
    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: String?
    @State private var showingCamera: Bool = true
    @State private var customPrompt: String = ""
    @State private var showingAskMore: Bool = false
    @State private var cameraController = CameraController()
    @State private var cameraReady = false
    @State private var cameraDenied = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if showingCamera && capturedImage == nil {
                cameraView
            } else if let image = capturedImage {
                resultView(image: image)
            }
            
            // Top bar
            VStack {
                topBar
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startCamera() }
        .onDisappear { cameraController.stop() }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button {
                HapticEngine.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            
            Spacer()
            
            Text("Snap & Ask")
                .font(RAAHTheme.Typography.headline())
            
            Spacer()
            
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, RAAHTheme.Spacing.lg)
        .padding(.top, RAAHTheme.Spacing.sm)
    }
    
    // MARK: - Camera View

    private var cameraView: some View {
        ZStack {
            if cameraReady {
                CameraPreviewView(session: cameraController.session)
                    .ignoresSafeArea()
            } else if cameraDenied {
                VStack(spacing: RAAHTheme.Spacing.lg) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Camera access denied")
                        .font(RAAHTheme.Typography.headline())
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(RAAHTheme.Typography.subheadline(.medium))
                    .foregroundStyle(appState.accentColor)
                }
            } else {
                VStack(spacing: RAAHTheme.Spacing.lg) {
                    Image(systemName: "camera")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Starting camera...")
                        .font(RAAHTheme.Typography.subheadline())
                        .foregroundStyle(.secondary)
                }
            }

            // Overlay: instruction + capture button
            VStack {
                Spacer()

                VStack(spacing: RAAHTheme.Spacing.md) {
                    Text("Point at something you're curious about")
                        .font(RAAHTheme.Typography.subheadline(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 4)

                    Button {
                        HapticEngine.heavy()
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 80, height: 80)

                            Circle()
                                .fill(.white)
                                .frame(width: 66, height: 66)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, RAAHTheme.Spacing.xxl)
            }
        }
    }
    
    // MARK: - Result View
    
    private func resultView(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: RAAHTheme.Spacing.lg) {
                // Captured image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: RAAHTheme.Radius.lg, style: .continuous))
                    .padding(.top, 60)
                
                if isAnalyzing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(appState.accentColor)
                        Text("Analyzing...")
                            .font(RAAHTheme.Typography.subheadline(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, RAAHTheme.Spacing.xl)
                } else if let result = analysisResult {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(appState.accentColor)
                                Text("RAAH says")
                                    .font(RAAHTheme.Typography.caption(.semibold))
                                    .foregroundStyle(appState.accentColor)
                            }
                            
                            Text(result)
                                .font(RAAHTheme.Typography.body())
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, RAAHTheme.Spacing.lg)
                    
                    // Speak it
                    GlassPillButton("Hear this aloud", icon: "speaker.wave.2.fill", accentColor: appState.accentColor, isActive: true) {
                        HapticEngine.light()
                        speakResult(result)
                    }
                }

                // Ask more: text field + send
                if showingAskMore {
                    HStack(spacing: 10) {
                        TextField("Ask something about this...", text: $customPrompt)
                            .font(RAAHTheme.Typography.body())
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: RAAHTheme.Radius.md, style: .continuous).fill(.ultraThinMaterial))

                        Button {
                            HapticEngine.medium()
                            guard !customPrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            analyzeImage(prompt: customPrompt)
                            customPrompt = ""
                            showingAskMore = false
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(appState.accentColor)
                        }
                    }
                    .padding(.horizontal, RAAHTheme.Spacing.lg)
                }

                // Action buttons
                HStack(spacing: 16) {
                    GlassPillButton("Retake", icon: "camera.fill") {
                        capturedImage = nil
                        analysisResult = nil
                        showingCamera = true
                        showingAskMore = false
                        startCamera()
                    }

                    if analysisResult != nil {
                        GlassPillButton("Ask more", icon: "text.bubble.fill") {
                            HapticEngine.light()
                            showingAskMore.toggle()
                        }
                    }
                }
                .padding(.top, RAAHTheme.Spacing.sm)
            }
            .padding(.bottom, RAAHTheme.Spacing.xxl)
        }
    }
    
    // MARK: - Actions
    
    private func startCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraController.setup()
            cameraReady = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        cameraController.setup()
                        cameraReady = true
                    } else {
                        cameraDenied = true
                    }
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func capturePhoto() {
        cameraController.capturePhoto { image in
            Task { @MainActor in
                if let image {
                    capturedImage = image
                    showingCamera = false
                    cameraController.stop()
                    analyzeImage()
                }
            }
        }
    }
    
    private func analyzeImage(prompt: String? = nil) {
        guard let image = capturedImage else { return }

        // Check snap limit
        guard appState.usageTracker.canUseSnap else {
            analysisResult = "Daily Snap & Ask limit reached. Upgrade to RAAH Pro for unlimited use."
            return
        }

        isAnalyzing = true
        analysisResult = nil

        Task {
            let vision = OpenAIVisionService()
            do {
                let effectivePrompt = prompt ?? "What is this? Provide a concise, informative description suitable for a curious traveler. Include historical or cultural context if relevant."
                let result = try await vision.analyzeImage(image, prompt: effectivePrompt)
                appState.usageTracker.recordSnap()
                appState.analytics.log(.snapUsed)
                analysisResult = result.description
            } catch {
                analysisResult = "Couldn't analyze this image: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }

    @State private var speechSynthesizer = AVSpeechSynthesizer()

    private func speakResult(_ text: String) {
        // Prefer voice session if active, otherwise use on-device TTS
        if appState.realtimeService.isConnected {
            appState.realtimeService.sendTextMessage("Say this aloud naturally: \(text)")
        } else {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            speechSynthesizer.speak(utterance)
        }
    }
}

// MARK: - Camera Controller

final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private var isConfigured = false

    func setup() {
        guard !isConfigured else {
            // Already configured — just restart the session
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                if !session.isRunning { session.startRunning() }
            }
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        isConfigured = true

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard session.isRunning else {
            completion(nil)
            return
        }
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.captureCompletion?(nil) }
            return
        }
        DispatchQueue.main.async { self.captureCompletion?(image) }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
