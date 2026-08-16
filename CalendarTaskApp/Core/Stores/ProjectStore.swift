import Foundation
import Combine

@MainActor final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var errorMessage: String?
    private let repository: any ProjectRepository
    init(repository: any ProjectRepository) { self.repository = repository }
    var activeProjects: [Project] { projects.filter { !$0.isArchived }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    func project(id: UUID?) -> Project? { guard let id else { return nil }; return projects.first { $0.id == id } }
    func load() async { do { projects = try await repository.fetchProjects(); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    func save(_ project: Project) async {
        do {
            if projects.contains(where: { $0.id == project.id }) { try await repository.updateProject(project) }
            else { try await repository.addProject(project) }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
    func setArchived(_ archived: Bool, id: UUID) async { do { try await repository.archiveProject(id: id, archived: archived); await load() } catch { errorMessage = error.localizedDescription } }
    func delete(id: UUID) async { do { try await repository.deleteProject(id: id); await load() } catch { errorMessage = error.localizedDescription } }
}
