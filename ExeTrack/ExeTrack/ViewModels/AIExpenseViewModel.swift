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
    /// How sure the parser was, 0...1. Drives the "check this" hint.
    var confidence: Double

    /// Below this we nudge the user to look before saving.
    var needsAttention: Bool { category == nil || confidence < 0.5 }
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
        let names = available.compactMap { $0.name }

        do {
            let parsed = try await ExpenseIntelligence(categories: names).parse(input)
            drafts = parsed.map { item in
                ExpenseDraft(
                    amount: item.amount,
                    category: resolve(item.categoryName, isIncome: item.isIncome, in: available),
                    note: item.note,
                    date: Date(),
                    isIncome: item.isIncome,
                    confidence: item.confidence
                )
            }
            phase = drafts.isEmpty
                ? .failed(ExpenseParseError.nothingRecognised.localizedDescription)
                : .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func backToComposing() {
        phase = .composing
    }

    func startOver() {
        text = ""
        drafts = []
        phase = .composing
    }

    func remove(_ draft: ExpenseDraft) {
        drafts.removeAll { $0.id == draft.id }
        if drafts.isEmpty { phase = .composing }
    }

    // MARK: - Saving

    /// Writes every draft as a transaction. Returns how many were saved.
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

    // MARK: - Category lookup

    private func allCategories() -> [CategoryEntity] {
        let request: NSFetchRequest<CategoryEntity> = CategoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Maps a category name the parser produced onto a real category, keeping
    /// income and expense sides separate so a refund can't land in "Groceries".
    private func resolve(_ name: String, isIncome: Bool, in all: [CategoryEntity]) -> CategoryEntity? {
        let candidates = all.filter { $0.isIncome == isIncome }
        guard !candidates.isEmpty else { return nil }

        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        if let exact = candidates.first(where: { ($0.name ?? "").lowercased() == needle }) {
            return exact
        }
        return candidates.first { candidate in
            let hay = (candidate.name ?? "").lowercased()
            return hay.contains(needle) || needle.contains(hay)
        }
    }
}
