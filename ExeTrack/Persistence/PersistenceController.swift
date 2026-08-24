import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// True when the on-disk store could not be opened and the app is running
    /// against memory only, so nothing the user adds will survive a relaunch.
    private(set) var failedToLoadStore = false

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ExeTrack")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        // Let Core Data migrate itself when the model changes in a later release.
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { [weak container] _, error in
            guard let error = error as NSError? else { return }
            // A corrupt or unmigratable store used to call fatalError, which
            // meant the app could never launch again. Fall back to memory so it
            // still opens; the file on disk is left alone for recovery.
            NSLog("[ExeTrack] Persistent store failed to load: \(error), \(error.userInfo)")
            self.failedToLoadStore = true
            guard let container else { return }
            let fallback = NSPersistentStoreDescription()
            fallback.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [fallback]
            container.loadPersistentStores { _, fallbackError in
                if let fallbackError {
                    NSLog("[ExeTrack] In-memory fallback also failed: \(fallbackError)")
                }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        seedDefaultCategories()
    }

    private func seedDefaultCategories() {
        let context = container.viewContext
        let request: NSFetchRequest<CategoryEntity> = CategoryEntity.fetchRequest()
        guard (try? context.count(for: request)) == 0 else { return }

        // name, icon, colorHex, isIncome, group
        // name, icon (SF Symbols), colorHex, isIncome, group
        let defaults: [(String, String, String, Bool, String)] = [
            // Everyday Spending — warm food palette
            ("Groceries",        "cart.fill",               "#30D158", false, "Everyday Spending"),
            ("Restaurants",      "fork.knife",              "#FF9F0A", false, "Everyday Spending"),
            ("Food delivery",    "bag.fill",                "#FF453A", false, "Everyday Spending"),
            ("Coffee",           "cup.and.saucer.fill",     "#AC8E68", false, "Everyday Spending"),
            // Transport — blue/grey/yellow
            ("Public transport", "bus.fill",                "#0A84FF", false, "Transport"),
            ("Car",              "car.fill",                "#98989D", false, "Transport"),
            ("Fuel",             "fuelpump.fill",           "#FF6B00", false, "Transport"),
            ("Taxi",             "car.fill",                "#FFD60A", false, "Transport"),
            // Living — purple/indigo
            ("Utilities",        "house.fill",              "#6E6CD8", false, "Living"),
            ("Rent",             "building.2.fill",         "#BF5AF2", false, "Living"),
            ("Internet",         "wifi",                    "#32ADE6", false, "Living"),
            // Health & Fitness — red/pink/green
            ("Health",           "heart.fill",              "#FF3B30", false, "Health & Fitness"),
            ("Gym",              "bolt.heart.fill",         "#FF2D55", false, "Health & Fitness"),
            ("Pharmacy",         "cross.case.fill",         "#34C759", false, "Health & Fitness"),
            // Entertainment — violet/pink/cyan
            ("Entertainment",    "gamecontroller.fill",     "#BF5AF2", false, "Entertainment"),
            ("Subscriptions",    "play.rectangle.fill",     "#FF375F", false, "Entertainment"),
            ("Travel",           "airplane",                "#5AC8FA", false, "Entertainment"),
            // Shopping — orange/blue
            ("Shopping",         "handbag.fill",            "#FF9500", false, "Shopping"),
            ("Electronics",      "laptopcomputer",          "#007AFF", false, "Shopping"),
            // Money moving without being spent — lending and borrowing are
            // everyday here, and with no category for them the classifier is
            // forced to file a qarz as Shopping.
            ("Debt",             "arrow.left.arrow.right",  "#8E8E93", false, "Other"),
            ("Savings",          "banknote.fill",           "#64D2FF", false, "Other"),
            // Income — green palette
            ("Salary",           "briefcase.fill",          "#30D158", true,  "Income"),
            ("Freelance",        "laptopcomputer",          "#5AC8FA", true,  "Income"),
            ("Investment",       "chart.bar.fill",          "#34C759", true,  "Income"),
            ("Gift",             "gift.fill",               "#FF9F0A", true,  "Income"),
            ("Loan received",    "arrow.left.arrow.right",  "#8E8E93", true,  "Income"),
        ]

        for (name, icon, color, isIncome, group) in defaults {
            let cat = CategoryEntity(context: context)
            cat.id = UUID()
            cat.name = name
            cat.icon = icon
            cat.isIncome = isIncome
            cat.colorHex = color
            cat.group = group
        }

        try? context.save()
    }

    static var preview: PersistenceController = {
        let ctrl = PersistenceController(inMemory: true)
        let ctx = ctrl.container.viewContext

        let cat = CategoryEntity(context: ctx)
        cat.id = UUID()
        cat.name = "Food"
        cat.icon = "fork.knife"
        cat.isIncome = false
        cat.colorHex = "#FF3B30"

        let tx = TransactionEntity(context: ctx)
        tx.id = UUID()
        tx.amount = 1500
        tx.note = "Lunch"
        tx.date = Date()
        tx.isIncome = false
        tx.category = cat

        try? ctx.save()
        return ctrl
    }()
}
