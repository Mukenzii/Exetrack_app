import Foundation

/// Speech-to-text through Aisha (space.aisha.group).
///
/// Uses the v1 sync endpoint, which suits short voice notes: the audio goes up
/// and the transcript comes straight back. The v2 endpoint exists for long
/// recordings and returns a task to poll — not needed for a one-line expense.
///
/// Note this sends the recording to Aisha's servers; it is not on-device.
struct AishaSTTService {

    enum Language: String, CaseIterable, Identifiable, Sendable {
        case uz, ru, en

        var id: String { rawValue }

        var shortLabel: String { rawValue.uppercased() }

        /// Best guess from the device language, defaulting to Uzbek.
        static var deviceDefault: Language {
            switch Locale.current.language.languageCode?.identifier {
            case "ru": return .ru
            case "en": return .en
            default:   return .uz
            }
        }
    }

    enum Failure: LocalizedError {
        case missingAPIKey
        case invalidAPIKey
        case badAudio
        case insufficientBalance
        case notAllowed
        case serviceUnavailable
        case unexpectedStatus(Int)
        case emptyTranscript
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No Aisha API key is set up, so voice notes can't be transcribed. Add one to Secrets.xcconfig, or type your expense instead."
            case .invalidAPIKey:
                return "Aisha rejected the API key. Check the value in Secrets.xcconfig."
            case .badAudio:
                return "Aisha couldn't read that recording. Try again, or type it instead."
            case .insufficientBalance:
                return "Your Aisha balance is used up, so the recording couldn't be transcribed."
            case .notAllowed:
                return "Aisha turned down that recording — it may be too long for your plan."
            case .serviceUnavailable:
                return "Aisha's transcription service is temporarily unavailable. Try again shortly."
            case .unexpectedStatus(let code):
                return "Aisha returned an unexpected response (\(code))."
            case .emptyTranscript:
                return "Aisha didn't hear anything in that recording."
            case .network(let why):
                return "Couldn't reach Aisha: \(why)"
            }
        }
    }

    private struct TranscriptResponse: Decodable {
        let id: Int?
        let duration: Double?
        let transcript: String?
    }

    var session: URLSession = .shared

    /// Uploads `fileURL` and returns the transcript.
    func transcribe(fileURL: URL, language: Language) async throws -> String {
        guard let apiKey = Config.Aisha.apiKey else { throw Failure.missingAPIKey }
        guard let url = URL(string: "\(Config.Aisha.baseURL)/api/v1/stt/post/") else {
            throw Failure.network("bad base URL")
        }

        let audio: Data
        do {
            audio = try Data(contentsOf: fileURL)
        } catch {
            throw Failure.badAudio
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(language.rawValue, forHTTPHeaderField: "Accept-Language")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            audio: audio,
            filename: fileURL.lastPathComponent,
            fields: [
                "language": language.rawValue,
                // Diarization needs at least 15s of audio and tells us nothing
                // useful about a one-line expense.
                "has_diarization": "false",
                "has_offset": "false",
                "is_summary": "false",
            ]
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.unexpectedStatus(-1)
        }

        switch http.statusCode {
        case 200, 201:
            break
        case 400:
            throw Failure.badAudio
        case 401:
            throw Failure.invalidAPIKey
        case 403:
            // Duration limits and access problems both land here.
            throw Failure.notAllowed
        case 402:
            throw Failure.insufficientBalance
        case 503:
            throw Failure.serviceUnavailable
        default:
            throw Failure.unexpectedStatus(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(TranscriptResponse.self, from: data) else {
            throw Failure.unexpectedStatus(http.statusCode)
        }
        let transcript = (decoded.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw Failure.emptyTranscript }
        return transcript
    }

    // MARK: - Multipart

    private static func multipartBody(
        boundary: String,
        audio: Data,
        filename: String,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType(for: filename))\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "wav":  return "audio/wav"
        case "mp3":  return "audio/mpeg"
        case "ogg":  return "audio/ogg"
        default:     return "audio/m4a"
        }
    }
}
