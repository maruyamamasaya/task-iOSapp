import Foundation
import WidgetKit

protocol WidgetRefreshService: Sendable { func reloadTodayWidgets() }

struct LiveWidgetRefreshService: WidgetRefreshService {
    func reloadTodayWidgets() { WidgetCenter.shared.reloadTimelines(ofKind: "CalendarTaskTodayWidget") }
}

struct NoopWidgetRefreshService: WidgetRefreshService { func reloadTodayWidgets() {} }
