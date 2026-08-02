import SwiftUI

/// 색.
///
/// **색은 둘뿐이다** — `water`(조작 가능·선택·오늘)와 `past`(마감 경과).
/// 나머지는 전부 무채색이다. 색이 여러 뜻을 맡으면 어느 뜻인지 매번 문맥으로
/// 추론해야 한다. Apple 캘린더의 적색은 "지금" 하나만, 미리 알림의 적색은
/// "지났음" 하나만 뜻한다 (디자인 연구 §7.4).
///
/// **묶음마다 색을 주지 않는다.** 마감 묶음은 순서와 기호로 구분한다 —
/// "위에 있을수록 급하다" 가 이 화면의 유일한 규칙이므로, 색은 그 규칙을
/// 되풀이할 뿐 새 정보를 주지 않는다 (디자인 언어 §4.1).
///
/// 명암비는 계산해서 확인했다. 본문에 쓰는 세 잉크와 두 색이 라이트·다크 모두
/// AA(4.5:1)를 넘는다. 잉크 4 와 괘선은 텍스트에 쓰지 않는다.
enum Palette {

    /// 제목 · 본문 · 활성 아이콘 — 18.1:1 / 15.2:1
    static let ink1 = Color(light: 0x14_16_1A, dark: 0xF2_F4_F7)
    /// 보조 텍스트 · 설명 — 8.1:1 / 9.1:1
    static let ink2 = Color(light: 0x4A_50_5A, dark: 0xB9_C0_CA)
    /// 마감 · 개수 · 부가 표식 — 5.0:1 / 6.0:1
    static let ink3 = Color(light: 0x68_70_7A, dark: 0x94_9C_A7)
    /// 비활성 요소의 **배경**. 텍스트에 쓰지 않는다 (명암비 미달)
    static let ink4 = Color(light: 0xB6_BC_C5, dark: 0x5C_64_6F)

    /// 괘선 · 카드 테두리 1px
    static let line = Color(light: 0xE2_E5_EA, dark: 0x2A_2F_37)
    /// 카드 · 시트
    static let surface = Color(light: 0xFF_FF_FF, dark: 0x1B_1E_23)
    /// 화면 바탕
    static let bed = Color(light: 0xF3_F4_F6, dark: 0x10_12_16)

    /// 조작 가능한 것 · 선택된 것 · 오늘 — 5.4:1 / 7.1:1
    static let water = Color(light: 0x0E_74_90, dark: 0x3F_B6_D8)
    /// 마감 경과 **하나만**. 언제나 기호를 병기한다 — 6.6:1 / 6.0:1
    static let past = Color(light: 0xB4_23_18, dark: 0xF9_70_66)
}

/// 움직임.
///
/// 물은 튀지 않고 **가라앉는다.** 튀는 스프링(damping < 0.7)은 쓰지 않는다 —
/// 물방울이 고무공으로 보인다.
enum Motion {
    /// 맺힘 — 물방울 크기 변화 · 카드 펼침
    static let settle = Animation.spring(response: 0.26, dampingFraction: 0.82)
    /// 스밈 — 나타남 · 사라짐 · 배너
    static let seep = Animation.easeOut(duration: 0.18)
    /// 번짐 — 선택 이동 · 사이드바 전환
    static let spread = Animation.easeInOut(duration: 0.24)
}

extension Color {
    /// 라이트·다크 한 쌍을 16진수로 적는다.
    ///
    /// 에셋 카탈로그를 쓰지 않는 이유는 **값이 코드에서 보여야 하기 때문**이다.
    /// 카탈로그에 넣으면 명암비를 계산한 근거와 값이 서로 다른 곳에 있게 된다.
    fileprivate init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(
            uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            })
        #elseif canImport(AppKit)
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(rgb: isDark ? dark : light)
            })
        #else
        self.init(rgb: light)
        #endif
    }

    fileprivate init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1)
    }
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
#elseif canImport(AppKit)
import AppKit

extension NSColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
#endif
