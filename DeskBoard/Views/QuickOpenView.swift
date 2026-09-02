import AppKit
import SwiftUI

struct QuickOpenView: View {
    private let applications = QuickOpenApplication.defaults

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let iconWidth = width * 0.10
            let buttonWidth = width * 0.12
            let spacing = width * 0.075

            HStack(spacing: spacing) {
                ForEach(applications) { application in
                    QuickOpenButton(application: application, iconWidth: iconWidth)
                        .frame(width: buttonWidth, height: 34)
                }
            }
            .padding(.horizontal, width * 0.05)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct QuickOpenButton: View {
    let application: QuickOpenApplication
    let iconWidth: CGFloat
    @State private var isHovering = false

    private var applicationURL: URL? { application.resolveURL() }

    var body: some View {
        Button { openApplication() } label: {
            QuickOpenGlyph(glyph: application.glyph)
                .frame(width: iconWidth, height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(applicationURL == nil ? 0.24 : (isHovering ? 0.82 : 1.0))
        .disabled(applicationURL == nil)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(applicationURL == nil ? "\(application.name) is not installed" : "Open \(application.name)")
        .accessibilityLabel(application.name)
    }

    private func openApplication() {
        guard let applicationURL else { return }
        for bundleIdentifier in application.bundleIdentifiers {
            if let runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                runningApplication.unhide()
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { runningApplication, _ in
            runningApplication?.unhide()
            runningApplication?.activate(options: [.activateAllWindows])
        }
    }
}

private struct QuickOpenGlyph: View {
    let glyph: QuickOpenGlyphKind

    @ViewBuilder
    var body: some View {
        switch glyph {
        case .notion:
            InstalledTemplateGlyph(
                resourcePaths: [
                    "/Applications/Notion.app/Contents/Resources/menuBarIconTemplate@2x.png",
                    "/Applications/Notion.app/Contents/Resources/devMenuBarIconTemplate@2x.png"
                ],
                size: 21,
                fallback: NotionGlyph()
            )
        case .chatGPT:
            InstalledTemplateGlyph(
                resourcePaths: [
                    "/Applications/ChatGPT.app/Contents/Resources/chatgptTemplate@2x.png",
                    "/Applications/ChatGPT.app/Contents/Resources/chatgptTemplate.png"
                ],
                size: 21,
                fallback: ChatGPTGlyph()
            )
        case .kakaoTalk:
            KakaoTalkGlyph()
        case .chrome:
            ChromeGlyph()
        case .finder:
            FinderGlyph()
        }
    }
}

private enum QuickOpenGlyphKind {
    case notion
    case chatGPT
    case kakaoTalk
    case chrome
    case finder
}

private struct InstalledTemplateGlyph<Fallback: View>: View {
    let resourcePaths: [String]
    let size: CGFloat
    let fallback: Fallback

    private let thickeningOffsets = [
        CGSize.zero,
        CGSize(width: -0.30, height: 0),
        CGSize(width: 0.30, height: 0),
        CGSize(width: 0, height: -0.30),
        CGSize(width: 0, height: 0.30)
    ]

    var body: some View {
        Group {
            if let image = templateImage {
                Color.secondary
                    .frame(width: size, height: size)
                    .mask {
                        ZStack {
                            ForEach(Array(thickeningOffsets.enumerated()), id: \.offset) { _, offset in
                                Image(nsImage: image)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .offset(offset)
                            }
                        }
                    }
            } else {
                fallback
            }
        }
        .accessibilityHidden(true)
    }

    private var templateImage: NSImage? {
        for path in resourcePaths {
            guard let source = NSImage(contentsOfFile: path),
                  let image = source.copy() as? NSImage else { continue }
            image.isTemplate = true
            return image
        }
        return nil
    }
}

private struct NotionGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(lineWidth: 2.24)
            Text("N")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .offset(y: -0.35)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

private struct ChatGPTGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) * 0.43
            let innerRadius = min(size.width, size.height) * 0.17
            let color = GraphicsContext.Shading.color(.secondary)
            let style = StrokeStyle(lineWidth: 2.24, lineCap: .round, lineJoin: .round)

            for index in 0..<6 {
                let angle = -Double.pi / 2 + Double(index) * Double.pi / 3
                var petal = Path()
                petal.move(to: point(center: center, radius: innerRadius, angle: angle - 0.38))
                petal.addCurve(
                    to: point(center: center, radius: innerRadius, angle: angle + 0.38),
                    control1: point(center: center, radius: outerRadius, angle: angle - 0.31),
                    control2: point(center: center, radius: outerRadius, angle: angle + 0.31)
                )
                context.stroke(petal, with: color, style: style)
            }

            var centerHexagon = Path()
            for index in 0..<6 {
                let angle = -Double.pi / 2 + Double(index) * Double.pi / 3
                let vertex = point(center: center, radius: innerRadius * 0.82, angle: angle)
                index == 0 ? centerHexagon.move(to: vertex) : centerHexagon.addLine(to: vertex)
            }
            centerHexagon.closeSubpath()
            context.stroke(centerHexagon, with: color, style: style)
        }
        .frame(width: 21, height: 21)
        .accessibilityHidden(true)
    }
}

