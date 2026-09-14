import Foundation

protocol ProjectRepository: Sendable {
    func fetchProjects() async throws -> [Project]
    func addProject(_ project: Project) async throws
    func updateProject(_ project: Project) async throws
    func archiveProject(id: UUID, archived: Bool) async throws
    func deleteProject(id: UUID) async throws
}

protocol TagRepository: Sendable {
    func fetchTags() async throws -> [AppTag]
    func saveTag(_ tag: AppTag) async throws
    func deleteTag(id: UUID) async throws
}
