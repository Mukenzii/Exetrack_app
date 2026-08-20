import CoreData
import SwiftUI

class BudgetViewModel: ObservableObject {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func upsert(amount: Double, category: CategoryEntity, month: Int, year: Int) {
        let request: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "category == %@ AND month == %d AND year == %d",
            category, month, year
        )
        let existing = (try? context.fetch(request))?.first
        let budget = existing ?? BudgetEntity(context: context)
        if existing == nil {
            budget.id = UUID()
            budget.category = category
            budget.month = Int32(month)
            budget.year = Int32(year)
        }
        budget.amount = amount
        try? context.save()
    }

    func spent(for category: CategoryEntity, month: Int, year: Int, transactions: [TransactionEntity]) -> Double {
        transactions
            .filter {
                !$0.isIncome &&
                $0.category == category &&
                Calendar.current.component(.month, from: $0.date ?? Date()) == month &&
                Calendar.current.component(.year, from: $0.date ?? Date()) == year
            }
            .reduce(0) { $0 + $1.amount }
    }
}
