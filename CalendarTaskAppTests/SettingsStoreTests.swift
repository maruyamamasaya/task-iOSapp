import XCTest
import SwiftUI
@testable import CalendarTaskApp

@MainActor final class SettingsStoreTests: XCTestCase {
    private var suiteName: String { "SettingsStoreTests.\(UUID().uuidString)" }

    func testSafeDefaultsAndInitialRoute() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.initialTab, .today)
        XCTAssertEqual(AppRootView.route(for: store.initialTab), .today)
        XCTAssertEqual(store.weekStartDay, .monday)
        XCTAssertEqual(store.initialCalendarMode, .month)
        XCTAssertEqual(store.defaultTaskPriority, .normal)
        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(store.theme, .classic)
    }

    func testSettingsPersistAndReload() {
        let name = suiteName, defaults = UserDefaults(suiteName: name)!
        var store = SettingsStore(defaults: defaults)
        store.initialTab = .tasks; store.weekStartDay = .sunday; store.appearance = .dark; store.theme = .midnight
        store.defaultTaskPriority = .high; store.defaultEventDurationMinutes = 90
        store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.initialTab, .tasks); XCTAssertEqual(AppRootView.route(for: store.initialTab), .tasks)
        XCTAssertEqual(store.weekStartDay, .sunday); XCTAssertEqual(store.appearance, .dark)
        XCTAssertEqual(store.theme, .midnight)
        XCTAssertEqual(store.defaultTaskPriority, .high); XCTAssertEqual(store.defaultEventDurationMinutes, 90)
        defaults.removePersistentDomain(forName: name)
    }

    func testTaskAndEventCreationDefaults() throws {
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        store.defaultTaskPriority = .low; store.newTasksAreAllDay = false; store.defaultReminder = .thirtyMinutes
        store.defaultEventStartHour = 10; store.defaultEventDurationMinutes = 60
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 18)))
        let task = store.taskCreationDefaults(referenceDate: reference)
        XCTAssertEqual(task.priority, .low); XCTAssertFalse(task.isAllDay)
        XCTAssertEqual(task.reminderDate, reference.addingTimeInterval(-1800))
        let event = store.eventCreationDefaults(referenceDate: reference, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: event.startDate), 10)
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 3600)
    }

    func testHapticOffDoesNotEmitFeedback() {
        var count = 0
        let service = SystemHapticService(isEnabled: { false }, completionFeedback: { count += 1 }, actionFeedback: { count += 1 }, deletionFeedback: { count += 1 })
        service.completion(); service.action(); service.deletion()
        XCTAssertEqual(count, 0)
    }

    func testThemeTextContrastInEveryAppearance() {
        for theme in AppTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.appearance(for: scheme)
                for surface in [palette.surface, palette.background] {
                    XCTAssertGreaterThanOrEqual(contrast(palette.ink, surface), 4.5, "\(theme) \(scheme) body")
                    XCTAssertGreaterThanOrEqual(contrast(palette.mutedInk, surface), 4.5, "\(theme) \(scheme) secondary")
                    XCTAssertGreaterThanOrEqual(contrast(palette.accent, surface), 4.5, "\(theme) \(scheme) action")
                }
                XCTAssertGreaterThanOrEqual(contrast(palette.accent, palette.control), 4.5, "\(theme) \(scheme) button")
                XCTAssertGreaterThanOrEqual(contrast(palette.selectionInk, palette.accent), 4.5, "\(theme) \(scheme) selection")
            }
        }
    }

    private func contrast(_ first: Color, _ second: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            let values = [r, g, b].map { value in
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testThemeAppearanceRenderings() throws {
        let name = suiteName
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_788_566_400)
        for theme in AppTheme.allCases {
            settings.theme = theme
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.appearance(for: scheme)
                let content = VStack(alignment: .leading, spacing: 20) {
                    Text(theme.rawValue + (scheme == .dark ? " · Dark" : " · Light"))
                        .font(theme.headingFont(.title, for: scheme)).foregroundStyle(palette.ink)
                    Text(palette.subtitle).font(.subheadline).foregroundStyle(palette.mutedInk)
                    CalendarHeader(month: date, previous: {}, next: {}, today: {})
                    HStack(spacing: 0) {
                        ForEach(0..<7) { index in
                            CalendarDayCell(date: date.addingTimeInterval(Double(index) * 86400),
                                            isToday: index == 2, isSelected: index == 3,
                                            isInDisplayedMonth: index != 6, hasEvent: index == 2 || index == 3,
                                            hasIncompleteTask: index == 3 || index == 4,
                                            projectColors: index == 3 ? [.blue, .orange] : [], select: {})
                        }
                    }.themedSurface(padding: 10)
                    PlannerSection(title: "今日やること", symbol: "checklist") {
                        HStack(spacing: 12) {
                            Image(systemName: "circle").font(.title3).foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("明日の打ち合わせを準備する").font(.body).foregroundStyle(palette.ink)
                                Text("仕事 · 15:00 · 優先度 高").font(.caption).foregroundStyle(palette.mutedInk)
                            }
                        }
                        Divider()
                        Text("ゆっくり、一つずつ進めましょう。").font(.subheadline).foregroundStyle(palette.mutedInk)
                    }
                    PlannerSection(title: "メモ", symbol: "pencil.line") {
                        Text("散歩の途中で見つけた、小さなアイデア。")
                            .font(.body).foregroundStyle(palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("今日に戻る") {}.buttonStyle(ThemedControlStyle())
                        Spacer()
                        Text("選択中").font(.subheadline.weight(.semibold)).padding(12)
                            .foregroundStyle(palette.selectionInk)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: palette.controlRadius))
                    }
                }
                .padding(20).frame(width: 390, height: 760, alignment: .top)
                .background { AppThemeBackground(theme: theme) }
                .environmentObject(settings)
                .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "ja_JP"))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
                attachment.name = "Theme-\(theme.id)-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

}
