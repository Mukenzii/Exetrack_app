import Foundation

/// Uzbek-specific text handling.
///
/// Apple's on-device model does not support Uzbek — `supportsLocale("uz")` is
/// false and there is a dedicated `unsupportedLanguageOrLocale` error — so for
/// Uzbek input the rule-based path is not a fallback, it is the whole pipeline.
/// It therefore has to actually understand the language.
///
/// Uzbek is written in both Latin and Cyrillic, and both are handled here.
enum UzbekLanguage {

    // MARK: - Normalisation

    /// Uzbek uses several apostrophe characters interchangeably (oʻ, o', o').
    /// Fold them all to one so "so'm", "soʻm" and "so'm" are the same word.
    static let apostrophes: Set<Character> = ["'", "\u{2018}", "\u{2019}", "\u{02BB}", "\u{02BC}", "`", "\u{00B4}"]

    static func normalise(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text.lowercased() {
            out.append(apostrophes.contains(ch) ? "'" : ch)
        }
        return out
    }

    /// Splits on everything that isn't a letter, digit or apostrophe — so
    /// "so'm" survives as one token instead of becoming "so" + "m".
    static func words(_ text: String) -> [String] {
        normalise(text)
            .split { ch in
                !(ch.isLetter || ch.isNumber || ch == "'")
            }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - Morphology

    /// Case, possessive and derivational endings, longest first so that
    /// "-lardan" is tried before "-dan".
    private static let suffixes = [
        "larimizdan", "laringizdan", "larimiz", "laringiz",
        "gacha", "qacha", "kacha", "lardan", "larga", "larda", "lardagi",
        "dagi", "tagi", "niki", "ning", "nikidan",
        "lar", "dan", "tan", "den", "dek", "cha", "lik", "liq", "lig",
        "ga", "ka", "qa", "da", "ta", "ni", "si", "im", "ing", "iz",
        // Cyrillic Uzbek takes the same endings.
        "ларидан", "лардан", "нинг", "даги", "дан", "лар", "лик", "ган",
        "га", "да", "ни", "та", "ча",
    ]

    /// Strips one grammatical ending so "Korzinkadan", "Korzinkaga" and
    /// "Korzinkada" all reduce to "korzinka" — which is what lets the
    /// classifier recognise the same merchant across sentences.
    ///
    /// Conservative on purpose: never leaves a stem shorter than four
    /// characters, so "ellik" doesn't erode to "el".
    static func stem(_ word: String) -> String {
        let w = normalise(word)
        guard w.count > 4 else { return w }
        for suffix in suffixes where w.hasSuffix(suffix) {
            let stem = String(w.dropLast(suffix.count))
            if stem.count >= 4 { return stem }
        }
        return w
    }

    /// Case endings only — the ones that mark a noun's role in the sentence,
    /// not the ones that build new words.
    private static let caseSuffixes = [
        "nikidan", "lardan", "larga", "larda", "dagi", "niki", "ning",
        "dan", "tan", "ga", "ka", "qa", "da", "ni",
        "ларидан", "лардан", "даги", "нинг", "дан", "га", "да", "ни",
    ]

    /// Stem for showing to a person: "Korzinkadan" → "Korzinka", while
    /// "tushlik" and "sovg'a" are left intact.
    static func displayStem(_ word: String) -> String {
        let w = normalise(word)
        guard w.count > 5 else { return w }
        for suffix in caseSuffixes where w.hasSuffix(suffix) {
            let stem = String(w.dropLast(suffix.count))
            if stem.count >= 4 { return stem }
        }
        return w
    }

    // MARK: - Spoken numbers

    /// Uzbek number words, Latin and Cyrillic. Aisha transcribes speech, so
    /// "yigirma besh ming" arrives as words rather than digits.
    private static let units: [String: Double] = [
        "nol": 0, "нол": 0,
        "bir": 1, "бир": 1,
        "ikki": 2, "икки": 2,
        "uch": 3, "уч": 3,
        "to'rt": 4, "tort": 4, "тўрт": 4, "торт": 4,
        "besh": 5, "беш": 5,
        "olti": 6, "олти": 6,
        "yetti": 7, "етти": 7,
        "sakkiz": 8, "саккиз": 8,
        "to'qqiz": 9, "toqqiz": 9, "тўққиз": 9,
        "o'n": 10, "on": 10, "ўн": 10,
        "yigirma": 20, "йигирма": 20,
        "o'ttiz": 30, "ottiz": 30, "ўттиз": 30,
        "qirq": 40, "қирқ": 40,
        "ellik": 50, "эллик": 50,
        "oltmish": 60, "олтмиш": 60,
        "yetmish": 70, "етмиш": 70,
        "sakson": 80, "саксон": 80,
        "to'qson": 90, "toqson": 90, "тўқсон": 90,
    ]

    /// Words that multiply whatever came before them.
    private static let scales: [String: Double] = [
        "yuz": 100, "юз": 100,
        "ming": 1_000, "минг": 1_000, "tysyacha": 1_000,
        "million": 1_000_000, "mln": 1_000_000, "миллион": 1_000_000, "млн": 1_000_000,
        "milliard": 1_000_000_000, "миллиард": 1_000_000_000, "mlrd": 1_000_000_000,
        // Russian, since people mix the two freely here.
        "тысяча": 1_000, "тысяч": 1_000, "тыс": 1_000,
    ]

    /// A token made purely of digits, or nil.
    private static func onlyDigits(_ token: String) -> String? {
        guard !token.isEmpty, token.allSatisfy({ $0.isNumber }) else { return nil }
        return token
    }

    /// Words that carry no numeric meaning and shouldn't break a number apart.
    private static let numberNoise: Set<String> = [
        "so'm", "som", "sum", "sums", "сўм", "сум", "uzs",
        "ga", "ta", "dan", "lik", "ва", "va",
    ]

    static func isNumberWord(_ word: String) -> Bool {
        let w = stripNumberSuffix(word)
        return units[w] != nil || scales[w] != nil
    }

    /// Number words take endings too — "mingga", "yuzdan", "milliondan".
    private static func stripNumberSuffix(_ word: String) -> String {
        let w = normalise(word)
        if units[w] != nil || scales[w] != nil { return w }
        for suffix in ["ga", "dan", "da", "ta", "lik", "gacha", "ni", "ka", "cha"] where w.hasSuffix(suffix) {
            let stem = String(w.dropLast(suffix.count))
            if units[stem] != nil || scales[stem] != nil { return stem }
        }
        return w
    }

    /// Reads a run of Uzbek number words into a value.
    ///
    /// Handles the additive-then-multiplicative structure of Uzbek numerals:
    /// "yigirma besh ming" is (20 + 5) × 1000, and "ikki yuz ming" is
    /// (2 × 100) × 1000. Bare digits mixed in are respected too, so "45 ming"
    /// works exactly like "qirq besh ming".
    ///
    /// Returns nil when the run holds no numeric information at all.
    static func value(ofNumberWords tokens: [String]) -> Double? {
        var total: Double = 0
        var current: Double = 0
        var sawAnything = false

        var index = 0
        while index < tokens.count {
            let raw = tokens[index]
            index += 1
            let token = stripNumberSuffix(raw)
            if numberNoise.contains(token) { continue }

            if var digitText = onlyDigits(token) {
                // "45 000" arrives as two tokens; a following group of exactly
                // three digits is a thousands separator, not a new number.
                while index < tokens.count,
                      let next = onlyDigits(tokens[index]), next.count == 3 {
                    digitText += next
                    index += 1
                }
                current += Double(digitText) ?? 0
                sawAnything = true
                continue
            }
            if let digits = Double(token.replacingOccurrences(of: ",", with: ".")) {
                current += digits
                sawAnything = true
                continue
            }
            if let unit = units[token] {
                current += unit
                sawAnything = true
                continue
            }
            if let scale = scales[token] {
                sawAnything = true
                if scale >= 1_000 {
                    // "ming" and up close off the group built so far.
                    total += max(current, 1) * scale
                    current = 0
                } else {
                    // "yuz" multiplies only the pending group.
                    current = max(current, 1) * scale
                }
                continue
            }
            // Anything else ends the number.
            break
        }

        guard sawAnything else { return nil }
        return total + current
    }

    /// Verbs and filler that surround an amount but never name a merchant.
    static let noteFiller: Set<String> = [
        "so'm", "som", "sum", "sums", "uzs", "сўм", "сум",
        "oldim", "oldim", "sotib", "to'ladim", "toladim", "berdim", "ketdi",
        "bo'ldi", "boldi", "qildim", "chiqdi", "uchun", "va", "ham", "pul",
        "menga", "bugun", "kecha", "edi", "ekan", "dedi",
        "олдим", "тўладим", "сотиб", "учун", "ва", "пул", "бугун",
        // Russian, since the two get mixed constantly.
        "купил", "купила", "заплатил", "заплатила", "потратил", "потратила",
        "на", "за", "в", "и", "рублей",
        // English, so one shared filter covers every path.
        "spent", "paid", "bought", "for", "at", "on", "the", "and", "plus", "a", "an",
    ]

    // MARK: - Detection

    private static let markers: Set<String> = [
        "so'm", "som", "sum", "ming", "yuz", "oldim", "to'ladim", "toladim",
        "sotib", "uchun", "berdim", "ketdi", "bo'ldi", "boldim", "pul",
        "сўм", "минг", "олдим", "тўладим",
    ]

    /// True when the text looks Uzbek — either a number word, a common verb or
    /// noun, or a grammatical ending we recognise. Used to route around a model
    /// that cannot read the language.
    static func looksUzbek(_ text: String) -> Bool {
        let tokens = words(text)
        guard !tokens.isEmpty else { return false }
        for token in tokens {
            let t = normalise(token)
            if markers.contains(t) { return true }
            if units[t] != nil || scales[t] != nil { return true }
            if isNumberWord(t) { return true }
            if t.contains("'") && t.count >= 3 { return true }
        }
        return false
    }
}
