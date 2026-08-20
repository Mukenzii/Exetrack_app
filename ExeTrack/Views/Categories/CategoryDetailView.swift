import SwiftUI
import CoreData

// MARK: - Main view

struct CategoryDetailView: View {
    let category: CategoryEntity

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var transactions: FetchedResults<TransactionEntity>
    @FetchRequest private var budgets: FetchedResults<BudgetEntity>

    @State private var showSetLimit = false
    @State private var selectedTx: TransactionEntity? = nil

    init(category: CategoryEntity) {
        self.category = category
        _transactions = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)],
            predicate: NSPredicate(format: "category == %@", category)
        )
        _budgets = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "category == %@", category)
        )
    }

    // MARK: Computed

    private var catColor: Color { Color(hex: category.colorHex ?? "#FFD60A") }

    private let cal = Calendar.current

    private var now: Date { Date() }

    private var periodStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
    }

    private var periodTransactions: [TransactionEntity] {
        transactions.filter {
            guard let d = $0.date else { return false }
            return d >= periodStart && !$0.isIncome
        }
    }

    private var totalSpent: Double {
        periodTransactions.reduce(0) { $0 + $1.amount }
    }

    private var categoryBudget: Double? {
        let m = cal.component(.month, from: now)
        let y = cal.component(.year, from: now)
        return budgets.first(where: { Int($0.month) == m && Int($0.year) == y })?.amount
    }

    // Daily spend array: index 0 = day 1, index 30 = day 31 (clamped to days in month)
    private var daysInMonth: Int { cal.range(of: .day, in: .month, for: now)?.count ?? 30 }
    private var todayDay: Int { cal.component(.day, from: now) }

    private var dailyCumulative: [Double] {
        var byDay = [Int: Double]()
        for tx in periodTransactions {
            guard let d = tx.date else { continue }
            let day = cal.component(.day, from: d)
            byDay[day, default: 0] += tx.amount
        }
        var cum = 0.0
        return (1...daysInMonth).map { day in
            if day <= todayDay { cum += byDay[day] ?? 0 }
            return cum
        }
    }

    private var forecastTotal: Double {
        guard todayDay > 0 else { return 0 }
        let dailyRate = totalSpent / Double(todayDay)
        return dailyRate * Double(daysInMonth)
    }

    // Last period (previous month): no data unless we query — skip for now
    private var lastPeriodSpent: Double? { nil }

    // Suggested limit = last 30 days actual spend
    private var suggestedLimit: Double {
        let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
        return transactions
            .filter { !$0.isIncome && ($0.date ?? now) >= cutoff }
            .reduce(0) { $0 + $1.amount }
    }

    // Group period transactions by date for the list
    private var groupedTransactions: [(String, [TransactionEntity])] {
        let sorted = periodTransactions.sorted { ($0.date ?? now) > ($1.date ?? now) }
        let grouped = Dictionary(grouping: sorted) { tx -> String in
            guard let d = tx.date else { return "Unknown" }
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInYesterday(d) { return "Yesterday" }
            let fmt = DateFormatter()
            fmt.dateFormat = "d MMMM"
            return fmt.string(from: d)
        }
        let order = ["Today", "Yesterday"]
        let keys = grouped.keys.sorted { a, b in
            let ai = order.firstIndex(of: a) ?? 999
            let bi = order.firstIndex(of: b) ?? 999
            if ai != bi { return ai < bi }
            return a > b
        }
        return keys.compactMap { k in grouped[k].map { (k, $0) } }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: catColor.opacity(0.55), location: 0),
                    .init(color: catColor.opacity(0.15), location: 0.35),
                    .init(color: .clear, location: 0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.top, 16)

                    chartSection
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        if categoryBudget != nil {
                            budgetForecastRow
                        } else {
                            suggestedLimitCard
                        }
                        transactionList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 60)
            }

            // Blur sits above scroll content but below header buttons
            ProgressiveBlurView(height: 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            // Header on top of blur
            VStack {
                headerBar
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Spacer()
            }

        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSetLimit) {
            SetCategoryLimitView(category: category, prefill: suggestedLimit) { limit in
                saveCategoryBudget(limit)
            }
        }
        .sheet(item: $selectedTx) { tx in
            TransactionDetailSheet(transaction: tx)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text(category.name ?? "Category")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 10) {
                Button {} label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Button {} label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spent in budget period")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))

                Text(Theme.money(totalSpent))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: totalSpent)

                if let last = lastPeriodSpent {
                    Text("vs \(Theme.money(last)) last period")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("No data from last period")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            // Category icon circle
            ZStack {
                Circle()
                    .fill(catColor)
                    .frame(width: 64, height: 64)
                Image(systemName: category.icon ?? "tag.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.contrasting(on: category.colorHex ?? "#FFD60A"))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CategorySpendChart(
                dailyCumulative: dailyCumulative,
                forecastTotal: forecastTotal,
                todayIndex: todayDay - 1,
                color: catColor,
                budgetLimit: categoryBudget
            )
            .frame(height: 160)
            .padding(.horizontal, 0)

            // X-axis labels
            HStack {
                ForEach([1, 6, 11, 16, 21, 25, 30], id: \.self) { day in
                    Text("\(day)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    if day != 30 { Spacer() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle().fill(catColor).frame(width: 8, height: 8)
                    Text("Actual")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(0.4)).frame(width: 8, height: 8)
                    Text("Forecast")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    // MARK: - Suggested limit card

    private var suggestedLimitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested category limit")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            Text(Theme.money(suggestedLimit))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            if let budget = categoryBudget, suggestedLimit > budget {
                Text("This suggested limit exceeds your total budget by \(Theme.money(suggestedLimit - budget))")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Button {
                showSetLimit = true
            } label: {
                Text("Use suggested limit")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Budget + Forecast 2-col (when limit is set)

    private var budgetForecastRow: some View {
        HStack(spacing: 6) {
            // Budget card
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Budget")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 14)

                Spacer()

                if let b = categoryBudget {
                    let progress = min(totalSpent / max(b, 1), 1.0)
                    let left = b - totalSpent

                    ProgressRing(progress: progress, size: 60, lineWidth: 6, color: catColor)
                        .overlay(
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .padding(.bottom, 14)

                    Text(Theme.money(max(left, 0)))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Left")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            // Forecast card
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Forecast")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Text(Theme.money(forecastTotal))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)

                if let b = categoryBudget, forecastTotal > 0, todayDay > 0 {
                    let daysLeft = daysInMonth - todayDay
                    let needed = max(b - totalSpent, 0)
                    let perDay = daysLeft > 0 ? needed / Double(daysLeft) : 0
                    Text("Spend \(Theme.money(perDay)) / day to stay within the limit")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                } else {
                    Text("By the end of this period")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Forecast + Insights 2-col

    private var forecastInsightsRow: some View {
        HStack(spacing: 12) {
            // Forecast
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Forecast")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text(Theme.money(forecastTotal))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("By the end of this period")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Insights
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Insights")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if periodTransactions.count >= 5 {
                    Text("Avg \(Theme.money(totalSpent / Double(max(1, todayDay))))/day")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("Add more transactions to unlock personalised insights")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Transaction list

    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedTransactions, id: \.0) { label, txs in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(Theme.money(txs.reduce(0) { $0 + $1.amount }))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(spacing: 0) {
                        ForEach(txs, id: \.id) { tx in
                            txRow(tx)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTx = tx }
                            if tx.id != txs.last?.id {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func txRow(_ tx: TransactionEntity) -> some View {
        HStack(spacing: 12) {
            CategoryAvatar(
                colorHex: category.colorHex ?? "#888",
                systemName: category.icon ?? "tag.fill",
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name ?? "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                if let note = tx.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("Personal")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            Text(Theme.money(tx.amount))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func saveCategoryBudget(_ limit: Double) {
        let m = Int32(cal.component(.month, from: now))
        let y = Int32(cal.component(.year, from: now))
        if let existing = budgets.first(where: { $0.month == m && $0.year == y }) {
            existing.amount = limit
        } else {
            let b = BudgetEntity(context: context)
            b.id = UUID()
            b.amount = limit
            b.month = m
            b.year = y
            b.category = category
        }
        try? context.save()
    }
}

// MARK: - Spend chart (Canvas)

private struct CategorySpendChart: View {
    let dailyCumulative: [Double]
    let forecastTotal: Double
    let todayIndex: Int
    let color: Color
    var budgetLimit: Double? = nil

    var body: some View {
        GeometryReader { geo in
            CategorySpendCanvas(
                dailyCumulative: dailyCumulative,
                forecastTotal: forecastTotal,
                todayIndex: todayIndex,
                color: color,
                size: geo.size,
                budgetLimit: budgetLimit
            )
        }
    }
}

private struct CategorySpendCanvas: View {
    let dailyCumulative: [Double]
    let forecastTotal: Double
    let todayIndex: Int
    let color: Color
    let size: CGSize
    var budgetLimit: Double? = nil

    private var maxValue: Double {
        max(dailyCumulative.max() ?? 1, forecastTotal, budgetLimit ?? 0, 1)
    }

    private func x(_ index: Int) -> CGFloat {
        guard dailyCumulative.count > 1 else { return 0 }
        return CGFloat(index) / CGFloat(dailyCumulative.count - 1) * size.width
    }

    private func y(_ value: Double) -> CGFloat {
        let topPad: CGFloat = 20
        let bottomPad: CGFloat = 10
        let range = size.height - topPad - bottomPad
        return topPad + range * (1 - CGFloat(value / maxValue))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
        Canvas { ctx, _ in
            let count = dailyCumulative.count
            guard count > 1 else { return }

            // --- Budget limit horizontal dashed line ---
            if let limit = budgetLimit, limit > 0 {
                let limitY = y(limit)
                var limitPath = Path()
                limitPath.move(to: CGPoint(x: 0, y: limitY))
                limitPath.addLine(to: CGPoint(x: size.width, y: limitY))
                ctx.stroke(
                    limitPath,
                    with: .color(.white.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                )
            }

            // Actual points up to today
            let actualCount = min(todayIndex + 1, count)

            // --- Gradient fill under actual line ---
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: x(0), y: size.height))
            for i in 0..<actualCount {
                fillPath.addLine(to: CGPoint(x: x(i), y: y(dailyCumulative[i])))
            }
            fillPath.addLine(to: CGPoint(x: x(actualCount - 1), y: size.height))
            fillPath.closeSubpath()

            ctx.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.35), color.opacity(0.0)]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            // --- Actual line ---
            var linePath = Path()
            linePath.move(to: CGPoint(x: x(0), y: y(dailyCumulative[0])))
            for i in 1..<actualCount {
                linePath.addLine(to: CGPoint(x: x(i), y: y(dailyCumulative[i])))
            }
            ctx.stroke(linePath, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // --- Dot at today ---
            let dotX = x(actualCount - 1)
            let dotY = y(dailyCumulative[actualCount - 1])
            let dotRect = CGRect(x: dotX - 5, y: dotY - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
            let innerRect = CGRect(x: dotX - 2.5, y: dotY - 2.5, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: innerRect), with: .color(.white))

            // --- Dashed forecast line from today to end ---
            if actualCount < count {
                let todayVal = dailyCumulative[actualCount - 1]
                var dashPath = Path()
                dashPath.move(to: CGPoint(x: x(actualCount - 1), y: y(todayVal)))
                dashPath.addLine(to: CGPoint(x: x(count - 1), y: y(forecastTotal)))
                ctx.stroke(
                    dashPath,
                    with: .color(.white.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 6])
                )

                // End dot
                let endX = x(count - 1)
                let endY = y(forecastTotal)
                let endRect = CGRect(x: endX - 4, y: endY - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: endRect), with: .color(.white.opacity(0.4)))
            }
        }
        .padding(.horizontal, 20)

        // Today spent pill label overlay
        if dailyCumulative.count > 0 {
            let topPad: CGFloat = 20
            let bottomPad: CGFloat = 10
            let hPad: CGFloat = 20
            let range = size.height - topPad - bottomPad
            let actualCount = min(todayIndex + 1, dailyCumulative.count)
            let todayVal = dailyCumulative[actualCount - 1]
            let todayY = topPad + range * (1 - CGFloat(todayVal / maxValue))
            let dotX = hPad + CGFloat(actualCount - 1) / CGFloat(max(dailyCumulative.count - 1, 1)) * size.width

            Text(Theme.money(todayVal))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .fixedSize()
                .position(x: dotX, y: todayY - 32)
        }

        // Budget limit pill label overlay
        if let limit = budgetLimit, limit > 0 {
            let topPad: CGFloat = 20
            let bottomPad: CGFloat = 10
            let hPad: CGFloat = 20
            let range = size.height - topPad - bottomPad
            let limitY = topPad + range * (1 - CGFloat(limit / maxValue))

            VStack {
                Spacer().frame(height: max(0, limitY - 12))
                HStack {
                    Spacer()
                    Text(Theme.money(limit))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                }
                .padding(.horizontal, hPad)
                Spacer()
            }
        }
        } // ZStack
    }
}
