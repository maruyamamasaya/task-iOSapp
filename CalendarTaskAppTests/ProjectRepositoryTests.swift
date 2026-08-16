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
}
