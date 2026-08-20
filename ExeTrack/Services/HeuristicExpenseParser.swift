import Foundation

/// Rule-based extractor used when Apple Intelligence isn't available.
///
/// It finds the numbers, expands spoken multipliers, and keeps the surrounding
/// words as the description. Choosing a category is not its job — that belongs
/// to `CategoryClassifier`, which runs on the result either way.
struct HeuristicExpenseParser {

    private static let incomeWords = [
        "salary", "received", "refund", "bonus", "income", "cashback",
        "зарплат", "получил", "возврат", "премия", "доход", "кэшбэк",
        "oylik", "maosh", "qaytar", "daromad",
    ]

    private static let multipliers: [(String, Double)] = [
        ("million", 1_000_000), ("mln", 1_000_000), ("млн", 1_000_000),
        ("ming",    1_000),     ("тыс", 1_000),     ("тысяч", 1_000),
        ("k",       1_000),     ("к",   1_000),
    ]

    func parse(_ text: String) throws -> [ParsedExpense] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseParseError.emptyInput }

        // "Coffee 25 000 and lunch 60 000" is two purchases, and each one's
        // words should stay with its own amount.
        let segments = Self.segments(of: trimmed)

        // Spoken Uzbek gives amounts as words ("yigirma besh ming"), which no
        // digit regex can see, so that text takes the word scanner instead.
        let scan: (String) -> [ParsedExpense] = UzbekLanguage.looksUzbek(trimmed)
            ? Self.spokenExpenses(in:)
            : Self.expenses(in:)

        var results = segments.flatMap(scan)
        if results.isEmpty { results = scan(trimmed) }
        // Last resort: a digit somewhere that the word scanner walked past.
        if results.isEmpty { results = Self.expenses(in: trimmed) }
        guard !results.isEmpty else { throw ExpenseParseError.nothingRecognised }
        return results
    }

    // MARK: - Word scanner (spoken amounts)

    /// Walks the text word by word, collecting runs of number words into
    /// amounts and keeping the surrounding words as the description.
    ///
    /// In Uzbek the merchant normally precedes the amount — "Korzinkadan 45
    /// ming so'mlik non oldim" — so words just before the number are preferred
    /// for the note, with following words used to fill out.
    private static func spokenExpenses(in text: String) -> [ParsedExpense] {
        let tokens = UzbekLanguage.words(text)
        guard !tokens.isEmpty else { return [] }

        var results: [ParsedExpense] = []
        var preceding: [String] = []
        var index = 0

        while index < tokens.count {
            guard Self.startsNumber(tokens[index]) else {
                preceding.append(tokens[index])
                index += 1
                continue
            }

            var end = index
            while end < tokens.count, Self.continuesNumber(tokens[end]) { end += 1 }
            let run = Array(tokens[index..<end])

            guard let amount = UzbekLanguage.value(ofNumberWords: run), amount > 0 else {
                preceding.append(contentsOf: run)
                index = end
                continue
            }

            // Words after the amount, up to whatever starts the next one.
            var following: [String] = []
            var lookahead = end
            while lookahead < tokens.count, !Self.startsNumber(tokens[lookahead]) {
                following.append(tokens[lookahead])
                lookahead += 1
            }

            let note = Self.note(before: preceding, after: following)
            results.append(
                ParsedExpense(
                    amount: amount,
                    note: note,
                    isIncome: Self.looksLikeIncome(text),
                    confidence: note.isEmpty ? 0.45 : 0.7
                )
            )

            preceding = []
            index = end
        }

        return results
    }

    private static func startsNumber(_ token: String) -> Bool {
        UzbekLanguage.isNumberWord(token) || token.allSatisfy(\.isNumber)
    }

    /// Number runs may contain currency words ("ming so'm besh yuz"), which
    /// shouldn't split the amount in two.
    private static func continuesNumber(_ token: String) -> Bool {
        startsNumber(token) || UzbekLanguage.noteFiller.contains(UzbekLanguage.normalise(token))
    }

    /// Builds a short merchant description, stemming so that "Korzinkadan"
    /// and "Korzinkaga" both read — and classify — as "Korzinka".
    private static func note(before: [String], after: [String]) -> String {
        func clean(_ words: [String]) -> [String] {
            words.compactMap { word in
                let stem = UzbekLanguage.displayStem(word)
                guard stem.count >= 2,
                      !UzbekLanguage.noteFiller.contains(UzbekLanguage.stem(word)),
                      !UzbekLanguage.noteFiller.contains(stem),
                      !UzbekLanguage.noteFiller.contains(UzbekLanguage.normalise(word)),
                      !UzbekLanguage.isNumberWord(stem),
                      stem.rangeOfCharacter(from: .decimalDigits) == nil
                else { return nil }
                return stem
            }
        }

        // The two words closest to the amount carry the most meaning.
        let lead = Array(clean(before).suffix(2))
        let trail = clean(after)
        var picked: [String] = []
        for word in lead + trail where !picked.contains(word) {
            picked.append(word)
            if picked.count == 3 { break }
        }
        return picked.joined(separator: " ").capitalizedFirst
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

    private static func expenses(in text: String) -> [ParsedExpense] {
        let matches = amountMatches(in: text)
        guard !matches.isEmpty else { return [] }

        let ns = text as NSString
        var results: [ParsedExpense] = []

        for (index, match) in matches.enumerated() {
            // Each amount owns the words between the previous amount and the next one.
            let start = index == 0 ? 0 : matches[index - 1].range.upperBound
            let end = index == matches.count - 1 ? ns.length : matches[index + 1].range.location
            let context = ns.substring(with: NSRange(location: start, length: max(end - start, 0)))

            let note = self.note(from: context)
            results.append(
                ParsedExpense(
                    amount: match.value,
                    note: note,
                    isIncome: looksLikeIncome(context),
                    // An amount with a description is a firmer reading than a bare number.
                    confidence: note.isEmpty ? 0.45 : 0.7
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
        pattern: #"(\d[\d  .,]*\d|\d)\s*(?:(million|mln|млн|ming|тысяч|тыс|k|к)(?![\p{L}]))?"#,
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

    // MARK: - Note + direction

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
