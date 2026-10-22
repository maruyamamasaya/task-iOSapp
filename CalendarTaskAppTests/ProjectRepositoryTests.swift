import XCTest
import SwiftData
@testable import CalendarTaskApp

@MainActor final class ProjectRepositoryTests: XCTestCase {
    func testProjectLifecycleAssignmentsAndSafeDeletion() async throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let projects = SwiftDataProjectRepository(container: persistence.container)
        let tasks = SwiftDataTaskRepository(container: persistence.container)
        let events = SwiftDataCalendarRepository(container: persistence.container)
        let now = Date.now
        var project = Project(id: UUID(), name: "仕事", colorIdentifier: .blue, iconName: "briefcase",
                              isArchived: false, createdAt: now, updatedAt: now)
        try await projects.addProject(project)
        var fetchedProjects = try await projects.fetchProjects()
        XCTAssertEqual(fetchedProjects.first?.name, "仕事")

        project.name = "業務"; project.colorIdentifier = .orange; project.updatedAt = now.addingTimeInterval(1)
        try await projects.updateProject(project)
        fetchedProjects = try await projects.fetchProjects()
        XCTAssertEqual(fetchedProjects.first?.colorIdentifier, .orange)
        try await projects.archiveProject(id: project.id, archived: true)
        fetchedProjects = try await projects.fetchProjects()
        XCTAssertTrue(try XCTUnwrap(fetchedProjects.first).isArchived)

        let task = TaskItem(id: UUID(), title: "定例準備", note: "", startDate: now, dueDate: now,
                            isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal,
                            reminderDate: nil, recurrenceRule: RecurrenceRule(frequency: .daily), projectID: project.id,
                            category: nil, tags: [], createdAt: now, updatedAt: now)
        let event = CalendarEvent(id: UUID(), title: "定例", note: "", startDate: now,
                                  endDate: now.addingTimeInterval(3600), isAllDay: false, reminderDate: nil,
                                  recurrenceRule: RecurrenceRule(frequency: .weekly), projectID: project.id,
                                  category: nil, externalEventID: nil, createdAt: now, updatedAt: now)
        try await tasks.addTask(task); try await events.addEvent(event)
        var fetchedTasks = try await tasks.fetchTasks()
        var fetchedEvents = try await events.fetchEvents()
        XCTAssertEqual(fetchedTasks.first?.projectID, project.id)
        XCTAssertEqual(fetchedEvents.first?.projectID, project.id)

        let next = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        XCTAssertTrue(RecurrenceCalculator().occurs(anchor: now, rule: task.recurrenceRule, on: next))
        XCTAssertEqual(task.projectID, project.id, "Occurrenceは系列元のProjectを参照する")

