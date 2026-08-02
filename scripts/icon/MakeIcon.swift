import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// CaptureTask 앱 아이콘.
//
// 물방울 안으로 할 일 세 개가 사방에서 빨려 들어간다 — 이 제품이 하는 일 그대로다.
// 흩어져 있던 것(스크린샷)이 한 곳으로 모여 정리된다.
//
//   swift scripts/icon/MakeIcon.swift <출력폴더>
//
// 손으로 그리지 않고 스크립트로 짓는 이유 — 색이나 각도를 고칠 때 모든 크기를
// 다시 만들어야 하는데, 손으로 하면 어느 크기 하나가 반드시 옛것으로 남는다.

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - 색

/// 할 일 세 개. 빨강은 급한 것, 노랑은 다가오는 것, 파랑은 그 뒤.
/// 마감 묶음의 색 언어와 같은 계열을 쓴다.
let taskColors: [NSColor] = [
    NSColor(srgbRed: 0.98, green: 0.30, blue: 0.31, alpha: 1),  // 빨
    NSColor(srgbRed: 1.00, green: 0.78, blue: 0.19, alpha: 1),  // 노
    NSColor(srgbRed: 0.20, green: 0.55, blue: 1.00, alpha: 1),  // 파
]

// MARK: - 그리기

/// 물방울 윤곽. 위가 뾰족하고 아래가 둥근 고전적인 모양.
func dropletPath(in rect: CGRect) -> NSBezierPath {
    let w = rect.width, h = rect.height
    let x = rect.minX, y = rect.minY

    // 아래쪽 원의 중심과 반지름
    let r = w * 0.5
    let cx = x + w * 0.5
    let cy = y + r

    let path = NSBezierPath()
    // 꼭짓점 (위)
    path.move(to: CGPoint(x: cx, y: y + h))
    // 오른쪽 옆선 → 원의 오른쪽 끝
    path.curve(
        to: CGPoint(x: cx + r, y: cy),
        controlPoint1: CGPoint(x: cx + w * 0.18, y: y + h * 0.62),
        controlPoint2: CGPoint(x: cx + r, y: y + h * 0.46)
    )
    // 아래 반원
    path.appendArc(
        withCenter: CGPoint(x: cx, y: cy),
        radius: r,
        startAngle: 0,
        endAngle: 180,
        clockwise: true
    )
    // 왼쪽 옆선 → 꼭짓점
    path.curve(
        to: CGPoint(x: cx, y: y + h),
        controlPoint1: CGPoint(x: cx - r, y: y + h * 0.46),
        controlPoint2: CGPoint(x: cx - w * 0.18, y: y + h * 0.62)
    )
    path.close()
    return path
}

/// 할 일 막대 하나. 물방울 중심을 향해 기울어져 들어간다.
func taskBar(center: CGPoint, angle: CGFloat, length: CGFloat, thickness: CGFloat) -> NSBezierPath {
    let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
    let rounded = NSBezierPath(roundedRect: rect, xRadius: thickness / 2, yRadius: thickness / 2)
    var transform = AffineTransform(translationByX: center.x, byY: center.y)
    transform.rotate(byRadians: angle)
    rounded.transform(using: transform)
    return rounded
}

