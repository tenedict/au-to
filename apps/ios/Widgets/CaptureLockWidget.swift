import SwiftUI
import WidgetKit

/// 잠금화면 위젯 — **눌러서 바로 찍기.**
///
/// 표식은 맥 메뉴바 아이콘·앱 아이콘과 **같은 것**(`Mark`)이다. 자리마다 다른
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
    ///
    /// 뒤에 `AccessoryWidgetBackground()` 를 깔지 않는다. 그건 시스템이 주는
    /// **흐린 원판**인데, 깔면 배경화면이 그 원만큼 뿌예져서 표식이 유리에 놓인 것이
    /// 아니라 **접시 위에 놓인 것**처럼 보인다. 이 제품의 표식은 뒤가 비쳐야 한다.
    private var circular: some View {
        MarkView()
            .padding(3)
            .accessibilityLabel("찍어서 담기")
    }

    /// 사각형 — 표식과 다음 일정 한 줄.
    ///
    /// 여기까지만 일정을 보여준다. 원형에 글자를 넣으면 두 글자밖에 안 들어가
    /// 무엇인지 알 수 없고, 인라인은 시스템이 한 줄로 압축한다.
    private var rectangular: some View {
        HStack(spacing: 8) {
            MarkView()
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
