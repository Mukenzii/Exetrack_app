import SwiftUI
import BlurSwiftUI

// MARK: - Theme tokens

enum Theme {
    static let accent = Color(hex: "#2F6BFF")
    static let background = Color(hex: "#08090D")
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.07)
    static let textSecondary = Color.white.opacity(0.5)

    static let currency = "sums"

    /// Exchange rate: how many сўм for 1 USD. TODO: replace with a live FX API.
    static let usdRate: Double = 12092.73

    /// Formats a number the way the app shows money: space thousands separator,
    /// comma decimal — e.g. 12092.73 -> "12 092,73", 5000 -> "5 000".
    static func amount(_ value: Double, fraction: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.decimalSeparator = ","
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Money string with the currency suffix, e.g. "5 000 сўм".
    static func money(_ value: Double, fraction: Int = 0) -> String {
        "\(amount(value, fraction: fraction)) \(currency)"
    }
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.background

            // Top dark fade — under the blue glow so glow renders on top
            LinearGradient(
                stops: [
                    .init(color: Theme.background, location: 0.0),
                    .init(color: Theme.background.opacity(0.55), location: 0.05),
                    .init(color: .clear, location: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top blue glow — radial, concentrated under the status bar
            RadialGradient(
                colors: [
                    Color(hex: "#2D5BE3").opacity(0.85),
                    Color(hex: "#16317F").opacity(0.45),
                    .clear
                ],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 460
            )

            // Subtle vertical fade to deepen the bottom
            LinearGradient(
                colors: [.clear, Theme.background.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass icon button (circular)

struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var tinted: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
        .glassEffect(
            tinted ? .regular.tint(Theme.accent.opacity(0.35)).interactive()
                   : .regular.interactive(),
            in: .circle
        )
    }
}

// MARK: - Personal capsule (leading chip)

struct SpaceChip: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.accent, in: .circle)
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
        }
        .glassEffect(.regular.tint(Theme.accent.opacity(0.35)).interactive(), in: .capsule)
    }
}

// MARK: - Outline pill button (Create budget / account)

struct OutlinePillButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .regular))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Elevated surface card

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Category avatar (solid circle + contrast icon)

struct CategoryAvatar: View {
    let colorHex: String
    let systemName: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.contrasting(on: colorHex))
        }
    }
}

// MARK: - Account badge (rounded square initial + name)

struct AccountBadge: View {
    let name: String

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(initial)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(name)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Balance chip (flag + amount) for the top bar

struct BalanceChip: View {
    let flag: String
    let value: Double
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(flag).font(.system(size: 16))
                Text(Theme.amount(value, fraction: 2))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.tint(Theme.accent.opacity(0.35)).interactive(), in: .capsule)
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 56
    var lineWidth: CGFloat = 5
    var color: Color? = nil

    private var clamped: Double { min(max(progress, 0), 1) }
    private var tint: Color {
        if let c = color { return c }
        return progress >= 1 ? .red : progress > 0.85 ? .orange : Theme.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Mini sparkline (accounts card)

struct MiniSparkline: View {
    let points: [Double]   // raw values, will be normalised internally
    var color: Color = Color(hex: "#30D158")

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            guard points.count > 1 else { return AnyView(EmptyView()) }
            let mn = points.min()!
            let mx = points.max()!
            let range = mx - mn == 0 ? 1.0 : mx - mn
            let norm = points.map { (($0 - mn) / range) }
            let n = norm.count - 1

            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: w * CGFloat(i) / CGFloat(n),
                        y: h * (1 - CGFloat(norm[i])) )
            }

            let linePath = Path { p in
                p.move(to: pt(0))
                for i in 1...n { p.addLine(to: pt(i)) }
            }

            let fillPath = Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: pt(0))
                for i in 1...n { p.addLine(to: pt(i)) }
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
            }

            return AnyView(ZStack {
                fillPath.fill(
                    LinearGradient(colors: [color.opacity(0.25), color.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                linePath.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            })
        }
    }
}

// MARK: - Spending trend line (cumulative spend, solid → dashed projection)

struct SpendingTrendLine: View {
    let points: [Double]
    let todayFraction: Double
    var totalBudget: Double = 0
    var totalSpent: Double = 0

    var body: some View {
        GeometryReader { geo in
            SpendingTrendCanvas(
                points: points,
                todayFraction: todayFraction,
                size: geo.size,
                totalBudget: totalBudget,
                totalSpent: totalSpent  
            )
        }
    }
}

private struct SpendingTrendCanvas: View {
    let points: [Double]
    let todayFraction: Double
    let size: CGSize
    var totalBudget: Double = 0
    var totalSpent: Double = 0

