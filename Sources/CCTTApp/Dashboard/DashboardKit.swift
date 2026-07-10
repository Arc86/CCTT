import SwiftUI
import AppKit
import CCTTCore

// MARK: - Colour system
//
// The design (CCTT Insight Dashboard) specifies exact light/dark palettes. These
// helpers reproduce them faithfully while still adapting to the viewer's macOS
// appearance, so the window is a good Mac citizen (follows system light/dark) and
// looks like the mockup in both.

extension Color {
    /// Build an opaque colour from a 24-bit hex literal, e.g. `Color(hex: 0x34C759)`.
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// A colour that resolves to `light` or `dark` based on the current appearance.
    static func adaptive(_ light: Color, _ dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

/// The dashboard's shared visual tokens — card chrome, text tiers, the categorical
/// palette, and the meter thresholds — all matched to the source design.
enum Dash {
    // Card + surface chrome.
    static let cardBackground = Color.adaptive(Color(hex: 0xFFFFFF), Color(hex: 0x262628))
    static let cardBorder = Color.adaptive(.black.opacity(0.08), .white.opacity(0.09))
    static let track = Color.adaptive(.black.opacity(0.06), .white.opacity(0.09))
    static let hairline = Color.adaptive(.black.opacity(0.08), .white.opacity(0.10))

    // Text tiers (primary is `.primary`).
    static let text2 = Color.adaptive(.black.opacity(0.5), .white.opacity(0.58))
    static let text3 = Color.adaptive(.black.opacity(0.32), .white.opacity(0.34))

    static let accent = Color.accentColor
    /// Soft accent wash used behind selection, callouts and chart fills.
    static let accentSoft = Color.accentColor.opacity(0.14)

    // Semantic status colours (fixed hues, as in the design).
    static let good = Color(hex: 0x34C759)
    static let warn = Color(hex: 0xFF9500)
    static let danger = Color(hex: 0xFF3B30)
    static let grey = Color(hex: 0x8E8E93)

    /// Categorical palette for donuts and ranked bars. Index 0 tracks the system
    /// accent so the primary series always matches the rest of the UI.
    static let palette: [Color] = [
        .accentColor, Color(hex: 0x34C759), Color(hex: 0xFF9500), Color(hex: 0xAF52DE),
        Color(hex: 0x5AC8FA), Color(hex: 0xFF2D55), Color(hex: 0xFFCC00), Color(hex: 0x00C7BE),
        Color(hex: 0xFF6482), Color(hex: 0xA2845E),
    ]

    static func paletteColor(_ i: Int) -> Color { palette[((i % palette.count) + palette.count) % palette.count] }

    /// Meter colour ramp (plan windows, %-of-ceiling): accent → amber → red.
    static func meterColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7:  return .accentColor
        case ..<0.9:  return warn
        default:      return danger
        }
    }
}

// MARK: - Card container

/// A rounded content card matching the design (hairline border, 13pt radius). The
/// content layer stays plain — no Liquid Glass — per macOS guidance.
struct DashCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Dash.cardBackground, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Dash.cardBorder, lineWidth: 1))
    }
}

/// A card's header line: a semibold title with an optional muted trailing note.
struct CardTitleRow: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.system(size: 11)).foregroundStyle(Dash.text3)
            }
        }
    }
}

// MARK: - Meter bar

