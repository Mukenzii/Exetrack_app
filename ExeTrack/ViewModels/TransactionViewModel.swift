import CoreData
import SwiftUI

class TransactionViewModel: ObservableObject {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func add(amount: Double, note: String, isIncome: Bool, category: CategoryEntity?, date: Date) {
        let tx = TransactionEntity(context: context)
        tx.id = UUID()
        tx.amount = amount
        tx.note = note
        tx.isIncome = isIncome
        tx.category = category
        tx.date = date
        save()
    }

    func delete(_ tx: TransactionEntity) {
        context.delete(tx)
        save()
    }

    private func save() {
        try? context.save()
    }
}
