# CalendarTaskApp アーキテクチャ

## 1. 設計の目的

予定、タスク、日別メモというドメインを UI や保存技術から分離し、永続化・同期・OS framework・Widget を追加または交換しても Feature 層の変更を小さくする。README は利用者向け概要、ルートの `AGENTS.md` は日常の変更規約、本書は依存関係と現状実装の記録を担う。

## 2. レイヤーと依存方向

```text
View
  ↓ user action / observed screen state
ViewModel
  ↓ use-case operation / shared state
Store
  ↓ domain persistence contract
Repository protocol (Core)
  ↓ implemented by
Repository / Data Source (Data)
```

逆方向の依存は作らない。具体的には、Core は Features / Data / SwiftUI / SwiftData に依存せず、Feature は SwiftData Entity や `ModelContext` を知らない。Data は Core の protocol と domain model を実装・変換する。

### View

SwiftUI による描画、入力、sheet / navigation、操作の ViewModel への転送を担当する。Home と Calendar は `EditorRoute` / `EditorHostView` でタスク・予定・メモのフォームを統一し、`QuickAddView` から直接保存または編集 draft に遷移する。Tasks はタスク一覧とタスク編集、Settings は設定およびプロジェクト・バックアップ管理を提供する。

### ViewModel

`@MainActor` の画面状態を持ち、Store の共有状態を画面用に絞り込み・並べ替える。Home は選択日のタイムラインとメモ、Calendar は月・週・日表示、Tasks はセクション・検索・ソートを調停する。ViewModel は具体 Repository を知らず、保存結果や haptic など画面ユースケースをまとめる。

### Store

Repository をラップする共有 application state。ロードと CRUD 後の状態再取得に加え、Task / Calendar / TaskCompletion の更新時には通知と Widget refresh を調停する。`SettingsStore` は例外的に `UserDefaults` を直接境界として設定値を保持する。Store に画面レイアウトや特定画面だけの選択状態を入れない。

### Repository と Data Source

`Core/Repositories` の protocol は domain model の非同期 CRUD 契約である。`Data/Repositories/SwiftDataRepositories.swift` は domain と SwiftData Entity を変換し、`Data/Local/SwiftDataPersistence.swift` が schema と container / store URL を管理する。InMemory Repository は隔離された unit test や fixture 用であり、本番 DI では使われていない。

## 3. 現在の構成

`AppDependencies.live()` が次を一度だけ組み立て、`AppRootView` が各 ViewModel に必要な Store / Service を渡す。

- SwiftData: Task、CalendarEvent、DailyNote、TaskCompletion、Project、Tag の各 Repository。
- Store: Task、Calendar、DailyNote、TaskCompletion、Project、Settings。
- Service: system date、UserNotifications、haptic、Widget refresh、backup。
- Root UI: Tasks、Calendar、WBS、Gantt、Settings の五つの Tab と各 `NavigationStack`。Today (Home) はTasks右上から開く。WBS／ガントはプロジェクト選択画面を入口とし、選択したプロジェクトのFeature内の画面ローカルdraftによるプレビューを開く。Repository／保存schemaには接続しない。

主要な書き込みは `View → ViewModel → Store → Repository` と進み、Repository が SwiftData を保存する。Store は成功後に通知を同期し、該当する操作では `WidgetCenter` の timeline reload を要求してから状態を再取得する。

## 4. モデルと永続化

- `TaskItem`: 日付、完了、優先度、通知、繰り返し、Project、category / tags を持つタスク。
- `CalendarEvent`: 開始・終了、終日、通知、繰り返し、Project、category、外部 event ID を持つ予定。
- `DailyNote`: 一日単位の本文。
- `TaskCompletion`: 繰り返しタスクの occurrence 単位の完了記録。
- `Project`: 色・icon と archive 状態を持つ分類。

予定・既存の日別メモ等の本番永続化はSwiftData。Dotタスクは後述のMac正本・端末独立JSONキャッシュで保持し、SwiftDataへ複製しない。Settings は UserDefaults、バックアップは SwiftData domain data の JSON export / import を扱う。タグ一覧は `TagEntity`、タスクへの割り当ては `TaskEntity.tagsData` に保存する。SwiftData Entity には現時点で Task の category、CalendarEvent の category / externalEventID が保存されず、domain への復元時に空値になる。これらを永続化する変更は schema・移行・バックアップ・テストを伴う独立タスクとして扱う。

## 5. Widget / App Intent の共有

アプリと Widget は同じ `APP_GROUP_IDENTIFIER` を Info.plist から `SwiftDataPersistence` に渡し、利用可能なら App Group container 内の `CalendarTaskApp.store` を開く設計である。既存の標準 store がある場合は初回に関連ファイルを共有先へコピーする。現在は両targetのentitlementがAPP_GROUP_IDENTIFIERを参照する。既存署名で実機の共有ファイル読戻しまで確認済み。別環境での配布時は両targetのcapability/provisioningを揃える。

