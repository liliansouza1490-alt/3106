import SwiftUI

enum AppTheme {
    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.64, blue: 0.42, alpha: 1.00)
                : UIColor(red: 0.85, green: 0.42, blue: 0.20, alpha: 1.00)
        }
    )
    static let pageBackground = Color(uiColor: .systemBackground)
    static let consoleBackground = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 20
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            Color(uiColor: .separator).opacity(0.22),
            lineWidth: 0.5
        )
        .accessibilityHidden(true)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}


private struct ConstellationParticleSeed {
    let x: CGFloat
    let y: CGFloat
    let phase: CGFloat
    let radius: CGFloat
}

struct ParticleConstellationView: View {
    private static let seeds: [ConstellationParticleSeed] = {
        var result: [ConstellationParticleSeed] = []
        for index in 0..<34 {
            let x = CGFloat((index * 37 + 11) % 101) / 100
            let y = CGFloat((index * 61 + 7) % 103) / 102
            let phase = CGFloat(index) * 0.83
            let radius: CGFloat = index % 5 == 0 ? 1.7 : 1.15
            result.append(ConstellationParticleSeed(x: x, y: y, phase: phase, radius: radius))
        }
        return result
    }()

    private let color = Color(red: 0.67, green: 0.48, blue: 1.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let points = Self.seeds.map { seed in
                    CGPoint(
                        x: CGFloat(min(max(Double(seed.x) + sin(time * 0.16 + Double(seed.phase)) * 0.025, 0.01), 0.99)) * size.width,
                        y: CGFloat(min(max(Double(seed.y) + cos(time * 0.13 + Double(seed.phase)) * 0.032, 0.01), 0.99)) * size.height
                    )
                }
                let maximumDistance = Double(min(max(size.width * 0.30, 78), 132))

                for first in points.indices {
                    for second in (first + 1)..<points.count {
                        let dx = Double(points[first].x - points[second].x)
                        let dy = Double(points[first].y - points[second].y)
                        let distance = sqrt(dx * dx + dy * dy)
                        guard distance < maximumDistance else { continue }

                        var line = Path()
                        line.move(to: points[first])
                        line.addLine(to: points[second])
                        let opacity = 0.13 * (1 - distance / maximumDistance)
                        context.stroke(line, with: .color(color.opacity(opacity)), lineWidth: 0.55)
                    }
                }

                for (index, point) in points.enumerated() {
                    let radius = Self.seeds[index].radius
                    let glow = CGRect(x: point.x - radius * 2.5, y: point.y - radius * 2.5,
                                      width: radius * 5, height: radius * 5)
                    let core = CGRect(x: point.x - radius, y: point.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: glow), with: .color(color.opacity(0.09)))
                    context.fill(Path(ellipseIn: core), with: .color(color.opacity(0.48)))
                }
            }
        }
        .blendMode(.screen)
        .opacity(0.78)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
