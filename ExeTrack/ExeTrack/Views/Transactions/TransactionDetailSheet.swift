import SwiftUI
import CoreData

struct TransactionDetailSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let transaction: TransactionEntity

    @State private var showCategoryPicker = false
    @State private var selectedCategory: CategoryEntity?

    private var vm: TransactionViewModel { TransactionViewModel(context: context) }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header buttons
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                Spacer()
                Button { } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.trailing, 8)
                Button {
                    context.delete(transaction)
                    try? context.save()
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Amount + icon
            VStack(spacing: 12) {
                CategoryAvatar(
                    colorHex: transaction.category?.colorHex ?? "#3A3A3C",
                    systemName: transaction.category?.icon ?? "questionmark",
                    size: 64
                )

                Text("\(transaction.isIncome ? "+" : "")\(Theme.money(transaction.amount))")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(transaction.isIncome ? Color.green : .white)
            }
            .padding(.top, 20)
            .padding(.bottom, 28)

            // Category select button (if uncategorized)
            if transaction.category == nil {
                Button { showCategoryPicker = true } label: {
                    Text("Select category")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Details card
            VStack(spacing: 0) {
                detailRow(icon: "calendar", label: "Date", value: formatted(transaction.date ?? Date()))
                Divider().background(Color.white.opacity(0.07)).padding(.leading, 52)
                detailRow(icon: "arrow.left.arrow.right", label: "Type", value: transaction.isIncome ? "Income" : "Expense")
                Divider().background(Color.white.opacity(0.07)).padding(.leading, 52)

                if let cat = transaction.category {
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28)
                        Text("Category")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        CategoryAvatar(colorHex: cat.colorHex ?? "#888", systemName: cat.icon ?? "tag.fill", size: 24)
                        Text(cat.name ?? "")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    Divider().background(Color.white.opacity(0.07)).padding(.leading, 52)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28)
                        Text("Category")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("Uncategorized")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    Divider().background(Color.white.opacity(0.07)).padding(.leading, 52)
                }

                detailRow(icon: "building.columns", label: "Account", valueView: AnyView(
                    HStack(spacing: 6) {
                        Text("A")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text("Abusha")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                ))
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            )
            .padding(.horizontal, 16)

            Spacer()
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(420), .height(560)])
        .presentationBackground {
            ZStack {
                Color(hex: "#161618")
                if let hex = transaction.category?.colorHex {
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: hex).opacity(0.25), location: 0),
                            .init(color: Color(hex: hex).opacity(0.06), location: 0.45),
                            .init(color: .clear, location: 0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(isIncome: transaction.isIncome, selected: Binding(
                get: { transaction.category },
                set: { cat in
                    transaction.category = cat
                    try? context.save()
                    if let cat, let merchant = transaction.note, !merchant.isEmpty {
                        reportCategorization(merchant: merchant, category: cat)
                    }
                    dismiss()
                }
            ))
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func detailRow(icon: String, label: String, valueView: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            valueView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func reportCategorization(merchant: String, category: CategoryEntity) {
        let backendURL = Config.backendURL
        guard let url = URL(string: "\(backendURL)/categorize") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "tx_id":     0,
            "merchant":  merchant.uppercased(),
            "category":  category.name ?? "",
            "icon":      category.icon ?? "tag.fill",
            "color_hex": category.colorHex ?? "#888888",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}
