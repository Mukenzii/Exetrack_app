import Foundation

/// Picks the category for an expense using a scoring ensemble rather than a
/// language model, so the result is deterministic, instant, and offline.
///
/// Four signals are blended:
///
/// 1. **Nearest past note** — token overlap against the user's own history.
///    "Korzinka" lands in Groceries because that is where they always put it.
/// 2. **Naive Bayes** — per-token likelihood learned from that same history,
///    which generalises beyond exact repeats.
/// 3. **Keyword table** — a built-in en/ru/uz dictionary, so a brand new
///    install still classifies sensibly with no history at all.
/// 4. **Category name match** — for when the user simply says the category.
///
/// Because the history is the user's saved transactions, every correction they
/// make on the review screen becomes training data for the next note.
struct CategoryClassifier {

    struct Example {
        let note: String
        let categoryName: String
    }

    struct Candidate: Identifiable {
        let name: String
        /// 0...1. Blends how far ahead this category is from the runner-up
        /// with how much evidence there was at all.
        let confidence: Double
        var id: String { name }
    }

    /// Categories the result must come from — already filtered to the right
    /// income/expense side by the caller.
    let categories: [String]
    let history: [Example]

    // Relative trust in each signal. History outranks the dictionary because
    // the user's own habits beat our guesses about them.
    private static let wNearest = 0.42
    private static let wBayes   = 0.24
    private static let wKeyword = 0.26
    private static let wName    = 0.08

    // MARK: - Public

    /// All plausible categories, best first. Empty when nothing scored.
    func rank(_ text: String) -> [Candidate] {
        let tokens = Self.tokenise(text)
        guard !tokens.isEmpty, !categories.isEmpty else { return [] }

        let byCategory = Dictionary(grouping: history) { $0.categoryName }
        let bayes = bayesScores(tokens: tokens, byCategory: byCategory)

        var scored: [(String, Double)] = categories.map { category in
            let examples = byCategory[category] ?? []
            let score =
                Self.wNearest * nearestNoteScore(tokens: tokens, examples: examples)
                + Self.wBayes * (bayes[category] ?? 0)
                + Self.wKeyword * Self.keywordScore(tokens: tokens, category: category)
                + Self.wName * Self.nameScore(tokens: tokens, category: category)
            return (category, score)
        }
        scored.sort { $0.1 > $1.1 }

        let positives = scored.filter { $0.1 > 0.001 }
        guard let topScore = positives.first?.1 else { return [] }

        let total = positives.reduce(0) { $0 + $1.1 }
        let runnerUp = positives.dropFirst().first?.1 ?? 0
        let lead = topScore > 0 ? (topScore - runnerUp) / topScore : 0

        return positives.prefix(4).map { name, score in
            // Share of the total says "how much better than the alternatives",
            // evidence says "was there enough signal to trust any of this",
            // and lead rewards a clear winner over a near tie.
            let share = total > 0 ? score / total : 0
            let evidence = min(1, score / 0.35)
            let confidence = score == topScore
                ? min(1, 0.45 * share + 0.35 * evidence + 0.20 * lead)
                : min(1, 0.5 * share + 0.5 * evidence)
            return Candidate(name: name, confidence: confidence)
        }
    }

    func best(_ text: String) -> Candidate? { rank(text).first }

    // MARK: - Signal 1: nearest past note

    /// Highest token-overlap (Jaccard, with a bonus for full containment)
    /// between the new note and any note already filed under this category.
    private func nearestNoteScore(tokens: Set<String>, examples: [Example]) -> Double {
        var best = 0.0
        for example in examples {
            let other = Self.tokenise(example.note)
            guard !other.isEmpty else { continue }
            let shared = tokens.intersection(other).count
            guard shared > 0 else { continue }

            let union = tokens.union(other).count
            var score = Double(shared) / Double(union)
            // "korzinka" matching a past note of exactly "korzinka" should be
            // near-certain even when the new note carries extra words.
            if other.isSubset(of: tokens) || tokens.isSubset(of: other) {
                score = max(score, 0.85)
            }
            best = max(best, score)
        }
        return best
    }

    // MARK: - Signal 2: Naive Bayes over history

