import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    var body: some View {
        Form {
            Section("一般") { Text("基本設定") }
            Section("カレンダー") { Text("表示と連携") }
            Section("通知") { Text("通知設定（今後対応）") }
            Section("データ") { Text("保存と同期（今後対応）") }
            Section("外観") { Toggle("システム設定を使用", isOn: $viewModel.useSystemAppearance).onChange(of: viewModel.useSystemAppearance) { _ in viewModel.updateAppearance() } }
        }.navigationTitle("設定")
    }
}
