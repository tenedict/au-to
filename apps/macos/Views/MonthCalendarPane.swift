import SwiftUI

/// 한 달을 한눈에 보는 격자와, 고른 날의 일정.
///
/// **캘린더는 여전히 원장이 아니다.** 할 일의 원장은 앱 하나뿐이고 여기는 그것을
/// 날짜라는 각도에서 볼 뿐이다. 다만 "보기만 하는 화면" 과 "고칠 수 없는 화면" 은
/// 다른 말이다 — 날짜를 눌러 일정을 찾은 사용자가 거기서 고칠 수 없으면,
/// 왼쪽 목록에서 같은 것을 **다시 찾아야** 한다.
///
/// 그래서 여기서도 고칠 수 있게 하되, 고치는 문은 목록과 **같은 하나**를 쓴다
/// (`TaskEditorSheet`). 원장이 둘이 되는 것은 화면이 둘일 때가 아니라
/// 저장 경로가 둘일 때다.
///
/// 날짜 계산은 하나도 하지 않는다. 격자는 `MonthGridBuilder`, 날짜별 묶기는
/// `store.tasksByDay()` 가 만든다 — iOS 캘린더와 같은 함수다.
struct MonthCalendarPane: View {
    @ObservedObject var store: TaskStore
    /// 일정을 눌렀을 때 열 것. 목록 화면과 같은 편집기로 간다.
    let onOpen: (AssistantTask) -> Void

    @State private var visibleMonth: Date = .now
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current

    var body: some View {
        let grid = MonthGridBuilder.grid(containing: visibleMonth, calendar: calendar)
        let byDay = store.tasksByDay()

        // 격자와 그날의 일정을 한 스크롤에 둔다. 둘을 따로 스크롤시키면 창을
        // 줄였을 때 아래쪽이 조용히 잘리고, 잘린 줄에 "여기서는 고치지 않아요"
        // 같은 안내가 들어 있으면 그 안내가 없는 것과 같아진다.
        ScrollView {
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                monthGrid(grid, byDay: byDay)
                Divider()
                dayAgenda(byDay: byDay)
            }
        }
        .frame(minWidth: 420)
    }

    // MARK: - 머리글

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Text(DueDateText.monthTitle(for: visibleMonth, calendar: calendar))
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())

            Spacer()

            Button("오늘") {
                withAnimation(.snappy(duration: 0.2)) {
                    visibleMonth = .now
                    selectedDay = calendar.startOfDay(for: .now)
                }
            }
            .disabled(isShowingToday)
            // 비활성 컨트롤에는 언제나 이유를 함께 보여준다 (규칙 12).
            .help(isShowingToday ? "이미 오늘을 보고 있어요" : "오늘로 돌아가요")

            Button {
                withAnimation(.snappy(duration: 0.2)) { shiftMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("이전 달")

            Button {
                withAnimation(.snappy(duration: 0.2)) { shiftMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("다음 달")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    // MARK: - 격자

    private func monthGrid(_ grid: MonthGrid, byDay: [Date: [AssistantTask]]) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(
                                day: day,
                                dayNumber: calendar.component(.day, from: day),
                                isToday: calendar.isDateInToday(day),
                                isSelected: calendar.isDate(selectedDay, inSameDayAs: day),
                                tasks: byDay[calendar.startOfDay(for: day)] ?? []
                            )
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.15)) {
                                    selectedDay = calendar.startOfDay(for: day)
                                }
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 52)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - 고른 날

    private func dayAgenda(byDay: [Date: [AssistantTask]]) -> some View {
        let dayTasks = byDay[selectedDay] ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(
                    DueDateText.string(
                        for: selectedDay, hasExplicitTime: false, width: .medium, now: selectedDay)
                )
                .font(.headline)
                Text(dayTasks.isEmpty ? "일정 없음" : "일정 \(dayTasks.count)건")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                // 안내는 머리글 줄에 둔다. 목록 아래에 두면 일정이 많을 때 밀려
                // 내려가서, 정작 읽어야 할 사람이 못 본다.
                if !dayTasks.isEmpty {
                    Text("눌러서 고칠 수 있어요")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if dayTasks.isEmpty {
                Text("이 날 마감인 할 일이 없어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                VStack(spacing: 6) {
                    ForEach(dayTasks) { task in
                        Button { onOpen(task) } label: { DayTaskRow(task: task) }
                            .buttonStyle(.plain)
                            .accessibilityHint("눌러서 자세히 보고 고쳐요")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 도움

    private var isShowingToday: Bool {
        calendar.isDate(visibleMonth, equalTo: .now, toGranularity: .month)
            && calendar.isDateInToday(selectedDay)
    }

    private func shiftMonth(by months: Int) {
        visibleMonth = MonthGridBuilder.month(
            offsetting: visibleMonth,
            by: months,
            calendar: calendar
        )
    }

    /// `firstWeekday` 를 반영해 요일 머리글을 돌린다.
    /// `shortWeekdaySymbols` 는 언제나 일요일부터라 그대로 쓰면 로캘이 바뀔 때 어긋난다.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

private struct DayCell: View {
    let day: Date
    /// 격자에 찍는 숫자.
    ///
    /// `day.formatted(.dateTime.day())` 를 쓰면 한국어 로캘에서 "20일" 이 나와
    /// 원을 넘치고 잘린다. 격자에는 숫자만 필요하다 — 맥락은 접근성 레이블이 말한다.
    let dayNumber: Int
    let isToday: Bool
    let isSelected: Bool
    let tasks: [AssistantTask]

    private var pendingCount: Int { tasks.filter { !$0.isCompleted }.count }

    var body: some View {
        VStack(spacing: 4) {
            Text(
                DueDateText.string(
                    for: day, hasExplicitTime: false, width: .tick, now: day)
            )
            .font(.callout.weight(isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .frame(width: 30, height: 30)
            // 오늘은 테두리 원, 고른 날은 채운 원. 색을 둘로 쓰지 않는다 (§10.8).
            .background(
                Circle()
                    .fill(isSelected ? Palette.water : .clear)
                    .overlay {
                        if isToday && !isSelected {
                            Circle().strokeBorder(Palette.water, lineWidth: 1.5)
                        }
                    }
            )

            // 점만 쓰면 색맹 사용자에게 아무 정보가 아니다. 개수는 접근성 레이블에 넣는다.
            HStack(spacing: 3) {
                ForEach(0..<min(pendingCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(isSelected ? Color.white : Palette.ink3)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var foreground: Color {
        if isSelected { return .white }
        return isToday ? Palette.water : Palette.ink1
    }

    private var accessibilityLabel: String {
        let base = DueDateText.string(
            for: day, hasExplicitTime: false, width: .narrow, now: day)
        guard pendingCount > 0 else { return "\(base), 마감 없음" }
        return "\(base), 마감 \(pendingCount)개"
    }
}

private struct DayTaskRow: View {
    let task: AssistantTask

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(task.isCompleted ? Palette.water : Palette.ink3)
            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
            Spacer(minLength: 8)
            if task.calendarEventIdentifier != nil {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("캘린더에 등록됨")
            }
            Text(
                DueDateText.clock(
                    for: task.dueDate, hasExplicitTime: task.hasExplicitTime)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .combine)
    }
}
