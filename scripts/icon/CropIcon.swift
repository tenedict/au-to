// 앱 아이콘 — 사람이 그린 그림(`docs/whenly.PNG`)에서 잘라 낸다.
//
//   swift scripts/icon/CropIcon.swift docs/whenly.PNG <출력폴더>
//
// ## 왜 잘라 내는가
//
// 원본은 유리 타일이 흰 여백 한가운데 떠 있는 그림이다. 그대로 아이콘으로 쓰면
// 홈 화면에서 **작은 사각형이 흰 판 위에 놓인 것**으로 보인다 — iOS 가 아이콘에
// 다시 여백을 주지 않기 때문이다. 타일이 아이콘을 꽉 채워야 한다.
//
// ## 왜 눈으로 좌표를 찍지 않는가
//
// 원본이 조금만 바뀌어도 좌표가 어긋나고, 어긋난 것은 32pt 아이콘에서만 보인다.
// 그래서 **픽셀에서 타일 경계를 찾는다.** 원본을 다시 그려도 같은 결과가 나온다.
//
// 겪은 함정 — 문턱을 40 으로 뒀더니 그림 맨 가장자리 1~2 픽셀(살짝 어둡다)이
// 잡혀서 "타일 경계 = 그림 전체" 가 됐다. 바깥 8px 을 보지 않고 문턱을 올려 고쳤다.

import AppKit
import ImageIO
import UniformTypeIdentifiers

// docs/whenly.PNG 의 유리 타일만 찾아 정사각형으로 잘라 1024 로 낸다.
// 눈으로 좌표를 찍지 않고 **픽셀에서 경계를 찾는다** — 원본이 바뀌어도 같은 결과가 나온다.
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("못 읽음") }

let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// 배경색은 모서리 한 점이 아니라 **네 귀퉁이 평균**으로 잡는다.
// 이 그림의 흰 배경에는 옅은 비네팅이 있어서, 한 점만 보면 반대쪽 귀퉁이가
// 통째로 "배경이 아님" 으로 잡힌다 — 실제로 그래서 경계가 그림 전체가 됐다.
func sample(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(pixels[i]), Int(pixels[i+1]), Int(pixels[i+2]))
}
let corners = [sample(4, 4), sample(w - 5, 4), sample(4, h - 5), sample(w - 5, h - 5)]
let bg = (corners.map(\.0).reduce(0, +) / 4,
          corners.map(\.1).reduce(0, +) / 4,
          corners.map(\.2).reduce(0, +) / 4)
func differs(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    let d = abs(Int(pixels[i]) - bg.0) + abs(Int(pixels[i+1]) - bg.1) + abs(Int(pixels[i+2]) - bg.2)
    // 문턱이 낮으면 잡음까지 잡힌다. 실제로 40 으로 뒀더니 그림 **맨 가장자리
    // 1~2 픽셀**(223~245 로 살짝 어둡다)이 잡혀서 경계가 그림 전체가 됐다.
    // 유리 테두리는 이보다 훨씬 짙다 (합 460 쯤).
    return d > 120
}
// 바깥 8px 은 아예 보지 않는다. 이 그림은 가장자리가 부드럽게 어두워진다.
let inset = 8
var minX = w, maxX = 0, minY = h, maxY = 0
for y in inset..<(h - inset) { for x in inset..<(w - inset) where differs(x, y) {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
print("배경 \(bg) · 귀퉁이샘플 \(corners)")
print("타일 경계 x \(minX)..\(maxX)  y \(minY)..\(maxY)")

// 정사각형으로 맞추고 여백을 조금 준다. 여백이 0 이면 유리 테두리가 iOS 의
// 모서리 둥글리기에 잘려 나가 테두리가 끊긴 것처럼 보인다.
let side = max(maxX - minX, maxY - minY)
let margin = CGFloat(side) * 0.06
let box = CGFloat(side) + margin * 2
let cx = CGFloat(minX + maxX) / 2, cy = CGFloat(minY + maxY) / 2
let crop = CGRect(x: cx - box / 2, y: cy - box / 2, width: box, height: box).integral
print("자른 곳 \(crop)")
guard let cropped = image.cropping(to: crop) else { fatalError("자르기 실패") }

func write(_ img: CGImage, side: Int, to url: URL) {
    // iOS 앱 아이콘은 알파를 가질 수 없다. noneSkipLast 로 불투명 비트맵을 만든다.
    guard let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }
    out.interpolationQuality = .high
    // 알파가 있는 원본이면 배경을 먼저 깐다.
    out.setFillColor(CGColor(srgbRed: CGFloat(bg.0)/255, green: CGFloat(bg.1)/255,
                             blue: CGFloat(bg.2)/255, alpha: 1))
    out.fill(CGRect(x: 0, y: 0, width: side, height: side))
    out.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let made = out.makeImage(),
          let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError() }
    CGImageDestinationAddImage(dst, made, nil)
    guard CGImageDestinationFinalize(dst) else { fatalError("저장 실패") }
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, side) in [("icon-1024", 1024), ("icon-512", 512), ("icon-512@2x", 1024),
                     ("icon-256", 256), ("icon-256@2x", 512), ("icon-128", 128),
                     ("icon-128@2x", 256), ("icon-32", 32), ("icon-32@2x", 64),
                     ("icon-16", 16), ("icon-16@2x", 32)] {
    write(cropped, side: side, to: outDir.appendingPathComponent("\(name).png"))
}
print("아이콘 11개 완료")
