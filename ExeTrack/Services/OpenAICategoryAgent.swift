import Foundation

/// Decides which of the user's own categories an expense belongs to, by asking
/// an OpenAI model.
///
/// The category list is passed as a JSON Schema `enum`, so the model is
/// structurally unable to answer with anything that is not already one of the
/// user's categories — no invented names, no fuzzy matching afterwards.
///
/// Built for Uzbek: notes arrive in Latin or Cyrillic Uzbek, usually mixed with
/// Russian, naming local merchants. The prompt says so explicitly, and a sample
/// of the user's own past filings is included so the model follows their habits
/// rather than generic assumptions.
struct OpenAICategoryAgent {

    /// One expense to place.
    struct Item {
        let note: String
        let amount: Double
    }

    /// Where the model put it.
    struct Suggestion {
        let index: Int
        /// Empty when the model declined — see `proposedCategory`.
        let category: String
        let confidence: Double
        /// Runner-up categories, offered as one-tap corrections.
        let alternatives: [String]
        /// When nothing fitted, the category the user should create, so the
        /// screen can offer to make it rather than just shrugging.
        let proposedCategory: ProposedCategory?
    }

    struct ProposedCategory {
        let name: String
        let icon: String
    }

    /// Sent in the enum alongside the real categories so the model has a way
    /// to say "none of these". Without it the schema forces a choice, and a
    /// debt gets filed as Shopping because that is the least-bad option the
    /// model is permitted to give.
    static let declineValue = "__none_fit__"

    /// SF Symbols the model may propose for a new category. An enum, so it
    /// cannot invent a name that renders as a blank square.
    static let proposableIcons = [
        "arrow.left.arrow.right", "banknote.fill", "creditcard.fill", "tag.fill",
        "cart.fill", "fork.knife", "car.fill", "house.fill", "heart.fill",
        "gift.fill", "bag.fill", "airplane", "gamecontroller.fill", "briefcase.fill",
        "wifi", "bolt.fill", "book.fill", "pawprint.fill", "graduationcap.fill",
        "wrench.and.screwdriver.fill", "figure.and.child.holdinghands", "cross.case.fill",
    ]

    /// A category the user has chosen before, used as a worked example.
    struct PastChoice {
        let note: String
        let category: String
    }

