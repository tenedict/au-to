import SwiftUI

/// 바로 넣은 뒤 뜨는 알림줄.
///
/// **이 배너가 확인 화면을 대신한다.** 확인 화면은 저장 전에 사람을 세우고,
/// 이 배너는 저장 후에 결정권을 남긴다. 둘 다 사람이 최종 판단을 하고,
/// 다른 것은 속도뿐이다 — 그래서 **실행 취소가 반드시 있어야 한다.**
/// 없으면 그냥 조용한 자동 저장이 된다.
struct FiledBanner: View {
    let filed: FiledCapture
    let onUndo: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    /// 배너가 저절로 사라지기까지. 실행 취소를 누를 시간은 충분히 준다.
    static let lifetime: Duration = .seconds(8)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remaining: Double = 1

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: filed.wentToCalendar ? "calendar.badge.checkmark" : "checklist")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(filed.wentToCalendar ? "캘린더에 넣었어요" : "할 일에 저장했어요")
                    .font(.subheadline.weight(.semibold))
                Text(filed.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !filed.wentToCalendar {
                    // 캘린더가 실패했으면 그렇게 말한다. "저장했어요" 만 보이면
                    // 사용자는 캘린더에도 들어간 줄 안다.
                    Text("캘린더에는 넣지 못했어요.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Button("실행 취소", action: onUndo)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("고치기", action: onEdit)
                    .buttonStyle(.link)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
        )
        .overlay(alignment: .bottom) {
            // 남은 시간을 눈으로 보여준다. 갑자기 사라지면 "방금 뭐였지" 가 된다.
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: geometry.size.width * remaining, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: Self.lifetime.seconds)) { remaining = 0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(filed.wentToCalendar ? "캘린더에 넣었어요" : "할 일에 저장했어요"), \(filed.summary)"
        )
    }
}

extension Duration {
    var seconds: Double {
        let (whole, attoseconds) = components
        return Double(whole) + Double(attoseconds) / 1e18
    }
}
