import SwiftUI
import Charts

struct StatisticsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
    ) private var transactions: FetchedResults<TransactionEntity>

    @State private var selectedPeriod: Period = .month

    enum Period: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    var filtered: [TransactionEntity] {
        let now = Date()
        let cal = Calendar.current
        return transactions.filter { tx in
            guard let date = tx.date else { return false }
            switch selectedPeriod {
            case .week:  return cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case .month: return cal.isDate(date, equalTo: now, toGranularity: .month)
            case .year:  return cal.isDate(date, equalTo: now, toGranularity: .year)
            }
        }
    }

    var totalIncome: Double { filtered.filter { $0.isIncome }.reduce(0) { $0 + $1.amount } }
    var totalExpense: Double { filtered.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount } }

    var expenseByCategory: [(String, Double, String)] {
        var dict: [String: (Double, String)] = [:]
        for tx in filtered where !tx.isIncome {
            let key = tx.category?.name ?? "Other"
            let color = tx.category?.colorHex ?? "#888"
            dict[key, default: (0, color)].0 += tx.amount
        }
        return dict.map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1 > $1.1 }
    }

    var dailyData: [(Date, Double, Double)] {
        let cal = Calendar.current
        var dict: [Date: (Double, Double)] = [:]
        for tx in filtered {
            guard let date = tx.date else { continue }
            let day = cal.startOfDay(for: date)
            if tx.isIncome {
                dict[day, default: (0, 0)].0 += tx.amount
            } else {
                dict[day, default: (0, 0)].1 += tx.amount
            }
        }
        return dict.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        SummaryCard(title: "Income", amount: totalIncome, color: .green)
                        SummaryCard(title: "Expenses", amount: totalExpense, color: .red)
                    }
                    .padding(.horizontal)

                    if !dailyData.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trend").font(.headline).padding(.horizontal)
                            Chart {
                                ForEach(dailyData, id: \.0) { day, income, expense in
                                    LineMark(
                                        x: .value("Day", day),
                                        y: .value("Income", income)
                                    )
                                    .foregroundStyle(.green)
                                    .symbol(.circle)

                                    LineMark(
                                        x: .value("Day", day),
                                        y: .value("Expense", expense)
                                    )
                                    .foregroundStyle(.red)
                                    .symbol(.square)
                                }
                            }
                            .frame(height: 200)
                            .padding(.horizontal)
                        }
                    }

                    if !expenseByCategory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Spending by category").font(.headline).padding(.horizontal)
                            Chart(expenseByCategory, id: \.0) { name, amount, colorHex in
                                SectorMark(
                                    angle: .value("Amount", amount),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color(hex: colorHex))
                                .annotation(position: .overlay) {
                                    Text(name).font(.caption2).foregroundStyle(.white)
                                }
                            }
                            .frame(height: 260)
                            .padding(.horizontal)

                            ForEach(expenseByCategory, id: \.0) { name, amount, colorHex in
                                HStack {
                                    Circle().fill(Color(hex: colorHex)).frame(width: 10, height: 10)
                                    Text(name)
                                    Spacer()
                                    Text(Theme.money(amount))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Statistics")
        }
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Theme.money(amount))
                .font(.system(.title3).bold())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}
