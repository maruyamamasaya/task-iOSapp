import SwiftUI

struct CalendarView: View {
    @StateObject var viewModel: CalendarViewModel
    @State private var editorRoute: EditorRoute?
    @State private var showsQuickAdd = false
    @State private var pendingQuickAddDraft: QuickAddResult?
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CalendarHeader(displayMode: $viewModel.displayMode,
                               previous: { Task { await move(by: -1) } },
                               next: { Task { await move(by: 1) } },
                               today: { Task { await viewModel.returnToToday() } })
                if viewModel.displayMode == .month {
                    MonthCalendarView(dates: viewModel.monthDates, weekdaySymbols: viewModel.weekdaySymbols,
                                      isToday: viewModel.isToday, isSelected: viewModel.isSelected,
                                      isInDisplayedMonth: viewModel.isInDisplayedMonth,
                                      hasEvent: viewModel.hasEvents, hasIncompleteTask: viewModel.hasIncompleteTasks,
                                      projectIDs: viewModel.projectIDs) { date in
                        Task {
                            await viewModel.select(date)
                        }
                    }
                        .themedSurface(padding: 14)
                    SelectedDaySummaryView(date: viewModel.selectedDate, events: viewModel.selectedEvents,
                                           tasks: viewModel.selectedTasks, note: viewModel.selectedNote,
                                           editEvent: eventActions.edit, editTask: taskActions.edit,
                                           editNote: { editorRoute = .note(viewModel.selectedNote, viewModel.selectedDate) })
                        .themedSurface()
                } else if viewModel.displayMode == .week {
                    WeekCalendarView(dates: viewModel.weekDates,
                                     events: viewModel.events, tasks: viewModel.tasks, timelineItems: viewModel.timelineItems,
                                     isToday: viewModel.isToday, isSelected: viewModel.isSelected,
                                     hasEvent: viewModel.hasEvents, hasTask: viewModel.hasIncompleteTasks,
                                     projectIDs: viewModel.projectIDs, select: { date in
                                         Task {
                                             await viewModel.select(date)
                                             viewModel.displayMode = .day
                                         }
                                     },
                                     taskActions: taskActions, eventActions: eventActions)
                } else {
                    DayCalendarView(date: viewModel.selectedDate,
                                    allDayEvents: viewModel.selectedAllDayEvents, allDayTasks: viewModel.selectedAllDayTasks,
                                    timelineItems: viewModel.selectedTimelineItems, unscheduledTasks: viewModel.selectedUnscheduledTasks,
                                    note: viewModel.selectedNote, now: viewModel.now, isToday: viewModel.isToday(viewModel.selectedDate),
                                    editNote: { editorRoute = .note(viewModel.selectedNote, viewModel.selectedDate) },
                                    taskActions: taskActions, eventActions: eventActions)
                        .contentShape(Rectangle())
                        .simultaneousGesture(daySwipeGesture)
                }
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .padding(.bottom, 80)
        }
        .themedScreen()
        .navigationTitle(headerTitle).navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            Button { showsQuickAdd = true } label: {
                Image(systemName: "bolt.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.tint, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("すばやく書く")
            .padding(.trailing, 20)
            .padding(.bottom, 16)
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
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) >= 60, abs(horizontal) > abs(vertical) * 1.5 else { return }
                Task { await viewModel.moveDay(by: horizontal < 0 ? 1 : -1) }
            }
    }
    private var headerTitle: String {
        switch viewModel.displayMode {
        case .month:
            viewModel.displayedMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP")))
        case .week: viewModel.weekTitle
        case .day: viewModel.dayTitle
        }
    }
    private func move(by value: Int) async {
        switch viewModel.displayMode {
        case .month: await viewModel.moveMonth(by: value)
        case .week: await viewModel.moveWeek(by: value)
        case .day: await viewModel.moveDay(by: value)
        }
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