        try await projects.deleteProject(id: project.id)
        fetchedProjects = try await projects.fetchProjects()
        fetchedTasks = try await tasks.fetchTasks()
        fetchedEvents = try await events.fetchEvents()
        XCTAssertTrue(fetchedProjects.isEmpty)
        XCTAssertNil(fetchedTasks.first?.projectID)
        XCTAssertNil(fetchedEvents.first?.projectID)
    }

    func testTaskListTagFiltersSortingAndDayGroups() async throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let suite = "TaskListFilteringTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.completedTasksAtBottom = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 1)))
        let evening = morning.addingTimeInterval(20 * 3600)
        let nextDay = morning.addingTimeInterval(24 * 3600)
        let alpha = AppTag(id: UUID(), name: "A"), beta = AppTag(id: UUID(), name: "B")
        func task(_ name: String, due: Date?, start: Date? = nil, tags: [AppTag]) -> TaskItem {
            TaskItem(id: UUID(), title: name, note: "", startDate: start, dueDate: due, isAllDay: true,
                     isCompleted: false, completedAt: nil, priority: .normal, reminderDate: nil,
                     recurrenceRule: nil, projectID: nil, category: nil, tags: tags, createdAt: morning, updatedAt: morning)
        }
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [
            task("朝", due: morning, tags: [beta]), task("夜", due: evening, tags: [alpha]),
            task("翌日", due: nil, start: nextDay, tags: [alpha]), task("日付なし", due: nil, tags: [])
        ]))
        let model = TaskListViewModel(store: store,
            completionStore: TaskCompletionStore(repository: SwiftDataTaskCompletionRepository(container: persistence.container)),
            projectStore: ProjectStore(repository: SwiftDataProjectRepository(container: persistence.container)),
            settingsStore: settings, calendar: calendar)
        await model.load()
        model.selectedSection = .all
        XCTAssertEqual(model.dayGroups.map { $0.tasks.count }, [2, 1, 1])
        XCTAssertEqual(model.dayGroups.first?.date, calendar.startOfDay(for: morning))
        XCTAssertNil(model.dayGroups.last?.date)
        XCTAssertEqual(model.availableTags.map(\.name), ["A", "B"])
        model.tagFilter = .tag(alpha.id)
        XCTAssertEqual(Set(model.visibleTasks.map(\.title)), ["夜", "翌日"])
        model.searchText = "見つからない"
        XCTAssertTrue(model.visibleTasks.isEmpty)
        model.searchText = ""
        model.tagFilter = .untagged
        XCTAssertEqual(model.visibleTasks.map(\.title), ["日付なし"])
        model.tagFilter = .all
        model.sortOption = .tag
        XCTAssertEqual(model.visibleTasks.last?.title, "日付なし")
        XCTAssertEqual(model.visibleTasks.first?.tags.first?.name, "A")
        model.searchText = "B"
        XCTAssertEqual(model.visibleTasks.map(\.title), ["朝"])
    }

    func testTaskListProjectFilter() async {
        let persistence = SwiftDataPersistence(inMemory: true)
        let projectRepository = SwiftDataProjectRepository(container: persistence.container)
        let taskRepository = SwiftDataTaskRepository(container: persistence.container)
        let completionRepository = SwiftDataTaskCompletionRepository(container: persistence.container)
        let projectStore = ProjectStore(repository: projectRepository)
        let taskStore = TaskStore(repository: taskRepository)
        let completionStore = TaskCompletionStore(repository: completionRepository)
        let projectID = UUID(), now = Date.now
        await taskStore.add(TaskItem(id: UUID(), title: "仕事", note: "", startDate: now, dueDate: now,
                                     isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal,
                                     reminderDate: nil, recurrenceRule: nil, projectID: projectID, category: nil, tags: [], createdAt: now, updatedAt: now))
        await taskStore.add(TaskItem(id: UUID(), title: "個人", note: "", startDate: now, dueDate: now,
                                     isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal,
                                     reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: now, updatedAt: now))
        let viewModel = TaskListViewModel(store: taskStore, completionStore: completionStore, projectStore: projectStore)
        await viewModel.load(); viewModel.selectedSection = .today; viewModel.projectFilter = .project(projectID)
        XCTAssertEqual(viewModel.visibleTasks.map(\.title), ["仕事"])
    }

    func testTagLifecycleAndTaskAssignments() async throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let tags = SwiftDataTagRepository(container: persistence.container)
        let tasks = SwiftDataTaskRepository(container: persistence.container)
        var tag = AppTag(id: UUID(), name: "重要")
        try await tags.saveTag(tag)
        var fetchedTags = try await tags.fetchTags()
        XCTAssertEqual(fetchedTags, [tag])

        let now = Date.now
        let task = TaskItem(id: UUID(), title: "確認", note: "", startDate: now, dueDate: now,
                            isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal,
                            reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil,
                            tags: [tag], createdAt: now, updatedAt: now)
        try await tasks.addTask(task)
        var fetchedTasks = try await tasks.fetchTasks()
        XCTAssertEqual(fetchedTasks.first?.tags, [tag])

        tag.name = "最優先"
        try await tags.saveTag(tag)
        fetchedTasks = try await tasks.fetchTasks()
        XCTAssertEqual(fetchedTasks.first?.tags.first?.name, "最優先")
        try await tags.deleteTag(id: tag.id)
        fetchedTags = try await tags.fetchTags()
        fetchedTasks = try await tasks.fetchTasks()
        XCTAssertTrue(fetchedTags.isEmpty)
        XCTAssertTrue(fetchedTasks.first?.tags.isEmpty == true)
    }
}
