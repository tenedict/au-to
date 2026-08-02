import SwiftUI
import WidgetKit

/// 홈 화면 위젯 — **다음 일정**.
///
/// 크기마다 다른 위젯을 만들지 않는다. 하나가 네 크기를 다 그리되,
/// **크기가 커진다고 새 정보를 더하지 않는다** — 같은 목록이 더 길어질 뿐이다.
/// 작은 위젯에만 있는 정보를 두면 사용자는 크기를 바꿀 때마다 무언가를 잃는다.
///
/// | 크기 | 무엇 |
/// | --- | --- |
/// | 소형 (2×2) | 다음 하나 · 지난 마감 배지 |
/// | 중형 (4×2) | 요약 줄 + 세 건 |
/// | 대형 (4×4) | 요약 줄 + 여섯 건 |
/// | 특대 (8×4, iPad) | 요약 줄 + 여덟 건을 두 단으로 |
struct NextTaskWidget: Widget {
    static let kind = "CaptureTaskNextTask"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            NextTaskView(entry: entry)
                .containerBackground(Palette.bed, for: .widget)
        }
        .configurationDisplayName("다음 일정")
        .description("마감이 가까운 것부터 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct NextTaskView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// 크기마다 몇 줄까지 그릴 것인가.
    ///
    /// 넘치면 잘리는 것이 아니라 **밀려서 안 보인다.** 줄 수를 화면 높이에 맡기지
    /// 않고 여기서 못 박는 이유다.
    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 8
        }
    }

    /// 특대는 두 단으로 나눈다. 한 단으로 늘이면 오른쪽 절반이 통째로 빈다.
    private var usesTwoColumns: Bool { family == .systemExtraLarge }

    var body: some View {
        if entry.snapshot.isUnavailable {
            unavailable
        } else if entry.snapshot.isEmpty {
            empty
        } else {
            content
        }
    }

    // MARK: - 본문

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            if family == .systemSmall {
                smallHeader
            } else {
                summaryLine
            }
            rows
            Spacer(minLength: 0)
        }
    }

    /// 소형은 요약 줄을 넣을 자리가 없다. 대신 표식과 배지만 한 줄로 둔다.
    private var smallHeader: some View {
        HStack(spacing: 6) {
            BeadShape()
                .fill(Palette.water)
                .frame(width: 13, height: 13)
            Text("다음 일정")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink3)
            Spacer(minLength: 0)
            if entry.snapshot.overdueCount > 0 {
                OverdueBadge(count: entry.snapshot.overdueCount)
            }
        }
    }

    /// 목록에 들어가기 전에 "지금 상태" 를 먼저 말한다 (디자인 언어 §10.6).
    private var summaryLine: some View {
        HStack(spacing: 8) {
            BeadShape()
                .fill(Palette.water)
                .frame(width: 15, height: 15)
            Text(summaryText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink1)
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.snapshot.overdueCount > 0 {
                OverdueBadge(count: entry.snapshot.overdueCount)
            }
        }
    }

    private var summaryText: String {
        if entry.snapshot.todayCount > 0 { return "오늘 \(entry.snapshot.todayCount)건" }
        return "다음 일정"
    }

    @ViewBuilder
    private var rows: some View {
        let shown = Array(entry.snapshot.upcoming.prefix(rowLimit))
        if usesTwoColumns {
            HStack(alignment: .top, spacing: 18) {
                column(Array(shown.prefix((shown.count + 1) / 2)))
                column(Array(shown.dropFirst((shown.count + 1) / 2)))
            }
        } else {
            column(shown)
        }
    }

    private func column(_ tasks: [AssistantTask]) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 8) {
            ForEach(tasks) { task in
                TaskLine(task: task, isCompact: family == .systemSmall, now: entry.date)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 비어 있을 때 · 못 읽었을 때

    /// **빈 것과 못 읽은 것을 다르게 말한다.** 같은 화면을 보여주면 설정이
    /// 잘못된 사용자가 영영 그 사실을 모른다.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            BeadShape()
                .fill(Palette.water)
                .frame(width: 18, height: 18)
            Spacer(minLength: 0)
            Text("다음 일정이 없어요")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink1)
            if family != .systemSmall {
                Text("스크린샷을 공유하면 여기에 올라와요.")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.past)
            Spacer(minLength: 0)
            Text("할 일을 읽지 못했어요")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink1)
            if family != .systemSmall {
                // 이유를 그대로 보여준다. "앱을 열어 주세요" 만 적으면
                // App Group 설정이 틀린 사용자는 영영 그 사실을 모른다.
                Text(entry.snapshot.unavailableReason ?? "앱을 한 번 열어 주세요.")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 한 줄 — 제목과 마감.
///
/// 날짜 문구는 만들지 않고 `DueDateText` 에 폭 등급만 넘긴다 (CLAUDE 규칙 15).
/// 위젯은 화면에서 가장 좁은 자리라, 여기서 완전 서술형을 쓰면 반드시 잘린다.
private struct TaskLine: View {
    let task: AssistantTask
    let isCompact: Bool
    let now: Date

    private var isOverdue: Bool {
        DueGrouping.bucket(for: task, now: now) == .overdue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(task.title)
                .font(isCompact ? .caption.weight(.semibold) : .footnote.weight(.medium))
                .foregroundStyle(Palette.ink1)
                .lineLimit(isCompact ? 2 : 1)
            HStack(spacing: 3) {
                // 색만으로 알리지 않는다 (CLAUDE 규칙 13).
                if isOverdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                }
                Text(
                    DueDateText.string(
                        for: task.dueDate,
                        hasExplicitTime: task.hasExplicitTime,
                        width: .narrow,
                        now: now)
                )
                .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(isOverdue ? Palette.past : Palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 지난 마감 개수. 숫자와 기호를 함께 쓴다.
private struct OverdueBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("\(count)").monospacedDigit()
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Palette.past)
        .accessibilityLabel("지난 마감 \(count)건")
    }
}
