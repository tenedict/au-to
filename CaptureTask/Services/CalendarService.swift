import EventKit
import Foundation

@MainActor
final class CalendarService {
    private let eventStore = EKEventStore()

    func addToCalendar(_ task: AssistantTask) async throws -> String {
        guard let dueDate = task.dueDate else {
            throw CalendarServiceError.missingDate
        }

        let granted = try await requestAccessIfNeeded()
        guard granted else {
            throw CalendarServiceError.accessDenied
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.title = task.title
        event.notes = task.notes
        event.startDate = dueDate
        event.isAllDay = !task.hasExplicitTime
        event.endDate = task.hasExplicitTime
            ? dueDate.addingTimeInterval(60 * 60)
            : Calendar.current.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate

        try eventStore.save(event, span: .thisEvent)
        guard let identifier = event.eventIdentifier else {
            throw CalendarServiceError.missingIdentifier
        }
        return identifier
    }

    private func requestAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return try await eventStore.requestWriteOnlyAccessToEvents()
        @unknown default:
            return false
        }
    }
}

enum CalendarServiceError: LocalizedError {
    case missingDate
    case accessDenied
    case missingIdentifier

    var errorDescription: String? {
        switch self {
        case .missingDate:
            return "날짜가 없어 캘린더에 추가할 수 없어요."
        case .accessDenied:
            return "캘린더 접근이 꺼져 있어요. 설정에서 접근을 허용해 주세요."
        case .missingIdentifier:
            return "캘린더 저장 결과를 확인하지 못했어요."
        }
    }
}