/// 정확히 `pixels` 픽셀짜리 불투명 비트맵을 만든다.
///
/// `NSImage.lockFocus()` 를 쓰면 안 된다 — Retina 화면의 배율(2x)이 적용돼
/// **요청한 것의 두 배** 크기로 그려진다. `rep.size` 를 나중에 고쳐도 픽셀 수는 그대로다.
/// 실제로 1024 를 요청했는데 2048 이 나와 Xcode 가 아이콘을 거부했다.
///
/// `CGContext` 를 직접 만드는 이유는 두 가지다.
///   · 픽셀 수를 못 박는다 (배율이 끼어들 자리가 없다)
///   · `noneSkipLast` 로 **알파가 없는** 비트맵을 만든다 — iOS 앱 아이콘은
///     투명도를 가질 수 없고, `NSBitmapImageRep` 는 알파 없는 그리기 문맥을 만들지 못한다
func makeIcon(size pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("그리기 문맥을 만들지 못했습니다")
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let s = size
    let full = CGRect(x: 0, y: 0, width: s, height: s)

    // ── 배경 ──────────────────────────────────────────────
    // iOS 앱 아이콘은 알파를 가질 수 없다. 반드시 꽉 채운다.
    let background = NSGradient(
        colors: [
            NSColor(srgbRed: 0.72, green: 0.87, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.38, green: 0.66, blue: 0.95, alpha: 1),
        ]
    )
    background?.draw(in: full, angle: -90)

    // ── 물방울 ────────────────────────────────────────────
    let dropWidth = s * 0.50
    let dropHeight = s * 0.62
    let dropRect = CGRect(
        x: (s - dropWidth) / 2,
        y: s * 0.17,
        width: dropWidth,
        height: dropHeight
    )
    let drop = dropletPath(in: dropRect)
    let center = CGPoint(x: dropRect.midX, y: dropRect.minY + dropWidth * 0.5)

    // ── 할 일 막대 세 개 ──────────────────────────────────
    //
    // **물방울보다 먼저 그린다.** 막대가 밖에서 안으로 가로지르고, 그 위에 반투명한
    // 유리를 덮으면 안쪽 부분이 물속에 잠긴 것처럼 보인다 — 그게 "들어간다" 는 그림이다.
    // 유리 안에 가둬 그리면 그냥 무늬가 된다.
    let barLength = s * 0.34
    let barThickness = s * 0.072
    // 사방에서 온다. 위, 오른쪽 아래, 왼쪽 아래.
    let bars: [(angle: CGFloat, from: CGFloat)] = [
        (.pi * 0.50, s * 0.200),   // 위에서
        (-.pi * 0.17, s * 0.205),  // 오른쪽에서
        (.pi * 1.17, s * 0.205),   // 왼쪽에서
    ]

    for (index, color) in taskColors.enumerated() {
        let (angle, distance) = bars[index]
        // 막대 중심을 물방울 중심에서 바깥쪽으로 밀어, 한쪽 끝만 안에 들어가게 한다.
        let barCenter = CGPoint(
            x: center.x + cos(angle) * distance,
            y: center.y + sin(angle) * distance
        )
        let bar = taskBar(
            center: barCenter,
            angle: angle,
            length: barLength,
            thickness: barThickness
        )

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.008),
            blur: s * 0.022,
            color: NSColor(srgbRed: 0.10, green: 0.22, blue: 0.45, alpha: 0.30).cgColor
        )
        color.setFill()
        bar.fill()
        ctx.restoreGState()
    }

    // ── 물방울 유리 ───────────────────────────────────────
    // 막대 위에 덮는다. 반투명이라 안쪽 막대가 비쳐 보인다.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.016),
        blur: s * 0.055,
        color: NSColor(srgbRed: 0.10, green: 0.28, blue: 0.55, alpha: 0.30).cgColor
    )
    ctx.saveGState()
    drop.addClip()
    NSGradient(
        colors: [
            NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.42),
            NSColor(srgbRed: 0.88, green: 0.95, blue: 1.00, alpha: 0.56),
        ]
    )?.draw(in: dropRect, angle: -90)

    // 위쪽 하이라이트 — 유리 느낌의 핵심. 물방울 곡선을 따라 눕힌다.
    let highlight = NSBezierPath(
        ovalIn: CGRect(
            x: dropRect.minX + dropWidth * 0.17,
            y: dropRect.minY + dropHeight * 0.56,
            width: dropWidth * 0.40,
            height: dropHeight * 0.17
        )
    )
    var tilt = AffineTransform(translationByX: dropRect.midX, byY: dropRect.midY)
    tilt.rotate(byDegrees: -22)
    tilt.translate(x: -dropRect.midX, y: -dropRect.midY)
    highlight.transform(using: tilt)
    NSColor.white.withAlphaComponent(0.52).setFill()
    highlight.fill()

    // 아래쪽 반사 — 빛이 바닥에서 한 번 더 튄다
    let bounce = NSBezierPath(
        ovalIn: CGRect(
            x: dropRect.minX + dropWidth * 0.30,
            y: dropRect.minY + dropHeight * 0.08,
            width: dropWidth * 0.40,
            height: dropHeight * 0.07
        )
    )
    NSColor.white.withAlphaComponent(0.30).setFill()
    bounce.fill()
    ctx.restoreGState()
    ctx.restoreGState()

    // 유리의 가장자리 — 두 겹으로 긋는다.
    // 한 겹만 흰색으로 그으면 밝은 배경에서 묻혀, 작은 크기에서 형태가 사라진다.
    NSColor(srgbRed: 0.18, green: 0.45, blue: 0.80, alpha: 0.28).setStroke()
    drop.lineWidth = s * 0.022
    drop.stroke()
    NSColor.white.withAlphaComponent(0.95).setStroke()
    drop.lineWidth = s * 0.013
    drop.stroke()

    guard let image = ctx.makeImage() else {
        fatalError("이미지를 뽑아내지 못했습니다")
    }
    return image
}

// MARK: - 내보내기

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

try FileManager.default.createDirectory(
    at: outputDirectory, withIntermediateDirectories: true
)

// iOS 는 1024 하나로 충분하다 (Xcode 가 나머지를 만든다).
// macOS 는 icns 규격 크기를 전부 요구한다.
let sizes: [(name: String, pixels: Int)] = [
    ("icon-1024", 1024),
    ("icon-512", 512), ("icon-512@2x", 1024),
    ("icon-256", 256), ("icon-256@2x", 512),
    ("icon-128", 128), ("icon-128@2x", 256),
    ("icon-32", 32), ("icon-32@2x", 64),
    ("icon-16", 16), ("icon-16@2x", 32),
]

for (name, pixels) in sizes {
    let image = makeIcon(size: pixels)
    // 요청한 크기와 다르면 그대로 내보내지 않는다. 한 번 이걸로 아이콘이 거부됐다.
    guard image.width == pixels, image.height == pixels else {
        fatalError("\(name): \(pixels) 를 요청했는데 \(image.width)×\(image.height) 가 나왔습니다")
    }
    try write(image, to: outputDirectory.appendingPathComponent("\(name).png"))
}

print("아이콘 \(sizes.count)개를 만들었습니다 → \(outputDirectory.path)")