    enum Failure: LocalizedError {
        case missingAPIKey
        case invalidAPIKey
        case rateLimited
        case quotaExhausted
        case serverUnavailable
        case unexpectedStatus(Int)
        case badResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No OpenAI API key is set, so categories can't be suggested. Add OPENAI_API_KEY to Secrets.xcconfig, or pick the category yourself."
            case .invalidAPIKey:
                return "OpenAI rejected the API key. Check OPENAI_API_KEY in Secrets.xcconfig."
            case .rateLimited:
                return "OpenAI is rate limiting the app. Try again in a moment."
            case .quotaExhausted:
                return "The OpenAI account is out of quota, so categories can't be suggested right now."
            case .serverUnavailable:
                return "OpenAI is temporarily unavailable. Pick the category yourself for now."
            case .unexpectedStatus(let code):
                return "OpenAI returned an unexpected response (\(code))."
            case .badResponse:
                return "Couldn't read OpenAI's answer."
            case .network(let why):
                return "Couldn't reach OpenAI: \(why)"
            }
        }
    }

    var session: URLSession = .shared

    // MARK: - Prompt

    private static let systemPrompt = """
    You file personal expenses for a user in Uzbekistan into their own categories.

    About the input:
    - Notes are in Uzbek, written in Latin or Cyrillic, and often mixed with Russian or English.
    - Uzbek is agglutinative, so a merchant carries case endings: "Korzinkadan", \
    "Korzinkaga" and "Korzinkada" are all the shop Korzinka.
    - The currency is the so'm. Amounts of tens or hundreds of thousands are ordinary.
    - Local merchants: Korzinka, Makro, Havas, Bek Market, magazin, bozor (shops \
    selling food); Evos, Maxway, Oqtepa Lavash, choyxona, oshxona, kafe (places you \
    eat); Express24, Chopar (delivery services); Yandex Go, MyTaxi (taxi); Uzum, \
    Texnomart (electronics and marketplace); Beeline, Ucell, Mobiuz, Uzmobile \
    (mobile operators); Payme, Click, Humo, Uzcard (payment apps); UzGasTrade and \
    filling stations (fuel); dorixona (pharmacy); shifoxona, klinika (health).

    Distinctions that are easy to get wrong:
    - Eating at or collecting from a place — choyxona, kafe, Evos, osh, tushlik, \
    lavash, somsa — is eating out. Only treat it as delivery when the note names a \
    delivery service or says the food was brought to them.
    - Topping up a mobile operator is connectivity, not a household utility. \
    Household utilities are electricity, gas and water for the home.
    - A shop selling food or ingredients — magazin, bozor, masalliq, non, go'sht — \
    is groceries. Shopping is for clothes, shoes and household goods.

    Rules:
    - Choose only from the categories provided. Never invent one.
    - If none of them genuinely fits, answer "__none_fit__" rather than forcing a
    poor match, and use proposed_category to name the category the user should
    create for it — a short, ordinary name in the same language and style as their
    existing ones, with a fitting icon. Leave proposed_category blank whenever you
    did pick a real category. Money lent or borrowed (qarz, qarz berdim, qarz oldim), a transfer
    between the person's own cards or accounts (o'tkazma, perevod), repaying a
    loan, and savings put aside are the usual cases — none of those is spending on
    goods, so unless the list has a category meant for them — "Debt", "Savings",
    "Loan received" or similar — decline. Leaving it
    for the user to choose is better than a confident wrong answer.
    - If several fit, choose the one the user's own past choices point to.
    - confidence is 0.0 to 1.0. Be honest: use a low value when the note is vague \
    or the merchant is unfamiliar, so the user knows to check.
    - Return exactly one result per input item, matching its index.
    - alternatives holds up to three other categories that could plausibly fit,     best first. Leave it empty when the choice is obvious.
    """

    // MARK: - Request

    /// Places every item in one round trip.
    ///
    /// `categories` must already be filtered to the right income/expense side —
    /// a refund should never be offered "Groceries".
    func classify(
        items: [Item],
        categories: [String],
        pastChoices: [PastChoice]
    ) async throws -> [Suggestion] {
        guard !items.isEmpty, !categories.isEmpty else { return [] }
        guard let apiKey = Config.OpenAI.apiKey else { throw Failure.missingAPIKey }
        guard let url = URL(string: "\(Config.OpenAI.baseURL)/v1/chat/completions") else {
            throw Failure.network("bad base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // No `temperature`: the gpt-5 family rejects any explicit value with a
        // 400, and the enum schema already leaves almost nothing to sample.
        var body: [String: Any] = [
            "model": Config.OpenAI.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": Self.userMessage(items: items, pastChoices: pastChoices)],
            ],
            "response_format": Self.responseFormat(categories: categories),
        ]

        // The gpt-5 family reasons before answering, and left uncapped it spends
        // a large hidden budget doing it — forty seconds and seven times the
        // cost for what is a one-line classification.
        if Config.OpenAI.model.hasPrefix("gpt-5") {
            body["reasoning_effort"] = Config.OpenAI.reasoningEffort
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw Failure.invalidAPIKey
        case 429:
            // OpenAI uses 429 both for rate limits and for a spent quota.
            let text = String(data: data, encoding: .utf8) ?? ""
            throw text.contains("insufficient_quota") ? Failure.quotaExhausted : Failure.rateLimited
        case 500...599:
            throw Failure.serverUnavailable
        default:
            throw Failure.unexpectedStatus(http.statusCode)
        }

        return try Self.decode(data, allowed: Set(categories))
    }

    /// A JSON Schema whose `category` field is an enum of exactly the user's
    /// categories — the model cannot return anything else.
    private static func responseFormat(categories: [String]) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "category_assignment",
                "strict": true,
                "schema": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["results"],
                    "properties": [
                        "results": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "additionalProperties": false,
                                "required": ["index", "category", "confidence", "alternatives",
                                             "proposed_category", "proposed_icon"],
                                "properties": [
                                    "index": ["type": "integer"],
                                    "category": ["type": "string", "enum": categories + [declineValue]],
                                    "confidence": ["type": "number"],
                                    // Also enum-constrained, so a correction
                                    // chip can only ever be a real category.
                                    "alternatives": [
                                        "type": "array",
                                        "items": ["type": "string", "enum": categories],
                                    ],
                                    "proposed_category": ["type": "string"],
                                    "proposed_icon": ["type": "string", "enum": proposableIcons],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func userMessage(items: [Item], pastChoices: [PastChoice]) -> String {
        var message = ""
        if !pastChoices.isEmpty {
            message += "How this user has filed things before:\n"
            for choice in pastChoices {
                message += "- \"\(choice.note)\" → \(choice.category)\n"
            }
            message += "\n"
        }
        message += "Place each of these:\n"
        for (index, item) in items.enumerated() {
            let amount = Theme.amount(item.amount)
            let note = item.note.isEmpty ? "(no description)" : item.note
            message += "\(index). \"\(note)\" — \(amount) so'm\n"
        }
        return message
    }

    // MARK: - Response

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct Payload: Decodable {
        struct Result: Decodable {
            let index: Int
            let category: String
            let confidence: Double
            let alternatives: [String]
            let proposed_category: String
            let proposed_icon: String
        }
        let results: [Result]
    }

    private static func decode(_ data: Data, allowed: Set<String>) throws -> [Suggestion] {
        guard let envelope = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = envelope.choices.first?.message.content,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(content.utf8))
        else { throw Failure.badResponse }

        // The schema already constrains this, but a category the user deleted
        // mid-request would still be nonsense to apply.
        return payload.results.map { result in
            let matched = allowed.contains(result.category)
            let proposal = result.proposed_category.trimmingCharacters(in: .whitespacesAndNewlines)
            return Suggestion(
                index: result.index,
                category: matched ? result.category : "",
                confidence: matched ? min(max(result.confidence, 0), 1) : 0,
                alternatives: result.alternatives
                    .filter { allowed.contains($0) && $0 != result.category }
                    .prefix(3)
                    .map { $0 },
                // Only meaningful when nothing matched; ignore a stray proposal
                // that arrives alongside a real answer.
                proposedCategory: (matched || proposal.isEmpty)
                    ? nil
                    : ProposedCategory(name: proposal, icon: result.proposed_icon)
            )
        }
    }
}
