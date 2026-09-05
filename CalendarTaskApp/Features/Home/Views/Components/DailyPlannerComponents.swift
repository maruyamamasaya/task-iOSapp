import SwiftUI

struct DailyHeader: View {
    @EnvironmentObject private var settings: SettingsStore
    let date: Date
    let isToday: Bool
    let previous: () -> Void
    let next: () -> Void
    let returnToToday: () -> Void

    var body: some View {
        HStack {
            Button(action: previous) { Image(systemName: "chevron.left") }.accessibilityLabel("前日")
            Spacer()
            Button(action: returnToToday) {
                VStack(spacing: 4) {
                    Text(date.formatted(.dateTime.month(.wide).day()))
                        .font(settings.theme.headingFont(.largeTitle))
                    Text(date.formatted(.dateTime.weekday(.wide))).font(.subheadline).foregroundStyle(.secondary)
                    if !isToday { Text("今日に戻る").font(.caption2).foregroundStyle(.tint) }
                }
            }.buttonStyle(ThemedPressStyle())
            Spacer()
            Button(action: next) { Image(systemName: "chevron.right") }.accessibilityLabel("翌日")
        }.buttonStyle(ThemedControlStyle()).font(.headline).padding(.vertical, 12)
    }
}

struct AllDaySection: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    let editEvent: (CalendarEvent) -> Void
    let editTask: (TaskItem) -> Void
    let toggleTask: (TaskItem) -> Void
    let taskActions: TaskRowActions
    let eventActions: EventRowActions

    var body: some View {
        PlannerSection(title: "終日", symbol: "sun.max") {
            if events.isEmpty && tasks.isEmpty { PlannerEmptyText(text: "終日の項目はありません") }
            ForEach(events) { event in
                Button { editEvent(event) } label: { HStack {
                    if let project = projectStore.project(id: event.projectID) { Circle().fill(project.colorIdentifier.color).frame(width: 6, height: 6) }
                    Label(event.title, systemImage: "calendar")
                    if event.recurrenceRule != nil { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(ThemedPressStyle())
                    .modifier(EventQuickActionsModifier(event: event, edit: { eventActions.edit(event) }, reschedule: { eventActions.reschedule(event, $0) }, duplicate: { eventActions.duplicate(event) }, delete: { eventActions.delete(event) }))
            }
            ForEach(tasks) { task in TaskPlannerRow(task: task, edit: { editTask(task) }, toggle: { toggleTask(task) }, actions: taskActions) }
        }
    }
}

struct DailyTimelineView: View {
    let items: [DailyTimelineItem]
    let showsNow: Bool
    let now: Date
    let editEvent: (CalendarEvent) -> Void
    let editTask: (TaskItem) -> Void
    let toggleTask: (TaskItem) -> Void
    let taskActions: TaskRowActions
    let eventActions: EventRowActions

    var body: some View {
        PlannerSection(title: "1日の流れ", symbol: "clock") {
            if items.isEmpty { PlannerEmptyText(text: "時間の決まった項目はありません") }
            if showsNow, shouldShowNowBeforeFirst { CurrentTimeRow(now: now) }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                TimelineItemRow(item: item, editEvent: editEvent, editTask: editTask, toggleTask: toggleTask, taskActions: taskActions, eventActions: eventActions)
                if showsNow && shouldShowNow(after: index) { CurrentTimeRow(now: now) }
            }
            if showsNow && items.isEmpty { CurrentTimeRow(now: now) }
        }
    }
    private var shouldShowNowBeforeFirst: Bool { guard let first = items.first else { return false }; return now < first.date }
    private func shouldShowNow(after index: Int) -> Bool {
        guard !shouldShowNowBeforeFirst, now >= items[index].date else { return false }
        return index == items.count - 1 || now < items[index + 1].date
    }
}

struct TimelineItemRow: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let item: DailyTimelineItem
    let editEvent: (CalendarEvent) -> Void
    let editTask: (TaskItem) -> Void
    let toggleTask: (TaskItem) -> Void
    let taskActions: TaskRowActions
    let eventActions: EventRowActions

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(item.date.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            VStack(spacing: 0) { Circle().fill(projectColor).frame(width: 5, height: 5); Rectangle().fill(projectColor.opacity(0.35)).frame(width: 1).frame(maxHeight: .infinity) }.frame(width: 18)
            switch item.source {
            case let .event(event):
                Button { editEvent(event) } label: { itemText(symbol: "calendar") }.buttonStyle(ThemedPressStyle())
                    .modifier(EventQuickActionsModifier(event: event, edit: { eventActions.edit(event) }, reschedule: { eventActions.reschedule(event, $0) }, duplicate: { eventActions.duplicate(event) }, delete: { eventActions.delete(event) }))
            case let .task(task):
                HStack(alignment: .top, spacing: 9) {
                    Button { toggleTask(task) } label: { Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44) }.buttonStyle(ThemedPressStyle())
                    Button { editTask(task) } label: { itemText(symbol: nil) }.buttonStyle(ThemedPressStyle())
                }
                .modifier(TaskQuickActionsModifier(task: task, usesCustomSwipe: true, edit: { taskActions.edit(task) }, toggle: { taskActions.toggle(task) }, moveToday: { taskActions.moveToday(task) }, moveTomorrow: { taskActions.moveTomorrow(task) }, reschedule: { taskActions.reschedule(task, $0) }, duplicate: { taskActions.duplicate(task) }, assignProject: { _ in }, delete: { taskActions.delete(task) }))
            }
        }.frame(minHeight: 52, alignment: .top)
    }
    private func itemText(symbol: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
                if isRecurring { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
                if let name = projectName { Text(name).font(.caption2).foregroundStyle(.secondary) }
                if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var isRecurring: Bool { switch item.source { case let .task(value): value.recurrenceRule != nil; case let .event(value): value.recurrenceRule != nil } }
    private var projectID: UUID? { switch item.source { case let .task(value): value.projectID; case let .event(value): value.projectID } }
    private var projectName: String? { projectStore.project(id: projectID)?.name }
    private var projectColor: Color { projectStore.project(id: projectID)?.colorIdentifier.color ?? .secondary }
}

private struct CurrentTimeRow: View {
    let now: Date
    var body: some View {
        HStack(spacing: 8) {
            Text(now.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
            Rectangle().fill(Color.accentColor.opacity(0.5)).frame(height: 1)
            Text("現在").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct UnscheduledTasksSection: View {
    let tasks: [TaskItem]
    let edit: (TaskItem) -> Void
    let toggle: (TaskItem) -> Void
    let actions: TaskRowActions
    var body: some View {
        PlannerSection(title: "今日やること", symbol: "checklist") {
            if tasks.isEmpty { PlannerEmptyText(text: "時刻未指定のタスクはありません") }
            ForEach(tasks) { task in TaskPlannerRow(task: task, edit: { edit(task) }, toggle: { toggle(task) }, actions: actions) }
        }
    }
}

private struct TaskPlannerRow: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let task: TaskItem; let edit: () -> Void; let toggle: () -> Void; let actions: TaskRowActions
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: toggle) { Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44) }.buttonStyle(ThemedPressStyle())
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        if let project = projectStore.project(id: task.projectID) { Circle().fill(project.colorIdentifier.color).frame(width: 6, height: 6) }
                        Text(task.title).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? .secondary : .primary)
                    }
                    if task.recurrenceRule != nil { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
                    if let project = projectStore.project(id: task.projectID) { Text(project.name).font(.caption2).foregroundStyle(.secondary) }
                    if !task.note.isEmpty { Text(task.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(ThemedPressStyle())
        }
        .modifier(TaskQuickActionsModifier(task: task, usesCustomSwipe: true, edit: { actions.edit(task) }, toggle: { actions.toggle(task) }, moveToday: { actions.moveToday(task) }, moveTomorrow: { actions.moveTomorrow(task) }, reschedule: { actions.reschedule(task, $0) }, duplicate: { actions.duplicate(task) }, assignProject: { _ in }, delete: { actions.delete(task) }))
    }
}

struct DailyNoteSection: View {
    let text: String; let edit: () -> Void
    var body: some View {
        PlannerSection(title: "メモ", symbol: "pencil.line") {
            Button(action: edit) {
                Text(text.isEmpty ? "メモを書く" : text).font(.subheadline)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary).lineLimit(5)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            }.buttonStyle(ThemedPressStyle())
        }
    }
}

struct PlannerSection<Content: View>: View {
    @EnvironmentObject private var settings: SettingsStore
    let title: String; let symbol: String; @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: settings.theme.contentSpacing) {
            Label(title, systemImage: symbol).font(settings.theme.headingFont(.headline)).foregroundStyle(.primary)
            Rectangle().fill(Color.accentColor.opacity(0.16)).frame(height: 1)
            content
        }
        .themedSurface()
    }
}

private struct PlannerEmptyText: View {
    let text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 5) }
}
