import SwiftUI
import CoreData

struct ManageCategoryBudgetsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
    ) private var categories: FetchedResults<CategoryEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetEntity.month, ascending: true)]
    ) private var budgets: FetchedResults<BudgetEntity>

    @State private var selectedCategory: CategoryEntity? = nil
    @State private var localAmounts: [UUID: Double] = [:]

    private var vm: BudgetViewModel { BudgetViewModel(context: context) }

    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var overallBudget: Double {
        budgets.first { $0.category == nil && Int($0.month) == currentMonth && Int($0.year) == currentYear }?.amount ?? 0
    }

    private var expenseCategories: [CategoryEntity] {
        categories.filter { !$0.isIncome }
    }

    private var totalAllocated: Double {
        expenseCategories.reduce(0.0) { sum, cat in
            sum + (localAmounts[cat.id ?? UUID()] ?? 0)
        }
    }

    private var allocationProgress: Double {
        overallBudget > 0 ? min(totalAllocated / overallBudget, 1.0) : 0
    }

    private var allocationColor: Color {
        totalAllocated > overallBudget ? .red : totalAllocated > overallBudget * 0.9 ? .orange : Color(hex: "#30D158")
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

                    Text("Manage Categories")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        withAnimation {
                            expenseCategories.forEach { cat in
                                guard let id = cat.id else { return }
                                localAmounts[id] = 0
                            }
                        }
                    } label: {
                        Text("Reset")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

                // Allocation progress card
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Theme.money(totalAllocated))
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), value: totalAllocated)
                            Text("of \(Theme.money(overallBudget)) allocated")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(allocationProgress * 100))%")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(allocationColor)
                            .contentTransition(.numericText())
                            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), value: allocationProgress)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                            Capsule().fill(allocationColor)
                                .frame(width: geo.size.width * allocationProgress, height: 6)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: allocationProgress)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Theme.cardStroke, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // AI Suggest button
                Button {
                    suggestAllocations()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                        Text("AI Suggest")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                }
                .glassEffect(.regular.tint(Theme.accent.opacity(0.3)).interactive(), in: .capsule)
                .padding(.vertical, 10)

                // Category list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(expenseCategories.enumerated()), id: \.element.id) { i, cat in
                            let catId = cat.id ?? UUID()
                            let amount = localAmounts[catId] ?? 0

                            VStack(spacing: 0) {
                                if i > 0 {
                                    Divider()
                                        .background(Color.white.opacity(0.07))
                                        .padding(.horizontal, 20)
                                }

                                Button {
                                    selectedCategory = cat
                                } label: {
                                    HStack(spacing: 14) {
                                        CategoryAvatar(
                                            colorHex: cat.colorHex ?? "#888",
                                            systemName: cat.icon ?? "tag.fill",
                                            size: 42
                                        )

                                        Text(cat.name ?? "")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        if amount > 0 {
                                            Text(Theme.money(amount))
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(.white)
                                                .contentTransition(.numericText())
                                                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), value: amount)
                                        } else {
                                            Text("No limit")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Theme.textSecondary)
                                        }

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Theme.cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }

                Spacer(minLength: 0)
            }

            // Save button (floating)
            VStack {
                Spacer()
                Button { save() } label: {
                    Text("Save")
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
        .sheet(item: $selectedCategory) { cat in
            let catId = cat.id ?? UUID()
            SetCategoryLimitView(
                category: cat,
                prefill: localAmounts[catId] ?? 0
            ) { newAmount in
                withAnimation { localAmounts[catId] = newAmount }
            }
        }
        .onAppear { loadExistingAmounts() }
        .preferredColorScheme(.dark)
    }

    private func loadExistingAmounts() {
        for budget in budgets where budget.category != nil {
            guard Int(budget.month) == currentMonth, Int(budget.year) == currentYear,
                  let id = budget.category?.id else { continue }
            localAmounts[id] = budget.amount
        }
    }

    private func save() {
        for cat in expenseCategories {
            guard let id = cat.id, let amount = localAmounts[id], amount > 0 else { continue }
            vm.upsert(amount: amount, category: cat, month: currentMonth, year: currentYear)
        }
        dismiss()
    }

    private func suggestAllocations() {
        guard overallBudget > 0, !expenseCategories.isEmpty else { return }
        let perCategory = overallBudget / Double(expenseCategories.count)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            expenseCategories.forEach { cat in
                guard let id = cat.id else { return }
                localAmounts[id] = (perCategory / 1000).rounded() * 1000
            }
        }
    }
}
