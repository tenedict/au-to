import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 앱 아이콘 — 유리에 맺힌 물방울 하나.
//
//   swift scripts/icon/MakeIcon.swift <출력폴더>
//
// ## 왜 이 그림인가
//
// 예전 아이콘은 물방울 안으로 색 막대 세 개가 빨려 들어가는 그림이었다.
// "정리된다" 를 설명하려던 것인데, 1024 에서만 읽히고 32pt 에서는 막대가 뭉개져
// 정체를 알 수 없는 얼룩이 됐다. 게다가 제품의 물방울(떠 있는 것 · 메뉴바)과
// 닮은 데가 없어서 같은 앱으로 보이지 않았다.
//
// 지금은 **물방울 하나**다. 제품 안의 물방울과 같은 윤곽을 쓰고,
// 작아져도 실루엣 하나가 남는다.
//
// ## 사실적으로 보이게 하는 것
//
// 물방울이 물방울로 읽히는 이유는 굴절이 아니라 **빛의 순서**다.
//
//   1. 뒤가 비친다      물방울 안에 배경을 **뒤집어** 다시 그린다. 실제 물방울이
//                       렌즈라서 뒤의 상이 상하로 뒤집혀 보인다 — 이것 하나가
//                       "그린 원" 과 "맺힌 물" 을 가른다
//   2. 가장자리가 어둡다  빛이 비껴 나가 테두리가 짙다. 흰 림만 쓰면 밝은 배경에서 사라진다
//   3. 얇은 밝은 선      유리에 닿은 물의 경계
//   4. 광점 둘          왼쪽 위의 작고 밝은 주광, 오른쪽 아래의 넓고 옅은 환경광
//   5. 그림자와 초점광   아래에 닿은 그림자, 그 안에 렌즈가 모은 밝은 점
//
// 배경은 빨강 → 파랑 → 초록 대각 그라디언트다. 색이 셋이라 물방울 안에 뒤집혀
// 비칠 때 **위아래 색이 확실히 달라지고**, 그 어긋남이 굴절을 읽히게 만든다.
// 단색 배경 위에서는 뒤집어도 아무 차이가 없어 이 효과가 통째로 사라진다.
//
// 손으로 그리지 않고 스크립트로 짓는 이유 — 색이나 각도를 고칠 때 모든 크기를
// 다시 만들어야 하는데, 손으로 하면 어느 크기 하나가 반드시 옛것으로 남는다.

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - 색

/// 배경 그라디언트 — 빨강 · 파랑 · 초록.
///
/// 순도 높은 원색을 그대로 쓰지 않는다. 세 색을 최대 채도로 이으면 경계마다
/// 탁한 띠(자주색 · 청록색)가 생겨 아이콘이 지저분해진다. 채도를 조금 낮추고
/// 명도를 비슷하게 맞추면 경계가 부드럽게 넘어간다.
let backgroundStops: [(color: NSColor, location: CGFloat)] = [
    (NSColor(srgbRed: 0.94, green: 0.26, blue: 0.31, alpha: 1), 0.00),  // 빨
    (NSColor(srgbRed: 0.85, green: 0.30, blue: 0.52, alpha: 1), 0.24),
    (NSColor(srgbRed: 0.24, green: 0.42, blue: 0.92, alpha: 1), 0.55),  // 파
    (NSColor(srgbRed: 0.13, green: 0.68, blue: 0.72, alpha: 1), 0.80),
    (NSColor(srgbRed: 0.16, green: 0.76, blue: 0.42, alpha: 1), 1.00),  // 초
]

// MARK: - 윤곽

