import SwiftUI
import CoreData

// MARK: - Gauge arc shape

private struct GaugeArcShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = rect.width / 2
        let endAngle = 180.0 - 180.0 * progress
        p.addArc(center: center, radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(endAngle),
                 clockwise: false)
        return p
    }
}

// MARK: - Main view

struct BudgetsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetEntity.month, ascending: true)]
    ) private var budgets: FetchedResults<BudgetEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
    ) private var transactions: FetchedResults<TransactionEntity>

    @State private var showEdit = false
    @State private var showManage = false
    @State private var showDeleteAlert = false

    private var vm: BudgetViewModel { BudgetViewModel(context: context) }
    private var cal: Calendar { Calendar.current }
    private var now: Date { Date() }
    private var currentMonth: Int { cal.component(.month, from: now) }
    private var currentYear: Int { cal.component(.year, from: now) }

    private var overallBudget: BudgetEntity? {
        budgets.first { $0.category == nil && Int($0.month) == currentMonth && Int($0.year) == currentYear }
    }

    private var categoryBudgets: [BudgetEntity] {
        budgets.filter { $0.category != nil && Int($0.month) == currentMonth && Int($0.year) == currentYear }
            .sorted { ($0.category?.name ?? "") < ($1.category?.name ?? "") }
    }

    private var totalSpent: Double {
        transactions
            .filter { !$0.isIncome
                && cal.component(.month, from: $0.date ?? now) == currentMonth
                && cal.component(.year, from: $0.date ?? now) == currentYear }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalCategoryAllocated: Double {
        categoryBudgets.reduce(0) { $0 + $1.amount }
    }

    private var budgetAmount: Double { overallBudget?.amount ?? 0 }
    private var remaining: Double { max(budgetAmount - totalSpent, 0) }
    private var leftToAllocate: Double { max(budgetAmount - totalCategoryAllocated, 0) }
    private var progress: Double { budgetAmount > 0 ? min(totalSpent / budgetAmount, 1.0) : 0 }

    private var daysInMonth: Int { cal.range(of: .day, in: .month, for: now)?.count ?? 30 }
    private var dayOfMonth: Int { cal.component(.day, from: now) }
    private var daysLeft: Int { max(daysInMonth - dayOfMonth, 0) }

    private var timeElapsed: Double { Double(dayOfMonth) / Double(daysInMonth) }
    private var isSpendingFast: Bool { budgetAmount > 0 && timeElapsed > 0 && (progress / timeElapsed) > 1.1 }

    private var gaugeColor: Color {
        progress >= 1 ? .red : progress > 0.85 ? .orange : Color(hex: "#30D158")
    }

    private var periodLabel: String {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        let fmt2 = DateFormatter(); fmt2.dateFormat = "MMM d"
        return "\(fmt.string(from: start)) – \(fmt2.string(from: end))"
    }

    var body: some View {
        ZStack {
            Color(hex: "#0B0B0D").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Warning banner
                    if isSpendingFast {
                        warningBanner
                    }

                    // Gauge card
                    gaugeCard

                    // Category budgets
                    if !categoryBudgets.isEmpty {
                        categorySection
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 64) }

            // Top bar
            VStack {
                topBar
                Spacer()
            }
        }
        .sheet(isPresented: $showEdit) {
            AddBudgetView(existingBudget: overallBudget)
        }
        .sheet(isPresented: $showManage) {
            ManageCategoryBudgetsView()
        }
        .alert("Delete Budget", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteBudget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will also delete all category budgets for this month.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text("Budget")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 10) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Warning banner

    private var warningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            Text("Spending a bit faster than planned. Keep an eye on it.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Gauge card

    private var gaugeCard: some View {
        VStack(spacing: 0) {
            // Period row
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Monthly")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Text(periodLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Days left")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(daysLeft) days")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Gauge + center text
            ZStack {
                GeometryReader { geo in

                    // Track
                    GaugeArcShape(progress: 1)
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 22, lineCap: .round))

                    // Progress fill
                    GaugeArcShape(progress: progress)
                        .stroke(gaugeColor, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
                }
                .frame(height: 130)
                .padding(.horizontal, 20)

                // Center text
                VStack(spacing: 4) {
                    Text("Left")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Text(Theme.money(remaining))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: remaining)
                    if budgetAmount > 0 {
                        Text("\(Int(progress * 100))% used")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(gaugeColor)
                    }
                }
                .offset(y: 20)
            }
            .frame(height: 160)

            // Stats row
            HStack(spacing: 0) {
                statItem(label: "Amount", value: Theme.money(budgetAmount))
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 36)
                statItem(label: "Left to allocate", value: Theme.money(leftToAllocate))
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category section

    private var categorySection: some View {
        VStack(spacing: 10) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Category budgets")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(Theme.money(totalCategoryAllocated)) total")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { showManage = true } label: {
                    Text("Manage")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            // Category rows — each is its own card
            ForEach(categoryBudgets, id: \.id) { budget in
                if let cat = budget.category {
                    let spent = vm.spent(for: cat, month: currentMonth, year: currentYear, transactions: Array(transactions))
                    let leftAmt = max(budget.amount - spent, 0)

                    HStack(spacing: 14) {
                        CategoryAvatar(colorHex: cat.colorHex ?? "#888", systemName: cat.icon ?? "tag.fill", size: 44)

                        Text(cat.name ?? "")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Theme.money(leftAmt)) left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("of \(Theme.money(budget.amount))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    // MARK: - Delete

    private func deleteBudget() {
        let toDelete = budgets.filter { Int($0.month) == currentMonth && Int($0.year) == currentYear }
        toDelete.forEach { context.delete($0) }
        try? context.save()
        dismiss()
    }
}
