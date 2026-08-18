import Foundation

/// Rule-based parser used when Apple Intelligence isn't available.
///
/// It is deliberately simple: find the numbers, expand spoken multipliers, then
/// match nearby words against a keyword table. Good enough that the screen is
/// never a dead end, and it keeps the simulator and older devices usable.
struct HeuristicExpenseParser {

    let categories: [String]

    // Keyword table keyed by the app's default category names. Latin and
    // Cyrillic spellings sit side by side because people mix languages here.
    private static let keywords: [String: [String]] = [
        "Groceries":        ["grocer", "supermarket", "korzinka", "makro", "havas", "продукт", "магазин", "oziq"],
        "Restaurants":      ["restaurant", "cafe", "lunch", "dinner", "breakfast", "ресторан", "кафе", "обед", "ужин", "restoran", "kafe", "tushlik"],
        "Food delivery":    ["delivery", "express24", "wolt", "glovo", "доставка", "yetkaz"],
        "Coffee":           ["coffee", "latte", "cappuccino", "espresso", "кофе", "qahva", "kofe"],
        "Public transport": ["metro", "bus", "tram", "метро", "автобус", "avtobus"],
        "Car":              ["parking", "car wash", "парковк", "мойка", "avtoturargoh"],
        "Fuel":             ["fuel", "petrol", "gasoline", "бензин", "заправк", "benzin", "yoqilg"],
        "Taxi":             ["taxi", "uber", "yandex go", "bolt", "такси", "taksi"],
        "Utilities":        ["utilit", "electric", "water bill", "коммунал", "свет", "вода", "kommunal"],
        "Rent":             ["rent", "аренда", "квартплат", "ijara"],
        "Internet":         ["internet", "wifi", "mobile", "интернет", "связь", "aloqa", "tarif"],
        "Health":           ["doctor", "clinic", "hospital", "dentist", "врач", "клиник", "больниц", "shifokor"],
        "Gym":              ["gym", "fitness", "workout", "зал", "фитнес", "sportzal"],
        "Pharmacy":         ["pharmac", "drugstore", "аптек", "dorixona"],
        "Entertainment":    ["cinema", "movie", "concert", "game", "кино", "концерт", "игр", "kino"],
        "Subscriptions":    ["subscription", "netflix", "spotify", "youtube", "icloud", "подписк", "obuna"],
        "Travel":           ["travel", "flight", "hotel", "ticket", "путешеств", "билет", "отел", "sayohat"],
        "Shopping":         ["shopping", "clothes", "shoes", "одежд", "обув", "покупк", "kiyim"],
        "Electronics":      ["electronic", "phone", "laptop", "headphone", "техник", "телефон", "ноутбук", "texnika"],
        "Salary":           ["salary", "payroll", "зарплат", "oylik", "maosh"],
        "Freelance":        ["freelance", "upwork", "фриланс"],
        "Investment":       ["investment", "dividend", "инвестиц", "dividend"],
        "Gift":             ["gift", "present", "подарок", "sovg"],
    ]

    private static let incomeWords = [
        "salary", "received", "refund", "bonus", "income", "paid me", "cashback",
        "зарплат", "получил", "возврат", "премия", "доход", "кэшбэк",
        "oylik", "maosh", "qaytar", "daromad",
    ]

    private static let multipliers: [(String, Double)] = [
        ("million", 1_000_000), ("mln", 1_000_000), ("млн", 1_000_000), ("mln.", 1_000_000),
        ("ming",    1_000),     ("тыс", 1_000),     ("тысяч", 1_000),   ("k", 1_000), ("к", 1_000),
    ]

