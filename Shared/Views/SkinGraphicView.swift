import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Renders the active 5-state visual skin (or user-uploaded custom PNG) with native WidgetRenderingMode support.
public struct SkinGraphicView: View {
    public let skin: WatchSkinStyle
    public let level: BodyStateLevel
    public let size: CGFloat
    public let isAccented: Bool

    public init(skin: WatchSkinStyle, level: BodyStateLevel, size: CGFloat = 44, isAccented: Bool = false) {
        self.skin = skin
        self.level = level
        self.size = size
        self.isAccented = isAccented
    }

    public var body: some View {
        Group {
            if let data = SharedStore.shared.loadCustomImageData(for: level),
               let image = makePlatformImage(from: data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            } else {
                builtInSkin
                    .frame(width: size, height: size)
            }
        }
    }

    private func makePlatformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private var builtInSkin: some View {
        switch skin {
        case .mascot:
            mascotView
        case .botanical:
            botanicalView
        case .pixel:
            pixelView
        case .orb:
            orbView
        }
    }

    private var mascotView: some View {
        ZStack {
            if isAccented {
                Circle()
                    .stroke(level.color, lineWidth: size * 0.08)
            } else {
                Circle()
                    .fill(level.color.gradient)
            }

            VStack(spacing: size * 0.1) {
                HStack(spacing: size * 0.22) {
                    Circle()
                        .fill(isAccented ? Color.primary : Color.black.opacity(0.85))
                        .frame(width: size * 0.12, height: size * 0.12)
                    Circle()
                        .fill(isAccented ? Color.primary : Color.black.opacity(0.85))
                        .frame(width: size * 0.12, height: size * 0.12)
                }
                MascotMouthShape(level: level)
                    .stroke(isAccented ? Color.primary : Color.black.opacity(0.85),
                            style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .frame(width: size * 0.34, height: size * 0.16)
            }
        }
    }

    private var botanicalView: some View {
        ZStack {
            Circle()
                .fill(level.color.opacity(isAccented ? 0.0 : 0.18))
            Image(systemName: level.rawValue >= 3 ? "leaf.fill" : (level == .balanced ? "leaf" : "wind"))
                .resizable()
                .scaledToFit()
                .padding(size * 0.2)
                .foregroundStyle(level.color)
        }
    }

    private var pixelView: some View {
        VStack(spacing: size * 0.08) {
            Image(systemName: "heart.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.52, height: size * 0.46)
                .foregroundStyle(level.color)
            HStack(spacing: size * 0.04) {
                ForEach(0..<5, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(idx <= level.rawValue ? level.color : Color.secondary.opacity(0.25))
                        .frame(width: size * 0.13, height: size * 0.14)
                }
            }
        }
    }

    private var orbView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: isAccented
                            ? [level.color.opacity(0.6), level.color.opacity(0.15)]
                            : [.white.opacity(0.9), level.color, level.color.opacity(0.25)],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.6
                    )
                )
            Image(systemName: level.sfSymbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

private struct MascotMouthShape: Shape {
    let level: BodyStateLevel

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        switch level {
        case .highStress:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: rect.minY))
        case .mildStress:
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        case .balanced:
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: midY),
                              control: CGPoint(x: rect.midX, y: rect.maxY))
        case .relaxed, .peak:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control: CGPoint(x: rect.midX, y: rect.maxY * 1.15))
        }
        return path
    }
}
