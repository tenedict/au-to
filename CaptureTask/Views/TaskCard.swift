import SwiftUI

/// 지갑 스택의 카드 한 장.
///
/// 접혔을 때 보이는 위쪽 영역만으로도 "무엇을 언제까지" 가 읽혀야 한다.
/// 아래쪽은 다음 카드가 덮기 때문이다.
struct TaskCard: View {
    let task: AssistantTask
    let bucket: DueBucket
    let isExpanded: Bool
    let onTap: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                detail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .leading) {
                    // 묶음을 색으로만 구분하지 않는다. 머리글의 기호·글자가 같은 말을 한다.
                    Rectangle()
                        .fill(bucket.tint)
                        .frame(width: 4)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 20,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0,
                                style: .continuous
                            )
                        )
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(isExpanded ? 0.16 : 0.10), radius: isExpanded ? 14 : 7, y: 4)
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
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "완료 취소" : "완료로 표시")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                    .lineLimit(isExpanded ? 3 : 1)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    Label(dueText, systemImage: dueSymbol)
                        .font(.caption)
                        .foregroundStyle(bucket == .overdue ? Color.red : .secondary)
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
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 펼쳤을 때만

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
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
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    // MARK: - 문구

    private var dueSymbol: String {
        task.dueDate == nil ? "questionmark.circle" : "calendar"
    }

    private var dueText: String {
        guard let dueDate = task.dueDate else { return "날짜 확인 필요" }
        return dueDate.formatted(
            date: .abbreviated,
            time: task.hasExplicitTime ? .shortened : .omitted
        )
    }

    private var accessibilityLabel: String {
        var parts = [task.title, dueText, bucket.title]
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
