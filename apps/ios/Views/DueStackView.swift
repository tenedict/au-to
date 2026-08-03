import SwiftUI

/// 마감이 가까운 것부터 지갑처럼 쌓아 보여주는 홈.
///
/// 하나를 누르면 펼쳐지고, 다른 것을 누르면 앞의 것이 접힌다. 펼침은 화면 전체에서
/// 하나뿐이다 — 여러 개가 동시에 펼쳐지면 "지금 뭘 보고 있는지" 가 사라진다.
struct DueStackView: View {
    @ObservedObject var store: TaskStore
    /// 펼친 카드. 알림을 눌러 들어온 경우 바깥에서 정해 주므로 바인딩이다.
    @Binding var expandedTaskID: UUID?
    /// 요약 타일의 "확인할 것" 을 눌렀을 때.
    let onOpenReview: () -> Void
    /// 카드에서 "고치기" 를 눌렀을 때. 편집기는 바깥이 띄운다 —
    /// 스택 안에서 시트를 열면 카드가 사라질 때 시트도 함께 사라진다.
    let onEditTask: (AssistantTask) -> Void
    /// 스크린샷 없이 직접 적기.
    let onAddTask: () -> Void
    let onAddText: () -> Void
    let onPickPhotos: () -> Void
    let onOpenSettings: () -> Void

    @State private var collapsedBuckets: Set<DueBucket> = Set(
        DueBucket.allCases.filter(\.startsCollapsed)
    )
    /// 확인할 것만 보고 있는가. 요약 타일의 숫자를 누르면 켜진다.
    @State private var showsOnlyReview = false

    /// Dynamic Type 배율. 값 1 을 주면 현재 글자 크기에 맞는 배율이 들어온다.
    /// 카드 높이가 고정값이면 글자를 키운 사용자에게 제목과 마감이 잘린다.
    @ScaledMetric(relativeTo: .headline) private var typeScale: CGFloat = 1
    /// 모션 줄이기를 켠 사용자에게는 카드가 튀지 않는다.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 접근성 글자 크기에서는 **겹침을 포기한다.**
    ///
    /// 지갑 겹침은 접힌 카드의 윗부분만 보이는 것을 전제로 한다. 접근성 크기에서는
    /// 제목 한 줄과 마감 한 줄만으로도 그 공간을 넘겨서, 배율을 아무리 키워도
    /// 다음 카드가 마감 날짜를 덮는다. 실제로 배율만 적용했을 때
    /// "2026년 7월 30일"이 두 줄로 넘쳐 아래가 잘렸다.
    ///
    /// 그래서 이 크기에서는 겹치지 않는 평범한 목록으로 바꾸고 높이를 내용에 맡긴다.
    /// 멋보다 읽히는 것이 먼저다.
    private var usesWalletStack: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var layout: WalletStackLayout {
        WalletStackLayout.default.scaled(by: typeScale)
    }

