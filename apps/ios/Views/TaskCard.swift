import SwiftUI

/// 지갑 스택의 카드 한 장.
///
/// 접혔을 때 보이는 위쪽 영역만으로도 "무엇을 언제까지" 가 읽혀야 한다.
/// 아래쪽은 다음 카드가 덮기 때문이다.
struct TaskCard: View {
    let task: AssistantTask
    let bucket: DueBucket
    let isExpanded: Bool
    /// 지갑처럼 겹쳐 쌓인 상태인가.
    ///
    /// 겹쳐 있으면 아래 카드가 윗부분만 남기고 덮으므로 제목을 한 줄로 자른다.
    /// 접근성 글자 크기에서는 겹치지 않으므로(`DueStackView.usesWalletStack`)
    /// 줄 수를 풀어 준다 — 그 크기의 사용자에게 잘린 제목은 아무 정보가 아니다.
    let isStacked: Bool
    let onTap: () -> Void
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// 대비 높이기를 켠 사용자에게는 카드 경계를 그림자 대신 선으로 준다.
    /// 그림자는 대비가 낮아 겹친 카드가 하나의 긴 카드로 보인다.
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wantsHighContrast: Bool { contrast == .increased }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                detail
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 카드 가장자리의 색 띠는 없앴다.
        //
        // 묶음마다 색을 주지 않기로 한 뒤(CLAUDE 규칙 16) 이 띠는 대부분의 카드에서
        // 무채색이 되었고, 남은 것은 **모서리에 붙은 얇은 회색 선** 하나였다.
        // 아무 정보도 주지 않으면서 카드가 잘린 것처럼 보이게 만들었다.
        // 급함은 순서가, 묶음은 머리글의 기호와 글자가 이미 말하고 있다.
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            if wantsHighContrast {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isExpanded ? 0.55 : 0.35), lineWidth: 1)
            }
        }
        // 겹침을 읽히게 하는 단서는 그림자뿐이다. 대비를 높인 사용자에게는
        // 그림자가 거의 안 보이므로 위의 선이 그 역할을 대신한다.
        .shadow(
            color: .black.opacity(wantsHighContrast ? 0 : (isExpanded ? 0.16 : 0.10)),
            radius: isExpanded ? 14 : 7,
            y: 4
        )
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isExpanded ? "탭하면 접어요" : "탭하면 자세히 봐요")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 접혀도 보이는 부분

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? Palette.water : Palette.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "완료 취소" : "완료로 표시")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                    .lineLimit(titleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                // 겹치지 않을 때는 마감·배지를 세로로 흘려 잘리지 않게 한다.
                metadata
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var titleLineLimit: Int? {
        guard isStacked else { return nil }
        return isExpanded ? 3 : 1
    }

    /// 마감과 배지.
    ///
    /// 겹쳐 있을 때는 한 줄에 나란히 둔다. 겹치지 않을 때(접근성 글자 크기)는
    /// 세로로 흘린다 — 가로로 두면 "2026년 7월 30일"이 잘리거나 배지가 화면 밖으로 나간다.
    @ViewBuilder
    private var metadata: some View {
        if isStacked {
            HStack(spacing: 8) { metadataItems }
                .labelStyle(.titleAndIcon)
        } else {
            VStack(alignment: .leading, spacing: 5) { metadataItems }
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        Label(dueText, systemImage: dueSymbol)
            .font(.caption)
            .foregroundStyle(bucket == .overdue ? Palette.past : Palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
        // **등록은 이미 됐다.** 이 배지는 "안 됐다" 가 아니라 "한 번 봐 달라" 다.
        // 그래서 경고색(past)이 아니라 조작 가능한 것의 색(water)을 쓴다.
        if task.needsReview {
            Label("확인 필요", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(Palette.water)
        }
        if task.calendarEventIdentifier != nil {
            Label("캘린더", systemImage: "calendar.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if task.dueDate != nil, !task.wantsReminders {
            Label("알림 꺼짐", systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 펼쳤을 때만

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            if let reason = task.reviewReason {
                Label(reason, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.water)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("메모가 없어요")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text(task.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if task.origin == .screenshot {
                    Tag(text: "스크린샷에서", symbol: "photo")
                }
                if task.confidence < 1 {
                    Tag(text: "신뢰도 \(Int((task.confidence * 100).rounded()))%", symbol: "gauge")
                }
                Spacer(minLength: 0)
                // 고치기가 삭제보다 먼저다. 훨씬 자주 쓰는 쪽이 손에 가까워야 하고,
                // 되돌릴 수 없는 것을 마지막에 두면 잘못 누를 일이 줄어든다.
                Button(action: onEdit) {
                    Label("고치기", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.water)
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.past)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    // MARK: - 문구

    private var dueSymbol: String {
        task.dueDate == nil ? "questionmark.circle" : "calendar"
    }

    /// 접힌 카드의 마감. **좁음 등급이고 한 줄이다** (디자인 언어 §10.4 계약 C-1·C-2).
    ///
    /// 이 자리에 완전 서술형을 쓰면 두 줄이 되어 다음 카드에 가려진다.
    private var dueText: String {
        DueDateText.string(
            for: task.dueDate,
            hasExplicitTime: task.hasExplicitTime,
            width: .narrow,
            now: .now
        )
    }

    private var accessibilityLabel: String {
        var parts = [task.title, dueText, bucket.title]
        if task.needsReview { parts.append("확인 필요") }
        if task.isCompleted { parts.append("완료함") }
        return parts.joined(separator: ", ")
    }
}

private struct Tag: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}
