import AVFoundation
import Foundation
import Speech

/// Records from the microphone and transcribes live, preferring on-device
/// recognition so spoken money talk doesn't leave the phone.
@MainActor
final class VoiceCaptureService: ObservableObject {

    enum Failure: LocalizedError {
        case microphoneDenied
        case speechDenied
        case recognizerUnavailable
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "ExeTrack needs microphone access to hear your expense. Turn it on in Settings › ExeTrack."
            case .speechDenied:
                return "ExeTrack needs speech recognition to turn your voice into text. Turn it on in Settings › ExeTrack."
            case .recognizerUnavailable:
                return "Speech recognition isn't available for your language right now. You can still type it."
            case .engineFailed(let why):
                return why
            }
        }
    }

    /// Live text as the user speaks — partial results included.
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    /// Recent microphone levels, 0...1, oldest first. Drives the waveform.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.04, count: barCount)

    static let barCount = 28

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Whether this device can transcribe the user's language at all.
    /// Resolved once — building an `SFSpeechRecognizer` is not free.
    let isAvailable: Bool

    init() {
        isAvailable = SFSpeechRecognizer(locale: Self.preferredLocale)?.isAvailable ?? false
    }

    /// The device language when we can transcribe it, else US English.
    private static var preferredLocale: Locale {
        let current = Locale.current
        if let r = SFSpeechRecognizer(locale: current), r.isAvailable { return current }
        return Locale(identifier: "en_US")
    }

    // MARK: - Permissions

    private func authorize() async throws {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { throw Failure.speechDenied }

        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard mic else { throw Failure.microphoneDenied }
    }

    // MARK: - Recording

    func start() async throws {
        guard !isRecording else { return }
        try await authorize()

        let recognizer = SFSpeechRecognizer(locale: Self.preferredLocale)
        guard let recognizer, recognizer.isAvailable else { throw Failure.recognizerUnavailable }
        self.recognizer = recognizer

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw Failure.engineFailed("Couldn't start the microphone: \(error.localizedDescription)")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep the audio on the device when the OS can manage it.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        transcript = ""
        levels = Array(repeating: 0.04, count: Self.barCount)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.rms(of: buffer)
            Task { @MainActor [weak self] in self?.push(level: level) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanUp()
            throw Failure.engineFailed("Couldn't start the microphone: \(error.localizedDescription)")
        }

        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    /// Stops recording and leaves `transcript` holding whatever was heard.
    func stop() {
        guard isRecording || engine.isRunning else { return }
        isRecording = false
        cleanUp()
    }

    func reset() {
        stop()
        transcript = ""
    }

    private func cleanUp() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        levels = Array(repeating: 0.04, count: Self.barCount)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Level metering

    private func push(level: CGFloat) {
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
    }

    /// Root-mean-square of the buffer mapped onto a 0...1 range that looks
    /// reasonable on a bar meter.
    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0.04 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0.04 }

        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))

        // −50 dB floor, then a gentle curve so quiet speech still moves the bars.
        let db = 20 * log10(max(rms, 0.000_01))
        let normalised = max(0, (db + 50) / 50)
        return CGFloat(min(1, pow(normalised, 0.7)))
    }
}
