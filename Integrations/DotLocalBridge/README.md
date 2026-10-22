# DotLocalBridge

Mac正本とiPhoneを同じLANで結ぶPython中継とSwift Package。Supabase・外部公開・VPNは使用しない。

現在の運用・残課題の入口は [Dot連携の現在地](../../docs/dot-task-integration.md)。このモジュールはアプリに組込み済みで、承認済み端末の認証付きTLS、実機での双方向往復、Mac常駐の異常終了後再起動を検証済み。

## 構成

- `canonical_tasks.py`: Mac正本の読取り・追加・revision付き更新、配信用SQLite投影、明示applyのCLI。
- `mac_bridge.py`: SQLiteの永続受信箱、同じoperation IDの再送、競合検出、明示適用・確認応答、認証付きHTTP/TLSサーバー。
- `run_approved_relay.py`: 固定LAN接続先と既存資格情報を検証し、CanonicalBridgeで起動する。上限付きライフサイクルログ。
- `Sources/DotLocalBridge`: 端末内atomicキャッシュ/outbox、TLSピニング、非同期送受信とパネル。資格情報はKeychainへ保持。
- `prepare_launch_agent.py`: 承認済み常駐設定の生成。停止・再配置手順は下記の運用文書を参照。

本番CanonicalBridgeは認証済み操作を受信箱へ永続保存し、revision一致時に正本保存・読戻しまで自動実行して200/appliedを返す。保存失敗はreceivedを保持して503、競合は上書きしない。次回取得・同一ID再送で中断操作を回復する。明示applyは復旧用に残す。独立した基底Bridgeの合成試験は従来の202/receivedも検証する。応答のtargetはdot_local_fileであり、WebやDot会話の更新を意味しない。

## 手順と検証

- [現在仕様・共通手順](../../docs/dot-task-integration.md)
- [入力契約](DOT-TASK-FORMAT.md)
- [正本CLI・競合・復旧](CANONICAL-SOURCE.md)
- [常駐の停止・解除](SERVICE-PROPOSAL.md)
- [Dotのひとこと](DAILY-BRIEF.md)
- [最終検証と公開範囲](../../docs/validation-status.md)

合成Pythonテストはこのディレクトリで `python3 -m unittest -q`、Swift Packageは `swift test --package-path Integrations/DotLocalBridge`。実タスク・認証情報をfixtureへ転記しない。XcodeテストはAGENTS.mdの既存Simulator/並列無効/容量保全手順を守る。公開リポジトリのcommit/pushはサービス再配置や実機更新ではない。
