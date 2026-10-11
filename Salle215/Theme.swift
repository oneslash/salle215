import SwiftUI

// Langfuse's theme (web/src/styles/globals.css), converted to sRGB; semi-transparent fills are flattened onto the background.
enum Palette {
    static let background = adaptive(0xffffff, 0x0f0f0f) // --background
    static let surface = adaptive(0xffffff, 0x131313) // --card
    static let fill = adaptive(0xf4f4f5, 0x1e1e1e) // --muted
    static let ink = adaptive(0x27272a, 0xb2b2b2) // --foreground
    static let primary = adaptive(0x18181b, 0xe6e6e6) // --primary
    static let inverse = adaptive(0xfafafa, 0x090909) // --primary-foreground
    static let muted = adaptive(0x71717a, 0x8a8a8a) // --muted-foreground
    static let line = adaptive(0xe4e4e7, 0x333333) // --border
    static let chart = adaptive(0x5f62f1, 0x6467fc) // --chart-1
    static let orange = adaptive(0x874c01, 0xeab305) // --dark-yellow
    static let orangeFill = adaptive(0xfefbd4, 0x4a3009) // --light-yellow
    static let red = adaptive(0xfb2c36, 0xff8e81) // --dark-red
    static let redFill = adaptive(0xffebeb, 0x5f1517) // --light-red
    static let green = adaptive(0x025f46, 0x07d295) // --dark-green
    static let greenFill = adaptive(0xdefced, 0x063b2e) // --light-green

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static func status(_ status: TraceStatus) -> Color {
        switch status { case .error: red; case .slow: orange; case .ok: green }
    }
    static func statusFill(_ status: TraceStatus) -> Color {
        switch status { case .error: redFill; case .slow: orangeFill; case .ok: greenFill }
    }

    // Langfuse's observation colours in their own OKLCH form (web/src/styles/globals.css, --observation-*):
    // one hue per type, with lightness and chroma shared per role and appearance.
    static func glyph(_ kind: TraceSpan.Kind) -> Color { observation(light: (0.55, 0.21), dark: (0.76, 0.11), hue: kind.hue) }
    static func bar(_ kind: TraceSpan.Kind) -> Color { observation(light: (0.68, 0.18), dark: (0.75, 0.12), hue: kind.hue) }

    private static func observation(light: (Double, Double), dark: (Double, Double), hue: Double) -> Color {
        Color(uiColor: UIColor { traits in
            let (lightness, chroma) = traits.userInterfaceStyle == .dark ? dark : light
            return oklch(lightness, chroma, hue)
        })
    }
    /// Extended-range sRGB, so colours beyond sRGB still render wide-gamut on P3 screens. https://bottosson.github.io/posts/oklab/
    private static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double) -> UIColor {
        let a = chroma * cos(hue * .pi / 180), b = chroma * sin(hue * .pi / 180)
        let cube = { (x: Double) in x * x * x }
        let l = cube(lightness + 0.3963377774 * a + 0.2158037573 * b)
        let m = cube(lightness - 0.1055613458 * a - 0.0638541728 * b)
        let s = cube(lightness - 0.0894841775 * a - 1.2914855480 * b)
        func encode(_ linear: Double) -> CGFloat {
            let magnitude = abs(linear) <= 0.0031308 ? 12.92 * abs(linear) : 1.055 * pow(abs(linear), 1 / 2.4) - 0.055
            return CGFloat(linear < 0 ? -magnitude : magnitude)
        }
        return UIColor(red: encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                       green: encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                       blue: encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), alpha: 1)
    }
}

extension TraceSpan.Kind {
    var hue: Double {
        switch self {
        case .span: 265; case .generation: 335; case .event: 115; case .agent: 310; case .tool: 55
        case .chain: 0; case .retriever: 145; case .evaluator: 285; case .embedding: 85; case .guardrail: 25
        }
    }
}

struct Screen<Content: View>: View {
    var horizontalPadding: CGFloat = 16
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}
struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Palette.muted) }
        }.padding(.top, 26).padding(.bottom, 10)
    }
}
struct SurfaceGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .card(.rect(cornerRadius: 24))
    }
}
extension View {
    /// Langfuse cards: a surface outlined by a hairline border.
    func card(_ shape: some InsettableShape) -> some View {
        background(Palette.surface, in: shape).overlay(shape.strokeBorder(Palette.line))
    }
}
struct RowDivider: View {
    var body: some View { Rectangle().fill(Palette.line).frame(height: 0.5).padding(.leading, 16) }
}
struct Chevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted.opacity(0.6)) }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { if let symbol { Image(systemName: symbol) }; Text(title) }
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(Palette.inverse)
                .background(Palette.primary, in: .capsule)
        }.buttonStyle(.plain)
    }
}
struct StatusPill: View {
    let status: TraceStatus
    var body: some View {
        Text(status.title).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(Palette.status(status)).background(Palette.statusFill(status), in: .capsule)
    }
}
struct MessageBlock: View {
    var role: String? = nil
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let role { Text(role.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Palette.muted) }
            Text(highlightedText).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).card(.rect(cornerRadius: 18))
    }
    private var highlightedText: AttributedString {
        var result = AttributedString(text)
        for match in text.matches(of: /\{\{[^{}]+\}\}/) {
            if let range = Range(match.range, in: result) {
                result[range].foregroundColor = Palette.chart
                result[range].font = .system(.body, design: .monospaced, weight: .medium)
            }
        }
        return result
    }
}
struct ContentBlocks: View {
    let content: MessageContent?
    var body: some View {
        switch content {
        case .text(let text): MessageBlock(text: text)
        case .messages(let messages):
            VStack(spacing: 10) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    MessageBlock(role: message.role, text: message.content)
                }
            }
        case nil: MessageBlock(text: "Nothing recorded.").foregroundStyle(Palette.muted)
        }
    }
}
struct ProjectMenuLabel: View {
    let title: String
    let environment: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.3.layers.3d")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(environment).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }.accessibilityElement(children: .combine)
    }
}

struct ReviewDecisions: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let needsWork: () -> Void
    let good: () -> Void
    var needsWorkID = "needsWork"
    var goodID = "rateGood"
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 24))
        layout {
            decision("Needs work", symbol: "hand.thumbsdown", color: Palette.muted, id: needsWorkID, action: needsWork)
            decision("Good", symbol: "hand.thumbsup", color: Palette.green, id: goodID, action: good)
        }
    }
    private func decision(_ title: String, symbol: String, color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.body.weight(.medium)).foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
