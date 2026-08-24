import CoreData
import SwiftUI
import UIKit

/// Capture an expense by describing it — typed, or spoken and transcribed by
/// Aisha — then review what was understood before anything hits the ledger.
struct AIAddExpenseView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("accentColorHex") private var accentColorHex = "#2D5BE3"

    @StateObject private var vm: AIExpenseViewModel
    @StateObject private var voice = VoiceCaptureService()

    @FocusState private var textFieldFocused: Bool
    @State private var categoryTarget: CategoryEditTarget?
    @State private var dateTarget: DateEditTarget?
    @State private var voiceError: String?
    @State private var showManualEditor = false

    init(context: NSManagedObjectContext) {
        _vm = StateObject(wrappedValue: AIExpenseViewModel(context: context))
    }

    private var accent: Color { Color(hex: accentColorHex) }

    private struct CategoryEditTarget: Identifiable {
        let id: UUID
        let isIncome: Bool
    }

    private struct DateEditTarget: Identifiable {
        let id: UUID
    }

    private static let examples = [
        "45 000 groceries at Korzinka",
        "Taxi home 18k",
        "Coffee 25 000 and lunch 60 000",
    ]

    var body: some View {
        ZStack {
            AppBackground()
            GlowLayer().opacity(0.55)

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch vm.phase {
                        case .composing:
                            composer
                        case .thinking:
                            thinkingState
                        case .review:
                            reviewState
                        case .failed(let message):
                            failureState(message)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 190)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            VStack {
                Spacer()
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: vm.phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: voice.phase)
        .onChange(of: voice.elapsed) { _, _ in
            // The sync endpoint is for short clips, so wrap up automatically.
            if voice.hasReachedLimit, voice.isRecording { finishRecording() }
        }
        .sheet(item: $categoryTarget) { target in
            CategoryPickerSheet(isIncome: target.isIncome, selected: categoryBinding(for: target.id))
        }
        .sheet(item: $dateTarget) { target in
            DatePickerSheet(date: dateBinding(for: target.id))
        }
        .fullScreenCover(isPresented: $showManualEditor) {
            AddTransactionView()
        }
        .alert("Voice input", isPresented: .constant(voiceError != nil)) {
            Button("OK") { voiceError = nil }
        } message: {
            Text(voiceError ?? "")
        }
        .onDisappear { voice.cancel() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")

            Spacer()

            VStack(spacing: 2) {
                Text("Describe an expense")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Text(vm.engineLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button { showManualEditor = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Enter manually instead")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Composing

    private var composer: some View {
        VStack(spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    switch voice.phase {
                    case .recording:
                        recordingBanner
                    case .transcribing:
                        transcribingBanner
                    case .idle:
                        EmptyView()
                    }

                    ZStack(alignment: .topLeading) {
                        if vm.text.isEmpty && !voice.isBusy {
                            Text("Tell me what you spent — for example “45 000 groceries at Korzinka”.")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $vm.text, axis: .vertical)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .tint(accent)
                            .lineLimit(3...8)
                            .focused($textFieldFocused)
                            .padding(.top, 8)
                            .disabled(voice.isBusy)
                            .accessibilityLabel("Expense description")
                    }
                }
                .padding(18)
            }

            if !voice.isBusy {
                languageRow
            }

            if vm.text.isEmpty && !voice.isBusy {
                exampleChips
            }

            if let notice = vm.fallbackNotice {
                noticeRow(notice)
            }
        }
    }

    private var recordingBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "#FF453A")).frame(width: 8, height: 8)
                Text("Recording · \(Self.timeLabel(voice.elapsed))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Text("Tap stop when you're done")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            VoiceWaveform(levels: voice.levels)
                .frame(height: 44)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording, \(Int(voice.elapsed)) seconds")
    }

    private var transcribingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(accent)
            Text("Transcribing with Aisha…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            Text("Voice language")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            ForEach(AishaSTTService.Language.allCases) { language in
                let selected = voice.language == language
                Button { voice.language = language } label: {
                    Text(language.shortLabel)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .black : .white)
                        .frame(width: 42, height: 30)
                        .background(
                            Capsule().fill(selected ? Color.white : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.rawValue.uppercased())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
    }

    private var exampleChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Self.examples, id: \.self) { example in
                Button {
                    vm.text = example
                    textFieldFocused = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text(example)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Theme.cardFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Thinking

    private var thinkingState: some View {
        VStack(spacing: 14) {
            ForEach(0..<2, id: \.self) { index in
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Circle().fill(Color.white.opacity(0.08)).frame(width: 40, height: 40)
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                                .frame(width: 110, height: 14)
                            Spacer()
                        }
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                            .frame(width: 160, height: 26)
                    }
                    .padding(18)
                }
                .opacity(index == 0 ? 1 : 0.5)
            }
        }
        .shimmer(active: !reduceMotion)
        .accessibilityLabel("Reading your note")
    }

    // MARK: - Review

    private var reviewState: some View {
        VStack(spacing: 14) {
            HStack {
                Text(vm.drafts.count == 1 ? "Here's what I understood" : "I found \(vm.drafts.count) expenses")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Button("Redo") { vm.backToComposing() }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 4)

            if let notice = vm.categoryNotice {
                noticeRow(notice)
            }

            ForEach($vm.drafts) { $draft in
                ExpenseDraftCard(
                    draft: $draft,
                    onPickCategory: {
                        categoryTarget = CategoryEditTarget(id: draft.id, isIncome: draft.isIncome)
                    },
                    onPickDate: { dateTarget = DateEditTarget(id: draft.id) },
                    onChooseAlternative: { category in
                        guard let index = vm.drafts.firstIndex(where: { $0.id == draft.id }) else { return }
                        withAnimation { swapCategory(at: index, to: category) }
                    },
                    onRemove: { withAnimation { vm.remove(draft) } }
                )
            }

            if vm.drafts.count > 1 {
                HStack {
                    Text("Total")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(Theme.money(vm.totalAmount))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Failure

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 30)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                OutlinePillButton(title: "Try again") { vm.backToComposing() }
                Button("Enter it manually") { showManualEditor = true }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch vm.phase {
        case .composing, .failed:
            HStack(spacing: 12) {
                micButton
                sendButton
            }
        case .thinking:
            EmptyView()
        case .review:
            HStack(spacing: 12) {
                Button { vm.startOver() } label: {
                    Text("Discard")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(height: 54)
                        .padding(.horizontal, 26)
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                Button { applyAndClose() } label: {
                    Text(vm.drafts.count > 1 ? "Add \(vm.drafts.count) expenses" : "Add expense")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(vm.canSave ? Color.white : Color.white.opacity(0.1)))
                }
                .disabled(!vm.canSave)
            }
        }
    }

    private var micButton: some View {
        Button { toggleRecording() } label: {
            Group {
                if voice.phase == .transcribing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(micTint)
                }
            }
            .frame(width: 60, height: 60)
            .background(Circle().fill(voice.isRecording ? Color.white : Color.clear))
        }
        .glassEffect(
            voice.isRecording ? .regular : .regular.tint(accent.opacity(0.35)).interactive(),
            in: .circle
        )
        .disabled(voice.phase == .transcribing || !voice.isConfigured)
        .accessibilityLabel(voice.isRecording ? "Stop recording" : "Record a voice note")
        .accessibilityHint(
            voice.isConfigured
                ? (voice.isRecording ? "Ends recording and sends it to Aisha" : "Describe your expense out loud")
                : "Voice needs an Aisha API key. Type instead."
        )
    }

    private var micTint: Color {
        if voice.isRecording { return .black }
        return voice.isConfigured ? .white : Theme.textSecondary
    }

    private var sendButton: some View {
        Button {
            textFieldFocused = false
            Task { await vm.submit() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                Text("Read it")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(canSend ? .black : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(canSend ? Color.white : Color.white.opacity(0.1)))
        }
        .disabled(!canSend)
        .accessibilityLabel("Read my note and suggest an expense")
    }

    private var canSend: Bool { vm.canSubmit && !voice.isBusy }

    // MARK: - Actions

    private func toggleRecording() {
        if voice.isRecording {
            finishRecording()
            return
        }
        textFieldFocused = false
        Task {
            do {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                try await voice.start()
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }

    private func finishRecording() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                if let transcript = try await voice.stopAndTranscribe(), !transcript.isEmpty {
                    vm.text = transcript
                }
            } catch {
                voice.cancel()
                voiceError = error.localizedDescription
            }
        }
    }

    private func applyAndClose() {
        let count = vm.applyAll()
        guard count > 0 else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private static func timeLabel(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - Bindings into the draft list

    /// Moves the chosen category to the front and puts the old pick back into
    /// the alternatives, so a mis-tap is one tap to undo.
    private func swapCategory(at index: Int, to category: CategoryEntity) {
        var alternatives = vm.drafts[index].alternatives.filter { $0 != category }
        if let previous = vm.drafts[index].category { alternatives.insert(previous, at: 0) }
        vm.drafts[index].category = category
        vm.drafts[index].alternatives = Array(alternatives.prefix(3))
        // The user just told us the answer, so stop flagging this row.
        vm.drafts[index].categoryConfidence = 1
    }

    private func categoryBinding(for id: UUID) -> Binding<CategoryEntity?> {
        Binding(
            get: { vm.drafts.first { $0.id == id }?.category },
            set: { new in
                guard let index = vm.drafts.firstIndex(where: { $0.id == id }) else { return }
                vm.drafts[index].category = new
                vm.drafts[index].categoryConfidence = 1
                // Picking an income category flips the row's sign, and vice versa.
                if let new { vm.drafts[index].isIncome = new.isIncome }
            }
        )
    }

    private func dateBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { vm.drafts.first { $0.id == id }?.date ?? Date() },
            set: { new in
                guard let index = vm.drafts.firstIndex(where: { $0.id == id }) else { return }
                vm.drafts[index].date = new
            }
        )
    }
}