    func parse(_ text: String) throws -> [ParsedExpense] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseParseError.emptyInput }

        // "Coffee 25 000 and lunch 60 000" is two purchases, and each one's
        // words should stay with its own amount.
        var results = Self.segments(of: trimmed).flatMap { expenses(in: $0) }
        if results.isEmpty { results = expenses(in: trimmed) }
        guard !results.isEmpty else { throw ExpenseParseError.nothingRecognised }
        return results
    }

    /// Breaks the note on spoken conjunctions. Commas are left alone because
    /// they show up inside numbers like "1,5 mln".
    private static let conjunctionRegex = try! NSRegularExpression(
        pattern: #"(?:\band\b|\bи\b|\bva\b|\bplus\b|;)"#,
        options: [.caseInsensitive]
    )

    private static func segments(of text: String) -> [String] {
        let ns = text as NSString
        var parts: [String] = []
        var cursor = 0
        for m in conjunctionRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            cursor = m.range.upperBound
        }
        parts.append(ns.substring(from: cursor))
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func expenses(in text: String) -> [ParsedExpense] {
        let matches = Self.amountMatches(in: text)
        guard !matches.isEmpty else { return [] }

        let ns = text as NSString
        var results: [ParsedExpense] = []

        for (index, match) in matches.enumerated() {
            // Each amount owns the words between the previous amount and the next one.
            let start = index == 0 ? 0 : matches[index - 1].range.upperBound
            let end = index == matches.count - 1 ? ns.length : matches[index + 1].range.location
            let context = ns.substring(with: NSRange(location: start, length: max(end - start, 0)))

            let category = Self.category(for: context, allowed: categories)
            results.append(
                ParsedExpense(
                    amount: match.value,
                    categoryName: category ?? "",
                    note: Self.note(from: context),
                    isIncome: Self.looksLikeIncome(context),
                    // A keyword hit is a decent guess; a bare number is not.
                    confidence: category == nil ? 0.35 : 0.7
                )
            )
        }

        return results
    }

    // MARK: - Amounts

    private struct AmountMatch {
        let value: Double
        let range: NSRange
    }

    /// Matches a number (optionally with space/dot/comma separators) plus an
    /// optional multiplier word: "45 000", "45k", "1,5 mln", "300 ming".
    /// The lookahead keeps "25 000 kg" from reading as 25 million, while
    /// still letting the bare number through.
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(\d[\d  .,]*\d|\d)\s*(?:(million|mln|млн|ming|тысяч|тыс|k|к)(?![\p{L}]))?"#,
        options: [.caseInsensitive]
    )

    private static func amountMatches(in text: String) -> [AmountMatch] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        return amountRegex.matches(in: text, range: full).compactMap { m in
            let digits = ns.substring(with: m.range(at: 1))
            guard var value = normalisedNumber(digits) else { return nil }

            if m.range(at: 2).location != NSNotFound {
                let suffix = ns.substring(with: m.range(at: 2)).lowercased()
                if let mult = multipliers.first(where: { $0.0 == suffix })?.1 {
                    value *= mult
                }
            }
            guard value > 0 else { return nil }
            return AmountMatch(value: value, range: m.range)
        }
    }

    /// Turns "45 000", "1.011,00" or "45,5" into a Double, working out whether a
    /// lone separator is grouping or decimal from how many digits follow it.
    static func normalisedNumber(_ raw: String) -> Double? {
        var s = raw.replacingOccurrences(of: " ", with: "")
                   .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }

        let lastDot = s.lastIndex(of: ".")
        let lastComma = s.lastIndex(of: ",")

        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            // Both present — whichever comes last is the decimal separator.
            if dot > comma {
                s = s.replacingOccurrences(of: ",", with: "")
            } else {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        case let (dot?, nil):
            s = isGrouping(s, at: dot) ? s.replacingOccurrences(of: ".", with: "") : s
        case let (nil, comma?):
            s = isGrouping(s, at: comma)
                ? s.replacingOccurrences(of: ",", with: "")
                : s.replacingOccurrences(of: ",", with: ".")
        case (nil, nil):
            break
        }

        return Double(s)
    }

    /// Exactly three trailing digits after the separator means it grouped thousands.
    private static func isGrouping(_ s: String, at index: String.Index) -> Bool {
        let after = s.distance(from: s.index(after: index), to: s.endIndex)
        let before = s.distance(from: s.startIndex, to: index)
        return after == 3 && before > 0
    }

    // MARK: - Category + note

    private static func category(for context: String, allowed: [String]) -> String? {
        let haystack = context.lowercased()

        // A category the user actually has, named outright, always wins.
        if let direct = allowed.first(where: { haystack.contains($0.lowercased()) }) {
            return direct
        }

        for (name, words) in keywords where allowed.contains(name) {
            if words.contains(where: { haystack.contains($0) }) { return name }
        }
        return nil
    }

    private static func looksLikeIncome(_ context: String) -> Bool {
        let haystack = context.lowercased()
        return incomeWords.contains { haystack.contains($0) }
    }

    /// Strips digits and filler words to leave something usable as a note.
    private static func note(from context: String) -> String {
        let filler: Set<String> = [
            "on", "for", "at", "the", "a", "an", "spent", "paid", "bought", "and", "plus",
            "и", "на", "за", "в", "по", "uchun", "va",
            "sum", "sums", "so'm", "som", "сум", "сўм", "uzs",
            // Multiplier words belong to the amount, not the description.
            "k", "к", "ming", "mln", "million", "тыс", "тысяч", "млн",
        ]
        let words = context
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                guard !word.isEmpty, word.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
                return !filler.contains(word.lowercased())
            }
        return words.prefix(3).joined(separator: " ").capitalizedFirst
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
