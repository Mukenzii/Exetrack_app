import SwiftUI

// MARK: - Draft card

/// A single proposed expense: everything on it is editable in place, so the
/// user can accept the reading, correct it, or drop the row entirely.
struct ExpenseDraftCard: View {
    @Binding var draft: ExpenseDraft
    var onPickCategory: () -> Void
    var onPickDate: () -> Void
    var onChooseAlternative: (CategoryEntity) -> Void
    var onCreateProposed: () -> Void
    var onRemove: () -> Void

    @AppStorage("accentColorHex") private var accentColorHex = "#2D5BE3"

    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool

    private var dateLabel: String {
        if Calendar.current.isDateInToday(draft.date) { return "Today" }
        if Calendar.current.isDateInYesterday(draft.date) { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM"
        return f.string(from: draft.date)
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                amountRow
                metaRow
                if draft.proposedCategory != nil {
                    createProposedRow
                }
                if !draft.alternatives.isEmpty {
                    alternativesRow
                }
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(draft.isIncome ? "Income" : "Expense"), \(Theme.money(draft.amount)), "
            + "\(draft.category?.name ?? "no category yet")"
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onPickCategory) {
                HStack(spacing: 10) {
                    CategoryAvatar(
                        colorHex: draft.category?.colorHex ?? "#3A3A3C",
                        systemName: draft.category?.icon ?? "questionmark",
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.category?.name ?? "Pick a category")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(draft.isIncome ? "Income" : "Expense")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Category: \(draft.category?.name ?? "not set"). Double tap to change.")

            Spacer(minLength: 8)

            if draft.needsAttention {
                Text("Check")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#FF9F0A"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#FF9F0A").opacity(0.15), in: Capsule())
                    .accessibilityLabel("Low confidence, please check")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this expense")
        }
    }

    /// Shown when nothing in the user's list fitted. Naming the category that
    /// should exist, and making it one tap, beats leaving them with a blank.
    @ViewBuilder
    private var createProposedRow: some View {
        if let proposal = draft.proposedCategory {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing fits this one")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)

                Button(action: onCreateProposed) {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                            .background(Color.white, in: .circle)
                        Text("Create \u{201C}\(proposal.name)\u{201D}")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: proposal.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create a new category called \(proposal.name) and use it here")
            }
        }
    }

    /// The classifier's runner-up categories. Correcting a wrong guess should
    /// be one tap, not a trip through the full picker.
    private var alternativesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draft.alternatives, id: \.objectID) { category in
                        Button { onChooseAlternative(category) } label: {
                            HStack(spacing: 7) {
                                CategoryAvatar(
                                    colorHex: category.colorHex ?? "#888",
                                    systemName: category.icon ?? "tag.fill",
                                    size: 22
                                )
                                Text(category.name ?? "")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 12)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change category to \(category.name ?? "")")
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(draft.isIncome ? "+" : "−")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(draft.isIncome ? Color(hex: "#30D158") : .white)

            GroupedAmountField(amount: $draft.amount)
                .focused($amountFocused)

            Text(Theme.currency)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { amountFocused = true }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            TextField("Add a note", text: $draft.note)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Color(hex: accentColorHex))
                .focused($noteFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: Capsule())
                .accessibilityLabel("Note")

            Button(action: onPickDate) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                    Text(dateLabel)
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date: \(dateLabel). Double tap to change.")
        }
    }
}

// MARK: - Amount field with live thousands grouping

/// Numeric field that keeps the app's "45 000" grouping while you type.
struct GroupedAmountField: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#2D5BE3"
    @Binding var amount: Double
    @State private var text = ""

    var body: some View {
        TextField("0", text: $text)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.white)
            .tint(Color(hex: accentColorHex))
            .keyboardType(.numberPad)
            .fixedSize(horizontal: true, vertical: false)
            .onAppear { text = Theme.amount(amount) }
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)
                let value = Double(digits) ?? 0
                amount = value
                let formatted = digits.isEmpty ? "" : Theme.amount(value)
                if formatted != new { text = formatted }
            }
            .accessibilityLabel("Amount")
            .accessibilityValue(Theme.money(amount))
    }
}

// MARK: - Voice waveform

/// Live microphone level meter. Bars animate from the centre outwards.
struct VoiceWaveform: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#2D5BE3"
    let levels: [CGFloat]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 4
            let barWidth = max((geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 2)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Color(hex: accentColorHex))
                        .frame(width: barWidth, height: max(geo.size.height * level, 3))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .linear(duration: 0.08), value: levels)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shimmer placeholder

private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        guard active else { return AnyView(content) }
        return AnyView(
            content
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.10), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .scaleEffect(x: 0.4, anchor: .leading)
                    .offset(x: phase * 400)
                    .blendMode(.plusLighter)
                )
                .mask(content)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 2
                    }
                }
        )
    }
}

extension View {
    func shimmer(active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}