/// 유리에 맺힌 물방울의 윤곽. **완벽한 원이 아니다.**
///
/// 아래가 조금 넓고 평평하고(중력), 위가 더 둥글고(표면장력), 좌우가 완전히
/// 대칭이 아니다(닿은 자리의 치우침). 그 어긋남이 도형과 물을 가른다.
///
/// 계수는 앱의 `Bead.cgPath(in:)`(`apps/macos/Views/BeadShape.swift`)와 같다.
/// 이 스크립트는 앱 코드를 가져다 쓸 수 없어서 값을 옮겨 적었다 — 한쪽을 고치면
/// 다른 쪽도 고쳐야 하고, 안 고치면 아이콘과 앱 속 물방울이 다른 물건으로 보인다.
///
/// 좌표계는 AppKit 기준이라 **y 가 위로 자란다.** 앱 쪽(SwiftUI · y 가 아래로)과
/// 위아래가 반대라, "위가 더 둥글다" 를 만드는 반지름의 자리도 반대다.
func beadPath(in rect: CGRect) -> NSBezierPath {
    let cx = rect.midX, cy = rect.midY
    let radiusLeft = rect.width * 0.500
    let radiusRight = rect.width * 0.487    // 좌우 살짝 비대칭
    let radiusTop = rect.height * 0.512     // 위가 높고
    let radiusBottom = rect.height * 0.470  // 아래가 눌림
    let k: CGFloat = 0.5523

    let path = NSBezierPath()
    path.move(to: CGPoint(x: cx, y: cy + radiusTop))  // 꼭대기
    path.curve(  // → 오른쪽
        to: CGPoint(x: cx + radiusRight, y: cy),
        controlPoint1: CGPoint(x: cx + radiusRight * k * 1.02, y: cy + radiusTop),
        controlPoint2: CGPoint(x: cx + radiusRight, y: cy + radiusTop * k * 1.02))
    path.curve(  // → 바닥 (평평)
        to: CGPoint(x: cx, y: cy - radiusBottom),
        controlPoint1: CGPoint(x: cx + radiusRight, y: cy - radiusBottom * k * 1.20),
        controlPoint2: CGPoint(x: cx + radiusRight * k * 1.18, y: cy - radiusBottom))
    path.curve(  // → 왼쪽
        to: CGPoint(x: cx - radiusLeft, y: cy),
        controlPoint1: CGPoint(x: cx - radiusLeft * k * 1.18, y: cy - radiusBottom),
        controlPoint2: CGPoint(x: cx - radiusLeft, y: cy - radiusBottom * k * 1.20))
    path.curve(  // → 꼭대기
        to: CGPoint(x: cx, y: cy + radiusTop),
        controlPoint1: CGPoint(x: cx - radiusLeft, y: cy + radiusTop * k * 0.98),
        controlPoint2: CGPoint(x: cx - radiusLeft * k * 0.98, y: cy + radiusTop))
    path.close()
    return path
}

// MARK: - 그리기 도구

/// 배경 그라디언트를 그린다. 물방울 안에도 같은 함수를 쓴다 — 안팎이 다른 그림이면
/// 비쳐 보이는 것이 아니라 그냥 다른 무늬가 된다.
func drawBackground(in ctx: CGContext, rect: CGRect) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: backgroundStops.map(\.color.cgColor) as CFArray,
        locations: backgroundStops.map(\.location)
    ) else { return }

    // 왼쪽 위 → 오른쪽 아래 대각. 세로나 가로로 두면 물방울 안의 뒤집힘이
    // 대칭이라 눈에 덜 띈다.
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

/// 흐릿한 타원. 겹겹이 그려서 번짐을 흉내 낸다.
///
/// `CGContext` 에는 안으로 번지는 흐림이 없다. CoreImage 를 끌어오면 되지만,
/// 아이콘 하나 만들자고 이미지 파이프라인을 붙이는 것보다 이쪽이 읽기 쉽다.
func softEllipse(
    in ctx: CGContext,
    rect: CGRect,
    color: NSColor,
    spread: CGFloat,
    layers: Int = 14
) {
    for step in 0..<layers {
        let t = CGFloat(step) / CGFloat(layers - 1)
        // 바깥으로 갈수록 넓고 옅다. 알파를 제곱으로 떨어뜨려야 가운데가 또렷하다.
        let grow = spread * t
        let alpha = (1 - t) * (1 - t)
        ctx.setFillColor(color.withAlphaComponent(color.alphaComponent * alpha).cgColor)
        ctx.fillEllipse(in: rect.insetBy(dx: -grow, dy: -grow))
    }
}

