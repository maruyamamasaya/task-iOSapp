import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var briefStore: DailyBriefStore
    @StateObject var viewModel: HomeViewModel
    @State private var dayBoundaryToken = UUID()
    @State private var editorRoute: EditorRoute?
    @State private var showsDotTaskGuidance = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                DailyHeader(date: viewModel.selectedDate, isToday: viewModel.isToday,
                            previous: { Task { await viewModel.moveDay(by: -1) } },
                            next: { Task { await viewModel.moveDay(by: 1) } },
                            returnToToday: { Task { await viewModel.returnToToday() } })
                DailyBriefSection(brief: briefStore.brief, isOutdated: briefStore.isOutdated,
                                  errorMessage: briefStore.errorMessage)
                HStack {
                    Label("予定 \(viewModel.dayEvents.count)件", systemImage: "calendar")
                    Spacer()
                    Label("残り \(viewModel.dayTasks.filter { !$0.isCompleted }.count)件", systemImage: "checkmark.circle")
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                }
                UnscheduledTasksSection(tasks: viewModel.pendingUnscheduledTasks,
                                        edit: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                                        toggle: { task in Task { await viewModel.toggleCompletion(task) } }, actions: taskActions,
                                        add: { showsDotTaskGuidance = true })
                if !viewModel.allDayEvents.isEmpty {
                AllDaySection(events: viewModel.allDayEvents, tasks: [],
                              editEvent: { editorRoute = .event(viewModel.sourceEvent(for: $0)) }, editTask: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                              toggleTask: { task in Task { await viewModel.toggleCompletion(task) } }, taskActions: taskActions, eventActions: eventActions)
                }
                DailyTimelineView(items: viewModel.timelineItems, showsNow: viewModel.isToday, now: viewModel.now,
                                  editEvent: { editorRoute = .event(viewModel.sourceEvent(for: $0)) }, editTask: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                                  toggleTask: { task in Task { await viewModel.toggleCompletion(task) } }, taskActions: taskActions, eventActions: eventActions,
                                  add: { editorRoute = .new(.event, viewModel.selectedDate) })
                CompletedDayTasksSection(tasks: viewModel.completedDayTasks,
                                         edit: { editorRoute = .task(viewModel.sourceTask(for: $0)) },
                                         toggle: { task in Task { await viewModel.toggleCompletion(task) } },
                                         actions: taskActions)
                    .id(Calendar.current.startOfDay(for: viewModel.selectedDate))
            }
            .environment(\.unifiedPlannerPage, true)
            .themedSurface()
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            if let task = viewModel.completionUndoTask {
                HStack(spacing: 12) {
                    Text(PlannerTaskPresentation(task: task).title)
                        .font(.caption).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("完了を取り消す") { Task { await viewModel.undoLastCompletion(taskID: task.id) } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(viewModel.isUndoingCompletion)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .alert("やることはDotで追加", isPresented: $showsDotTaskGuidance) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("Dotのチャットで、やることと日付を伝えてください。このアプリでは、取り込んだタスクの確認と完了ができます。")
        }
        .themedScreen()
        .navigationTitle("今日").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AddItemMenu(date: viewModel.selectedDate, route: $editorRoute) } }
        .sheet(item: $editorRoute) { route in
            EditorHostView(route: route, noteForDate: viewModel.note,
                           saveTask: viewModel.saveTask, deleteTask: viewModel.deleteTask,
                           saveEvent: viewModel.saveEvent, deleteEvent: viewModel.deleteEvent,
                           saveNote: viewModel.saveNote, deleteNote: viewModel.deleteNote)
        }
        .task { await viewModel.load() }
        .task(id: BriefRefreshID(context: viewModel.dailyBriefContext.id, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await briefStore.refresh(viewModel.dailyBriefContext)
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
        .task(id: dayBoundaryToken) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await viewModel.refreshDayBoundary()
                let now = Date.now
                guard let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) else { break }
                do { try await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(now)))) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, _ in dayBoundaryToken = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            dayBoundaryToken = UUID()
        }
    }
    private struct BriefRefreshID: Equatable {
        let context: String
        let active: Bool
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
