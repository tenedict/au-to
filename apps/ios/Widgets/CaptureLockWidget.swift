import SwiftUI
import WidgetKit

/// 잠금화면 위젯 — **눌러서 바로 찍기.**
///
/// 표식은 맥 메뉴바 아이콘과 **같은 물방울 윤곽**(`Bead`)이다. 두 기기에서 다른
/// 그림을 쓰면 같은 제품으로 보이지 않는다.
///
/// 누르면 `whenly://capture` 로 앱이 열리고 곧바로 카메라가 뜬다.
/// 종이 안내문이나 화이트보드처럼 **스크린샷이 존재하지 않는 것**을 담는 길이
/// 지금까지 없었다 — 사진을 먼저 찍고, 앨범에 들어가고, 공유하고, 골라야 했다.
/// 잠금화면에서 한 번 누르는 것으로 그 넷을 없앤다.
///
/// 셋 다 만드는 이유는 사용자가 어느 자리를 비워 뒀는지 알 수 없기 때문이다.
///
/// | 원형 | 시계 아래 작은 자리. 표식만 |
/// | 사각형 | 표식 + 다음 일정 한 줄 |
/// | 인라인 | 시계 위 한 줄. 글자만 (시스템이 도형을 그리지 않는다) |
struct CaptureLockWidget: Widget {
    static let kind = "WhenlyCapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            CaptureLockView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(DeepLink.capture)
        }
        .configurationDisplayName("찍어서 담기")
        .description("누르면 카메라가 열리고, 찍으면 바로 일정으로 등록해요.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CaptureLockView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    /// 원형 — 표식 하나.
    ///
    /// 잠금화면 위젯은 **틴트가 씌워진다.** 시스템이 알파 채널만 보고 색을 스스로
    /// 칠하므로, 여기서 정할 수 있는 것은 메뉴바 아이콘과 마찬가지로 실루엣뿐이다.
    /// 그래서 광점을 파내지 않고 **채운다** — 이 크기에서 파내면 선과 구멍 사이가
    /// 1pt 아래로 내려가 뭉갠다.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            BeadMark()
                .padding(7)
        }
        .accessibilityLabel("찍어서 담기")
    }

    /// 사각형 — 표식과 다음 일정 한 줄.
    ///
    /// 여기까지만 일정을 보여준다. 원형에 글자를 넣으면 두 글자밖에 안 들어가
    /// 무엇인지 알 수 없고, 인라인은 시스템이 한 줄로 압축한다.
    private var rectangular: some View {
        HStack(spacing: 8) {
            BeadMark()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("찍어서 담기")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .widgetAccentable(false)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        // 인라인에는 도형이 들어가지 않는다. 시스템이 기호 하나와 글자만 그린다.
        Label(subtitle, systemImage: "camera.fill")
    }

    /// 다음 일정 한 줄. 없으면 무엇을 하는 위젯인지 말한다 —
    /// 빈 줄을 두면 사용자는 위젯이 고장 난 것으로 읽는다.
    private var subtitle: String {
        guard let next = entry.snapshot.upcoming.first else { return "다음 일정 없음" }
        let when = DueDateText.string(
            for: next.dueDate,
            hasExplicitTime: next.hasExplicitTime,
            width: .narrow,
            now: entry.date)
        return "\(when) \(next.title)"
    }
}

/// 잠금화면용 물방울 표식.
///
/// 맥 메뉴바 아이콘(`MenuBarIcon`)과 같은 구성이다 — 윤곽선 하나와 채운 광점 하나.
/// 두 자리의 그림이 다르면 같은 물건으로 보이지 않는다.
private struct BeadMark: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                BeadShape()
                    .strokeBorder(.primary, lineWidth: max(side * 0.085, 1))
                // 광점은 파내지 않고 채운다. 작은 크기에서 파내면 선과 구멍
                // 사이가 뭉개져 그냥 두꺼운 원이 된다.
                Circle()
                    .fill(.primary)
                    .frame(width: side * Bead.highlightRadius * 2 * 0.82)
                    .offset(
                        x: side * Bead.highlightOffset.x * 0.82,
                        y: side * Bead.highlightOffset.y * 0.82)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