    /// 펼침 애니메이션. 모션 줄이기에서는 즉시 바뀐다.
    private var expandAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)
    }

    private var collapseAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                // 목록에 들어가기 전에 "지금 어떤가" 를 먼저 말한다.
                // 생김새는 core/swift/Design 의 하나를 쓴다 — 맥 사이드바와 같은 물건이다.
                SummaryTile(summary: summary) {
                    withAnimation(collapseAnimation) { showsOnlyReview.toggle() }
                    onOpenReview()
                }

                notices

                if showsOnlyReview {
                    reviewOnly
                } else {
                    let groups = store.dueGroups()
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            section(for: group)
                        }
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
                Menu {
                    // **직접 적기가 맨 위다.** 스크린샷이 없을 때 쓰는 길이고,
                    // 이게 없어서 "할 일을 내가 못 넣는다" 는 말을 들었다.
                    Button(action: onAddTask) {
                        Label("직접 적기", systemImage: "square.and.pencil")
                    }
                    Divider()
                    Button {
                        onPickPhotos()
                    } label: {
                        Label("사진에서 고르기", systemImage: "photo.on.rectangle")
                    }
                    Button(action: onAddText) {
                        Label("텍스트 붙여넣기", systemImage: "text.viewfinder")
                    }
                    Divider()
                    Button(action: onOpenSettings) {
                        Label("설정", systemImage: "gearshape")
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    private var summary: TaskScoping.Summary {
        TaskScoping.summary(for: store.tasks, now: .now)
    }

    // MARK: - 확인할 것만 보기

    /// 요약 타일의 "확인할 것" 을 눌렀을 때 나오는 목록.
    ///
    /// 새 화면으로 밀어 넣지 않고 **같은 자리에서 걸러 보여준다** — 확인은 몇 초짜리
    /// 일이라, 화면을 옮겼다 돌아오는 비용이 그 일보다 크다.
    @ViewBuilder
    private var reviewOnly: some View {
        let tasks = TaskScoping.needingReview(store.tasks, now: .now)
        HStack(spacing: Space.gap2) {
            Text("확인할 일정")
                .font(.headline)
            Spacer()
            Button("전체 보기") {
                withAnimation(collapseAnimation) { showsOnlyReview = false }
            }
            .font(.subheadline)
        }
        if tasks.isEmpty {
            Text("확인할 게 없어요. 전부 확인했어요.")
                .font(.callout)
                .foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 10) {
                ForEach(tasks) { task in
                    // 묶음은 여기서 지어내지 않고 물어본다. 지어내면 카드의 기호와
                    // 접근성 문구가 목록의 다른 자리와 달라진다.
                    card(
                        task,
                        bucket: DueGrouping.bucket(for: task, now: .now),
                        isExpanded: task.id == expandedTaskID,
                        isStacked: false)
                }
            }
            .animation(expandAnimation, value: expandedTaskID)
        }
    }

    // MARK: - 알림줄

    @ViewBuilder
    private var notices: some View {
        // 왜 안 되는지 함께 보여준다. 이유 없는 침묵은 고장으로 읽힌다.
        if let explanation = store.inboxAvailability.explanation {
            NoticeRow(
                symbol: "exclamationmark.triangle.fill",
                title: "공유 시트로 담기를 쓸 수 없어요",
                detail: explanation,
                tint: Palette.past,
                showsChevron: false
            )
        }

        if let explanation = store.reminderAuthorization.explanation,
           store.reminderAuthorization == .denied {
            NoticeRow(
                symbol: "bell.slash.fill",
                title: "마감 알림이 꺼져 있어요",
                detail: explanation,
                tint: Palette.past,
                showsChevron: false
            )
        }

        // 첫 저장까지 기다리면 **첫 공유의 확인 알림을 놓친다** — 권한이 없으면
        // Share Extension 이 건 알림이 조용히 사라진다. 그래서 여기서 먼저 권한을 권한다.
        if store.reminderAuthorization == .notDetermined {
            Button {
                Task { await store.enableReminders() }
            } label: {
                NoticeRow(
                    symbol: "bell.badge",
                    title: "알림을 켤까요?",
                    detail: "마감 전에 알려 드리고, 스크린샷을 담으면 확인을 요청해요.",
                    tint: Palette.water,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("아직 할 일이 없어요", systemImage: "checklist")
        } description: {
            Text(
                "직접 적어도 되고, 다른 앱에서 스크린샷을 공유하거나 사진에서 골라도 돼요. "
                    + "공유한 것은 읽어서 바로 등록해 드려요."
            )
        } actions: {
            VStack(spacing: 10) {
                Button("직접 적기", action: onAddTask)
                    .buttonStyle(.borderedProminent)
                Button("사진에서 고르기", action: onPickPhotos)
                    .buttonStyle(.bordered)
                Button("텍스트 붙여넣기", action: onAddText)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 묶음

    private func section(for group: DueGroup) -> some View {
        let isCollapsed = collapsedBuckets.contains(group.bucket)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(collapseAnimation) {
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

    @ViewBuilder
    private func stack(for group: DueGroup) -> some View {
        if usesWalletStack {
            walletStack(for: group)
        } else {
            plainList(for: group)
        }
    }

    private func walletStack(for group: DueGroup) -> some View {
        let expandedIndex = group.tasks.firstIndex { $0.id == expandedTaskID }
        return ZStack(alignment: .top) {
            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                card(
                    task, bucket: group.bucket, isExpanded: index == expandedIndex,
                    isStacked: usesWalletStack)
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
        .animation(expandAnimation, value: expandedTaskID)
    }

    /// 접근성 글자 크기용. 겹치지 않고 높이를 내용에 맡긴다.
    private func plainList(for group: DueGroup) -> some View {
        VStack(spacing: 10) {
            ForEach(group.tasks) { task in
                card(
                    task, bucket: group.bucket, isExpanded: task.id == expandedTaskID,
                    isStacked: usesWalletStack)
            }
        }
        .animation(expandAnimation, value: expandedTaskID)
    }

    private func card(
        _ task: AssistantTask,
        bucket: DueBucket,
        isExpanded: Bool,
        isStacked: Bool
    ) -> TaskCard {
        TaskCard(
            task: task,
            bucket: bucket,
            isExpanded: isExpanded,
            isStacked: isStacked,
            onTap: { toggleExpansion(of: task.id) },
            onToggleCompletion: { Task { await store.toggleCompletion(for: task.id) } },
            onEdit: { onEditTask(task) },
            onDelete: { Task { await store.delete(task.id) } }
        )
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
                .monospacedDigit()
                .foregroundStyle(Palette.ink3)
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
    /// 묶음의 기호 색.
    ///
    /// **묶음마다 색을 주지 않는다.** 여섯 색이 각각 "급함" 의 정도를 뜻하려 했지만,
    /// **순서가 이미 그 정보를 담고 있다** — 위에 있을수록 급하다는 것이 이 화면의
    /// 유일한 규칙이다 (결정 D-9). 색은 그 규칙을 되풀이할 뿐 새 정보를 주지 않았다.
    ///
    /// 대신 기호는 남긴다. 기호는 목록을 훑을 때 위치와 무관하게 묶음을 식별하게
    /// 해 준다 (디자인 언어 §4.4).
    var tint: Color {
        self == .overdue ? Palette.past : Palette.ink3
    }
}