WidgetのWidgetDataProviderはSwiftDataから予定を読み、Dotの未完了タスクはApp Groupの表示専用キャッシュから生成する。対話的ボタンは `ToggleTaskCompletionIntent` から `WidgetTaskActionService` を呼び、通常タスクの完了状態または繰り返し occurrence の `TaskCompletion` を更新する。アプリ側 Store の書き込みは `WidgetRefreshService` を経由して timeline を更新する。共有 schema、App Group entitlement、target membership は一体として扱う。

## 6. 将来の adapter

- **CloudKit 等の同期**: Repository の裏側に remote/local coordination を実装する。競合解決や同期状態は Data に閉じ、必要な表示状態だけ Store 経由で公開する。
- **EventKit**: Core に用途を絞った service / repository protocol、Data に EventKit adapter と domain 変換を置く。Feature に `EKEvent` を渡さず、`externalEventID` を対応付けに使う。
- **UserNotifications**: 現在と同様に `NotificationService` 経由とし、Store が domain 更新との同期点を担う。
- **Widget / App Intents**: domain / persistence 契約を共有しつつ独立 target を保つ。AppIntent から Feature ViewModel を呼ばず、用途を限定した service を使う。
- **SwiftData schema 拡張**: domain model、Entity、mapping、migration、backup、Widget をまとめて設計し、Repository protocol が不要に保存技術へ寄らないようにする。

この境界を守れば、Composition Root と Data 実装を中心に変更し、Feature の表示・操作ロジックを維持できる。


## 7. Dotタスク: Mac正本・端末キャッシュ・表示投影

Mac正本は専用領域 `DotLocalRelay/state/tasks.json`。`Integrations/DotLocalBridge/canonical_tasks.py` のCanonicalBridgeが検証、ロック、revision付き更新、SQLiteへの投影を担当する。SQLiteは配信用投影と永続受信箱で、正本破損時に正本をDBから上書きしない。正本保存後の投影失敗は次回読取りで回復し、iPhone操作適用中の失敗は次回取得または同じoperation IDの再送で回復する。

App targetのみがローカルSwift Package `DotLocalBridge` を参照する。AppDependenciesはDotRelayTaskCacheを通じ同じLocalBridgeStoreを画面間で共有する。Keychainの接続情報がある場合にTLSピニング・端末別認証付きtransportを注入し、ない場合は未接続となる。秘密値はソース・表示用データ・バックアップへ含めない。

通常の完了操作はView→ViewModel→TaskStore→DotRelayTaskRepository→LocalBridgeStoreを通す。outboxをatomic保存してから表示と自動送信へ進む。Mac受信と正本適用は別段階で、認証済み操作はrevision一致時に受信箱commit後、正本保存・読戻し・DB/確認応答までCanonicalBridgeが自動実行する。保存失敗はreceivedを保持し、取得・再送時に同じIDで回復する。同じoperation IDで再送し、検証済みapplied応答でのみoutboxを解消する。未送信であることを記録した新操作だけは取消時にoutboxから取り下げられる。送信開始前にsending/neverSubmitted=falseを永続化し、以降は元ID/payloadを保持してnextCompletedに最新希望を保存する。適用ack後に新ID/ackのrevisionで後続操作を作る。旧ファイルのneverSubmitted欠落は送信不確実として扱い、取り下げない。最新希望はUI/Widget投影で優先する。明示applyは復旧用に残す。

AppRootViewのscenePhaseと前景15秒周期が送受信・表示Store再読込みを調停する。バックグラウンドやスリープ中の稼働は保証しない。Mac常駐は承認済みLaunchAgentが同じ接続設定で管理し、service配布の3モジュールを利用する。変更時はリポジトリ編集だけでは稼働コードへ反映されない。

### 表示と保存境界

