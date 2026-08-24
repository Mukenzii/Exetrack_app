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

    /// OpenAI, used to place expenses into the user's own categories.
    enum OpenAI {
        static let baseURL = "https://api.openai.com"

        /// Categorising is a constrained choice — the response schema already
        /// limits the answer to the user's own categories — so the smallest
        /// model is usually enough and costs a fraction of the alternatives.
        ///
        /// Uzbek is a lower-resource language, though, so if merchants start
        /// landing in the wrong place, set OPENAI_MODEL to gpt-5-mini and
        /// measure with tools/compare-models.py.
        static var model: String {
            value(forKey: "OpenAIModel") ?? "gpt-5-nano"
        }

        /// Read from Info.plist, populated by the `OPENAI_API_KEY` build
        /// setting in `Secrets.xcconfig`. Never checked in.
        static var apiKey: String? { value(forKey: "OpenAIAPIKey") }

        static var isConfigured: Bool { apiKey != nil }
    }

    /// Reads an Info.plist string, treating an unset build setting as absent.
    private static func value(forKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
