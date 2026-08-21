import SwiftUI
import UIKit

// MARK: - Main create/edit view

struct EditCategoryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    var category: CategoryEntity?

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var isIncome = false
    @State private var colorHex = "#FF3B30"
    @State private var group = "Other"
    @State private var showIconPicker = false
    @State private var showColorPicker = false

    private var accentColor: Color { Color(hex: colorHex) }

    var body: some View {
        ZStack {
            // Background with glow
            Color(hex: "#161618").ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: accentColor.opacity(0.3), location: 0),
                    .init(color: accentColor.opacity(0.08), location: 0.4),
                    .init(color: .clear, location: 0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: colorHex)

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

                    // Expense / Income toggle
                    HStack(spacing: 0) {
                        typeButton(label: "Expense", icon: "arrow.up.right", selected: !isIncome) {
                            withAnimation { isIncome = false }
                        }
                        typeButton(label: "Income", icon: "arrow.down.left", selected: isIncome) {
                            withAnimation { isIncome = true }
                        }
                    }
                    .glassEffect(.regular, in: .capsule)

                    Spacer()

                    // Placeholder to balance layout
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Avatar
                Button { showIconPicker = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 96, height: 96)
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundStyle(Color.contrasting(on: colorHex))
                            )
                            .animation(.easeInOut(duration: 0.3), value: colorHex)

                        // Pencil badge
                        Circle()
                            .fill(Color(hex: "#1C1C1E"))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 4, y: -4)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 40)

                Text(name.isEmpty ? "Category Name" : name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(name.isEmpty ? .white.opacity(0.3) : .white)
                    .padding(.top, 12)

                Spacer()

                // Fields
                VStack(spacing: 12) {
                    // Name field + color dot
                    HStack(spacing: 12) {
                        TextField("Category Name", text: $name)
                            .autocorrectionDisabled()
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .tint(accentColor)

                        Button { showColorPicker = true } label: {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 28, height: 28)
                                .animation(.easeInOut(duration: 0.3), value: colorHex)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Color presets row
                    colorPresetsRow

                    // Folder picker
                    folderPicker
                }
                .padding(.horizontal, 16)

                // Create / Save button
                Button { save() } label: {
                    Text(category == nil ? "Create" : "Save")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(36)
        .presentationBackground { Color.clear }
        .onAppear { loadIfEditing() }
        .sheet(isPresented: $showIconPicker) {
            IconPickerSheet(selectedIcon: $icon)
        }
        .sheet(isPresented: $showColorPicker) {
            ColorPickerSheet(selectedHex: $colorHex)
        }
    }

    // MARK: Color presets

    private let presets = [
        "#FF3B30", "#FF6B00", "#FF9500", "#FFCC00",
        "#34C759", "#00C7BE", "#32ADE6", "#0A84FF",
        "#5856D6", "#BF5AF2", "#FF2D55", "#A2845E"
    ]

    private var colorPresetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Color wheel → opens full picker
                Button { showColorPicker = true } label: {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 24)

                ForEach(presets, id: \.self) { hex in
                    Button {
                        withAnimation { colorHex = hex }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 36, height: 36)
                            if colorHex == hex {
                                Circle()
                                    .strokeBorder(.black.opacity(0.3), lineWidth: 2)
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .fill(.black.opacity(0.25))
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Folder picker

    private let groups = ["Everyday Spending", "Transport", "Living", "Health & Fitness", "Entertainment", "Shopping", "Income", "Other"]

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Folder")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Menu {
                    ForEach(groups, id: \.self) { g in
                        Button(g) { group = g }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(group)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Assign this category to a folder for better organization")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Type button

    private func typeButton(label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.45))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func loadIfEditing() {
        guard let cat = category else { return }
        name = cat.name ?? ""
        icon = cat.icon ?? "tag.fill"
        isIncome = cat.isIncome
        colorHex = cat.colorHex ?? "#FF3B30"
        group = cat.group ?? "Other"
    }

    private func save() {
        let cat = category ?? CategoryEntity(context: context)
        if category == nil { cat.id = UUID() }
        cat.name = name.trimmingCharacters(in: .whitespaces)
        cat.icon = icon
        cat.isIncome = isIncome
        cat.colorHex = colorHex
        cat.group = group
        try? context.save()
        dismiss()
    }
}

// MARK: - Icon Picker Sheet

struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    @State private var search = ""

    private let icons = [
        "photo.on.rectangle", "character", "sparkle", "sparkles", "alarm",
        "allergens", "leaf", "cross.case.fill", "anchor", "apple.logo",
        "battery.50", "bag.fill", "bag.badge.plus", "briefcase", "cross.circle",
        "bed.double.fill", "tennis.racket", "balloon.fill", "banknote", "bandage",
        "building.columns", "cooktop", "baseball", "basketball.fill", "trash.fill",
        "beach.umbrella", "teddybear", "mug.fill", "bicycle", "ellipsis.rectangle",
        "ellipsis.bubble", "dollarsign.square", "cup.and.saucer.fill", "bone", "fork.knife.circle",
        "fuelpump.fill", "car.fill", "bus.fill", "tram.fill", "cablecarsymbol",
        "cart.fill", "house.fill", "building.2.fill", "wifi", "bolt.fill",
        "drop.fill", "flame.fill", "thermometer.medium", "heart.fill", "bolt.heart.fill",
        "dumbbell.fill", "figure.run", "figure.walk", "figure.hiking", "figure.swimming",
        "gamecontroller.fill", "play.rectangle.fill", "airplane", "globe", "map.fill",
        "handbag.fill", "laptopcomputer", "iphone", "headphones", "tv",
        "creditcard.fill", "banknote.fill", "chart.bar.fill", "chart.line.uptrend.xyaxis", "dollarsign.circle.fill",
        "gift.fill", "party.popper.fill", "birthday.cake.fill", "music.note", "books.vertical.fill",
        "graduationcap.fill", "pencil", "paintbrush.fill", "scissors", "wrench.fill",
        "pawprint.fill", "dog.fill", "cat.fill", "tortoise.fill", "bird.fill",
        "tag.fill", "bookmark.fill", "flag.fill", "star.fill", "crown.fill",
        "lock.fill", "key.fill", "shield.fill", "bell.fill", "envelope.fill",
        "phone.fill", "message.fill", "camera.fill", "photo.fill", "moon.fill"
    ]

    private var filtered: [String] {
        if search.isEmpty { return icons }
        return icons.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "#161618").ignoresSafeArea()

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
                    Text("Choose Icon")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: cols, spacing: 0) {
                        ForEach(filtered, id: \.self) { ic in
                            Button {
                                selectedIcon = ic
                                dismiss()
                            } label: {
                                ZStack {
                                    if selectedIcon == ic {
                                        Circle()
                                            .fill(Theme.accent)
                                            .frame(width: 52, height: 52)
                                    }
                                    Image(systemName: ic)
                                        .font(.system(size: 24))
                                        .foregroundStyle(selectedIcon == ic ? .white : .white.opacity(0.85))
                                        .frame(width: 52, height: 52)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }

            // Search bar pinned at bottom
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search icons", text: $search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
                    .tint(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(36)
        .presentationBackground { Color(hex: "#161618") }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Color Picker Sheet

struct ColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedHex: String

    @State private var pickedColor: Color = .red

    var body: some View {
        VStack(spacing: 24) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            Text("Choose Color")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            ColorPicker("", selection: $pickedColor, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(2.0)
                .frame(height: 120)
                .onChange(of: pickedColor) { color in
                    if let hex = color.toHex() {
                        selectedHex = hex
                    }
                }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Spacer()
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(320)])
        .presentationBackground { Color(hex: "#1C1C1E") }
        .presentationCornerRadius(36)
        .presentationDragIndicator(.hidden)
        .onAppear {
            pickedColor = Color(hex: selectedHex)
        }
    }
}

// MARK: - Color.toHex helper

extension Color {
    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