- Home/Calendar: plannerTaskStore→DotPlannerTaskRepositoryがJSON取込みと中継だけをTaskItemへ投影。同じslugは中継を優先。outboxの希望完了値を優先し、SwiftDataへ挿入しない。中継の名前・日付編集は未対応。
- タスクタブ: AppRootView→DotPlannerListView→TaskListViewModel→plannerTaskStoreで今日/カレンダーと同じ投影を表示する。JSON取込み専用のDotTaskListView→DotTaskStoreはその他メニューへ残す。
- JSON取込み: CoreのDotTaskSource/DotTaskCache/DotTaskFileImportingをDataが実装。5MiB上限、形式・重複ID・日付を検証してatomic保存し、slugごとのUUIDを保持する。sourceはdot-local-json-v1、accountはon-device、保存先はDotTasks/local-v1.json。欠落行は削除しない。Mac正本の更新経路にはしない。
- iPhone中継: Application SupportのDotLocalRelay/paired/<bridgeID>/state-v1.jsonへキャッシュ・outbox・履歴を保存。未接続領域はunpairedで分離。
- 既存taskStoreとSwiftData: 既存の保存・通知・バックアップ・メンテナンス用として維持。App Group、署名、保存schemaは本連携で変更していない。
- Widget: plannerTaskStoreの投影をDotWidgetTaskCacheが既存App GroupのDotTasks/widget-v1.jsonへatomic保存し、今日/月のWidgetへreload要求する。キャッシュはUUID・名前・日付・終日・有効完了値だけを持つ表示用データで、資格情報やoutbox正本ではない。WidgetDataProviderはこれを読み、Dot行のtaskIDをnilにして旧SwiftData Intentへの誤更新を防ぐ。アプリ内読戻し一致と本人の表示報告を確認。描画時刻・実際の日跨ぎやスリープ条件は別の未確認事項として扱う。
- バックアップ: 既存SwiftDataの全置換バックアップにDotキャッシュ/outbox・Mac正本/受信箱は含まれない。

Supabaseを使用しない。現在地と検証証跡は [dot-task-integration.md](dot-task-integration.md)、CLIと復旧は [CANONICAL-SOURCE.md](../Integrations/DotLocalBridge/CANONICAL-SOURCE.md) を参照する。

共有LocalBridgeStoreは保存成功後の変更をAsyncStreamで通知し、Composition Rootのcache observerがplannerTaskStore/taskStoreを再読込みする。plannerの公開後に既存App Groupのatomic表示snapshotを保存してWidget reloadするため、Macのackや15秒周期を待たず端末内の希望値を共有する。TaskStoreは古い非同期loadの結果で新しい表示を巻き戻さない。Widget snapshotに任意のcalendarDateを追加し、終日の暦日をタイムゾーン変更後も維持する（旧v1は従来のDateで読込み）。Widgetは予定開始/終了・翌日開始・次々日開始のentryを最大64件まで事前作成し、上限時も暦日境界を残す。実描画時刻はWidgetKit管理。今日を追従中だけ前景の日跨ぎ/時刻変更で日付を進め、手動で選んだ別日は維持する。

### Dot分類・リマインダーの投影（2026-10-22）

Mac正本レコードの任意項目project（UUID/name）・tags（UUID/name配列）・reminderAt（オフセット付きISO 8601秒精度）をWireTaskが保持する。旧キャッシュは項目欠落を未設定として読み込む。DotRelayTaskRepositoryが既存TaskItemへ投影し、Mac所有の分類はProject/Tag Repository adapterで端末内一覧と合わせる。分類とタスクをSwiftDataへコピーせず、標準バックアップの対象も増やさない。同じIDの名前不一致・端末内分類とのID衝突は拒否する。AppDependenciesはキャッシュ変更後のStore再読込と、直列化したDot通知同期を組み立てる。通知の予約・取消は既存NotificationServiceへ委譲する。Macには通知予約成功の応答を返していない。入力契約と前景同期の制約はIntegrations/DotLocalBridge/DOT-TASK-FORMAT.mdに記載。

Dotの追加任意項目aiContextと分単位日程はWireTask/独立JSONキャッシュ内に保持し、native SwiftData schemaには追加しない。投影ではAI補足を除外し、時刻付き作業は指定zoneの開始日時、固定期限は別の表示情報として扱う。通知reminderAtと完了outboxの契約は維持する。詳細仕様はdocs/dot-task-integration.mdへ集約する。

週間一覧の大分類/状態/期限は、AppDependenciesがrelay/JSONから表示用PlannerTaskMetadataを作りTaskListViewModelへsource closureで注入する。TaskItemやSwiftData schemaへ追加せず、更新は従来Store経路を維持する。

### Dotの日別生成文

「今日」の生成文は `HomeView → DailyBriefStore → DailyBriefRepository → DotDailyBriefRepository` で取得し、`AppDependencies` で注入する。既存DailyNote/SwiftDataのschemaとは分離する。HomeViewModelが表示日の日別予定・完了表示設定に依存しないタスク状態から生成材料を組み立て、日付・timezone・整列済み入力のSHA256を識別子とする。Data adapterが既存のKeychain pairing/TLSピニング付きHTTPSへ材料を送信し、生成文をMac別・日別の端末ファイルにキャッシュする。保存・通信はView内で行わない。

Macは認証済み`/v1/daily-brief`で材料をmetadataへ保存し、生成文を返す。生成自体は本人がDotチャットで依頼したときだけ行い、MacのCLIが材料識別子一致を条件に保存・読戻しする。タスク正本・投影・受信箱の書換え経路へは入れない。生成後の入力変更は古さとして表示し、日付変更や遅延応答で別日の文章を表示しない。運用と未導入時の扱いは[DAILY-BRIEF.md](../Integrations/DotLocalBridge/DAILY-BRIEF.md)。
