import SwiftUI

struct CalendarView: View {
    @StateObject var viewModel: CalendarViewModel
    @State private var editorRoute: EditorRoute?
    @State private var showsQuickAdd = false
    @State private var pendingQuickAddDraft: QuickAddResult?
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Picker("表示", selection: $viewModel.displayMode) {
                    ForEach(CalendarDisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 220)
                CalendarHeader(month: viewModel.displayedMonth, title: viewModel.displayMode == .week ? viewModel.weekTitle : nil,
                               previous: { Task { if viewModel.displayMode == .month { await viewModel.moveMonth(by: -1) } else { await viewModel.moveWeek(by: -1) } } },
                               next: { Task { if viewModel.displayMode == .month { await viewModel.moveMonth(by: 1) } else { await viewModel.moveWeek(by: 1) } } },
                               today: { Task { await viewModel.returnToToday() } })
                if viewModel.displayMode == .month {
                    MonthCalendarView(dates: viewModel.monthDates, weekdaySymbols: viewModel.weekdaySymbols,
                                      isToday: viewModel.isToday, isSelected: viewModel.isSelected,
                                      isInDisplayedMonth: viewModel.isInDisplayedMonth,
                                      hasEvent: viewModel.hasEvents, hasIncompleteTask: viewModel.hasIncompleteTasks,
                                      projectIDs: viewModel.projectIDs) { date in Task { await viewModel.select(date) } }
                        .themedSurface(padding: 14)
                    SelectedDaySummaryView(date: viewModel.selectedDate, events: viewModel.selectedEvents,
                                           tasks: viewModel.selectedTasks, note: viewModel.selectedNote,
                                           editEvent: eventActions.edit, editTask: taskActions.edit,
                                           editNote: { editorRoute = .note(viewModel.selectedNote, viewModel.selectedDate) })
                        .themedSurface()
                } else {
                    WeekCalendarView(dates: viewModel.weekDates, selectedDate: viewModel.selectedDate,
                                     allDayEvents: viewModel.selectedAllDayEvents, allDayTasks: viewModel.selectedAllDayTasks,
                                     timelineItems: viewModel.selectedTimelineItems, unscheduledTasks: viewModel.selectedUnscheduledTasks, now: viewModel.now,
                                     isToday: viewModel.isToday, isSelected: viewModel.isSelected, hasEvent: viewModel.hasEvents, hasTask: viewModel.hasIncompleteTasks,
                                     projectIDs: viewModel.projectIDs, select: { date in Task { await viewModel.select(date) } },
                                     taskActions: taskActions, eventActions: eventActions)
                }
            }.padding(.horizontal, 20).padding(.vertical, 16)
        }
        .themedScreen()
        .navigationTitle("カレンダー").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showsQuickAdd = true } label: { Image(systemName: "bolt") }.accessibilityLabel("クイック追加")
                AddItemMenu(date: viewModel.selectedDate, route: $editorRoute)
            }
        }
        .sheet(item: $editorRoute) { route in
            EditorHostView(route: route, noteForDate: viewModel.note,
                           saveTask: viewModel.saveTask, deleteTask: viewModel.deleteTask,
                           saveEvent: viewModel.saveEvent, deleteEvent: viewModel.deleteEvent,
                           saveNote: viewModel.saveNote, deleteNote: viewModel.deleteNote)
        }
        .sheet(isPresented: $showsQuickAdd, onDismiss: openPendingDraft) {
            QuickAddView(defaultDate: viewModel.selectedDate, add: viewModel.saveQuickAdd) { pendingQuickAddDraft = $0 }
        }
        .task { await viewModel.load() }
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
    private func openPendingDraft() {
        guard let draft = pendingQuickAddDraft else { return }
        pendingQuickAddDraft = nil
        Task { @MainActor in editorRoute = .quickAddDraft(draft) }
    }
}