/// A rounded progress bar (track + coloured fill). Non-zero fractions keep a
/// minimum sliver so tiny values stay visible (as in the design's branch bars).
struct MeterBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let f = min(1, max(0, fraction))
            let w = f <= 0 ? 0 : max(3, geo.size.width * f)
            ZStack(alignment: .leading) {
                Capsule().fill(Dash.track)
                Capsule().fill(color).frame(width: w)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Ranked bar row

/// One "name — bar — value — %" row shared by every ranking (projects, models,
/// branches, skills, plugins, attribution).
struct RankedBarRow: View {
    let name: String
    var nameWidth: CGFloat = 150
    var monospaced: Bool = false
    let fraction: Double          // 0…1 of the row set's max
    var color: Color = .accentColor
    let value: String
    var percent: String? = nil
    var barHeight: CGFloat = 9
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 11) {
            Text(name)
                .font(.system(size: monospaced ? 12 : 12.5, design: monospaced ? .monospaced : .default))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: nameWidth, alignment: .leading)
            MeterBar(fraction: fraction, color: color, height: barHeight)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(valueColor)
                .frame(width: 62, alignment: .trailing)
            if let percent {
                Text(percent)
                    .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Dash.text2)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Donut

/// A ring chart with a labelled hole, used for "share of tokens" and
/// "main vs. subagent". Slices are (fraction, colour) pairs summing to ~1.
struct Donut: View {
    let slices: [(fraction: Double, color: Color)]
    let centerTitle: String
    let centerSubtitle: String
    var diameter: CGFloat = 118

    private var stops: [(start: Double, end: Double, color: Color)] {
        var acc = 0.0
        return slices.map { s in
            let seg = (start: acc, end: acc + max(0, s.fraction), color: s.color)
            acc += max(0, s.fraction)
            return seg
        }
    }

    var body: some View {
        let ring = diameter * 0.195
        ZStack {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, s in
                Circle()
                    .trim(from: s.start, to: min(1, s.end))
                    .stroke(s.color, style: StrokeStyle(lineWidth: ring, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(centerTitle).font(.system(size: 15, weight: .bold)).monospacedDigit()
                Text(centerSubtitle).font(.system(size: 8.5)).foregroundStyle(Dash.text2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// A small colour swatch + label + value line, used beside donuts.
struct LegendItemRow: View {
    let color: Color
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(name).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }
}

// MARK: - Insight line

/// A one-line takeaway prefixed by a small diamond, matching the design's inline
/// insights ("CCTT drove 62% of spend …").
struct InsightLine: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("◆").font(.system(size: 9)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Dash.text2)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sparkline

/// A compact filled line chart for the hero. `values` are plotted left→right and
/// auto-scaled to their own max.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    var size = CGSize(width: 168, height: 46)

    var body: some View {
        Canvas { ctx, canvas in
            guard values.count > 1 else { return }
            let maxV = max(values.max() ?? 1, 1)
            let n = values.count
            func point(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(n - 1) * canvas.width
                let y = canvas.height - 2 - CGFloat(values[i] / maxV) * (canvas.height - 6)
                return CGPoint(x: x, y: y)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<n { line.addLine(to: point(i)) }

            var fill = line
            fill.addLine(to: CGPoint(x: canvas.width, y: canvas.height))
            fill.addLine(to: CGPoint(x: 0, y: canvas.height))
            fill.closeSubpath()

            ctx.fill(fill, with: .color(color.opacity(0.12)))
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Delta pill

/// The hero's trend pill (▲/▼ N%). Green when usage rose, red when it fell.
struct DeltaPill: View {
    let fraction: Double     // signed; e.g. +0.12 = up 12%

    var body: some View {
        let up = fraction >= 0
        let color = up ? Dash.good : Dash.danger
        Text("\(up ? "▲" : "▼") \(Int((abs(fraction) * 100).rounded()))%")
            .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.vertical, 3).padding(.horizontal, 9)
            .background(color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Status pill

/// A rounded status chip (e.g. "Healthy", "Approaching limit").
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 4).padding(.horizontal, 11)
            .background(color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Callout banner

/// An accent-tinted callout with a leading bolt, used for the models
/// cache-efficiency headline.
struct CalloutBanner: View {
    let systemImage: String
    let bold: String
    let rest: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: systemImage).foregroundStyle(Dash.accent).font(.system(size: 14))
            (Text(bold).font(.system(size: 12.5, weight: .semibold))
             + Text(" " + rest).font(.system(size: 12.5)).foregroundStyle(Dash.text2))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .background(Dash.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Meter card (plan windows)

/// A single limit-window meter: label + sub, big coloured %, used figure, bar, and
/// a reset line. Used by the Plan tab.
struct MeterCard: View {
    let label: String
    let sub: String
    let fraction: Double?
    let usedText: String
    let resets: String?

    var body: some View {
        let f = fraction ?? 0
        let color = Dash.meterColor(f)
        DashCard {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                Text(sub).font(.system(size: 10.5)).foregroundStyle(Dash.text3)
            }
            .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(fraction == nil ? "—" : "\(Int((f * 100).rounded()))%")
                    .font(.system(size: 32, weight: .bold)).monospacedDigit()
                    .foregroundStyle(color)
                Text(usedText).font(.system(size: 11)).foregroundStyle(Dash.text2).monospacedDigit()
            }
            .padding(.bottom, 12)

            MeterBar(fraction: f, color: color, height: 9)
                .padding(.bottom, 11)

            if let resets {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(Dash.text2)
                    Text(resets).font(.system(size: 11)).foregroundStyle(Dash.text2)
                }
            }
        }
    }
}

// MARK: - Stacked composition row (models)

/// One model's token composition as a proportional stacked bar (input / cache-read
/// / output), its whole width scaled to the row set's max.
struct CompositionRow: View {
    let name: String
    let value: String
    let barFraction: Double            // 0…1 of the max total
    let segments: [(fraction: Double, color: Color)]   // sum to 1 within the bar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                let total = max(3, geo.size.width * min(1, max(0, barFraction)))
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        Rectangle().fill(s.color).frame(width: total * min(1, max(0, s.fraction)))
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 15)
        }
    }
}

/// A horizontal legend of coloured labels (composition, etc.).
struct SwatchLegend: View {
    let items: [(name: String, color: Color)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(it.color).frame(width: 8, height: 8)
                    Text(it.name).font(.system(size: 10.5)).foregroundStyle(Dash.text2)
                }
            }
        }
    }
}
