import Foundation

/// 한 달 달력 격자. 뷰가 날짜 계산을 하지 않도록 여기서 전부 끝낸다.
///
/// `weeks` 는 항상 7칸짜리 줄이고, 그 달에 속하지 않는 칸은 `nil` 이다.
/// 뷰에서 `if index < leading` 같은 산수를 하면 주 시작 요일이 바뀌는 순간 조용히 어긋난다.
struct MonthGrid: Equatable, Sendable {
    let firstOfMonth: Date
    let weeks: [[Date?]]

    var days: [Date] { weeks.flatMap { $0 }.compactMap { $0 } }
}

enum MonthGridBuilder {

    /// `reference` 가 속한 달의 격자.
    ///
    /// 주 시작 요일은 `calendar.firstWeekday` 를 그대로 따른다. 한국어 로캘은 일요일이다.
    static func grid(containing reference: Date, calendar: Calendar = .current) -> MonthGrid {
        let components = calendar.dateComponents([.year, .month], from: reference)
        guard let firstOfMonth = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return MonthGrid(firstOfMonth: calendar.startOfDay(for: reference), weeks: [])
        }

        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        // firstWeekday 가 1(일)이 아닌 로캘에서도 앞 빈칸이 맞도록 7로 정규화한다.
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        var weeks: [[Date?]] = []
        for start in stride(from: 0, to: cells.count, by: 7) {
            weeks.append(Array(cells[start..<start + 7]))
        }
        return MonthGrid(firstOfMonth: firstOfMonth, weeks: weeks)
    }

    /// 달을 앞뒤로 옮긴다. 12월에서 +1 하면 다음 해 1월이 되도록 Calendar 에 맡긴다.
    static func month(offsetting reference: Date, by months: Int, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: reference)
        let firstOfMonth = calendar.date(from: components) ?? reference
        return calendar.date(byAdding: .month, value: months, to: firstOfMonth) ?? firstOfMonth
    }

    /// 날짜별 할 일 묶음. 캘린더 격자에 점을 찍고 날짜를 눌렀을 때 쓸 목록을 함께 만든다.
    ///
    /// 완료한 할 일도 남긴다 — 달력에서 "그날 뭘 했더라"를 보는 쪽이 더 자주 필요하다.
    static func tasksByDay(
        _ tasks: [AssistantTask],
        calendar: Calendar = .current
    ) -> [Date: [AssistantTask]] {
        var result: [Date: [AssistantTask]] = [:]
        for task in tasks {
            guard let dueDate = task.dueDate else { continue }
            result[calendar.startOfDay(for: dueDate), default: []].append(task)
        }
        return result.mapValues { members in
            members.sorted { lhs, rhs in
                switch (lhs.hasExplicitTime, rhs.hasExplicitTime) {
                // 종일 할 일이 위, 시간이 있는 것은 이른 시각부터.
                case (false, true): return true
                case (true, false): return false
                default: return (lhs.dueDate ?? .distantPast) < (rhs.dueDate ?? .distantPast)
                }
            }
        }
    }
}
