import SwiftUI

/// 이번 달을 한눈에 보는 읽기 전용 격자.
///
/// **여기서는 고치지 않는다.** 할 일의 원장은 홈의 마감 스택 하나뿐이고, 캘린더는
/// 그것을 다른 각도에서 볼 뿐이다. 두 곳에서 고칠 수 있게 만들면 "어느 쪽이 진짜인가" 를
/// 사용자도 코드도 답하지 못하게 된다.
struct MonthCalendarView: View {
    @ObservedObject var store: TaskStore

    @State private var visibleMonth: Date = .now
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        let grid = MonthGridBuilder.grid(containing: visibleMonth, calendar: calendar)
        let byDay = store.tasksByDay()

        ScrollView {
            VStack(spacing: 20) {
                monthHeader
                weekdayHeader
                monthGrid(grid, byDay: byDay)
                Divider().padding(.horizontal, 18)
                dayDetail(byDay: byDay)
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("캘린더")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("오늘") {
                    withAnimation(.snappy) {
                        visibleMonth = .now
                        selectedDay = calendar.startOfDay(for: .now)
                    }
                }
                .disabled(isShowingCurrentMonthAndToday)
            }
        }
        .onAppear {
            if selectedDay == nil { selectedDay = calendar.startOfDay(for: .now) }
        }
    }

    // MARK: - 머리글

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.snappy) { shiftMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .accessibilityLabel("이전 달")

            Spacer()
            Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
            Spacer()

            Button {
                withAnimation(.snappy) { shiftMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .accessibilityLabel("다음 달")
        }
        .padding(.horizontal, 22)
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
        .padding(.horizontal, 14)
        .accessibilityHidden(true)
    }

    // MARK: - 격자

    private func monthGrid(_ grid: MonthGrid, byDay: [Date: [AssistantTask]]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(
                                day: day,
                                dayNumber: calendar.component(.day, from: day),
                                isToday: calendar.isDateInToday(day),
                                isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) }
                                    ?? false,
                                tasks: byDay[calendar.startOfDay(for: day)] ?? []
                            )
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.2)) {
                                    selectedDay = calendar.startOfDay(for: day)
                                }
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 46)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - 고른 날

    @ViewBuilder
    private func dayDetail(byDay: [Date: [AssistantTask]]) -> some View {
        let day = selectedDay ?? calendar.startOfDay(for: .now)
        let dayTasks = byDay[day] ?? []

        VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(.dateTime.month(.abbreviated).day().weekday(.wide)))
                .font(.headline)

            if dayTasks.isEmpty {
                Text("이 날 마감인 할 일이 없어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayTasks) { task in
                    DayTaskRow(task: task)
                }
            }

            Text("여기서는 보기만 해요. 고치려면 '할 일' 탭에서 카드를 눌러 주세요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    // MARK: - 도움

    private var isShowingCurrentMonthAndToday: Bool {
        calendar.isDate(visibleMonth, equalTo: .now, toGranularity: .month)
            && (selectedDay.map { calendar.isDateInToday($0) } ?? false)
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
    /// 32pt 원을 넘치고 "2…" 로 잘린다. 격자에는 숫자만 필요하다.
    /// 요일·월 같은 맥락은 아래 접근성 레이블이 말한다.
    let dayNumber: Int
    let isToday: Bool
    let isSelected: Bool
    let tasks: [AssistantTask]

    private var pendingCount: Int { tasks.filter { !$0.isCompleted }.count }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber, format: .number.grouping(.never))
                .font(.callout.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(
                        isSelected ? Color.accentColor
                            : (isToday ? Color.accentColor.opacity(0.16) : .clear)
                    )
                )

            // 점만 쓰면 색맹 사용자에게 아무 정보가 아니다. 개수를 접근성 레이블에 넣는다.
            HStack(spacing: 3) {
                ForEach(0..<min(pendingCount, 3), id: \.self) { _ in
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var foreground: Color {
        if isSelected { return .white }
        return isToday ? .accentColor : .primary
    }

    private var accessibilityLabel: String {
        let base = day.formatted(.dateTime.month(.abbreviated).day())
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
                .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
            Text(task.title)
                .font(.subheadline)
                .strikethrough(task.isCompleted)
            Spacer(minLength: 8)
            Text(task.hasExplicitTime
                ? (task.dueDate?.formatted(date: .omitted, time: .shortened) ?? "")
                : "종일")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
    }
}
