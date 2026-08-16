import Foundation
import Combine

@MainActor final class CalendarStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var errorMessage: String?
    private let repository: any CalendarRepository
    private let notificationService: any NotificationService
    private let widgetRefreshService: any WidgetRefreshService
    init(repository: any CalendarRepository, notificationService: any NotificationService = NoopNotificationService(), widgetRefreshService: any WidgetRefreshService = NoopWidgetRefreshService()) {
        self.repository = repository; self.notificationService = notificationService; self.widgetRefreshService = widgetRefreshService
    }
    func load() async {
        do { events = try await repository.fetchEvents(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func add(_ event: CalendarEvent) async -> Bool {
        do { try await repository.addEvent(event); await notificationService.sync(event: event); widgetRefreshService.reloadTodayWidgets(); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func update(_ event: CalendarEvent) async -> Bool {
        do { try await repository.updateEvent(event); await notificationService.sync(event: event); widgetRefreshService.reloadTodayWidgets(); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func delete(id: UUID) async {
        do { try await repository.deleteEvent(id: id); await notificationService.removeEventNotification(id: id); widgetRefreshService.reloadTodayWidgets(); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    func reschedule(_ event: CalendarEvent, to day: Date, calendar: Calendar = .current) async {
        guard event.recurrenceRule == nil else { return }
        var value = event
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let newStart = calendar.replacingDate(of: event.startDate, with: day)
        let delta = newStart.timeIntervalSince(event.startDate)
        value.startDate = newStart; value.endDate = newStart.addingTimeInterval(duration)
        if let reminder = event.reminderDate { value.reminderDate = reminder.addingTimeInterval(delta) }
        value.updatedAt = .now
        await update(value)
    }
    func duplicate(_ event: CalendarEvent) async {
        let now = Date.now
        let copy = CalendarEvent(id: UUID(), title: event.title, note: event.note, startDate: event.startDate,
                                 endDate: event.endDate, isAllDay: event.isAllDay, reminderDate: nil,
                                 recurrenceRule: event.recurrenceRule, projectID: event.projectID, category: event.category,
                                 externalEventID: nil, createdAt: now, updatedAt: now)
        _ = await add(copy)
    }
}