    private let topPad: CGFloat = 28

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }
    private var n: Int { max(points.count - 1, 1) }
    private var todayX: CGFloat { w * CGFloat(todayFraction) }

    private func pt(_ i: Int) -> CGPoint {
        CGPoint(x: todayX * CGFloat(i) / CGFloat(n),
                y: topPad + (h - topPad) * (1 - CGFloat(points[i])))
    }

    private var solid: Path {
        let r: CGFloat = 16
        return Path { p in
            guard !points.isEmpty else { return }
            p.move(to: pt(0))
            for i in 1..<points.count {
                let curr = pt(i)
                if i < points.count - 1 {
                    let prev = pt(i - 1)
                    let next = pt(i + 1)
                    let d1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
                    let d2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
                    let l1 = sqrt(d1.x*d1.x + d1.y*d1.y)
                    let l2 = sqrt(d2.x*d2.x + d2.y*d2.y)
                    guard l1 > 0, l2 > 0 else { p.addLine(to: curr); continue }
                    let t1 = min(r / l1, 0.45)
                    let t2 = min(r / l2, 0.45)
                    let before = CGPoint(x: curr.x - d1.x * t1, y: curr.y - d1.y * t1)
                    let after  = CGPoint(x: curr.x + d2.x * t2, y: curr.y + d2.y * t2)
                    p.addLine(to: before)
                    p.addQuadCurve(to: after, control: curr)
                } else {
                    p.addLine(to: curr)
                }
            }
        }
    }

    var body: some View {
        let lastPt = points.isEmpty ? CGPoint(x: 0, y: h) : pt(points.count - 1)
        let dashed = Path { p in
            p.move(to: lastPt)
            p.addLine(to: CGPoint(x: w, y: lastPt.y))
        }
        let fill = Path { p in
            p.move(to: CGPoint(x: 0, y: h))
            p.addPath(solid)
            p.addLine(to: CGPoint(x: todayX, y: h))
            p.closeSubpath()
        }
        let limitLine = Path { p in
            p.move(to: CGPoint(x: 0, y: topPad))
            p.addLine(to: CGPoint(x: w, y: topPad))
        }

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                // Limit line
                if totalBudget > 0 {
                    ctx.stroke(limitLine, with: .color(.white.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }
                // Fill + actual line
                ctx.fill(fill, with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.35), .clear]),
                    startPoint: CGPoint(x: w / 2, y: topPad),
                    endPoint: CGPoint(x: w / 2, y: h)
                ))
                ctx.stroke(solid, with: .color(Theme.accent),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ctx.stroke(dashed, with: .color(Theme.accent.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 7]))
                // Dot at today
                if !points.isEmpty {
                    let dotRect = CGRect(x: lastPt.x - 5, y: lastPt.y - 5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: dotRect), with: .color(Theme.accent))
                    let innerRect = CGRect(x: lastPt.x - 2.5, y: lastPt.y - 2.5, width: 5, height: 5)
                    ctx.fill(Path(ellipseIn: innerRect), with: .color(.white))
                }
            }

            // Budget limit pill (top right)
            if totalBudget > 0 {
                HStack {
                    Spacer()
                    Text(Theme.money(totalBudget))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(.ultraThinMaterial)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .padding(.trailing, 20)
                }
                .offset(y: topPad - 12)
            }

            // Current spend pill (at today dot)
            if totalSpent > 0 && !points.isEmpty {
                Text(Theme.money(totalSpent))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .fixedSize()
                    .position(x: todayX, y: lastPt.y - 20)
            }
        }
    }
}

// MARK: - Progressive blur (top fade, no tint)

struct ProgressiveBlurView: View {
    var height: CGFloat = 120

    var body: some View {
        VariableBlur(direction: .down)
            .maximumBlurRadius(4)
            .dimmingTintColor(nil)
            .dimmingAlpha(nil)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}

// MARK: - Bottom scrim (blur + dark gradient behind floating buttons)

struct TopScrim: View {
    var height: CGFloat = 120

    var body: some View {
        VStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.background, location: 0.0),
                    .init(color: Theme.background.opacity(0.6), location: 0.4),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)
            Spacer()
        }
        .ignoresSafeArea()
    }
}

struct BottomScrim: View {
    var height: CGFloat = 140

    var body: some View {
        VStack {
            Spacer()
            VariableBlur(direction: .up)
                .maximumBlurRadius(2)
                .dimmingTintColor(nil)
                .dimmingAlpha(nil)
                .frame(height: height)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Category spend card (horizontal scroll tile)

struct CategorySpendCard: View {
    let category: CategoryEntity
    let spent: Double
    let budget: Double?

    private var catColor: Color { Color(hex: category.colorHex ?? "#888") }
    private var isOverBudget: Bool { budget.map { spent >= $0 } ?? false }
    private var ringProgress: Double { budget.map { min(spent / max($0, 1), 1) } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle()
                    .fill(catColor.opacity(0.35))
                    .frame(width: 52, height: 52)
                    .blur(radius: 14)
                if budget != nil {
                    ProgressRing(progress: ringProgress, size: 52, lineWidth: 3, color: catColor)
                }
                CategoryAvatar(
                    colorHex: category.colorHex ?? "#888",
                    systemName: category.icon ?? "tag.fill",
                    size: 42
                )
            }
            .frame(width: 52, height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 68, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text(category.name ?? "")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(Theme.money(spent))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Group {
                    if let b = budget {
                        Text("/ \(Theme.money(max(b - spent, 0))) left")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("No limit").foregroundStyle(Theme.textSecondary)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 160, height: 152)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
