import SwiftUI
import CoreData

struct NeedsReviewView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)],
        predicate: NSPredicate(format: "category == nil"),
        animation: .default
    ) private var uncategorized: FetchedResults<TransactionEntity>

    @State private var selectedTx: TransactionEntity?

    private var totalIncome: Double { uncategorized.filter { $0.isIncome }.reduce(0) { $0 + $1.amount } }
    private var totalExpense: Double { uncategorized.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount } }

    private var cal: Calendar { Calendar.current }

    private var grouped: [(String, [TransactionEntity])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        let dict = Dictionary(grouping: uncategorized) { tx in
            cal.isDateInToday(tx.date ?? Date()) ? "Today" : formatter.string(from: tx.date ?? Date())
        }
        return dict.sorted { a, b in
            if a.key == "Today" { return true }
            if b.key == "Today" { return false }
            return a.key > b.key
        }
    }

    private func dayTotal(_ txs: [TransactionEntity]) -> String {
        let net = txs.reduce(0.0) { $0 + ($1.isIncome ? $1.amount : -$1.amount) }
        let sign = net >= 0 ? "+" : ""
        return "\(sign)\(Theme.money(net))"
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0C").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    Text("Needs review")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Summary
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(uncategorized.count) transaction\(uncategorized.count == 1 ? "" : "s")")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 20, height: 20)
                                .background(Color.white, in: .circle)
                            Text(Theme.money(totalExpense))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 20, height: 20)
                                .background(Color.white, in: .circle)
                            Text(Theme.money(totalIncome))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(grouped, id: \.0) { dateLabel, txs in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(dateLabel)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(dayTotal(txs))
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(txs.enumerated()), id: \.element.id) { idx, tx in
                                        Button { selectedTx = tx } label: {
                                            TransactionRow(transaction: tx)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 14)
                                        }
                                        .buttonStyle(.plain)

                                        if idx < txs.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.07))
                                                .padding(.leading, 72)
                                        }
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedTx) { tx in
            TransactionDetailSheet(transaction: tx)
        }
    }
}
