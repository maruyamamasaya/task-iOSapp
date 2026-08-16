import AppIntents
import WidgetKit

struct ToggleTaskCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "タスクの完了を切り替える"
    static let description = IntentDescription("今日のタスクを完了または未完了にします。")
    static var openAppWhenRun = false

    @Parameter(title: "タスクID") var taskID: String
    @Parameter(title: "Occurrence日") var occurrenceDate: Date

    init() {}
    init(taskID: UUID, occurrenceDate: Date) {
        self.taskID = taskID.uuidString; self.occurrenceDate = occurrenceDate
    }

    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            _ = await WidgetTaskActionService().toggle(taskID: id, occurrenceDate: occurrenceDate)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "CalendarTaskTodayWidget")
        return .result()
    }
}
