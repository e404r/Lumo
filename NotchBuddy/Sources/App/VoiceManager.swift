import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - VoiceManager
// Native macOS Speech Recognition & Dictation for Lumo.
// Uses Apple's Speech framework and AVAudioEngine for real-time, low-latency voice command processing.

@MainActor
final class VoiceManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate, @unchecked Sendable {
    static let shared = VoiceManager()

    @Published var isRecording: Bool = false
    @Published var recognizedText: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var isAuthorized: Bool = false
    @Published var statusDescription: String = "Ready"

    @Published var ttsEnabled: Bool = UserDefaults.standard.bool(forKey: "voice_tts_enabled") {
        didSet {
            UserDefaults.standard.set(ttsEnabled, forKey: "voice_tts_enabled")
        }
    }

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var speechSynthesizer = AVSpeechSynthesizer()
    private var silenceTimer: Timer?
    private var onTextUpdateHandler: ((String) -> Void)?
    private var onFinishedHandler: ((String) -> Void)?

    override private init() {
        super.init()
        setupRecognizer()
        checkPermissions()
    }

    // MARK: - Setup & Permissions

    private func setupRecognizer() {
        if let rec = SFSpeechRecognizer(locale: Locale.current), rec.isAvailable {
            speechRecognizer = rec
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        speechRecognizer?.delegate = self
    }

    // Non-isolated helper so TCC block invocations from background threads don't trigger MainActor assertions
    nonisolated private static func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // Non-isolated helper for microphone access request
    nonisolated private static func requestMicrophoneAuth() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func requestPermissions() {
        Task {
            let speechStatus = await Self.requestSpeechAuth()
            guard speechStatus == .authorized else {
                self.isAuthorized = false
                self.statusDescription = "Speech recognition permission denied"
                return
            }

            let micGranted = await Self.requestMicrophoneAuth()
            self.isAuthorized = micGranted
            if micGranted {
                self.statusDescription = "Ready for voice commands"
            } else {
                self.statusDescription = "Microphone permission denied"
            }
        }
    }

    private func checkPermissions() {
        let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.isAuthorized = speechAuth && micAuth
    }

    // MARK: - Non-isolated Background Bridges
    // CoreAudio and SFSpeech call blocks on background realtime threads.
    // Making these methods nonisolated static prevents the Swift compiler from injecting MainActor dispatch assertions.

    nonisolated private static func installAudioTap(
        on node: AVAudioNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(frames, 1)))
            let normalized = min(max(rms * 12, 0), 1)

            onLevel(normalized)
        }
    }

    nonisolated private static func createRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onResult(result, error)
        }
    }

    // MARK: - Recording & Speech Recognition

    func toggleRecording(onUpdate: ((String) -> Void)? = nil, onFinished: ((String) -> Void)? = nil) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(onUpdate: onUpdate, onFinished: onFinished)
        }
    }

    func startRecording(onUpdate: ((String) -> Void)? = nil, onFinished: ((String) -> Void)? = nil) {
        guard !isRecording else { return }

        // Ensure authorized
        if !isAuthorized {
            requestPermissions()
            statusDescription = "Granting permissions…"
            return
        }

        // Cancel previous task if any
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        self.onTextUpdateHandler = onUpdate
        self.onFinishedHandler = onFinished
        self.recognizedText = ""
        self.audioLevel = 0.0

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        guard let recognizer = speechRecognizer else {
            statusDescription = "Speech recognizer unavailable"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(macOS 10.15, *) {
            if recognizer.supportsOnDeviceRecognition {
                req.requiresOnDeviceRecognition = false
            }
        }
        self.recognitionRequest = req

        self.recognitionTask = Self.createRecognitionTask(recognizer: recognizer, request: req) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil

            Task { @MainActor in
                let manager = VoiceManager.shared
                guard manager.isRecording else { return }

                if let text = text {
                    manager.recognizedText = text
                    manager.onTextUpdateHandler?(text)
                    manager.resetSilenceTimer()

                    if isFinal {
                        manager.finishRecording()
                    }
                }

                if hasError {
                    manager.finishRecording()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            statusDescription = "Audio input format unavailable"
            finishRecording()
            return
        }

        Self.installAudioTap(on: inputNode, format: recordingFormat, request: req) { level in
            Task { @MainActor in
                VoiceManager.shared.audioLevel = level
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            statusDescription = "Listening…"
            SoundEngine.shared.play("peek")
        } catch {
            statusDescription = "Audio Engine error: \(error.localizedDescription)"
            finishRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil

        finishRecording()
    }

    private func finishRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        isRecording = false
        audioLevel = 0.0
        statusDescription = "Ready"

        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onFinishedHandler?(text)
        }
        onTextUpdateHandler = nil
        onFinishedHandler = nil
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        // Auto-finish after 2.0s of silence if speech was recognized
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording, !self.recognizedText.isEmpty else { return }
                self.finishRecording()
            }
        }
    }

    // MARK: - Text-To-Speech (TTS)

    func speak(_ text: String) {
        guard ttsEnabled else { return }

        stopSpeaking()

        let cleaned = cleanTextForSpeech(text)
        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = Float(AppState.shared.soundVolume) * 5.0

        if let voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US") {
            utterance.voice = voice
        }

        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func cleanTextForSpeech(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " (code omitted) ", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "[#*]", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
