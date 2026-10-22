# Widget signing setup

In Xcode, enable **App Groups** for both `CalendarTaskApp` and `CalendarTaskWidget` and select the value of the shared `APP_GROUP_IDENTIFIER` build setting. The checked-in entitlements reference that build setting rather than duplicating the identifier in source code. A paid Apple Developer team/provisioning profile is required for device distribution.

Widgets read Dot tasks from the display-only `DotTasks/widget-v1.json` projection in the App Group. The app refreshes it after loading its Dot planner list and requests updates for both widget kinds. Open the app once after updating to populate it. Missing or unreadable projections show no tasks; native SwiftData tasks are never a fallback. Events continue to use the existing shared SwiftData store. Dot rows open the app rather than invoking the native completion intent.

更新: 端末での完了/取消・Mac確認応答を保存後、共有snapshotへ最新希望を反映してreloadを要求する。終日項目はcalendarDateで暦日を維持し、予定境界と翌日/次々日のsnapshotをtimelineへ事前登録する。最大64entryでも日付境界を保持。WidgetからDotの直接完了書込みは行わず、タップ先のアプリで操作する。WidgetKitが実描画時刻を管理するため、アプリの保存直後の描画を確約しない。
