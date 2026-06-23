import SwiftUI
import CoreData

struct BudgetsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
    ) private var categories: FetchedResults<CategoryEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetEntity.month, ascending: true)]
    ) private var budgets: FetchedResults<BudgetEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
    ) private var transactions: FetchedResults<TransactionEntity>

    @State private var showAdd = false

    private var vm: BudgetViewModel { BudgetViewModel(context: context) }

    var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var currentBudgets: [BudgetEntity] {
        budgets.filter { Int($0.month) == currentMonth && Int($0.year) == currentYear }
    }

    var body: some View {
        NavigationStack {
            List {

                ForEach(currentBudgets, id: \.id) { budget in
                    if let cat = budget.category {
                        let spent = vm.spent(
                            for: cat, month: currentMonth, year: currentYear,
                            transactions: Array(transactions)
                        )
                        BudgetRow(budget: budget, spent: spent)
                    }
                }
                .onDelete { offsets in
                    offsets.forEach { context.delete(currentBudgets[$0]) }
                    try? context.save()
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddBudgetView()
            }
            .overlay {
                if currentBudgets.isEmpty {
                    ContentUnavailableView(
                        "No budgets",
                        systemImage: "chart.bar",
                        description: Text("Tap + to add a limit")
                    )
                }
            }
        }
    }
}

struct BudgetRow: View {
    let budget: BudgetEntity
    let spent: Double

    var progress: Double {
        guard budget.amount > 0 else { return 0 }
        return min(spent / budget.amount, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let cat = budget.category {
                    Image(systemName: cat.icon ?? "tag")
                        .foregroundColor(Color(hex: cat.colorHex ?? "#888"))
                    Text(cat.name ?? "").bold()
                }
                Spacer()
                Text("\(spent, specifier: "%.0f") / \(budget.amount, specifier: "%.0f") ₸")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(progress > 0.85 ? .red : progress > 0.6 ? .orange : .green)
        }
        .padding(.vertical, 4)
    }
}
