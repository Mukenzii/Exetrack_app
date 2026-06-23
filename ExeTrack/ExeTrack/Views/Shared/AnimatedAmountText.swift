import SwiftUI

// MARK: - Digit slide transition modifier

private struct DigitSlide: ViewModifier {
    let yOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: yOffset)
            .opacity(opacity)
            .blur(radius: abs(yOffset) * 0.18)
    }
}

private extension AnyTransition {
    static var digitIn: AnyTransition {
        .modifier(active: DigitSlide(yOffset: 32, opacity: 0),
                  identity: DigitSlide(yOffset: 0, opacity: 1))
    }
    static var digitOut: AnyTransition {
        .modifier(active: DigitSlide(yOffset: -32, opacity: 0),
                  identity: DigitSlide(yOffset: 0, opacity: 1))
    }
}

// MARK: - Single digit cell

private struct DigitCell: View {
    let char: String
    let fontSize: CGFloat
    let delay: Double

    var body: some View {
        ZStack {
            Text(char)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize()
                .id(char)
                .transition(.asymmetric(insertion: .digitIn, removal: .digitOut))
        }
        .animation(
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.42).delay(delay),
            value: char
        )
    }
}

// MARK: - Animated amount text

struct AnimatedAmountText: View {
    let text: String          // formatted number string e.g. "1 234 567"
    let currency: String
    let fontSize: CGFloat
    let currencySize: CGFloat

    private var chars: [String] { Array(text).map { String($0) } }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                    if ch == " " {
                        Text(ch)
                            .font(.system(size: fontSize * 0.45, weight: .semibold, design: .rounded))
                            .foregroundStyle(.clear)
                    } else {
                        let stagger = Double(max(0, chars.count - 1 - i)) * 0.022
                        DigitCell(char: ch, fontSize: fontSize, delay: stagger)
                    }
                }
            }

            Text(currency)
                .font(.system(size: currencySize, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }
}
