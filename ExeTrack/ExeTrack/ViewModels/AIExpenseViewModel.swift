import CoreData
import Foundation
import SwiftUI

/// One proposed transaction the user can accept, edit, or throw away.
struct ExpenseDraft: Identifiable {
    let id = UUID()
    var amount: Double
    var category: CategoryEntity?
    var note: String
    var date: Date
    var isIncome: Bool
    /// How sure the extractor was about the amount, 0...1.
    var amountConfidence: Double
    /// How sure the classifier was about the category, 0...1.
    var categoryConfidence: Double
    /// Runner-up categories, offered as one-tap corrections.
    var alternatives: [CategoryEntity]

    /// Below this we nudge the user to look before saving.
    var needsAttention: Bool {
        category == nil || categoryConfidence < 0.5 || amountConfidence < 0.5
    }
}

@MainActor
final class AIExpenseViewModel: ObservableObject {

    enum Phase: Equatable {
        case composing
        case thinking
        case review
        case failed(String)
    }

    @Published var text = ""
    @Published private(set) var phase: Phase = .composing
    @Published var drafts: [ExpenseDraft] = []
    /// Shown once when we quietly fell back to the rule parser.
    @Published private(set) var fallbackNotice: String?

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        if case .ruleBased(let reason) = ExpenseIntelligence.status {
            fallbackNotice = reason
        }
    }

    var usesAppleIntelligence: Bool { ExpenseIntelligence.status.usesAppleIntelligence }

    var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .thinking
    }

    var canSave: Bool { drafts.contains { $0.amount > 0 } }

    var totalAmount: Double {
        drafts.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Parsing

    func submit() async {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        phase = .thinking
        let available = allCategories()

        do {
            // Step 1 — pull out amounts and merchants.
            let parsed = try await ExpenseIntelligence().parse(input)
            // Step 2 — decide where each one belongs, using the user's history.
            drafts = parsed.map { item in
                let ranked = classify(item.note.isEmpty ? input : item.note,
                                      isIncome: item.isIncome,
                                      in: available)
                return ExpenseDraft(
                    amount: item.amount,
                    category: ranked.first?.category,
                    note: item.note,
                    date: Date(),
                    isIncome: item.isIncome,
                    amountConfidence: item.confidence,
                    categoryConfidence: ranked.first?.confidence ?? 0,
                    alternatives: Array(ranked.dropFirst().prefix(3).map(\.category))
                )
            }
            phase = drafts.isEmpty
                ? .failed(ExpenseParseError.nothingRecognised.localizedDescription)
                : .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func backToComposing() { phase = .composing }

    func startOver() {
        text = ""
        drafts = []
        phase = .composing
    }

    func fail(_ message: String) { phase = .failed(message) }

    func remove(_ draft: ExpenseDraft) {
        drafts.removeAll { $0.id == draft.id }
        if drafts.isEmpty { phase = .composing }
    }

    // MARK: - Saving

    /// Writes every draft as a transaction. Returns how many were saved.
    ///
    /// Each saved row also becomes training data: the classifier reads the same
    /// history next time, so a correction here improves the next suggestion.
    @discardableResult
    func applyAll() -> Int {
        let vm = TransactionViewModel(context: context)
        let saved = drafts.filter { $0.amount > 0 }
        for draft in saved {
            vm.add(
                amount: draft.amount,
                note: draft.note,
                isIncome: draft.isIncome,
                category: draft.category,
                date: draft.date
            )
        }
        return saved.count
    }

    // MARK: - Classification

    private struct RankedCategory {
        let category: CategoryEntity
        let confidence: Double
    }

    /// Runs `CategoryClassifier` over the user's own transactions and maps the
    /// winning names back onto real category objects.
    private func classify(_ note: String, isIncome: Bool, in all: [CategoryEntity]) -> [RankedCategory] {
        let side = all.filter { $0.isIncome == isIncome }
        guard !side.isEmpty else { return [] }

        let names = side.compactMap { $0.name }
        let classifier = CategoryClassifier(categories: names, history: trainingExamples(for: isIncome))

        let byName = Dictionary(
            side.compactMap { entity -> (String, CategoryEntity)? in
                guard let name = entity.name else { return nil }
                return (name, entity)
            },
            uniquingKeysWith: { first, _ in first }
        )

        return classifier.rank(note).compactMap { candidate in
            guard let entity = byName[candidate.name] else { return nil }
            return RankedCategory(category: entity, confidence: candidate.confidence)
        }
    }

    /// Past transactions that carry both a note and a category — the classifier's
    /// training set.
    private func trainingExamples(for isIncome: Bool) -> [CategoryClassifier.Example] {
        let request: NSFetchRequest<TransactionEntity> = TransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "note != nil AND note != '' AND category != nil AND isIncome == %@",
            NSNumber(value: isIncome)
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
        // Recent habits matter more than ancient ones, and this keeps the
        // classifier cheap on a long history.
        request.fetchLimit = 500

        return ((try? context.fetch(request)) ?? []).compactMap { tx in
            guard let note = tx.note, !note.isEmpty,
                  let name = tx.category?.name else { return nil }
            return CategoryClassifier.Example(note: note, categoryName: name)
        }
    }

    private func allCategories() -> [CategoryEntity] {
        let request: NSFetchRequest<CategoryEntity> = CategoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Re-runs classification for one draft after the user flips it between
    /// expense and income, or edits the note.
    func reclassify(draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        let draft = drafts[index]
        let ranked = classify(draft.note, isIncome: draft.isIncome, in: allCategories())
        drafts[index].category = ranked.first?.category
        drafts[index].categoryConfidence = ranked.first?.confidence ?? 0
        drafts[index].alternatives = Array(ranked.dropFirst().prefix(3).map(\.category))
    }
}
