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
    /// Set when nothing in the user's list fitted: the category the agent
    /// thinks should exist, so the card can offer to create it.
    var proposedCategory: (name: String, icon: String)?

    /// Below this we nudge the user to look before saving.
    ///
    /// The threshold is set from what the agent actually returns: confident
    /// placements come back at 0.75 and above, an unfamiliar merchant around
    /// 0.65, and a note with no merchant at all around 0.40.
    var needsAttention: Bool {
        category == nil || categoryConfidence < 0.7 || amountConfidence < 0.5
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
    /// Why no category was suggested, when that happens. Not a failure — the
    /// user can still choose one.
    @Published private(set) var categoryNotice: String?

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        if case .ruleBased(let reason) = ExpenseIntelligence.status {
            fallbackNotice = reason
        }
    }

    var usesAppleIntelligence: Bool { ExpenseIntelligence.status.usesAppleIntelligence }

    /// Reports the engine that would actually run on the current text, rather
    /// than merely whether Apple Intelligence exists. Uzbek always uses the
    /// built-in parser because the on-device model cannot read it.
    var engineLabel: String {
        guard usesAppleIntelligence, ExpenseIntelligence.handlesLanguage(of: text) else {
            return "Built-in parser"
        }
        return "On device"
    }

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
            guard !parsed.isEmpty else {
                phase = .failed(ExpenseParseError.nothingRecognised.localizedDescription)
                return
            }
            drafts = parsed.map { item in
                ExpenseDraft(
                    amount: item.amount,
                    category: nil,
                    note: item.note,
                    date: Date(),
                    isIncome: item.isIncome,
                    amountConfidence: item.confidence,
                    categoryConfidence: 0,
                    alternatives: [],
                    proposedCategory: nil
                )
            }
            // Step 2 — let the agent place them among the user's categories.
            await assignCategories(to: parsed, from: available)
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func backToComposing() { phase = .composing }

    func startOver() {
        text = ""
        drafts = []
        categoryNotice = nil
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

    // MARK: - Creating a missing category

    /// Colours new categories get, cycled so two created in a row look distinct.
    private static let palette = [
        "#8E8E93", "#64D2FF", "#FF9F0A", "#BF5AF2", "#30D158",
        "#FF453A", "#5AC8FA", "#FF2D55", "#FFD60A", "#0A84FF",
    ]

    /// Creates the category the agent proposed and files the draft under it.
    ///
    /// Saved immediately, so it is a real category the user can reuse and edit
    /// like any other — not something that exists only on this screen.
    func createProposedCategory(for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }),
              let proposal = drafts[index].proposedCategory else { return }

        let isIncome = drafts[index].isIncome
        let existing = allCategories()

        // If the user already has one by that name, just use it.
        if let match = existing.first(where: {
            $0.name?.caseInsensitiveCompare(proposal.name) == .orderedSame && $0.isIncome == isIncome
        }) {
            apply(match, at: index)
            return
        }

        let category = CategoryEntity(context: context)
        category.id = UUID()
        category.name = proposal.name
        category.icon = proposal.icon
        category.isIncome = isIncome
        category.colorHex = Self.palette[existing.count % Self.palette.count]
        category.group = "Other"
        try? context.save()

        apply(category, at: index)
    }

    private func apply(_ category: CategoryEntity, at index: Int) {
        drafts[index].category = category
        drafts[index].categoryConfidence = 1
        drafts[index].proposedCategory = nil
    }

    // MARK: - Classification

    /// Asks the OpenAI agent to place every draft, in one round trip.
    ///
    /// The agent is handed only this user's categories, so whatever comes back
    /// is already one of them. When no key is configured, or the call fails,
    /// drafts simply arrive without a category and the user picks — the screen
    /// still works, it just stops guessing.
    private func assignCategories(to parsed: [ParsedExpense], from all: [CategoryEntity]) async {
        guard Config.OpenAI.isConfigured else {
            categoryNotice = OpenAICategoryAgent.Failure.missingAPIKey.localizedDescription
            return
        }

        // Income and expense are placed separately so a refund can never be
        // offered "Groceries".
        for isIncome in [false, true] {
            let indices = parsed.indices.filter { parsed[$0].isIncome == isIncome }
            guard !indices.isEmpty else { continue }

            let side = all.filter { $0.isIncome == isIncome }
            let names = side.compactMap(\.name)
            guard !names.isEmpty else { continue }

            let byName = Dictionary(
                side.compactMap { entity -> (String, CategoryEntity)? in
                    guard let name = entity.name else { return nil }
                    return (name, entity)
                },
                uniquingKeysWith: { first, _ in first }
            )

            let items = indices.map {
                OpenAICategoryAgent.Item(note: parsed[$0].note, amount: parsed[$0].amount)
            }

            do {
                let suggestions = try await OpenAICategoryAgent().classify(
                    items: items,
                    categories: names,
                    pastChoices: pastChoices(isIncome: isIncome)
                )
                for suggestion in suggestions {
                    guard indices.indices.contains(suggestion.index) else { continue }
                    let draftIndex = indices[suggestion.index]
                    guard drafts.indices.contains(draftIndex) else { continue }
                    drafts[draftIndex].category = byName[suggestion.category]
                    drafts[draftIndex].categoryConfidence = suggestion.confidence
                    drafts[draftIndex].alternatives = suggestion.alternatives.compactMap { byName[$0] }
                    drafts[draftIndex].proposedCategory = suggestion.proposedCategory
                        .map { (name: $0.name, icon: $0.icon) }
                }
            } catch {
                categoryNotice = error.localizedDescription
            }
        }
    }

    /// A sample of what this user has filed before, given to the agent as
    /// worked examples so it follows their habits rather than generic ones.
    private func pastChoices(isIncome: Bool) -> [OpenAICategoryAgent.PastChoice] {
        let request: NSFetchRequest<TransactionEntity> = TransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "note != nil AND note != '' AND category != nil AND isIncome == %@",
            NSNumber(value: isIncome)
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
        // Enough to show the pattern without bloating the prompt.
        request.fetchLimit = 40

        var seen = Set<String>()
        var choices: [OpenAICategoryAgent.PastChoice] = []
        for tx in (try? context.fetch(request)) ?? [] {
            guard let note = tx.note, !note.isEmpty,
                  let name = tx.category?.name else { continue }
            let key = note.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            choices.append(.init(note: note, category: name))
            if choices.count == 15 { break }
        }
        return choices
    }

    private func allCategories() -> [CategoryEntity] {
        let request: NSFetchRequest<CategoryEntity> = CategoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

}
