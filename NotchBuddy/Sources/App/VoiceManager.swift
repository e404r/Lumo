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
        // Try current locale, fallback to en-US
        if let rec = SFSpeechRecognizer(locale: Locale.current), rec.isAvailable {
            speechRecognizer = rec
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        speechRecognizer?.delegate = self
    }

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    self?.requestMicrophoneAccess()
                default:
                    self?.isAuthorized = false
                    self?.statusDescription = "Speech recognition permission denied"
                }
            }
        }
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.isAuthorized = granted
                if !granted {
                    self?.statusDescription = "Microphone permission denied"
                } else {
                    self?.statusDescription = "Ready for voice commands"
                }
            }
        }
    }

    private func checkPermissions() {
        let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.isAuthorized = speechAuth && micAuth
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
            return
        }

        // Cancel previous task if any
        recognitionTask?.cancel()
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        self.onTextUpdateHandler = onUpdate
        self.onFinishedHandler = onFinished
        self.recognizedText = ""
        self.audioLevel = 0.0

        let inputNode = audioEngine.inputNode

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            statusDescription = "Unable to create recognition request"
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        if #available(macOS 10.15, *) {
            // Prefer on-device recognition if available for speed and privacy
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                recognitionRequest.requiresOnDeviceRecognition = false
            }
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.recognizedText = text
                    self.onTextUpdateHandler?(text)
                    self.resetSilenceTimer()

                    if result.isFinal {
                        self.finishRecording()
                    }
                }

                if error != nil {
                    self.finishRecording()
                }
            }
        }

        // Install audio tap for live transcription and audio level metering
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate RMS audio level for waveform visualization
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(frames, 1)))
            let normalized = min(max(rms * 12, 0), 1)

            Task { @MainActor in
                self?.audioLevel = normalized
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
            stopRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil

        finishRecording()
    }

    private func finishRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

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

        // Clean code blocks before reading
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
        // Strip markdown code fences ```...```
        var result = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " (code omitted) ", options: .regularExpression)
        // Strip backticks `...`
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Strip excessive asterisks / hashes
        result = result.replacingOccurrences(of: "[#*]", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
