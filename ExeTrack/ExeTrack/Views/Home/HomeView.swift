import SwiftUI
import CoreData

struct HomeView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)],
        animation: .default
    ) private var transactions: FetchedResults<TransactionEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetEntity.month, ascending: true)]
    ) private var budgets: FetchedResults<BudgetEntity>

    @State private var showAddTransaction = false
    @State private var showStatistics = false
    @State private var showBudgets = false
    @State private var showAddBudget = false
    @State private var showCategories = false
    @State private var showNeedsReview = false
    @State private var showAllTransactions = false
    @State private var selectedCategory: CategoryEntity? = nil
    @State private var selectedTx: TransactionEntity? = nil
    @State private var showQuickCategories = false
    @State private var quickCategory: CategoryEntity? = nil
    @State private var hoveredCategory: CategoryEntity? = nil
    @State private var pillFrames: [UUID: CGRect] = [:]
    @State private var longPressTask: Task<Void, Never>? = nil
    @State private var categoriesReady = false
    @State private var isTouchingPlus = false
    @State private var lastDragLocation: CGPoint = .zero

    // MARK: Derived data

    private var cal: Calendar { Calendar.current }

    private var monthName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM"
        return f.string(from: Date())
    }

    private var thisMonthTx: [TransactionEntity] {
        transactions.filter { cal.isDate($0.date ?? Date(), equalTo: Date(), toGranularity: .month) }
    }

    private var totalSpentThisMonth: Double {
        thisMonthTx.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var netBalance: Double {
        transactions.reduce(0) { $0 + ($1.isIncome ? $1.amount : -$1.amount) }
    }

    private var hasData: Bool { !transactions.isEmpty }

    private var currentMonth: Int { cal.component(.month, from: Date()) }
    private var currentYear: Int { cal.component(.year, from: Date()) }

    private var currentBudgets: [BudgetEntity] {
        budgets.filter { Int($0.month) == currentMonth && Int($0.year) == currentYear }
    }

    private var totalBudget: Double {
        currentBudgets.reduce(0) { $0 + $1.amount }
    }

    // Top 5 most-used expense categories across all time
    private var topCategories: [CategoryEntity] {
        var counts: [CategoryEntity: Int] = [:]
        for tx in transactions where !tx.isIncome {
            guard let cat = tx.category else { continue }
            counts[cat, default: 0] += 1
        }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return ($0.key.name ?? "") < ($1.key.name ?? "")
        }.prefix(5).map(\.key)
    }

    private var hasBudget: Bool { totalBudget > 0 }

    /// (category, total, count) for this month's expenses, sorted desc.
    private var spendingByCategory: [(CategoryEntity, Double, Int)] {
        var map: [CategoryEntity: (Double, Int)] = [:]
        for tx in thisMonthTx where !tx.isIncome {
            guard let c = tx.category else { continue }
            map[c, default: (0, 0)].0 += tx.amount
            map[c, default: (0, 0)].1 += 1
        }
        return map.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    /// Normalised cumulative spending per elapsed day of the month.
    private var trendPoints: [Double] {
        let day = cal.component(.day, from: Date())
        guard day > 0 else { return [] }
        var cumulative = [Double](repeating: 0, count: day)
        for tx in thisMonthTx where !tx.isIncome {
            let d = cal.component(.day, from: tx.date ?? Date())
            for i in (d - 1)..<day where i >= 0 { cumulative[i] += tx.amount }
        }
        let denom = max(totalBudget > 0 ? totalBudget : (cumulative.last ?? 1), 1)
        return cumulative.map { min($0 / denom, 1) }
    }

    private var todayFraction: Double {
        let range = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return Double(cal.component(.day, from: Date())) / Double(range)
    }

    /// Daily running balance over the last 30 days for the accounts sparkline.
    private var balanceSparkPoints: [Double] {
        let days = 30
        let now = Date()
        var result: [Double] = []
        var running = 0.0
        for d in (0..<days).reversed() {
            guard let day = cal.date(byAdding: .day, value: -d, to: now) else { continue }
            for tx in transactions {
                guard let txDate = tx.date, cal.isDate(txDate, inSameDayAs: day) else { continue }
                running += tx.isIncome ? tx.amount : -tx.amount
            }
            result.append(running)
        }
        return result.isEmpty ? [0, 0] : result
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    hero
                    if hasData { trendLine }
                    budgetSection
                    if hasData && !spendingByCategory.isEmpty { spendingSection }
                    accountsSection
                    recentSection
                    notificationsRow
                    customizeButton
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 60) }
            .scrollDisabled(showQuickCategories || isTouchingPlus)
            .allowsHitTesting(!isTouchingPlus)

            ProgressiveBlurView(height: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
            }

            BottomScrim(height: 60)

            // Dimming overlay — blocks all interaction, tap to dismiss
            if showQuickCategories {
                Color.black.opacity(0.88)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .gesture(DragGesture(minimumDistance: 0))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showQuickCategories = false
                        }
                        hoveredCategory = nil
                        categoriesReady = false
                        longPressTask?.cancel()
                        longPressTask = nil
                    }
            }

            floatingButtons
        }
        .fullScreenCover(isPresented: $showAddTransaction) { AddTransactionView() }
        .fullScreenCover(isPresented: $showNeedsReview) { NeedsReviewView() }
        .sheet(isPresented: $showAllTransactions) { TransactionsListView() }
        .sheet(isPresented: $showStatistics) { StatisticsView() }
        .sheet(isPresented: $showBudgets) { BudgetsView() }
        .sheet(isPresented: $showAddBudget) { AddBudgetView() }
        .sheet(isPresented: $showCategories) { CategoriesView() }
        .fullScreenCover(item: $selectedCategory) { cat in
            CategoryDetailView(category: cat)
        }
        .sheet(item: $selectedTx) { tx in
            TransactionDetailSheet(transaction: tx)
        }
        .sheet(item: $quickCategory) { cat in
            AddTransactionView(preselectedCategory: cat)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            SpaceChip(title: "Personal") { showCategories = true }
            Spacer()
            GlassIconButton(systemName: "wallet.bifold") {
                if currentBudgets.isEmpty { showAddBudget = true } else { showBudgets = true }
            }
            GlassIconButton(systemName: "chart.bar.fill") { showStatistics = true }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 6) {
            Text("Total spent in \(monthName)")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text(Theme.money(totalSpentThisMonth))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(.top, 40)
        .padding(.bottom, 4)
    }

    private var trendLine: some View {
        SpendingTrendLine(
            points: trendPoints,
            todayFraction: todayFraction,
            totalBudget: totalBudget,
            totalSpent: totalSpentThisMonth
        )
        .frame(height: 110)
        .padding(.horizontal, -20)
    }

    // MARK: Budget

    @ViewBuilder private var budgetSection: some View {
        if hasBudget {
            SurfaceCard {
                HStack(spacing: 16) {
                    ZStack {
                        ProgressRing(progress: totalSpentThisMonth / totalBudget)
                        Text("\(Int((totalSpentThisMonth / totalBudget * 100).rounded()))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(budgetTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Text(budgetSubtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(18)
            }
        } else {
            SurfaceCard {
                VStack(spacing: 16) {
                    Text("Create a budget for this space to stay on top of your finances")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    OutlinePillButton(title: "Create budget") { showAddBudget = true }
                }
                .padding(24)
            }
        }
    }

    private var budgetTitle: String {
        let diff = totalSpentThisMonth - totalBudget
        return diff > 0 ? "\(Theme.money(diff)) over budget"
                        : "\(Theme.money(-diff)) left"
    }

    private var budgetSubtitle: String {
        totalSpentThisMonth <= totalBudget
            ? "Well under pace. You've built a strong cushion."
            : "You're spending faster than planned."
    }

    // MARK: Spending by category

    private var spendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Spending by category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(spendingByCategory, id: \.0.id) { cat, total, _ in
                        CategorySpendCard(
                            category: cat,
                            spent: total,
                            budget: categoryBudget(for: cat)
                        )
                        .onTapGesture { selectedCategory = cat }
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -20)
        }
    }

    private func categoryBudget(for cat: CategoryEntity) -> Double? {
        currentBudgets.first(where: { $0.category == cat })?.amount
    }

    // MARK: Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Accounts")
            SurfaceCard {
                VStack(spacing: 0) {
                    // Total row with sparkline
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Total")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary)
                            Text(Theme.money(netBalance))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        Spacer()
                        MiniSparkline(points: balanceSparkPoints, color: Theme.accent)
                            .frame(width: 100, height: 44)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)

                    if hasData {
                        Divider().background(Theme.cardStroke)
                        accountRow(icon: "person.fill", color: Theme.accent, name: "Personal", balance: netBalance)
                    }
                }
            }
        }
    }

    private func accountRow(icon: String, color: Color, name: String, balance: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(name)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
            Text(Theme.money(balance))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Needs review

    private var uncategorizedTx: [TransactionEntity] {
        transactions.filter { $0.category == nil }
    }

    // MARK: Recent transactions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent transactions")

            if transactions.isEmpty {
                SurfaceCard {
                    Text("Use the buttons below to add your first transaction")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            } else {
                SurfaceCard {
                    VStack(spacing: 0) {
                        // Needs review row at top
                        if !uncategorizedTx.isEmpty {
                            let income = uncategorizedTx.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
                            let expense = uncategorizedTx.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
                            Button { showNeedsReview = true } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(uncategorizedTx.count) transactions need review")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                        HStack(spacing: 12) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.right")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.black)
                                                    .frame(width: 16, height: 16)
                                                    .background(Color.white, in: .circle)
                                                Text(Theme.money(expense))
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.down.left")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.black)
                                                    .frame(width: 16, height: 16)
                                                    .background(Color.white, in: .circle)
                                                Text(Theme.money(income))
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(16)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Theme.cardStroke)
                        }

                        let recent = Array(transactions.prefix(3))
                        ForEach(Array(recent.enumerated()), id: \.element.id) { idx, tx in
                            TransactionRow(transaction: tx)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTx = tx }
                            if idx < recent.count - 1 {
                                Divider().background(Theme.cardStroke).padding(.leading, 64)
                            }
                        }
                        Divider().background(Theme.cardStroke)
                        Button { showAllTransactions = true } label: {
                            HStack {
                                Text("View all")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Notifications

    private var notificationsRow: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Notifications")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Get reminders for recurring payments.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
        }
    }

    private var customizeButton: some View {
        OutlinePillButton(title: "Customize widgets", systemImage: "square.grid.2x2")
            .frame(maxWidth: .infinity)
    }

    // MARK: Floating buttons

    private var floatingButtons: some View {
        VStack {
            Spacer()
            ZStack(alignment: .bottom) {
                // Category pills centered above + button
                if showQuickCategories {
                    VStack(alignment: .center, spacing: 10) {
                        ForEach(Array(topCategories.enumerated()), id: \.element.id) { idx, cat in
                            QuickCategoryPill(
                                cat: cat,
                                isHovered: hoveredCategory?.id == cat.id,
                                insertionDelay: Double(idx) * 0.06,
                                removalDelay: Double(topCategories.count - 1 - idx) * 0.04,
                                onFrameChange: { frame in
                                    if let id = cat.id { pillFrames[id] = frame }
                                }
                            )
                        }
                    }
                    .fixedSize()
                    .padding(.bottom, 88)
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        floatingButton(systemName: "viewfinder") { }

                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: .circle)
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { value in
                                        if !showQuickCategories {
                                            if longPressTask == nil {
                                                isTouchingPlus = true
                                                longPressTask = Task {
                                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                                    guard !Task.isCancelled else { return }
                                                    await MainActor.run {
                                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                            showQuickCategories = true
                                                        }
                                                    }
                                                                    // Wait for animation to finish before tracking hover
                                                    try? await Task.sleep(nanoseconds: 450_000_000)
                                                    guard !Task.isCancelled else { return }
                                                    await MainActor.run {
                                                        categoriesReady = true
                                                        // Check if finger is already over a pill
                                                        let loc = lastDragLocation
                                                        let found = topCategories.first { cat in
                                                            guard let id = cat.id, let frame = pillFrames[id] else { return false }
                                                            return frame.contains(loc)
                                                        }
                                                        if let found {
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                            hoveredCategory = found
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            lastDragLocation = value.location
                                            if categoriesReady {
                                                let found = topCategories.first { cat in
                                                    guard let id = cat.id, let frame = pillFrames[id] else { return false }
                                                    return frame.contains(value.location)
                                                }
                                                if found?.id != hoveredCategory?.id {
                                                    if found != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                                                    hoveredCategory = found
                                                }
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        if showQuickCategories {
                                            // Finger lifted while categories shown — select hovered
                                            let selected = hoveredCategory
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                showQuickCategories = false
                                            }
                                            hoveredCategory = nil
                                            categoriesReady = false
                                            isTouchingPlus = false
                                            longPressTask?.cancel()
                                            longPressTask = nil
                                            if let cat = selected {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                    quickCategory = cat
                                                }
                                            }
                                        } else {
                                            // Short tap — cancel timer and open add transaction
                                            longPressTask?.cancel()
                                            longPressTask = nil
                                            categoriesReady = false
                                            isTouchingPlus = false
                                            showAddTransaction = true
                                        }
                                    }
                            )
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func floatingButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

private struct QuickCategoryPill: View {
    let cat: CategoryEntity
    let isHovered: Bool
    let insertionDelay: Double
    let removalDelay: Double
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        HStack(spacing: 10) {
            CategoryAvatar(
                colorHex: cat.colorHex ?? "#888",
                systemName: cat.icon ?? "tag.fill",
                size: 36
            )
            Text(cat.name ?? "")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if isHovered {
                Capsule().fill(Color.white.opacity(0.2))
            }
        }
        .glassEffect(.regular, in: .capsule)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { onFrameChange(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { onFrameChange($0) }
        })
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity)
                .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(insertionDelay)),
            removal: .move(edge: .bottom).combined(with: .opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.8).delay(removalDelay))
        ))
    }
}
