import SwiftUI

/// 마감이 가까운 것부터 지갑처럼 쌓아 보여주는 홈.
///
/// 하나를 누르면 펼쳐지고, 다른 것을 누르면 앞의 것이 접힌다. 펼침은 화면 전체에서
/// 하나뿐이다 — 여러 개가 동시에 펼쳐지면 "지금 뭘 보고 있는지" 가 사라진다.
struct DueStackView: View {
    @ObservedObject var store: TaskStore
    let onReviewDrafts: () -> Void
    let onAddText: () -> Void

    @State private var expandedTaskID: UUID?
    @State private var collapsedBuckets: Set<DueBucket> = Set(
        DueBucket.allCases.filter(\.startsCollapsed)
    )

    private let layout = WalletStackLayout.default

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                notices

                let groups = store.dueGroups()
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { group in
                        section(for: group)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 할 일")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if store.isImporting {
                    ProgressView().accessibilityLabel("공유한 스크린샷을 분석하는 중")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAddText) {
                    Label("텍스트로 추가", systemImage: "plus")
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    // MARK: - 알림줄

    @ViewBuilder
    private var notices: some View {
        if !store.pendingDrafts.isEmpty {
            Button(action: onReviewDrafts) {
                NoticeRow(
                    symbol: "tray.full.fill",
                    title: "확인할 할 일 \(store.pendingDrafts.count)개",
                    detail: "저장하기 전에 제목과 날짜를 확인해 주세요.",
                    tint: .accentColor,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        // 왜 안 되는지 함께 보여준다. 이유 없는 침묵은 고장으로 읽힌다.
        if let explanation = store.inboxAvailability.explanation {
            NoticeRow(
                symbol: "exclamationmark.triangle.fill",
                title: "공유 시트로 담기를 쓸 수 없어요",
                detail: explanation,
                tint: .orange,
                showsChevron: false
            )
        }

        if let explanation = store.reminderAuthorization.explanation,
           store.reminderAuthorization == .denied {
            NoticeRow(
                symbol: "bell.slash.fill",
                title: "마감 알림이 꺼져 있어요",
                detail: explanation,
                tint: .orange,
                showsChevron: false
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("아직 할 일이 없어요", systemImage: "checklist")
        } description: {
            Text("스크린샷을 공유하거나 텍스트를 붙여 넣으면 할 일 후보를 만들어요.")
        } actions: {
            Button("텍스트로 시험하기", action: onAddText)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 묶음

    private func section(for group: DueGroup) -> some View {
        let isCollapsed = collapsedBuckets.contains(group.bucket)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    if isCollapsed {
                        collapsedBuckets.remove(group.bucket)
                    } else {
                        collapsedBuckets.insert(group.bucket)
                        if group.tasks.contains(where: { $0.id == expandedTaskID }) {
                            expandedTaskID = nil
                        }
                    }
                }
            } label: {
                SectionHeader(group: group, isCollapsed: isCollapsed)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                stack(for: group)
            }
        }
    }

    private func stack(for group: DueGroup) -> some View {
        let expandedIndex = group.tasks.firstIndex { $0.id == expandedTaskID }
        return ZStack(alignment: .top) {
            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                TaskCard(
                    task: task,
                    bucket: group.bucket,
                    isExpanded: index == expandedIndex,
                    onTap: { toggleExpansion(of: task.id) },
                    onToggleCompletion: { Task { await store.toggleCompletion(for: task.id) } },
                    onDelete: { Task { await store.delete(task.id) } }
                )
                .frame(height: layout.height(forCardAt: index, expandedIndex: expandedIndex))
                .offset(y: layout.offset(forCardAt: index, expandedIndex: expandedIndex))
                // 아래 카드가 위 카드를 덮어야 지갑처럼 보인다.
                .zIndex(Double(index))
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: layout.totalHeight(cardCount: group.count, expandedIndex: expandedIndex),
            alignment: .top
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: expandedTaskID)
    }

    private func toggleExpansion(of taskID: UUID) {
        expandedTaskID = expandedTaskID == taskID ? nil : taskID
    }
}

private struct SectionHeader: View {
    let group: DueGroup
    let isCollapsed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.bucket.symbolName)
                .font(.subheadline)
                .foregroundStyle(group.bucket.tint)
            Text(group.bucket.title)
                .font(.headline)
            Text("\(group.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.bucket.title), \(group.count)개")
        .accessibilityHint(isCollapsed ? "탭하면 펼쳐요" : "탭하면 접어요")
    }
}

private struct NoticeRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

extension DueBucket {
    /// 색은 거들 뿐이다. 같은 정보를 기호와 글자가 항상 함께 말한다 (AGENTS 규칙 10).
    var tint: Color {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .within7Days: return .accentColor
        case .later: return .teal
        case .someday: return .gray
        case .done: return .green
        }
    }
}
