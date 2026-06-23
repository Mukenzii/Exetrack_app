import SwiftUI
import CoreData

struct CategoriesView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)],
        animation: .default
    ) private var categories: FetchedResults<CategoryEntity>

    @State private var showAdd = false
    @State private var editTarget: CategoryEntity?

    var body: some View {
        NavigationStack {
            List {
                Section("Expenses") {
                    ForEach(categories.filter { !$0.isIncome }, id: \.id) { cat in
                        NavigationLink(destination: CategoryDetailView(category: cat)) {
                            CategoryRow(category: cat)
                        }
                    }
                    .onDelete { delete(from: categories.filter { !$0.isIncome }, at: $0) }
                }
                Section("Income") {
                    ForEach(categories.filter { $0.isIncome }, id: \.id) { cat in
                        NavigationLink(destination: CategoryDetailView(category: cat)) {
                            CategoryRow(category: cat)
                        }
                    }
                    .onDelete { delete(from: categories.filter { $0.isIncome }, at: $0) }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { EditCategoryView() }
            .sheet(item: $editTarget) { EditCategoryView(category: $0) }
        }
        .preferredColorScheme(.dark)
    }

    private func delete(from list: [CategoryEntity], at offsets: IndexSet) {
        offsets.forEach { context.delete(list[$0]) }
        try? context.save()
    }
}

struct CategoryRow: View {
    let category: CategoryEntity

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: category.colorHex ?? "#888").opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: category.icon ?? "questionmark")
                    .foregroundColor(Color(hex: category.colorHex ?? "#888"))
            }
            Text(category.name ?? "")
            Spacer()
            Text(category.isIncome ? "Income" : "Expense")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
