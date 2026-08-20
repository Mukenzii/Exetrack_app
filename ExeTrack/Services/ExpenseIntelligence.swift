import Foundation
import FoundationModels

// MARK: - Plain parse result (no Core Data, safe to cross actors)

/// One expense found in the user's note.
///
/// Deliberately carries no category: extracting *what was spent* and deciding
/// *where it belongs* are separate jobs. `CategoryClassifier` does the second,
/// using the user's own history rather than a model's guess.
struct ParsedExpense: Identifiable, Sendable {
    let id = UUID()
    var amount: Double
    var note: String
    var isIncome: Bool
    /// How sure the extractor was about the amount and description, 0...1.
    var confidence: Double
}

/// Why the parser could not produce anything, phrased for the UI.
enum ExpenseParseError: LocalizedError {
    case emptyInput
    case nothingRecognised
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Say or type what you spent first."
        case .nothingRecognised:
            return "I couldn't find an amount in that. Try something like “45 000 groceries at Korzinka”."
        case .failed(let why):
            return why
        }
    }
}

// MARK: - Generable schema handed to the on-device model

@Generable
struct GeneratedExpenseList {
    @Guide(description: "One entry for every separate purchase mentioned. Usually exactly one.")
    var expenses: [GeneratedExpense]
}

@Generable
struct GeneratedExpense {
    @Guide(description: "The amount as a plain positive number, no spaces or currency symbols.")
    var amount: Double

    @Guide(description: "The merchant or a short description, at most three words, in the user's own language.")
    var note: String

    @Guide(description: "True only when this is money received, such as salary, a refund or a gift.")
    var isIncome: Bool

    @Guide(description: "How confident this reading is, from 0.0 to 1.0.")
    var confidence: Double
}

// MARK: - Availability

enum ExpenseAIStatus {
    /// Apple's on-device model is ready.
    case onDevice
    /// Falling back to the built-in rule parser, with a reason worth surfacing once.
    case ruleBased(reason: String)

    var usesAppleIntelligence: Bool {
        if case .onDevice = self { return true }
        return false
    }
}

// MARK: - Facade

/// Pulls amounts and merchants out of free-form text, preferring Apple's
/// on-device model and falling back to a rule parser when it isn't available.
///
/// Nothing here touches the network — the text never leaves the device.
struct ExpenseIntelligence {

    static var status: ExpenseAIStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .onDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            return .ruleBased(reason: "Apple Intelligence is off, so ExeTrack is reading your text with its built-in parser.")
        case .unavailable(.deviceNotEligible):
            return .ruleBased(reason: "This device doesn't support Apple Intelligence, so ExeTrack is using its built-in parser.")
        case .unavailable(.modelNotReady):
            return .ruleBased(reason: "The on-device model is still downloading. Using the built-in parser for now.")
        @unknown default:
            return .ruleBased(reason: "Using ExeTrack's built-in parser.")
        }
    }

    private var instructions: String {
        """
        You pull spending details out of short spoken or typed notes.

        Rules:
        - amount is a positive number with no separators or currency symbols.
        - Expand spoken multipliers: "k", "ming" and "тыс" mean thousand; "mln" and "млн" mean million.
        - note is the merchant or a short description of at most three words, kept in the user's own language.
        - Return one entry per distinct purchase when several are mentioned.
        - isIncome is true only for money received.
        - Never invent an amount that was not stated.
        - Do not categorise anything; only report what was spent and where.
        """
    }

    /// Whether Apple's model can read this text at all.
    ///
    /// It supports 23 locales and Uzbek is not among them — `supportsLocale`
    /// returns false and generation fails with `unsupportedLanguageOrLocale`.
    /// Detecting that up front beats attempting the call and silently landing
    /// in the fallback.
    static func handlesLanguage(of text: String) -> Bool {
        if UzbekLanguage.looksUzbek(text) { return false }
        return SystemLanguageModel.default.supportsLocale(Locale.current)
            || SystemLanguageModel.default.supportsLocale(Locale(identifier: "en_US"))
    }

    func parse(_ text: String) async throws -> [ParsedExpense] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseParseError.emptyInput }

        guard case .onDevice = Self.status, Self.handlesLanguage(of: trimmed) else {
            return try HeuristicExpenseParser().parse(trimmed)
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Note from the user: \"\(trimmed)\"",
                generating: GeneratedExpenseList.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let parsed = response.content.expenses
                .filter { $0.amount > 0 }
                .map {
                    ParsedExpense(
                        amount: $0.amount,
                        note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines),
                        isIncome: $0.isIncome,
                        confidence: min(max($0.confidence, 0), 1)
                    )
                }
            // The model occasionally returns an empty list for terse input —
            // the rule parser usually still finds the number.
            guard !parsed.isEmpty else {
                return try HeuristicExpenseParser().parse(trimmed)
            }
            return parsed
        } catch {
            // Guardrails, context overflow, or the model going away mid-request:
            // degrade to the rule parser rather than dead-ending the user.
            return try HeuristicExpenseParser().parse(trimmed)
        }
    }
}
