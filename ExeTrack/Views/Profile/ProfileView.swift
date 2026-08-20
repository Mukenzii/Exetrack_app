import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("userName") private var userName = "Personal"
    @AppStorage("accentColorHex") private var accentColorHex = "#2D5BE3"

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var showCategories = false

    private let accentPalette: [String] = [
        "#2D5BE3", "#5856D6", "#AF52DE", "#FF2D55",
        "#FF6B00", "#FF9F0A", "#30D158", "#00C7BE",
        "#0A84FF", "#BF5AF2"
    ]

    private var initial: String {
        String(userName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Color(hex: "#0B0B0D").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Avatar + name
                    profileHeader

                    // Appearance
                    settingsSection(title: "Appearance") {
                        colorPickerRow
                    }

                    // Data
                    settingsSection(title: "Data") {
                        settingsRow(
                            icon: "tag.fill",
                            iconColor: "#5856D6",
                            title: "Categories"
                        ) {
                            showCategories = true
                        }
                    }

                    // Preferences
                    settingsSection(title: "Preferences") {
                        notificationsRow
                        Divider().background(Color.white.opacity(0.07)).padding(.horizontal, 16)
                        currencyRow
                    }

                    // About
                    settingsSection(title: "About") {
                        infoRow(title: "Version", value: "1.0.0")
                        Divider().background(Color.white.opacity(0.07)).padding(.horizontal, 16)
                        settingsRow(icon: "star.fill", iconColor: "#FF9F0A", title: "Rate ExeTrack") {}
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 64) }

            VStack {
                topBar
                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showCategories) {
            CategoriesView()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text("Profile")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: accentColorHex))
                    .frame(width: 84, height: 84)
                    .shadow(color: Color(hex: accentColorHex).opacity(0.5), radius: 20)
                Text(initial)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Name (tap to edit)
            if isEditingName {
                HStack(spacing: 8) {
                    TextField("Your name", text: $draftName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .onSubmit { commitName() }

                    Button { commitName() } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(hex: accentColorHex))
                    }
                }
                .padding(.horizontal, 32)
            } else {
                Button {
                    draftName = userName
                    withAnimation(.spring(response: 0.3)) { isEditingName = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(userName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
            }

            Text("Personal space")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Color picker row

    private var colorPickerRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                rowIcon(systemName: "paintpalette.fill", colorHex: accentColorHex)
                Text("Accent color")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(Color(hex: accentColorHex))
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(accentPalette, id: \.self) { hex in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                accentColorHex = hex
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                if accentColorHex == hex {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2.5)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Static rows

    @State private var notificationsEnabled = true

    private var notificationsRow: some View {
        HStack(spacing: 14) {
            rowIcon(systemName: "bell.fill", colorHex: "#FF2D55")
            Text("Notifications")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .tint(Color(hex: accentColorHex))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var currencyRow: some View {
        HStack(spacing: 14) {
            rowIcon(systemName: "dollarsign", colorHex: "#30D158")
            Text("Currency")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Text("сўм")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Reusable components

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.leading, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func settingsRow(icon: String, iconColor: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                rowIcon(systemName: icon, colorHex: iconColor)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 14) {
            rowIcon(systemName: "info.circle.fill", colorHex: "#636366")
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func rowIcon(systemName: String, colorHex: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: colorHex))
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { userName = trimmed }
        withAnimation(.spring(response: 0.3)) { isEditingName = false }
    }
}
