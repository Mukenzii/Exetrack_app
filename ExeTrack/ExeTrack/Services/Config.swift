import Foundation

enum Config {
    static let backendURL = "https://battery-delivers-tobacco-sometimes.trycloudflare.com"

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
