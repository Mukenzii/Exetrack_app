import SwiftUI
import CoreData

struct SetCategoryLimitView: View {
    let category: CategoryEntity
    let prefill: Double
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var transactions: FetchedResults<TransactionEntity>

    @State private var digits: String

    init(category: CategoryEntity, prefill: Double, onSave: @escaping (Double) -> Void) {
        self.category = category
        self.prefill  = prefill
        self.onSave   = onSave
        _digits = State(initialValue: prefill > 0 ? String(Int(prefill)) : "")
        _transactions = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "category == %@", category)
        )
    }

    private var amount: Double {
        Double(digits.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var displayAmount: String {
        if digits.isEmpty { return "0" }
        let num = Double(digits.replacingOccurrences(of: ",", with: ".")) ?? 0
        return Theme.amount(num)
    }

    private var last30DaysSpend: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return transactions
            .filter { !$0.isIncome && ($0.date ?? Date()) >= cutoff }
            .reduce(0) { $0 + $1.amount }
    }

    private var periodLabel: String {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let endComponents = DateComponents(month: 1, day: -1)
        let end = cal.date(byAdding: endComponents, to: start) ?? now
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    private var catColor: Color { Color(hex: category.colorHex ?? "#888") }

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

                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(catColor).frame(width: 32, height: 32)
                            Image(systemName: category.icon ?? "tag.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.contrasting(on: category.colorHex ?? "#888"))
                        }
                        Text(category.name ?? "")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // Amount display
                VStack(spacing: 10) {
                    Text("Period: \(periodLabel)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(displayAmount)
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: displayAmount)
                        Text(Theme.currency)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                    Text("Spent last 30 days: \(Theme.money(last30DaysSpend))")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

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

                // Set limit button
                Button {
                    guard amount > 0 else { return }
                    onSave(amount)
                    dismiss()
                } label: {
                    Text("Set limit")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Key builders

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

    // MARK: - Input helpers

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
