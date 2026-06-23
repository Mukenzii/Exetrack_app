import SwiftUI
import CoreData

struct AddTransactionView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    var preselectedCategory: CategoryEntity? = nil

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
    ) private var categories: FetchedResults<CategoryEntity>

    @State private var expr = "0"
    @State private var isIncome = false
    @State private var selectedCategory: CategoryEntity?
    @State private var date = Date()
    @State private var note = ""
    @State private var showCategoryPicker = false
    @State private var showDatePicker = false
    @State private var showNotes = false

    private var dateLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private var vm: TransactionViewModel { TransactionViewModel(context: context) }

    // MARK: Calculator

    private var evaluated: Double {
        let normalized = expr
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        // Strip a trailing operator before evaluating.
        let trimmed = normalized.last.map { "+-*/".contains($0) } == true
            ? String(normalized.dropLast()) : normalized
        guard !trimmed.isEmpty else { return 0 }
        let ex = NSExpression(format: trimmed)
        return (ex.expressionValue(with: nil, context: nil) as? NSNumber)?.doubleValue ?? 0
    }

    /// Inserts spaces every 3 digits from the right (integer part only).
    private func groupDigits(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i != 0 && i % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return String(out.reversed())
    }

    private var displayString: String {
        // Plain number → grouped; expression with operators → show as typed.
        if expr.rangeOfCharacter(from: CharacterSet(charactersIn: "+−×÷")) == nil {
            let parts = expr.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            let intPart = groupDigits(String(parts[0]))
            return parts.count == 2 ? intPart + "," + String(parts[1]) : intPart
        }
        return expr
    }

    private var canSave: Bool { evaluated > 0 }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0C").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                accountCurrencyRow
                    .padding(.top, 18)
                Spacer()
                amountDisplay
                Spacer()
                keypadPanel
                bottomBar
                    .padding(.top, 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 100 &&
                        abs(value.translation.width) < value.translation.height {
                        dismiss()
                    }
                }
        )
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(isIncome: isIncome, selected: $selectedCategory)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(date: $date)
        }
        .sheet(isPresented: $showNotes) {
            NotesSheet(note: $note)
        }
        .onAppear {
            if let cat = preselectedCategory {
                selectedCategory = cat
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            circleButton("xmark") { dismiss() }
            Spacer()
            typeToggle
            Spacer()
            circleButton("ellipsis") { }
        }
    }

    private var typeToggle: some View {
        HStack(spacing: 6) {
            // Expense side
            Button { withAnimation(.spring(duration: 0.25)) { isIncome = false } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isIncome ? Color.white.opacity(0.6) : .black)
                        .frame(width: 28, height: 28)
                        .background(isIncome ? Color.white.opacity(0.18) : Color.white, in: .circle)
                    if !isIncome {
                        Text("Expense")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, isIncome ? 4 : 10)
                .padding(.vertical, 6)
                .background(
                    isIncome ? Color.clear : Color.white.opacity(0.08),
                    in: Capsule()
                )
            }

            // Income side
            Button { withAnimation(.spring(duration: 0.25)) { isIncome = true } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isIncome ? .black : Color.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(isIncome ? Color.white : Color.white.opacity(0.18), in: .circle)
                    if isIncome {
                        Text("Income")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, isIncome ? 10 : 4)
                .padding(.vertical, 6)
                .background(
                    isIncome ? Color.white.opacity(0.08) : Color.clear,
                    in: Capsule()
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: Account + currency

    private var accountCurrencyRow: some View {
        HStack {
            HStack(spacing: 10) {
                Text("A")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Abusha")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white)
                    Text("0 \(Theme.currency)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            HStack(spacing: 6) {
                Text("🇺🇿").font(.system(size: 18))
                Text(Theme.currency)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
        }
    }

    // MARK: Amount

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(displayString)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: displayString)
            Text(Theme.currency)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.3)
        .padding(.horizontal, 8)
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { showDatePicker = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(dateLabel).font(.system(size: 14, weight: .regular))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular, in: .capsule)

            circleButton("arrow.clockwise") { }

            Spacer()

            circleButton(note.isEmpty ? "note.text" : "note.text.badge.plus") { showNotes = true }
        }
    }

    // MARK: Keypad

    private let keys: [[String]] = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        [",", "0", "⌫", "+"]
    ]

    private var keypadPanel: some View {
        VStack(spacing: 14) {
            actionRow
            keypad
        }
        .padding(.top, 10)
        .padding(.horizontal, 0)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(Color(hex: "#0B0B0D"))
        )
    }

    private var keypad: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let available = geo.size.width - gap * 3
            let opW = available * 0.20
            let numW = (available - opW) / 3

            VStack(spacing: gap) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { i in
                            keyButton(row[i], width: numW)
                        }
                        keyButton(row[3], width: opW, dim: true)
                    }
                }
            }
        }
        .frame(height: 54 * 4 + 4 * 3)
    }

    private func keyButton(_ key: String, width: CGFloat, dim: Bool = false) -> some View {
        Button { tap(key) } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18, weight: .regular))
                } else if "÷×−+".contains(key) {
                    Image(systemName: symbolForOperator(key))
                        .font(.system(size: 18, weight: .regular))
                } else {
                    Text(key)
                        .font(.system(size: 24, weight: .regular))
                }
            }
            .foregroundStyle(Color(hex: "#F4F4F4"))
            .frame(width: width, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(dim ? Color(hex: "#141416") : Color(hex: "#1C1C1E"))
            )
        }
        .buttonStyle(.plain)
    }

    private func symbolForOperator(_ key: String) -> String {
        switch key {
        case "÷": return "divide"
        case "×": return "multiply"
        case "−": return "minus"
        case "+": return "plus"
        default:  return "questionmark"
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Button { showCategoryPicker = true } label: {
                HStack(spacing: 10) {
                    if let cat = selectedCategory {
                        CategoryAvatar(
                            colorHex: cat.colorHex ?? "#888",
                            systemName: cat.icon ?? "tag.fill",
                            size: 40
                        )
                        Text(cat.name ?? "")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                    } else {
                        CategoryAvatar(colorHex: "#3A3A3C", systemName: "square.grid.2x2", size: 40)
                        Text("Select category")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .padding(.vertical, 6)
            }
            .background(Color(hex: "#1C1C1E"), in: Capsule())

            Spacer()

            Button { save() } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(canSave ? .black : Theme.textSecondary)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(canSave ? Color.white : Color.white.opacity(0.08))
                    )
            }
            .disabled(!canSave)
        }
    }

    // MARK: Input handling

    private func tap(_ key: String) {
        switch key {
        case "⌫":
            expr = String(expr.dropLast())
            if expr.isEmpty { expr = "0" }
        case "÷", "×", "−", "+":
            if let last = expr.last, "÷×−+".contains(last) {
                expr = String(expr.dropLast()) + key      // replace trailing operator
            } else {
                expr += key
            }
        case ",":
            // only one comma per current operand
            let currentOperand = expr.split(whereSeparator: { "÷×−+".contains($0) }).last ?? ""
            if !currentOperand.contains(",") { expr += "," }
        default: // digit
            if expr == "0" { expr = key } else { expr += key }
        }
    }

    private func save() {
        guard canSave else { return }
        vm.add(amount: evaluated, note: note, isIncome: isIncome, category: selectedCategory, date: date)
        dismiss()
    }
}