private struct KakaoTalkGlyph: View {
    var body: some View {
        KakaoTalkBubbleShape()
            .fill(.secondary)
        .frame(width: 21, height: 21)
        .accessibilityHidden(true)
    }
}

private struct KakaoTalkBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.10))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.47),
            control1: CGPoint(x: rect.width * 0.75, y: rect.height * 0.10),
            control2: CGPoint(x: rect.width * 0.92, y: rect.height * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.82),
            control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.68),
            control2: CGPoint(x: rect.width * 0.75, y: rect.height * 0.81)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.94))
        path.addLine(to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.76))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.08, y: rect.height * 0.47),
            control1: CGPoint(x: rect.width * 0.17, y: rect.height * 0.70),
            control2: CGPoint(x: rect.width * 0.08, y: rect.height * 0.61)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.10),
            control1: CGPoint(x: rect.width * 0.08, y: rect.height * 0.24),
            control2: CGPoint(x: rect.width * 0.25, y: rect.height * 0.10)
        )
        path.closeSubpath()
        return path
    }
}

private struct ChromeGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) * 0.44
            let innerRadius = min(size.width, size.height) * 0.20
            let color = GraphicsContext.Shading.color(.secondary)
            let style = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

            var glyph = Path()
            glyph.addEllipse(in: CGRect(
                x: center.x - outerRadius,
                y: center.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            ))
            glyph.addEllipse(in: CGRect(
                x: center.x - innerRadius,
                y: center.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ))

            let clockwiseRotation = Double.pi / 3
            for baseAngle in [-Double.pi / 2, Double.pi / 6, Double.pi * 5 / 6] {
                let outerAngle = baseAngle + clockwiseRotation
                glyph.move(to: point(center: center, radius: outerRadius, angle: outerAngle))
                glyph.addLine(to: point(center: center, radius: innerRadius, angle: outerAngle - Double.pi / 3))
            }
            context.stroke(glyph, with: color, style: style)
        }
        .frame(width: 21, height: 21)
        .accessibilityHidden(true)
    }
}

private struct FinderGlyph: View {
    var body: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(.secondary)
            let style = StrokeStyle(lineWidth: 2.05, lineCap: .round, lineJoin: .round)
            let rect = CGRect(x: 1.7, y: 1.7, width: size.width - 3.4, height: size.height - 3.4)

            var glyph = Path()
            glyph.addRoundedRect(in: rect, cornerSize: CGSize(width: 4.2, height: 4.2))

            glyph.move(to: CGPoint(x: size.width * 0.55, y: rect.minY))
            glyph.addCurve(
                to: CGPoint(x: size.width * 0.52, y: size.height * 0.92),
                control1: CGPoint(x: size.width * 0.47, y: size.height * 0.39),
                control2: CGPoint(x: size.width * 0.40, y: size.height * 0.67)
            )

            glyph.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.35))
            glyph.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.42))
            glyph.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.35))
            glyph.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.42))

            glyph.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.61))
            glyph.addQuadCurve(
                to: CGPoint(x: size.width * 0.78, y: size.height * 0.61),
                control: CGPoint(x: size.width * 0.50, y: size.height * 0.86)
            )
            context.stroke(glyph, with: color, style: style)
        }
        .frame(width: 21, height: 21)
        .accessibilityHidden(true)
    }
}

private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
    CGPoint(
        x: center.x + radius * CGFloat(cos(angle)),
        y: center.y + radius * CGFloat(sin(angle))
    )
}

private struct QuickOpenApplication: Identifiable {
    let id: String
    let name: String
    let bundleIdentifiers: [String]
    let fallbackPaths: [String]
    let glyph: QuickOpenGlyphKind

    func resolveURL() -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }
        return fallbackPaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static let defaults = [
        QuickOpenApplication(
            id: "notion",
            name: "Notion",
            bundleIdentifiers: ["notion.id"],
            fallbackPaths: ["/Applications/Notion.app"],
            glyph: .notion
        ),
        QuickOpenApplication(
            id: "chatgpt",
            name: "ChatGPT",
            bundleIdentifiers: ["com.openai.codex", "com.openai.chat"],
            fallbackPaths: ["/Applications/ChatGPT.app"],
            glyph: .chatGPT
        ),
        QuickOpenApplication(
            id: "kakaotalk",
            name: "KakaoTalk",
            bundleIdentifiers: ["com.kakao.KakaoTalkMac"],
            fallbackPaths: ["/Applications/KakaoTalk.app"],
            glyph: .kakaoTalk
        ),
        QuickOpenApplication(
            id: "chrome",
            name: "Google Chrome",
            bundleIdentifiers: ["com.google.Chrome"],
            fallbackPaths: ["/Applications/Google Chrome.app"],
            glyph: .chrome
        ),
        QuickOpenApplication(
            id: "finder",
            name: "Finder",
            bundleIdentifiers: ["com.apple.finder"],
            fallbackPaths: ["/System/Library/CoreServices/Finder.app"],
            glyph: .finder
        )
    ]
}
