import SwiftUI

struct AmountText: View {
    let amount: Double
    let isIncome: Bool

    var body: some View {
        Text("\(isIncome ? "+" : "-") \(Theme.money(amount))")
            .font(.system(.body).bold())
            .foregroundColor(isIncome ? .green : .red)
    }
}