// MARK: - 아이콘

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
    let s = CGFloat(pixels)
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

    let full = CGRect(x: 0, y: 0, width: s, height: s)

    // ── 1. 배경 ───────────────────────────────────────────
    // iOS 앱 아이콘은 알파를 가질 수 없다. 반드시 꽉 채운다.
    drawBackground(in: ctx, rect: full)

    // ── 2. 곁방울 ─────────────────────────────────────────
    // 큰 방울 하나만 두면 "물방울 그림" 이고, 작은 것이 몇 개 흩어져 있으면
    // **유리에 맺힌 것**이 된다. 큰 방울보다 먼저 그려 뒤로 물러나게 한다.
    let sideBeads: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.215, 0.760, 0.052),
        (0.800, 0.735, 0.038),
        (0.170, 0.300, 0.034),
        (0.845, 0.268, 0.048),
    ]
    for bead in sideBeads {
        drawBead(
            in: ctx,
            frame: CGRect(
                x: s * (bead.x - bead.r), y: s * (bead.y - bead.r),
                width: s * bead.r * 2, height: s * bead.r * 2),
            canvas: full,
            scale: s,
            isMain: false)
    }

    // ── 3. 주 방울 ────────────────────────────────────────
    let side = s * 0.580
    drawBead(
        in: ctx,
        // 중력에 눌려 가로가 조금 더 넓다. 정원으로 두면 구슬로 보인다.
        frame: CGRect(x: (s - side) / 2, y: s * 0.215, width: side, height: side * 0.945),
        canvas: full,
        scale: s,
        isMain: true)

    guard let image = ctx.makeImage() else {
        fatalError("이미지를 뽑아내지 못했습니다")
    }
    return image
}

