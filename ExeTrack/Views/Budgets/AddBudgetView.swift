import SwiftUI
import CoreData

struct AddBudgetView: View {
    var existingBudget: BudgetEntity? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
    ) private var transactions: FetchedResults<TransactionEntity>

    @State private var digits = ""
    @State private var isWeekly = false
    @State private var startDay = 1

    private var isEditing: Bool { existingBudget != nil }
    private var vm: BudgetViewModel { BudgetViewModel(context: context) }

    private var amount: Double {
        Double(digits.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var displayAmount: String {
        if digits.isEmpty { return "0" }
        let num = Double(digits.replacingOccurrences(of: ",", with: "")) ?? 0
        return Theme.amount(num)
    }

    private var last30DaysSpend: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return transactions
            .filter { !$0.isIncome && ($0.date ?? Date()) >= cutoff }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0B0B0D").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    Text(isEditing ? "Edit Budget" : "Budget")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // Subtitle + amount
                VStack(spacing: 12) {
                    Text("Set your overall budget limit for this period")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(displayAmount)
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: displayAmount)
                        Text(Theme.currency)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                    Text("Last 30 days: \(Theme.money(last30DaysSpend))")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Period + start day
                HStack {
                    // Sliding W/M toggle — same pattern as Expense/Income in AddTransactionView
                    HStack(spacing: 6) {
                        Button { withAnimation(.spring(duration: 0.25)) { isWeekly = true } } label: {
                            HStack(spacing: 8) {
                                Text("W")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isWeekly ? .black : Color.white.opacity(0.6))
                                    .frame(width: 22, height: 22)
                                    .background(isWeekly ? Color.white : Color.white.opacity(0.18), in: .circle)
                                if isWeekly {
                                    Text("Weekly")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, isWeekly ? 10 : 4)
                            .padding(.vertical, 6)
                            .background(isWeekly ? Color.white.opacity(0.08) : Color.clear, in: Capsule())
                        }
                        Button { withAnimation(.spring(duration: 0.25)) { isWeekly = false } } label: {
                            HStack(spacing: 8) {
                                Text("M")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isWeekly ? Color.white.opacity(0.6) : .black)
                                    .frame(width: 22, height: 22)
                                    .background(isWeekly ? Color.white.opacity(0.18) : Color.white, in: .circle)
                                if !isWeekly {
                                    Text("Monthly")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, isWeekly ? 4 : 10)
                            .padding(.vertical, 6)
                            .background(isWeekly ? Color.clear : Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)

                    Spacer()

                    Menu {
                        ForEach(1...28, id: \.self) { day in
                            Button("Start \(day)") { startDay = day }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Start \(startDay)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Numpad
                VStack(spacing: 4) {
                    ForEach([[7,8,9],[4,5,6],[1,2,3]], id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(row, id: \.self) { digit in
                                numKey(label: "\(digit)") { append("\(digit)") }
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        numKey(label: ",", dim: true) { appendComma() }
                        numKey(label: "0") { append("0") }
                        numKey(systemName: "delete.left", dim: true) { backspace() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Continue button
                Button {
                    guard amount > 0 else { return }
                    let month = Calendar.current.component(.month, from: Date())
                    let year  = Calendar.current.component(.year, from: Date())
                    if let existing = existingBudget {
                        existing.amount = amount
                        try? context.save()
                    } else {
                        let entity = BudgetEntity(context: context)
                        entity.id = UUID()
                        entity.amount = amount
                        entity.month = Int32(month)
                        entity.year  = Int32(year)
                        try? context.save()
                    }
                    dismiss()
                } label: {
                    Text(isEditing ? "Save" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .padding(.horizontal, 20)

                Text("You can skip and set category budgets next")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let existing = existingBudget, existing.amount > 0 {
                digits = String(Int(existing.amount))
            }
        }
    }

    // MARK: - Helpers

    private func numKey(label: String, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(dim ? Color(hex: "#141416") : Color(hex: "#1C1C1E"),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func numKey(systemName: String, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(dim ? Color(hex: "#141416") : Color(hex: "#1C1C1E"),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func append(_ s: String) {
        guard digits.replacingOccurrences(of: ",", with: "").count < 12 else { return }
        digits += s
    }

    private func appendComma() {
        guard !digits.contains(",") else { return }
        if digits.isEmpty { digits = "0" }
        digits += ","
    }

    private func backspace() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }
}
