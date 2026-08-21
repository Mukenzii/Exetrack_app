import Foundation

enum Config {
    /// Base URL of the optional ExeTrack backend (Telegram card-monitoring and
    /// push). Empty means "not deployed": the app is fully usable without it,
    /// and every feature that needs it stays switched off rather than calling
    /// a host that isn't there.
    static let backendURL = ""

    static var isBackendConfigured: Bool {
        !backendURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Aisha (space.aisha.group) speech-to-text.
    enum Aisha {
        static let baseURL = "https://back.aisha.group"

        /// Read from the app's Info.plist, which is populated from the
        /// `AISHA_API_KEY` build setting in `Secrets.xcconfig`.
        ///
        /// The key is deliberately never checked in — see `Secrets.example.xcconfig`.
        static var apiKey: String? {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: "AishaAPIKey") as? String else {
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unset build setting reaches us as the literal "$(AISHA_API_KEY)".
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
            return trimmed
        }

        static var isConfigured: Bool { apiKey != nil }
    }
}