/// 물방울 하나. 층의 **순서가 곧 광학**이라 이 순서를 바꾸면 물처럼 보이지 않는다.
func drawBead(
    in ctx: CGContext,
    frame: CGRect,
    canvas: CGRect,
    scale s: CGFloat,
    isMain: Bool
) {
    let path = beadPath(in: frame)
    let cg = path.cgPath
    let diameter = frame.width

    // ── 닿은 그림자 ───────────────────────────────────────
    // 물방울은 유리에 **닿아** 있지 떠 있지 않다. 그림자를 아래로 조금만 내리고
    // 얕게 편다. 멀리 떨어뜨리면 공중에 뜬 구슬이 된다.
    ctx.saveGState()
    softEllipse(
        in: ctx,
        rect: CGRect(
            x: frame.minX + diameter * 0.10,
            y: frame.minY - diameter * 0.035,
            width: diameter * 0.80,
            height: diameter * 0.20),
        color: NSColor(srgbRed: 0.04, green: 0.05, blue: 0.10, alpha: 0.30),
        spread: diameter * 0.055)
    ctx.restoreGState()

    // ── 굴절 — 뒤가 뒤집혀 비친다 ─────────────────────────
    // 물방울은 렌즈다. 안에 배경을 **상하로 뒤집어** 다시 그린다.
    // 이것 하나가 "그린 원" 과 "맺힌 물" 을 가른다.
    ctx.saveGState()
    ctx.addPath(cg)
    ctx.clip()
    ctx.translateBy(x: frame.midX, y: frame.midY)
    // 1보다 크게 잡아야 렌즈가 확대하는 느낌이 난다.
    // **줄여서** 그린다. 확대가 아니다.
    //
    // 유리에 맺힌 물방울은 광각 렌즈처럼 굴어서, 뒤의 넓은 장면이 방울 안에
    // **압축되어 뒤집힌 채** 들어온다. 확대(2.1배)로 만들었더니 방울 안이 배경의
    // 가운데 한 구간만 담아 통째로 파랗게 굳었고, 뒤집은 티가 사라져
    // 플라스틱 구슬이 됐다. 줄이면 방울 하나에 배경의 빨강부터 초록까지가
    // 다 들어와, 바깥과 위아래가 뚜렷이 어긋난다.
    ctx.scaleBy(x: 0.60, y: -0.60)
    ctx.translateBy(x: -frame.midX, y: -frame.midY)
    drawBackground(in: ctx, rect: canvas)
    ctx.restoreGState()

    // 물빛을 아주 옅게 얹는다. 없으면 굴절한 배경이 너무 쨍해서 유리가 아니라
    // 오려 붙인 조각으로 보인다.
    ctx.saveGState()
    ctx.addPath(cg)
    ctx.clip()
    // 아주 옅게. 0.16 은 굴절한 색을 덮어 버려서 안이 뿌옇게 보였다.
    ctx.setFillColor(NSColor(srgbRed: 0.86, green: 0.95, blue: 1.00, alpha: 0.06).cgColor)
    ctx.fill(frame.insetBy(dx: -diameter, dy: -diameter))
    ctx.restoreGState()

    // ── 가장자리 그늘 ─────────────────────────────────────
    // 흰 배경에서도 물방울이 보이게 하는 것은 이 층 하나다. 흰 림만 쓰면
    // 밝은 곳에서 통째로 사라진다. 실제 물방울도 가장자리에서 빛이 비껴 나가 어둡다.
    ctx.saveGState()
    ctx.addPath(cg)
    ctx.clip()
    if let edge = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.clear.cgColor,
            NSColor(srgbRed: 0.02, green: 0.04, blue: 0.10, alpha: 0.46).cgColor,
        ] as CFArray,
        locations: [0.62, 1.0]
    ) {
        ctx.drawRadialGradient(
            edge,
            startCenter: CGPoint(x: frame.midX, y: frame.midY), startRadius: 0,
            endCenter: CGPoint(x: frame.midX, y: frame.midY), endRadius: diameter / 2,
            options: [])
    }
    ctx.restoreGState()

    // ── 얇은 밝은 선 — 유리에 닿은 물의 경계 ──────────────
    ctx.saveGState()
    ctx.addPath(cg)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    ctx.setLineWidth(max(diameter * 0.008, s * 0.0015))
    ctx.strokePath()
    ctx.restoreGState()

    // ── 광점 둘 ───────────────────────────────────────────
    ctx.saveGState()
    ctx.addPath(cg)
    ctx.clip()

    // 아래 초승달 — 물방울을 통과한 빛이 아래쪽 안쪽 벽에 모인다.
    //
    // 방울보다 조금 작은 도형을 위로 밀어 올려, 겹치지 않고 남는 아래쪽
    // 테두리만 밝힌다. **얇고 옅어야 한다** — 두껍게 하면 흰 플라스틱 테가
    // 되어 물방울이 통째로 장난감처럼 보였다.
    ctx.saveGState()
    let crescent = beadPath(in: frame.insetBy(dx: diameter * 0.030, dy: diameter * 0.030)
        .offsetBy(dx: 0, dy: diameter * 0.036))
    ctx.addPath(crescent.cgPath)
    ctx.addPath(CGPath(rect: frame.insetBy(dx: -diameter, dy: -diameter), transform: nil))
    ctx.clip(using: .evenOdd)
    // 아래에서 위로 사그라든다. 네모로 잘라 아래쪽만 남기면 **잘린 자리가
    // 가로선으로 보인다** — 실제로 좌우 양옆에 직선 두 개가 생겼다.
    if let fade = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.white.withAlphaComponent(0.46).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            fade,
            start: CGPoint(x: frame.midX, y: frame.minY),
            end: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.42),
            options: [.drawsBeforeStartLocation])
    }
    ctx.restoreGState()

    // 주광 — **작고 또렷하다.** 왼쪽 위. 크게 그리면 흰 얼룩이 되고,
    // 물방울이 아니라 도색이 벗겨진 플라스틱으로 보인다.
    softEllipse(
        in: ctx,
        rect: CGRect(
            x: frame.midX - diameter * 0.30,
            y: frame.midY + diameter * 0.14,
            width: diameter * 0.145,
            height: diameter * 0.105),
        color: NSColor.white.withAlphaComponent(0.98),
        spread: diameter * 0.022)

    // 그 옆의 작은 점 하나. 광원이 정확히 하나인 물체는 렌더링처럼 보인다.
    softEllipse(
        in: ctx,
        rect: CGRect(
            x: frame.midX - diameter * 0.13,
            y: frame.midY + diameter * 0.235,
            width: diameter * 0.058,
            height: diameter * 0.042),
        color: NSColor.white.withAlphaComponent(0.70),
        spread: diameter * 0.014)
    ctx.restoreGState()

    // ── 초점광 ────────────────────────────────────────────
    // 렌즈가 모은 빛이 그림자 안에 밝은 점을 남긴다. 큰 방울에만 둔다 —
    // 작은 방울에서는 몇 픽셀이라 얼룩으로만 보인다.
    guard isMain else { return }
    ctx.saveGState()
    softEllipse(
        in: ctx,
        rect: CGRect(
            x: frame.midX - diameter * 0.16,
            y: frame.minY - diameter * 0.005,
            width: diameter * 0.32,
            height: diameter * 0.075),
        color: NSColor(srgbRed: 1.0, green: 0.98, blue: 0.86, alpha: 0.42),
        spread: diameter * 0.04)
    ctx.restoreGState()
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
