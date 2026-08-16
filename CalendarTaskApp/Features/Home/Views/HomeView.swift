import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel
    @State private var editorRoute: EditorRoute?
    @State private var showsQuickAdd = false
    @State private var pendingQuickAddDraft: QuickAddResult?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                DailyHeader(date: viewModel.selectedDate, isToday: viewModel.isToday,
                            previous: { Task { await viewModel.moveDay(by: -1) } },
                            next: { Task { await viewModel.moveDay(by: 1) } },
                            returnToToday: { Task { await viewModel.returnToToday() } })
                Button { showsQuickAdd = true } label: {
                    Label("予定やタスクを追加...", systemImage: "plus")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Divider() }
                }.buttonStyle(.plain)
                AllDaySection(events: viewModel.allDayEvents, tasks: viewModel.allDayTasks,
                              editEvent: { editorRoute = .event(viewModel.sourceEvent(for: $0)) }, editTask: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                              toggleTask: { task in Task { await viewModel.toggleCompletion(task) } }, taskActions: taskActions, eventActions: eventActions)
                DailyTimelineView(items: viewModel.timelineItems, showsNow: viewModel.isToday, now: viewModel.now,
                                  editEvent: { editorRoute = .event(viewModel.sourceEvent(for: $0)) }, editTask: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                                  toggleTask: { task in Task { await viewModel.toggleCompletion(task) } }, taskActions: taskActions, eventActions: eventActions)
                UnscheduledTasksSection(tasks: viewModel.unscheduledTasks,
                                        edit: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                                        toggle: { task in Task { await viewModel.toggleCompletion(task) } }, actions: taskActions)
                DailyNoteSection(text: viewModel.memoText) {
                    editorRoute = .note(viewModel.note(for: viewModel.selectedDate), viewModel.selectedDate)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
        }
        .navigationTitle("今日").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AddItemMenu(date: viewModel.selectedDate, route: $editorRoute) } }
        .sheet(item: $editorRoute) { route in
            EditorHostView(route: route, noteForDate: viewModel.note,
                           saveTask: viewModel.saveTask, deleteTask: viewModel.deleteTask,
                           saveEvent: viewModel.saveEvent, deleteEvent: viewModel.deleteEvent,
                           saveNote: viewModel.saveNote, deleteNote: viewModel.deleteNote)
        }
        .sheet(isPresented: $showsQuickAdd, onDismiss: openPendingDraft) {
            QuickAddView(defaultDate: viewModel.selectedDate, add: viewModel.saveQuickAdd) { result in
                pendingQuickAddDraft = result
            }
        }
        .task { await viewModel.load() }
    }
    private func openPendingDraft() {
        guard let draft = pendingQuickAddDraft else { return }
        pendingQuickAddDraft = nil
        Task { @MainActor in editorRoute = .quickAddDraft(draft) }
    }
    private var taskActions: TaskRowActions {
        TaskRowActions(edit: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                       toggle: { task in Task { await viewModel.toggleCompletion(task) } },
                       moveToday: { task in Task { await viewModel.moveTaskToToday(task) } },
                       moveTomorrow: { task in Task { await viewModel.moveTaskToTomorrow(task) } },
                       reschedule: { task, date in Task { await viewModel.rescheduleTask(task, to: date) } },
                       duplicate: { task in Task { await viewModel.duplicateTask(task) } },
                       delete: { task in Task { await viewModel.deleteTask(id: task.id) } })
    }
    private var eventActions: EventRowActions {
        EventRowActions(edit: { editorRoute = .event(viewModel.sourceEvent(for: $0)) },
                        reschedule: { event, date in Task { await viewModel.rescheduleEvent(event, to: date) } },
                        duplicate: { event in Task { await viewModel.duplicateEvent(event) } },
                        delete: { event in Task { await viewModel.deleteEvent(id: event.id) } })
    }
}
