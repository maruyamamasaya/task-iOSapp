# Mac中継の常駐運用（有効化済み）

2026-10-21 JST。ユーザー承認後にLaunchAgentを配置・登録済み。異常終了後の自動再起動と同じLAN接続先への復旧を確認した。以下は現在の設定と停止・解除手順。再ログイン・長期稼働・スリープ復帰は未検証。

- Label: `local.CalendarTaskApp.DotLocalRelay`
- plist 保存先: `~/Library/LaunchAgents/local.CalendarTaskApp.DotLocalRelay.plist`（0600）
- 実行ファイル: 現在の Python の絶対パスと `~/Library/Application Support/CalendarTaskApp/DotLocalRelay/service/run_approved_relay.py --foreground`。同じ service フォルダに mac_bridge.py と canonical_tasks.py をコピー。日別生成文対応版ではdaily_brief.pyも必要で、依存ファイルをまとめて検証・配置する（0700ディレクトリ、0600ファイル）。リポジトリの移動や編集から実行環境を分離する。Python 更新で実行パスがなくなった場合は確認して設定を更新する。
- 既存の relay-config.json / auth / tls / state をそのまま使用。接続先は既存設定で承認された特定LAN IPv4・ポートのみ。新しい資格情報、証明書、信頼設定、ネットワーク設定は作らない。
- RunAtLoad=true、KeepAlive=true、ThrottleInterval=30秒、ProcessType=Background、umask=077。ユーザーのログイン中に起動し、終了すると再起動を試す。Mac起動直後の未ログイン中やスリープ中の稼働は保証しない。IP不在・別プロセスによるポート使用・設定異常でも安全に終了して30秒以上間隔で再試行し、別IPへは切り替えない。
- ログ: `~/Library/Application Support/CalendarTaskApp/DotLocalRelay/logs/lifecycle.log`、256KiB × 最大4ファイル（現行+3世代、計約1MiB）。開始・停止・シグナル番号・例外クラスのみ。タスク本文、ID、認証情報、HTTPヘッダーを記録しない。stdout/stderrは/dev/null。既存 traffic-metadata.json は固定件数の集計を上書きする別ファイル。SQLite inboxやタスク履歴にはログ上限を適用しない。
- 導入時は既存の前景プロセスだけを停止し、二重bindを避けてから `launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/local.CalendarTaskApp.DotLocalRelay.plist"`。先に設定案を `python3 prepare_launch_agent.py` で確認する。
- 状態確認: `launchctl print gui/$(id -u)/local.CalendarTaskApp.DotLocalRelay`
- 停止: `launchctl bootout gui/$(id -u)/local.CalendarTaskApp.DotLocalRelay`。KeepAliveがあるためkillだけでは停止しない。
- 再起動: `launchctl kickstart -k gui/$(id -u)/local.CalendarTaskApp.DotLocalRelay`
- 常駐解除: bootout後、上記のplistだけを削除。auth/tls/stateと端末のoutboxは残す。serviceとlogsの削除もデータ削除とは分けて判断する。
- 手動復旧: このリポジトリの `run_approved_relay.py --foreground` を実行。常駐と同時起動しない。CanonicalBridgeの認証済みHTTP受信はrevision一致時にローカル適用・読戻しまで実行する。

過去の停止原因: 既存プロセスはチャット側の前景セッションに属し、サービス管理対象ではなかった。以前の終了時刻・exit code・signal記録はなく、対応するPythonクラッシュレポートも見つからない。セッション終了やシグナルが原因という仮説はあるが断定不可。今回のログで今後の通常停止・例外終了を識別できる。SIGKILL・OS停止は最後の停止ログが残らず、常駐有効化後はlaunchctlのexit statusも併用する。

有効化済み: ユーザーが2026-10-21に設定案を承認。上記保存先に配置しbootstrapした。別チャットで追加されたCanonicalBridgeの依存canonical_tasks.pyも配布に含む。正本state/tasks.jsonを読み書きする構成を保持し、後続ユーザー指示により認証済み操作の自動適用へ更新した。
