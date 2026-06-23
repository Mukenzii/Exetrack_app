import SwiftUI
import CoreData

struct TransactionsListView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)],
        animation: .default
    ) private var transactions: FetchedResults<TransactionEntity>

    @State private var showAdd = false

    private var vm: TransactionViewModel { TransactionViewModel(context: context) }

    var grouped: [(String, [TransactionEntity])] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "en_US")

        let sorted = transactions.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let dict = Dictionary(grouping: sorted) { tx -> String in
            let d = tx.date ?? Date()
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInYesterday(d) { return "Yesterday" }
            return formatter.string(from: d)
        }
        let order = ["Today", "Yesterday"]
        return dict.keys.sorted { a, b in
            let ai = order.firstIndex(of: a)
            let bi = order.firstIndex(of: b)
            if let ai, let bi { return ai < bi }
            if ai != nil { return true }
            if bi != nil { return false }
            return (dict[a]?.first?.date ?? .distantPast) > (dict[b]?.first?.date ?? .distantPast)
        }.compactMap { k in dict[k].map { (k, $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.0) { date, txs in
                    Section(date) {
                        ForEach(txs, id: \.id) { tx in
                            TransactionRow(transaction: tx)
                        }
                        .onDelete { offsets in
                            offsets.forEach { vm.delete(txs[$0]) }
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTransactionView()
            }
            .overlay {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "tray",
                        description: Text("Tap + to add your first")
                    )
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: TransactionEntity

    private var accountName: String {
        if let note = transaction.note, !note.isEmpty { return note }
        return "Personal"
    }

    var body: some View {
        HStack(spacing: 14) {
            CategoryAvatar(
                colorHex: transaction.category?.colorHex ?? "#888",
                systemName: transaction.category?.icon ?? "questionmark"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.category?.name ?? "No category")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                AccountBadge(name: accountName)
            }

            Spacer()

            Text(transaction.isIncome
                 ? "+ \(Theme.money(transaction.amount))"
                 : Theme.money(transaction.amount))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(transaction.isIncome ? .green : .white)
        }
        .padding(.vertical, 4)
    }
}
