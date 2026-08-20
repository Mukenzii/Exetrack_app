import AVFoundation
import Foundation

/// Records a short voice note and has Aisha turn it into text.
///
/// Recording is local; transcription is a round trip to Aisha's servers, so the
/// flow is record → stop → upload → transcript, rather than live dictation.
@MainActor
final class VoiceCaptureService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    enum Failure: LocalizedError {
        case microphoneDenied
        case recorderFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "ExeTrack needs microphone access to hear your expense. Turn it on in Settings › ExeTrack."
            case .recorderFailed(let why):
                return "Couldn't start recording: \(why)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// Recent microphone levels, 0...1, oldest first. Drives the waveform.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.04, count: barCount)
    /// How long the current recording has been running.
    @Published private(set) var elapsed: TimeInterval = 0
    /// Which language Aisha should transcribe as.
    @Published var language: AishaSTTService.Language = .deviceDefault

    static let barCount = 28
    /// The v1 endpoint is meant for short clips, so stop well before any limit.
    static let maxDuration: TimeInterval = 60

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase != .idle }
    var isConfigured: Bool { Config.Aisha.isConfigured }

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var fileURL: URL?
    private let stt = AishaSTTService()

    // MARK: - Recording

    func start() async throws {
        guard phase == .idle else { return }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { throw Failure.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw Failure.recorderFailed(error.localizedDescription)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("expense-note-\(UUID().uuidString).m4a")

        // 16 kHz mono AAC: plenty for speech, and a small upload.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw Failure.recorderFailed("the recorder refused to start")
            }
            self.recorder = recorder
            self.fileURL = url
        } catch let failure as Failure {
            deactivateSession()
            throw failure
        } catch {
            deactivateSession()
            throw Failure.recorderFailed(error.localizedDescription)
        }

        phase = .recording
        elapsed = 0
        levels = Array(repeating: 0.04, count: Self.barCount)
        startMetering()
    }

    /// Stops recording and returns the transcript from Aisha.
    /// Returns nil if there was nothing recorded.
    func stopAndTranscribe() async throws -> String? {
        guard phase == .recording, let recorder, let fileURL else { return nil }

        stopMetering()
        recorder.stop()
        self.recorder = nil
        deactivateSession()

        phase = .transcribing
        defer {
            phase = .idle
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
        }

        return try await stt.transcribe(fileURL: fileURL, language: language)
    }

    /// Abandons the recording without transcribing.
    func cancel() {
        stopMetering()
        recorder?.stop()
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        deactivateSession()
        phase = .idle
        elapsed = 0
        levels = Array(repeating: 0.04, count: Self.barCount)
    }

    // MARK: - Metering

    private func startMetering() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()

        var next = levels
        next.removeFirst()
        next.append(Self.normalise(recorder.averagePower(forChannel: 0)))
        levels = next

        elapsed = recorder.currentTime
    }

    /// True once the clip has run past what the sync endpoint is meant for.
    /// The view watches this and finishes the recording.
    var hasReachedLimit: Bool { elapsed >= Self.maxDuration }

    /// Maps AVAudioRecorder's dB scale onto something that reads well on bars.
    private static func normalise(_ decibels: Float) -> CGFloat {
        let floorDB: Float = -50
        guard decibels > floorDB else { return 0.04 }
        let normalised = (decibels - floorDB) / -floorDB
        return CGFloat(min(1, max(0.04, pow(normalised, 0.7))))
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