// MARK: - Category picker sheet

struct CategoryPickerSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let isIncome: Bool
    @Binding var selected: CategoryEntity?

    @State private var showAddCategory = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
    ) private var categories: FetchedResults<CategoryEntity>

    @State private var isGrid = true
    @State private var search = ""

    private var filtered: [CategoryEntity] {
        let base = categories.filter { $0.isIncome == isIncome }
        if search.isEmpty { return base }
        return base.filter { ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }

    // Group by the `group` attribute; fallback to "Other"
    private var grouped: [(String, [CategoryEntity])] {
        let dict = Dictionary(grouping: filtered) { $0.group ?? "Other" }
        let order = ["Suggested", "Everyday Spending", "Transport", "Living", "Income", "Other"]
        let sorted = dict.keys.sorted {
            let i0 = order.firstIndex(of: $0) ?? 99
            let i1 = order.firstIndex(of: $1) ?? 99
            return i0 < i1
        }
        return sorted.compactMap { key in
            guard let cats = dict[key], !cats.isEmpty else { return nil }
            return (key, cats)
        }
    }

    private let gridCols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)

                    Spacer()
                    Text("Select category")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()

                    Button { withAnimation { isGrid.toggle() } } label: {
                        Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(grouped, id: \.0) { groupName, cats in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(groupName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 4)

                                if isGrid {
                                    LazyVGrid(columns: gridCols, spacing: 0) {
                                        ForEach(cats, id: \.id) { cat in
                                            gridCell(cat)
                                        }
                                    }
                                    .background(Color(hex: "#2C2C2E"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(Array(cats.enumerated()), id: \.element.id) { idx, cat in
                                            listRow(cat, isLast: idx == cats.count - 1)
                                        }
                                    }
                                    .background(Color(hex: "#2C2C2E"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }

            // Pinned bottom area: Add category + search
            VStack(spacing: 8) {
                Button { showAddCategory = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text("Add category")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Search category", text: $search)
                        .foregroundStyle(.white)
                        .tint(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Color(hex: "#161618"))
        }
        .preferredColorScheme(.dark)
        .presentationBackground { Color(hex: "#161618") }
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .sheet(isPresented: $showAddCategory) {
            EditCategoryView()
        }
    }

    @ViewBuilder
    private func gridCell(_ cat: CategoryEntity) -> some View {
        let isSelected = selected?.id == cat.id
        Button {
            selected = cat
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    CategoryAvatar(colorHex: cat.colorHex ?? "#888", systemName: cat.icon ?? "tag.fill", size: 56)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color(hex: "#2F6BFF")))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(cat.name ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func listRow(_ cat: CategoryEntity, isLast: Bool) -> some View {
        let isSelected = selected?.id == cat.id
        Button {
            selected = cat
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CategoryAvatar(colorHex: cat.colorHex ?? "#888", systemName: cat.icon ?? "tag.fill", size: 44)
                Text(cat.name ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)

        if !isLast {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.leading, 70)
        }
    }
}

// MARK: - Date picker sheet (custom calendar)

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date

    @State private var month: Date

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }

    init(date: Binding<Date>) {
        _date = date
        _month = State(initialValue: date.wrappedValue)
    }

    private let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var title: String {
        cal.isDateInToday(date) ? "Today" : formatted(date, "d MMM yyyy")
    }

    private var monthLabel: String { formatted(month, "MMMM yyyy") }

    private func formatted(_ d: Date, _ fmt: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = fmt
        return f.string(from: d)
    }

    /// Day cells for the displayed month, with leading nils for alignment.
    private var days: [Int?] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private func shiftMonth(_ by: Int) {
        if let m = cal.date(byAdding: .month, value: by, to: month) { month = m }
    }

    private func select(_ day: Int) {
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = day
        if let d = cal.date(from: comps) {
            date = d
            dismiss()
        }
    }

    private func isSelected(_ day: Int) -> Bool {
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = day
        guard let d = cal.date(from: comps) else { return false }
        return cal.isDate(d, inSameDayAs: date)
    }

    var body: some View {
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 18)
                }

                HStack {
                    Text(monthLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.white)
                    }
                    .padding(.trailing, 18)
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right").foregroundStyle(.white)
                    }
                }
                .font(.system(size: 15, weight: .medium))

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdays, id: \.self) { wd in
                        Text(wd)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        if let day {
                            Button { select(day) } label: {
                                Text("\(day)")
                                    .font(.system(size: 17))
                                    .foregroundStyle(isSelected(day) ? .black : .white)
                                    .frame(width: 44, height: 44)
                                    .background {
                                        if isSelected(day) { Circle().fill(.white) }
                                    }
                            }
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        .preferredColorScheme(.dark)
        .presentationDetents([.height(500)])
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Notes & tags sheet

struct NotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var note: String
    @State private var draft: String
    @FocusState private var focused: Bool

    init(note: Binding<String>) {
        _note = note
        _draft = State(initialValue: note.wrappedValue)
    }

    var body: some View {
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    Text("Notes and tags")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        note = draft
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                    }
                    .glassEffect(.regular, in: .capsule)
                }

                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Add notes or tags starting with #")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 8)
                    }
                    TextEditor(text: $draft)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        .preferredColorScheme(.dark)
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}
