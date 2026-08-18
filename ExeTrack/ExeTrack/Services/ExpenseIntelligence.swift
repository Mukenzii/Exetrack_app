import Foundation
import FoundationModels

// MARK: - Plain parse result (no Core Data, safe to cross actors)

/// One expense the parser believes it found in the user's text.
struct ParsedExpense: Identifiable, Sendable {
    let id = UUID()
    var amount: Double
    var categoryName: String
    var note: String
    var isIncome: Bool
    var confidence: Double
}

/// Why the parser could not produce anything, phrased for the UI.
enum ExpenseParseError: LocalizedError {
    case emptyInput
    case nothingRecognised
    case modelUnavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Say or type what you spent first."
        case .nothingRecognised:
            return "I couldn't find an amount in that. Try something like “45 000 groceries at Korzinka”."
        case .modelUnavailable(let why):
            return why
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

    @Guide(description: "The single best matching category, copied exactly from the provided list.")
    var category: String

    @Guide(description: "A short merchant or description, at most three words, in the user's own language.")
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

/// Turns free-form text into expense drafts, preferring Apple's on-device model
/// and falling back to a rule parser when Apple Intelligence isn't available.
///
/// Nothing here touches the network — the text never leaves the device.
struct ExpenseIntelligence {

    let categories: [String]

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
        You turn short spoken or typed notes about money into structured expense entries.

        Rules:
        - Choose the category from the provided list only, copying the name exactly.
        - amount is a positive number with no separators or currency symbols.
        - Expand spoken multipliers: "k", "ming" and "тыс" mean thousand; "mln" and "млн" mean million.
        - note is a short merchant or description of at most three words, kept in the user's own language.
        - Return one entry per distinct purchase when several are mentioned.
        - isIncome is true only for money received.
        - Never invent an amount that was not stated.
        """
    }

    func parse(_ text: String) async throws -> [ParsedExpense] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseParseError.emptyInput }

        guard case .onDevice = Self.status else {
            return try HeuristicExpenseParser(categories: categories).parse(trimmed)
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            Available categories: \(categories.joined(separator: ", "))

            Note from the user: "\(trimmed)"
            """
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedExpenseList.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let parsed = response.content.expenses
                .filter { $0.amount > 0 }
                .map {
                    ParsedExpense(
                        amount: $0.amount,
                        categoryName: $0.category,
                        note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines),
                        isIncome: $0.isIncome,
                        confidence: min(max($0.confidence, 0), 1)
                    )
                }
            // The model occasionally returns an empty list for terse input —
            // the rule parser usually still finds the number.
            guard !parsed.isEmpty else {
                return try HeuristicExpenseParser(categories: categories).parse(trimmed)
            }
            return parsed
        } catch is ExpenseParseError {
            throw ExpenseParseError.nothingRecognised
        } catch {
            // Guardrails, context overflow, or the model going away mid-request:
            // degrade to the rule parser rather than dead-ending the user.
            return try HeuristicExpenseParser(categories: categories).parse(trimmed)
        }
    }
}
