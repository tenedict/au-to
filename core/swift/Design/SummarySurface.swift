import SwiftUI

/// 요약 타일의 표면.
///
/// ## 왜 이것만 색을 갖는가
///
/// 나머지 화면은 무채색 + 물색 둘뿐이다 (CLAUDE 규칙 16). 이 표면은 **화면에서
/// 유일하게 정보를 담지 않은 면**이라 예외를 둔다 — 여기 칠한 색은 어떤 마감 묶음도
/// 뜻하지 않으므로, "색이 뜻을 갖는다" 는 규칙을 깨지 않는다.
/// 물방울이 유리에 맺힌 제품이니 표면도 유리여야 한다.
///
/// ## 왜 화면 폴더가 아니라 여기 있는가
///
/// iOS 홈 상단과 macOS 사이드바 최상단이 **같은 물건**이어야 하기 때문이다.
/// 각자 그리면 그라디언트 각도나 색이 조금씩 어긋나고, 두 기기를 나란히 놓았을 때
/// 같은 앱으로 보이지 않는다. 화면 구성은 플랫폼마다 다르되 **표면은 하나**다.
///
/// macOS 26 · iOS 26 부터는 시스템 유리를 그 위에 얹는다. 그 아래에서는 같은
/// 인상을 그라디언트만으로 만든다 — 유리가 없다고 회색으로 떨어지면 두 OS 에서
/// 다른 제품이 된다.
struct SummarySurface: View {
    var body: some View {
        LinearGradient(
            colors: Self.stops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // 유리에 얹힌 빛. 위쪽만 살짝 밝혀 평평한 색면이 되지 않게 한다.
            LinearGradient(
                colors: [.white.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .glassIfAvailable()
    }

    /// 파스텔 세 단.
    ///
    /// **흰 글씨가 어디서든 읽혀야 하므로 밝은 쪽을 너무 밝히지 않는다.**
    /// 파스텔의 인상은 채도를 낮춰서 만들고 명도로 만들지 않는다 — 명도로 만들면
    /// 흰 글씨의 명암비가 무너진다.
    static let stops: [Color] = [
        Color(.sRGB, red: 0.38, green: 0.60, blue: 0.86, opacity: 1),
        Color(.sRGB, red: 0.55, green: 0.52, blue: 0.85, opacity: 1),
        Color(.sRGB, red: 0.36, green: 0.68, blue: 0.78, opacity: 1),
    ]
}

extension View {
    /// 요약 타일 하나를 만든다. 여백·모서리·그림자까지 여기서 정한다 —
    /// 화면마다 다르게 주면 두 기기의 타일이 다른 물건으로 보인다.
    func summaryTileSurface() -> some View {
        self
            .padding(.horizontal, Space.gap4)
            .padding(.vertical, Space.gap4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SummarySurface())
            .clipShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            // 그림자는 얕게. 떠 보이면 화면이 두 겹으로 읽힌다.
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }
}

extension View {
    /// 시스템 유리를 쓸 수 있으면 그 위에 얹는다.
    ///
    /// 물방울(`DropletView`)은 `.clear` 를 쓴다 — 뒤가 보여야 물방울이다.
    /// 여기서는 글씨를 얹는 표면이라 `.regular` 다. 뒤가 그대로 비치면
    /// 흰 글씨가 읽히는지가 뒤에 있는 것에 따라 달라진다.
    @ViewBuilder
    fileprivate func glassIfAvailable() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: Radius.surface))
        } else {
            self
        }
    }
}

/// 지금 상태를 큰 숫자로 먼저 말하는 타일.
///
/// **목록에 들어가기 전에 "지금 어떤가" 를 말한다** (디자인 연구 §6.3 · 디자인 언어 §10.6).
///
/// iOS 홈 상단과 macOS 사이드바 최상단이 **이 하나를 함께 쓴다.** 화면 파일은
/// 플랫폼마다 다른 것이 맞지만, 이건 화면이 아니라 **표식에 가깝다** — 두 기기에서
/// 다르게 생기면 같은 앱으로 보이지 않는다. 배치만 각자 정하고 생김새는 여기 하나다.
struct SummaryTile: View {
    let summary: TaskScoping.Summary
    /// "확인할 것" 을 눌렀을 때. 없으면 누를 수 없는 숫자로 그린다.
    var onTapReview: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.gap5) {
            if summary.isClear {
                // 0 을 셋 나열하면 "아무 일도 없다" 가 숫자로만 전달된다. 말로 한다.
                Label("지금은 급한 게 없어요", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            } else {
                Figure(value: summary.overdue, label: "지난 마감")
                Figure(value: summary.today, label: "오늘")
                if summary.needsReview > 0 {
                    if let onTapReview {
                        Button(action: onTapReview) {
                            Figure(value: summary.needsReview, label: "확인할 것")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Figure(value: summary.needsReview, label: "확인할 것")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .summaryTileSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard !summary.isClear else { return "지금은 급한 게 없어요" }
        var parts = ["지난 마감 \(summary.overdue)건", "오늘 \(summary.today)건"]
        if summary.needsReview > 0 { parts.append("확인할 것 \(summary.needsReview)건") }
        return parts.joined(separator: ", ")
    }

    /// 큰 숫자 하나와 그 이름.
    ///
    /// **여기서는 지난 마감에도 붉은색을 쓰지 않는다.** 색 있는 표면 위의 붉은
    /// 글씨는 명암비가 무너지고, 급함은 **왼쪽이라는 자리**가 이미 말하고 있다.
    private struct Figure: View {
        /// 컬렉션이 아니라 개수다. 이름을 `count` 로 두면 린터가 `isEmpty` 를 쓰라고 한다.
        let value: Int
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