    /// Multinomial Naive Bayes with Laplace smoothing, returned as softmax
    /// probabilities so the numbers sit on the same 0...1 scale as the rest.
    private func bayesScores(tokens: Set<String>, byCategory: [String: [Example]]) -> [String: Double] {
        let trained = categories.filter { !(byCategory[$0] ?? []).isEmpty }
        guard trained.count >= 2 else { return [:] }

        var vocabulary = Set<String>()
        var counts: [String: [String: Int]] = [:]
        var totals: [String: Int] = [:]

        for category in trained {
            var bag: [String: Int] = [:]
            for example in byCategory[category] ?? [] {
                for token in Self.tokenise(example.note) {
                    bag[token, default: 0] += 1
                    vocabulary.insert(token)
                }
            }
            counts[category] = bag
            totals[category] = bag.values.reduce(0, +)
        }
        guard !vocabulary.isEmpty else { return [:] }

        // With no recognised token there is no evidence, only class priors —
        // and those would hand every unknown note to whichever category happens
        // to have the most history. Stay silent instead.
        let known = tokens.filter { vocabulary.contains($0) }
        guard !known.isEmpty else { return [:] }

        let vocabSize = Double(vocabulary.count)
        let corpus = Double(trained.reduce(0) { $0 + (byCategory[$1]?.count ?? 0) })

        var logScores: [String: Double] = [:]
        for category in trained {
            let docs = Double(byCategory[category]?.count ?? 0)
            var logProb = log(max(docs, 1) / max(corpus, 1))
            let bag = counts[category] ?? [:]
            let denominator = Double(totals[category] ?? 0) + vocabSize

            // Only tokens we have actually seen carry information; unknown
            // words would otherwise punish every category equally.
            for token in known {
                logProb += log((Double(bag[token] ?? 0) + 1) / denominator)
            }
            logScores[category] = logProb
        }

        guard let maxLog = logScores.values.max() else { return [:] }
        let exponentials = logScores.mapValues { exp($0 - maxLog) }
        let sum = exponentials.values.reduce(0, +)
        guard sum > 0 else { return [:] }
        return exponentials.mapValues { $0 / sum }
    }

    // MARK: - Signal 3: keyword dictionary

    private static func keywordScore(tokens: Set<String>, category: String) -> Double {
        guard let words = keywords[category] else { return 0 }
        let haystack = tokens.joined(separator: " ")
        for word in words where haystack.contains(word) {
            // A whole-token hit is stronger than a prefix hit inside a word.
            return tokens.contains(word) ? 1.0 : 0.8
        }
        return 0
    }

    // MARK: - Signal 4: the category's own name

    private static func nameScore(tokens: Set<String>, category: String) -> Double {
        let nameTokens = tokenise(category)
        guard !nameTokens.isEmpty else { return 0 }
        if !tokens.intersection(nameTokens).isEmpty { return 1 }

        // Catch near-misses and typos: "grocerys" vs "groceries".
        var best = 0.0
        for token in tokens where token.count >= 4 {
            for name in nameTokens where name.count >= 4 {
                best = max(best, similarity(token, name))
            }
        }
        return best > 0.8 ? best : 0
    }

    /// 1 - normalised Levenshtein distance.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        let distance = Double(previous[y.count])
        return 1 - distance / Double(max(x.count, y.count))
    }

    // MARK: - Tokenising

    private static let stopwords: Set<String> = [
        "on", "for", "at", "the", "and", "plus", "spent", "paid", "bought", "from", "with",
        "и", "на", "за", "в", "по", "с", "у",
        "va", "uchun", "bilan",
        "sum", "sums", "som", "uzs", "сум", "сўм",
    ]

    static func tokenise(_ text: String) -> Set<String> {
        let parts = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { token in
            token.count >= 2
                && token.rangeOfCharacter(from: .decimalDigits) == nil
                && !stopwords.contains(token)
        })
    }

    // MARK: - Built-in keyword table (cold start)

    /// Keyed by the app's default category names. Latin and Cyrillic spellings
    /// sit side by side because people mix languages here.
    static let keywords: [String: [String]] = [
        "Groceries":        ["grocer", "supermarket", "korzinka", "makro", "havas", "продукт", "магазин", "oziq"],
        "Restaurants":      ["restaurant", "cafe", "lunch", "dinner", "breakfast", "ресторан", "кафе", "обед", "ужин", "restoran", "kafe", "tushlik"],
        "Food delivery":    ["delivery", "express24", "wolt", "glovo", "доставка", "yetkaz"],
        "Coffee":           ["coffee", "latte", "cappuccino", "espresso", "кофе", "qahva", "kofe"],
        "Public transport": ["metro", "bus", "tram", "метро", "автобус", "avtobus"],
        "Car":              ["parking", "carwash", "парковк", "мойка", "avtoturargoh"],
        "Fuel":             ["fuel", "petrol", "gasoline", "бензин", "заправк", "benzin", "yoqilg"],
        "Taxi":             ["taxi", "uber", "yandex", "bolt", "такси", "taksi"],
        "Utilities":        ["utilit", "electric", "коммунал", "свет", "вода", "kommunal"],
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
        "Investment":       ["investment", "dividend", "инвестиц"],
        "Gift":             ["gift", "present", "подарок", "sovg"],
    ]
}
